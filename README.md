# Mintzo

**Euskararako eta frantseserako diktaketa eta transkripzioa, % 100 lokala, zure Mac-ean.**

**Euskara** · [Français](README.fr.md) · [English](README.en.md)

## Zer egiten duen

- **Diktaketa sistema osoan.** Laster-tekla globala sakatu, hitz egin, eta testu zuzendua kurtsorean itsasten da, edozein aplikaziotan. Kopia bat arbelean eta historian gordetzen da.
- **Audio-fitxategien transkripzioa.** Arrastatu WhatsAppeko ahots-mezu bat (`.opus`), ahots-ohar bat (`.m4a`), `.mp3` bat edo beste audio-formatu bat: Mintzok transkribatu eta zuzendu egiten du.
- **Euskarazko zuzenketa, lokala.** Transkripzio gordinaz gain, Latxa ereduak ortografia, puntuazioa eta maiuskulak zuzentzen ditu, esanahia aldatu gabe. Bi bertsioak gordetzen dira beti: jatorrizkoa eta zuzendua.
- **Historia.** Transkripzio guztiak leku bakarrean: testu osoko bilaketa, klik bakarrean kopiatu, banaka edo denak ezabatu.
- **Konexiorik gabe.** Ereduak behin deskargatuta, ez da konexiorik behar: hegazkin moduan ere badabil. Telemetriarik ez, konturik ez, harpidetzarik ez.

**Audioa ez da inoiz zure Mac-etik ateratzen.**

## Zergatik

Euskarak lehen mailako tresnak merezi ditu — ingelesak eta frantsesak dituztenen parekoak. Mintzo euskal hizkuntza-teknologien komunitatearen lanaren gainean eraikita dago: HiTZ zentroaren ereduak, Common Voice-ko boluntarioen ahotsak, urteetako lan librea. Helburua xumea da: lan hori eguneroko tresna bihurtzea, doan eta kode irekian, Mac bat duen edozein euskaldunentzat.

## Egoera

Garapen aktiboan; lehen bertsioa eraikitzen ari gara. Oraingoz, iturburutik eraikita bakarrik erabil daiteke: ez dago deskargatzeko bertsiorik oraindik.

Ekarpenak ongi etorriak dira; ikus [CONTRIBUTING.md](CONTRIBUTING.md).

### Iturburutik eraikitzea

Behar dituzu: Apple Silicon duen Mac bat, macOS 15 edo berriagoa, Xcode 26 eta [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
# errepositorioaren erroan
brew install xcodegen
scripts/fetch-whisper-xcframework.sh   # whisper.cpp v1.9.1 (XCFramework)
scripts/fetch-llama-xcframework.sh     # llama.cpp b9862 (XCFramework)
xcodegen generate
open Mintzo.xcodeproj
```

Xcode-n, exekutatu `Mintzo` eskema. Testak pasatzeko, deskargatu aurrez testetarako eredu txikia (`scripts/download-test-model.sh`) eta gero Product ▸ Test (⌘U).

## Nola dabilen

```
audioa — mikrofonoa edo fitxategia
   │
   │  CoreAudio · 16 kHz mono
   ▼
Whisper large-v3, euskarazko doikuntza — whisper.cpp · Metal
   │
   │  transkripzio gordina
   ▼
Latxa 4B (aukeran) — llama.cpp
   │
   │  zuzenketa: ortografia, puntuazioa, maiuskulak
   ▼
testua — kurtsorean itsatsita · arbelean · historian
```

Euskarazko audioak Whisper large-v3ren euskarazko doikuntzarekin transkribatzen dira; frantsesezkoak, large-v3-turbo eredu eleaniztunarekin. Ereduak aplikazioak berak deskargatzen ditu lehen erabileran, behin bakarrik, eta SHA256 bidez egiaztatzen dira. Tamainak: euskarazko eredua 3,1 GB, frantsesezkoa 1,6 GB, Latxa 2,5 GB.

Zuzenketa aukerakoa da: desaktiba daiteke, edo, nahi izanez gero, hodeiko eredu batekin egin, norberaren API gakoa erabilita. Lehenespena beti lokala da, eta audioa ez da inolaz ere igotzen.

## Kredituak

Mintzo lan hauen gainean dago eraikita:

- **[xezpeleta/whisper-large-v3-eu](https://huggingface.co/xezpeleta/whisper-large-v3-eu)** (Apache 2.0) — euskarazko transkripzioaren motorra. Ereduaren txartelaren arabera, % 4,84eko WERa Common Voice 18ko testean, Whisper arruntaren % 38,85en aldean.
- **[HiTZ](https://hitz.ehu.eus/)**, Euskal Herriko Unibertsitateko (UPV/EHU) Hizkuntza Teknologiako Zentroa — **[Latxa](https://huggingface.co/HiTZ/Latxa-Qwen3-VL-4B-Instruct)** euskarazko hizkuntza-ereduen sortzailea (Apache 2.0). Latxa da zuzenketa-pasearen bihotza.
- **[Mozilla Common Voice euskara](https://commonvoice.mozilla.org/eu)** — boluntarioen ahotsekin osatutako corpus askea, euskarazko ahots-teknologiaren oinarria. Zuk ere lagun dezakezu: [grabatu esaldi batzuk](https://commonvoice.mozilla.org/eu).
- **[whisper.cpp](https://github.com/ggml-org/whisper.cpp)** eta **[llama.cpp](https://github.com/ggml-org/llama.cpp)** (ggml-org, MIT) — inferentzia lokala posible egiten duten motorrak.
- **[Librezale](https://librezale.eus/)** — software librea euskaratzen duen taldea. Mintzoren euskarazko testuek haren konbentzioei jarraitzen diete, eta lokalizazioa komunitatearen berrikuspenera zabalik dago.

Baita [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) eta [GRDB](https://github.com/groue/GRDB.swift) Swift liburutegiak ere.

## Bide-orria

1. **V1 — Mac aplikazio natiboa** (orain eraikitzen): diktaketa, fitxategiak, historia.
2. **2. fasea — webgunea**: audioa igo eta linean transkribatzeko; Windows erabiltzaileentzako lehen bidea.
3. **3. fasea — Windows aplikazio natiboa**: motorrak eta ereduak (whisper.cpp, llama.cpp, GGML/GGUF) eramangarriak dira diseinuz, prest daude horretarako.

iOS ez dago gaur egungo bide-orrian.

## Lizentzia

MIT — ikus [LICENSE](LICENSE). Exekuzio-garaian deskargatzen diren ereduek nork bere lizentzia dute; zerrenda osoa eta egiaztapen-datuak: [docs/MODELS.md](docs/MODELS.md).
