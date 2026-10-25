# Plan 081

| Zone | Fichier | Changement |
|---|---|---|
| Mémoire | `Sources/RoadieDaemon/LauncherMemory.swift` (nouveau) | déplacements notés, refus, propositions, liste vide (pur) |
| Notation | `WindowContextActions.swift`, `StageCommands.swift` | un enregistrement par déplacement |
| Liste | `LauncherList.swift` | lignes `action` et `rule` |
| Barre | `TargetOverlayPresenter.swift`, `SearchBarRenderer.swift`, `SearchInputPanel.swift` | liste vide, chip, ⌘R, choix de règle |
| Contrôleur | `TargetModeRuntimeController.swift` | calcul des propositions, choix (créer, plus tard, jamais) |

Tests : `Tests/RoadieDaemonTests/Spec081MemoryTests.swift`.
