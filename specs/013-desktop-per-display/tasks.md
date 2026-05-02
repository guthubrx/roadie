# Tasks — SPEC-013 Desktop par Display (mode global ↔ per_display)

**Feature** : 013-desktop-per-display
**Branch** : `013-desktop-per-display`
**Total tasks** : 36

## Phase 1 — Setup

- [x] T001 Créer la structure de dossier persistance vide `~/.config/roadies/displays/` au boot du daemon (ne fait rien si déjà présent) dans `Sources/roadied/main.swift` bootstrap.

## Phase 2 — Foundational (prérequis communs aux 5 user stories)

- [x] T002 [P] Ajouter `enum DesktopMode: String, Codable, Sendable { case global ; case perDisplay = "per_display" }` dans `Sources/RoadieCore/Config.swift`, avec parser TOML qui fallback à `.global` + log warn si valeur inconnue (FR-001, FR-002).
- [x] T003 Ajouter `var mode: DesktopMode = .global` dans la struct `DesktopsConfig` de `Sources/RoadieCore/Config.swift` + Codable encode/decode.
- [x] T004 [P] Refondre `DesktopRegistry.currentID: Int` en `currentByDisplay: [CGDirectDisplayID: Int]` dans `Sources/RoadieDesktops/DesktopRegistry.swift`. Ajouter compatibility shim `func currentID(for displayID: CGDirectDisplayID? = nil) -> Int` (FR-004). **Approche choisie** : currentByDisplay coexiste avec currentID legacy (pas de breaking change).
- [x] T005 Ajouter `var mode: DesktopMode = .global` dans `DesktopRegistry`, propagé depuis Daemon au boot. Méthode `setMode(_:)` qui synchronise les entries `currentByDisplay` lors du switch global ↔ per_display selon spec data-model.md transition R6 (FR-003, FR-006).
- [x] T006 Implémenter `DesktopRegistry.setCurrent(_ desktopID: Int, on displayID: CGDirectDisplayID)` qui mute toute la map en mode global et uniquement la cible en per_display (FR-005, FR-006). Helper `syncCurrentByDisplay(presentIDs:)` ajouté pour init/cleanup. Émission event display_id : reportée à T050.
- [x] T007 Mettre à jour tous les call-sites de `DesktopRegistry.currentID` dans `Sources/roadied/main.swift` et `Sources/roadied/CommandRouter.swift` pour utiliser `currentID(for: displayID)` ou `setCurrent(_:on:)` selon contexte. **Aucun changement de comportement attendu en mode global.** Approche : compat shim — `currentID` legacy maintenu pour mode global ; per_display utilise `currentByDisplay` via les nouveaux handlers.
- [x] T008 Créer `Sources/RoadieDesktops/DesktopMigration.swift` avec `func runIfNeeded(configDir: URL, primaryUUID: String) throws -> Int` qui détecte `~/.config/roadies/desktops/`, le déplace via `FileManager.moveItem` vers `displays/<primaryUUID>/desktops/`, écrit `current.toml` initial, retourne le count (FR-021, FR-022, FR-023).
- [x] T009 Brancher `DesktopMigration.runIfNeeded` dans `Daemon.bootstrap()` AVANT l'init du `DesktopRegistry` (Sources/roadied/main.swift), avec log info `migration v2->v3 completed`.

## Phase 3 — User Story 1 : Activer le mode per_display (P1, MVP)

**Goal** : `roadie desktop focus N` en mode per_display affecte uniquement le display de la frontmost.

**Independent Test** : 2 écrans, focus sur LG, `roadie desktop focus 2` → seul LG bascule. `roadie desktop list` montre les 2 currents distincts.

