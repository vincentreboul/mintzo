# Mintzo — Recherche UX & produit (dictée basque/français macOS)

Date : 2026-07-03 · Recherche web (WebSearch + fetch pages officielles) · Rédigé pour cadrer l'UX v1.

**Garde-fou** : chaque affirmation est étiquetée. FAIT = vérifié avec URL (listée en bas). NON CONFIRMÉ = plausible mais pas trouvé de source directe. Aucun chiffre inventé.

---

## 1. Teardown UX des références

### 1.1 Wispr Flow (macOS, cloud) — la référence "invisible dictation"

FAITS (docs.wisprflow.ai, wisprflow.ai, reviews 2026) :
- **Déclenchement** : push-to-talk = **maintenir la touche Fn** (hotkey par défaut, remappable). Mode mains-libres = **Fn+Espace** ou double-tap du raccourci ; on arrête en réappuyant Fn ou en cliquant l'icône stop rouge de la barre.
- **HUD** : "**Flow Bar**" — petite barre flottante en bas au centre de l'écran, avec barres blanches animées (waveform) pendant l'écoute ; cliquable pour stopper. Feedback sonore ("ping") au démarrage.
- **Insertion** : au relâchement de la touche, le texte formaté est collé **directement au curseur de l'app active** (Gmail, Slack, VS Code, n'importe quel champ). Aucune fenêtre intermédiaire.
- **Nettoyage AI** : suppression des "euh", ponctuation, listes, ton adapté par app (casual Slack vs formel email, réglage "Personalized Style" du très décontracté au formel). Lit le contexte de la fenêtre active pour améliorer le formatage (→ envoyé au cloud, critiqué par les reviewers privacy).
- **Langues** : 100+, **auto-détection y compris changement de langue en cours de phrase** ; si l'auto-detect se trompe, on peut le couper et fixer la langue manuellement. Modèle dédié "Hinglish" pour le code-switching hindi/anglais (précédent intéressant pour un mode code-switching eu/fr).
- **Onboarding** : permissions micro + accessibilité ; article support dédié "**re-verify permissions after updating**" → la casse des permissions accessibilité après mise à jour macOS est un point de douleur récurrent assumé.
- **Dictionnaire personnel + snippets** : inclus dès le tier gratuit.
- **Limites** : 100 % cloud, **aucun mode offline** ; ~6 min max par capture ; gratuit plafonné à 2 000 mots/semaine (Mac) ; Pro 15 $/mois (12 $/mois annuel), pas de licence à vie ; "Command Mode" (édition vocale) réservé Pro.

### 1.2 SuperWhisper (macOS, local-first)

FAITS (superwhisper.com, reviews 2026) :
- **Modes** : Custom Modes qui formatent le transcript (chat casual, email, code, prompts custom) et **s'auto-activent selon l'app au premier plan**. Reviewers : c'est LA killer feature.
- **Mode meeting** : capture l'audio système (Zoom/Meet/Teams sans bot), transcrit localement avec labels de locuteurs, produit un résumé.
- **Modèles locaux** : Whisper Tiny → Large-v3-Turbo + Parakeet, tout on-device sur Apple Silicon. Recommandé par défaut : **Large-v3-Turbo (1,6 GB, ~8× plus rapide que Large-v3, WER quasi identique)**. Choix du modèle exposé à l'utilisateur avec taille/vitesse.
- **Historique** : transcripts horodatés, clic sur timestamp pour rejouer l'audio, **re-traitement d'un enregistrement avec un autre mode**. Fichiers déposables : MP3, MP4, WAV, M4A, OGG, OPUS.
- **Prix** : free tier réel (modèles locaux petits illimités : Fast/Nano/Standard) ; Pro 8,49 $/mois ou **249,99 $ lifetime**.
- **Friction signalée** : les enregistrements audio sont écrits par défaut dans **iCloud Documents → sync silencieuse vers le cloud Apple** alors que l'app se vend "local/privé" ; complexité des modes intimidante au premier lancement ; prix lifetime jugé élevé.
- HUD "recording pill" : existence d'une mini-fenêtre d'enregistrement confirmée par les reviews ; position exacte à l'écran NON CONFIRMÉ par mes sources.

### 1.3 MacWhisper (fichiers, local)

