# Audit de l'existant 099

Statut : **OK**.

| Élément | Existant | Décision |
|---|---|---|
| Grille, tuiles, voisins | `SearchBarLayout.makeGrid`, `drawTile`, `AlfredGridView.neighbour` (092) | RÉUTILISER |
| ← → en grille | `SearchInputPanel.gridColumns`, `.move` (092) | RÉUTILISER |
| Touche réglable | `TargetSearchHotkey.resolve`, `ShortcutRecorderControl`, `TargetGridConfig.normalizedKey` | RÉUTILISER |
| Chip | pastille du compteur (`counterText`, 081) | ÉTENDRE |
| Mémoire | `LauncherHistoryStore` (090), `LauncherRankingStore` (073) | CRÉER un petit store (format différent : clé → présentation) |
| Vignette | `SearchBarRenderer.icon(.image)` | ÉTENDRE (vignette réduite) |

Arbitrage : un store dédié plutôt qu'une clé dans le classement : données de nature différente,
effaçables séparément.

## Gate avant tasks
- [x] Décision pour chaque élément. - [x] Créations justifiées. - [x] Aucune dépendance ajoutée.