- [x] T010 [US1] Dans `CommandRouter.swift` handler `desktop.focus`, lire `daemon.desktopRegistry.mode`. En mode `global` : path V2 inchangé. En mode `per_display` : nouveau handler `handleDesktopFocusPerDisplay` qui résout displayID via `displayIDContainingPoint`, appelle `setCurrent(N, on: displayID)`, scope hide/show au display.
- [x] T011 [US1] Hide/show ciblé implémenté inline dans `handleDesktopFocusPerDisplay` : itère `registry.allWindows`, filtre par display, applique `setLeafVisible` + `HideStrategyImpl.hide/show` selon `state.desktopID == newID`.
- [x] T012 [P] [US1] Dans `CommandRouter.swift` handler `desktop.list`, output JSON branche sur `mode` : en `per_display`, ajouter le tableau `displays[]` avec `current` par display ; en `global`, format V2 préservé (FR-010, contracts §2). Réponse contient désormais `mode` + `current_by_display`.
- [x] T013 [P] [US1] Dans `CommandRouter.swift` handler `desktop.current`, output JSON branche sur `mode` : `per_display` → display de frontmost + current ; `global` → current global (FR-009). Réponse contient `mode` + `display_id` quand applicable.
- [ ] T014 [P] [US1] Dans `Sources/roadie/main.swift` formatter table CLI pour `desktop list` : si JSON contient `displays[]`, afficher colonnes par display (un `*` dans la colonne du current de chaque écran). Sinon format V2 (FR-010). [DEFERRED] : reporter à V3.1, le JSON contient déjà les champs nécessaires.
- [x] T015 [P] [US1] Test : `Tests/RoadieDesktopsTests/DesktopRegistryPerDisplayTests.swift` avec 5 cas : mode global (sync), mode per_display (indep), transition global→per_display, transition per_display→global, fallback display introuvable.

## Phase 4 — User Story 2 : Drag cross-écran adopte le desktop cible (P1)

**Goal** : drag d'une fenêtre de display A → B, en mode per_display, fait adopter le current desktop du display B à la fenêtre.

**Independent Test** : drag manuel cross-écran sur 2 displays différents, vérifier `desktopID` mis à jour, fenêtre reste visible.

- [x] T020 [US2] Modifier `Daemon.onDragDrop()` : après le `moveWindow(wid, fromDisplay:src, toDisplay:dst)`, en mode `per_display`, lire `currentByDisplay[dst]` et appeler `registry.update(wid) { $0.desktopID = newDesktopID }` (FR-011). En mode `global`, ne rien changer (FR-013).
- [x] T021 [US2] `CommandRouter.handleWindowDisplay(N)` : après moveWindow + setBounds, en mode `per_display`, met à jour le `desktopID` de la fenêtre déplacée à `currentByDisplay[targetDisplayID]` (FR-012).
- [ ] T022 [US2] Persister la nouvelle assignation : trigger `DesktopPersistence.saveDesktopWindows(displayUUID:src, desktopID:oldDeskID)` (retire la fenêtre) ET `saveDesktopWindows(displayUUID:dst, desktopID:newDeskID)` (ajoute) après chaque drag/move cross-display (FR-016). [DEFERRED V3.1] : le snapshot global au focus suivant rattrape.
- [ ] T023 [P] [US2] Test : `Tests/RoadieTilerTests/DragCrossDisplayDesktopTests.swift` avec 3 cas. [DEFERRED V3.1].

## Phase 5 — User Story 3 : Recovery écran débranché/rebranché (P1)

**Goal** : au rebranchement, restaurer les fenêtres + le current desktop du display d'après son state persisté disque.

**Independent Test** : LG desktop 2 avec 3 fenêtres, débrancher → migration. Rebrancher → 3 fenêtres reviennent + current=2 restauré.

- [x] T030 [US3] Créé `Sources/RoadieDesktops/DesktopPersistence.swift` avec API : `saveCurrent / loadCurrent / saveDesktopWindows / loadDesktopWindows`. Format TOML minimaliste, parser propre.
- [x] T031 [US3] Dans `Daemon.handleDisplayConfigurationChange`, pour chaque `added` display : `loadCurrent` + `setCurrent` ; pour chaque desktop, `loadDesktopWindows` + matching N1 (cgwid) / N2 (bundleID + title prefix).
- [x] T032 [US3] Restoration frame implémentée : `AXReader.setBounds(element, frame: snap.expectedFrame)` + `layoutEngine.moveWindow` + applyLayout. Process tué → ignore silencieux.
- [x] T033 [US3] Vérifié : `clearDisplayRoot` du runtime ne touche PAS au disque. `displays/<uuid>/` est conservé.
- [x] T034 [US3] Hook persistance dans `handleDesktopFocusPerDisplay` : à chaque `setCurrent(_:on:)`, snapshot des fenêtres du desktop courant du display + `saveCurrent` + `saveDesktopWindows`.
- [x] T035 [P] [US3] Test : `Tests/RoadieDesktopsTests/DesktopPersistenceTests.swift` (5 cas : roundtrip current, missing file, roundtrip windows, missing windows file, escape titre).

