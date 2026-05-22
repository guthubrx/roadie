# Plan d'implémentation — SPEC-013 Arbre BSP persistant

## Architecture cible

```
RoadieTiler/
├── BSPTree.swift            (NOUVEAU) — modèle d'arbre + opérations pures
│   ├── enum BSPTree { leaf | split | empty }
│   ├── insert(window:nextTo:side:) / remove(window:) / windowIDs / place(in:)
│   └── adoptRatio(...) (resize manuel)
├── SpatialBSPLayoutStrategy.swift (NOUVEAU) — plan(request) via l'arbre
└── LayoutTypes.swift        (MODIFIÉ) — LayoutRequest porte l'arbre ; LayoutPlanner branche le mode

RoadieCore/
├── WindowManagementMode.swift (MODIFIÉ) — cas .spatialBsp
└── Config.swift             (MODIFIÉ) — WindowPlacementConfig.newWindowSide

RoadieDaemon/
├── StageStore.swift         (MODIFIÉ) — PersistentStage.bspTree
└── DaemonSnapshot.swift     (MODIFIÉ) — reconciliation arbre + fourniture à layoutPlan
```

## Couche 1 — Cœur pur (testable sans macOS)

### Étape 1 — Modèle d'arbre (T001-T003)
- `Sources/RoadieTiler/BSPTree.swift` : enum + `BSPOrientation`.
- Opérations : `windowIDs`, `contains`, `place(in:innerGap:)`.
- Tests : `BSPTreeTests` (place 1/2/3 fenêtres, ratios, orientations).

### Étape 2 — Insertion / suppression (T004-T006)
- `insert(window:nextTo:side:)` : divise la feuille focus.
- `remove(window:)` : remonte le frère.
- `adoptRatio(forSplitContaining:ratio:)` : resize manuel.
- Tests : insertion focus (les autres ne bougent pas), fermeture (frère récupère), direction left/right, orientation auto.

### Étape 3 — Stratégie de layout (T007-T008)
- `Sources/RoadieTiler/SpatialBSPLayoutStrategy.swift` : `plan(request)` utilise `request.bspTree`.
- `LayoutRequest.bspTree: BSPTree?` ; `LayoutPlanner` branche `.spatialBsp`.
- Tests : `SpatialBSPLayoutStrategyTests` via LayoutPlanner.

## Couche 2 — Intégration runtime

### Étape 4 — Mode + config (T009-T011)
- `WindowManagementMode.spatialBsp` (+ `roadieValue` `spatial_bsp`/`spatial`/`tree`).
- `WindowPlacementConfig.newWindowSide` (`new_window_side`, défaut `right`).
- Tests parsing config.

### Étape 5 — Persistance (T012-T013)
- `PersistentStage.bspTree: BSPTree?` (Codable, décodage optionnel rétro-compat).
- Migration : arbre construit depuis `members` si `mode == .spatialBsp` et arbre absent.
- Tests round-trip JSON.

### Étape 6 — Reconciliation + branchement (T014-T016)
- Dans `DaemonSnapshot` : pour un stage `.spatialBsp`, reconcilier l'arbre (insert nouvelles fenêtres à côté du focus selon `newWindowSide`, remove disparues), persister, fournir à `layoutPlan`.
- `orderedWindowIDs` / `layoutPlan` : passer l'arbre dans le `LayoutRequest`.
- Tests d'intégration : nouvelle fenêtre divise le focus, fermeture, persistance.

### Étape 7 — Validation (T017-T019)
- `swift build` + `swift test` complet.
- Smoke : activer `default_strategy = spatial_bsp`, ouvrir/fermer des fenêtres dans les deux modes (mono + modulaire), vérifier insertion focalisée + direction.
- `implementation.md`.

## Considérations constitutionnelles

| Article | Application |
|---|---|
| III SpecKit | spec/plan/tasks ✓ |
| IV Disjoncteur | Couche 1 testée avant couche 2 ; max 3 tentatives/blocage |
| VII ADR | Décision arbre persistant → ADR candidate (`docs/decisions/`) |
| XV Test-Before-Next | build + tests après chaque étape |
| XVIII Complexité | place/insert/remove = O(n) sur l'arbre (n feuilles, borné par fenêtres du stage). Documenter. |

## Critères PR ready

- [ ] `swift build` OK
- [ ] `swift test` : tous verts (existants + nouveaux BSPTree/SpatialBSP)
- [ ] Modes existants inchangés (balanced/dwindle/masterStack/float)
- [ ] Nouvelle fenêtre divise uniquement le focus (SC-001)
- [ ] `new_window_side` respecté (SC-002)
- [ ] Arbre persiste au redémarrage (SC-003)
- [ ] Pas de perte de fenêtre (SC-005)
