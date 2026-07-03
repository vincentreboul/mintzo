# Mintzo — Recherche stack macOS native (dictée type Wispr Flow / SuperWhisper)

> Date : 2026-07-03 · Cible : macOS 26 (Tahoe), Xcode 26.5, Apple Silicon M4, SwiftUI, open source
> Besoin : hotkey global → micro → transcription locale (Whisper fine-tuné **basque** + turbo standard) → insertion au curseur + clipboard + historique. Plus : transcription de fichiers audio dont vocaux WhatsApp (`.opus`).
> Méthode : docs officielles + GitHub vérifiés (URLs en fin de doc) + **tests empiriques exécutés sur cette machine (macOS 26.5, build 25F71)**. Ce qui n'a pas pu être vérifié est marqué **NON CONFIRMÉ**.

---

## TL;DR — Stack recommandée

| Composant | Choix | Version vérifiée (2026-07) | Licence |
|---|---|---|---|
| Runtime ASR | **WhisperKit** (argmax-oss-swift) | v1.0.0 (2026-05-01), pushé 2026-07-01 | MIT |
| Conversion fine-tune | **whisperkittools** (`whisperkit-generate-model`) | actif | MIT |
| Fallback ASR | whisper.cpp via XCFramework binaryTarget | v1.9.1 (2026-06-19) | MIT |
| Hotkey global | **sindresorhus/KeyboardShortcuts** + CGEventTap dédié pour touche Fn | 3.0.1 (2026-06-17) | MIT |
| Insertion texte | NSPasteboard + CGEvent Cmd+V simulé, restauration clipboard | AppKit natif | — |
| Capture micro | AVAudioEngine installTap + AVAudioConverter → 16 kHz mono Float32 | AVFAudio natif | — |
| Décodage .opus | **AVAudioFile natif** (vérifié empiriquement sur macOS 26.5) ; fallback SFBAudioEngine | SFBAudioEngine 0.13.0 (2026-06-08) | MIT |
| UI menu bar | MenuBarExtra (.window) + **MenuBarExtraAccess** | 1.3.0 (2026-02-25) | MIT |
| HUD pilule | NSPanel `.nonactivatingPanel` + NSHostingView + `.glassEffect()` (Liquid Glass) | AppKit/SwiftUI natif | — |
| Historique | **GRDB.swift** (FTS5 pour recherche plein texte) | v7.11.1 (2026-06-18) | MIT |

---

## 1. Runtime Whisper en Swift — WhisperKit vs whisper.cpp

### a) WhisperKit (argmaxinc) — RECOMMANDÉ

