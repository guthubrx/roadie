# Plan — SPEC-014 Manipulation interactive de l'arbre BSP

## Architecture

```
RoadieTiler/BSPTree.swift (MODIFIÉ)
├── swapping(_ a:_ b:)            — échange deux feuilles (structure préservée)
├── warping(_ window: nextTo: side:) — remove + insert à côté de la voisine
└── resizing(window: orientation: delta:) — ajuste le ratio du split ancêtre

RoadieDaemon/WindowCommands.swift (MODIFIÉ)
└── move/warp/resize : si stage.mode == .spatialBsp → opération sur l'arbre + persist + relayout
    sinon comportement actuel (mutableBsp)

RoadieDaemon/StageStore.swift : helpers bspTree(for:)/setBSPTree (déjà SPEC-013)
```

## Étapes

1. **Opérations d'arbre (T001-T003)** : `swapping`, `warping`, `resizing` dans `BSPTree.swift` + tests `BSPTreeMutationTests`.
2. **Câblage commandes (T004-T006)** : dans `WindowCommands`, brancher move/warp/resize sur l'arbre pour `.spatialBsp`. Helper `applyTreeMutation(scope:, mutate:)` qui lit l'arbre, applique, persiste (si writer), retire l'intent et laisse le tiler re-tiler.
3. **Validation (T007-T009)** : build, tests complets, smoke.

## Décisions

- `resizing` prend une orientation cible (`vertical` pour resize gauche/droite, `horizontal` pour haut/bas) + un delta signé ; trouve le split ancêtre le plus profond de cette orientation contenant la fenêtre et ajuste son ratio.
- `warping` = `removing(window)` puis `inserting(window, nextTo: neighbor, side:)` selon la direction.
- Le câblage Direction→paramètres se fait dans WindowCommands (RoadieDaemon connaît `Direction`).

## Article XVIII
Opérations O(n) sur l'arbre, n borné (fenêtres d'un stage). Hors hot path serré.

## PR ready
- [ ] build OK · tests verts (455 + nouveaux)
- [ ] swap/resize persistent · modes existants inchangés
