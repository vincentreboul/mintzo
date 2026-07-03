# ADR-002 — Version web (phase 2, lancée en session le 2026-07-03)

Décision Vincent 15:06 : transcription web **côté serveur GPU serverless** — même qualité que l'app Mac (large-v3-eu + Latxa), coût à l'usage, audio supprimé après traitement (affiché honnêtement : la promesse « ne quitte jamais » reste exclusive à l'app).

## Architecture

```
web/
├── server/    FastAPI (Python) — moteur portable ADR-001 : whisper.cpp + llama.cpp,
│              MÊMES fichiers modèles que l'app (GGML/GGUF, téléchargés au boot, volume cache)
│              POST /v1/transcribe (multipart: file ≤ 50 Mo, language eu|fr, correct bool)
│              → { text, rawText, language, durationSeconds, timings }
│              GET /v1/health → { status, models }
│              CORS ouvert au domaine du front. Décodage : ffmpeg (opus WhatsApp inclus).
│              Testable en local CPU/Metal AUJOURD'HUI (mêmes modèles que l'app sur le M4).
│              modal_app.py = wrapper Modal GPU (T4/A10G, scale-to-zero) + Dockerfile générique
│              (portable : Modal, Fly GPU, VPS). Déploiement = runbook Vincent (compte Modal).
└── app/       SvelteKit statique (Cloudflare Pages) — landing + outil + confidentialité,
               trilingue eu (défaut) / fr / en, design-language.md appliqué au web,
               historique local navigateur (IndexedDB), VITE_API_URL configurable.
```

## Rejetés
- WASM navigateur : qualité basque dégradée (modèle réduit) — contraire au critère n°1. Réévaluable plus tard en mode « offline web » complémentaire.
- Middle-server applicatif : le front statique parle directement à l'endpoint GPU (moins d'ops, moins de latence).
- Comptes utilisateurs, stockage serveur des audios/textes : hors scope — rien n'est conservé côté serveur.

## Conséquences
- Le serveur réutilise ModelCatalog/prompts/garde-fous conceptuels de l'app (portés en Python — source de vérité : les fichiers Swift).
- mintzo.eus (PuntuEUS) à enregistrer par Vincent avant mise en ligne.
- Coût estimé début : 0-30 €/mois (crédits Modal + scale-to-zero) ; à revoir si adoption.
