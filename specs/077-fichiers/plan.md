# Plan 077

| Zone | Fichier | Changement |
|---|---|---|
| Fichier | `Sources/RoadieDaemon/LauncherFiles.swift` (nouveau) | `LauncherFile`, `LauncherFileSearch` (Spotlight), filtres et tri |
| Liste | `Sources/RoadieDaemon/LauncherList.swift` | `Row.file`, section `files`, recherche rapide |
| Verbes | `Sources/RoadieDaemon/LauncherActions.swift` | `LauncherSubject.file`, verbes `reveal`, `quickLook`, `copyPath`, variantes |
| Document | `Sources/RoadieAX/AXDocument.swift` (nouveau) | `axDocumentPath(_:)` |
| Barre | `Sources/RoadieDaemon/TargetOverlayPresenter.swift`, `SearchInputPanel.swift` | lignes fichiers, recherche asynchrone, `.copy` (⌘C), `.preview` (⌘Y) |
| Effets | `Sources/RoadieDaemon/TargetModeRuntimeController.swift` | ouvrir/aller à la fenêtre, stage du dossier, placement commun, Finder, Quick Look, copie ; `launcher.launch` |
| CLI | `Sources/RoadieDaemon/CLICommandRouter.swift` | `roadie launch CHEMIN [--stage NOM|--new-stage]` |
| Catalogue | `Sources/RoadieDaemon/LauncherAppCatalog.swift` | deux dossiers d'applications |

Complexité : liste O(f) fichiers (≤ 40) de plus ; document O(w) lectures AX au choix seulement.
Tests : `Tests/RoadieDaemonTests/Spec077FilesTests.swift`.
