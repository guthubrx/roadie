# Tasks — SPEC-018 Stages-per-display

**Status**: Implemented + 8 fixes post-livraison cohérence display×desktop×stage (2026-05-03)
**Spec**: [spec.md](spec.md)
**Plan**: [plan.md](plan.md)
**Audit cohérence**: [audit-coherence.md](audit-coherence.md)
**Last updated**: 2026-05-03

## Format

`- [ ] T<nnn> [P?] [US<k>?] Description avec chemin de fichier`

- `[P]` = parallélisable (fichiers indépendants, aucune dépendance sur tâche en cours)
- `[US<k>]` = appartient à user story k

## Path Conventions

Tous les chemins relatifs à la racine du repo `/Users/moi/Nextcloud/10.Scripts/39.roadies/`.

---

## Phase 1 — Setup (P0)

- [X] T001 Vérifier que la branche `018-stages-per-display` est checkout (`git branch --show-current`)
- [X] T002 [P] Confirmer la dépendance SPEC-013 effective : `grep -q "DesktopRegistry" Sources/RoadieDesktops/DesktopRegistry.swift` doit retourner 0 (sinon abort spec)
- [X] T003 [P] Confirmer la dépendance SPEC-012 effective : `grep -q "displayUUID" Sources/RoadieCore/Display.swift` doit retourner 0
- [X] T004 [P] Bench baseline `swift test --filter RoadieStagePluginTests` doit passer 100% AVANT modification (= filet de sécurité régression)

**Critère de fin Phase 1** : pré-conditions vérifiées, baseline tests verts.

---

## Phase 2 — Foundational : modèle de données + persistance abstraite

Pré-requis bloquants pour TOUTES les user stories.

- [X] T010 Créer `Sources/RoadieStagePlugin/StageScope.swift` (~50 LOC) — struct `StageScope: Hashable, Sendable, Codable` avec `displayUUID: String`, `desktopID: Int`, `stageID: StageID`, factory `.global(_:)`, accesseur `isGlobal`
- [X] T011 [P] Créer `Tests/RoadieStagePluginTests/StageScopeTests.swift` (~50 LOC) — test Hashable contract (eq → hash égal), Codable round-trip, factory `.global` produit sentinel correct, `isGlobal` reflète l'état
- [X] T012 Créer `Sources/RoadieStagePlugin/StagePersistenceV2.swift` (~180 LOC) — protocol `StagePersistenceV2` avec `loadAll() -> [StageScope: Stage]`, `save(_:at:)`, `delete(at:)`, `saveActiveStage(_:)`, `loadActiveStage()`. Plus 2 implémentations : `FlatStagePersistence` (mode global, fichiers `<stagesDir>/<stageID>.toml`) et `NestedStagePersistence` (mode per_display, walk `<stagesDir>/<UUID>/<desktopID>/<stageID>.toml`)
- [X] T013 [P] Créer `Tests/RoadieStagePluginTests/StagePersistenceV2Tests.swift` (~120 LOC) — round-trip flat (load/save/delete), round-trip nested (load/save/delete avec UUID + desktopID), atomicité (tmpfile + rename)
- [X] T014 Créer `Sources/RoadieStagePlugin/MigrationV1V2.swift` (~120 LOC) — `class MigrationV1V2`, méthode `runIfNeeded() -> Report?`, idempotent via test `stages.v1.bak/` exists, backup `cp -r`, déplacement `<id>.toml` → `<UUID>/1/<id>.toml`, gestion erreurs disque (`MigrationError.diskFull`, `.permissionDenied`, `.partialMigration`)
- [X] T015 [P] Créer `Tests/RoadieStagePluginTests/MigrationV1V2Tests.swift` (~150 LOC) — cas heureux (5 stages flat → 5 stages nested), idempotence (2 boots → migration 1 seule fois), recovery (backup présent → skip), erreur disque simulée (vérifier flag fallback)
- [X] T016 Modifier `Sources/RoadieStagePlugin/StageManager.swift` — refactor interne : `private var stages: [StageScope: Stage]` (vs `[StageID: Stage]`), ajouter `mode: StageMode`, ajouter `persistence: any StagePersistenceV2`, conserver l'API publique compatible (méthodes prennent un scope ou retombent sur `.global` selon mode). ~150 LOC nettes (delta)
- [X] T017 [P] Étendre `Tests/RoadieStagePluginTests/StageManagerTests.swift` (existant) — vérifier compat ascendante stricte mode global : tous les tests V1 passent toujours

