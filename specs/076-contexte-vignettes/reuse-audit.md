# Audit de réutilisation 076

Statut : `OK`. Repli manuel (`rg`).

| Élément | Existant | Issue |
|---|---|---|
| Mémoire par stage | `LauncherRanking.Entry` (abréviations, ancre) | RÉUTILISER, ajouter `contexts` optionnel |
| Ordre | `LauncherList.before` | RÉUTILISER, deux comparaisons de plus |
| Nom de stage | `WindowSwitcherService.stageLabels`, déjà appelé dans `launcherContext` | RÉUTILISER |
| Vignettes | `RailThumbnailStore.shared` (`detailedImage`, `cachedImage`, `hasCapturedImage`) | RÉUTILISER, lecture seule |
| Icône de ligne | `SlashSuggestion.Icon` | RÉUTILISER, cas `.window` |

## Gate avant tasks
- [x] Recherche d'existant tranchée pour chaque élément.
- [x] Aucune duplication.
- [x] Aucun refactor du plan à demander.

## Arbitrages
Aucun.
