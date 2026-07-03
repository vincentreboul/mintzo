# Mintzo — Design Language

Statut : v1.1 — 2026-07-03. Document de référence unique pour toute décision visuelle.

> **Amendement v1.2 (feedback Vincent, 15:21 — « ressemble à une app web packagée, loin de Wispr/SuperWhisper »)** : le CHROME doit être 100 % natif macOS. Fond de fenêtre = système (`windowBackgroundColor`/vibrancy), jamais `MzPaper` en pleine fenêtre ; boutons = styles système (`.borderedProminent`/`.bordered` teintés par accentColor Gorri), jamais de boutons custom ; toolbar unifiée native ; Form/GroupBox natifs. **Le papier/encre est réservé aux SURFACES DE LECTURE** (cellules d'historique, corps de transcription, zone d'essai) — c'est là que vit l'identité éditoriale, avec la serif. Référence de feel : SuperWhisper/Wispr Flow. Le HUD (verre réel) et les accents Gorri sont inchangés.
>
> **Amendement v1.1 (décision Vincent, 15:14)** : l'identité s'ancre désormais dans un **symbole basque explicite** — un **lauburu réinterprété typographiquement** (quatre virgules serif en rotation : la ponctuation de la parole). Il devient LA marque : icône app, favicon, logo du site (cohérence exigée entre les trois). L'option « piment de Bayonne » a été écartée (trop localisée pour un outil pan-basque) mais reste réévaluable à la validation de la charte par Vincent, qui se fait sur la production du site. La règle « pas de folklore plaqué » du §1 est amendée : le symbole est assumé, son exécution reste éditoriale (jamais de clipart). Le glyphe caret-et-ondes (§5.1) est conservé UNIQUEMENT comme icône fonctionnelle de menu bar. Assets : `web/app/static/brand/` + `Resources/AppIcon.icns` + SPEC de la marque.
Cible : macOS 26 « Liquid Glass » (SwiftUI, Swift 6), fallback matériaux macOS 15.
Règles absolues héritées de la spec : **zéro emoji dans l'UI** (SF Symbols + typographie uniquement), contenu opaque / verre réservé à la couche fonctionnelle, couleurs testées Light + Dark + Increased Contrast + Reduce Transparency.

---

## 1. Positionnement visuel

