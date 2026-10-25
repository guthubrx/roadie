# Plan 082

| Zone | Fichier | Changement |
|---|---|---|
| Modèle | `Sources/RoadieDaemon/LauncherOpenItems.swift` (nouveau) | `LauncherOpenItem` (document ou onglet), scripts, lecture des sorties, correspondance par cadre |
| Liste | `LauncherList.swift` | section « Documents et onglets », ligne `openItem` |
| Barre | `TargetOverlayPresenter.swift`, `LauncherSearchContext.swift` | chargement en fond à l'ouverture, lignes, Retour |
| Effets | `TargetModeRuntimeController.swift` | lecture des documents et onglets, aller à la fenêtre, sélection de l'onglet |

Tests : `Tests/RoadieDaemonTests/Spec082OpenItemsTests.swift`.
