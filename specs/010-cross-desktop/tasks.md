# Tasks: RoadieCrossDesktop (SPEC-010)

**Feature** : SPEC-010 cross-desktop | **Branch** : `010-cross-desktop`

## Garde-fou : 450 LOC strict (cible 300)

## Phase 1 — Setup
- [ ] T001 Créer `Sources/RoadieCrossDesktop/` et `Tests/RoadieCrossDesktopTests/`
- [ ] T002 `Package.swift` : target `.dynamicLibrary` + test target

## Phase 2 — Foundational
- [ ] T010 Vérifier APIs SPEC-004 + SPEC-003 dispos : `OSAXCommand.moveWindowToSpace/setSticky/setLevel`, `MultiDesktopManager.uuidFor(label:) / uuidFor(index:)` exposé public
- [ ] T011 Si SPEC-003 n'expose pas l'API → étendre SPEC-003 (+10 LOC max, ouvrir un PR sur sa branche). En attendant, fallback shell pipe `roadie desktop list --json | jq` (moins propre).

## Phase 3 — User Story 1 (P1) MVP : window space command
- [ ] T020 [US1] `Sources/RoadieCrossDesktop/Config.swift` (~50 LOC) : `CrossDesktopConfig` + `PinRule` + `ForceTilingConfig` Codable
- [ ] T021 [US1] `Sources/RoadieCrossDesktop/CommandHandler.swift` (~80 LOC) : `handleSpaceCommand(selector:)`, résout via SPEC-003 API, envoie `moveWindowToSpace` via osax, return exit code
- [ ] T022 [US1] `Sources/RoadieCrossDesktop/Module.swift` (~80 LOC) : `@_cdecl module_init`, registre command handlers
- [ ] T023 [US1] Étendre `Sources/roadie/main.swift` (+5 LOC) : sous-verbe `window space <selector>`
- [ ] T024 [US1] Étendre `Sources/roadied/CommandRouter.swift` (+15 LOC) : route `window.space` vers `CrossDesktopModule.handleSpaceCommand` si module loaded, sinon retourne `module_not_loaded` exit 4
- [ ] T030 [US1] `tests/integration/22-fx-crossdesktop.sh` : créer 2 desktops, ouvrir Safari sur 1, exec `roadie window space 2`, vérifier que Safari est sur desktop 2 (via `roadie windows list --on-desktop 2`)

## Phase 4 — US2 (P1) pinning rules
- [ ] T040 [US2] `Sources/RoadieCrossDesktop/PinEngine.swift` (~80 LOC) : `match(window:) -> String?` (UUID cible), helper `resolveByIndex(idx:)`, registre `[bundleID: PinRule]`
- [ ] T041 [US2] Étendre `Module.subscribe` : event `window_created` → PinEngine.match → si target → moveWindowToSpace
- [ ] T045 [P] [US2] `Tests/RoadieCrossDesktopTests/PinEngineTests.swift` (~50 LOC) : 6 cas (rule match desktop_label, rule match desktop_index, no match, multiple rules first wins, label invalid → nil, index invalid → nil)
- [ ] T046 [US2] Test integration : config rule Slack→comm, lancer Slack stub, vérifier `move_window_to_space` reçu côté osax avec UUID comm

## Phase 5 — US3 (P2) sticky window
- [ ] T050 [US3] CommandHandler.handleStickyCommand → `setSticky(wid: frontmost, sticky: bool)` + tracker
- [ ] T051 [US3] Sub-verbe `roadie window stick [bool]` dans CLI

## Phase 6 — US4 (P2) always-on-top
- [ ] T060 [US4] CommandHandler.handlePinCommand → `setLevel(wid, level: 24)` + LevelTracker
- [ ] T061 [US4] Sub-verbe `roadie window pin|unpin`

## Phase 7 — US5 (P3, peut être livré séparément) force-tiling
- [ ] T070 [US5] Étendre `Sources/RoadieTiler/LayoutEngine.swift` (+20 LOC max) : `if forceTilingEnabled && bundleIDsMatch → setFrame via osax au lieu d'AX`. Gated par flag config + module loaded.
- [ ] T071 [US5] Test : config avec FaceTime, ouvrir FaceTime, vérifier qu'il est tilé (frame set OK), via `roadie windows list` montre le frame attendu

## Phase 8 — Polish
- [ ] T080 [P] Mesurer LOC ≤ 450 strict
- [ ] T081 [P] Restauration shutdown : LevelTracker.restoreAll, StickyTracker.restoreAll. Ne déplace PAS les fenêtres au shutdown (acceptable).
- [ ] T082 [P] Doc quickstart.md SPEC-004
- [ ] T083 REX

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
