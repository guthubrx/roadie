# Data Model: Single Source of Truth — Stage/Desktop Ownership

**Spec**: SPEC-021 | **Created**: 2026-05-03

## Vue d'ensemble du diff data-model

| Type | Avant | Après |
|---|---|---|
| `WindowState.stageID` | `var stageID: StageID?` (stored) | `var stageID: StageID? { get }` (computed, weak ref vers StageManager) |
| `StageManager.widToScope` | _absent_ | `private var widToScope: [WindowID: StageScope] = [:]` |
| `StageManager.widToStageV1` | _absent_ | `private var widToStageV1: [WindowID: StageID] = [:]` (mode V1 global) |
| `StageManager.scopeOf(wid:)` | _absent_ | `public func scopeOf(wid: WindowID) -> StageScope?` |
| `StageManager.stageIDOf(wid:)` | _absent_ | `public func stageIDOf(wid: WindowID) -> StageID?` |
| `StageManager.reconcileStageOwnership` | `public func reconcileStageOwnership()` (~90 LOC) | _supprimée_ |
| `DesktopRegistry.scopeForSpaceID` | _absent_ | `public func scopeForSpaceID(_ spaceID: UInt64) -> (displayUUID: String, desktopID: Int)?` |
| `SkyLightBridge` | _absent_ | nouveau fichier `Sources/RoadieCore/SkyLightBridge.swift` (~30 LOC) |
| `WindowDesktopReconciler` | _absent_ | nouveau fichier `Sources/roadied/WindowDesktopReconciler.swift` (~80 LOC) |

---

## `WindowState.stageID` — computed property (Sources/RoadieCore/Types.swift)

### Avant (stored)

```swift
public struct WindowState: Sendable {
    public let cgWindowID: WindowID
    public var frame: CGRect
    public var stageID: StageID?  // ← stored, mutable, ancrage du drift
    /* ... */
}
```

### Après (computed)

```swift
public struct WindowState: Sendable {
    public let cgWindowID: WindowID
    public var frame: CGRect
    /// SPEC-021 : computed property, lecture-seule. Source unique = StageManager.widToScope.
    /// L'écriture est interdite (compile error : `state.stageID = X` ne compile plus).
    /// Pour mettre une wid dans un stage : `stageManager.assign(wid:to:)`.
    public var stageID: StageID? {
        StageManagerLocator.shared?.stageIDOf(wid: cgWindowID)
    }
    /* ... */
}
```

`StageManagerLocator` est un service locator simple (singleton initialisé au boot) qui détient une weak ref vers le `StageManager` du daemon. Permet à `WindowState` (dans RoadieCore, sans dépendance circulaire vers RoadieStagePlugin) d'interroger le manager via une fonction libre.

```swift
// Sources/RoadieCore/StageManagerLocator.swift (nouveau, ~20 LOC)
public protocol StageManagerProtocol: AnyObject {
    func stageIDOf(wid: WindowID) -> StageID?
}

@MainActor
public enum StageManagerLocator {
    public static weak var shared: StageManagerProtocol?
}
```

Le daemon initialise `StageManagerLocator.shared = stageManager` au démarrage.

---

## `StageManager` — index inverse `widToScope`

### Nouveau champ (mode V2 perDisplay)

```swift
/// SPEC-021 : index inverse wid → scope, mis à jour incrémentalement par les
/// mutations de stagesV2. Reconstruit au boot via rebuildWidToScopeIndex().
/// Source dérivée — pas une vérité, juste un cache de lookup O(1).
private var widToScope: [WindowID: StageScope] = [:]
```

### Nouveau champ (mode V1 global)

```swift
/// SPEC-021 : équivalent V1 (stages flat), mappe wid → stageID.
private var widToStageV1: [WindowID: StageID] = [:]
```

### Hooks de mise à jour

Dans `assign(wid: WindowID, to scope: StageScope)` (StageManager.swift:672-720) :
```swift
// Avant le block existant qui mute stagesV2 :
widToScope[wid] = scope

// Si la wid était dans un autre scope, l'ancien scope a déjà été nettoyé
// par la boucle existante "for s in stagesV2 where s != scope { remove }".
// L'index est cohérent en sortie de fonction.
```

Dans `assign(wid: WindowID, to stageID: StageID)` (V1) :
```swift
widToStageV1[wid] = stageID
```

