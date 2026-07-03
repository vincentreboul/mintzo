# Recherche ASR basque + français — local Apple Silicon (Mintzo)

Date recherche : 2026-07-03. Méthode : chaque ID de modèle ci-dessous a été **vérifié via l'API Hugging Face** (`https://huggingface.co/api/models/<id>`) le 2026-07-03 — existence, date de mise à jour, licence et métriques `model-index` extraites verbatim. Les WER proviennent des cards HF ou du papier cité. Ce qui n'a pas pu être confirmé est marqué **NON CONFIRMÉ**.

## TL;DR — Reco

**Stratégie 2 modèles + routing par langue, moteur unique whisper.cpp (Metal) :**

1. **Basque : `xezpeleta/whisper-large-v3-eu`** — WER 4.84 sur Common Voice 18 (test), Apache-2.0, et le repo **contient déjà le fichier GGML** (`ggml-large-v3.eu.bin`) → chargeable tel quel dans whisper.cpp, zéro conversion.
2. **Français : `openai/whisper-large-v3-turbo`** vanille (GGML officiel dispo) — WER fr ≈ 7.7 % (benchmark communautaire int8), ~5× plus rapide que large-v3.
3. **Routing** : sélecteur de langue manuel en V1 (toggle/raccourci). L'auto-détection est possible (Whisper détecte la langue) mais un mauvais routage vers le modèle eu monolingue produit du charabia en français → le toggle manuel est le choix fiable.

Un seul modèle pour les deux langues n'existe pas à qualité acceptable : le fine-tuning monolingue basque dégrade les autres langues (catastrophic forgetting, documenté), et les modèles vanille sont inutilisables en basque (WER 38.85 pour large-v3).

---

## 1. Candidats basque — tableau vérifié

