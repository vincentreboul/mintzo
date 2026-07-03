# Mintzo

**Dictation and transcription for Basque and French, 100% local on your Mac.**

[Euskara](README.md) · [Français](README.fr.md) · **English**

**Website and online tool: [www.mintzo.fr](https://www.mintzo.fr)** · **[Download the Mac app](https://github.com/vincentreboul/mintzo/releases/latest)**

## What Mintzo does

- **System-wide dictation.** Press a global hotkey, speak, and the corrected text is inserted at the cursor in any application. A copy goes to the clipboard and to the history.
- **Audio file transcription.** Drop a WhatsApp voice message (`.opus`), a voice memo (`.m4a`), an `.mp3` or another audio format: Mintzo transcribes and corrects it.
- **Basque correction, on device.** Beyond the raw transcript, the Latxa model fixes spelling, punctuation and casing without changing the meaning. Both versions are always kept: original and corrected.
- **History.** All your transcriptions in one place: full-text search, one-click copy, delete one or all.
- **Offline.** Once the models are downloaded, no connection is needed: Mintzo works in airplane mode. No telemetry, no account, no subscription.

**"Audioa ez da inoiz zure Mac-etik ateratzen." — audio never leaves your Mac.**

## Why

Basque deserves first-rank tools — on par with what English or French speakers take for granted. Mintzo is built on the work of the Basque language-technology community: the models of the HiTZ center, the voices of Common Voice volunteers, years of free-software effort. The goal is simple: turn that work into an everyday tool, free and open source, for any Basque speaker with a Mac.

## Status

Under active development. **[Download the latest release (zip)](https://github.com/vincentreboul/mintzo/releases/latest)** — Apple Silicon, macOS 15+, unsigned development build: on first launch, right-click the app and choose "Open". The online tool: [www.mintzo.fr/tresna](https://www.mintzo.fr/tresna).

Contributions are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md).

### Building from source

Requirements: an Apple Silicon Mac, macOS 15 or later, Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
# from the repository root
brew install xcodegen
scripts/fetch-whisper-xcframework.sh   # whisper.cpp v1.9.1 (XCFramework)
scripts/fetch-llama-xcframework.sh     # llama.cpp b9862 (XCFramework)
xcodegen generate
open Mintzo.xcodeproj
```

In Xcode, run the `Mintzo` scheme. To run the tests, first download the small test model (`scripts/download-test-model.sh`), then Product ▸ Test (⌘U).

## How it works

```
audio — microphone or file
   │
   │  CoreAudio · 16 kHz mono
   ▼
Whisper large-v3, Basque fine-tune — whisper.cpp · Metal
   │
   │  raw transcript
   ▼
Latxa 4B (optional) — llama.cpp
   │
   │  correction: spelling, punctuation, casing
   ▼
text — inserted at the cursor · clipboard · history
```

Basque audio is transcribed with the Basque fine-tune of Whisper large-v3; French with the multilingual large-v3-turbo model. The app downloads the models itself on first use, once, and verifies them with SHA256. Sizes: Basque model 3.1 GB, French model 1.6 GB, Latxa 2.5 GB.

Correction is optional: it can be turned off, or, if you choose, handed to a cloud model with your own API key. The default is always local, and audio is never uploaded anywhere.

## Credits

Mintzo is built on this work:

- **[xezpeleta/whisper-large-v3-eu](https://huggingface.co/xezpeleta/whisper-large-v3-eu)** (Apache 2.0) — the Basque transcription engine. Per its model card, 4.84 WER on the Common Voice 18 test set, against 38.85 for vanilla Whisper.
- **[HiTZ](https://hitz.ehu.eus/)**, the language technology center of the University of the Basque Country (UPV/EHU) — creator of **[Latxa](https://huggingface.co/HiTZ/Latxa-Qwen3-VL-4B-Instruct)**, the family of Basque language models (Apache 2.0). Latxa is the heart of the correction pass.
- **[Mozilla Common Voice Basque](https://commonvoice.mozilla.org/eu)** — the free corpus of volunteer voices that underpins Basque speech technology. You can help too: [record a few sentences](https://commonvoice.mozilla.org/eu).
- **[whisper.cpp](https://github.com/ggml-org/whisper.cpp)** and **[llama.cpp](https://github.com/ggml-org/llama.cpp)** (ggml-org, MIT) — the engines that make local inference possible.
- **[Librezale](https://librezale.eus/)** — the collective that localizes free software into Basque. Mintzo's Basque strings follow its conventions, and the localization is open to community review.

Plus the Swift libraries [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) and [GRDB](https://github.com/groue/GRDB.swift).

## Roadmap

1. **V1 — native Mac app** (in progress): dictation, files, history.
2. **Phase 2 — website**: upload and transcribe online; a first answer for Windows users.
3. **Phase 3 — native Windows app**: the engines and models (whisper.cpp, llama.cpp, GGML/GGUF) are portable by design, ready for this step.

iOS is not on the current roadmap.

## License

MIT — see [LICENSE](LICENSE). Models downloaded at runtime keep their own licenses; full list and verification data: [docs/MODELS.md](docs/MODELS.md).
