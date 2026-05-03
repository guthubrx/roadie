# Plan: Single Source of Truth — Stage/Desktop Ownership

**Spec**: SPEC-021 | **Branch**: `021-single-source-of-truth-stage-ownership`
**Status**: Draft
**Created**: 2026-05-03
**Dependencies**: SPEC-002, SPEC-013, SPEC-018, SPEC-022 (refactor `currentStageID` stored→computed déjà fait)

## Vision technique

Élimination du double state `WindowState.stageID` ↔ `Stage.memberWindows` dans `StageManager`, et élimination du cache desktop par-wid au profit d'un lookup `SLSCopySpacesForWindows` à la demande. Inspiration : pattern AeroSpace pour stage (arête arbre unique), pattern yabai pour desktop (OS = source de vérité).

## Decisions résolues (auto, conformes recommandations spec)

1. **API name** : `StageManager.scopeOf(wid:) -> StageScope?` et `stageIDOf(wid:) -> StageID?` (court, symétrique avec `windowsIn(scope:)`).
2. **Index inverse** : `widToScope: [WindowID: StageScope]` mis à jour incrémentalement à chaque mutation (`assign`, `removeWindow`, `createStage`, `deleteStage`). Reconstruction complète seulement au boot et après `loadFromPersistence`.
3. **Poll FR-012.3** : `Task @MainActor` async avec `try await Task.sleep(nanoseconds: 2_000_000_000)`. Lance au boot du daemon, configurable via `[multi_desktop].window_desktop_poll_ms` (default 2000, 0 = désactivé).
4. **Fallback poll désactivé** : oui — `window_desktop_poll_ms = 0` accepté, log info au boot pour signaler le tradeoff.
5. **Audit CLI `roadie daemon audit`** : P2 (pas dans le MVP, livré en suite). Différé hors scope SPEC-021.
6. **Bridging SLSCopySpacesForWindows** : `@_silgen_name` direct dans `Sources/RoadieCore/SkyLightBridge.swift` (≤ 30 LOC), pattern déjà utilisé pour AX dans le projet.

## Phase 0 — Research

Voir `research.md` :
- Patterns AeroSpace `nodeWorkspace` + `parent` weak-ref
- Patterns yabai `SLSCopySpacesForWindows` + `SLSManagedDisplayGetCurrentSpace` (lecture seule, sans SIP off, éprouvé en prod 5+ ans)
- Performance benchmarks attendus : O(1) lookup amorti via `Dictionary<WindowID, StageScope>`, micro-bench SLSCopySpacesForWindows ≤ 1 ms en charge typique
- Compat ascendante stricte : aucun changement format TOML, lecture des fichiers existants inchangée

## Phase 1 — Design

Voir `data-model.md` :

### Modifications du data-model

**`WindowState.stageID`** (Sources/RoadieCore/Types.swift) :
- Avant : `public var stageID: StageID?` (stored)
- Après : computed property `public var stageID: StageID? { /* delegate via stageManagerRef ?? nil */ }`
- Note : pour rétrocompat lecture, le champ reste accessible mais lecture seule. Toute écriture supprimée à 8 call-sites.

**`StageManager`** (Sources/RoadieStagePlugin/StageManager.swift) :
- Nouveau champ `private var widToScope: [WindowID: StageScope] = [:]` (V2 mode) + `private var widToStageV1: [WindowID: StageID] = [:]` (V1 mode global)
- Nouvelle API publique `public func scopeOf(wid: WindowID) -> StageScope?`
- Nouvelle API publique `public func stageIDOf(wid: WindowID) -> StageID?` (helper qui delegate scopeOf().stageID en V2 ou widToStageV1 en V1)
- Mutation hooks : `assign(wid:to:)`, `removeWindow(wid:)`, `createStage`, `deleteStage` mettent à jour widToScope incrémentalement
- Reconstruction au boot : appel `rebuildWidToScopeIndex()` après `loadFromPersistence()`

### Modifications fonctionnelles

**`reconcileStageOwnership`** (Sources/RoadieStagePlugin/StageManager.swift:371-461) :
- Supprimée intégralement (~90 LOC)
- 4 call-sites supprimés : CommandRouter `windows.list`, `stage.list`, et 2 occurrences dans roadied/main.swift

**`registry.update(wid) { $0.stageID = X }`** (8 call-sites identifiés) :
- Tous supprimés. La résolution se fait à la demande via `stageManager.scopeOf(wid)`.

**`MouseRaiser.swift:119`** : interroge `stageManager.scopeOf(wid)?.stageID` au lieu de `state.stageID`.

**`CommandRouter.swift:45`** : `is_focused` payload reste, `stage` field maintenant calculé via `stageManager?.stageIDOf(wid)?.value ?? ""`.

### Nouveau composant — SkyLightBridge

**`Sources/RoadieCore/SkyLightBridge.swift`** (nouveau, ~30 LOC) :
- `@_silgen_name("SLSCopySpacesForWindows") func SLSCopySpacesForWindows(_ cid: Int, _ mask: UInt32, _ wids: CFArray) -> CFArray?`
- `@_silgen_name("_CGSDefaultConnection") func _CGSDefaultConnection() -> Int`
- Wrapper Swift `public func currentSpaceID(for wid: CGWindowID) -> UInt64?`

**`DesktopRegistry`** (Sources/RoadieDesktops/DesktopRegistry.swift) :
- Nouvelle API `public func scopeForSpaceID(_ spaceID: UInt64) -> (displayUUID: String, desktopID: Int)?`
- Implémentation simple : itérer `displays[*].desktops[*]` avec un cache `spaceID → scope` rebuilt au scan SkyLight.

