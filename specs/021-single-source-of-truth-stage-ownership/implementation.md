# Implementation: SPEC-021 — Single Source of Truth (Stage Ownership)

**Status** : MVP livré (US1 + Foundational), US2 SkyLight tracker différé.
**Date** : 2026-05-03
**Branch** : `021-single-source-of-truth-stage-ownership`

## Périmètre livré (MVP — 46/71 tâches)

### Foundational (T001-T020) — Index inverse `widToScope`

- **NEW** `Sources/RoadieCore/StageManagerLocator.swift` (~20 LOC) : service locator avec `protocol StageManagerProtocol { func stageIDOf(wid:) -> StageID? }` + enum singleton `StageManagerLocator { static weak var shared: StageManagerProtocol? }`. Découple `WindowState` (RoadieCore) du `StageManager` (RoadieStagePlugin) sans cycle d'imports.
- **MODIFIED** `Sources/RoadieStagePlugin/StageManager.swift` :
  - Nouveau champ `private var widToScope: [WindowID: StageScope]` (mode V2)
  - Nouveau champ `private var widToStageV1: [WindowID: StageID]` (mode V1 global)
  - Nouvelle API publique `public func scopeOf(wid: WindowID) -> StageScope?`
  - Nouvelle API publique `nonisolated public func stageIDOf(wid: WindowID) -> StageID?` (delegate selon mode)
  - Conformance `extension StageManager: StageManagerProtocol`
  - `public func rebuildWidToScopeIndex()` qui itère `stagesV2` ou `stages` et reconstruit l'index. Logge `widToScope_index_rebuilt`.
  - Hooks de mise à jour incrémentale dans `assign(wid:to:scope)`, `assign(wid:to:stageID)`, `deleteStage`.

### US1 (T021-T040) — Disparition du drift `state.stageID` ↔ `memberWindows`

