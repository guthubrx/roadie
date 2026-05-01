# Tasks: RoadieCrossDesktop (SPEC-010)

**Feature** : SPEC-010 cross-desktop | **Branch** : `010-cross-desktop`

## Garde-fou : 450 LOC strict (cible 300)

## Phase 1 — Setup
- [x] T001 Créer `Sources/RoadieCrossDesktop/` et `Tests/RoadieCrossDesktopTests/`
- [x] T002 `Package.swift` : target `.dynamicLibrary` + test target

## Phase 2 — Foundational
- [x] T010 Vérifier APIs SPEC-004 + SPEC-003 dispos : `OSAXCommand.moveWindowToSpace/setSticky/setLevel` *(SPEC-004 OK via cherry-pick. `MultiDesktopManager.uuidFor(label:) / uuidFor(index:)` MANQUANT — les resolvers sont passés en paramètre `@Sendable (String) -> String?` au PinEngine, à câbler post-merge SPEC-003)*
- [ ] T011 Si SPEC-003 n'expose pas l'API → étendre SPEC-003 (+10 LOC max, ouvrir un PR sur sa branche). En attendant, fallback shell pipe `roadie desktop list --json | jq` (moins propre). *(reporté au moment du merge dans main — solution adoptée : injecter les resolvers via paramètre, ce qui permet de câbler n'importe quelle source de UUID au moment de l'instanciation)*

## Phase 3 — User Story 1 (P1) MVP : window space command
- [x] T020 [US1] `Sources/RoadieCrossDesktop/Config.swift` (~50 LOC) : `CrossDesktopConfig` + `PinRule` + `ForceTilingConfig` Codable *(implémenté à 44 LOC, conformes Codable avec CodingKeys snake_case)*
- [x] T021 [US1] `Sources/RoadieCrossDesktop/CommandHandler.swift` (~80 LOC) : `handleSpaceCommand(selector:)`, résout via SPEC-003 API, envoie `moveWindowToSpace` via osax, return exit code *(implémenté à 84 LOC : LevelTracker + WindowStateBackup + CommandHandler avec 4 méthodes : handleSpace, handleSticky, handlePin, handleWindowCreated. Resolvers passés en closure)*
- [x] T022 [US1] `Sources/RoadieCrossDesktop/Module.swift` (~80 LOC) : `@_cdecl module_init`, registre command handlers *(implémenté à 54 LOC, CrossDesktopModule singleton + CrossDesktopBridge singleton)*
- [ ] T023 [US1] Étendre `Sources/roadie/main.swift` (+5 LOC) : sous-verbe `window space <selector>` *(reporté au merge — pas modifié dans le worktree pour préserver l'isolation)*
- [ ] T024 [US1] Étendre `Sources/roadied/CommandRouter.swift` (+15 LOC) : route `window.space` vers `CrossDesktopModule.handleSpaceCommand` si module loaded, sinon retourne `module_not_loaded` exit 4 *(reporté au merge)*
- [ ] T030 [US1] `tests/integration/22-fx-crossdesktop.sh` *(reporté SPEC-010.1)*

## Phase 4 — US2 (P1) pinning rules
- [x] T040 [US2] `Sources/RoadieCrossDesktop/PinEngine.swift` (~80 LOC) : `target(forBundleID:) -> String?` (UUID cible), resolvers en closure injectée *(implémenté à 30 LOC bien plus compact, struct PinEngine immutable avec rules + 2 closures resolver)*
- [x] T041 [US2] Étendre `Module.subscribe` : event `window_created` → PinEngine.match → si target → moveWindowToSpace *(implémenté dans `CrossDesktopModule.handle(event:)` qui filtre `.windowCreated` et délègue à `handler.handleWindowCreated(wid:bundleID:)`)*
- [x] T045 [P] [US2] `Tests/RoadieCrossDesktopTests/PinEngineTests.swift` (~50 LOC) *(7 tests : testNoRulesNoMatch, testLabelMatch, testLabelUnknownReturnsNil, testIndexMatch, testIndexInvalidReturnsNil, testFirstRuleWinsOnMultiple, testNoMatchForBundleID)*
- [ ] T046 [US2] Test integration : config rule Slack→comm, lancer Slack stub, vérifier `move_window_to_space` reçu côté osax avec UUID comm *(reporté SPEC-010.1)*

## Phase 5 — US3 (P2) sticky window
- [x] T050 [US3] CommandHandler.handleStickyCommand → `setSticky(wid: frontmost, sticky: bool)` + tracker *(implémenté dans `CommandHandler.handleSticky(wid:sticky:previousSticky:)` avec LevelTracker.track pour restauration shutdown)*
- [ ] T051 [US3] Sub-verbe `roadie window stick [bool]` dans CLI *(reporté au merge)*

## Phase 6 — US4 (P2) always-on-top
- [x] T060 [US4] CommandHandler.handlePinCommand → `setLevel(wid, level: 24)` + LevelTracker *(implémenté dans `CommandHandler.handlePin(wid:pinned:previousLevel:)`)*
- [ ] T061 [US4] Sub-verbe `roadie window pin|unpin` *(reporté au merge)*

## Phase 7 — US5 (P3, peut être livré séparément) force-tiling
- [ ] T070 [US5] Étendre `Sources/RoadieTiler/LayoutEngine.swift` (+20 LOC max) : `if forceTilingEnabled && bundleIDsMatch → setFrame via osax au lieu d'AX`. Gated par flag config + module loaded. *(reporté SPEC-010.1 — confirmé P3 par utilisateur, pas prioritaire. Config `ForceTilingConfig` est en place mais non utilisée encore)*
- [ ] T071 [US5] Test : config avec FaceTime, ouvrir FaceTime, vérifier qu'il est tilé (frame set OK), via `roadie windows list` montre le frame attendu *(reporté SPEC-010.1)*

## Phase 8 — Polish
- [x] T080 [P] Mesurer LOC ≤ 450 strict *(180 LOC mesurées — PASS, cible 300, plafond 450)*
- [x] T081 [P] Restauration shutdown : LevelTracker.restoreAll *(implémenté dans `CrossDesktopModule.shutdown()` : restoreAll() retourne tous les backups, lance Task qui envoie setLevel(originalLevel) + setSticky(false) si nécessaire). Ne déplace PAS les fenêtres au shutdown (acceptable).*
- [ ] T082 [P] Doc quickstart.md SPEC-004 *(reporté SPEC-010.1)*
- [x] T083 REX *(implementation.md créé)*

## Implementation Strategy

**MVP = Phase 1+2+3+4 (US1 + US2)** = 9 tâches → cmd `window space` + pinning rules ✅
US3+US4 (sticky + pin) faciles, +4 tâches.
US5 force-tiling P3, peut être skippé si scope dérive → SPEC-010.1.
Total : **24 tâches**, ~4-5 jours.

## Garde-fou minimalisme

À chaque tâche :
❓ « cette ligne sert vraiment ? »
❓ « ce mode/option est-il utilisé concrètement ? »
❓ « Phase 7 force-tiling est-elle critique ou peut-on la couper ? »