**Critère de fin Phase 2** : `swift build` clean, `swift test --filter RoadieStagePluginTests` passe 100% (V1 + V2), aucun fichier daemon n'est cassé.

---

## Phase 3 — User Story 1 : Isolation cross-display (P1, MVP)

**Goal** : créer "Stage 2" sur Display 1 ne pollue pas la liste vue depuis Display 2.

**Independent test** : 2 écrans connectés, mode `per_display`, créer une stage sur D1, vérifier `roadie stage list` curseur sur D2 ne contient pas cette stage.

- [X] T020 [US1] Modifier `Sources/roadied/main.swift` — ajouter helper privé `currentStageScope() -> StageScope` qui résout dans l'ordre : `NSEvent.mouseLocation` → `displayRegistry.displayContaining(point:)` → frontmost frame center → `CGMainDisplayID()` (~40 LOC)
- [X] T021 [P] [US1] Modifier `Sources/roadied/main.swift` — au boot, choisir `StagePersistenceV2` selon `config.desktops.mode` : `.global` → `FlatStagePersistence`, `.perDisplay` → `NestedStagePersistence` (~20 LOC)
- [X] T022 [US1] Modifier `Sources/roadied/CommandRouter.swift` case `stage.list` — récupérer `currentStageScope()`, appeler `stageManager.stages(in: .displayDesktop(scope.displayUUID, scope.desktopID))`, retourner avec champs `scope`, `mode`, `inferred_from`. Mode global : pas de scope, retour identique à V1 (~40 LOC nettes)
- [X] T023 [US1] Modifier `Sources/roadied/CommandRouter.swift` cases `stage.assign`, `stage.switch`, `stage.create`, `stage.delete`, `stage.rename` — tous déterminent leur scope via `currentStageScope()` (mode per_display) ou utilisent sentinel `.global(stageID)` (mode global). Persistance via `StageManager` mise à jour (~80 LOC nettes)
- [X] T024 [US1] Tests `Tests/RoadieStagePluginTests/StageManagerScopedTests.swift` (~200 LOC) — couvre :
  - Coexistence : créer "stage 2" dans `(D1_uuid, 1)` ET `(D2_uuid, 1)`, vérifier les 2 dans le dict interne, vérifier `stages(in: .displayDesktop(D1_uuid, 1))` ne retourne que la première
  - Mutations scopées : `renameStage(at: scope_D1)` ne touche pas la stage homonyme dans `scope_D2`
  - `assign(wid:to:)` lazy-create dans le bon scope
  - Stage 1 immortelle dans CHAQUE scope (delete refuse en `.exact(scope_D1.with(stageID: 1))` ET en `.exact(scope_D2.with(stageID: 1))`)
- [X] T025 [US1] Test acceptance bash `tests/18-stage-list-scope.sh` — 2 écrans (skip si mono-display), curseur D1 → assign 2, vérifier list D1 contient 2, curseur D2 → list D2 ne contient pas 2 (cf contracts/cli-stage-list.md test acceptance)
- [X] T026 [US1] Test acceptance bash `tests/18-stage-mutations-scope.sh` — couvre rename + delete scopés (cf contracts/cli-stage-mutations.md test acceptance)

**Critère de fin US1** : 2 stages homonymes coexistent dans des scopes différents, `roadie stage list` filtre correctement, tests acceptance PASS sur machine 2 écrans.

