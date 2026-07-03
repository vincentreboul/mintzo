# Recherche — Correction post-ASR basque/français par LLM local (Mintzo)

Date : 2026-07-03 · Cible : macOS app SwiftUI, M4 32 Go, 100 % local (cloud BYOK en secours)
Méthode : IDs de modèles vérifiés par fetch réel de l'API Hugging Face (`huggingface.co/api/models`) le 2026-07-03. Tout chiffre non vérifiable est marqué.

---

## TL;DR — Recommandation

| Rôle | Choix | Pourquoi |
|---|---|---|
| **Modèle correction basque (défaut)** | `HiTZ/Latxa-Qwen3-VL-4B-Instruct` (révision `mono_eu`), Apache 2.0 — GGUF communautaire dispo | 4B = seul gabarit qui tient le budget ~3-5 s sur M4 base ; licence propre pour distribution |
| **Modèle qualité max (option "précision")** | `HiTZ/Latxa-Llama-3.1-8B-Instruct` (licence Llama-Latxa 3.1 Community) | Meilleur basque open vérifié (EusProficiency 52.8, bat Llama-3.1-Instruct largement) ; ~10-13 s / 100 mots sur M4 base → à réserver au mode "corriger en arrière-plan" ou aux Mac M4 Pro/Max |
| **Runtime Swift** | **MLX Swift** (`ml-explore/mlx-swift-lm`, MLXLLM) | Officiel Apple, actif (push 2026-06-30, 704★), archi `Llama.swift` + `Qwen3.swift` + `Qwen35.swift` supportées, 20-87 % plus rapide que llama.cpp <14B |
| **Conversion** | `mlx_lm.convert --hf-path HiTZ/… -q` (aucune conversion MLX Latxa n'existe encore — vérifié : 0 résultat) | Archi Llama/Qwen3 = conversion standard, effort ~1 h + hébergement des poids |
| **Français** | Le même modèle Latxa gère le français correctement (base Llama 3.1 / Qwen multilingue) ; sinon même prompt sur le modèle choisi | Pas besoin d'un 2e modèle |
| **Cloud BYOK** | `claude-opus-4-8` (qualité) ou `claude-sonnet-4-6` (défaut coût/qualité) | ~0,5-0,8 centime / dictée de 100 mots ; frontière = référence qualité basque dans l'arène HiTZ |

---

## 1. Latxa en 2026 — état des lieux (org HiTZ, tout vérifié via API HF)

### Familles disponibles

| Modèle | Base | Date maj | Licence | Instruct |
|---|---|---|---|---|
| `HiTZ/latxa-7b/13b/70b-v1…v1.2` | Llama 2 | 2024 | Llama 2 | ❌ (base only, obsolète) |
| `HiTZ/Latxa-Llama-3.1-8B-Instruct` | Llama-3.1-8B-Instruct | 2025-12-15 | **« LLAMA-LATXA 3.1 COMMUNITY LICENSE »** (dérivé Llama 3.1 Community — mention "Built with Llama", clause 700M MAU ; OK pour une app distribuée avec attribution) | ✅ |
| `HiTZ/Latxa-Llama-3.1-70B-Instruct` (+`-FP8`, +`-v2`, +`-v2-FP8`) | Llama-3.1-70B-Instruct | 2025-2026 | idem | ✅ (hors budget RAM 32 Go en q4 ≈ 40 Go) |
| `HiTZ/Latxa-Qwen3-VL-2B/4B/8B/32B-Instruct` | Qwen3-VL-Instruct | fin 2025 | **Apache 2.0** | ✅ multimodal ; révisions `multi` (eu+gl+ca) et **`mono_eu`** (basque seul). ⚠️ carte modèle : « still under development / preliminary » |
| `HiTZ/Latxa-Qwen3.5-2B` / `-4B` | Qwen/Qwen3.5-2B/-4B | **2026-06-24** | **Apache 2.0** | conversational (pipeline image-text-to-text) ; corpus latxa-corpus-v2 ; très récent, peu de retours |

- Paper instruct : « Instructing Large Language Models for Low-Resource Languages: A Systematic Study for Basque » (arXiv:2506.07597, v3 mars 2026). Corpus 4,2 Md tokens eu ; préférences humaines de 1 680 participants. Conclusion clé : partir d'un backbone **déjà instruct** > base ; le 70B « comes near frontier models of much larger sizes for Basque ». Code : github.com/hitz-zentroa/latxa-instruct.
- Scores carte modèle 8B-Instruct (5-shot) : EusProficiency **52.83**, EusReading 59.66, EusTrivia 61.05, EusExams 56.0, Belebele 80.

### GGUF / MLX existants

- **GGUF 8B-Instruct** : `mradermacher/Latxa-Llama-3.1-8B-Instruct-GGUF` (Q4_K_M/Q4_K_S/IQ4_XS/Q5/Q8 — vérifié fichier par fichier) ; aussi `MaziyarPanahi/Latxa-Llama-3.1-8B-Instruct-GGUF`.
- **GGUF Qwen3-VL** : `itzune/Latxa-Qwen3-VL-2B/4B/8B-GGUF` + `mradermacher/Latxa-Qwen3-VL-*-Instruct-GGUF`.
- **GGUF Latxa-Qwen3.5** : NON CONFIRMÉ (rien trouvé au 2026-07-03).
- **MLX : AUCUNE conversion Latxa publiée** (recherche `mlx-community` + `latxa mlx` = vide, vérifié). Effort de conversion : standard — archi `llama` (et `qwen3`/`qwen3_5` texte) supportées par `mlx_lm.convert … -q` (4-bit). ~1 h de travail + publier les poids (HF privé ou CDN app).

## 2. Runtime LLM en Swift

| Option | État (vérifié GitHub API 2026-07-03) | Verdict |
|---|---|---|
| **MLX Swift** — `ml-explore/mlx-swift-lm` (MLXLLM/MLXLMCommon/MLXVLM, ex mlx-swift-examples) | 704★, dernier push **2026-06-30**, officiel Apple/ml-explore. Archis incluses : `Llama.swift`, `Qwen3.swift`, `Qwen35.swift`, `Gemma3Text.swift`, `Gemma4.swift`… (liste des fichiers vérifiée). Charge tout modèle HF converti via `mlx_lm.convert` ; exemples LLMEval/MLXChatExample téléchargent depuis le Hub | **RECOMMANDÉ** : API Swift propre, Apple-first, benchs 2026 : MLX 20-87 % plus rapide que llama.cpp <14B sur Apple Silicon |
| `tattn/LocalLLMClient` | 220★, push 2026-04-29, backend llama.cpp **et** MLX, « experimental, API subject to change » | Bon plan B unique si on veut charger directement les GGUF mradermacher sans conversion |
| `LLM.swift` (eastriverlee), `Kuzco` | Lookup GitHub API en échec (404/renommage ?) — **maturité NON CONFIRMÉE**, à revérifier avant d'en dépendre | Ne pas parier dessus |
| llama.cpp SPM direct | `Package.swift` non trouvé à la racine du repo ggml-org (lookup API nul) ; wrappers tiers fragmentés (swift-llama-cpp, llmfarm_core) | Viable mais bricolage ; réserver au fallback |

**Reco** : MLXLLM en runtime principal (poids MLX 4-bit convertis nous-mêmes). Garder l'ID GGUF mradermacher en secours (test rapide via Ollama/LM Studio pendant le dev).

## 3. Mémoire & latence sur M4 32 Go

- **RAM** : 8B Q4_K_M ≈ 4,6 Go de poids, ~5,5-6 Go résidents avec KV cache court. 4B ≈ 2,4 Go. 2B ≈ 1,3 Go. Aucun souci sur 32 Go, même avec Whisper chargé.
- **Débit** : llmcheck.net (index 2026) annonce « Llama 3.1 8B Q4 : 75 tok/s sur M4 16 Go » — **⚠️ chiffre auto-estimé par leur méthodo et physiquement impossible** : M4 base = 120 Go/s de bande passante ; 8B q4 (4,6 Go lus/token) ⇒ plafond théorique ≈ **26 tok/s**, réaliste **~18-23 tok/s**. Pour un 4B : plafond ~48, réaliste **~35-42 tok/s** ; 2B : **~70-85 tok/s**. (Sur M4 Pro 273 Go/s : ×2,3.)
- **Dictée 100 mots** ≈ 220-250 tokens de sortie en basque (≈2,2-2,5 tok/mot, tokenizer non adapté à l'euskara) :
  - 8B q4 : **~10-13 s** → dépasse le budget 3-4 s sur M4 base ❌
  - 4B q4 : **~5-7 s** → borderline ; OK si on streame le texte corrigé au fil de l'eau ✅~
  - 2B q4 : **~3 s** ✅
- **Conclusion** : viser **Latxa-Qwen3-VL-4B `mono_eu`** (ou Latxa-Qwen3.5-4B quand mûr) avec affichage en streaming + correction par phrase ; proposer le 8B en option « qualité » asynchrone. Prefill (prompt) négligeable (<0,5 s).

## 4. Alternatives si Latxa impraticable

Contexte évals : IberBench (arXiv:2504.16921) et La Leaderboard (arXiv:2507.00999) montrent que **le basque est la langue la plus difficile** du panel ; **Latxa-7B est 1er en raisonnement basque**, `BSC-LT/salamandra-7b-instruct` (Apache 2.0, 36 langues dont eu — vérifié) 2e en QA basque. Repères :

1. **Salamandra-7b-instruct** (BSC) — meilleur fallback non-Latxa pour l'euskara, Apache 2.0. Même problème de débit qu'un 7-8B.
2. **EuroLLM-9B-Instruct-2512** (utter-project, maj 2026-02, Apache 2.0 — vérifié) — bon multilingue UE, basque couvert mais non spécialisé ; 9B = trop lent sur M4 base.
3. Gemma 3 4B / Qwen 3-3.5 4B génériques — rapides mais basque nettement plus faible que Latxa (les évals Iberian placent les modèles génériques derrière les spécialisés en eu). À réserver au **français**.
4. Étude utile : « Evaluating Compact LLMs for Zero-Shot Iberian Language Tasks on End-User Devices » (arXiv:2504.03312) ; multimodal basque : arXiv:2511.09396.

## 5. Cloud BYOK (Anthropic) — secours

- Qualité euskara : dans l'arène humaine du paper Latxa-Instruct, les modèles frontière (Claude Sonnet, GPT-4o) sont la référence haute que Latxa-70B « approche » — Claude est donc un excellent correcteur basque. Pas de benchmark euskara public dédié aux Claude 2026 trouvé (NON CONFIRMÉ au-delà de l'arène HiTZ).
- **Modèles 2026** (réf. interne claude-api, prix /MTok) : `claude-opus-4-8` $5/$25 (reco qualité) ; `claude-sonnet-4-6` $3/$15 (reco défaut) ; `claude-haiku-4-5` $1/$5 (éco, basque plus risqué).
- **Coût 1000 mots basques** (~2 500 tok in + 2 500 tok out) : Opus 4.8 ≈ **$0.075** ; Sonnet 4.6 ≈ **$0.045** ; Haiku ≈ $0.015. Une dictée de 100 mots ≈ 0,5-0,8 ¢. Négligeable.
- ⚠️ API 2026 : `temperature`/`top_p` **supprimés** (400) sur Opus 4.7+/Sonnet 5 — le déterminisme se contraint par prompt + **structured outputs** (`output_config.format` json_schema `{corrected_text: string}`), ce qui élimine aussi le bavardage.

## 6. Prompt de correction — état de l'art anti-hallucination

Littérature : la correction générative post-ASR souffre de **sur-correction et d'hallucination d'entités** (ex. documenté : « I like algorithms » → « I like Al Gore ») ; parades = détection avant correction, contraintes strictes, vérification (framework 3 étapes RLLM-CF, arXiv:2505.24347 ; survey arXiv:2508.07285 ; Task-Activating Prompting, Chen et al. 2024).

**Prompt de base recommandé (système)** — même gabarit eu/fr, un appel par langue détectée :

```text
Zuzentzaile automatiko bat zara. Hizketa-transkripzio bat jasoko duzu euskaraz.
Zuzendu SOILIK: puntuazioa, maiuskulak, ASR akats nabariak (gaizki ezagututako
hitzak, deklinabide okerrak). EZ berridatzi, EZ laburtu, EZ gehitu ezer.
Zalantzarik baduzu, utzi bere horretan. Itzuli testu zuzendua BAKARRIK.
```

Réglages : température 0 / greedy (local), pas de sampling créatif ; `max_tokens ≈ 2×` l'entrée ; correction **phrase par phrase** pour les longues dictées.
**Garde-fous applicatifs** (obligatoires) : (1) ratio de longueur sortie/entrée hors [0,75 ; 1,35] → rejeter et garder l'original ; (2) similarité (Levenshtein mots) < ~0,6 → rejeter ; (3) ne jamais corriger les noms propres absents phonétiquement ; (4) UI diff avant remplacement.

## Sources principales (fetchées)

huggingface.co/api/models?author=HiTZ · huggingface.co/HiTZ/Latxa-Llama-3.1-8B-Instruct (+LICENSE) · huggingface.co/HiTZ/Latxa-Qwen3-VL-4B-Instruct · huggingface.co/HiTZ/Latxa-Qwen3.5-4B · huggingface.co/mradermacher/Latxa-Llama-3.1-8B-Instruct-GGUF · arxiv.org/abs/2506.07597 · github.com/ml-explore/mlx-swift-lm · github.com/tattn/LocalLLMClient · llmcheck.net/benchmarks (+ /models/llama-31-8b-on-m4/) · arxiv 2505.24347, 2508.07285, 2504.16921, 2507.00999, 2504.03312
