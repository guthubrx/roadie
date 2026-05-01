# Tasks: RoadieBlur (SPEC-009)

**Feature** : SPEC-009 blur | **Branch** : `009-blur`

## Garde-fou : 150 LOC strict (cible 100)

## Phase 1 — Setup
- [x] T001 Créer `Sources/RoadieBlur/` et `Tests/RoadieBlurTests/`
- [x] T002 `Package.swift` : target `.dynamicLibrary` + test target

## Phase 2 — Foundational
- [x] T010 Vérifier `OSAXCommand.setBlur(wid:radius:)` dispo SPEC-004 *(présent via cherry-pick SPEC-004)*

## Phase 3 — User Story 1 (P1) MVP per-app rules
- [x] T020 [US1] `Sources/RoadieBlur/Module.swift` (~80 LOC) : `BlurConfig` + `BlurRule` Codable, `BlurModule.shared`, `radius(for:config:)` pure, subscribe/handleEvent/shutdown, `@_cdecl module_init` *(implémenté à 82 LOC, mono-fichier comme prévu, fonction pure `radius(for:config:)` clamp [0,100])*
- [x] T030 [P] [US1] `Tests/RoadieBlurTests/RuleMatcherTests.swift` (~30 LOC) *(6 tests : testNoRulesNoDefault, testDefaultOnly, testRuleMatchOverridesDefault, testClampAbove100, testClampBelowZero, testZeroIsValidNoOp)*
- [ ] T031 [US1] `tests/integration/21-fx-blur.sh` : config rule Slack 30, lancer Slack, vérifier `set_blur radius=30` dans log osax *(reporté SPEC-009.1)*

## Phase 4 — User Story 2 (P2) blur global
- [x] T040 [US2] Si `default_radius > 0` → applique sur toutes fenêtres au création (sans rule match) *(implémenté dans `BlurModule.handle(event:)` : `radius(for: bundleID, config:)` retourne defaultRadius si pas de rule match — appliqué uniquement si `target > 0` pour éviter l'envoi d'un setBlur radius=0 inutile)*

## Phase 5 — Polish
- [x] T050 [P] Mesurer LOC ≤ 150 strict *(82 LOC mesurées — PASS, cible 100, plafond 150)*
- [ ] T051 [P] Doc quickstart.md SPEC-004 *(reporté SPEC-009.1)*
- [x] T052 REX *(implementation.md créé)*

## Implementation Strategy

**MVP = Phase 1+2+3** = 5 tâches → per-app blur ✅
Total : **9 tâches**, ~1 jour