Mintzo est une maison d'édition, pas un gadget de productivité : ce que tu dictes est **composé** comme une page imprimée, pas loggé comme un event. L'app emprunte au livre basque contemporain (Susa, Elkar, les couvertures d'Argia) sa retenue : papier chaud, encre profonde, un seul rouge — celui des pans de bois des etxeak — utilisé avec parcimonie et précision. L'identité basque est structurelle, jamais décorative : elle vit dans la langue (euskara batua day one), dans les noms des tokens, dans le rouge architectural, dans le rythme respiré du motion — aucun lauburu, aucune ikurriña, aucun folklore. Le caractère vient de trois choses : une vraie hiérarchie typographique serif/sans, un rouge tranché sur des neutres chauds, et un motion calme qui respire au lieu de vibrer. L'objectif mesurable : posé à côté de Wispr Flow, Mintzo doit paraître plus **édité** — plus silencieux, plus précis, plus sûr de lui.

**3 mots-clés directeurs** (à invoquer à chaque arbitrage) :

| Mot-clé | Sens | Application concrète |
|---|---|---|
| **Tinta** (encre) | typographie d'abord, contrastes francs | serif New York pour le texte dicté, neutres chauds encre/papier, hairlines 0.5 pt |
| **Arnasa** (souffle) | le motion respire, jamais nerveux | pulsations ≥ 3 s, springs amortis, zéro bounce, référence aux *arnasguneak* |
| **Harria** (pierre) | solidité, densité, rien de flottant | surfaces opaques, dimensions stables (le HUD ne « jitter » jamais), ombres courtes |

---

## 2. Palette

### 2.1 Principe

Neutres **chauds** (axe papier/encre, jamais le gris bleuté tech par défaut) + **un seul accent**. Le texte courant utilise les couleurs custom ci-dessous ; les contrôles standards (boutons, toggles, focus rings des Settings) restent teintés par `accentColor` = Gorri pour hériter gratuitement des états système.

### 2.2 Accent principal — le rouge décidé

**Gorri Etxea `#9B2D23` (light) / `#D96A5B` (dark).**
Justification : c'est le rouge oxblood des colombages et volets des fermes labourdines — un rouge *architectural* et domestique, immédiatement basque pour qui connaît, simplement élégant pour qui ne connaît pas ; il est profond et mat là où le rouge « recording » universel est criard, donc il peut porter la marque ET l'enregistrement sans agressivité. Un vert sombre a été écarté : il lit « fintech/Spotify » et n'a aucun ancrage culturel comparable.

Conséquence assumée : **le moment d'enregistrement est le moment de marque** — la waveform bat en Gorri. L'erreur, elle, utilise `systemRed` (plus vif, plus froid) : les deux rouges ne se confondent pas (profond/mat vs saturé/alarmant) et l'erreur reste conventionnelle.

### 2.3 Tokens

Noms d'assets Swift entre parenthèses. Déclarer chaque couleur dans `Assets.xcassets` avec variantes Any/Dark (+ High Contrast).

| Rôle | Token | Light | Dark |
|---|---|---|---|
| Fond fenêtre | `MzPaper` | `#FAF9F7` | `#171614` |
| Surface (cellules, cartes) | `MzSurface` | `#FFFFFF` | `#201E1C` |
| Surface survolée | `MzSurfaceHover` | `#F3F1ED` | `#2A2825` |
| Séparateur hairline | `MzHairline` | `#1C1B1A` à 8 % | `#F2F0ED` à 8 % |
| Texte primaire (encre) | `MzInk` | `#1C1B1A` | `#F2F0ED` |
| Texte secondaire | `MzInkSecondary` | `#6B6560` | `#A39D95` |
| Texte tertiaire / placeholders | `MzInkTertiary` | `#9B948C` | `#6E6862` |
| **Accent principal** | `MzGorri` | `#9B2D23` | `#D96A5B` |
| **Accent enregistrement (live)** | `MzGorriBizi` | `#B5382B` | `#E87A66` |
| Succès | `MzSuccess` | `#3E7A4E` | `#86C29A` |
| Erreur | *(système)* | `systemRed` | `systemRed` |
| Avertissement (permissions) | *(système)* | `systemOrange` | `systemOrange` |

Contrastes vérifiés à la conception (à re-mesurer en QA) : `MzInk`/`MzPaper` ≈ 15:1, `MzInkSecondary`/`MzPaper` ≥ 5:1, `MzGorri` sur `MzPaper` ≥ 7:1, `MzGorri (dark)` sur `#171614` ≥ 5:1 — tout texte accentué passe AA.

### 2.4 Déclinaisons d'opacité de l'accent

S'appliquent à `MzGorri` (ou `MzGorriBizi` en contexte live). Ne jamais inventer d'autres paliers.

| Opacité | Usage |
|---|---|
| 100 % | texte accentué, icônes actives, barres de waveform, barre de progression |
| 85 % | fill de bouton principal en hover/pressed |
| 24 % | bordure d'élément actif (badge langue sélectionné, focus custom) |
| 12 % | fond teinté : badge langue, wash de succès sur le HUD, sélection de ligne |
| 8 % | hover subtil sur éléments accentués, fond de tag au repos |

### 2.5 Règles matériaux (Liquid Glass)

- **Verre uniquement sur la couche fonctionnelle** : HUD, toolbar, popover menu bar, overlay de drop. Jamais sur l'historique ni le corps de transcription (contenu = opaque sur `MzPaper`/`MzSurface`).
- Jamais de glass-sur-glass ; rayons concentriques : utiliser les conteneurs système, ne pas hardcoder les radii de fenêtre.
- `Reduce Transparency` activé → tout matériau tombe sur `MzSurface` opaque + hairline. À tester explicitement.
- Dark mode ≠ inversion : les neutres chauds sont redéfinis (tableau ci-dessus), l'accent est éclairci et désaturé, jamais le même hex.

---

## 3. Typographie

### 3.1 Les deux voix

- **SF Pro** (`.system`) : toute la chrome UI — contrôles, méta, réglages, HUD. Design par défaut d'optical size, graisses ci-dessous.
- **New York** (`.system(design: .serif)`) : **exclusivement le texte dicté** (extraits en liste, corps de transcription). C'est LE geste éditorial : la parole de l'utilisateur est typographiée comme un livre, la machinerie reste en sans. Aucun autre usage de la serif dans l'app.
- Chiffres : `monospacedDigit()` obligatoire partout où un nombre change (timer, durées, compteurs, progression) — aucun jitter de layout.

### 3.2 Hiérarchie exacte

| Contexte | Fonte | Taille / interligne (pt) | Graisse | Détails |
|---|---|---|---|---|
| **HUD — badge langue** | SF Pro Text | 11 / — | Semibold | small caps (`.lowercaseSmallCaps` sur texte « eu »/« fr »), tracking +0.6 pt |
| **HUD — timer** | SF Pro Text | 11 / — | Medium | monospacedDigit, `MzInkSecondary` |
| **HUD — label d'état** | SF Pro Text | 12 / — | Medium | « Transkribatzen… », ellipse typographique `…` |
| **Historique — extrait dicté** | New York | 15 / 22 | Regular | 2 lignes max, truncation `.tail`, `MzInk` |
| **Historique — ligne méta** | SF Pro Text | 11 / 14 | Regular | `MzInkSecondary` ; tag langue en small caps Semibold |
| **Historique — en-tête de section (date)** | SF Pro Text | 11 / 13 | Semibold | SMALL CAPS, tracking +1.0 pt, `MzInkSecondary` |
| **Corps transcription (détail)** | New York | 16 / 26 | Regular | mesure max 640 pt (~68 caractères), sélectionnable |
| **Titre de fenêtre / navigation** | SF Pro Display | 15 / 20 | Semibold | standard toolbar |
| **Réglages — corps** | SF Pro Text | 13 / 16 | Regular | HIG standard (`Form` native) |
| **Réglages — notes de bas de section** | SF Pro Text | 11 / 14 | Regular | `MzInkTertiary` |
| **Onboarding — titre** | SF Pro Display | 28 / 34 | Bold | aligné à gauche (convention Tahoe) |
| **Onboarding — corps** | SF Pro Text | 15 / 22 | Regular | mesure max 460 pt |

### 3.3 Fonte display — wordmark « Mintzo » uniquement

Usage strictement limité : wordmark (onboarding écran 1, About, site, DMG). Jamais dans l'UI courante. Trois candidates, toutes licence SIL OFL :

1. **Fraunces** (undercase.xyz, variable) — **recommandée**. Old-style display avec ink traps et axes optiques ; en Black à grand corps, ses empattements presque taillés évoquent la lettre lapidaire basque (stèles, linteaux) *sans jamais l'imiter*. Chaleureuse, imprimée, très 2026-éditorial.
2. **Young Serif** (Bastien Sozeau) — humaniste massive, dessin robuste « gravé », excellent en un seul mot ; moins de finesse optique que Fraunces, pas de variable.
3. **Instrument Serif** — élégante et tranchante, très contemporaine ; risque de sur-exposition (déjà beaucoup vue en 2025-26), garder en plan B.

Spec wordmark : `Mintzo` (capitale initiale), Fraunces opsz 144 / Black (900), tracking −1 %, `MzInk` sur `MzPaper` (ou papier sur Gorri pour les assets marketing). Le « o » final peut recevoir le point-voix de l'icône (cf. §8) dans les déclinaisons marketing — jamais dans l'app.

### 3.4 Micro-typographie (non négociable)

- Ellipse `…` (U+2026), jamais `...` ; apostrophe typographique `'` (U+2019).
- FR : espace fine insécable (U+202F) avant `: ; ! ?` et à l'intérieur des guillemets `« »`. EU : ponctuation collée (usage espagnol), guillemets `« »` acceptés (convention Librezale).
- Aucune capitalisation Title Case en fr/eu : phrases en bas de casse (« Copier le texte », pas « Copier Le Texte »).
- Durées : `0:42`, `12:07` (pas de « s » ni « min » en méta) ; dates relatives en toutes lettres (« gaur », « atzo », « aujourd'hui », « hier »).

---

## 4. HUD de dictée — la pièce maîtresse

Une **capsule** flottante bas-centre. Personnalité : un instrument de mesure calme — un sismographe qui écrit ta voix — pas un gadget qui gesticule.

### 4.1 Conteneur

| Propriété | Valeur |
|---|---|
| Fenêtre | `NSPanel` non-activant (`.nonactivatingPanel`), `level = .statusBar`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, ignore le cycle Cmd-Tab |
| Hauteur | **36 pt** constante (tous états) |
| Rayon | **18 pt** (capsule parfaite) |
| Largeur | variable par état (cf. 4.3), morphing animé — jamais de reflow interne visible |
| Matériau macOS 26 | `.glassEffect(.regular, in: Capsule())` |
| Fallback macOS 15 | `NSVisualEffectView` `material: .hudWindow`, `blendingMode: .behindWindow`, masqué en capsule |
| Reduce Transparency | fond opaque `MzSurface` + hairline |
| Bordure | hairline 0.5 pt — light : noir 8 % ; dark : blanc 12 % |
| Ombre | `y = 8`, `blur = 24`, noir 20 % (light) / 35 % (dark) |
| Padding horizontal interne | 14 pt ; espacement inter-éléments 10 pt |
| Position | centré horizontalement ; `y = visibleFrame.minY + 24 pt` (24 pt au-dessus du Dock, du bord si Dock masqué) ; **écran du champ texte actif** (via AX focus), fallback écran du pointeur |
| Interaction | clic n'importe où sur la capsule = stop (en écoute) ; la capsule ne vole jamais le focus |

### 4.2 Contenu en écoute (état de référence, 208 × 36 pt)

```
( [eu]  ▂▄▆▃▁▂▅▇▄▂▁▃▄▂▆▄▃▁▂▄▅▃▂▁▄▂   0:42 )
  badge          waveform 26 barres        timer
```

- **Badge langue** : rounded rect 24 × 20 pt, rayon 6 pt, fond `MzGorri` 12 %, texte « eu »/« fr » small caps 11 pt Semibold `MzGorri`. Mode auto-détection : badge affiche « a→ » (petites caps « a » + flèche) en `MzInkSecondary` tant que la langue n'est pas déterminée, puis bascule sur la langue détectée en Gorri.
- **Waveform** — spec exacte :
  - **26 barres verticales**, largeur **2 pt**, gap **2 pt** (zone 102 pt), extrémités arrondies (mini-capsules).
  - Hauteur : min **3 pt** (silence = rangée de points), max **22 pt**, ancrage centré vertical.
  - Couleur : `MzGorriBizi` 90 % ; barres de silence à 28 %.
  - **Animation : historique défilant** (sismographe) — une nouvelle barre entre à droite toutes les **66 ms** (≈ 15 barres/s), translation continue vers la gauche, la barre sortante fade sur ses 8 derniers pt. Amplitude = RMS du buffer sur la fenêtre de 66 ms, mappée log entre 3 et 22 pt, lissée par interpolation linéaire 66 ms. Jamais de barres aléatoires décoratives : la forme doit être la voix.
  - Justification vs « danse sur place » (Wispr) : le défilement écrit le temps de gauche à droite — métaphore exacte de la dictée (la parole devient ligne), et signature visuelle immédiatement différenciante.
- **Timer** : `m:ss`, 11 pt Medium monospacedDigit, `MzInkSecondary`. Si limite technique de durée → afficher le décompte des 30 dernières secondes en `MzGorri` (jamais de plafond silencieux).

### 4.3 États (largeurs, contenu, transitions)

| # | État | Largeur | Contenu | Entrée/sortie |
|---|---|---|---|---|
| 0 | **Repos / armé** (hotkey pressé, micro s'ouvre, < 300 ms) | 208 pt | badge + 26 points (3 pt, 28 %) + `0:00` | apparition : scale 0.85→1 + fade 0→1, spring 180 ms |
| 1 | **Écoute** | 208 pt | cf. 4.2 ; halo `MzGorriBizi` 12 % derrière la capsule respire (cf. §7) | continue depuis 0 (les points prennent vie, pas de nouvelle transition) |
| 2 | **Transcription** | 156 pt | barres s'affaissent à 3 pt et fusionnent en **un trait continu 2 pt** (largeur 40 pt) traversé par une onde de luminosité (shimmer 1.1 s, linéaire, boucle) + label « Transkribatzen… » 12 pt Medium | morph 240 ms |
| 3 | **Correction** (si activée) | 156 pt | même trait-shimmer ; label devient « Zuzentzen… » ; badge inchangé | crossfade label 160 ms |
| 4 | **Insertion réussie** | 112 pt | SF Symbol `checkmark` 13 pt Semibold `MzSuccess` + label « Itsatsita » 12 pt Medium ; wash `MzGorri` 12 % balaye la capsule (300 ms) | tient **600 ms** puis sortie : scale →0.92 + fade, easeIn 220 ms |
| 5 | **Erreur** | max 320 pt | SF Symbol `exclamationmark.triangle` 13 pt `systemRed` + message court (1 ligne, truncation milieu) ; hairline passe `systemRed` 40 % | persiste **4 s** ou jusqu'au clic (clic = ouvre la fenêtre principale sur le détail de l'erreur) ; sortie idem 220 ms |

Morphing de largeur entre états : spring `response 0.32, damping 0.8` — le contenu sortant fade-out 120 ms AVANT le resize, le contenu entrant fade-in 160 ms après ; jamais deux textes visibles simultanément.

En **hold-to-talk**, le relâchement de la touche déclenche directement 1→2. En mode toggle, re-hotkey ou clic capsule.

### 4.4 Bascule de langue

- **Clic sur le badge** : cycle eu → fr → auto → eu. Le badge marque la bascule d'un pulse unique (scale 1→1.12→1, 220 ms) — pas de menu.
- **Hover badge** : tooltip natif « eu / fr / auto — ⌃⌥L ».
- **Raccourci global** `⌃⌥L` (configurable) : même cycle, y compris pendant l'écoute ; hors session, il met à jour la langue par défaut (feedback = icône menu bar, cf. §5).
- La langue choisie manuellement est **verrouillée** pour la session ; l'auto-détection n'est jamais le défaut silencieux (friction n°1 documentée des apps multilingues).

---

## 5. Menu bar

### 5.1 Icône — concept « le point d'insertion qui écoute »

La promesse produit en un glyphe : **un curseur texte (caret) flanqué d'ondes** — la voix entre dans le texte, au curseur. Aucun micro (cliché), aucune bulle.

Description vectorielle (canvas **18 × 18 pt**, template image, traits arrondis) :

- **Caret** : barre verticale capsule, 2 pt de large × 12 pt de haut, centrée (x = 9, de y = 3 à y = 15).
- **Barres d'onde** : 2 de chaque côté, capsules 2 pt de large, centrées verticalement (y = 9) :
  - intérieures (x = 4.5 et x = 13.5) : hauteur 7 pt ;
  - extérieures (x = 1.5 et x = 16.5) : hauteur 4 pt.
- Marges optiques : le glyphe pèse visuellement comme les icônes système voisines (~70 % du canvas).
- Export : `Image` template (`isTemplate = true`) — s'adapte menu bar claire/sombre/teintée de Tahoe. Fournir 1x/2x PDF vectoriel.

### 5.2 États

| État | Rendu |
|---|---|
| Repos | glyphe template monochrome |
| Enregistrement | les 4 barres d'onde s'animent en boucle douce (3 hauteurs pré-calculées, cycle 900 ms) **teintées `MzGorriBizi`** ; le caret reste template. Si l'animation menu bar s'avère distrayante en test : variante statique barres pleines Gorri |
| Transcription/correction | glyphe template + point 3 pt `MzGorri` sous le caret, pulse 1.6 s |
| Erreur (modèle manquant, permission) | badge point 3 pt `systemOrange` en haut à droite du glyphe |
| Bascule langue via raccourci (hors session) | le glyphe laisse place au texte « eu »/« fr » small caps 1 s, puis revient |

### 5.3 Popover (clic)

Matériau menu système standard (vibrancy native, aucun chrome custom). Contenu : ligne d'état (langue + modèle chargés, 11 pt secondaire), bascule langue (segmented eu / fr / auto), « Diktatu » avec rappel du raccourci, « Ireki Mintzo », « Fitxategia transkribatu… », séparateur, « Ezarpenak… », « Irten ». Drag-drop d'un fichier audio sur l'icône = ajout direct à la file (l'icône pulse une fois en Gorri à la réception).

---

## 6. Fenêtre principale

### 6.1 Intention

Un **journal composé**, pas une liste de logs : le texte dicté (serif) est le héros, la machinerie (méta, actions) s'efface en petites capitales et hairlines. Une seule colonne généreuse — pas de sidebar V1 (trois sources seulement : tout / dictées / fichiers → filtre segmented dans la toolbar).

### 6.2 Wireframe (défaut 760 × 560 pt, min 560 × 400)

```
┌────────────────────────────────────────────────────────────────┐
│ ● ● ●   Mintzo          [Dena|Diktaketak|Fitxategiak] [Bilatu…] │  toolbar glass
├────────────────────────────────────────────────────────────────┤
│                                                                │  32 pt
│   ILARA — 2 FITXATEGI                              ▸ gelditu   │  ← file d'attente
│   ┌──────────────────────────────────────────────────────┐    │    (si active)
│   │ ahots-mezua.opus        ▮▮▮▮▮▮▮▮▮░░░░░  1:12 · eu    │    │  56 pt
│   │ bilera.m4a              zain                          │    │  40 pt
│   └──────────────────────────────────────────────────────┘    │
│                                                                │  28 pt
│   GAUR                                                        │  ← section small caps
│   ┌──────────────────────────────────────────────────────┐    │
│   │ Kaixo Maite, bihar goizean elkartuko gara            │    │  New York 15/22
│   │ bulegoan proiektua ixteko.                 [copier]  │    │  (hover)
│   │ 14:32 · 0:42 · EU · diktaketa                        │    │  SF 11 secondaire
│   ├───────────────────────────────────── hairline ──────┤    │
│   │ Le devis part ce soir, je t'appelle après           │    │
│   │ la réunion pour valider les délais.                  │    │
│   │ 11:05 · 0:31 · FR · diktaketa                        │    │
│   └──────────────────────────────────────────────────────┘    │
│                                                                │
│   ATZO                                                        │
│   ┌──────────────────────────────────────────────────────┐    │
│   │ …                                                    │    │
│                                                                │
│              (fenêtre entière = zone de drop)                  │
└────────────────────────────────────────────────────────────────┘
```

*(« Bilatu… » = champ `.searchable` natif dans la toolbar — SF Symbol `magnifyingglass`, jamais un emoji)*

### 6.3 Spécifications

- **Marges** : 24 pt horizontales ; 28 pt entre sections ; groupes de cellules dans un conteneur `MzSurface` rayon 10 pt (concentrique fenêtre Tahoe), hairline `MzHairline`.
- **Cellule** (hauteur naturelle ≈ 76 pt) : padding 14 pt ; extrait New York 15/22 (2 lignes max) ; ligne méta 11 pt : `14:32 · 0:42 · EU · diktaketa` — heure et durée en monospacedDigit, tag langue small caps Semibold `MzGorri` (12 % de fond, rayon 4 pt, padding 3×1.5 pt), source en toutes lettres `MzInkSecondary`. Séparateur : hairline **entre cellules seulement** (inset 14 pt), pas en tête/pied.
- **Hover** : fond `MzSurfaceHover` + bouton `doc.on.doc` (copier, 13 pt) apparaît en trailing, fade 160 ms. Clic cellule = détail (corps New York 16/26, toggle discret « jatorrizkoa / zuzendua » en segmented 11 pt pour brut/corrigé). Copie : le bouton devient `checkmark` `MzSuccess` 800 ms — pas de toast.
- **Recherche** : `.searchable` natif toolbar ; résultats = mêmes cellules, occurrences surlignées `MzGorri` 24 % ; état vide de recherche : « Ez da emaitzarik » 13 pt `MzInkSecondary`, centré, sans illustration.
- **File d'attente** : section épinglée en tête, visible seulement si active. Par item : nom de fichier SF 13 Medium, barre de progression **2 pt** pleine largeur `MzGorri` (rail `MzHairline`), état à droite (« zain » = en attente, durée détectée, langue). Terminée → l'item glisse dans « Gaur » (cf. motion §7).
- **Drop** : fenêtre entière. Au drag-over : overlay glass (`.glassEffect` / fallback `MzPaper` 92 %) inset 12 pt rayon 14 pt, **bordure dashed 1.5 pt `MzGorri`** (dash 6/4), au centre SF Symbol `arrow.down.doc` 28 pt `MzGorri` + « Askatu hemen transkribatzeko » 15 pt Medium. Apparition 180 ms.
- **État vide (première ouverture)** : moment éditorial — au centre optique (45 % hauteur) : « Sakatu Fn eta hitz egin. » en **New York 22/30 Regular `MzInk`**, dessous « edo arrastatu audio-fitxategi bat hona » 13 pt `MzInkSecondary`. Rien d'autre. Aucune illustration, aucun blob.
- **Ce qui la rend éditoriale** (vs liste générique) : papier chaud au lieu de blanc bleuté ; serif pour le contenu ; dates en petites capitales espacées comme des folios ; hairlines 0.5 pt au lieu de bordures 1 px grises ; actions cachées jusqu'au hover ; densité aérée mais alignements stricts sur grille 4 pt.

---

## 7. Motion

Principe unique : **Arnasa — l'app respire, elle ne vibre pas.** Tout ce qui pulse le fait au rythme d'un souffle calme ; tout ce qui apparaît se pose ; rien ne bounce, rien ne wiggle, zéro anticipation cartoon.

### 7.1 Tokens

| Token | Durée | Courbe | Usage |
|---|---|---|---|
| `motion.enter` | 180 ms | spring(response 0.32, damping 0.80) | apparition HUD, overlay drop, hover reveals |
| `motion.morph` | 240 ms | spring(response 0.32, damping 0.80) | changements d'état HUD (largeur + contenu), segmented |
| `motion.exit` | 220 ms | easeIn (cubic-bezier 0.4, 0, 1, 1) | disparition HUD, dismiss overlays |
| `motion.micro` | 160 ms | easeOut (cubic-bezier 0, 0, 0.2, 1) | crossfades de labels, boutons hover, checkmark copie |
| `motion.breath` | 3 200 ms | easeInOut symétrique, boucle | halo d'écoute du HUD : `MzGorriBizi` 12 % → 18 % → 12 % (opacité seule, jamais l'échelle) |
| `motion.shimmer` | 1 100 ms | linéaire, boucle | onde de luminosité du trait de traitement |
| `motion.settle` | 320 ms | spring(response 0.45, damping 0.85) | insertion d'une cellule dans l'historique (glisse depuis la file, léger fade) |