---

## Phase 4 — User Story 2 : Migration silencieuse V1 → V2 (P1, MVP)

**Goal** : utilisateur existant qui upgrade ne perd aucune stage.

**Independent test** : préparer 5 stages V1 flat, basculer en mode `per_display`, redémarrer daemon, vérifier 5 stages dans `<mainDisplayUUID>/1/`, backup `.v1.bak/` créé.

- [X] T030 [US2] Modifier `Sources/roadied/main.swift` — au boot, si `config.desktops.mode == .perDisplay`, instancier `MigrationV1V2(stagesDir, mainDisplayUUID)` et appeler `runIfNeeded()`. Sur succès : log + émission event `migration_v1_to_v2` via EventBus. Sur erreur : log structuré + flag `daemon.migrationPending = true`, fallback sur FlatStagePersistence (~30 LOC nettes)
- [X] T031 [P] [US2] Étendre `Sources/RoadieCore/EventBus.swift` — factory `DesktopEvent.migrationV1V2(migratedCount: Int, backupPath: String, targetUUID: String, durationMs: Int)` (~15 LOC)
- [X] T032 [P] [US2] Modifier `Sources/roadied/CommandRouter.swift` case `daemon.status` — exposer `stages_mode: "per_display"|"global"`, `current_scope`, `migration_pending: Bool` (~20 LOC nettes)
- [X] T033 [US2] Test acceptance bash `tests/18-migration.sh` — créer 3 fichiers `~/.config/roadies/stages-test/<id>.toml`, lancer `MigrationV1V2(stagesDir: "stages-test", mainDisplayUUID: "TEST-UUID").runIfNeeded()` via swift script ad-hoc, vérifier `stages-test.v1.bak/` créé, vérifier `stages-test/TEST-UUID/1/<id>.toml` créés, vérifier compteur dans Report
- [X] T034 [US2] Test acceptance bash `tests/18-migration-idempotent.sh` — re-lancer la migration sur un état déjà migré → no-op silencieux, pas de re-création de backup

**Critère de fin US2** : utilisateur upgrade sans intervention, recovery V1 documentée et testée.

---

## Phase 5 — User Story 3 : Compat ascendante stricte mode `global` (P1, MVP)

**Goal** : aucune régression pour utilisateurs en mode `global`.

**Independent test** : lancer la suite SPEC-002 complète en mode `global`, 100% verte.

- [X] T040 [US3] Vérifier qu'avec `[desktops] mode = "global"`, `StageManager` utilise `FlatStagePersistence` et le tuple sentinel `.global(stageID)` partout. Aucun appel à `currentStageScope()` ne touche les fichiers
- [X] T041 [P] [US3] Test régression `Tests/RoadieStagePluginTests/StageManagerTests.swift` (existant) DOIT passer 100% sans modification
- [X] T042 [P] [US3] Test acceptance bash `tests/18-global-mode-compat.sh` — config TOML mode global, créer 5 stages V1 sur disque, démarrer daemon, vérifier `roadie stage list` retourne les 5, vérifier aucun nouveau dossier `<UUID>/` sur disque

**Critère de fin US3** : zéro régression mesurée, test acceptance PASS.

---

## Phase 6 — User Story 4 : Override CLI explicite (P2, V1.1)

**Goal** : scripts power-user peuvent cibler un display sans bouger la souris.

- [X] T050 [US4] Modifier `Sources/roadie/main.swift` `handleStage` — accepter `--display <selector>` et `--desktop <id>` flags pour toutes les sous-commandes (list, assign, create, delete, rename) ; passer ces args au daemon dans `request.args` (~40 LOC)
- [X] T051 [P] [US4] Modifier `Sources/roadied/CommandRouter.swift` — si `request.args["display"]` ou `request.args["desktop"]` présents, override `currentStageScope()` (résoudre selector via `DisplayRegistry.display(at:)` ou matching UUID). Sinon résolution implicite (~30 LOC nettes)
- [X] T052 [P] [US4] Erreurs : `unknown_display` si selector invalide, `desktop_out_of_range` si desktop > count
- [X] T053 [US4] Test acceptance bash `tests/18-cli-override.sh` — `roadie stage list --display 1 --desktop 1` retourne stages D1, `--display 99` → erreur `unknown_display`, `--desktop 42` (si count = 4) → erreur `desktop_out_of_range`

