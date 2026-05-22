# Tasks — SPEC-014 Manipulation interactive de l'arbre BSP

## Opérations d'arbre (RoadieTiler)
- [X] T001 Créer `Tests/RoadieTilerTests/BSPTreeMutationTests.swift` (swap, warp, resize)
- [X] T002 Ajouter `swapping(_:_:)`, `warping(_:nextTo:side:)`, `resizing(window:orientation:delta:)` dans `Sources/RoadieTiler/BSPTree.swift`
- [X] T003 Faire passer `BSPTreeMutationTests`

## Câblage commandes (RoadieDaemon)
- [X] T004 Ajouter helper `applyBSPTreeMutation(scope:mutate:)` dans `Sources/RoadieDaemon/WindowCommands.swift` (lit l'arbre, applique, persiste si writer, retire l'intent)
- [X] T005 Brancher `move`/`warp`/`resize` sur l'arbre quand `stage.mode == .spatialBsp` (sinon comportement actuel)
- [X] T006 Exposer le mode du stage actif au branchement (lecture via snapshot.state.stage(scope:).mode)

## Validation
- [X] T007 `swift build` (PATH Xcode) sans erreur
- [X] T008 `swift test` complet : tous verts
- [X] T009 Smoke + `implementation.md`
