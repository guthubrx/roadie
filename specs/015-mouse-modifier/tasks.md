# Tasks — SPEC-015 Mouse modifier drag & resize

**Feature** : 015-mouse-modifier
**Branch** : `015-mouse-modifier`
**Total tasks** : 24

## Phase 1 — Setup

- [x] T001 Vérifier que `Input Monitoring` permission est obtenue au boot (déjà acquise pour MouseRaiser, juste tracer le statut au log si KO).

## Phase 2 — Foundational

- [x] T002 [P] Ajouter enums `ModifierKey` (ctrl/alt/cmd/shift/hyper/none) avec `nsFlags: NSEvent.ModifierFlags` computed dans `Sources/RoadieCore/Config.swift` (FR-001).
- [x] T003 [P] Ajouter enum `MouseAction` (move/resize/none) dans `Sources/RoadieCore/Config.swift`.
- [x] T004 Ajouter struct `MouseConfig { modifier, actionLeft, actionRight, actionMiddle, edgeThreshold }` dans `Sources/RoadieCore/Config.swift`. Codable avec parser tolérant : valeurs invalides → fallback default + log warn (FR-002, FR-003).
- [x] T005 Ajouter `var mouse: MouseConfig` dans `Config` root struct, défaut all-default.
- [x] T006 [P] Enum `Quadrant` (topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight) dans `Sources/RoadieCore/MouseDragHandler.swift` (NEW).
- [x] T007 Helper `computeQuadrant(cursor: CGPoint, frame: CGRect, edgeThreshold: Int) -> Quadrant` (FR-020). Pure function, testable.
- [x] T008 Helper `computeResizedFrame(startFrame: CGRect, delta: CGPoint, quadrant: Quadrant) -> CGRect` (FR-021). Pure function, testable.

## Phase 3 — User Story 1 : Drag move (P1)

**Goal** : Ctrl+LClick+drag déplace la fenêtre.

**Independent Test** : Ctrl-click au milieu d'une fenêtre, déplacer 200px → fenêtre suit.

- [x] T010 [US1] Créer `Sources/RoadieCore/MouseDragHandler.swift` (~200 LOC) : classe `MouseDragHandler` avec `init(config: MouseConfig, registry: WindowRegistry, layoutEngine: LayoutEngine)` et `start()` qui pose `NSEvent.addGlobalMonitorForEvents`.
- [x] T011 [US1] Implémenter `handleMouseDown(event: NSEvent, button: Int)` :
  - Check `event.modifierFlags.intersection(config.modifier.nsFlags) == config.modifier.nsFlags`.
  - Si match + bouton match config (left/right/middle) + action == .move → identifier wid via CGWindowList (pattern MouseRaiser) + démarrer session.
- [x] T012 [US1] Implémenter `handleMouseDragged(event: NSEvent)` pour mode `.move` :
  - throttle 30ms, calculer delta = currentCursor - startCursor.
  - newFrame = startFrame.offsetBy(delta).
  - `AXReader.setBounds(element, frame: newFrame)`.
  - `registry.updateFrame(wid, newFrame)`.
  - Au 1er drag, si tilée, `layoutEngine.removeWindow(wid)` + `state.isFloating=true` (FR-012).
- [x] T013 [US1] Implémenter `handleMouseUp(event: NSEvent)` pour mode `.move` :
  - setBounds final inconditionnel.
  - Si la fenêtre a traversé un display, déléguer à `daemon.onDragDrop` (SPEC-013) — interface via callback.
  - Détruire la session.
- [x] T014 [P] [US1] Test : `Tests/RoadieCoreTests/MouseConfigTests.swift` (3 cas : defaults, custom, fallback invalide).
- [x] T015 [P] [US1] Test : `Tests/RoadieCoreTests/MouseDragSessionTests.swift` (3 cas : delta move, throttle, cross-display).

## Phase 4 — User Story 2 : Drag resize quadrant-aware (P1)

**Goal** : Ctrl+RClick+drag dans un coin redimensionne avec ancre opposée fixe.

