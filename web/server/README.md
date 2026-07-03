# Mintzo — serveur de transcription web

FastAPI portable (ADR-002) réutilisant les moteurs et les modèles de l'app Mac
(ADR-001) : binaires **whisper.cpp** (`whisper-cli`, greedy) + **llama.cpp**
(`llama-server` résident pour la correction Latxa), mêmes fichiers GGML/GGUF,
prompt et garde-fous **portés verbatim du Swift** (`Sources/MintzoCore` =
source de vérité). Rien n'est conservé côté serveur : l'audio reçu vit dans un
tmpdir supprimé en `finally`.

## API

| Route | Contrat |
|---|---|
| `POST /v1/transcribe` | multipart : `file` (≤ 50 Mo ; .opus .m4a .mp3 .wav .aac .ogg .flac), `language` (`eu`\|`fr`), `correct` (bool, défaut false) → `200 {text, rawText, language, durationSeconds, timings:{asr, correction}}` |
| `GET /v1/health` | `{status: ok\|degraded, models: {eu, fr, latxa}}` |

Erreurs : toujours `{error, message}` — `413 file_too_large`,
`415 unsupported_format` / `undecodable_audio`, `422 invalid_params`,
`500 pipeline_error`. Si la correction échoue ou est rejetée par les
garde-fous, `text == rawText` (le brut n'est jamais perdu).

## Dev local (macOS, M4)

Prérequis : `brew install ffmpeg whisper-cpp llama.cpp uv`. Les modèles sont
lus depuis `~/Library/Application Support/Mintzo/Models` (ceux de l'app Mac,
réutilisés tels quels) ; s'ils manquent, ils sont téléchargés au boot et
vérifiés (sha256).

```bash
cd web/server
uv sync                                  # venv + deps
uv run uvicorn app.main:app --port 8787  # boot: vérif modèles + llama-server résident
```

Test manuel :

```bash
curl -sS http://127.0.0.1:8787/v1/health
curl -sS -X POST http://127.0.0.1:8787/v1/transcribe \
  -F "file=@note-vocale.opus" -F "language=eu" -F "correct=true"
```

Repères M4 (échantillon basque 5,8 s, serveur chaud) : ASR ≈ 2,7 s,
correction ≈ 0,6 s.

### Tests

```bash
uv run pytest                 # unitaires + API stubée (les tests @real se skippent seuls)
MINTZO_REAL_AUDIO=/chemin/vers/phrase-basque.wav uv run pytest -m real   # intégration réelle
```

### Variables d'environnement

| Var | Défaut | Rôle |
|---|---|---|
| `MODELS_DIR` | `~/Library/Application Support/Mintzo/Models` (mac) / `~/.cache/mintzo/models` | dossier des modèles |
| `CORS_ORIGINS` | `*` | origines autorisées, séparées par virgules |
| `MAX_UPLOAD_BYTES` | `52428800` | plafond upload (50 Mo) |
| `LLAMA_PORT` / `LLAMA_CTX` | `8089` / `4096` | llama-server interne |
| `LLAMA_AUTOSTART` | `1` | `0` = pas de correction (fallback brut) |
| `WHISPER_CLI` / `LLAMA_SERVER` / `FFMPEG` | noms des binaires | chemins des exécutables |
| `ASR_TIMEOUT_S` / `CORRECTION_TIMEOUT_S` | `900` / `180` | timeouts subprocess |
| `MINTZO_SKIP_ENSURE` | `0` | `1` = ne pas télécharger/vérifier les modèles au boot |

## Déploiement Modal (runbook ~5 min)

`modal_app.py` (GPU T4, scale-to-zero, volume modèles) est **écrit mais pas
encore déployé** — chaque appel a été vérifié contre docs.modal.com le
2026-07-03, il manque juste un compte. Pas-à-pas :

1. Compte : https://modal.com (login GitHub, crédits gratuits inclus).
2. CLI + auth :
   ```bash
   cd web/server
   uv tool install modal    # ou: pip install modal
   modal setup              # ouvre le navigateur, colle le token
   ```
3. Déploiement :
   ```bash
   modal deploy modal_app.py
   ```
   L'image CUDA se construit dans leur cloud (whisper.cpp + llama.cpp,
   ~10-15 min la première fois), puis la commande imprime l'URL, de la forme
   `https://<workspace>--mintzo-transcribe-web.modal.run`.
4. Premier boot : ouvrir `https://<URL>/v1/health` — le conteneur télécharge
   les ~7 Go de modèles dans le volume `mintzo-models` (une seule fois,
   quelques minutes), démarre llama-server, puis répond `{"status":"ok",...}`.
   Les boots suivants (cold start) prennent ~30-60 s ; conteneur chaud ≈
   latence locale.
5. Brancher le front : coller l'URL dans `VITE_API_URL` de `web/app`, et
   restreindre `CORS_ORIGINS` au domaine du front (éditer `.env({...})` dans
   `modal_app.py`, redéployer).

Coût : T4 facturée à la seconde d'activité, scale-to-zero au bout de 5 min
d'inactivité (`scaledown_window=300`) — estimation ADR-002 : 0-30 €/mois au
début.

### Alternative générique (Fly GPU, VPS CUDA)

Le `Dockerfile` est autonome (multi-stage, non testé localement — pas de CUDA
sur Apple Silicon) :

```bash
docker build -t mintzo-server .
docker run --gpus all -p 8000:8000 -v mintzo-models:/models mintzo-server
```

## Architecture

```
app/
├── config.py         env → réglages (lus à l'appel, testables)
├── models.py         catalogue GGML/GGUF (URLs + sha256 = ModelCatalog/LatxaCatalog.swift),
│                     download au boot + vérif sha256 + marqueurs
├── prompts.py        prompt système eu/fr + plafond tokens (CorrectionPrompt.swift)
├── guardrails.py     sanitize + evaluate : ratio 0.7–1.5, similarité mots ≥ 0.6,
│                     préfixes méta, fallback raisonné (CorrectionGuardrails.swift)
├── llama_runtime.py  llama-server résident (spawn, health-poll, chat greedy temp 0)
├── pipeline.py       decode ffmpeg 16k mono → whisper-cli greedy → correction gardée
└── main.py           FastAPI : /v1/transcribe, /v1/health, erreurs typées, CORS
```

Pourquoi `llama-server` résident et pas `llama-cli` par requête : llama-cli ≥
b9860 est conversation-only (bannière sur stdout, non parsable) et recharger
2,5 Go par requête coûte des secondes ; résident, la correction tombe à ~0,6 s
et le JSON est fiable. `whisper-cli` reste un subprocess par requête (modèle
par langue, chargement ~2 s inclus dans le timing ASR).
