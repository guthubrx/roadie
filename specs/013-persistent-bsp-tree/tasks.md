# Tasks — SPEC-013 Arbre BSP persistant

## Couche 1 — Cœur pur (testable sans macOS)

- [X] T001 [P] Créer `Tests/RoadieTilerTests/BSPTreeTests.swift` (place 1/2/3 fenêtres, ratios, orientations, windowIDs ordre)
- [X] T002 Créer `Sources/RoadieTiler/BSPTree.swift` : enum `BSPTree` (leaf/split/empty) + `BSPOrientation` + `windowIDs`, `contains`, `place(in:innerGap:)`
- [X] T003 Faire passer `BSPTreeTests` (place)
- [X] T004 [P] Étendre `BSPTreeTests` : insertion focus (autres inchangés), suppression (frère récupère), direction left/right, orientation auto
- [X] T005 Implémenter `insert(window:nextTo:side:)`, `remove(window:)`, `adoptRatio(...)` dans `BSPTree.swift`
- [X] T006 Faire passer les tests d'insertion/suppression
- [X] T007 Créer `Sources/RoadieTiler/SpatialBSPLayoutStrategy.swift` + `LayoutRequest.bspTree` + branche `.spatialBsp` dans `LayoutPlanner`
- [X] T008 Ajouter `SpatialBSPLayoutStrategyTests` (via LayoutPlanner) et les faire passer

## Couche 2 — Intégration runtime

- [X] T009 Ajouter `WindowManagementMode.spatialBsp` (+ `roadieValue` `spatial_bsp`/`spatial`/`tree`) dans `Sources/RoadieCore/WindowManagementMode.swift`
- [X] T010 Étendre `WindowPlacementConfig` avec `newWindowSide` (`new_window_side`, défaut `"right"`) dans `Sources/RoadieCore/Config.swift`
- [X] T011 Tests parsing : mode `spatial_bsp` + `new_window_side`
- [X] T012 Ajouter `PersistentStage.bspTree: BSPTree?` (Codable optionnel) dans `Sources/RoadieDaemon/StageStore.swift`
- [X] T013 Tests round-trip JSON de `PersistentStage` avec arbre + migration depuis `members`
- [X] T014 Reconciliation dans `Sources/RoadieDaemon/DaemonSnapshot.swift` : insert nouvelles fenêtres à côté du focus (selon `newWindowSide`), remove disparues, pour les stages `.spatialBsp`
- [X] T015 Fournir l'arbre au `LayoutRequest` dans `DaemonSnapshot.layoutPlan` pour le mode `.spatialBsp`
- [X] T016 Tests d'intégration : nouvelle fenêtre divise le focus, fermeture remonte le frère, persistance

## Validation

- [X] T017 `swift build` (PATH Xcode) sans erreur
- [X] T018 `swift test` complet : tous verts ; modes existants inchangés
- [X] T019 Smoke deux modes (mono + modulaire) avec `default_strategy = spatial_bsp` + `implementation.md`