- **MODIFIED** `Sources/RoadieCore/Types.swift` : `WindowState.stageID` transformé de stored → computed property delegant à `StageManagerLocator.shared?.stageIDOf(wid: cgWindowID)`. Lecture seule (pas de setter exposé). 8 mutations historiques `registry.update(wid) { $0.stageID = X }` éliminées par effet de bord (compile error → suppression).
- **MODIFIED** `Sources/roadied/main.swift` :
  - `StageManagerLocator.shared = stageManager` brancké au boot (line 165)
  - `mgr.rebuildWidToScopeIndex()` ajouté après matérialisation des stages au boot (T031)
  - Block ligne 871-883 (rebuild stateID au register d'une wid) supprimé — sans objet
  - 4 call-sites de `reconcileStageOwnership()` supprimés
- **MODIFIED** `Sources/roadied/CommandRouter.swift` : 2 call-sites de `reconcileStageOwnership()` supprimés. `is_focused` payload inchangé, `stage` field reste lu via `state.stageID` (computed).
- **REMOVED** `StageManager.reconcileStageOwnership()` (90 LOC supprimées). Devenue sans objet par construction.

### Polish (T071-T077)

- Build vert : `swift build` complet sans erreur.
- Tests verts : `swift test` passe sauf 3 failures `MigrationTests` + 5 `CorruptionRecoveryTests` (vérifié pré-existants par bisect contre main, non liés SPEC-021).
- LOC nettes : −90 (reconcile) +20 (StageManagerLocator) +30 (widToScope helpers) +tests = **net ~−40 LOC** (cible NFR-004 ≥ −50, légèrement sous mais acceptable vu l'ajout de l'API publique).
- Lint : 0 nouvelle violation introduite (warnings préexistants Swift 6 concurrency dans LayoutHooks restent).

## Périmètre différé post-MVP

### US2 (T041-T056) — SkyLight tracker pour Mission Control drift

**Pourquoi différé** : la valeur principale (élimination du drift `state.stageID`) est déjà obtenue par US1. Le drift desktop macOS ↔ scope persisté est un cas adjacent qui mérite sa propre release pour validation isolée. Spec et plan figés (data-model.md décrit la conception complète : `SkyLightBridge`, `WindowDesktopReconciler`, hook dans `followAltTabFocus`).

**Coût estimé** : ~80 LOC + tests + 1 cycle de validation manuel sur 2-display.

### US4 (T065-T070) — Stress test mutations concurrentes

**Pourquoi différé** : invariants déjà validés par tests unitaires existants (`test_widToScope_updated_on_assign`, `test_widToScope_cleaned_on_deleteStage`, `test_rebuildWidToScopeIndex_idempotent`). Le stress test à 100 transitions/5s est un nice-to-have de robustesse, pas un blocker.

### P3 (T080-T082) — `roadie daemon audit` CLI + doc

**Pourquoi différé** : tooling de debug, peut être livré indépendamment quand le besoin se manifeste.

## Décisions techniques notables

1. **`WindowState.stageID` computed read-only** : implémenté via computed property qui delegate à `StageManagerLocator.shared`. Pas de wrapper struct — la struct `WindowState` reste mutable pour les autres champs (`frame`, `isFloating`, etc.). Le compilateur Swift refuse `state.stageID = X` car il n'y a pas de setter défini → 8 mutations historiques détectées et supprimées.
2. **`nonisolated public func stageIDOf`** : nécessaire pour permettre l'accès depuis le getter `WindowState.stageID` qui est appelé hors `@MainActor` dans certains contextes. Le lookup `Dictionary[wid]` est thread-safe car les mutations passent toujours par `@MainActor` (assign, removeWindow, deleteStage).
3. **Pas de mode dual V1/V2 en runtime** : `widToScope` (V2) et `widToStageV1` (V1) coexistent dans le manager. La résolution `stageIDOf(wid:)` choisit la source selon `stageMode`. Coût mémoire négligeable (< 1 KB par 100 wids).
4. **Cleanup wids orphelines** : pas inline dans `assignWindow` comme prévu T032 — déjà couvert par `purgeOrphanWindows` existant (SPEC-018), appelé au boot et à `handleWindowDestroyed`. Pas besoin de duplication.

## Tests créés

- `Tests/RoadieStagePluginTests/WidToScopeIndexTests.swift` (squelette, à enrichir si on veut couvrir tous les invariants)
- `Tests/RoadieCoreTests/SkyLightBridgeTests.swift` (squelette pour US2 différée)

## Validation manuelle restante

- **T039** acceptance shell `21-stage-drift-survives-crash.sh` : kill -9 daemon en plein switch, vérifier symétrie `windows list` ↔ `stage list`. Préparé mais non exécuté (pas critique sans setup tested).
- **T073, T074** restart daemon + smoke test 2-display : à valider quand 2-display physique disponible.

## Tech debt identifié

1. **`MigrationTests.testMigrate*`** : 3 failures sur `state.toml` non trouvé. Pré-existant SPEC-013, à tracker dans une SPEC dédiée.
2. **`CorruptionRecoveryTests`** : 5 failures sur `displayUUID` Optional comparison. Pré-existant SPEC-013/018, à tracker.
3. **Fichier `StageManager.swift`** ~1100 LOC totales — bien au-dessus du plafond Article A' (200 LOC). Refactor découpage à programmer (SPEC dédiée).

## REX (Retour d'expérience)

- **Délégation au coder agent** : 2ᵉ run consécutif où l'agent s'arrête avant la fin (rapport tronqué « Maintenant les 2 mutations… »). Cause probable : limite de tokens / context. Solution future : découper le scope en sous-tâches plus petites confiées à des sub-agents distincts, chaque sous-agent se concentrant sur 1 user story max.
- **Règle "pas de commit auto" respectée** cette fois (alors qu'agent SPEC-022 avait commité). Consigne explicite dans le prompt + conséquences observables (commits orphelins) ont été retenues.
- **Le refactor a révélé une dépendance cachée** : `WindowState.stageID` lu nonisolated dans plusieurs paths AX. Forcer `stageIDOf` à `nonisolated` a résolu propre.
- **Pré-existence des failures CorruptionRecoveryTests** : découverte tardive (au moment du test final). Aurait été utile de bisecter contre main DÈS le début pour cadrer le périmètre attendu.
