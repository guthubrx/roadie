# Tasks: RoadieBlur (SPEC-009)

**Feature** : SPEC-009 blur | **Branch** : `009-blur`

## Garde-fou : 150 LOC strict (cible 100)

## Phase 1 — Setup
- [ ] T001 Créer `Sources/RoadieBlur/` et `Tests/RoadieBlurTests/`
- [ ] T002 `Package.swift` : target `.dynamicLibrary` + test target

## Phase 2 — Foundational
- [ ] T010 Vérifier `OSAXCommand.setBlur(wid:radius:)` dispo SPEC-004

## Phase 3 — User Story 1 (P1) MVP per-app rules
- [ ] T020 [US1] `Sources/RoadieBlur/Module.swift` (~80 LOC) : `BlurConfig` + `BlurRule` Codable, `BlurModule.shared`, `radius(for:config:)` pure, subscribe/handleEvent/shutdown, `@_cdecl module_init`
- [ ] T030 [P] [US1] `Tests/RoadieBlurTests/RuleMatcherTests.swift` (~30 LOC) : rule match → radius rule, no match → defaultRadius, clamp out of range, empty rules
- [ ] T031 [US1] `tests/integration/21-fx-blur.sh` : config rule Slack 30, lancer Slack, vérifier `set_blur radius=30` dans log osax

## Phase 4 — User Story 2 (P2) blur global
- [ ] T040 [US2] Si `default_radius > 0` → applique sur toutes fenêtres au création (sans rule match)

## Phase 5 — Polish
- [ ] T050 [P] Mesurer LOC ≤ 150 strict
- [ ] T051 [P] Doc quickstart.md SPEC-004
- [ ] T052 REX

## Implementation Strategy

**MVP = Phase 1+2+3** = 5 tâches → per-app blur ✅
Total : **9 tâches**, ~1 jour
