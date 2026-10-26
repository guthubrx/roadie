# Audit de réutilisation 091

Statut : `OK`. Repli manuel (`rg`), 26 octobre 2026.

| Élément | Existant | Issue |
|---|---|---|
| Verbes et destinations | `LauncherActionList`, `LauncherDestination` (074) | RÉUTILISER, liste du lot |
| Exécution | `perform(_ action:)` (074) | RÉUTILISER pour chaque objet ; CRÉER `performBatch` (destination résolue une fois) |
| Nouvelle stage | `stageScope(for:)` | RÉUTILISER une seule fois par lot |
| Annuler | `LauncherMemoryBook.undoable` (081) | RÉUTILISER, champ `batch` |
| Capsule | `TargetSearchBar.chip` (081) | RÉUTILISER |
| Sélection | aucun équivalent dans le lanceur | CRÉER `LauncherSelection` |

## Gate avant tasks
- [x] Recherche d'existant tranchée.
- [x] Aucune duplication non arbitrée.
- [x] Aucun refactor à demander.

## Arbitrages
Aucun.