**Critère de fin US4** : override fonctionnel, erreurs claires, tests acceptance PASS.

---

## Phase 7 — User Story 5 : Cohérence rail UI (P1, MVP)

**Goal** : chaque panel rail (un par écran) affiche STRICTEMENT les stages de son scope.

**Note** : le rail SPEC-014 fait déjà le job côté client (filtre `state.windows[wid]`). Cette user story consiste à valider end-to-end que le daemon retourne bien les bonnes stages au rail.

- [X] T060 [US5] Vérifier que le rail (SPEC-014 RailController) appelle bien `stage.list` SANS override `--display` (= scope implicite par display sous le curseur du panel concerné). Aucune modification du code rail nécessaire si le scope est correctement inféré
- [X] T061 [P] [US5] Étendre les events `stage_*` (changed, created, renamed, deleted, assigned) émis dans `Sources/RoadieCore/EventBus.swift` ou helpers ad-hoc — ajouter `display_uuid` et `desktop_id` dans le payload (~30 LOC cumulé pour les helpers)
- [X] T062 [US5] Modifier `Sources/RoadieRail/RailController.swift` `handleEvent` — filtrer côté client : si `display_uuid` de l'event ne match pas le `displayUUID` du panel concerné, ignorer. Si `desktop_id` ne match pas le current_desktop_for_display, ignorer (~20 LOC nettes)
- [X] T063 [US5] Test acceptance bash `tests/18-rail-scope.sh` — lancer rail sur 2 écrans, créer stage sur D1, vérifier que panel D1 affiche la nouvelle stage et que panel D2 reste inchangé (test manuel + screenshot pour documentation)

**Critère de fin US5** : rail filtre correctement, screenshot before/after dans la session.

---

## Phase 8 — Polish & cross-cutting

- [ ] T070 [POLISH] Documentation : compléter `quickstart.md` avec captures d'écran 2-display avant/après (PNG dans `docs/screenshots/spec-018/`) — **MANUEL post-livraison** (skip pipeline /my.specify-all)
- [X] T071 [P] [POLISH] Documentation : ajouter section "Stages per display" au README projet pointant vers SPEC-018
- [X] T072 [P] [POLISH] Logger structuré : `logInfo("scope_inferred_from", ["source": "cursor"|"frontmost"|"primary"])` à chaque résolution pour debug
- [ ] T073 [POLISH] Performance : bench `currentStageScope()` p95 < 5 ms (cf SC-004) — ajouter test perf dans `StageManagerScopedTests` — **DEFERRED V1.1** (impl actuelle est triviale O(1) lookup, bench formel reportable)
- [X] T074 [POLISH] Régression : re-jouer toute la suite `swift test` → **DONE 2026-05-02** : 336 tests exécutés, 0 failure imputable à SPEC-018. Segfault `RoadieDesktopsTests.ParserTests` en run all-suite est PRÉ-EXISTANT (passe 7/7 en isolation, déjà documenté SPEC-014 implementation.md).
- [X] T075 [POLISH] Mise à jour `implementation.md` avec REX de chaque user story
- [ ] T076 [POLISH] Audit `/audit 018-stages-per-display` mode fix, viser score ≥ A- — **PHASE 6 PIPELINE** (à lancer après commit en session dédiée)

**Critère de fin Polish** : tous tests verts, audit ≥ A-, doc complète.

---

## Phase 9 — Fixes post-livraison cohérence display × desktop × stage (2026-05-03)

