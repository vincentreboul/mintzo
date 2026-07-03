# Contributing to Mintzo

Ongi etorri. Ekarpenak euskaraz, frantsesez edo ingelesez egin daitezke — issues eta pull requestak, hirurak ongi etorriak.

Issues and pull requests are welcome in Basque, French or English. This guide is in English so that upstream contributors can follow it; the project itself is Basque-first.

## Building from source

Requirements: Apple Silicon Mac, macOS 15 or later, Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
scripts/fetch-whisper-xcframework.sh   # whisper.cpp v1.9.1, SHA256-pinned
scripts/fetch-llama-xcframework.sh     # llama.cpp b9862, SHA256-pinned
xcodegen generate
open Mintzo.xcodeproj
```

To run the tests, download the small test model once (`scripts/download-test-model.sh`), then Product ▸ Test (⌘U) on the `Mintzo` or `MintzoCore` scheme.

Layout: `Sources/Mintzo` is the macOS app shell, `Sources/MintzoCore` is the portable core (transcription, correction, models, history), `Tests/` the unit tests, `scripts/` the fetch tooling.

## Style — non negotiable

- **Swift 6, strict concurrency** (`SWIFT_STRICT_CONCURRENCY: complete`). No new warnings.
- **[docs/design/design-language.md](docs/design/design-language.md) is law** for anything user-visible: colors, typography, spacing, motion, microcopy. Read it before touching UI, and check the QA checklist at its end before opening a PR.
- **No emoji in the UI.** SF Symbols and typography only.
- **Sober copy.** No exclamation marks, no chatbot humor. Explanations say why, plainly.
- **Every user-facing string ships in the three languages**: euskara (batua), French, English. Basque terminology follows the [Librezale](https://librezale.eus/) conventions. A PR that adds a string in one language only is incomplete.
- **Models are never committed.** They are downloaded at runtime and checksum-verified; see [docs/MODELS.md](docs/MODELS.md).

## Where help matters most

1. **Basque dialects and accents.** Testing dictation with bizkaiera, zuberera, Iparralde accents, spontaneous speech. This is the most valuable contribution: the models are trained mostly on read batua.
2. **ASR quality reports.** Open an issue with: a short audio sample (a few seconds is enough), what Mintzo produced, what you expected, your macOS version and chip, and which model (name and size, see [docs/MODELS.md](docs/MODELS.md)).
3. **Basque localization review.** Checking Mintzo's strings against Librezale conventions, proposing better wording.
4. **Not code, still essential:** [record a few sentences on Common Voice](https://commonvoice.mozilla.org/eu). Every validated hour improves the next generation of Basque models.

## Pull requests

- One topic per PR, small and focused.
- Say what and why. For UI changes, include before/after screenshots in light and dark mode.
- Tests must pass locally before review.
- New user-facing strings come with their eu/fr/en versions in the same PR.

## Bug reports

Include: macOS version, chip, commit or app version, installed models, steps to reproduce. For transcription issues, attach audio whenever possible.