FAITS (macwhisper.org, goodsnooze.gumroad.com, reviews 2026) :
- **Upload** : **drag & drop d'un fichier audio/vidéo dans la fenêtre → transcription démarre immédiatement** ; collage d'URL YouTube ; enregistrement direct.
- **Batch** : dossier entier / centaines de fichiers, avec **plusieurs formats d'export sélectionnés simultanément** (ex. TXT + SRT par fichier).
- **Exports** : TXT, SRT, VTT, DOCX, PDF, Markdown, HTML, CSV + envoi direct Notion/Obsidian.
- **Prix** : free tier réel (modèles Tiny/Base) ; Pro **59 € one-time (Gumroad)** ; version Mac App Store "Whisper Transcription" en abonnement (6,99 $/mois, 29,99 $/an, 99,99 $ lifetime) avec moins de features.
- **Friction signalée** : le **double pricing Gumroad vs App Store avec deux noms différents est jugé "confusing on purpose"** (article Medium 2026) ; la dictée système est un ajout secondaire, l'app reste "file-first".

### 1.4 Patterns UX à copier (liste actionnable)

1. **Hold-to-talk par défaut** (touche unique maintenue, remappable) + double-tap = mains-libres. Zéro fenêtre à ouvrir. (Wispr)
2. **HUD pill bas-centre** : waveform animée + états visibles (écoute → traitement → collé), cliquable pour stopper, son discret au start. (Wispr)
3. **Insertion au curseur dans n'importe quelle app** via accessibilité, fallback presse-papier+Cmd-V. La dictée n'a JAMAIS sa propre fenêtre de saisie. (Wispr/SuperWhisper)
4. **Onboarding = 2 écrans de permission** (micro, accessibilité) avec test "dicte ici pour essayer" immédiat + **écran "santé des permissions"** re-vérifiable après chaque mise à jour macOS. (douleur documentée chez Wispr)
5. **Modes par app** (message / email / notes / brut) auto-activés selon l'app active. (SuperWhisper)
6. **Gestionnaire de modèles in-app** : liste curée avec taille/vitesse/qualité, téléchargement avec progression, défaut recommandé selon la RAM du Mac. (SuperWhisper)
7. **Historique horodaté avec re-traitement** (autre modèle/autre mode) sans re-dicter. (SuperWhisper)
8. **Dictionnaire personnel** — crucial en basque : noms propres, toponymes (Azpeitia, Urepel…), déclinaisons. Gratuit, pas premium. (Wispr le donne en free)
9. **Drag & drop fichier → transcription immédiate + batch + exports multiples simultanés** (TXT/SRT/VTT/DOCX/MD). (MacWhisper)
10. **Free tier réel, pas trial** : modèles locaux illimités gratuits, features avancées payantes si un jour monétisé. (SuperWhisper/MacWhisper)

### 1.5 Frictions à éviter (signalées par les users)

- Cloud obligatoire / pas d'offline / abonnement sans lifetime (reproche n°1 à Wispr Flow).
- Envoi du contexte d'écran au cloud sans que l'utilisateur le réalise (Wispr, critiqué privacy).
- Enregistrements audio écrits par défaut dans un dossier synchronisé iCloud alors qu'on promet "local" (SuperWhisper) → Mintzo : stockage local explicite, hors iCloud par défaut.
- Double pricing / double nom d'app selon le canal (MacWhisper) → un seul nom, un seul canal.
- Auto-détection de langue qui se trompe sans issue simple → toujours offrir le verrouillage manuel de langue à 1 clic (Wispr le fait, à garder).
- Plafond de durée de dictée silencieux (6 min Wispr) → si limite technique, l'afficher.

---

## 2. Paysage basque (STT/dictée euskara)

### 2.1 Aditu (Elhuyar) — l'acteur installé

FAITS (aditu.eus, elhuyar.eus, orai.eus) :
- **Ce que c'est** : service web SaaS de reconnaissance vocale d'Elhuyar (motorisé par Orai NLP Teknologiak). Transcription et sous-titrage d'audios/vidéos, fichiers pré-enregistrés ou live, avec éditeur avancé de correction et traduction automatique.
- **Langues** : basque, espagnol, français, anglais, catalan, galicien (6).
- **Prix (aditu.eus, juillet 2026)** : 15 €/heure à la demande ; abonnements 5 h/mois = 60 € (12 €/h), 10 h/mois = 105 € (10,5 €/h), 15 h/mois = 135 € (9 €/h), hors TVA 21 %.
- **Limites vs Mintzo** : SaaS web uniquement — **pas d'app native macOS, pas de traitement local, pas de dictée système au curseur** ; payant à l'heure ; orienté transcription de fichiers/sous-titrage pro (médias, institutions), pas productivité personnelle quotidienne.

