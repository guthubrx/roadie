# Plan 080

| Zone | Fichier | Changement |
|---|---|---|
| Modèle | `Sources/RoadieDaemon/StageProjects.swift` (nouveau) | `StageProject`, `ProjectWindow`, magasin, capture pure, arbre par rangs |
| Document | `Sources/RoadieAX/AXDocument.swift` | adresse web en plus du chemin |
| Ouverture | `Sources/RoadieDaemon/TargetModeRuntimeController.swift` | enregistrer, rouvrir (stage, fenêtres une à une, arbre), supprimer ; `placeNewWindow` rend la fenêtre placée |
| Barre | `LauncherList.swift`, `LauncherActions.swift`, `TargetOverlayPresenter.swift` | section Projets, objet projet, verbes |
| CLI | `CLICommandRouter.swift` | `roadie project save|open|list|delete` |

Tests : `Tests/RoadieDaemonTests/Spec080ProjectsTests.swift`.
