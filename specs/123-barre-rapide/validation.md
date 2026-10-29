# Validation 123 : barre de lancement rapide

- Tests `Spec123LauncherSpeedTests` : score accéléré identique à l'algorithme d'avant (36 saisies × 22 textes),
  empreinte des lettres sans rejet à tort, index des signets et de l'historique identique à l'ancienne règle.
- `Spec123SpotlightQueryTests` : requêtes Spotlight valides, mêmes règles que `predicate`.
- `Spec123FileOrderTests` : « Suivi commandé Maya » reste premier avant et après l'arrivée de fichiers jamais ouverts
  au nom plus proche (« Commande », `commande-parent.json`).
- Suite complète : 2 264 tests / 329 suites et 28 tests de scripts réussis. Installé, PID 51959, santé 5/5,
  signature `roadied-cert`.

## Mesures réelles (`launcher.timing`, charge 18 à 52)

| Mesure | Avant | Après |
|---|---|---|
| Fil principal bloqué au plus | jusqu'à 1 200 ms | 80 à 260 ms |
| Historique par touche | 170 à 220 ms (version de test) | 1 à 9 ms (version optimisée) |
| Icône d'une nouvelle ligne, à froid | 80 à 265 ms | 4 à 9 ms |
| Premier dessin de la barre | non mesuré | 88 à 157 ms (une fois 531 ms) |
| Premiers fichiers | après Spotlight, 0,4 à 4,6 s | environ 50 ms (fichiers déjà ouverts) |

## Limites

- Les fichiers jamais ouverts dépendent toujours de Spotlight : 0,4 à 4,6 s sous charge.
- Pistes non retenues : index complet des fichiers à la manière de Raycast ou LaunchBar ; fichiers réservés au
  mot-clé `open` comme dans Alfred.
- Correction de l'ordre des fichiers non encore confirmée par l'utilisateur.
- Pas de diaporama : clics et touches simulés refusés sur ce poste.