**Independent Test** : Ctrl+RClick coin TL d'une fenêtre, drag 100px en TL → fenêtre s'agrandit en TL, BR fixe.

- [x] T020 [US2] Étendre `handleMouseDown` pour mode `.resize` :
  - Calculer `quadrant = computeQuadrant(...)`.
  - Démarrer session avec mode `.resize` + quadrant.
- [x] T021 [US2] Étendre `handleMouseDragged` pour `.resize` :
  - delta = currentCursor - startCursor.
  - newFrame = computeResizedFrame(startFrame, delta, session.quadrant).
  - setBounds + updateFrame (throttlé).
- [x] T022 [US2] Étendre `handleMouseUp` pour `.resize` :
  - Si state.isTileable, `layoutEngine.adaptToManualResize(wid, newFrame:)` (FR-022).
  - Sinon commit final via updateFrame (FR-023).
- [x] T023 [P] [US2] Test : `Tests/RoadieCoreTests/MouseQuadrantTests.swift` (10 cas : 9 quadrants + center fallback).

## Phase 5 — User Story 3 : Configuration TOML (P2)

- [x] T030 [US3] Vérifier que `Config.swift` parse `[mouse]` section correctement avec defaults + fallbacks (test).
- [x] T031 [US3] Étendre `daemon.reload` (CommandRouter) pour reinit le `MouseDragHandler` avec la nouvelle config sans drag en cours perdu (FR-004).

## Phase 6 — User Story 4 : Coexistence avec MouseRaiser (P2)

- [x] T040 [US4] Modifier `Sources/RoadieCore/MouseRaiser.swift` `handleClick(at:)` pour skip si modifier configuré pressé. Lire la config courante via une référence injectée à `MouseConfig` au boot (FR-030, FR-031).

## Phase 7 — Bootstrap & integration

- [x] T050 Init `MouseDragHandler` dans `Daemon.bootstrap()` (Sources/roadied/main.swift) après `MouseRaiser`. Skip si Input Monitoring KO (FR-041).
- [x] T051 Brancher la callback `onCrossDisplayDrop` du `MouseDragHandler` vers `Daemon.onDragDrop` pour réutiliser le flow SPEC-013.

## Phase 8 — Polish

- [x] T060 Mettre à jour CHANGELOG.md avec entrée SPEC-015.
- [x] T061 Mettre à jour README.md section "configuration" avec `[mouse]` exemple.
- [x] T062 Audit LOC : vérifier que MouseDragHandler ≤ 250 LOC effectives.
- [x] T063 Run test suite complète : `swift test` doit passer 100 % (suites V14 + 3 nouvelles SPEC-015).
- [x] T064 Smoke-test runtime daemon : restart daemon, faire un Ctrl-LClick-drag manuel sur une fenêtre, vérifier le mouvement fluide.
- [x] T065 Cocher tous les T001-T064 + générer `implementation.md` final avec REX.

## Dependencies

```
T001 (Setup)
  └→ T002, T003, T004, T005 (Config foundations) [P]
        └→ T006, T007, T008 (Quadrant + helpers) [P]
              └→ Phase 3 US1 (T010..T015)
                    └→ Phase 4 US2 (T020..T023)
                          └→ Phase 5 US3 (T030..T031)
                          └→ Phase 6 US4 (T040)
                                └→ Phase 7 integration (T050, T051)
                                      └→ Phase 8 Polish (T060..T065)
```

## Parallel execution opportunities

- **T002, T003** parallélisables (enums distincts).
- **T006, T007, T008** parallélisables (helpers indépendants, pure functions).
- **T014, T015, T023** tests parallélisables (fichiers tests distincts).

## Implementation strategy (MVP first)

1. **Sprint MVP** : Phase 1-3 (foundations + US1 drag-move) → drag move utilisable au quotidien.
2. **Sprint 2** : US2 resize quadrant.
3. **Sprint 3** : US3 config flexibility + US4 coexistence raiser.
4. **Sprint Polish** : CHANGELOG + tests + smoke runtime.