| Modèle (ID HF exact) | Base | WER eu (test set) | Màj | Licence | Formats dispo | URL |
|---|---|---|---|---|---|---|
| **xezpeleta/whisper-large-v3-eu** | whisper-large-v3 | **4.84 (CV 18.0 test)** ; 6.54 (val. composite) | 2025-02-26 | apache-2.0 | HF safetensors + **GGML inclus** (`ggml-large-v3.eu.bin`, `ggml-large.eu.bin`) | https://huggingface.co/xezpeleta/whisper-large-v3-eu |
| xezpeleta/whisper-large-v3-eu-ct2 | ↑ (même modèle) | 4.84 (CV 18.0) | 2025-02-26 | apache-2.0 | CTranslate2 (faster-whisper, Python) | https://huggingface.co/xezpeleta/whisper-large-v3-eu-ct2 |
| xezpeleta/whisper-{tiny,base,small,medium}-eu (+ -ct2, -ct2-int8) | tailles Whisper | non relevé ici (série complète existe) | 2025 | apache-2.0 | HF + CT2 | https://huggingface.co/xezpeleta |
| **HiTZ/whisper-large-v3-eu** (≡ zuazo/whisper-large-v3-eu, mêmes runs d'entraînement) | whisper-large-v3 | 10.62 (CV 13.0 test) | 2025-12-16 (HiTZ) / 2025-04-04 (zuazo) | apache-2.0 | HF transformers seulement | https://huggingface.co/HiTZ/whisper-large-v3-eu |
| zuazo/whisper-large-v2-eu | whisper-large-v2 | 11.34 (CV 13.0 test) | 2025-04-04 | apache-2.0 | HF seulement | https://huggingface.co/zuazo/whisper-large-v2-eu |
| HiTZ/whisper-{tiny→large}-eu (série) | tailles Whisper | 32.27 (tiny) → 10.62 (large-v3), CV 13.0 | 2025 | apache-2.0 | HF seulement | https://huggingface.co/HiTZ |
| **itzune/parakeet-tdt-0.6b-v3-basque** (≡ xezpeleta/parakeet-tdt-0.6b-v3-basque) | nvidia/parakeet-tdt-0.6b-v3 | 6.92 (test_cv) / 4.36 (test_parl) / 14.52 (test_oslr) | **2026-03-08** | cc-by-4.0 | `.nemo` + ONNX (`-onnx-asr`) + **export sherpa-onnx prêt** (`-sherpa-onnx`) | https://huggingface.co/xezpeleta/parakeet-tdt-0.6b-v3-basque |
| **HiTZ/stt_eu_conformer_transducer_large_v2** | NeMo Conformer | **2.5 (CV 18.0 test)** / 3.78 (Parlement) / 11.87 (OpenSLR) / 9.17 (EITB) | **2026-03-31** | apache-2.0 | `.nemo` seulement | https://huggingface.co/HiTZ/stt_eu_conformer_transducer_large_v2 |
| HiTZ/stt_eu_conformer_ctc_large / _transducer_large (v1) | NeMo Conformer | 2.42 / 2.79 (CV 16.1 test) | 2025-11-28 | apache-2.0 | `.nemo` (+ KenLM pour le CTC) | https://huggingface.co/HiTZ/stt_eu_conformer_ctc_large |

Notes de provenance :
- **zuazo = Xabier de Zuazo (UPV/EHU)**, auteur du papier *Whisper-LM: Improving ASR Models with Language Models for Low-Resource Languages* (arXiv:2503.23542, co-auteurs Navas/Saratxaga/Hernáez = groupe **Aholab**). Les modèles zuazo/* et HiTZ/whisper-*-eu sont les modèles de ce papier (fine-tune CV13). La piste "Aholab" débouche donc sur les modèles HiTZ/zuazo — il n'existe **pas** d'org HF "aholab" ni "asierhv" avec des modèles (vérifié : 0 modèles ; `asierhv` héberge le **dataset** `composite_corpus_eu_v2.1`, gated, qui sert d'entraînement aux modèles xezpeleta).
- `HiTZ/whisper-lm-ngrams` existe : les LM n-gram du papier Whisper-LM pour re-scorer la sortie Whisper (gain WER supplémentaire dans le papier). Intégration non triviale dans whisper.cpp → backlog V2.
- Les conformers HiTZ ont le meilleur WER absolu (2.5 sur CV18) mais format `.nemo` uniquement → **aucun chemin Swift/Apple Silicon raisonnable** (NeMo = Python/CUDA-first). Écartés pour Mintzo.

## 2. Baselines vanille (pourquoi le fine-tune est indispensable)

| Modèle vanille | WER basque | Source |
|---|---|---|
| whisper-large-v3 | **38.85 (CV 13)** | papier Whisper-LM, arXiv:2503.23542 |
| whisper-tiny | 97.93 (CV 13) | idem |
| whisper-large-v3-turbo | **NON CONFIRMÉ** (aucun chiffre publié trouvé) ; attendu ≥ large-v3 (décodeur 4 couches vs 32, faiblesse connue sur langues low-resource) | — |
| parakeet-tdt-0.6b-v3 | > 100 % (ne connaît pas le basque ; 25 langues européennes, **eu absent de la liste**) | card nvidia + card fine-tune xezpeleta |
| whisper-large-v3-turbo (français) | ≈ 7.7 % WER (benchmark int8 batché) | discussion HF deepdml/faster-whisper-large-v3-turbo-ct2 |

Conclusion : fine-tune basque = division du WER par ~8 (38.85 → 4.84). Non négociable.

## 3. Question critique : le fine-tune eu dégrade-t-il le français ? OUI (présumé fortement)

- Les fine-tunes basques listés sont **monolingues** (`language: [eu]`, entraînement 100 % basque). Aucune éval française publiée sur ces modèles (**NON CONFIRMÉ** chiffré), mais le phénomène générique est bien documenté :
  - Fine-tune Whisper 100 % yoruba → WER anglais passe de 21.84 à **147.09** (catastrophic forgetting) — medium.com/@ccibeekeoc42 (Hypa AI).
  - Études du forgetting multilingue sur Whisper et mitigations (LoRA, rehearsal) : arXiv:2408.10680, arXiv:2506.21555, Springer s13636-024-00349-3.
- **Confirmation de la stratégie 2 modèles + routing** : basque → fine-tune eu ; français → turbo vanille. Ne jamais envoyer du français dans le modèle eu.
- Routing V1 : toggle manuel (fiable, coût nul). Auto-détection possible plus tard (passe de détection langue Whisper, ou heuristique) mais erreur de routage = transcription poubelle → à tester sérieusement avant d'activer.

## 4. Alternatives non-Whisper

| Modèle | Basque ? | Apple Silicon / Swift ? | Verdict |
|---|---|---|---|
| **NVIDIA Parakeet TDT 0.6b v3** | Non (25 langues eu. sans basque) — **mais fine-tune basque communautaire existe** (itzune/xezpeleta, 2026-03) | Base v3 : oui via **FluidAudio** (Swift, CoreML/ANE) ; fine-tune basque : ONNX/sherpa-onnx (API Swift, CPU only, pas de conversion CoreML publiée) | **Plan B crédible pour le basque** si la latence Whisper déçoit : très rapide, WER 6.92 test_cv. Mais stack additionnelle |
| Meta MMS (facebook/mms-1b-all) | Oui (eus, via adapters, 1162 langues) | Non (PyTorch/transformers ; pas de port Swift/CoreML) | Écarté : **licence CC-BY-NC-4.0** (non commercial), WER eu non publié, pas de runtime Mac |
| Kyutai STT (stt-1b-en_fr / stt-2.6b-en) | Non (en+fr uniquement) | Oui (MLX existe) | Option streaming pour le **français** seulement ; n'aide pas le basque → complexité inutile en V1 |
| Moonshine | Non (en, es, zh, ja, ko, vi, uk, ar — ni fr ni eu) | — | Écarté |
| OWSM (espnet) | Support eu **NON CONFIRMÉ** dans mes recherches ; runtime = Python/espnet, pas de port Swift | Non | Écarté |
| Conformers NeMo HiTZ | Oui (meilleur WER : 2.5 CV18) | Non (`.nemo` only) | Écarté malgré la qualité — surveiller un éventuel export ONNX futur |

## 5. Formats & toolchains de conversion

- **whisper.cpp (GGML)** : `xezpeleta/whisper-large-v3-eu` fournit **déjà** `ggml-large-v3.eu.bin` → aucun travail. Pour tout autre fine-tune HF : `models/convert-h5-to-ggml.py` est **officiellement documenté pour les fine-tunes HF** (section "Fine-tuned models" de whisper.cpp/models/README.md). Quantization q5/q8 possible ensuite (`quantize`).
- **WhisperKit (CoreML/ANE)** : aucun CoreML basque pré-converti trouvé. Conversion custom **documentée** : `whisperkit-generate-model --model-version <repo-hf>` (argmaxinc/whisperkittools), puis chargement Swift via `WhisperKitConfig(modelRepo:)`. Faisable mais étape + validation qualité à prévoir.
- **MLX** : `mlx-examples/whisper/convert.py` vise les checkpoints format OpenAI ; un fine-tune HF demande une conversion intermédiaire → chemin le moins direct. Secondaire.
- **CTranslate2** : variantes `-ct2` prêtes (faster-whisper) — utile pour prototyper en Python, pas pour l'app Swift.
- **Parakeet basque** : `.nemo` + ONNX + **export sherpa-onnx prêt à l'emploi** ; sherpa-onnx a des bindings Swift (CPU). FluidAudio ne couvre que le parakeet v3 de base (pas le fine-tune).

## 6. Vitesse attendue sur M4 (whisper.cpp Metal, chiffres publics)

| Modèle | RTF approx. |
|---|---|
| large-v3 fp16 (→ le fine-tune eu) | **~2.6× temps réel sur M4 base** (justvoice.ai benchmark M1→M4) ; M2 Pro ~2.5×, plus sur M4 Pro/Max | 
| large-v3-turbo (français) | ~5× plus rapide que large-v3 (whispernotes.app) ; M2 Pro : 60 s d'audio en ~2.8 s avec flash attention | 
| small q5 | ~12× (M4) |
| Parakeet v3 CoreML | ~10× plus rapide que Whisper large-v3-turbo (whispernotes.app, 35 min d'audio) |

Pour de la dictée (clips courts) : large-v3-eu à ~2.6× RT = 10 s d'audio en ~4 s. Utilisable mais pas instantané ; le français turbo sera quasi instantané. **Il n'existe pas de fine-tune turbo basque** (vérifié dans les listings xezpeleta/HiTZ/zuazo) → si la latence basque gêne, options : quantizer le GGML eu (q5), tester `xezpeleta/whisper-medium-eu`, ou basculer sur Parakeet basque via sherpa-onnx.

## 7. Risques

1. **Éval single-source** : le 4.84 CV18 de xezpeleta est auto-rapporté, sans leaderboard indépendant. Le parakeet basque montre 14.5 sur OpenSLR vs 4.36 Parlement → forte variance par domaine. **Action : bench maison sur vrais enregistrements (micro Mac, dialecte réel)** avant de figer le choix — Common Voice eu = surtout batua lu, pas de la parole spontanée dialectale.
2. **Routage = point de fiabilité central** : le modèle eu monolingue produira du texte inutilisable si on lui envoie du français (et réciproquement turbo est mauvais en basque). Toggle manuel V1, auto-détection seulement après tests.
3. **Latence basque** : pas de turbo-eu ; ~2.6× RT sur M4 base peut décevoir sur dictées longues. Mitigations listées en §6.
4. **Licences OK** (apache-2.0 / cc-by-4.0 avec attribution) sauf MMS (NC, exclu). Attribution xezpeleta/NVIDIA à prévoir dans l'app.
5. **NON CONFIRMÉS** : WER turbo vanille en basque ; WER français exact des fine-tunes eu ; qualité MMS eu ; support eu d'OWSM.

## Sources principales (fetchées le 2026-07-03)

- https://huggingface.co/xezpeleta/whisper-large-v3-eu (+ /api/models/… pour métriques, fichiers, licence)
- https://huggingface.co/xezpeleta/whisper-large-v3-eu-ct2 · https://huggingface.co/xezpeleta/parakeet-tdt-0.6b-v3-basque · https://huggingface.co/xezpeleta/parakeet-tdt-0.6b-v3-basque-onnx-asr · https://huggingface.co/xezpeleta/parakeet-tdt-0.6b-v3-basque-sherpa-onnx
- https://huggingface.co/HiTZ/whisper-large-v3-eu · https://huggingface.co/HiTZ/stt_eu_conformer_transducer_large_v2 · https://huggingface.co/HiTZ/stt_eu_conformer_ctc_large · https://huggingface.co/zuazo/whisper-large-v3-eu · https://huggingface.co/zuazo/whisper-large-v2-eu
- Papier Whisper-LM (baselines vanille eu) : https://arxiv.org/abs/2503.23542
- Parakeet v3 (langues) : https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
- MMS : https://huggingface.co/facebook/mms-1b-all (licence cc-by-nc-4.0 vérifiée via API)
- Kyutai STT : https://kyutai.org/stt/ · https://huggingface.co/kyutai/stt-2.6b-en — Moonshine : https://github.com/moonshine-ai/moonshine
- Catastrophic forgetting : https://medium.com/@ccibeekeoc42/advancing-multilingual-speech-recognition-fine-tuning-whisper-for-enhanced-low-resource-34529b525f90 · https://arxiv.org/abs/2408.10680 · https://arxiv.org/pdf/2506.21555 · https://link.springer.com/article/10.1186/s13636-024-00349-3
- Conversion : https://github.com/ggml-org/whisper.cpp (models/README.md, convert-h5-to-ggml.py) · https://github.com/argmaxinc/whisperkittools · https://github.com/ml-explore/mlx-examples (whisper/convert.py)
- Vitesse Apple Silicon : https://justvoice.ai/blog/whisper-benchmark-apple-silicon-m3-m4 · https://whispernotes.app/blog/parakeet-v3-default-mac-model · https://getspeakup.app/blog/whisper-cpp-benchmark-mac/
- Runtimes Swift : https://github.com/FluidInference/FluidAudio · https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml · sherpa-onnx Swift : https://carlosmbe.medium.com/running-speech-models-with-swift-using-sherpa-onnx-for-apple-development-d31fdbd0898f