### 7.2 Règles

- La waveform est la **seule** chose rapide de l'app (66 ms/barre) : elle reflète la voix en temps réel. Tout le reste est ≥ 160 ms.
- Jamais deux animations concurrentes sur le même élément ; le morphing HUD séquence fade-out → resize → fade-in (cf. 4.3).
- Succès = bref et silencieux (600 ms puis disparition). L'app ne se félicite pas.
- **Reduce Motion** : halo fixe à 12 %, waveform remplacée par une jauge de niveau statique (barre horizontale 2 pt dont la largeur suit le RMS), morphs → crossfades 160 ms sans changement d'échelle.
- Son : un « tick » discret optionnel au démarrage d'écoute (< −30 dB, désactivable, off par défaut) ; aucun son de succès.

---

## 8. Icône app

Direction (format Icon Composer, variantes light/dark/tinted obligatoires — signal « 2026-native » dans le Dock) :

1. **Concept** : le glyphe caret-et-ondes (§5.1) monumentalisé — « la voix entre dans la page » — gravé plein centre d'un squircle.
2. **Formes** : caret + 4 barres en blanc papier `#FAF9F7`, terminaisons capsules, épaisseurs généreuses (le glyphe occupe ~55 % de la largeur), géométrie strictement symétrique.
3. **Matières** : fond **Gorri Etxea** en dégradé vertical très retenu (`#A83226` → `#8C2820`), couche de verre Liquid Glass au-dessus du glyphe (léger relief, ombre interne douce) — l'effet « laque sur bois peint ».
4. **Subtilité basque admise ici** : le grain du fond peut porter une texture minérale à peine perceptible (2-3 % de bruit, évocation de la pierre calcaire — *harria*), et les terminaisons des barres peuvent être taillées en léger biseau lapidaire vu de près. Aucun symbole folklorique.
5. **Variantes** : dark = fond `#5E1B15` plus profond, glyphe inchangé ; tinted = glyphe seul monochrome. L'icône doit rester lisible à 16 px (le caret ne fusionne pas avec les barres : gap minimal 8 % de la largeur).

