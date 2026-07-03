# Mintzo — SPEC de la marque lauburu

**Concept.** Lauburu (croix basque, 4 têtes en virgule, rotation traditionnelle horaire)
construit à partir de **4 virgules typographiques serif** (tête ronde pleine + queue
courbe effilée, terminaison en goutte). De loin : lauburu évident. De près : quatre
virgules — la ponctuation de la parole. Masses égales, respiration centrale, aucun
contact entre têtes. Réf. design : `docs/design/design-language.md` (amendement v1.1 + §5).

## Géométrie (maître gelé R9, 2026-07-03)

- Source paramétrique : `work/gen_lauburu.py` → `work/paths.json`. Box 1000×1000, centre (500,500).
- Têtes : rayon 132, centres à 268 du centre (étendue visuelle = 800/1000 de la box).
- Queue : spine polaire 18°→93°, plongée `rho` 225→96, largeur 150 effilée (exp. 1.38),
  bout arrondi (cap 5) — virgule « imprimée », pas de cusp.
- QA mesuré : gap pointe/tête voisine **40.2**, canal queue/tête voisine **14.6**,
  vide central rayon **91** (aucun contact, respiration réelle).
- **Coupes optiques petites tailles** (même famille, canaux élargis — r 118, w 135) :
  - `26-grid` : icône 32 px (canal 38.4) ; aussi la géométrie de `favicon.svg`/`favicon-32.png`.
  - `16 px` : lauburu **classique plein** (au compas) — les 4 virgules ne tiennent
    physiquement pas à 16 px ; la silhouette tournante reste.

## Fichiers

| Fichier | Usage |
|---|---|
| `lauburu.svg` | mark maître, viewBox 0 0 1000 1000, `currentColor` — site, docs |
| `lauburu-wordmark.svg` | lockup horizontal mark + « Mintzo » (Fraunces opsz 144 / Black 900, tracking −1 %, outlines figées) — `currentColor` ; inliné : `.mark { fill:#9B2D23 }` pour le deux-tons |
| `AppIcon.iconset/` + `AppIcon.icns` | icône app (squircle Apple 824/1024, relief laque, grille 26/12 aux petites tailles) → `Resources/AppIcon.icns` |
| `favicon.svg` | coupe 26-grid, gorri `#9B2D23` / dark `#D96A5B` via `prefers-color-scheme` |
| `favicon-32.png` / `favicon-16.png` | fallback raster (16 = coupe classique pleine) |
| `apple-touch-icon.png` | 180×180, lauburu papier `#FAF9F7` sur gorri plein, coins droits |
| `previews/` | rendus de contrôle (512 light/dark, 64/32/16 ×8, sanity SVG, wordmark) |

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
- Le maître (canaux fins) jamais rendu sous 64 px : utiliser les coupes optiques.
- Zone de protection : ½ tête (66/1000) minimum autour du mark.

## Verdict 16 px

Favicon 16 et icône 16 : la coupe classique pleine reste **lisible comme silhouette
tournante à 4 lobes** (vérifié pixel ×8) ; le détail « virgules » est réservé à ≥ 32 px —
choix assumé, standard des marques à petit corps.
