# ADR-001 — Moteurs d'inférence et portabilité

Date : 2026-07-03 · Statut : accepté · Contexte complet : `notes/research/*.md`

## Contexte

1. Recherche ASR : le meilleur modèle basque (`xezpeleta/whisper-large-v3-eu`, Apache 2.0, WER 4,84 vs 38,85 pour Whisper vanille) est **déjà publié au format GGML** (`ggml-large-v3.eu.bin`) prêt pour whisper.cpp. Sa conversion CoreML (voie WhisperKit) est le risque technique n°1 identifié.
2. Les fine-tunes monolingues détruisent les autres langues (WER anglais 21→147 documenté) → **2 modèles + routing manuel** : eu fine-tuné + `large-v3-turbo` pour le français.
3. **Exigence Vincent (12:31) : compatibilité Windows.** + Phase 2 = site web d'upload/transcription.

## Décision

**Cœur 100% portable (C/C++), coquilles natives par plateforme.**

| Composant | Choix | Portabilité |
|---|---|---|
| ASR | **whisper.cpp v1.9.x** (XCFramework sur Mac, Metal) | Mac / Windows / Linux / serveur web |
| Modèles ASR | `ggml-large-v3.eu.bin` (xezpeleta) + `ggml-large-v3-turbo` | fichiers identiques partout |
| Correction LLM | **llama.cpp** + Latxa GGUF 4B (Apache 2.0) + BYOK Anthropic | identique partout |
| Décodage audio | Couche plateforme : CoreAudio/AVAudioFile sur Mac (opus vérifié), ffmpeg côté serveur web, libopus/ffmpeg sur Windows | interface commune |
| Shell V1 | SwiftUI natif macOS 26 (KeyboardShortcuts 3.x, CGEventTap pour hold-Fn, NSPanel `.glassEffect()` HUD, GRDB FTS5) | Mac uniquement, par design |

**Roadmap plateformes** : V1 app Mac native → Phase 2 site web (les utilisateurs Windows sont servis en ligne, mêmes moteurs/modèles côté serveur) → Phase 3 app Windows native réutilisant moteurs + modèles + prompts + logique produit.

## Rejetés

- **WhisperKit** (CoreML) : conversion du fine-tune basque = risque majeur ; lock-in Apple incompatible avec l'exigence Windows. Regret accepté : pas d'ANE (Metal suffit sur M4).
- **MLX Swift** pour Latxa : Apple-only → llama.cpp à la place (GGUF Latxa disponibles).
- **Framework UI cross-platform** (Tauri/Electron/Flutter) : tuerait l'exigence « UX premium niveau Wispr Flow » ; le cross-platform passe par le cœur portable, pas par l'UI.
- **SwiftData** : pas de FTS5 → GRDB.
- **Parakeet TDT eu via sherpa-onnx** (WER 6,92, ~10× plus rapide) : conservé en **plan B latence dictée** si large-v3-eu dépasse le budget < 5 s.
- **SpeechAnalyzer Apple** : pas de modèles custom → pas de basque.

## Conséquences

- Un seul écosystème de modèles téléchargés (GGML/GGUF) pour Mac, web, Windows — le ModelManager et les prompts de correction sont réutilisables tels quels en phase 2/3.
- Les apps GPL du même créneau (VoiceInk) et sans licence (Speak2) ne doivent **jamais** être copiées (Mintzo = MIT) — patterns publics uniquement.
- Distribution : Developer ID + notarization (hors App Store).