## Phase 6 — User Story 4 : Migration ascendante V2 → V3 (P2)

**Goal** : booting V3 sur un layout V2 existant déplace transparente sans intervention.

**Independent Test** : poser un état V2 manuellement dans `~/.config/roadies/desktops/`, démarrer V3, vérifier dossier déplacé sous primary UUID.

- [x] T040 [P] [US4] Test : `Tests/RoadieDesktopsTests/DesktopMigrationTests.swift` (3 cas : no-op, V2→V3, idempotente).
- [x] T041 [US4] `primaryUUID` résolu via `NSScreen.frame.origin == .zero` ?? `NSScreen.main` directement dans bootstrap (pas besoin de DisplayRegistry). Skip silencieux si UUID indisponible.

## Phase 7 — User Story 5 : Visibilité de l'état per-display (P2)

**Goal** : `desktop list` colonnes par display + events `desktop_changed` incluent `display_id`.

**Independent Test** : `roadie desktop list` 2 colonnes, `roadie events --follow` émet `display_id` par event focus.

- [x] T050 [US5] Event `desktop_changed` enrichi avec `display_id` + `mode` dans 2 paths : `handleDesktopFocusPerDisplay` (mode per_display) et `DesktopSwitcher.performSwitch` (mode global, display_id = primary). Events SPEC-012 inchangés.
- [ ] T051 [P] [US5] Help CLI annotation. [DEFERRED V3.1].
- [ ] T052 [P] [US5] Test events. [DEFERRED V3.1] : `DesktopEventsTests` SPEC-012 reste valide.

## Phase 8 — Polish & Cross-Cutting

- [x] T060 CHANGELOG.md : entrée SPEC-013 + Fixed pour le bug DesktopSwitcher activate.
- [ ] T061 README.md exemple `mode`. [DEFERRED V3.1].
- [x] T062 Audit LOC informel : nouveaux fichiers `DesktopMigration.swift` (~70 LOC), `DesktopPersistence.swift` (~150 LOC). Modifications cumulées Config + DesktopRegistry + main + CommandRouter + DesktopSwitcher : ~350 LOC. **Total ~570 LOC**, sous la cible 600 et largement sous le plafond 800. ✅
- [x] T063 Test suite complète : 37 suites, 0 fail (33 V2 + 4 nouvelles SPEC-013).
- [x] T064 Smoke-test : restart daemon + `desktop list/current` JSON valide les nouveaux champs.
- [x] T065 tasks.md mis à jour avec checkmarks ; implementation.md complété.

## Dependencies

```
T001 (Setup)
  └→ T002, T003 (Config mode)
        └→ T004, T005 (DesktopRegistry refactor)
              └→ T006, T007 (setCurrent + propagate call-sites)
                    └→ T008, T009 (Migration V2→V3)
                          └→ Phase 3 US1 (T010..T015)
                          └→ Phase 4 US2 (T020..T023)
                          └→ Phase 5 US3 (T030..T035)
                          └→ Phase 6 US4 (T040..T041)
                          └→ Phase 7 US5 (T050..T052)
                                └→ Phase 8 Polish (T060..T065)
```

User stories sont **indépendantes** une fois les Phase 1-2 fondations posées. US1, US2, US3 peuvent être implémentées en parallèle par des contributeurs différents (mais dépendent toutes du refactor T004-T006).

## Parallel execution opportunities

- **T002 & T004** parallélisables (Config et DesktopRegistry indépendants).
- **T012, T013, T014** parallélisables (3 commandes CLI distinctes, fichiers différents).
- **T015, T023, T035, T040, T052** tests parallélisables (fichiers tests indépendants).

## Implementation strategy (MVP first)

1. **Sprint MVP** : Phase 1-2 (foundations) + US1 (Activer per_display) → permet déjà à l'utilisateur de basculer en mode séparé et de l'utiliser au quotidien si toutes ses fenêtres restent sur leur écran d'origine.
2. **Sprint 2** : US2 (drag cross-display) → débloque le workflow drag manuel.
3. **Sprint 3** : US3 (recovery branch/débranch) → débloque le workflow laptop dock.
4. **Sprint 4** : US4 (migration V2→V3) + US5 (visibility) → polish.

Le mode par défaut `global` garantit zéro régression à chaque sprint pour les utilisateurs qui n'activent pas le nouveau mode.
