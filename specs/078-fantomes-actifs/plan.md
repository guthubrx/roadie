# Plan 078

| Zone | Fichier | Changement |
|---|---|---|
| Disposition future | `Sources/RoadieDaemon/DaemonSnapshot.swift` | `SnapshotService.previewPlacements(scope:incoming:in:)` |
| Suspension | `Sources/RoadieDaemon/LayoutPreviewHold.swift` (nouveau), `LayoutMaintainer.swift` | maintien partagé, sortie tôt de la passe |
| Aperçu | `Sources/RoadieDaemon/TargetModeRuntimeController.swift` | début (bascule, maintien, écriture), renouvellement, fin (restauration ou validation) |
| Barre | `Sources/RoadieDaemon/TargetOverlayPresenter.swift`, `LauncherSearchContext.swift` | demande d'aperçu à 150 ms, fin à Échap, retour, fermeture ; fantôme dessiné |

Complexité : un plan O(n log n) par aperçu (n fenêtres de la stage), une écriture par fenêtre.
Tests : `Tests/RoadieDaemonTests/Spec078PreviewTests.swift` (disposition future arbre et
master-stack, maintien et échéance, demande d'aperçu selon la ligne).