Dans `removeWindow(wid:)` (à ajouter ou compléter) :
```swift
public func removeWindow(_ wid: WindowID) {
    widToScope.removeValue(forKey: wid)
    widToStageV1.removeValue(forKey: wid)
    // ... cleanup memberWindows existant
}
```

Dans `deleteStage(id:)` :
```swift
// Itérer les wids retirées et nettoyer l'index
for member in deletedStage.memberWindows {
    widToScope.removeValue(forKey: member.cgWindowID)
}
```

### API publique

```swift
/// SPEC-021 — résout le scope d'une wid en O(1). Source unique de vérité,
/// remplace l'ancien `WindowState.stageID` stored.
public func scopeOf(wid: WindowID) -> StageScope? {
    widToScope[wid]
}

/// SPEC-021 — helper pour récupérer juste le stageID, en mode V1 ou V2.
public func stageIDOf(wid: WindowID) -> StageID? {
    if stageMode == .perDisplay {
        return widToScope[wid]?.stageID
    }
    return widToStageV1[wid]
}
```

### Reconstruction au boot

```swift
/// SPEC-021 — appelé après loadFromPersistence pour reconstruire l'index inverse
/// depuis la source de vérité (memberWindows). O(stages × members) une fois au boot.
public func rebuildWidToScopeIndex() {
    widToScope.removeAll(keepingCapacity: true)
    widToStageV1.removeAll(keepingCapacity: true)
    if stageMode == .perDisplay {
        for (scope, stage) in stagesV2 {
            for member in stage.memberWindows {
                widToScope[member.cgWindowID] = scope
            }
        }
    } else {
        for (sid, stage) in stages {
            for member in stage.memberWindows {
                widToStageV1[member.cgWindowID] = sid
            }
        }
    }
    logInfo("widToScope_index_rebuilt", [
        "v2_entries": String(widToScope.count),
        "v1_entries": String(widToStageV1.count),
    ])
}
```

---

## `SkyLightBridge` (Sources/RoadieCore/SkyLightBridge.swift, nouveau)

```swift
import Foundation
import CoreGraphics

/// SPEC-021 — bridge vers SLSCopySpacesForWindows (lecture seule, sans SIP off,
/// pattern yabai éprouvé en prod 5+ ans). Permet de récupérer le space_id macOS
/// courant d'une fenêtre tierce, source de vérité OS, pas un cache local.

@_silgen_name("SLSCopySpacesForWindows")
private func SLSCopySpacesForWindows(_ cid: Int, _ mask: UInt32, _ wids: CFArray) -> CFArray?

@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> Int

public enum SkyLightBridge {
    /// Retourne le space_id du desktop visible courant pour une wid donnée.
    /// nil si la wid n'a pas de space attribué (helper, off-screen, fullscreen non-managed).
    /// Latence typique ≤ 1 ms.
    @MainActor
    public static func currentSpaceID(for wid: CGWindowID) -> UInt64? {
        let cid = _CGSDefaultConnection()
        let widsArray = [wid] as CFArray
        guard let spaces = SLSCopySpacesForWindows(cid, 0x7, widsArray) as? [UInt64],
              let first = spaces.first else { return nil }
        return first
    }
}
```

---

## `DesktopRegistry.scopeForSpaceID`

```swift
/// SPEC-021 — résout un space_id SkyLight vers un scope roadie (displayUUID, desktopID).
/// Cache rebuilt au scan SkyLight initial (boot + display reconfiguration).
/// Retourne nil si le space_id est inconnu (espace fullscreen natif, desktop nouvellement créé).
public func scopeForSpaceID(_ spaceID: UInt64) -> (displayUUID: String, desktopID: Int)? {
    spaceIDToScopeCache[spaceID]
}
```

Rebuild via :

```swift
private func rebuildSpaceIDCache() {
    spaceIDToScopeCache.removeAll(keepingCapacity: true)
    for display in displays {
        for desktop in display.desktops {
            if let sid = desktop.skyLightSpaceID {
                spaceIDToScopeCache[sid] = (display.uuid, desktop.id)
            }
        }
    }
}
```

