# Tasks: RoadieBorders (SPEC-008)

**Feature** : SPEC-008 borders | **Branch** : `008-borders` | **Date** : 2026-05-01

## Garde-fou minimalisme : 280 LOC strict (cible 200)

---

## Phase 1 — Setup
- [ ] T001 Créer `Sources/RoadieBorders/` et `Tests/RoadieBordersTests/`
- [ ] T002 Mettre à jour `Package.swift` : target `.dynamicLibrary` + test target

## Phase 2 — Foundational
- [ ] T010 Vérifier APIs SPEC-004 dispo (FXModule, EventBus, OSAXBridge.setLevel) + SPEC-007 optionnel (`AnimationsModule.requestAnimation`)

## Phase 3 — User Story 1 (P1) MVP
- [ ] T020 [US1] `Sources/RoadieBorders/Config.swift` (~40 LOC) : `BordersConfig` Codable + parsing hex color helper
- [ ] T021 [US1] `Sources/RoadieBorders/BorderOverlay.swift` (~120 LOC) : NSWindow borderless + CALayer borderWidth/Color, ignoresMouseEvents, updateFrame/updateColor/close
- [ ] T022 [US1] `Sources/RoadieBorders/Module.swift` (~80 LOC) : `@_cdecl module_init`, `BordersModule.shared @MainActor`, subscribe events, registry `[CGWindowID: BorderOverlay]`, handleEvent dispatch création/update/close
- [ ] T030 [P] [US1] `Tests/RoadieBordersTests/ConfigTests.swift` (~40 LOC) : parsing hex `#RRGGBB`, `#RRGGBBAA`, color(for:stageID), thickness clamp [0..20]
- [ ] T031 [US1] `tests/integration/20-fx-borders.sh` : ouvre 2 fenêtres, vérifie 2 overlays NSWindow visibles, focus l'une, vérifie couleurs différentes via screenshot pixel sample

## Phase 4 — US2 pulse (P2)
- [ ] T040 [US2] Étendre `BordersModule` : si SPEC-007 chargé + `pulse_on_focus=true` → call `AnimationsModule.requestAnimation` au focus_changed (anim épaisseur 2→4→2 sur 250 ms)
- [ ] T041 [US2] Si SPEC-007 absent → set instantané, log info une fois
- [ ] T045 [US2] Test : trigger focus_changed, vérifier pulse via log animations module

## Phase 5 — US3 stage overrides (P2)
- [ ] T050 [US3] Étendre `Config` + `BordersModule.handleEvent stage_changed` : applique nouvelle couleur active selon stage_id courant
- [ ] T055 [US3] Test : 2 stages avec couleurs différentes, switch ⌥1/⌥2, vérifier que toutes les bordures changent

## Phase 6 — Polish
- [ ] T060 [P] Mesurer LOC ≤ 280 strict
- [ ] T061 [P] Doc dans quickstart.md SPEC-004
- [ ] T062 REX implementation.md
- [ ] T063 Test 24h stabilité (overlays bien libérés au unregister, pas de leak NSWindow)

## Implementation Strategy

**MVP = Phase 1+2+3** = 6 tâches → focus indicator visuel ✅
Total : **15 tâches**, ~3 jours