- **État 2026** : v1.0.0 publiée le 2026-05-01. Le repo a été renommé `argmaxinc/WhisperKit` → `argmaxinc/argmax-oss-swift` et regroupe désormais WhisperKit + SpeakerKit + TTSKit dans un seul package SPM MIT (produits de librairie séparés, ou umbrella `ArgmaxOSS`). ★6 243, dernier push 2026-07-01 — très actif. URL package SPM : `https://github.com/argmaxinc/argmax-oss-swift`.
- **Fine-tunes custom — pipeline DOCUMENTÉ** (le point décisif pour le modèle basque) :
  1. `pip install whisperkittools` puis `whisperkit-generate-model --model-version <org/mon-whisper-basque-HF> --output-dir <dir>` — convertit n'importe quel Whisper PyTorch Hugging Face (donc un fine-tune) en CoreML. Options de quantization : `--generate-quantized-variants`, `--allowed-nbits 4`, etc.
  2. Publication sur HF : `MODEL_REPO_ID=mon-org/mon-repo whisperkit-generate-model ...`.
  3. Chargement côté app : `WhisperKitConfig(model: "...", modelRepo: "username/your-model-repo")` — extrait verbatim du README. Les modèles peuvent aussi être embarqués localement (pas d'obligation HF au runtime).
  - Précédent réel : ModMed a déployé un large-v3 fine-tuné médical sur iOS via ce pipeline ; le modèle communautaire Breeze ASR 25 (fine-tune large-v2 taïwanais) est distribué au format whisperkit-coreml.
- **Turbo standard** : `large-v3-v20240930` (= large-v3-turbo, variante 626 MB quantizée) est hébergé pré-converti dans `argmaxinc/whisperkit-coreml` sur HF — download over-the-air intégré.
- **Streaming temps réel** : architecture modifiée pour l'inférence streaming (encoder streaming + decoder sur audio partiel — papier arXiv 2507.10860). VAD énergie intégré + `DecodingOptions.chunkingStrategy = .vad`. La classe haut niveau `AudioStreamTranscriber` (micro → texte live) existait dans les versions pré-1.0 ; **NON CONFIRMÉ : sa surface exacte dans v1.0.0** (une source tierce affirme qu'elle n'est plus exposée dans l'OSS ; le streaming WebSocket "temps réel" est poussé côté Argmax Pro ; l'OSS garde le streaming SSE via serveur local + le chunking VAD). À vérifier dans le code au spike #1. Speak2 (app open source, avril 2026) fait de la transcription streaming live avec WhisperKit OSS — donc faisable.
- **Perf ANE/GPU M-series** : encoder + decoder CoreML schedulés automatiquement sur ANE/GPU/CPU. C'est LE différenciateur vs whisper.cpp (Metal GPU only par défaut, ANE seulement via conversion CoreML séparée de l'encoder).
- **SPM** : `File > Add Package Dependencies` → URL du repo, produit `WhisperKit`. Requirement plancher macOS : **NON CONFIRMÉ pour v1.0.0** (historiquement macOS 13+) — sans enjeu, Mintzo cible macOS 26.
- Attention : certaines features avancées (diarization, perfs "Pro") sont réservées à WhisperKit Pro (commercial). L'OSS couvre tout le besoin dictée.

### b) whisper.cpp en SPM