---

## 9. Ton rédactionnel et microcopy

### 9.1 Règles de voix

- **Langue** : euskara batua par défaut si le système est en `eu`, sinon français, sinon anglais. Terminologie alignée sur les conventions Librezale (fichier de localisation proposé en relecture à la communauté).
- **Ton** : sobre, précis, chaleureux par la clarté — jamais par l'enthousiasme. **Zéro point d'exclamation** dans toute l'app. Pas de « Oups », pas d'humour de chatbot, pas de « magique ».
- Adresse : eu = `zu` (neutre standard) ; fr = formes impersonnelles d'abord (« Autoriser le micro »), `vous` quand l'adresse est inévitable ; en = `you`.
- Les labels/boutons : pas de point final. Les explications : phrases complètes ponctuées.
- Honnêteté structurelle : chaque demande de permission dit *pourquoi* et *ce qui ne sort pas du Mac*. La promesse privacy est du copy récurrent : « Audioa ez da inoiz zure Mac-etik ateratzen. »

### 9.2 Microcopy de référence (eu / fr / en)

| Contexte | EU | FR | EN |
|---|---|---|---|
| Bouton dicter (popover/onboarding) | Diktatu | Dicter | Dictate |
| État écoute (HUD, accessibilité/VoiceOver) | Entzuten… | Écoute… | Listening… |
| Correction en cours (HUD) | Zuzentzen… | Correction… | Correcting… |
| Permission micro (onboarding, titre + corps) | Mikrofonoa behar dugu. — Mintzok mikrofonoa erabiltzen du zure ahotsa entzuteko. Audioa zure Mac-ean prozesatzen da, eta ez da inoiz hemendik aterako. | Le micro est nécessaire. — Mintzo utilise le micro pour entendre votre voix. L'audio est traité sur votre Mac et n'en sort jamais. | Microphone needed. — Mintzo uses the microphone to hear your voice. Audio is processed on your Mac and never leaves it. |
| Erreur modèle manquant (HUD + fenêtre) | Euskarazko eredua falta da. Deskargatu behin, erabili betiko — konexiorik gabe. [Deskargatu (1,6 GB)] | Le modèle basque n'est pas installé. Téléchargez-le une fois, utilisez-le pour toujours — sans connexion. [Télécharger (1,6 Go)] | The Basque model isn't installed. Download it once, use it forever — no connection needed. [Download (1.6 GB)] |

