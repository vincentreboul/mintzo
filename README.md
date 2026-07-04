# Mintzo

**Dictée et transcription pour l'euskara et le français, 100 % en local sur votre Mac.**

**Français** · [Euskara](README.eu.md) · [English](README.en.md)

*Projet expérimental. Développé par Vincent Reboul, en partenariat avec [Isaak Elduaien](https://github.com/ixak), qui en a eu l'idée et validé la première version.*

**Site et outil en ligne : [www.mintzo.fr](https://www.mintzo.fr)** · **[Télécharger l'app Mac](https://github.com/vincentreboul/mintzo/releases/latest)**

## Ce que fait Mintzo

- **Dictée système.** Un raccourci global, vous parlez, le texte corrigé s'insère au curseur dans n'importe quelle application. Une copie part au presse-papier et dans l'historique.
- **Transcription de fichiers audio.** Glissez un vocal WhatsApp (`.opus`), un mémo vocal (`.m4a`), un `.mp3` ou un autre format audio : Mintzo transcrit et corrige.
- **Correction en euskara, locale.** Au-delà de la transcription brute, le modèle Latxa corrige orthographe, ponctuation et majuscules, sans toucher au sens. Les deux versions sont toujours conservées : l'originale et la corrigée.
- **Historique.** Toutes vos transcriptions au même endroit : recherche plein texte, copie en un clic, suppression unitaire ou totale.
- **Sans connexion.** Une fois les modèles téléchargés, aucune connexion n'est requise : Mintzo fonctionne en mode avion. Pas de télémétrie, pas de compte, pas d'abonnement.

**« Audioa ez da inoiz zure Mac-etik ateratzen. » — l'audio ne quitte jamais votre Mac.**

## Pourquoi

L'euskara mérite des outils de premier rang — au niveau de ceux dont bénéficient l'anglais ou le français. Mintzo est construit sur le travail de la communauté basque des technologies de la langue : les modèles du centre HiTZ, les voix des bénévoles de Common Voice, des années de travail libre. L'objectif est simple : transformer ce travail en outil quotidien, gratuit et open source, pour tout bascophone équipé d'un Mac.

## État

**Projet expérimental, en développement actif.** Née d'une idée d'Isaak Elduaien, développée par Vincent Reboul, cette première version est une preuve de concept ouverte à la communauté.

**[Télécharger la dernière version (zip)](https://github.com/vincentreboul/mintzo/releases/latest)** — Apple Silicon, macOS 15+, build de développement non signé : au premier lancement macOS bloque l'app : Réglages Système › Confidentialité et sécurité › « Ouvrir quand même ». L'outil en ligne : [www.mintzo.fr/tresna](https://www.mintzo.fr/tresna).

Les contributions sont bienvenues ; voir [CONTRIBUTING.md](CONTRIBUTING.md).

### Compiler depuis les sources

Prérequis : un Mac Apple Silicon, macOS 15 ou plus récent, Xcode 26 et [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
# à la racine du dépôt
brew install xcodegen
scripts/fetch-whisper-xcframework.sh   # whisper.cpp v1.9.1 (XCFramework)
scripts/fetch-llama-xcframework.sh     # llama.cpp b9862 (XCFramework)
xcodegen generate
open Mintzo.xcodeproj
```

Dans Xcode, lancez le schéma `Mintzo`. Pour exécuter les tests, téléchargez d'abord le petit modèle de test (`scripts/download-test-model.sh`), puis Product ▸ Test (⌘U).

## Comment ça marche

```
audio — micro ou fichier
   │
   │  CoreAudio · 16 kHz mono
   ▼
Whisper large-v3, affiné pour le basque — whisper.cpp · Metal
   │
   │  transcription brute
   ▼
Latxa 4B (optionnel) — llama.cpp
   │
   │  correction : orthographe, ponctuation, majuscules
   ▼
texte — inséré au curseur · presse-papier · historique
```

L'audio en basque est transcrit avec le fine-tune basque de Whisper large-v3 ; le français, avec le modèle multilingue large-v3-turbo. Les modèles sont téléchargés par l'application elle-même au premier usage, une seule fois, et vérifiés par SHA256. Tailles : modèle basque 3,1 Go, modèle français 1,6 Go, Latxa 2,5 Go.

La correction est optionnelle : elle peut être désactivée, ou, si vous le souhaitez, confiée à un modèle cloud avec votre propre clé API. Le défaut est toujours local, et l'audio n'est jamais envoyé nulle part.

## Crédits

Mintzo est construit sur ces travaux :

- **[xezpeleta/whisper-large-v3-eu](https://huggingface.co/xezpeleta/whisper-large-v3-eu)** (Apache 2.0) — le moteur de transcription basque. D'après la fiche du modèle, WER de 4,84 % sur le test Common Voice 18, contre 38,85 % pour le Whisper standard.
- **[HiTZ](https://hitz.ehu.eus/)**, le centre de technologies de la langue de l'Université du Pays basque (UPV/EHU) — créateur de **[Latxa](https://huggingface.co/HiTZ/Latxa-Qwen3-VL-4B-Instruct)**, la famille de modèles de langue en euskara (Apache 2.0). Latxa est le cœur de la passe de correction.
- **[Mozilla Common Voice euskara](https://commonvoice.mozilla.org/eu)** — le corpus libre constitué des voix de bénévoles, socle des technologies vocales basques. Vous pouvez y contribuer : [enregistrez quelques phrases](https://commonvoice.mozilla.org/eu).
- **[whisper.cpp](https://github.com/ggml-org/whisper.cpp)** et **[llama.cpp](https://github.com/ggml-org/llama.cpp)** (ggml-org, MIT) — les moteurs qui rendent l'inférence locale possible.
- **[Librezale](https://librezale.eus/)** — le collectif qui localise le logiciel libre en basque. Les textes en euskara de Mintzo suivent ses conventions, et la localisation est ouverte à la relecture de la communauté.

Ainsi que les bibliothèques Swift [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) et [GRDB](https://github.com/groue/GRDB.swift).

## Feuille de route

1. **V1 — application Mac native** (en construction) : dictée, fichiers, historique.
2. **Phase 2 — site web** : upload et transcription en ligne ; première réponse pour les utilisateurs Windows.
3. **Phase 3 — application Windows native** : les moteurs et les modèles (whisper.cpp, llama.cpp, GGML/GGUF) sont portables par conception, prêts pour cette étape.

iOS n'est pas dans la feuille de route actuelle.

## Auteurs

- **Vincent Reboul** — conception et développement
- **[Isaak Elduaien](https://github.com/ixak)** — idée d'origine et validation de la première version

## Licence

MIT — voir [LICENSE](LICENSE). Les modèles téléchargés à l'exécution conservent leurs licences respectives ; liste complète et données de vérification : [docs/MODELS.md](docs/MODELS.md).