### 2.2 Briques open source existantes (à créditer, pas à concurrencer)

FAITS :
- **HiTZ/Aholab (EHU/UPV)** publie sur Hugging Face des **Whisper fine-tunés basque : whisper-tiny-eu → whisper-large-v3-eu, licence Apache-2.0**, entraînés sur Common Voice basque, présentés comme état de l'art ASR euskara. Également xezpeleta/whisper-{small,medium,large-v3}-eu.
- **Aholab / projet ILENIA** : système de reconnaissance vocale basque disponible (annonce aholab.ehu.eus).
- **Common Voice basque** : **~702 h enregistrées / ~472 h validées, ~11 000 locuteurs** (Common Voice Scripted Speech 25.0, Mozilla Data Collective). Campagne communautaire structurée (**gaitu.eus**, marathons d'enregistrement, contributions de phrases par EITB et Argia).
- **MINTZAI (Vicomtech + Aholab + Ametzagaiña + ISEA)** : projet de recherche ELKARTEK de traduction parole↔parole eu↔es ; corpus **mintzai-ST** (~480 h, Parlement basque 2011-2018, CC BY-NC-ND). C'est un corpus/projet de recherche, pas un produit grand public.

### 2.3 Existe-t-il déjà une app Mac locale de dictée basque ?

**Aucune trouvée** (recherches en anglais, basque et espagnol, juillet 2026). Les apps génériques locales (SuperWhisper, Spokenly, OpenWhispr, local-whisper…) annoncent "100+ langues" via Whisper multilingue vanilla, mais aucune ne met en avant le basque ni n'embarque les fine-tunes HiTZ ; qualité euskara du Whisper vanilla non mise en avant par ces apps (WER exact : voir model cards HiTZ, non recopié ici). Statut : NON CONFIRMÉ qu'il n'en existe zéro (impossible de prouver une absence), mais **rien d'indexé sur le web ne ressemble à "Wispr Flow euskaraz"**. La fenêtre est ouverte.

### 2.4 Différenciation Mintzo (synthèse)

| | Aditu (Elhuyar) | Apps Mac génériques | **Mintzo** |
|---|---|---|---|
| Basque | ✔ cœur de cible | Whisper vanilla, non optimisé | ✔ fine-tunes HiTZ (SOTA) |
| Local/privé | ✗ SaaS cloud | ✔ | ✔ 100 % on-device |
| Dictée système au curseur | ✗ (web, fichiers) | ✔ | ✔ |
| Prix | 9–15 €/h | freemium/lifetime | open source gratuit |
| UI en euskara | ✔ | ✗ | ✔ (batua, day one) |

Positionnement en une phrase : *« la dictée niveau Wispr Flow, en euskara, 100 % locale et libre — construite sur les modèles HiTZ et les voix de Common Voice »*.

---

## 3. Communauté bascophone tech — où et comment exister

FAITS :
- **Librezale.eus** : groupe ouvert (fondé 2003) qui localise le logiciel libre en basque (Firefox eu day-one, Mastodon…). Wiki avec guides de localisation. C'est LE gardien des conventions de l'euskara dans le logiciel libre.
- **mastodon.eus** (+ jalgi.eus) : instances Mastodon en basque, localisées par des bénévoles Librezale — le réseau social naturel du lancement.
- **Sustatu.eus** : premier blog/média tech basque (2001), toujours hub d'actus techno euskara.
- **Euskarabildua** (euskarabildua.eus) : conférence annuelle euskara+technologie, **octobre, Donostia**, organisée par Iametza/Ametzagaiña/Argia, très axée souveraineté technologique et logiciel libre ; Common Voice euskara y a été présenté. Le lieu où présenter Mintzo.
- **HiTZ** : centre basque de technologie du langage (EHU), org GitHub/HF active — citer et créditer leurs modèles est à la fois une obligation Apache-2.0 (attribution) et un signal de crédibilité.
- Presse alliée : Argia (rubrique tech), Zuzeu, Behategia (observatoire, a documenté la campagne Common Voice/gaitu.eus).

**Ce qui rend un projet crédible dans cette communauté** (déduit des sources ci-dessus) : UI en euskara batua d'abord (pas une traduction after-thought), licence libre réelle, crédit visible aux travaux HiTZ/Aholab et aux contributeurs Common Voice, terminologie conforme aux usages Librezale, domaine .eus (fondation PuntuEUS), et boucle de retour vers la communauté (inciter à contribuer à Common Voice depuis l'app).