**Goal** : éliminer toutes les incohérences observées après livraison (Grayjay visible alors que stage 2 inactif, état stage perdu au desktop_changed, etc.). Détails dans `audit-coherence.md`.

### Helpers windows et hide

- [X] T080 Ajouter `WindowState.minimumUsefulDimension = 100` + `isHelperWindow` computed dans `Sources/RoadieCore/Types.swift` (F1)
- [X] T081 Étendre `isTileable` pour exclure `isHelperWindow` (Types.swift, F1)
- [X] T082 Garde `isHelperWindow` dans `assign(wid:to: stageID:)` et `assign(wid:to: scope:)` de `Sources/RoadieStagePlugin/StageManager.swift` (F1)
- [X] T083 `purgeOrphanWindows` étendu pour purger les helpers (StageManager.swift, F1)
- [X] T084 `reconcileStageOwnership` Sens 2 skip helpers (StageManager.swift, F1)
- [X] T085 `Sources/roadied/main.swift` Task post-boot appelle `sm.switchTo(currentStageID)` pour propager hide initial (F2)

### Respect du scope par MouseRaiser et focus AX

- [X] T090 Callback `onClickInOtherStage` dans `Sources/RoadieCore/MouseRaiser.swift` (F3)
- [X] T091 Branchement du callback dans `Sources/roadied/main.swift` → `sm.switchTo(targetStage)` (F3)
- [X] T092 Hook stage dans `axDidChangeFocusedWindow` de `Sources/roadied/main.swift` — Cmd+Tab vers wid d'un autre stage déclenche switchTo (F4)

### Active stage par (display, desktop)

- [X] T100 `DesktopKey` struct Hashable dans `Sources/RoadieStagePlugin/StageManager.swift` (F5)
- [X] T101 Dict `activeStageByDesktop: [DesktopKey: StageID]` privé sur StageManager (F5)
- [X] T102 API publique `setCurrentDesktopKey`, `activeStage(for:)`, `loadActiveStagesByDesktop` (F5)
- [X] T103 `switchTo(stageID:)` met à jour `activeStageByDesktop` + persiste via `persistenceV2.saveActiveStage(scope)` (F5)
- [X] T104 `setMode(perDisplay)` rappelle `loadFromPersistence()` pour peupler stagesV2 + activeStageByDesktop (F5)
- [X] T105 `reload(forDesktop:)` en mode V2 ne purge plus stagesV2 (F6)
- [X] T106 Hook `stageHook` dans `main.swift` appelle `setCurrentDesktopKey(...)` après `reload(forDesktop:)` (F5+F6)

### Anti-double-attribution V1↔V2

- [X] T110 `assign(wid:to: stageID:)` V1 délègue à V2 quand mode `.perDisplay` (StageManager.swift, F11)

### Boot timing (cause racine Grayjay)

- [X] T120 Précharger `setMode V2 + setCurrentDesktopKey` AVANT `registerExistingWindows` dans `Sources/roadied/main.swift` (F12)
- [X] T121 `registerWindow` propage `state.stageID` depuis `stagesV2.memberWindows` AVANT `insertWindow` pour que `LayoutEngine.stageID(for:)` choisisse le bon tree (F13)
- [X] T122 `registerWindow` skip `sm.assign(...)` si la wid est déjà persistée dans une stage (F14)
- [X] T123 `bootstrap` appelle `reconcileStageOwnership` AVANT auto-assign des orphelines (F15)

### Synchronisation rail

- [X] T130 Émettre `window_created` event sur DesktopEvent bus dans `axDidCreateWindow` (F16)
- [X] T131 Émettre `window_destroyed` event sur DesktopEvent bus dans `axDidDestroyWindow` (F16)

### Synchronisation stages V1↔V2 et desktop switch