(Hors scope strict de cette spec : si `Desktop.skyLightSpaceID` n'est pas déjà tracké par SPEC-013, ajout mineur ≤ 30 LOC en pré-requis.)

---

## `WindowDesktopReconciler` (Sources/roadied/WindowDesktopReconciler.swift, nouveau)

```swift
import Foundation
import CoreGraphics
import RoadieCore
import RoadieDesktops
import RoadieStagePlugin

/// SPEC-021 — Tracker périodique du desktop macOS courant des wids tileables.
/// Détecte les déplacements via Mission Control natif (Cmd+drag) qui ne génèrent
/// pas d'event AX dédié. Réattribue la wid au scope correct si drift détecté.
/// Pattern : poll léger toutes les `pollIntervalMs` (default 2000ms, configurable).

@MainActor
public final class WindowDesktopReconciler {
    private weak var registry: WindowRegistry?
    private weak var desktopRegistry: DesktopRegistry?
    private weak var stageManager: StageManager?
    private let pollIntervalMs: Int
    private var task: Task<Void, Never>?
    /// Debounce : exiger 2 polls consécutifs avec le même space_id divergent
    /// avant de déclencher la ré-attribution. Évite les yo-yo pendant un drag actif.
    private var pendingMigrations: [WindowID: (toScope: StageScope, observedAt: Date)] = [:]

    public init(registry: WindowRegistry, desktopRegistry: DesktopRegistry,
                stageManager: StageManager, pollIntervalMs: Int) {
        self.registry = registry
        self.desktopRegistry = desktopRegistry
        self.stageManager = stageManager
        self.pollIntervalMs = pollIntervalMs
    }

    public func start() {
        guard pollIntervalMs > 0 else {
            logInfo("window_desktop_reconciler_disabled", ["reason": "poll_ms_zero"])
            return
        }
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self?.pollIntervalMs ?? 2000) * 1_000_000)
                self?.tick()
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    private func tick() {
        guard let registry = registry,
              let desktopRegistry = desktopRegistry,
              let stageManager = stageManager else { return }

        for state in registry.allWindows where state.isTileable && !state.isMinimized {
            let wid = state.cgWindowID
            guard let osSpaceID = SkyLightBridge.currentSpaceID(for: wid),
                  let osScope = desktopRegistry.scopeForSpaceID(osSpaceID),
                  let persistedScope = stageManager.scopeOf(wid: wid)
            else { continue }

            let osScopeKey = StageScope(displayUUID: osScope.displayUUID,
                                         desktopID: osScope.desktopID,
                                         stageID: persistedScope.stageID)

            if osScope.displayUUID != persistedScope.displayUUID
               || osScope.desktopID != persistedScope.desktopID {
                // Debounce : 1 cycle d'attente.
                if let pending = pendingMigrations[wid],
                   pending.toScope.displayUUID == osScope.displayUUID
                   && pending.toScope.desktopID == osScope.desktopID {
                    // Confirmé sur 2 cycles consécutifs → migrer.
                    stageManager.assign(wid: wid, to: osScopeKey)
                    pendingMigrations.removeValue(forKey: wid)
                    logInfo("wid_desktop_migrated", [
                        "wid": String(wid),
                        "from_scope": "\(persistedScope.displayUUID):\(persistedScope.desktopID)",
                        "to_scope": "\(osScope.displayUUID):\(osScope.desktopID)",
                    ])
                } else {
                    pendingMigrations[wid] = (osScopeKey, Date())
                }
            } else {
                pendingMigrations.removeValue(forKey: wid)
            }
        }
    }
}
```

---

## Persistence — aucun changement

Les fichiers TOML `~/.config/roadies/stages/<UUID>/<desktop>/<stage>.toml` restent strictement identiques. La struct `Stage.memberWindows: [StageMember]` est conservée. Le format `StageMember { cgWindowID, bundleID, titleHint, savedFrame }` est inchangé.

Le seul changement on-disk est la **suppression** (T-non-prio) du fichier global `~/.config/roadies/stages/active.toml` deprecated (déjà loggé en warn par SPEC-022 T065).

---

## Compatibilité

- **V1 mode global** : `widToStageV1` remplace fonctionnellement la lecture de `state.stageID`. Pas de breaking change utilisateur.
- **V2 mode perDisplay** : `widToScope` couvre le cas multi-display + multi-desktop. Pas de breaking change.
- **Modules SIP-off (SPEC-004+)** : si un module lisait `state.stageID`, ça continue à fonctionner via la computed property. Lecture OK, écriture impossible.
- **Tests existants** : la lecture `state.stageID` est préservée via le getter computed. Aucun test modifié sur ce champ.
