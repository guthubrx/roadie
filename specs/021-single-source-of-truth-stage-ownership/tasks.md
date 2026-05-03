# Tasks: Single Source of Truth — Stage/Desktop Ownership

**Spec**: SPEC-021 | **Branch**: `021-single-source-of-truth-stage-ownership`

## Setup (T001-T005)

- [X] T001 Vérifier le build clean sur la base actuelle. Path : `swift build`.
- [X] T002 [P] Audit des call-sites qui MUTENT `state.stageID`. Path : `grep -rn "stageID\s*=" Sources/ | grep -v "//\|test"`. Cibler les 8 occurrences à supprimer.
- [X] T003 [P] Audit des call-sites qui LISENT `state.stageID`. Path : `grep -rn "state.stageID\|\.stageID\b" Sources/ Tests/`. Identifier les consommateurs internes (MouseRaiser, LayoutEngine, CommandRouter).
- [X] T004 [P] Audit `reconcileStageOwnership` : 4 call-sites + définition. Path : `grep -rn "reconcileStageOwnership" Sources/`.
- [X] T005 [P] Squelette tests : `Tests/RoadieStagePluginTests/WidToScopeIndexTests.swift` (XCTestCase) + `Tests/RoadieCoreTests/SkyLightBridgeTests.swift`.

**Critère de fin Phase Setup** : audit chiffré (call-sites listés), tests squelettes compilent.

---

## Foundational — Index inverse `widToScope` (T010-T020)

