# Architecture — Stage & Desktop Ownership (SPEC-021)

**Status** : Production. Livré 2026-05-03 (US1 + US2 + US4 + P3).

## Vue d'ensemble

L'attribution d'une fenêtre à un stage et à un desktop macOS suit deux principes inspirés de yabai et AeroSpace :

1. **Stage ownership** = source unique = `Stage.memberWindows` (persisté TOML). Tout le reste est dérivé.
2. **Desktop ownership** = pas de cache local. À chaque besoin, on demande à SkyLight (`SLSCopySpacesForWindows`).

## Composants

### `WindowState.stageID` (computed)

```swift
public struct WindowState {
    public let cgWindowID: WindowID
    /// Source unique : StageManagerLocator.shared?.stageIDOf(wid:).
    /// Lecture seule par construction (pas de setter). Toute mutation
    /// passe par stageManager.assign(wid:to:scope:).
    public var stageID: StageID? {
        StageManagerLocator.shared?.stageIDOf(wid: cgWindowID)
    }
}
```

### `StageManagerLocator` (RoadieCore)

Service locator simple qui détient une `weak var shared` vers le manager. Permet à `WindowState` (RoadieCore, sans dépendance vers RoadieStagePlugin) d'interroger sans cycle d'imports.

### `StageManager.widToScope` (index inverse)

```swift
private var widToScope: [WindowID: StageScope] = [:]      // mode V2 perDisplay
private var widToStageV1: [WindowID: StageID] = [:]       // mode V1 global
```

Index dérivé, source de vérité = `stagesV2.memberWindows` (resp. `stages.memberWindows`). Mis à jour incrémentalement à chaque mutation (`assign`, `deleteStage`, `removeWindow`). Reconstruit au boot via `rebuildWidToScopeIndex()`.

### `SkyLightBridge` (RoadieCore, ~55 LOC)

Bridge `@_silgen_name` vers les APIs SkyLight privées **lecture seule** (sans SIP off, pattern yabai éprouvé 5+ ans) :

- `SLSCopySpacesForWindows(cid, mask, [wid])` → space_id courant d'une fenêtre.
- `_CGSDefaultConnection()` → connection ID du process.
- `CGSCopyManagedDisplaySpaces(cid)` → liste `[(displayUUID, [spaceID])]` pour rebuild le cache.

### `DesktopRegistry.spaceIDToScopeCache`

Cache **RAM-only** (pas persisté) `[UInt64 (space_id) : (displayUUID, desktopID)]`. Reconstruit au boot et sur `display_changed`. Convention : pour un display donné, les spaces dans l'ordre retourné par SkyLight = desktopID 1, 2, 3, ... (pattern yabai/AeroSpace).

### `WindowDesktopReconciler` (~108 LOC)

Task `@MainActor` async qui, toutes les `pollIntervalMs` (default 2000, 0 = désactivé) :

1. Itère `registry.allWindows` filtrées par `isTileable && !isMinimized`
2. Pour chaque wid : `osScope = SkyLightBridge.currentSpaceID(wid) → DesktopRegistry.scopeForSpaceID`
3. Si `osScope.displayUUID != persistedScope.displayUUID || osScope.desktopID != persistedScope.desktopID` : enregistre l'observation dans `pendingMigrations[wid]`
4. Au cycle suivant, si même drift confirmé : `stageManager.assign(wid: wid, to: newScope)` — debounce 1 cycle = exiger 2 polls consécutifs avant de migrer (évite yo-yo pendant un drag actif)

Configurable via `[desktops].window_desktop_poll_ms` dans le TOML.

## Flow de propagation

```
User drag wid via Mission Control depuis desktop 1 vers desktop 2
                                    │
                                    ▼
       AX n'émet pas d'event dédié — silence côté roadie
                                    │
                                    ▼
       Au prochain tick reconciler (≤ 2s) :
         SkyLightBridge.currentSpaceID(wid) → space_id_2
         DesktopRegistry.scopeForSpaceID(space_id_2) → (display, desktop=2)
         stageManager.scopeOf(wid) → (display, desktop=1)  ← drift détecté
         pendingMigrations[wid] = (newScope, now)
                                    │
                                    ▼
       Au tick suivant (≤ 2s) :
         Drift confirmé → stageManager.assign(wid, to: newScope)
                                    │
                                    ▼
       Index widToScope mis à jour, fichiers TOML re-écrits, navrail
       du desktop 2 affiche la vignette correctement.
```

## Audit ownership

Commande CLI `roadie daemon audit` retourne JSON :

```json
{
  "violations": ["wid 12 in widToScope[1] but not in memberWindows", ...],
  "count": 0,
  "healthy": true
}
```

Vérifie 3 invariants en O(stages × members + scopes²) :

- I1 : `widToScope[wid]` pointe vers un scope qui contient effectivement la wid
- I2 : Pour chaque `memberWindows[wid]`, `widToScope[wid]` pointe vers ce scope
- I3 : Aucune wid présente simultanément dans 2 scopes (intersection vide)

Appelée aussi au boot avec log d'erreur si non-vide. Utile pour diagnostiquer un fichier TOML hérité d'une session ancienne.

## Migration depuis l'ancienne architecture

| Avant | Après |
|---|---|
| `WindowState.stageID: StageID?` (stored, mutable, 8 mutations) | `WindowState.stageID: StageID? { get }` (computed, lecture seule) |
| `StageManager.reconcileStageOwnership()` (~90 LOC, appelée à 4 sites) | Supprimée — sans objet par construction |
| Drift desktop macOS via Mission Control non détecté | `WindowDesktopReconciler` poll 2s, debounce 1 cycle |
| Pas d'outil de debug invariants | `roadie daemon audit` + log au boot |

## Compatibilité TOML

- Les fichiers `~/.config/roadies/stages/<UUID>/<desktop>/<stage>.toml` restent strictement identiques.
- Aucune migration de format requise. Le refactor est purement interne.

## Configuration

```toml
[desktops]
window_desktop_poll_ms = 2000   # 0 = disable Mission Control tracking, 2000 = 2s default
```
