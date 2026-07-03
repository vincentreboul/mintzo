# Mintzo — SPEC de la marque lauburu

**Concept.** Lauburu (croix basque, rotation traditionnelle horaire) construit à
partir de **4 virgules typographiques** — la ponctuation de la parole. De loin :
lauburu évident. De près : quatre virgules. Masses égales, respiration centrale,
aucun contact. Réf. design : `docs/design/design-language.md` (amendement v1.1 + §5).

## Géométrie R3 (maître gelé 2026-07-03) — « au compas »

Coords math (y vers le haut), centre C=(0,0), box 1000 (SVG : (500+x, 500−y)).
Source paramétrique : `work/gen_lauburu.py` → `work/paths.json`.

**UNE virgule maîtresse, entièrement déterminée par 7 nombres, puis rotation
programmatique exacte ×4 (`<use rotate(90k,500,500)>`) — l'identité des 4
virgules est garantie par construction.**

- **Tête** : cercle parfait rayon **132**, centre H=(0, 268) → étendue 800/1000.
- **Spine de queue** : arc de cercle exact de H au centre de pointe
  T=(−97.96, 31.83) (polaire 162°, r=103) ; sagitta **48** côté concave vers C
  → centre G=(86.10, 93.88), rayon spine **194.24**, balayage **82.3°**,
  longueur d'arc 279.
- **Loi de largeur (demi-cosinus)** : disque de rayon
  `w(t) = 14 + 118·((1+cos πt)/2)^1.5`, t∈[0,1] — **décroissance strictement
  monotone** 132 → 14, pente nulle aux deux bouts.
- **La virgule = enveloppe (courbe canal) de la famille de disques** centrés sur
  le spine. Conséquences exactes, pas « à l'œil » :
  - la tête est le disque t=0 → la queue en émerge **exactement tangente**
    (zéro épaulement, zéro morsure : bord convexe jamais sous le cercle, écart 0.00) ;
  - la pointe est le disque t=1 → **cap demi-circulaire exact** (180.0°),
    perpendiculaire aux deux bords : bout arrondi net ;
  - cap de tête = demi-cercle exact (180.0°) ;
  - contacts d'enveloppe inclinés de cos β = −w′/|s′| (formule, échantillonnée) ;
    régularité max |w′|/|s′| = **0.77 < 1** (aucun cusp possible).
- **SVG** : caps émis en arcs `A` exacts ; bords d'enveloppe ajustés par
  12 cubiques/bord, erreur max **0.51/1000** ; rendu SVG vs géométrie exacte :
  écart moyen 0.06/255 (invisible).

### QA mesurée (unités /1000)

| Mesure | R3 | R2 (pour mémoire) |
|---|---|---|
| Symétrie C4 (bitmap tourné 90° vs original, diff pixel) | **max 0, moyenne 0.0** | non vérifiée |
| Gap pointe ↔ tête voisine | **27.0** | 40.2 |
| Gap pointe ↔ racine de queue voisine (menton) | **23.9** | non mesuré |
| Min inter-virgules vrai (polygones denses) | **23.8** | 14.6 (pincement canal) |
| Pincement avant pointe (min profil − gap pointe) | **−0.95** (canal quasi constant) | ~−25 |
| Vide central (rayon inscrit) | **89** | 91 |
| Étendue | 800/1000 | 800/1000 |

Les 4 gaps inter-virgules sont identiques par symétrie C4 ; chaque pointe meurt
dans le creux tête/queue de la virgule suivante, à ~24 des deux parois
(emboîtement traditionnel du lauburu, ici avec respiration constante).

### Coupes optiques petites tailles (même construction, autres nombres)

- **small** (favicon 32, icônes 32/64) : tête r118 à 282, T polaire 156° r118,
  sagitta 32, M=1.4, pointe r18 → gaps **38.3 / 38.3 / 44.7**, vide **100**.
- **16 px** : lauburu **classique plein** (compas pur : bras = demi-cercle
  extérieur R + lobe R/2 + encoche R/2, miroir pour la chirality maîtresse) —
  les 4 virgules ne tiennent pas physiquement à 16 px ; la silhouette
  tournante reste.

## Fichiers

| Fichier | Usage |
|---|---|
| `lauburu.svg` | mark maître, viewBox 0 0 1000 1000, `currentColor` — LA virgule dans `<defs>` + 3 `<use>` rotatifs |
| `lauburu-wordmark.svg` | lockup horizontal mark + « Mintzo » (Fraunces opsz 144 / Black 900, tracking −1 %, outlines figées) — `currentColor` ; inliné : `.mark { fill:#9B2D23 }` pour le deux-tons |
| `AppIcon.iconset/` + `AppIcon.icns` | icône app (squircle Apple 824/1024 superellipse n=5, laque gorri : dégradé + grain + reflet, mark papier ; coupes small à 32/64, classique à 16, recalage px) |
| `favicon.svg` | coupe small pleine box 32, gorri `#9B2D23` / dark `#D96A5B` via `prefers-color-scheme` (vérifié au rendu) |
| `favicon-32.png` / `favicon-16.png` | fallback raster (16 = classique plein) |
| `apple-touch-icon.png` | 180×180, lauburu papier `#FAF9F7` sur gorri plein, coins droits |
| `previews/` | rendus de contrôle : mark 512 light/dark, 64/32 ×8, icônes 1024/64 + 32/16 ×8, favicons ×8, wordmark, sanity SVG, **comma-anatomy.png** (LA virgule seule + construction : cercles de tête/pointe, spine, centres) |
| `work/gen_lauburu.py` | générateur unique (géométrie, QA, SVG, rasters, icns) — `--search` pour ré-explorer |

## Couleurs (design-language §2)

Gorri Etxea `#9B2D23` (light) / `#D96A5B` (dark) ; papier `#FAF9F7` ; encre `#1C1B1A`.
Le mark vit en gorri sur papier, papier sur gorri, ou encre (monochrome). Rien d'autre.

## Assemblage site

Header : `lauburu-wordmark.svg` inliné (hauteur cible 28–36 px), `color: #1C1B1A`
(`#F2F0ED` dark) + `.mark { fill: #9B2D23 }` (`#D96A5B` dark). Alternative : `lauburu.svg`
seul + « Mintzo » en Fraunces web (opsz 144, wght 900, `letter-spacing: -0.01em`) —
mêmes proportions : diamètre mark ≈ 1.3 × hauteur de capitale, centré sur la mi-hauteur
de capitale, gap ≈ 0.3 × cap.

## Interdits

- Pas d'étirement, pas de rotation, pas de miroir (le sens de rotation EST la marque).
- Pas d'autres couleurs, pas de dégradé hors icône app, pas de contour/outline.
- Pas d'emoji de substitution. Jamais de clipart lauburu externe.
- Le maître (queue fine) jamais rendu sous 64 px : utiliser les coupes optiques.
- Zone de protection : ½ tête (66/1000) minimum autour du mark.
- Ne pas retoucher les paths à la main : toute retouche passe par
  `work/gen_lauburu.py` (les 4 virgules doivent rester générées).

## Verdict 16 px

Favicon 16 et icône 16 : la coupe classique pleine reste **lisible comme
silhouette tournante à 4 lobes** (vérifié pixel ×8) ; le détail « virgules »
est réservé à ≥ 32 px — choix assumé, standard des marques à petit corps.