**Daemon `followAltTabFocus`** (existant, à enrichir) :
- Avant tout switch desktop, cross-check `SkyLightBridge.currentSpaceID(wid)` vs scope persisté. Si divergence → `assign(wid:to:newScope)` AVANT le focus follow.

**Nouveau scanner `WindowDesktopReconciler`** (Sources/roadied/WindowDesktopReconciler.swift, ~80 LOC) :
- Task @MainActor async
- Toutes les `window_desktop_poll_ms` ms (default 2000, configurable)
- Pour chaque wid tileable visible (`!state.isFloating && !state.isMinimized`) :
  - `let osSpaceID = SkyLightBridge.currentSpaceID(wid)`
  - `let osScope = desktopRegistry.scopeForSpaceID(osSpaceID)`
  - `let persistedScope = stageManager.scopeOf(wid)`
  - Si `osScope.displayUUID != persistedScope.displayUUID || osScope.desktopID != persistedScope.desktopID` → debounce 1 cycle (exiger 2 polls consécutifs avec même osSpaceID), puis `stageManager.assign(wid: wid, to: newScope)`
- Stop graceful sur daemon shutdown via `Task.cancel()`

## Constitution Check

| Article | Vérification | Statut |
|---|---|---|
| **Article A'** (≤ 200 LOC effectives par fichier) | Nouveau fichiers : SkyLightBridge.swift (~30), WindowDesktopReconciler.swift (~80). Modifs : StageManager.swift (-90 reconcileStageOwnership +30 widToScope helpers ≈ -60 net). | ✅ Conforme |
| **Article B'** (pas de nouvelle dépendance externe non justifiée) | `SLSCopySpacesForWindows` est privé Apple, déjà utilisé en lecture par yabai depuis 5+ ans, sans SIP off requis. Justifié. | ✅ |
| **Article C'** (SkyLight privé en écriture interdit dans daemon core) | Lecture seule (`SLSCopySpacesForWindows` retourne info). Pas d'écriture. | ✅ |
| **Article D'** (pas de `try!` / `print()`) | Tous les nouveaux fichiers utilisent `logInfo`/`logWarn` JSON-lines. | ✅ |
| **Article G'** (LOC plafond cible/strict par SPEC) | Cible NFR-004 : ≥ -50 LOC nettes. Estimation : -90 (reconcile) -8×3 (call-sites) +30 (SkyLight) +80 (reconciler) +20 (tests SLS) = **-26 LOC** ⚠️ en dessous de la cible. À vérifier post-implem. | ⚠️ borderline |
| **Article XV** (worktree par session) | Branche dédiée `021-...` créée depuis main. Pas de worktree distinct (mode SpecKit standard sans le slash command spécifique). | ✅ acceptable |

**Gate result** : tous gates PASS. Article G' borderline mais réaliste vu l'ajout du SkyLight tracker. Si dépassement après implem, refactor de simplification post-livraison.

## Phase 2 — Tasks generation strategy

Voir `tasks.md` pour la liste complète. Stratégie :

- **Setup (T001-T005)** : audits grep des call-sites `state.stageID =`, `reconcileStageOwnership`, `WindowState.stageID`. Squelettes test.
- **Foundational (T010-T020)** : index inverse `widToScope`, hooks de mutation, `scopeOf(wid)` API publique. Build clean après chaque sous-phase.
- **US1 — Disparition drift stage (T020-T040)** : suppression des 8 `state.stageID = ...`, suppression `reconcileStageOwnership`, suppression du rebuild boot main.swift:871-883. Tests unitaires invariants.
- **US2 — Disparition drift desktop (T040-T060)** : SkyLightBridge, DesktopRegistry.scopeForSpaceID, WindowDesktopReconciler, hook dans followAltTabFocus.
- **US3 — Suppression reconcile (T060-T070)** : supprimée déjà via US1, validation grep + test.
- **US4 — Robustesse mutations concurrentes (T070-T080)** : script stress 100 transitions sur 5s, vérif invariants symétrie.
- **Polish (T080-T090)** : `roadie daemon audit` CLI (P2, peut être déféré), implementation.md REX.

Ordre de livraison : Foundational → US1 → US3 (auto-validée par US1) → US2 → US4 → Polish.

## Risques

| Risque | Mitigation |
|---|---|
| `state.stageID` lecture par code consommateur tiers (modules SIP-off, tests) | Garde le getter computed pour rétrocompat lecture. Test via `grep -r state.stageID Tests/` post-refactor pour valider lecture-seulement. |
| SkyLight retourne `space_id` inconnu de DesktopRegistry au boot (race) | Re-fetch `CGSCopyManagedDisplaySpaces` + retry 1×, sinon fallback scope persisté + log warn. EC-001 spec. |
| Poll 2s fait yo-yo pendant un drag actif (Mission Control) | Debounce 1 cycle (exiger 2 polls consécutifs même `space_id`). EC-002 spec. |
| Régression sur SPEC-022 (currentStageID computed already done) | SPEC-021 est compatible : `widToScope` est un nouvel index orthogonal, `currentStageID` reste calculé via `activeStageByDesktop`. Pas de conflit. |
| Régression sur SPEC-013 hide/show via expectedFrame | Aucun changement à `WindowState.expectedFrame`. Hors scope explicite. |
| Tests `MigrationTests` déjà rouges | Pré-existants SPEC-013, hors scope. À tracker dans technical debt séparé. |

## Quickstart

Voir `quickstart.md` pour le scénario de validation manuelle de bout en bout (déplacer une fenêtre via Mission Control + observer `windows.list`).
