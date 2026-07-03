# Mintzo V1 — Spécification

Statut : draft validé scope (Vincent, 2026-07-03 12:11). Choix moteurs finalisés post-recherche dans `docs/specs/adr-001-moteurs.md`.

## Vision

Dictée et transcription vocale de niveau Wispr Flow / SuperWhisper, conçue **euskara-first** avec support français de première classe, **100% locale** sur Apple Silicon. Open source (MIT). Objectif : devenir l'outil de référence de la communauté bascophone sur Mac — « ton euskara ne quitte jamais ton Mac ».

## Scope V1

### Flow A — Dictée système (le cœur)
1. Hotkey global (configurable, défaut à définir ; modes toggle ET hold-to-talk).
2. HUD flottant discret pendant l'enregistrement (waveform, langue active, état).
3. Relâche/stop → transcription locale (basque ou français, auto-détection + override manuel).
4. Passe de correction (ponctuation, majuscules, orthographe) — locale (Latxa) ou cloud BYOK, désactivable.
5. Le texte final : inséré au curseur de l'app active (simulation Cmd+V) + presse-papier + historique. Clipboard précédent restauré.

### Flow B — Fichiers audio
- Drag-drop / bouton d'import sur la fenêtre principale ET sur l'icône menu bar.
- Formats : `.opus` (vocaux WhatsApp — décodés nativement par CoreAudio, vérifié empiriquement 2026-07-03), `.m4a`, `.mp3`, `.wav`, `.aac`, `.ogg`, `.flac`.
- File d'attente visible, transcription + correction, résultat dans l'historique + bouton copier.

### Flow C — Historique
- Liste chronologique : texte, date, durée audio, langue détectée, source (dictée/fichier), version brute vs corrigée.
- Recherche plein texte. Copier en 1 clic. Suppression unitaire + tout effacer. Stockage local (SwiftData).

### Onboarding
Première ouverture : 3 écrans max — (1) micro + accessibilité avec explication honnête, (2) téléchargement du modèle basque (taille annoncée, barre de progression, le modèle FR/multilingue selon ADR), (3) essai de dictée guidé. Correction Latxa = téléchargement optionnel différé (proposé, jamais imposé).

## Non-goals V1
- Site web (phase 2), Windows/Linux, iOS.
  - **Contrainte actée pour la phase 2 (Vincent, 2026-07-03)** : le site web devra aussi accepter et décoder les vocaux WhatsApp `.opus`. Faisable sans dépendre de CoreAudio : décodage côté serveur (ffmpeg/libopus) ou côté navigateur (Web Audio API / WebCodecs — support Safari à valider à ce moment-là). À intégrer dès la conception de l'API d'upload.
- Diarization multi-locuteurs, traduction, résumé, export sous-titres.
- Multi-user, comptes, télémétrie (AUCUNE télémétrie — argument privacy).
- App Store (distribution DMG GitHub + Homebrew en phase lancement).

## Architecture (modules)

```
MintzoApp (SwiftUI, macOS 26+, Apple Silicon only)
├── CaptureService      AVAudioEngine → buffers 16 kHz mono Float32
├── TranscriptionEngine protocole ASREngine ; impl WhisperKit OU whisper.cpp (ADR-001)
│                       modèle eu fine-tuné + modèle fr/multilingue, routing par langue
├── CorrectionService   protocole Corrector ; impl LatxaLocal (LLM local) + CloudBYOK (Anthropic) + Off
├── InsertionService    NSPasteboard + CGEvent Cmd+V, restore clipboard, fallback clipboard-only
├── HotkeyService       raccourci global + hold-to-talk (event tap), permission gérée
├── ModelManager        téléchargement HF, checksum, stockage ~/Library/Application Support/Mintzo/Models
├── HistoryStore        SwiftData : Transcription(texteBrut, texteCorrigé, date, durée, langue, source)
├── UI
│   ├── MenuBarExtra    statut, langue, actions rapides
│   ├── RecordingHUD    NSPanel flottant non-activant
│   ├── MainWindow      historique + drop zone fichiers + file d'attente
│   ├── Onboarding      permissions + modèles
│   └── Settings        hotkey, langues, correction, modèles, insertion
└── Localisation        eu (défaut si système eu), fr, en
```

## Décisions actées
- **Swift 6 / SwiftUI natif**, pas d'Electron/Tauri — exigence UX premium + local ML.
- **Audio décodé via CoreAudio/AVFoundation uniquement** (opus inclus, vérifié) — zéro ffmpeg embarqué.
- **Modèles jamais commités** ; téléchargés au runtime avec licences affichées.
- **Pas d'emojis dans l'UI** — SF Symbols et typographie uniquement.
- **Direction design** : luxe minimal éditorial, identité basque subtile (pas de folklore) ; conforme Liquid Glass macOS 26.
- **Correction ≠ reformulation** : la passe LLM corrige (orthographe, ponctuation, casse), interdiction de paraphraser. Les deux versions (brute/corrigée) sont conservées.

## Critères d'acceptation V1
1. Dicter une phrase en basque dans TextEdit via hotkey → texte correct inséré < 5 s après fin de parole (M4).
2. Dicter en français → même flow, qualité équivalente à la dictée macOS ou mieux.
3. Glisser un vocal WhatsApp .opus de 2 min → transcription basque correcte dans l'historique.
4. Correction activée → ponctuation/majuscules propres sans changement de sens ; les deux versions consultables.
5. Quit/relaunch → historique intact, réglages intacts, modèles pas re-téléchargés.
6. Fonctionne intégralement en mode avion.

## Risques identifiés
- Qualité basque du modèle fine-tuné ≠ « parfait » sur accents/dialectes (souletin…) → mitiger : choisir le meilleur benchmark public, roadmap fine-tuning communautaire.
- Fine-tune eu qui dégrade le fr → routing 2 modèles (coût disque/RAM) — arbitrage ADR-001.
- Latence correction LLM local sur longues dictées → correction async/streaming, toggle par mode.
- Permissions accessibilité = friction onboarding → écran pédagogique soigné + fallback clipboard-only fonctionnel.
- Nom « Mintzo » : collisions à vérifier (recherche en cours).
