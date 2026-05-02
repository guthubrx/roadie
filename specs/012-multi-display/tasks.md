# Tasks — SPEC-012 Roadie Multi-Display

**Branch** : `012-multi-display` | **Date** : 2026-05-02
**Plan** : [plan.md](./plan.md) | **Spec** : [spec.md](./spec.md)

Convention : `- [ ] T<nnn> [P?] [US<k>?] Description + chemin`. `[P]` parallélisable. `[US<k>]` associé à User Story k.

---

## Phase 1 : Setup

Préparer les fichiers et dépendances de base.

- [x] T001 Vérifier que `RoadieCore` lie déjà `AppKit` et `CoreGraphics` (devraient l'être via SkyLight imports SPEC-011) — pas de modif Package.swift nécessaire en théorie ; sinon ajouter `linkerSettings .linkedFramework("AppKit")` dans `Package.swift` target RoadieCore
- [x] T002 [P] Créer `Sources/RoadieCore/Display.swift` (entité Pure data, Sendable, Codable) — squelette uniquement, conforme à data-model.md
- [x] T003 [P] Créer `Tests/RoadieCoreTests/DisplayRegistryTests.swift` (squelette empty test class)
- [x] T004 [P] Créer `Tests/RoadieDesktopsTests/MultiDisplayPersistenceTests.swift` (squelette)
- [x] T005 [P] Étendre `Tests/StaticChecks/no-cgs.sh` pour inclure `Sources/RoadieCore/DisplayRegistry.swift` et `Sources/RoadieCore/Display.swift` dans le périmètre (modifs minimes du glob — déjà couvert par `Sources/RoadieDesktops/` ; il faut élargir au scope SPEC-012)

---

## Phase 2 : Foundational

Briques de base bloquantes pour toutes les user stories.

- [x] T006 [P] Implémenter `Sources/RoadieCore/Display.swift` avec struct `Display` (id, index, uuid, name, frame, visibleFrame, isMain, isActive, tilerStrategy, gapsOuter, gapsInner) + initializer convenience depuis `NSScreen` (R-001, FR-001). Codable + Sendable.
- [x] T007 [P] Créer `Sources/RoadieCore/DisplayProvider.swift` : protocol `DisplayProvider` avec `func currentScreens() -> [NSScreen]`. Impl `NSScreenDisplayProvider` (production) + `MockDisplayProvider` (tests). Pattern R-011.
- [x] T008 Créer `Sources/RoadieCore/DisplayRegistry.swift` : actor avec `displays: [Display]`, `provider: any DisplayProvider`, `activeID: CGDirectDisplayID?`. Méthodes `refresh()` async, `display(at:)`, `display(forID:)`, `display(forUUID:)`, `displayContaining(point:)`, `setActive(id:)`, `count`. Conforme R-001..R-003 + FR-001..003, FR-005.
- [x] T009 [US7] Étendre `DisplayRegistry` : observer `NSApplication.didChangeScreenParametersNotification` dans `init()`, déclencher `refresh()` async + recovery (FR-002).
- [x] T010 [P] Étendre `Sources/RoadieDesktops/DesktopState.swift` : ajouter champ `displayUUID: String?` sur `WindowEntry`. Backward-compat (Codable.decode tolère absence). Conforme FR-020.
- [x] T011 Mettre à jour `Sources/RoadieDesktops/Parser.swift` : sérialisation/désérialisation `display_uuid` champ optionnel TOML.
- [x] T012 [P] Tests `Tests/RoadieDesktopsTests/MultiDisplayPersistenceTests.swift` : round-trip `WindowEntry` avec et sans `displayUUID`.

---

## Phase 3 : User Story 1 (P1) — Tiling indépendant par écran

**Goal** : `LayoutEngine` distribue les fenêtres dans le visibleFrame de chaque écran, indépendamment.

**Independent Test** : 2 fenêtres iTerm sur écran 1 + 2 Firefox sur écran 2 → chaque groupe tilé sur son écran.

- [ ] T013 [US1] Refondre `Sources/RoadieTiler/LayoutEngine.swift` : remplacer `rootNode: TilingContainer` unique par `rootsByDisplay: [CGDirectDisplayID: TilingContainer]`. Préserver l'API existante pour mono-écran (clé unique = mainDisplayID).
- [ ] T014 [US1] Étendre `LayoutEngine` : `func applyAll(displayRegistry:)` itère sur tous les displays connus et appelle `tiler.layout(rect:)` avec leur `visibleFrame` respectif (R-004, FR-006).
- [ ] T015 [US1] Étendre `LayoutEngine.insertWindow(_ wid:, focusedID:)` : si une fenêtre est insérée, déterminer son écran d'origine via `DisplayRegistry.displayContaining(point:)` (centre de sa frame) et l'insérer dans `rootsByDisplay[displayID]` (FR-005).
- [ ] T016 [US1] Étendre `LayoutEngine.setLeafVisible(_:_:)` : router vers le bon arbre selon le displayID de la fenêtre.
- [ ] T017 [US1] Compatibilité mono-écran : si `rootsByDisplay.count == 1`, comportement strictement équivalent à avant (FR-024).
- [ ] T018 [US1] Mettre à jour `Sources/roadied/main.swift` : injecter `DisplayRegistry` dans `LayoutEngine` au boot. Hooks SPEC-011 `LayoutHooks.applyLayout` doivent désormais appeler `applyAll(displayRegistry:)`.
- [ ] T019 [US1] Tests `Tests/RoadieTilerTests/LayoutEngineMultiDisplayTests.swift` : 2 mock screens, insérer 2 fenêtres dont 1 sur chaque, applyAll → vérifier que chaque fenêtre a une frame dans le visibleFrame de son écran (SC-001).
- [ ] T020 [US1] Régression : re-runner la suite SPEC-011 (`Tests/RoadieDesktopsTests/`) avec mono-screen mock, tous tests doivent passer (FR-024, SC-004).

**Checkpoint US1** : tiling per-écran fonctionnel ; régression mono-écran zéro.

---

## Phase 4 : User Story 2 (P1) — `roadie window display N`

**Goal** : déplacer la fenêtre frontmost vers un autre écran.

**Independent Test** : 1 fenêtre tilée sur écran 1, exécuter `roadie window display 2`, vérifier qu'elle est sur l'écran 2 et tilée selon sa stratégie.

- [ ] T021 [US2] Étendre `LayoutEngine` : méthode `func moveWindow(_ wid:, fromDisplay src:, toDisplay dst:)` qui retire le wid de `rootsByDisplay[src]` et insère dans `rootsByDisplay[dst]` (R-005).
- [ ] T022 [US2] Câbler dans `Sources/roadied/CommandRouter.swift` : nouveau handler `case "window.display"` qui : (1) valide selector range 1..count, (2) résout `from` via current frame, (3) calcule new frame centrée dans `dst.visibleFrame` avec clamp si dépasse, (4) `AXReader.setBounds`, (5) `LayoutEngine.moveWindow`, (6) update `WindowEntry.displayUUID` via DesktopRegistry, 
(7) `applyLayout(displayID: src)` + `applyLayout(displayID: dst)`. Conforme FR-008, contracts/cli-window-display.md.
- [ ] T023 [US2] Étendre `Sources/roadie/main.swift` : sous-commande `window display <selector>`. Selectors `1..N`, `prev`, `next`, `main` (FR-014). Pipe vers daemon socket.
- [ ] T024 [P] [US2] Tests intégration : MockDisplayRegistry 2 écrans, fenêtre sur écran 1, appel `window.display 2`, vérifier WindowEntry.displayUUID == écran 2 + frame mise à jour.
- [ ] T025 [P] [US2] Test selector invalide : `window.display 5` avec 2 écrans → erreur `unknown_display`.

**Checkpoint US2** : déplacement entre écrans fonctionnel.

---

## Phase 5 : User Story 3 (P1) — Détection branch/débranch

**Goal** : à la déconnexion, migration des fenêtres vers le primary en < 500 ms.

**Independent Test** : 2 fenêtres sur écran 2, simuler déconnexion (mockProvider.removeDisplay), vérifier que les 2 fenêtres sont sur primary avec frames dans son visibleFrame.

- [ ] T026 [US3] Étendre `DisplayRegistry.handleScreenChange()` (interne, déclenchée par observer T009) : compute diff `oldDisplays` vs `newDisplays` (R-006, FR-015).
- [ ] T027 [US3] Pour chaque écran retiré : itérer sur les fenêtres rattachées (via `LayoutEngine.rootsByDisplay[oldID]`), pour chaque wid : ajuster sa frame pour le mettre dans le visibleFrame du primary (clamp + shift), `AXReader.setBounds`, `LayoutEngine.moveWindow(from:oldID, to:primaryID)`, update WindowEntry.displayUUID = primary.uuid.
- [ ] T028 [US3] Pour chaque écran ajouté : initialiser `rootsByDisplay[newID] = TilingContainer()` vide.
- [ ] T029 [US3] Émettre `display_configuration_changed` event (FR-023).
- [ ] T030 [P] [US3] Tests `Tests/RoadieCoreTests/DisplayRegistryRecoveryTests.swift` : MockProvider initial 2 displays + 2 fenêtres sur display 2 ; remove display 2 ; vérifier que fenêtres sont migrées et leurs frames sont dans visibleFrame du primary.
- [ ] T031 [P] [US3] Test perf : cycle connect/disconnect 10 fois : 0 fenêtre fantôme (SC-006), perf < 500 ms par cycle (SC-003).

**Checkpoint US3** : recovery branch/débranch sans fenêtre fantôme.

---

## Phase 6 : User Story 4 (P1) — `roadie display list/current/focus`

**Goal** : CLI pour énumérer et focus écrans.

**Independent Test** : `roadie display list` retourne la bonne liste sur 1, 2, 3 écrans (mocks).

- [ ] T032 [US4] Câbler `Sources/roadied/CommandRouter.swift` : handler `case "display.list"` qui appelle `daemon.displayRegistry.displays`, formate avec `windows: count` par display (depuis `LayoutEngine.rootsByDisplay[displayID].leafCount`). Conforme contracts/cli-display.md (FR-011).
- [ ] T033 [US4] Câbler handler `case "display.current"` : retourne le display contenant la fenêtre frontmost (FR-012).
- [ ] T034 [US4] Câbler handler `case "display.focus"` : selector → display, focus la fenêtre frontmost de l'écran ou la première leaf tilée (FR-013).
- [ ] T035 [US4] Étendre `Sources/roadie/main.swift` : sous-commande `display list/current/focus`.
- [ ] T036 [P] [US4] Tests CLI : socket round-trip avec MockDisplayRegistry sur configurations 1, 2, 3 écrans (SC-005), vérifier output.

**Checkpoint US4** : CLI display fonctionnelle.

---

## Phase 7 : User Story 5 (P2) — Per-display config

**Goal** : section TOML `[[displays]]` avec overrides per-écran.

**Independent Test** : config 2 displays avec stratégies différentes, vérifier que le tiling diffère.

- [ ] T037 [US5] Étendre `Sources/RoadieCore/Config.swift` : ajouter struct `DisplayRule` (matchIndex, matchUUID, matchName, defaultStrategy, gapsOuter, gapsInner) ; champ `displays: [DisplayRule]` sur `Config`. Parser section `[[displays]]` (R-008, FR-018).
- [ ] T038 [US5] Au boot et après chaque `refresh()` du DisplayRegistry, appliquer les rules : pour chaque Display, chercher matchIndex/matchUUID/matchName puis copier les overrides dans `display.tilerStrategy/gapsOuter/gapsInner` (FR-019).
- [ ] T039 [P] [US5] Tests `Tests/RoadieCoreTests/ConfigDisplaysTests.swift` : parser TOML 2 rules, vérifier match par index/uuid/name.
- [ ] T040 [P] [US5] Test E2E : 2 mock displays, config rule pour display 2 = master_stack, vérifier `display.list` retourne stratégies différentes.

---

## Phase 8 : User Story 6 (P2) — Events display

**Goal** : émettre `display_changed` quand l'écran actif change.

**Independent Test** : subscriber connecté, déplacer focus d'un écran à l'autre, recevoir l'event.

- [ ] T041 [US6] Étendre `DisplayRegistry.setActive(id:)` : si l'id change, émettre `display_changed` event via le bus daemon (R-009, FR-022).
- [ ] T042 [US6] Câbler dans `Sources/roadied/main.swift` : à chaque `axDidChangeFocusedWindow`, recalculer le display actif (via centre de la frame) et appeler `displayRegistry.setActive(id:)`.
- [ ] T043 [US6] Émettre `display_configuration_changed` à chaque `refresh()` quand la liste a changé (FR-023, déjà T029).
- [ ] T044 [P] [US6] Tests `Tests/RoadieDesktopsTests/DisplayEventsTests.swift` : subscriber + change activeID → event reçu < 50 ms.

---

## Phase 9 : User Story 7 (P1) — Compatibilité ascendante mono-écran

**Cross-cutting** : pas de tâche dédiée, mais validation explicite.

- [ ] T045 [US7] Re-runner toute la suite SPEC-011 (`swift test --filter RoadieDesktops --filter RoadieStagePlugin`) après chaque sprint US1..US4. Tous tests doivent rester verts (FR-024, SC-004).
- [ ] T046 [US7] Tester `roadie display list` sur mono-écran : retourne 1 ligne identique (FR-011).
- [ ] T047 [US7] Tester `roadie window display 2` sur mono-écran : erreur `unknown_display` (FR-010).

---

## Phase 10 : Polish & Cross-Cutting

- [ ] T048 [P] Vérifier LOC `Sources/RoadieCore/Display*.swift` + nouveaux fichiers SPEC-012 < 800 LOC effectives (plafond plan.md)
- [ ] T049 [P] Vérifier que la suite tests SPEC-011+SPEC-012 passe complètement : ≥ 200 tests verts cible
- [ ] T050 [P] Re-run linter `bash Tests/StaticChecks/no-cgs.sh` étendu (SC-007)
- [ ] T051 [P] Mettre à jour `README.md` avec la section multi-display (≤ 200 mots, SC-010)
- [ ] T052 [P] Mettre à jour `CHANGELOG.md` : entry SPEC-012
- [ ] T053 Mesurer perf SC-002 manuellement : 10 mesures de `time roadie window display 2` < 200 ms p95
- [ ] T054 Backward-compat : tester sur un state.toml SPEC-011 existant (sans `display_uuid`), vérifier load propre + auto-fill du champ au prochain save (FR-021, R-012)
- [ ] T055 Test E2E manuel sur le setup réel utilisateur (MacBook + écran 4K externe)

---

## Dependencies & Story Order

```
Phase 1 (Setup) ──┐
                  ▼
Phase 2 (Foundational) ──┐
                          ▼
Phase 3 (US1 P1 tiling) ─────► Phase 4 (US2 P1 window display)
                                    │
                                    ▼
                              Phase 5 (US3 P1 recovery)
                                    │
                                    ▼
                              Phase 6 (US4 P1 CLI display)
                                    │
                                    ├────► Phase 7 (US5 P2 config)
                                    │
                                    └────► Phase 8 (US6 P2 events)
                                                │
                                                ▼
                                          Phase 9 (US7 P1 compat) ◄── cross-cutting
                                                │
                                                ▼
                                          Phase 10 (Polish)
```

- **MVP minimal** : Phases 1+2+3+4+5+6 (US1 + US2 + US3 + US4 = les 4 P1 multi-display).
- **Release V3 complète** : MVP + US5 + US6 (P2).
- **Validation** : US7 cross-cutting tout au long.

## Parallelization Examples

**Phase 1 (setup)** : T002 + T003 + T004 + T005 en parallèle (4 fichiers indépendants).

**Phase 2 (foundational)** : T006 + T007 + T010 + T012 en parallèle. T008 dépend de T006/T007.

**Phase 3 (US1)** : T013 → T014/T015/T016 en séquence (modif même fichier). T019 + T020 en parallèle après US1 implé.

**Phase 5 (US3)** : T026 → T027/T028/T029 en séquence. T030 + T031 en parallèle.

**Phase 10 (polish)** : T048 + T049 + T050 + T051 + T052 tous parallèles.

## Implementation Strategy

1. **Sprint 1 — MVP P1** : Phases 1 → 6. Tiling per-écran + window display + recovery + CLI list. Demo possible.
2. **Sprint 2 — Adoption** : Phase 7 (config) + Phase 8 (events) + Phase 9 (compat tests).
3. **Sprint 3 — Polish** : Phase 10. Audit final.

À chaque sprint, audit `/audit` mode fix sur le scope ajouté.
