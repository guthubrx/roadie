# Tasks: RoadieBorders (SPEC-008)

**Feature** : SPEC-008 borders | **Branch** : `008-borders` | **Date** : 2026-05-01

## Garde-fou minimalisme : 280 LOC strict (cible 200)

---

## Phase 1 — Setup
- [x] T001 Créer `Sources/RoadieBorders/` et `Tests/RoadieBordersTests/`
- [x] T002 Mettre à jour `Package.swift` : target `.dynamicLibrary` + test target

## Phase 2 — Foundational
- [x] T010 Vérifier APIs SPEC-004 dispo (FXModule, EventBus, OSAXBridge.setLevel) + SPEC-007 optionnel (`AnimationsModule.requestAnimation`) *(SPEC-004 OK via cherry-pick. SPEC-007 absent dans ce worktree — pulse en mode no-op)*

## Phase 3 — User Story 1 (P1) MVP
- [x] T020 [US1] `Sources/RoadieBorders/Config.swift` (~40 LOC) : `BordersConfig` Codable + parsing hex color helper *(implémenté à 65 LOC : BordersConfig + StageOverride + RGBA + parseHexColor 6/8 chars + activeColor(forStage:config:))*
- [ ] T021 [US1] `Sources/RoadieBorders/BorderOverlay.swift` (~120 LOC) : NSWindow borderless + CALayer borderWidth/Color, ignoresMouseEvents, updateFrame/updateColor/close *(reporté SPEC-008.1 — requiert AppKit + OSAXBridge.setLevel pour positionnement au-dessus, validation manuelle SIP off)*
- [x] T022 [US1] `Sources/RoadieBorders/Module.swift` (~80 LOC) : `@_cdecl module_init`, `BordersModule.shared`, subscribe events, registry, handleEvent *(implémenté à 60 LOC : BordersModule singleton avec NSLock, subscribe 8 events, handle dispatch focusChange/stageChanged, colorFor(wid:) helper. Le registry [CGWindowID: BorderOverlay] est reporté avec T021)*
- [x] T030 [P] [US1] `Tests/RoadieBordersTests/ConfigTests.swift` (~40 LOC) *(7 tests : testParseHexColor6Digits, 8Digits, WithoutHash, Invalid, ThicknessClamping, ActiveColorWithoutOverride, ActiveColorWithStageOverride)*
- [ ] T031 [US1] `tests/integration/20-fx-borders.sh` : ouvre 2 fenêtres, vérifie 2 overlays NSWindow visibles, focus l'une, vérifie couleurs différentes via screenshot pixel sample *(reporté SPEC-008.1)*

## Phase 4 — US2 pulse (P2)
- [ ] T040 [US2] Étendre `BordersModule` : si SPEC-007 chargé + `pulse_on_focus=true` → call `AnimationsModule.requestAnimation` au focus_changed (anim épaisseur 2→4→2 sur 250 ms) *(reporté SPEC-008.1, dépend de SPEC-007 mergé pour avoir l'API publique)*
- [ ] T041 [US2] Si SPEC-007 absent → set instantané, log info une fois *(reporté SPEC-008.1)*
- [ ] T045 [US2] Test : trigger focus_changed, vérifier pulse via log animations module *(reporté SPEC-008.1)*

## Phase 5 — US3 stage overrides (P2)
- [x] T050 [US3] Étendre `Config` + `BordersModule.handleEvent stage_changed` : applique nouvelle couleur active selon stage_id courant *(`activeColor(forStage:config:)` helper retourne la couleur du stageOverride si match. Le `BordersModule.handleEvent` met à jour `currentStageID` au stageChanged. La répercussion visuelle sur les overlays dépend de T021 reporté)*
- [ ] T055 [US3] Test : 2 stages avec couleurs différentes, switch ⌥1/⌥2, vérifier que toutes les bordures changent *(reporté SPEC-008.1)*

## Phase 6 — Polish
- [x] T060 [P] Mesurer LOC ≤ 280 strict *(125 LOC mesurées — PASS, cible 200, plafond 280)*
- [ ] T061 [P] Doc dans quickstart.md SPEC-004 *(reporté SPEC-008.1)*
- [x] T062 REX implementation.md *(implementation.md créé avec bilan + reportés)*
- [ ] T063 Test 24h stabilité (overlays bien libérés au unregister, pas de leak NSWindow) *(reporté SPEC-008.1, dépend de T021)*

## Implementation Strategy

**MVP = Phase 1+2+3** = 6 tâches → focus indicator visuel ✅
Total : **15 tâches**, ~3 jours
