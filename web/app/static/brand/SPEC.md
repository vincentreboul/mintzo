# Mintzo — SPEC de la marque lauburu

**Concept R4 « vraie virgule » (2026-07-03).** Feedback client verbatim : « Je veux
des vraies virgules ». Le lauburu (croix basque, rotation traditionnelle horaire)
est désormais construit avec **LE glyphe virgule d'une fonte réelle** — reconnaissable
au premier regard comme une virgule de texte — disposé ×4 en rotation 90° autour du
centre. De près : quatre virgules typographiques. De loin : la croix basque qui tourne.
Réf. design : `docs/design/design-language.md`. Comparatif : `previews/side-by-side.png`
(R3 « virgule construite » vs R4 « glyphe Fraunces »).

## Source du glyphe (gelée R4)

- **Fonte** : **Fraunces** — déjà la fonte display de la marque — build variable
  auto-hébergé `web/app/static/fonts/fraunces-latin-opsz-normal.woff2`
  (axes opsz 9–144, wght 100–900, upem 2000).
- **Instance** : **wght 900 (Black) · opsz 9** — l'optical size *texte*, c'est-à-dire
  la virgule telle qu'on la lit dans un paragraphe : tête pleine bien ronde, queue
  courte et charnue. L'opsz 144 (display, queue longue et fine) a été essayé et
  écarté : plus « guillemet flottant » que virgule, queue trop maigre aux petites
  tailles (`work/explore/glyph-compare.png`, `grid-opsz144.png` vs `grid-opsz9.png`).
- **Glyphe** : « comma » U+002C, 1 contour TrueType, extrait tel quel via fonttools
  (`varLib.instancer` puis RecordingPen) — quadratiques préservées EXACTES dans le
  SVG (`M/L/Q/Z`), zéro approximation, zéro retouche. Bbox 518×819 unités.
- **Licence** : SIL OFL 1.1 (The Fraunces Project Authors, github.com/undercase/Fraunces).
  L'usage des contours dans un logo est permis ; les outlines sont figées dans les
  SVG, aucune redistribution de la fonte elle-même.
- Traçabilité : `work/fraunces/comma-opsz9-wght900.json` (+ TTF instanciés),
  `work/params_r4.json`.

## Composition (box 1000, centre C=(500,500))

**AUCUNE déformation du glyphe** — échelle uniforme + rotation seulement.
3 paramètres, gelés après exploration (`work/explore/`) :

| Paramètre | Master | Small (coupe optique) |
|---|---|---|
| Rayon de placement **R** (centre → ancre = centre bbox du glyphe) | **230** | 236 |
| Angle de départ **θ0** (rotation globale écran) | **0°** (virgule n°1 parfaitement droite, en haut) | 0° |
| Étendue cible (⇒ échelle résolue) | **800/1000** ⇒ s = 0.4152 (virgule 215×340) | 800 ⇒ s = 0.4006 |

- Virgule k = rotation exacte de k·90° autour de C, émise en SVG par
  `<use rotate(90k,500,500)>` — l'identité des 4 virgules est garantie par
  construction.
- **Chirality** : tête en haut, queue plongeant vers le centre en balayant à
  gauche → les 4 têtes tournent en **sens horaire** (lauburu traditionnel,
  même sens que R3).
- θ0 = 45° (virgules aux diagonales) exploré et écarté : plus « trèfle », et
  plus aucune virgule droite — moins littéral.
- R < 228 : les queues touchent les têtes voisines (gap ≈ 0) — interdit ;
  R = 230 = emboîtement le plus serré avec respiration constante.

### QA mesurée (unités /1000, `work/gen_lauburu_r4.py`)

| Mesure | Master R4 | Small R4 | R3 (mémoire) |
|---|---|---|---|
| Gap inter-virgules (min vrai, polygones denses) | **22.6** | 41.8 | 23.8 |
| Vide central (rayon inscrit) | **76.6** | 87.2 | 89 |
| Étendue | 800 | 800 | 800 |
| **C4 bitmap** (rot 90° vs original, diff pixel) — raster PIL | **max 0, moyenne 0.0** | — | max 0 |
| **C4 bitmap** — `lauburu.svg` rendu qlmanage 1000 px | **max 0, moyenne 0.0** | — | — |
| SVG rendu vs géométrie (diff moyenne /255) | 0.063 | — | 0.06 |

Les 4 gaps sont identiques par symétrie C4 ; chaque queue meurt dans le creux
tête/queue de la virgule suivante (emboîtement du lauburu), sans jamais toucher.

