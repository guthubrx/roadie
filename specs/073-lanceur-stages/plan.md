# Plan 073 - Lanceur intégré aux stages, lot 1

## Architecture
- `LauncherMatch` (pur) : appariement par score, seuil `max(3, 2·L − 1)`.
- `LauncherRanking` (pur) + `LauncherRankingStore` : abréviations mémorisées et
  fréquence-récence à demi-vie de 10 jours, `~/.roadies/launcher-ranking.json`.
- `LauncherAppCatalog` : parcours des dossiers d'applications hors du fil principal,
  gardé en mémoire, rafraîchi au démarrage du démon et à chaque ouverture de la barre.
- `LauncherList` (pur) : sections, tri, meilleure ligne, navigation.
- `LauncherSearchContext` + `LauncherPlacement` : contexte transmis à la barre, choix de
  la fenêtre à rejoindre, état des applications ouvertes.
- `TargetSearchSession` : liste au-dessus de la barre (panneau des suggestions, en-têtes et
  icônes), flèches, Tab, Retour, clic, mémorisation des choix.
- `TargetModeRuntimeController.launch` : rejoindre via `WindowSwitcherService`, sinon
  `NSWorkspace.openApplication`.

## Écart au découpage initial
F5 (intention de placement) passe au lot 2 : le lot 1 ouvre dans la stage active, déjà
assurée par la règle de placement des nouvelles fenêtres (SPEC-046). Aucun mécanisme
sans usage n'est ajouté.