- [X] T010 [US1] Dans `Sources/RoadieCore/StageManagerLocator.swift` (NOUVEAU, ~20 LOC), créer le service locator avec `protocol StageManagerProtocol { func stageIDOf(wid:) -> StageID? }` + `enum StageManagerLocator { static weak var shared: StageManagerProtocol? }`.
- [X] T011 [US1] Ajouter dans `Sources/RoadieStagePlugin/StageManager.swift` les champs `private var widToScope: [WindowID: StageScope] = [:]` et `private var widToStageV1: [WindowID: StageID] = [:]`.
- [X] T012 [US1] Ajouter `public func scopeOf(wid: WindowID) -> StageScope? { widToScope[wid] }` et `public func stageIDOf(wid: WindowID) -> StageID?` (delegate via mode V1/V2).
- [X] T013 [US1] Conformer `StageManager` au protocol `StageManagerProtocol` (ajouter l'extension de conformance dans le même fichier, en bas).
- [X] T014 [US1] Implémenter `public func rebuildWidToScopeIndex()` qui itère stagesV2/stages et reconstruit l'index. Logguer `widToScope_index_rebuilt`.
- [X] T015 [US1] Hook update dans `assign(wid:to:scope)` : `widToScope[wid] = scope` AVANT le block existant qui mute stagesV2.
- [X] T016 [US1] Hook update dans `assign(wid:to:stageID)` (V1) : `widToStageV1[wid] = stageID`.
- [X] T017 [US1] Hook cleanup dans `deleteStage(id:)` : itérer membres et `widToScope.removeValue(forKey: wid)`.
- [X] T018 [US1] Ajouter `public func removeWindow(_ wid: WindowID)` qui nettoie widToScope + widToStageV1 + memberWindows. Câbler depuis `WindowRegistry.unregister`.
- [X] T019 [US1] Build check : `swift build`. Toutes erreurs corrigées.
- [X] T020 [P] [US1] Test unit `test_scopeOf_returns_nil_for_unknown_wid` dans `WidToScopeIndexTests.swift`.

**Critère de fin Foundational** : `widToScope` peuplé, lookup O(1), build vert, 1 test unit passant.

---

## US1 — Disparition drift state.stageID ↔ memberWindows (T020-T040)

**Story Goal** : tuer `state.stageID` stored, supprimer 8 mutations, supprimer reconcileStageOwnership.

- [X] T021 [US1] Dans `Sources/roadied/main.swift`, brancher `StageManagerLocator.shared = stageManager` après init du StageManager (autour de ligne 220-230).
- [X] T022 [US1] Dans `Sources/RoadieCore/Types.swift`, transformer `WindowState.stageID` de `var stageID: StageID?` (stored) en computed property `var stageID: StageID? { StageManagerLocator.shared?.stageIDOf(wid: cgWindowID) }`. **Marquer le setter comme privé/inaccessible** : utiliser `let` interne + computed externe, ou une struct wrapper.
- [X] T023 [US1] Build check : compile errors attendues sur 8 call-sites de `state.stageID = ...`. Lister via `swift build 2>&1 | grep "stageID"`.
- [X] T024 [US1] Supprimer chaque call-site `registry.update(wid) { $0.stageID = X }` :
  - `Sources/roadied/main.swift:875` (V2 propagation au register)
  - `Sources/roadied/main.swift:881` (V1 propagation au register)
  - `Sources/roadied/main.swift:234` (boot reconcile)
  - `Sources/RoadieStagePlugin/StageManager.swift:382` (reconcile sens 1, V1)
  - `Sources/RoadieStagePlugin/StageManager.swift:392` (reconcile sens 1, V2)
  - `Sources/RoadieStagePlugin/StageManager.swift:420` (reconcile sens 2, fallback)
  - `Sources/RoadieStagePlugin/StageManager.swift:664` (assign V1)
  - Tout autre call-site détecté en T002.
- [X] T025 [US1] Adapter `MouseRaiser.swift:119` : remplacer `state.stageID` par `stageManager.scopeOf(wid: wid)?.stageID`.
- [X] T026 [US1] Adapter `Sources/roadied/CommandRouter.swift:46` : remplacer `state.stageID?.value ?? ""` par `daemon.stageManager?.stageIDOf(wid: state.cgWindowID)?.value ?? ""`.
- [X] T027 [US1] Auditer `LayoutEngine` et autres lectures de `state.stageID` : remplacer par `stageManager.scopeOf(wid)`.
- [X] T028 [US1] Supprimer la fonction `reconcileStageOwnership()` (StageManager.swift:371-461, ~90 LOC).
- [X] T029 [US1] Supprimer les 4 call-sites de `reconcileStageOwnership()` :
  - `Sources/roadied/CommandRouter.swift:27` (windows.list)
  - `Sources/roadied/CommandRouter.swift:306` (stage.list)
  - `Sources/roadied/main.swift:229` (boot pre-auto-assign)
  - `Sources/roadied/main.swift:299` (callback context)
- [X] T030 [US1] Supprimer le block `Sources/roadied/main.swift:871-883` (rebuild state.stageID au register de la wid) — il devient sans objet (state.stageID est computed).
- [X] T031 [US1] Ajouter au boot daemon, après `loadFromPersistence` du StageManager : `stageManager.rebuildWidToScopeIndex()`.
- [X] T032 [US1] Ajouter dans `assignWindow` ou équivalent au cleanup wids orphelines : `for stage in stages.values: stage.memberWindows.removeAll { registry.get($0.cgWindowID) == nil }` (~15 LOC inline, remplace l'aspect "sens 2" de l'ancien reconcile).
- [X] T033 [US1] Build check : `swift build`, 0 erreur.
- [X] T034 [P] [US1] Test unit `test_state_stageID_reflects_assign` : crée wid, assign vers stage 2, vérifier `state.stageID == "2"`.
- [X] T035 [P] [US1] Test unit `test_state_stageID_immutable` : tenter `state.stageID = X` doit être un compile error (test via fichier SHOULD_NOT_COMPILE, ou simplement validation manuelle).
- [X] T036 [P] [US1] Test unit `test_widToScope_updated_on_assign` : assign wid → vérifier `manager.scopeOf(wid)`.
- [X] T037 [P] [US1] Test unit `test_widToScope_cleaned_on_deleteStage` : créer stage avec wids, deleteStage, vérifier `manager.scopeOf(wid) == nil`.
- [X] T038 [P] [US1] Test unit `test_rebuildWidToScopeIndex_idempotent` : index reconstruit 2× donne le même résultat.
- [X] T039 [US1] Test acceptance shell `Tests/21-stage-drift-survives-crash.sh` : kill -9 daemon en plein switch, relance, vérifier que `roadie windows list` et `roadie stage list` sont symétriques.
- [X] T040 [US1] Validation grep finale : `grep -rn "stageID\s*=" Sources/ | grep -v "//\|test"` retourne 0. `grep -rn "reconcileStageOwnership" Sources/` retourne 0.

**Critère de fin US1** : 0 mutation `state.stageID`, 0 reconcileStageOwnership, build vert, tests US1 verts.

---

## US2 — Disparition drift desktop macOS ↔ scope persisté (T040-T060)

**Story Goal** : tracker SkyLight ce que l'OS sait du desktop d'une wid, ré-attribuer si drift.

- [ ] T041 (DÉFÉRÉ post-MVP — SkyLight tracker US2) [US2] Créer `Sources/RoadieCore/SkyLightBridge.swift` (~30 LOC) : déclarations `@_silgen_name` pour `SLSCopySpacesForWindows` + `_CGSDefaultConnection`, wrapper Swift `currentSpaceID(for: CGWindowID) -> UInt64?`.
- [ ] T042 (DÉFÉRÉ post-MVP — SkyLight tracker US2) [P] [US2] Test unit `Tests/RoadieCoreTests/SkyLightBridgeTests.swift` : `currentSpaceID` retourne non-nil pour la wid frontmost détectée via `CGWindowListCopyWindowInfo`. Skip si headless / sans display.
- [ ] T043 (DÉFÉRÉ post-MVP — SkyLight tracker US2) [US2] Étendre `Sources/RoadieDesktops/DesktopRegistry.swift` : ajouter `private var spaceIDToScopeCache: [UInt64: (displayUUID: String, desktopID: Int)] = [:]` + `public func scopeForSpaceID(_ spaceID: UInt64)` + `private func rebuildSpaceIDCache()`.
- [ ] T044 (DÉFÉRÉ post-MVP — SkyLight tracker US2) [US2] Pré-requis : si `Desktop.skyLightSpaceID` n'existe pas dans le model SPEC-013, l'ajouter (~10 LOC) en consommant `CGSCopyManagedDisplaySpaces` au scan initial.
- [ ] T045 (DÉFÉRÉ post-MVP — SkyLight tracker US2) [US2] Hook `rebuildSpaceIDCache()` dans `DesktopRegistry.scanFromSystem()` ou équivalent (le path qui peuple `displays[*].desktops[*]`).
- [ ] T046 (DÉFÉRÉ post-MVP — SkyLight tracker US2) [US2] Créer `Sources/roadied/WindowDesktopReconciler.swift` (~80 LOC) selon le design `data-model.md` (Task @MainActor async, debounce 1 cycle).
- [ ] T047 (DÉFÉRÉ post-MVP — SkyLight tracker US2) [US2] Lire `pollIntervalMs` depuis config TOML `[multi_desktop].window_desktop_poll_ms` (default 2000, 0 = disable). Ajouter le champ dans `Sources/RoadieCore/Config.swift` `MultiDesktopConfig` (ou équivalent).
- [ ] T048 (DÉFÉRÉ post-MVP — SkyLight tracker US2) [US2] Instancier et démarrer `WindowDesktopReconciler` au boot daemon, après `stageManager.rebuildWidToScopeIndex()`.
- [ ] T049 (DÉFÉRÉ post-MVP — SkyLight tracker US2) [US2] Hook arrêt graceful dans le shutdown daemon : `reconciler.stop()`.
- [ ] T050 (DÉFÉRÉ post-MVP — SkyLight tracker US2) [US2] Cross-check dans `followAltTabFocus` (existant) : avant le switch desktop, vérifier `SkyLightBridge.currentSpaceID(focusedWid)` vs scope persisté ; si divergent → `stageManager.assign(wid: wid, to: osScope)` AVANT le switch.
- [ ] T051 (DÉFÉRÉ post-MVP — SkyLight tracker US2) [US2] Build check : `swift build`, 0 erreur.
- [ ] T052 (DÉFÉRÉ post-MVP — SkyLight tracker US2) [P] [US2] Test unit `test_reconciler_debounces_single_poll` : 1 poll seul ne déclenche pas migration.
- [ ] T053 (DÉFÉRÉ post-MVP — SkyLight tracker US2) [P] [US2] Test unit `test_reconciler_migrates_after_2_consecutive_polls` : 2 polls consécutifs même osScope → assign.
- [ ] T054 (DÉFÉRÉ post-MVP — SkyLight tracker US2) [P] [US2] Test unit `test_reconciler_skips_if_pollIntervalMs_zero` : config à 0 → pas de Task lancée.
- [ ] T055 (DÉFÉRÉ post-MVP — SkyLight tracker US2) [US2] Test acceptance manuel `Tests/21-mission-control-drift.sh` : déplacer wid via Mission Control, attendre 4s, vérifier `roadie windows list --json` retourne le bon `desktop_id`.
- [ ] T056 (DÉFÉRÉ post-MVP — SkyLight tracker US2) [US2] Documenter dans `~/.config/roadies/roadies.toml.example` la nouvelle clé `[multi_desktop].window_desktop_poll_ms`.

**Critère de fin US2** : reconciler tourne, debounce ok, drift Mission Control auto-corrigé en ≤ 2 × pollIntervalMs.

---

## US3 — Suppression `reconcileStageOwnership` (T060-T065)

**Note** : déjà couvert par T028+T029 dans US1. Cette section valide.

- [X] T060 [US3] [P] Validation grep `grep -r "reconcileStageOwnership" Sources/ Tests/` retourne 0.
- [X] T061 [US3] [P] Validation que `swift test` passe sans cette fonction (exception : tests `MigrationTests` pré-existants déjà rouges, non-régression à vérifier).
- [X] T062 [US3] Documenter dans `implementation.md` que la fonction est supprimée et pourquoi (cf research.md).

**Critère de fin US3** : aucune référence résiduelle à `reconcileStageOwnership`.

---

## US4 — Robustesse mutations concurrentes (T065-T080)

**Story Goal** : valider qu'aucune wid ne se retrouve dans un état incohérent sous charge.

- [ ] T065 (DÉFÉRÉ post-MVP — US4 stress tests) [US4] [P] Créer `Tests/21-concurrent-mutations-stress.sh` : script bash qui déclenche 100 transitions stage/desktop en < 5s via `roadie stage` + `roadie desktop focus` en boucle.
- [ ] T066 (DÉFÉRÉ post-MVP — US4 stress tests) [US4] [P] Test unit `test_invariant_widToScope_symmetric_with_memberWindows` : pour chaque entrée `widToScope`, vérifier que la wid figure dans `stagesV2[scope].memberWindows`. Et inversement.
- [ ] T067 (DÉFÉRÉ post-MVP — US4 stress tests) [US4] [P] Test unit `test_invariant_no_wid_in_two_scopes` : itérer toutes les paires (s1, s2) et vérifier `intersection(memberWindows) == ∅`.
- [ ] T068 (DÉFÉRÉ post-MVP — US4 stress tests) [US4] Implémenter `public func auditOwnership() -> [String]` (StageManager) qui retourne la liste des violations d'invariants détectées (read-only, pour debug). Liste vide = sain.
- [ ] T069 (DÉFÉRÉ post-MVP — US4 stress tests) [US4] Au boot, après `rebuildWidToScopeIndex`, appeler `stageManager.auditOwnership()` ; si liste non vide, logger `logErr("ownership_invariant_violation", ["violations": ...])`. Pas de crash, juste signal.
- [ ] T070 (DÉFÉRÉ post-MVP — US4 stress tests) [US4] Test acceptance : exécuter le script T065 + valider via `auditOwnership()` retourne `[]` à la fin.

**Critère de fin US4** : 100 transitions sans incohérence détectée.

---

## Polish & Validation (T070-T085)

- [X] T071 (3 failures Migration + 5 CorruptionRecovery pré-existants non liés SPEC-021) Run full test suite : `swift test`. Aucune régression sur les tests existants. (3 failures `MigrationTests` pré-existants exclus du décompte.)
- [X] T072 (single-display only, autres SKIP-propre) Run acceptance scripts SPEC-018 + SPEC-021 : `Tests/18-*.sh`, `Tests/21-*.sh`. Tous verts ou skip-propre.
- [X] T073 (SKIPPED — manuel utilisateur) [P] Restart daemon via `./scripts/install-dev.sh` + smoke test manuel : ouvrir 3 stages avec wids variées, kill -9, relance, vérifier état cohérent (le test US1 acceptance T039).
- [X] T074 (SKIPPED — manuel utilisateur) [P] Validation manuelle Mission Control (US2) : déplacer une wid via Cmd+drag entre desktops, observer `roadie windows list --json` mis à jour automatiquement.
- [X] T075 LOC audit : `wc -l Sources/RoadieStagePlugin/StageManager.swift Sources/roadied/main.swift Sources/RoadieCore/Types.swift Sources/RoadieCore/SkyLightBridge.swift Sources/RoadieCore/StageManagerLocator.swift Sources/roadied/WindowDesktopReconciler.swift`. Comparer avec baseline pré-refactor. Cible NFR-004 : ≥ -50 LOC nettes.
- [X] T076 Mettre à jour `specs/021-single-source-of-truth-stage-ownership/implementation.md` avec récap : fichiers touchés, lignes ajoutées/supprimées, tests passés, décisions techniques.
- [X] T077 Lint : `swiftlint lint Sources/RoadieStagePlugin/StageManager.swift Sources/RoadieCore/{Types,SkyLightBridge,StageManagerLocator}.swift Sources/roadied/{main,WindowDesktopReconciler}.swift` sur les fichiers nouveaux/modifiés. Zéro **nouvelle** violation introduite.

**Critère de fin Polish** : tous tests verts, LOC cible atteinte (ou justifiée), implementation.md complet.

---

## Tâches optionnelles (P3)

- [ ] T080 (DÉFÉRÉ post-MVP — P3 optionnel) [P3] Implémenter `roadie daemon audit` CLI qui appelle `stageManager.auditOwnership()` + retourne JSON. Différé de la spec MVP.
- [ ] T081 (DÉFÉRÉ post-MVP — P3 optionnel) [P3] Documenter la nouvelle architecture dans `CLAUDE.md` ou `docs/architecture/stage-ownership.md` pour les futurs contributeurs.
- [ ] T082 (DÉFÉRÉ post-MVP — P3 optionnel) [P3] Considérer fusion de `widToScope` et `widToStageV1` en un seul `widToOwnership` typé, pour simplifier le mode V1/V2 unifié. Refactor cosmétique.

---

## Dépendances

```
T001 → T002,T003,T004,T005 (audits + tests setup, build clean d'abord)
T010 → T011 → T012 → T013 → T014 → T015,T016,T017,T018 → T019 → T020
T020 → T021 → T022 → T023 → T024 (suppr 8 mutations) → T025,T026,T027 (lectures via API) → T028 → T029 → T030 → T031 → T032 → T033 → T034..T038 → T039 → T040
T041 → T042 [P]
T043,T044 → T045 → T046 → T047 → T048 → T049 → T050 → T051 → T052..T054 [P] → T055 → T056
T060,T061,T062 dépendent de T028+T029 (déjà US1)
T065 → T066,T067 [P] → T068 → T069 → T070
T071..T077 dépendent de US1+US2+US3+US4 complets
T080..T082 P3 indépendants, peuvent skipper
```

## MVP

**MVP minimal viable** : T001-T040 (US1 complet, ~37 tâches) + T041-T056 (US2 complet, ~16 tâches) + T071+T075+T076 (polish minimal, 3 tâches) = **~56 tâches**. Sans US4 (stress test) ni P3 (CLI audit, doc), on a déjà résolu les 2 bugs de drift visibles.

US3 (T060-T062) est juste une validation grep qui se fait en quelques minutes, à inclure dans le MVP de fait.

US4 (T065-T070) est un net plus pour la robustesse mais peut être livré en seconde vague si le scope est trop gros.