### 5 actions concrètes pour le lancement

1. **Annonce en euskara d'abord** : compte + post sur mastodon.eus, article proposé à Sustatu.eus et Argia. Version FR/EN ensuite.
2. **README + UI euskara batua day one**, terminologie alignée sur les conventions Librezale ; proposer le fichier de localisation à relecture sur Librezale (wiki/forum) — ça transforme les gardiens en co-auteurs.
3. **Crédit visible dans l'app et le README** : "Motorra: HiTZ/Aholab whisper-large-v3-eu (Apache-2.0) · Ahotsak: Mozilla Common Voice-ko boluntarioak" + bouton in-app "Hobetu euskarazko eredua → grabatu Common Voice-en" (boucle communautaire).
4. **Candidater à Euskarabildua (octobre, Donostia)** pour une démo live "diktatu euskaraz zure Mac-ean, konexiorik gabe" ; contacter en parallèle le réseau gaitu.eus/Behategia.
5. **mintzo.eus** (PuntuEUS) + org GitHub dédiée (`mintzo-app` — voir §4, le handle `mintzo` est pris) avec releases signées/notariées et page produit bilingue eu/fr.

---

## 4. Le nom "Mintzo"

FAITS :
- **Sens** : Elhuyar hiztegia (hiztegiak.elhuyar.eus/eu/mintzo) : *mintzo* = **voz / habla** (voix, parole) ; *mintzo izan* = parler. Registre plutôt littéraire/poétique, très présent en Iparralde et dans les textes classiques (« odolaren mintzoa », la voix du sang). Connotation positive, digne — "la voix". Pour une app de dictée FR+EU dont une partie du public est en Pays basque nord, le registre iparralde est un atout.
- **Collisions vérifiées** :
  - **MINTZAI / mintzai-ST (Vicomtech)** : projet de recherche + corpus de traduction vocale eu↔es. Même champ (speech tech basque) mais objet différent (corpus recherche, pas d'app grand public). Collision la plus proche → à désamorcer en citant/distinguant proprement.
  - **Mintzanet / Mintzalaguna** : programmes de pratique conversationnelle du basque (mintzanet.net, collectivités). Domaine différent (apprentissage), confusion faible mais possible ("encore un truc mintza-").
  - **GitHub : le handle `mintzo` est pris** (Omer Mintz, dev israélien, sans rapport) → prendre `mintzo-app`/`mintzoapp`.
  - **App Store / npm : aucune app "Mintzo" trouvée** via recherche web (juillet 2026). NON CONFIRMÉ à 100 % — faire une recherche directe dans l'App Store + dépôt de vérification EUIPO (marque) avant lancement. Pas de recherche de marque effectuée ici.
- **Risques résiduels** : (1) proximité phonétique avec MINTZAI dans le même champ ; (2) famille "mintza-" très utilisée dans l'écosystème euskara — c'est aussi une preuve que le mot est juste.

**Verdict : bon nom.** Signifiant exact ("voix/parole"), prononçable en FR/ES/EN, registre noble, aucun produit concurrent homonyme trouvé. Conditions : sécuriser mintzo.eus + org GitHub alternative, check App Store/EUIPO avant annonce.

---

## 5. macOS 26 "Liquid Glass" — paraître natif et premium en 2026

FAITS (developer.apple.com HIG/WWDC25 "Get to know the new design system", articles dev 2025-2026) :
1. **Le verre uniquement sur la couche fonctionnelle** : Liquid Glass (`.glassEffect()` SwiftUI) est réservé aux contrôles/navigation/UI transitoire ; le **contenu (transcript, historique) reste opaque et lisible**. Jamais de glass sur du texte long, jamais de glass-sur-glass.
2. **Coins concentriques** : les rayons d'arrondi des éléments imbriqués épousent le rayon du conteneur (fenêtres Tahoe = rayons généreux, plus larges avec toolbar). Utiliser les conteneurs système, ne pas hardcoder les radii.
3. **Menu bar transparente + matériaux système** : la barre de menus de Tahoe est transparente → **icône status en template image monochrome** (s'adapte light/dark), popover en matériau système (vibrancy) qui laisse passer la teinte du fond, pas de chrome custom.
4. **Typo et couleurs système** : SF Pro, titres plus gras et alignés à gauche (alertes/onboarding) ; palette système réajustée pour Light/Dark/Increased Contrast → n'utiliser que des couleurs sémantiques, tester dark mode ET "réduire la transparence".
5. Bonus : icône app au format Liquid Glass (Icon Composer) avec variantes dark/tinted — signal "2026-native" immédiat dans le Dock.

---

## 6. Synthèse — les 5 décisions UX v1

1. **Hold-Fn (remappable) + HUD pill bas-centre avec waveform**, insertion au curseur, zéro fenêtre. Double-tap = mains-libres.
2. **Local-first affiché** : modèles HiTZ embarqués/téléchargeables in-app (défaut large-v3-turbo-eu si RAM ok, small-eu sinon), mention "audioa ez da zure Mac-etik ateratzen", stockage hors iCloud par défaut.
3. **Langue = choix explicite EU/FR à 1 clic dans le HUD** (voire un raccourci par langue), auto-détection en option — pas en défaut (l'auto-detect qui se trompe est la friction n°1 des apps multilingues).
4. **Onboarding 3 étapes** (micro → accessibilité → "proba ezazu hemen") + écran santé des permissions re-vérifiable après chaque màj macOS.
5. **Fenêtre historique horodatée avec re-traitement + drag & drop fichiers + exports TXT/SRT/VTT/DOCX/MD** — couvre dictée (Wispr), reprise (SuperWhisper) et fichiers (MacWhisper) dans une seule app.

---

## Sources principales

- Wispr Flow : https://docs.wisprflow.ai/articles/6409258247-starting-your-first-dictation · https://docs.wisprflow.ai/articles/6391241694-use-flow-hands-free · https://docs.wisprflow.ai/articles/3191899797-use-flow-with-multiple-languages · https://docs.wisprflow.ai/articles/5510622673-re-verify-wispr-flow-permissions-after-updating · https://wisprflow.ai/pricing · https://wisprflow.ai/features · https://spokenly.app/blog/wispr-flow-review · https://weesperneonflow.ai/en/blog/2026-02-09-wispr-flow-review-cloud-dictation-2026/
- SuperWhisper : https://superwhisper.com/models · https://superwhisper.com/meeting-transcription · https://superwhisper.com/docs/modes/modes · https://spokenly.app/blog/superwhisper-review · https://metawhisp.com/blog/superwhisper-review/ · https://www.getvoibe.com/resources/best-local-whisper-model-superwhisper/
- MacWhisper : https://macwhisper.org/ · https://goodsnooze.gumroad.com/l/macwhisper · https://www.getvoibe.com/resources/macwhisper-pricing/ · https://lumevoice.com/blog/macwhisper-review-2026/
- Aditu/Elhuyar : https://aditu.eus/ (tarifs relevés le 2026-07-03) · https://www.elhuyar.eus/en/press-room/elhuyar-technologies-enable-translation-transcribing-sub-headline-and-translating-texts-6-languages · https://www.orai.eus/en/successful-cases/aditueus
- Modèles basques : https://huggingface.co/HiTZ/whisper-large-v3-eu · https://huggingface.co/HiTZ/whisper-tiny-eu · https://huggingface.co/xezpeleta/whisper-large-v3-eu · https://aholab.ehu.eus/aholab/ilenia-disponible-el-sistema-de-reconocimiento-de-voz-en-euskera/
- Common Voice eu : https://datacollective.mozillafoundation.org/datasets/cmn2hwe0d01n8mm07wug9r5he · https://behategia.eus/en/urtekaria_artikulua/8-common-voice-a-digital-community-work-for-teaching-basque-to-technology-gaitu-eus/
- MINTZAI : https://github.com/Vicomtech/mintzai-ST · https://www.isea.eus/en/projects/mintzai/
- Communauté : https://librezale.eus/ · https://sustatu.eus/urtzai/1729238756 · https://euskarabildua.eus/ · https://iametza.eus/proiektua/euskarabildua-jardunaldia/ · https://eu.wikipedia.org/wiki/Euskara_eta_ingurune_digitala
- Nom : https://hiztegiak.elhuyar.eus/eu/mintzo · https://github.com/mintzo · https://www.etxepare.eus/en/mintzanet-basque-language-wherever-and-whenever
- Liquid Glass : https://developer.apple.com/videos/play/wwdc2025/356/ · https://developer.apple.com/design/human-interface-guidelines/materials · https://lapcatsoftware.com/articles/2026/3/4.html · https://www.createwithswift.com/liquid-glass-redefining-design-through-hierarchy-harmony-and-consistency/ · https://blakecrosley.com/blog/liquid-glass-swiftui-patterns