Autres chaînes canoniques déjà fixées dans ce document : « Transkribatzen… » (transcription), « Itsatsita » / « Inséré » / « Inserted » (succès), « Askatu hemen transkribatzeko » / « Déposez ici pour transcrire » / « Drop here to transcribe », « Sakatu Fn eta hitz egin. » / « Appuyez sur Fn et parlez. » / « Press Fn and speak. », « zain » / « en attente » / « queued », « jatorrizkoa / zuzendua » / « original / corrigé » / « original / corrected ».

### 9.3 SF Symbols canoniques (rappel : jamais d'emoji)

| Usage | Symbole |
|---|---|
| Copier | `doc.on.doc` → `checkmark` (confirmé) |
| Drop fichier | `arrow.down.doc` |
| Succès HUD | `checkmark` |
| Erreur | `exclamationmark.triangle` |
| Réglages | `gearshape` |
| Historique / recherche | `clock` / `magnifyingglass` |
| Supprimer | `trash` |
| Micro (uniquement écran permission) | `mic` |
| Modèles / téléchargement | `arrow.down.circle`, `internaldrive` |

---

## 10. Checklist QA design (à passer avant tout merge UI)

1. Dark ET Light audités (pas d'hex partagé entre les deux par accident).
2. Increased Contrast + Reduce Transparency + Reduce Motion testés.
3. Aucun emoji, aucune icône hors SF Symbols ; ellipses `…` ; espaces fines FR.
4. Chiffres monospacedDigit partout où ça compte/défile ; zéro jitter de layout (HUD largeur stable par état).
5. Verre uniquement sur HUD/toolbar/popover/overlay — jamais sous du texte long.
6. Hairlines à 0.5 pt réels (pas 1 px), radii concentriques non hardcodés.
7. Serif New York = texte dicté uniquement ; small caps = méta/dates/badges uniquement.
8. Un seul rouge de marque (`MzGorri`/`MzGorriBizi`) ; `systemRed` réservé aux erreurs.
9. Motion : rien ne pulse plus vite que `motion.breath` sauf la waveform.
10. VoiceOver : chaque état du HUD annoncé (« Entzuten », « Transkribatzen », « Itsatsita ») ; la capsule est un bouton « Gelditu ».