### Coupes optiques petites tailles

- **small** (favicon 32, icônes 32/64) : mêmes glyphes, R = 236 → canaux élargis
  (gap 41.8, vide 87.2) pour que les inter-virgules restent ouverts au pixel.
- **16 px** : lauburu **classique plein** (compas R3 : bras = demi-cercle
  extérieur + lobe + encoche, même chirality). Les 4 glyphes ne tiennent PAS
  physiquement à 16 px — poussière de pixels même dilatés — preuve :
  `work/explore/cut16-variants.png`. La silhouette tournante reste.

## Fichiers

| Fichier | Usage |
|---|---|
| `lauburu.svg` | mark maître, viewBox 0 0 1000 1000, `currentColor` — LE glyphe (path exact) dans `<defs>` + 4 `<use>` rotatifs |
| `lauburu-wordmark.svg` | lockup horizontal mark + « Mintzo » (Fraunces opsz 144 / Black 900, tracking −1 %, outlines figées) — `currentColor` ; inliné : `.mark { fill:#9B2D23 }` pour le deux-tons |
| `AppIcon.iconset/` + `AppIcon.icns` | icône app (squircle Apple 824/1024 superellipse n=5, laque gorri : dégradé + grain + reflet + ombre, mark papier ; master ≥128 px frac .50, small à 64/32 frac .56/.64, classique à 16 frac .70, recalage px) |
| `favicon.svg` | coupe small box 32, gorri `#9B2D23` / dark `#D96A5B` via `prefers-color-scheme` (vérifié au rendu : `previews/svg-sanity-favicon.png`, rendu par un hôte en dark mode → D96A5B) |
| `favicon-32.png` / `favicon-16.png` | fallback raster (16 = classique plein) |
| `apple-touch-icon.png` | 180×180, 4 virgules papier `#FAF9F7` sur gorri plein, coins droits |
| `previews/` | mark 512 light/dark, 64/32 ×8, icônes 1024/64 + 32/16 ×8, favicons ×8, wordmark, sanity SVG, **comma-anatomy.png** (LE glyphe Fraunces seul + provenance), **side-by-side.png** (R3 vs R4) ; traces R3 conservées en `r3-*` |
| `work/gen_lauburu_r4.py` | générateur unique R4 (extraction fonte, composition, QA, SVG, rasters, icns) — `--extract`, `--explore` |
| `work/gen_lauburu.py` | générateur R3 (conservé : primitives de rendu + coupe classique 16 px) |

## Couleurs (design-language §2)

Gorri Etxea `#9B2D23` (light) / `#D96A5B` (dark) ; papier `#FAF9F7` ; encre `#1C1B1A`.
Le mark vit en gorri sur papier, papier sur gorri, ou encre (monochrome). Rien d'autre.

## Assemblage site

Header : `lauburu-wordmark.svg` inliné (hauteur cible 28–36 px), `color: #1C1B1A`
(`#F2F0ED` dark) + `.mark { fill: #9B2D23 }` (`#D96A5B` dark). Alternative : `lauburu.svg`
seul + « Mintzo » en Fraunces web (opsz 144, wght 900, `letter-spacing: -0.01em`) —
mêmes proportions : diamètre mark ≈ 1.3 × hauteur de capitale, centré sur la mi-hauteur
de capitale, gap ≈ 0.3 × cap. Cohérence totale : le mark EST un glyphe de la fonte du logo.

## Interdits

- Pas d'étirement, pas de miroir, pas de rotation libre (le sens de rotation EST
  la marque ; seules les rotations 90° de la construction existent).
- **Pas de déformation du glyphe** : jamais de retouche des contours à la main —
  toute évolution passe par `work/gen_lauburu_r4.py` (glyphe ré-extrait de la fonte).
- Pas d'autres couleurs, pas de dégradé hors icône app, pas de contour/outline.
- Pas d'emoji de substitution. Jamais de clipart lauburu externe.
- Le maître jamais rendu sous 64 px : coupe small à 32–64, classique à 16.
- Zone de protection : ½ tête de virgule (≈ 70/1000) minimum autour du mark.

## Verdict 16 px

Favicon 16 et icône 16 : coupe classique pleine, **lisible comme silhouette
tournante à 4 lobes** (vérifié pixel ×8) ; les vraies virgules sont réservées à
≥ 32 px — choix assumé (les 4 glyphes à 16 px = poussière illisible, preuve dans
`work/explore/cut16-variants.png`), standard des marques à petit corps.
