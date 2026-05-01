import Foundation
import CoreGraphics
import RoadieCore
import RoadieFXCore

/// SPEC-005 RoadieShadowless — désactive (ou customise la densité de) l'ombre des
/// fenêtres tierces tilées. Module mono-fichier opt-in chargé via dlopen par le
/// daemon FXLoader (SPEC-004).
///
/// Plafond LOC strict : 120 (cible 80). Mesure : `find Sources/RoadieShadowless ...`.

/// Modes d'application : sur quelles fenêtres appliquer la densité custom.
public enum ShadowMode: String, Codable, Sendable {
    case all
    case tiledOnly = "tiled-only"
    case floatingOnly = "floating-only"
}

/// Configuration du module, parsée depuis section `[fx.shadowless]` du `roadies.toml`.
public struct ShadowlessConfig: Codable, Sendable {
    public var enabled: Bool = false
    public var mode: ShadowMode = .tiledOnly
    public var density: Double = 0.0
}

/// Logique pure : détermine la densité cible pour une fenêtre selon mode + density config.
/// Retourne `nil` si la fenêtre ne doit pas être touchée par ce mode.
/// Density clamp dans [0.0, 1.0].
public func targetDensity(isFloating: Bool, mode: ShadowMode, configDensity: Double) -> Double? {
    let clamped = max(0.0, min(1.0, configDensity))
    switch mode {
    case .all:           return clamped
    case .tiledOnly:     return isFloating ? nil : clamped
    case .floatingOnly:  return isFloating ? clamped : nil
    }
}

/// Singleton module. État RAM : trackedWindows pour restauration au shutdown.
public final class ShadowlessModule: @unchecked Sendable {
    public static let shared = ShadowlessModule()
    public var config = ShadowlessConfig()
    private var trackedWindows: Set<CGWindowID> = []
    private let lock = NSLock()
    private var subscriptionID: UUID?

    public func subscribe(to bus: FXEventBus) {
        let id = bus.subscribe(to: [.windowCreated, .windowFocused,
                                    .stageChanged, .desktopChanged,
                                    .configReloaded]) { [weak self] event in
            self?.handle(event: event)
        }
        lock.lock(); subscriptionID = id; lock.unlock()
    }

    public func shutdown() {
        // Restaure ombre par défaut sur toutes wid tracked.
        let wids: [CGWindowID] = lock.withLock {
            let snapshot = Array(trackedWindows)
            trackedWindows.removeAll()
            return snapshot
        }
        Task {
            for wid in wids {
                _ = await OSAXBridgeProvider.shared.send(.setShadow(wid: wid, density: 1.0))
            }
        }
    }

    private func handle(event: FXEvent) {
        guard config.enabled else { return }
        guard let wid = event.wid else { return }
        let isFloating = event.isFloating ?? false
        guard let target = targetDensity(isFloating: isFloating,
                                         mode: config.mode,
                                         configDensity: config.density) else { return }
        lock.lock(); trackedWindows.insert(wid); lock.unlock()
        Task { _ = await OSAXBridgeProvider.shared.send(.setShadow(wid: wid, density: target)) }
    }
}

/// Singleton bridge OSAX partagé (instancié au premier accès).
/// Permet aux modules de tous parler à la même instance sans duplication.
public final class OSAXBridgeProvider: @unchecked Sendable {
    public static let shared: OSAXBridge = OSAXBridge()
}

/// Entry point appelé par le daemon FXLoader. Retourne un pointeur opaque
/// vers la vtable que le loader cast en `FXModuleVTable`.
@_cdecl("roadie_fx_init_shadowless")
public func roadie_fx_init_shadowless() -> UnsafeMutableRawPointer {
    let vtable = UnsafeMutablePointer<FXModuleVTable>.allocate(capacity: 1)
    let nameStr = strdup("shadowless")!
    let versionStr = strdup("0.1.0")!
    vtable.initialize(to: FXModuleVTable(
        name: UnsafePointer(nameStr),
        version: UnsafePointer(versionStr),
        subscribe: { busPtr in
            ShadowlessModule.shared.subscribe(to: FXEventBus.from(opaquePtr: busPtr))
        },
        shutdown: { ShadowlessModule.shared.shutdown() }
    ))
    return UnsafeMutableRawPointer(vtable)
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        self.lock(); defer { self.unlock() }; return body()
    }
}