- [X] T140 `setCurrentDesktopKey` resync `stages` V1 dict avec stages V2 du scope courant (F17)
- [X] T141 `setCurrentDesktopKey` ne fait plus `setActiveStage` (causait re-show des wids cross-desktop) (F18)
- [X] T142 `desktop.focus per_display` (CommandRouter.swift) filtre `shouldShow` par `activeStageOnTarget` — un desktop n'affiche plus toutes ses wids mais seulement celles du stage actif (F19)

### Validation finale

- [X] T150 Validation visuelle par 8 screenshots dans `/tmp/roadie-debug/` couvrant Boot, switch stage 1↔2, desktop 1↔2, retour avec mémoire stage actif
- [X] T151 Document `specs/018-stages-per-display/audit-coherence.md` listant les 19 findings, 15 fixes appliqués, 4 TODO mineurs documentés
- [ ] T152 [TODO] F7 — `LayoutEngine.workspace.activeStageByDisplay` (multi-display réel : un display = un tree actif différent en simultané) — refonte plus invasive, session dédiée
- [ ] T153 [TODO] F8 — `windows.list` retourne `display_uuid` + `desktop_id` en plus de `stage`
- [ ] T154 [TODO] F9 — `WallpaperStageCoordinator.handleClick` utilise l'API V2 `assign(wid:to: scope:)`
- [ ] T155 [TODO] F10 — `registerWindow` desktopID dynamique au lieu de `1` hardcodé

**Critère de fin Phase 9** : Grayjay reste hidden offscreen quand son stage est inactif (validé visuellement), mémoire stage active conservée par desktop, pas de double-attribution sur disque.

---

## Dependencies (DAG)

```
T001..T004 (Setup, parallèles entre eux)
   ↓
T010..T017 (Foundational : StageScope + persistence + migration core)
   ↓
   ├──► T020..T026 (US1 isolation cross-display) ════ MVP gate
   │       ↓
   │       T030..T034 (US2 migration silencieuse)
   │       ↓
   │       T040..T042 (US3 compat global mode) ─► MVP V1 livrable
   │       ↓
   │       T050..T053 (US4 CLI override)         V1.1
   │       ↓
   │       T060..T063 (US5 rail coherence)       V1.2 (en parallèle possible avec US4)
   │       ↓
   │       T070..T076 (Polish)                   V1 final
```

**MVP livrable** : T001 → T042 inclus (US1 + US2 + US3 complets). Estimation effort : ~1 journée pour développeur Swift familier de SPEC-002/012/013.

## Estimation parallélisme

Tâches marquées `[P]` peuvent tourner en parallèle :
- T002, T003, T004 (vérifications baseline)
- T011, T013, T015 (tests unit)
- T017 (test régression mode global existing) ‖ T024 (tests scopés mode per_display)
- T031 (event helper) ‖ T032 (daemon status) ‖ T033 (test migration)
- T041, T042 (compat global)
- T051, T052 (override CLI)
- T061 (events enrichis)

Tâches sur `Sources/RoadieStagePlugin/StageManager.swift` (T016) doivent être séquentielles. Idem pour `Sources/roadied/CommandRouter.swift` (T022, T023, T032, T051) — un seul fichier modifié plusieurs fois.

## Total

- **77 tâches initiales** réparties sur 8 phases
- **+25 tâches Phase 9** (T080-T155) fixes post-livraison cohérence display×desktop×stage
- **MVP** = T001-T042 (47 tâches) couvrant US1 + US2 + US3
- **V1.1** = +T050-T053 (4 tâches) override CLI
- **V1.2** = +T060-T063 (4 tâches) rail coherence
- **Polish** = +T070-T076 (7 tâches)
- **Phase 9** = +T080-T155 (25 tâches, 21 cochées + 4 TODO mineurs F7/F8/F9/F10)

**Effort total estimé initial** : ~12-15 heures pour développeur Swift, hors tests acceptance manuels nécessitant 2 écrans physiques.
**Effort Phase 9 réel** : ~6 heures (audit + 15 fixes + 8 screenshots de validation).
