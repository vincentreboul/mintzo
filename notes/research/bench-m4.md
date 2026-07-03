# Bench réel M4 — whisper-large-v3-eu (2026-07-03 13:02, whisper-cli brew, Metal)

4 phrases basques réelles (dataset public mikelalda/basque_speech_dataset, split gizonezkoa, vérité terrain fournie).

| # | Référence | Sortie modèle | Verdict |
|---|---|---|---|
| 0 | Cadena Estrella Azul Tien21 etxetresnen taldeari atxikita dago | Kadena estrella azul Tien 21 etxetresnen taldeari atxikita dago. | quasi parfait (graphie marque ES) |
| 1 | Ariana Grandek jendaurrean esan berri du Mac Millerrekin dabilela | identique + ponctuation | parfait |
| 2 | Gaueko hirurak eta hamarrean hartuko dugu autobusa | identique + point | parfait |
| 3 | Punto Radio Euskadi irratian entzuten ditut Athleticen igandeetako partidak | Puntos… atletiken… | 2 fautes, noms propres seulement |

## Conclusions

1. **Qualité euskara excellente sur audio réel** — erreurs limitées aux noms propres non basques. Le modèle sort déjà ponctuation + majuscules → la passe de correction Latxa a moins à faire que prévu (elle se concentre sur les vraies fautes ASR et la typographie).
2. **Latence** : total CLI 5,8-6,2 s dont **load 1,8 s (une fois par session en app, modèle résident)** ; encode ≈ 2,5 s = coût quasi FIXE par fenêtre de 30 s (Whisper padde à 30 s). Dictée typique 5-15 s ⇒ **~2,5-3,5 s d'inférence** modèle chargé → budget « < 5 s » TENU. Fichiers longs : ~0,5-0,7× temps réel, OK pour vocaux WhatsApp.
3. Plan B latence (Parakeet eu via sherpa-onnx, ~10×) reste en réserve, non nécessaire à ce stade.