- **Le package SPM officiel `ggerganov/whisper.spm` est mort** : dernier push 2024-05-27 (vérifié via API GitHub), 42 commits. Ne pas l'utiliser.
- **La voie moderne documentée dans le README whisper.cpp** : XCFramework précompilé en `binaryTarget` SPM (exemple verbatim avec `whisper-vX-xcframework.zip` + checksum dans le README). whisper.cpp lui-même : v1.9.1 (2026-06-19), ★51 243, très actif.
- **Fine-tunes** : `models/convert-h5-to-ggml.py` (présence vérifiée via l'API GitHub du dossier `models/`) convertit un fine-tune Hugging Face en GGML un-fichier ; quantization q5_0/q8 via l'outil `quantize`. Pipeline mûr, utilisé partout.
- **Metal** : oui par défaut sur Apple Silicon. **ANE** : uniquement pour l'encoder, via conversion CoreML supplémentaire (`generate-coreml-model.sh`, env Python requis) — gain annoncé ×3 vs CPU.
- **VAD** : Silero-VAD intégré nativement (modèle `ggml-silero-v6.2.0.bin`, options fines `--vad-threshold`, `--vad-min-silence-duration-ms`, etc.).
- **Realtime** : exemple `stream` (échantillonnage ~500 ms) — dépend de SDL2 en CLI, à réimplémenter proprement en Swift dans une app.
- Coût réel : bindings C à envelopper soi-même (ou wrapper tiers type SwiftWhisper, non maintenu au même rythme), gestion mémoire manuelle, pas d'ANE decoder.

### Verdict

**WhisperKit en runtime principal.** Raisons : (1) pipeline fine-tune → CoreML → chargement par simple `modelRepo` documenté et éprouvé (ModMed, Breeze) — c'est exactement le besoin basque + turbo ; (2) Swift natif async/await, zéro glue C ; (3) ANE réel sur M4 ; (4) c'est le standard de la catégorie : SuperWhisper tourne sur WhisperKit, MacWhisper a adopté WhisperKit (annonce argmax mai 2024), Speak2/VocaMac (clones open source de Wispr Flow) sont sur WhisperKit. VoiceInk (★5 408, le plus gros clone open source) est lui sur whisper.cpp + FluidAudio/Parakeet — preuve que la voie whisper.cpp marche aussi.
**whisper.cpp en plan B** si la conversion CoreML du fine-tune basque se passe mal (spike à faire en semaine 1 : convertir le modèle basque avec whisperkittools ET avec convert-h5-to-ggml.py, comparer WER/latence).
Note : Parakeet v3 (runtime FluidAudio, plus rapide que Whisper) ne couvre **pas** le basque (25 langues EU vérifiées via l'API HF `nvidia/parakeet-tdt-0.6b-v3` : pas de tag `eu`) → hors sujet pour Mintzo v1.

---

## 2. Hotkey global + push-to-talk

### KeyboardShortcuts (sindresorhus)

- État 2026 : v3.0.1 (2026-06-17), pushé 2026-06-17, ★2 654, MIT. Sain et actif.
- `KeyboardShortcuts.Recorder` = UI SwiftUI de capture du raccourci (stockage UserDefaults, détection de conflits système/menus inclus).
- **Push-to-talk possible** : `.onKeyDown(for:)` + `.onKeyUp(for:)` → down = start recording, up = stop + transcribe. Vérifié dans le README.
- **Aucune permission TCC requise** (Carbon `RegisterEventHotKey` sous le capot ; "fully sandboxed and Mac App Store compatible" — README). macOS 10.15+.
- Limite : ne gère pas la touche **Fn seule** (pas un raccourci Carbon). Pas de mention Fn dans le README/FAQ.

### Hold-to-talk : CGEventTap vs NSEvent global monitor — permissions

- `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` → exige la permission **Accessibility** ; ne peut PAS modifier/avaler les événements.
- `CGEvent.tapCreate` en **listen-only** → permission **Input Monitoring** (`CGPreflightListenEventAccess()` / `CGRequestListenEventAccess()`), compatible sandbox/MAS. En tap **actif** (capable d'avaler l'événement) → **Accessibility**.
- En pratique, la permission Accessibility couvre aussi les taps listen-only : Speak2 ne demande que Accessibility + Microphone pour son HotkeyManager CGEventTap ("fn key detection requires Accessibility permission" — README Speak2). Comme Mintzo a de toute façon besoin d'Accessibility pour le collage simulé (§3), **un seul prompt Accessibility suffit** pour hotkey Fn + paste. 
- Piège documenté (danielraffel, 2026-02) : un binaire re-signé/recompilé perd silencieusement son event tap (TCC lie la permission à la signature) → prévoir détection de tap désactivé (`kCGEventTapDisabledByTimeout` / re-enable) et message utilisateur.

### Touche Fn/🌐 comme Wispr Flow

- **Faisable, prouvé en production open source** : Speak2 (v1.8.1, 2026-04) utilise exactement "Hold the fn key → record, release → paste", via CGEventTap sur `flagsChanged` (keyCode 63 / flag `.maskSecondaryFn`). Hotkeys proposés : "Fn, Right Option, Right Command, Hyper Key, or any custom key combo".
- Pas d'API publique dédiée "Globe key hotkey" : c'est du monitoring `flagsChanged` (keyDown Fn = flag présent, keyUp = flag retiré).
- **Pièges** : (1) le simple appui Fn déclenche l'action système configurée (émoji / changement de langue / dictée Apple) → demander à l'utilisateur de mettre "Appuyer sur la touche 🌐 : Ne rien faire" dans Réglages Système > Clavier, OU avaler l'événement avec un tap actif (plus intrusif) ; (2) le double-appui Fn est réservé par macOS pour sa propre dictée — avaler les flagsChanged casse cette détection système (bug documenté kitty #9661) ; (3) débounce nécessaire (multiples flagsChanged par appui perçu).
- Reco : **KeyboardShortcuts pour les combos classiques (avec son Recorder) + un petit moniteur CGEventTap `flagsChanged` dédié pour le mode "hold Fn"** — le pattern Speak2.

---

## 3. Insertion au curseur

### Pattern standard (celui de toute la catégorie)

1. Snapshot du pasteboard courant (`NSPasteboard.general`, garder `changeCount` + items).
2. `setString(transcription)`.
3. Delay ~50 ms (le pasteboard doit "prendre" — délai empirique documenté dans les writeups de dictée Swift).
4. CGEvent keyDown/keyUp keyCode 9 (V) avec `.maskCommand`, posté sur `kCGHIDEventTap` → **exige Accessibility** (`AXIsProcessTrusted()`, prompt via `AXIsProcessTrustedWithOptions`).
5. Restaurer l'ancien clipboard après ~200-300 ms.

C'est exactement le pipeline de Speak2 (« TextInjector - Copies transcription to clipboard, simulates Cmd+V to paste, then restores original clipboard contents ») et de VoiceInk. Wispr Flow / SuperWhisper font pareil (comportement observable : clipboard écrasé puis restauré).

### Pièges connus

- **Secure input** : quand un champ mot de passe est actif (`IsSecureEventInputEnabled()` — TN2150 Apple), les CGEvents clavier et le monitoring sont bloqués. Pire : un process peut laisser le secure input "coincé" système-wide (problème classique documenté par Keyboard Maestro, Espanso, TextExpander). → Checker `IsSecureEventInputEnabled()` avant d'insérer ; si actif, fallback clipboard-seul + notification "Cmd+V manuellement".
- **Apps Electron** : paste simulé OK en général, mais délais plus longs parfois nécessaires (rendu web) ; prévoir un délai par-app configurable (VoiceInk fait du per-app "power mode").
- **Restauration clipboard** : race avec les clipboard managers (Raycast, Maccy…) qui capturent la valeur transitoire ; restaurer trop vite peut écraser le paste dans les apps lentes. Compromis : 200-300 ms + ne restaurer que si `changeCount` n'a pas bougé entre-temps.
- Certains types riches du pasteboard (images, fichiers) ne se re-snapshotent pas parfaitement — restaurer au mieux (texte + types courants), documenter la limite.

### Alternative AXUIElement — verdict : fast-path opportuniste seulement

- `AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute, text)` insère au curseur **quand l'app implémente correctement AX** : OK champs natifs AppKit ; **cassé/fragile en Electron** (electron#36337 : ranges faux si la ligne commence par des blancs ; lenteurs et curseur erratique dans Slack — writeup Hammerspoon/balatero) ; échoue **silencieusement sans erreur** sur les éléments non supportés ; exception rapportée au-delà de ~2040 caractères (Apple dev forums).
- `kAXValueAttribute` remplace tout le contenu du champ — inutilisable pour insérer.
- Reco : v1 = paste simulé partout. Option v1.1 : tenter AX (focused element via `kAXFocusedUIElementAttribute`) et fallback paste — c'est du polish, pas du socle.

---

## 4. Capture micro

- **Pattern recommandé** : `AVAudioEngine` → `inputNode.installTap(onBus: 0, bufferSize: 1024-4096, format: nil)` (format hardware, typiquement 48 kHz) → `AVAudioConverter` vers `AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)` → accumulation dans un buffer `[Float]` pour Whisper. Pattern validé par l'issue whisper.cpp #2008 (exemple verbatim de conversion) et les writeups WhisperKit/CoreML.
- **Ne jamais imposer 16 kHz directement dans `installTap`** (crash si le device ne le supporte pas) : taper au format natif puis convertir. **Recréer le converter sur changement de device** (AirPods = sample rates différents — fil Swift Forums).
- Avec `AVAudioConverter`, dimensionner le buffer de sortie sur l'estimation de frames et ne nourrir l'input qu'une fois par callback de conversion (piège classique du block-based convert).
- **Permission** : `NSMicrophoneUsageDescription` dans Info.plist + `AVAudioApplication.requestRecordPermission` (ou `AVCaptureDevice.requestAccess(for: .audio)`).
- Note : WhisperKit embarque son propre `AudioProcessor` (capture + resampling interne) — si WhisperKit est retenu, la capture "maison" ne sert que pour la waveform du HUD et le VAD local ; possibilité de brancher les mêmes buffers dans les deux.

---

## 5. Décodage .opus WhatsApp

### ✅ VÉRIFIÉ EMPIRIQUEMENT : AVFoundation lit l'Ogg Opus nativement sur macOS 26.5

Test exécuté sur cette machine (2026-07-03, macOS 26.5 build 25F71) :

```
$ ffmpeg -f lavfi -i "sine=..." -c:a libopus test-voicenote.opus   # Ogg Opus, comme un vocal WhatsApp
$ afinfo test-voicenote.opus
File type ID:   Oggf
Data format:     1 ch,  48000 Hz, opus (0x00000000)
$ swift opustest.swift test-voicenote.opus
AVAudioFile OK | processingFormat: <AVAudioFormat: 1 ch, 48000 Hz, Float32> | length: 96000
read frames: 8192
$ afconvert -f WAVE -d LEI16@16000 -c 1 test-voicenote.opus out.wav   # → OK, WAV 16 kHz mono
```

- `AVAudioFile(forReading:)` ouvre et décode le `.opus` (conteneur Ogg, codec Opus — le format exact des vocaux WhatsApp) et sort du PCM Float32 48 kHz → conversion 16 kHz via AVAudioConverter, identique au flux micro. Les vieux threads Apple Forums "error -11828 not supported" (2019) sont **obsolètes** sur macOS 26 ; le README SFBAudioEngine confirme : "FLAC, Ogg Opus, and MP3 are natively supported by Core Audio".
- **Reste à re-smoke-tester avec un vrai vocal WhatsApp** (mon échantillon était généré par ffmpeg/libopus — même conteneur/codec, risque quasi nul, 5 min de test).
- Conséquence : **zéro dépendance C (libopus/libogg) nécessaire** pour la cible macOS 26. Gros gain de simplicité.

### Fallbacks si un .opus exotique coince

- **SFBAudioEngine** (sbooth) : 0.13.0 (2026-06-08), pushé 2026-06-23, MIT, ★694. Décodeurs propres Ogg Opus/Vorbis/Speex + tout Core Audio + libsndfile. Le fallback le plus riche.
- **element-hq/swift-ogg** : 0.0.4 (2026-05-06), Apache-2.0, ★50. API minuscule opus/ogg ↔ m4a via libopus/libogg (utilisé par Element/Matrix). OK mais conçu pour la conversion, pas le décodage streaming.
- alta/swift-opus : BSD-3, **stale** (dernier push 2024-08) — éviter.

### Autres formats

- `.m4a` / `.mp3` / `.aac` / `.wav` / `.flac` : trivial via `AVAudioFile` — confirmé aussi par le README WhisperKit (`transcribe(audioPath: "audio.{wav,mp3,m4a,flac}")`). WhisperKit accepte directement un chemin de fichier → pour les fichiers, pas besoin de pipeline audio custom, juste convertir l'`.opus` → buffer PCM et le passer en `AudioProcessor`/array de floats (ou pré-convertir en wav 16k temporaire).

---

## 6. UI menu bar + HUD

### MenuBarExtra (SwiftUI)

- Utilisable en `.menuBarExtraStyle(.window)` pour un popover riche. **Limites documentées** (repo MenuBarExtraAccess + feedback-assistant FB13683950 / FB11984872) :
  - pas d'API premier-parti pour lire/piloter l'état de présentation, accéder au `NSStatusItem`, ou fermer programmatiquement la fenêtre `.window` ;
  - en style `.menu`, le menu bloque le runloop tant qu'il est ouvert (bindings inopérants) et aucun événement d'ouverture ;
  - le bouton de barre est limité à image/texte (pas de vue custom — donc pas de mini-waveform animée dans la barre via MenuBarExtra pur ; il faudrait un `NSStatusItem` manuel si indispensable).
- **MenuBarExtraAccess** (orchetect) comble l'essentiel : binding `isPresented`, accès au `NSStatusItem`. 1.3.0 (2026-02-25), pushé 2026-04, MIT. Piège connu : cas limites où l'état du status item s'inverse.
- Piège classique app menu-bar : ouvrir Settings depuis le popover (activation policy `.accessory`, focus) — writeup steipete "Showing Settings from macOS Menu Bar Items". Prévoir `NSApp.activate` + `openSettings`.

### HUD flottant (pilule waveform style SuperWhisper)

Recette standard, bien documentée (tutoriel Cindori "Make a floating panel in SwiftUI" + fazm.ai + doc Apple `nonactivatingPanel`) :

- Sous-classe `NSPanel` avec `styleMask: [.borderless, .nonactivatingPanel]` → **ne vole jamais le focus** de l'app cible (critique : le paste doit atterrir dans l'app active).
- `level = .floating` (ou `.statusBar` pour passer au-dessus de tout), `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` (visible sur tous les Spaces et par-dessus les apps fullscreen), `becomesKeyOnlyIfNeeded = true`, `isMovableByWindowBackground` au choix, contenu SwiftUI via `NSHostingView`.
- Position : bas-centre de `NSScreen.main.visibleFrame` (pattern SuperWhisper) ; suivre le curseur est possible (`NSEvent.mouseLocation`) mais gadget.
- Piège : un champ texte dans un panel non-activant ne reçoit pas le clavier → `panel.makeKey()` explicite au clic si un jour le HUD devient éditable.
- Waveform : `TimelineView` + `Canvas` SwiftUI alimenté par les RMS des buffers du tap micro — pas de lib nécessaire.

### macOS 26 "Liquid Glass"

- Nouveau langage visuel Tahoe : SwiftUI `.glassEffect()` (+ `GlassEffectContainer` pour grouper — le verre ne peut pas sampler du verre), AppKit `NSGlassEffectView`. Pertinent pour Mintzo : la **pilule HUD en capsule `.glassEffect()`** rend exactement l'esthétique "verre" système native, et le popover MenuBarExtra hérite du style système sans effort. Morphing d'états (idle → recording → processing) via `glassEffectID` + Namespace.
- La barre de menus Tahoe est transparente par défaut — fournir un template icon monochrome propre (pas d'emoji, conforme à la règle UI).

---

## 7. Persistence historique

- **SwiftData sur macOS 26** : fonctionne pour un historique simple, mais l'écosystème 2026 reste réservé : rough edges persistants, investissement Apple faible depuis le lancement, perfs read/write nettement sous SQLite direct (analyses fatbobman + BrightDigit). Surtout : **pas de recherche plein texte**.
- **GRDB.swift** : v7.11.1 (2026-06-18), ★8 516, MIT, très actif. **FTS5 supporté nativement** (`db.create(virtualTable:using: FTS5())`, doc dédiée FullTextSearch.md) → la recherche dans l'historique de transcriptions (feature core d'un Wispr-like) est triviale et instantanée. Migrations propres, `ValueObservation` pour brancher SwiftUI.
- Verdict : **GRDB**. Schéma v1 : table `transcription(id, text, createdAt, durationSec, language, source[dictation|file], modelId, appBundleId?)` + table virtuelle FTS5 `transcription_ft(text)` en external content. SwiftData n'apporterait que du sucre @Model au prix de la FTS et du contrôle.
- (Anecdote validante : Speak2 stocke son historique en JSON local plafonné à 500 entrées — ça marche, mais pas de recherche riche ; GRDB est le bon cran au-dessus pour un historique illimité searchable.)

---

## Risques transverses & pièges

1. **Permissions TCC (le vrai sujet UX du premier lancement)** : Microphone + Accessibility obligatoires (paste + Fn). Input Monitoring seulement si on choisit le tap listen-only sans Accessibility. Prévoir un écran d'onboarding permissions avec deep-links `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`. Après revoke/re-grant ou re-signature du binaire, les event taps meurent silencieusement → watchdog + relaunch hint (Speak2 documente le même symptôme).
2. **Pas de sandbox** : CGEvent posting + AXIsProcessTrusted sont incompatibles App Store sandbox → distribution **Developer ID + notarization** (canal GitHub Releases + Homebrew cask, comme VoiceInk/Speak2). KeyboardShortcuts serait MAS-safe mais le paste ne l'est pas.
3. **Licences des références** : VoiceInk = GPL-3.0 (indiqué dans sa doc ; l'API GitHub remonte NOASSERTION), Speak2 = licence non déclarée. **Ne pas copier leur code** si Mintzo veut être MIT — s'en inspirer architecturalement seulement. WhisperKit/whisper.cpp/GRDB/KeyboardShortcuts/SFBAudioEngine : MIT, swift-ogg : Apache-2.0 — tous compatibles MIT.
4. **Conversion du fine-tune basque = risque n°1 du projet** → spike semaine 1 : `whisperkit-generate-model` sur le checkpoint HF basque, éval WER via `whisperkit-evaluate-model` (supporte dataset custom HF), comparaison avec la voie GGML whisper.cpp. Si les deux échouent, le plan C est l'inférence GGML du fine-tune en process séparé (whisper-cli) — moche mais dérisquant.
5. **Streaming WhisperKit v1.0.0** : vérifier la présence/forme d'`AudioStreamTranscriber` dans la v1.0.0 (renommage possible dans la réorg argmax-oss-swift). Le fallback simple : transcription à la volée par fenêtres VAD (chunkingStrategy .vad) — suffisant pour une dictée (le texte n'est inséré qu'au release de toute façon).
6. **Apple SpeechAnalyzer/SpeechTranscriber (natif macOS 26)** : nouvelle API WWDC25, rapide et gratuite, mais locales limitées (liste type ar_SA, da_DK, de_*, en_*, … — **NON CONFIRMÉ : liste exacte macOS 26 GM**) et **aucun support de modèles custom** → inutilisable pour le basque. Option future : offrir SpeechTranscriber comme moteur alternatif pour les langues majeures (Argmax eux-mêmes publient un comparatif "Apple SpeechAnalyzer and Argmax WhisperKit").
7. **Secure input coincé système-wide** : symptôme connu qui "casse" toutes les apps de ce type ; afficher l'app coupable (pattern Keyboard Maestro : `ioreg -l -w 0 | grep SecureInput`) dans un diagnostic.

---

## Spikes recommandés (ordre)

1. Conversion fine-tune basque → whisperkittools → chargement WhisperKit local + WER sur 10 vocaux réels.
2. Boucle complète hold-Fn → micro → turbo → paste dans TextEdit/Slack/Safari (3 familles d'apps).
3. Vrai vocal WhatsApp `.opus` → AVAudioFile → transcription (5 min, valide le §5).
4. HUD NSPanel + glassEffect au-dessus d'une app fullscreen.

---

## Sources (vérifiées 2026-07-03)

**Runtime ASR**
- https://github.com/argmaxinc/argmax-oss-swift (alias https://github.com/argmaxinc/WhisperKit) — v1.0.0, MIT, README : Generating Models / Quick Example / Local Server
- https://github.com/argmaxinc/whisperkittools — conversion + éval, `whisperkit-generate-model`
- https://huggingface.co/argmaxinc/whisperkit-coreml — modèles pré-convertis (dont large-v3 turbo 626MB)
- https://www.argmaxinc.com/blog/whisperkit · https://arxiv.org/html/2507.10860v1 (papier WhisperKit)
- https://github.com/ggml-org/whisper.cpp — v1.9.1 ; sections Core ML / VAD / XCFramework / ggml format ; `models/convert-h5-to-ggml.py` (vérifié via API contents)
- https://github.com/ggerganov/whisper.spm — STALE (dernier push 2024-05-27, vérifié API GitHub)
- https://x.com/argmaxinc/status/1792631832250335539 (MacWhisper on WhisperKit)
- https://huggingface.co/api/models/nvidia/parakeet-tdt-0.6b-v3 (25 langues, pas de `eu`)

**Apps de référence (architecture)**
- https://github.com/Beingpax/VoiceInk — ★5.4k, whisper.cpp + FluidAudio, GPL
- https://github.com/zachswift615/speak2 — WhisperKit, hold-Fn via CGEventTap, TextInjector clipboard+Cmd+V+restore
- https://github.com/jatinkrmalik/vocamac — WhisperKit hold-hotkey

**Hotkey / événements**
- https://github.com/sindresorhus/KeyboardShortcuts — 3.0.1, Recorder, onKeyDown/onKeyUp, sandbox-safe
- https://developer.apple.com/forums/thread/789896 (NSEvent global = Accessibility ; CGEventTap listen-only = Input Monitoring, CGPreflight/RequestListenEventAccess)
- https://github.com/kovidgoyal/kitty/issues/9661 (double-Fn dictée système vs flagsChanged avalés)
- https://danielraffel.me/til/2026/02/19/cgevent-taps-and-code-signing-the-silent-disable-race/

**Insertion**
- https://www.hairizuan.com/building-a-dictation-app-with-swift (pattern pasteboard + 50ms + Cmd+V)
- https://developer.apple.com/library/archive/technotes/tn2150/_index.html (Secure Event Input, IsSecureEventInputEnabled)
- https://wiki.keyboardmaestro.com/assistance/Secure_Input_Problem · https://espanso.org/docs/troubleshooting/secure-input/
- https://github.com/electron/electron/issues/36337 (AX selected-text range cassé Electron)
- https://balatero.com/writings/hammerspoon/retrieving-input-field-values-and-cursor-position-with-hammerspoon/

**Audio**
- https://github.com/ggerganov/whisper.cpp/issues/2008 (installTap → AVAudioConverter 16k mono Float32)
- https://forums.swift.org/t/swift-avaudioengine-airpod-convert-samplerate/34243
- Test local .opus : afinfo/afconvert/AVAudioFile sur macOS 26.5 (25F71) — voir §5
- https://github.com/sbooth/SFBAudioEngine — 0.13.0, MIT, décodeurs Ogg Opus
- https://github.com/element-hq/swift-ogg — 0.0.4, Apache-2.0
- https://developer.apple.com/forums/thread/128434 (ancien "not supported", obsolète macOS 26)

**UI**
- https://developer.apple.com/documentation/SwiftUI/MenuBarExtra
- https://github.com/orchetect/MenuBarExtraAccess — 1.3.0 + limitations MenuBarExtra documentées
- https://github.com/feedback-assistant/reports/issues/475 · https://github.com/feedback-assistant/reports/issues/383
- https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items
- https://cindori.com/developer/floating-panel · https://fazm.ai/blog/swiftui-floating-panel
- https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel
- https://dev.to/diskcleankit/liquid-glass-in-swift-official-best-practices-for-ios-26-macos-tahoe-1coo · https://github.com/conorluddy/LiquidGlassReference

**Persistence**
- https://github.com/groue/GRDB.swift — v7.11.1 + https://github.com/groue/GRDB.swift/blob/master/Documentation/FullTextSearch.md (FTS5)
- https://fatbobman.com/en/posts/key-considerations-before-using-swiftdata/ · https://brightdigit.com/articles/swiftdata-considerations/

**Apple Speech (alternative non retenue pour le basque)**
- https://developer.apple.com/documentation/speech/speechanalyzer · https://developer.apple.com/documentation/speech/speechtranscriber
- https://www.argmaxinc.com/blog/apple-and-argmax
