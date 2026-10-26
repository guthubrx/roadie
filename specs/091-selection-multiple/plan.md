# Plan 091

| Zone | Fichier | Changement |
|---|---|---|
| Touches | `Sources/RoadieDaemon/SearchInputPanel.swift`, `TargetOverlayPresenter.swift` (`SearchKeyInput`) | ⌥↑ ⌥↓ ⌥← ⌥→ ⌥⌫ |
| Sélection | `Sources/RoadieDaemon/LauncherSelection.swift` (nouveau) | sélection ordonnée, verbes communs et leur nombre, actions du lot |
| Verbes | `Sources/RoadieDaemon/LauncherActions.swift` | `LauncherActionList.selection` : lignes de verbes du lot, destinations |
| Barre | `Sources/RoadieDaemon/TargetOverlayPresenter.swift` | coches, capsule « N choisis », étapes du lot, Échap |
| Effets | `Sources/RoadieDaemon/TargetModeRuntimeController.swift`, `LauncherSearchContext.swift` | `performBatch` : nouvelle stage résolue une fois, suite d'actions, focus final |
| Annuler | `Sources/RoadieDaemon/LauncherMemory.swift` | `WindowMove.batch`, annulation du lot |

Complexité : ajout/retrait O(s) (s ≤ quelques dizaines) ; verbes communs O(s) ; exécution O(s)
actions. Tests : `Spec091SelectionTests`.
