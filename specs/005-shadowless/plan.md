# Implementation Plan: RoadieShadowless (SPEC-005)

**Branch** : `005-shadowless` | **Date** : 2026-05-01 | **Spec** : [spec.md](./spec.md)
**Input** : Feature specification from `/specs/005-shadowless/spec.md`

## Summary

Premier module FX du framework SPEC-004. Désactive (ou customise la densité de) l'ombre des fenêtres tierces tilées. Module mono-fichier ou dual-fichier max, ≤ 120 LOC strict (cible 80). Subscribe aux events `window_created` / `window_focused` / `stage_changed` / `desktop_changed` via l'EventBus partagé, calcule la density cible selon `mode` config, envoie `OSAXCommand.setShadow` via `OSAXBridge` (RoadieFXCore). Au `shutdown()`, restaure les ombres par défaut. Hot-reload via reload config.

## Technical Context

**Language/Version** : Swift 5.9+, conforme aux contraintes V1 (`@MainActor`, Sendable où nécessaire)

**Primary Dependencies** :
- `RoadieFXCore.dylib` (chargée à runtime, fournit `OSAXBridge`, `EventBus` accessor, `FXModule` protocol)
- Pas de framework système nouveau
- Pas de dépendance externe

**Storage** : aucune (le module ne persiste rien sur disque, état purement RAM)

**Testing** :
- Tests unitaires XCTest sur la logique pure (`mode → density mapping`, `clamp density`)
- Tests d'intégration : étendre `tests/integration/12-fx-loaded.sh` (SPEC-004) avec un `assert visuel` (mesure shadow via screenshot diff, ou simple log check côté osax)

**Target Platform** : identique SPEC-004 (macOS 14+, SIP partial off requis pour effet)

**Project Type** : Swift target `.dynamicLibrary` ajouté à `Package.swift`

**Performance Goals** :
- SC-001 : latence event → shadow updated ≤ 100 ms
- SC-005 : LOC ≤ 120 strict (cible 80)

**Constraints** :
- Plafond LOC strict 120 — toute tâche qui pousserait au-dessus = STOP
- Pas de framework nouveau, pas de dépendance externe
- Restauration garantie au shutdown (pas d'effet rémanent)
- Module désactivable via flag config sans le retirer

**Scale/Scope** :
- 1 utilisateur, jusqu'à 100 fenêtres simultanées
- ~1-5 events par seconde (moy.) → 1-5 OSAX calls / sec (largement sous le throttle 1000/sec)

## Constitution Check

| Principe | Conformité |
|---|---|
| **A — Préservation Loi de Conservation** | ✅ aucune intention V1/V2/V3 supprimée, ajout pur |
| **A' — Suckless en esprit** | ✅ ≤ 120 LOC ; idéalement 1 fichier `Module.swift` |
| **B' — Dépendances minimisées** | ✅ aucune dépendance nouvelle |
| **C' — APIs privées encadrées (amendée 1.3.0)** | ✅ module SIP-off opt-in déclaré dans famille SPEC-004 |
| **D' — Fail loud** | ✅ log warnings sur osax indispo, mode invalide, etc. |
| **G — Mode Minimalisme LOC** | ✅ plafond 120 strict déclaré |
| **I' — Architecture pluggable** | ✅ module est `.dynamicLibrary` séparé, daemon ignore son existence sans osax |

✅ Toutes gates passent. Pas de violation à justifier.

## Project Structure

### Documentation (this feature)

```text
specs/005-shadowless/
├── plan.md
├── spec.md
├── tasks.md
└── checklists/requirements.md
```

(Pas de research.md / data-model.md / contracts/ : trop simple pour justifier ces artefacts. Les détails ABI sont dans SPEC-004.)

### Source Code

```text
Sources/
└── RoadieShadowless/                # NEW target .dynamicLibrary
    └── Module.swift                 # ~80 LOC : tout le module
                                      #   - @_cdecl module_init
                                      #   - ShadowlessModule.shared singleton
                                      #   - subscribe + handleEvent
                                      #   - shutdown() restaure
                                      #   - ShadowMode enum
                                      #   - mapWindow(wid) -> density?

Tests/
└── RoadieShadowlessTests/
    └── ModeMappingTests.swift       # tests purs sur logique mode→density

tests/integration/
└── 16-fx-shadowless.sh              # extension de 12-fx-loaded.sh
```

### Modifications

- `Package.swift` : ajouter target `RoadieShadowless` type `.dynamicLibrary` et target test `RoadieShadowlessTests`
- Aucune modification du daemon, RoadieCore, RoadieTiler, RoadieStagePlugin

## Phase 0 — Research

Pas de recherche nécessaire. Tout l'inconnu technique a été résolu dans SPEC-004 research.md (déclarations CGS, ABI vtable, OSAXBridge protocol).

## Phase 1 — Design

### Logique mode → density

```swift
enum ShadowMode: String { case all, tiledOnly = "tiled-only", floatingOnly = "floating-only" }

func targetDensity(for window: WindowState, mode: ShadowMode, configDensity: Double) -> Double? {
    switch mode {
    case .all:           return clamp(configDensity)
    case .tiledOnly:     return window.isFloating ? nil : clamp(configDensity)
    case .floatingOnly:  return window.isFloating ? clamp(configDensity) : nil
    }
}

private func clamp(_ d: Double) -> Double { max(0.0, min(1.0, d)) }
```

→ `nil` retourné = "ne touche pas cette fenêtre" (n'envoie pas de OSAX cmd).

### Module skeleton

```swift
@_cdecl("module_init")
public func module_init() -> UnsafeMutablePointer<FXModuleVTable> {
    let vtable = UnsafeMutablePointer<FXModuleVTable>.allocate(capacity: 1)
    vtable.pointee.name = strdup("shadowless")
    vtable.pointee.version = strdup("0.1.0")
    vtable.pointee.subscribe = { busPtr in
        ShadowlessModule.shared.subscribe(to: FXEventBus.from(opaquePtr: busPtr))
    }
    vtable.pointee.shutdown = {
        ShadowlessModule.shared.shutdown()
    }
    return vtable
}

@MainActor
final class ShadowlessModule {
    static let shared = ShadowlessModule()
    private var trackedWindows: Set<CGWindowID> = []
    private var config: ShadowlessConfig = .init()
    private var bridge: OSAXBridge { RoadieFXCore.bridge }

    func subscribe(to bus: FXEventBus) {
        bus.subscribe(self, to: [.windowCreated, .windowFocused, .stageChanged, .desktopChanged, .configReloaded])
    }

    func handleEvent(_ event: FXEvent) {
        guard config.enabled else { return }
        // Trouve les fenêtres à updater selon event
        // Pour chaque : calcule targetDensity, envoie set_shadow via bridge
    }

    func shutdown() {
        for wid in trackedWindows {
            Task { _ = await bridge.send(.setShadow(wid: wid, density: 1.0)) }
        }
        trackedWindows.removeAll()
    }
}
```

### Hot-reload

L'event `configReloaded` (à ajouter en SPEC-004 si pas déjà fait, sinon ici) est émis quand `roadie daemon reload` est exécuté. Le module relit sa section TOML et ré-applique sur toutes les fenêtres concernées.

### Constitution Check (post Phase 1)

- ✅ Module mono-fichier `Module.swift` ≤ 120 LOC
- ✅ Pas de fichier > 200 LOC effectives (constitution-002 A')
- ✅ Aucune nouvelle dépendance
- ✅ Tests unitaires sur logique pure prévus (T030 dans tasks.md)

## Complexity Tracking

Aucune violation. Module trivial.
