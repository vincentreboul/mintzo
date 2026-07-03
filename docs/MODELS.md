# Models — provenance, licenses, integrity

Mintzo ships no model weights: nothing is bundled in the app or committed to this repository. Models are downloaded at runtime, once, and every download is verified against the exact size and SHA256 below before being used.

These values mirror the source of truth in code — `Sources/MintzoCore/Models/ModelCatalog.swift` and `Sources/MintzoCore/Correction/LatxaCatalog.swift` — and were verified against the Hugging Face API (`size` and `lfs.oid` of each file) on 2026-07-03.

## Catalog

| Role | Model | Hugging Face repo | File | Size | License |
|---|---|---|---|---|---|
| Basque transcription | Whisper large-v3, Basque fine-tune | [xezpeleta/whisper-large-v3-eu](https://huggingface.co/xezpeleta/whisper-large-v3-eu) | `ggml-large-v3.eu.bin` | 3.1 GB (3 095 033 483 B) | Apache-2.0 |
| French / multilingual transcription | Whisper large-v3-turbo | [ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp) | `ggml-large-v3-turbo.bin` | 1.6 GB (1 624 555 275 B) | MIT |
| Basque correction (optional) | Latxa-Qwen3-VL-4B-Instruct, Q4_K_M quant | [mradermacher/Latxa-Qwen3-VL-4B-Instruct-GGUF](https://huggingface.co/mradermacher/Latxa-Qwen3-VL-4B-Instruct-GGUF) | `Latxa-Qwen3-VL-4B-Instruct.Q4_K_M.gguf` | 2.5 GB (2 497 282 176 B) | Apache-2.0 |
| Automated tests only | Whisper tiny | [ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp) | `ggml-tiny.bin` | 78 MB (77 691 713 B) | MIT |

## Integrity (SHA256)

| File | SHA256 |
|---|---|
| `ggml-large-v3.eu.bin` | `dae98a83f5450d1a26632430649633842f0b6e535c246baa5b46b962bedf8cab` |
| `ggml-large-v3-turbo.bin` | `1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69` |
| `Latxa-Qwen3-VL-4B-Instruct.Q4_K_M.gguf` | `3eae629d2714189689aa8de1b1d7cfdf8ec846c405b26e4faeeb1fdfa3b4f26b` |
| `ggml-tiny.bin` | `be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21` |

## Provenance notes

- **whisper-large-v3-eu** — a fine-tune of OpenAI's Whisper large-v3 for Basque, published by xezpeleta already converted to GGML for whisper.cpp. Its model card reports a WER of 4.84 on the Common Voice 18 test set (self-reported, against 38.85 for vanilla large-v3). Apache-2.0.
- **large-v3-turbo and tiny** — GGML conversions hosted in the [ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp) repository on Hugging Face (MIT). The original Whisper models are published by [OpenAI](https://github.com/openai/whisper) under MIT.
- **Latxa** — the family of Basque language models built by [HiTZ](https://hitz.ehu.eus/), the language technology center of the University of the Basque Country (UPV/EHU). Upstream model: [HiTZ/Latxa-Qwen3-VL-4B-Instruct](https://huggingface.co/HiTZ/Latxa-Qwen3-VL-4B-Instruct) (Apache-2.0); Mintzo downloads the Q4_K_M GGUF quantization published by [mradermacher](https://huggingface.co/mradermacher/Latxa-Qwen3-VL-4B-Instruct-GGUF). Text-only use: the vision projector (`mmproj`) is not downloaded. The upstream model card is marked as still under development; Mintzo therefore keeps both the raw and the corrected text at all times, and the correction pass is optional.
- **Inference engines** — [whisper.cpp](https://github.com/ggml-org/whisper.cpp) v1.9.1 and [llama.cpp](https://github.com/ggml-org/llama.cpp) build b9862 (both MIT, ggml-org), fetched as prebuilt, SHA256-pinned XCFrameworks by `scripts/fetch-whisper-xcframework.sh` and `scripts/fetch-llama-xcframework.sh`.

Mintzo itself is MIT-licensed (see [LICENSE](../LICENSE)); the licenses above apply to the model files, not to Mintzo's code.
