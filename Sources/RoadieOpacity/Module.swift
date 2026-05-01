import Foundation
import CoreGraphics
import RoadieCore
import RoadieFXCore

/// SPEC-006 RoadieOpacity — focus dimming + per-app baseline + stage hide via α.
/// Plafond LOC strict : 220 (cible 150).
/// La logique pure (`targetAlpha`, `RuleMatcher`) est dans DimEngine.swift / Config.swift,
/// testée unitairement. Ce fichier orchestre les events FXEventBus et les envois OSAX.

public final class OpacityModule: @unchecked Sendable {
    public static let shared = OpacityModule()
    public var config = OpacityConfig()
    private var matcher = RuleMatcher([])
    private var trackedWindows: Set<CGWindowID> = []
    private let lock = NSLock()

    public func subscribe(to bus: FXEventBus) {
        bus.subscribe(to: [.windowCreated, .windowFocused,
                          .stageChanged, .desktopChanged,
                          .configReloaded]) { [weak self] event in
            self?.handle(event: event)
        }
    }

    public func shutdown() {
        let wids: [CGWindowID] = lock.withLock {
            let snap = Array(trackedWindows)
            trackedWindows.removeAll()
            return snap
        }
        Task {
            for wid in wids {
                _ = await OpacityBridge.shared.send(.setAlpha(wid: wid, alpha: 1.0))
            }
        }
    }

    public func setConfig(_ cfg: OpacityConfig) {
        lock.lock()
        config = cfg
        matcher = RuleMatcher(cfg.rules)
        lock.unlock()
    }

    private func handle(event: FXEvent) {
        guard config.enabled else { return }
        guard let wid = event.wid else { return }
        let focused = (event.kind == .windowFocused)
        let bundleID = event.bundleID ?? ""
        let perAppRule = matcher.alpha(for: bundleID)
        let target = targetAlpha(focused: focused,
                                 baseline: config.inactiveDim,
                                 perAppRule: perAppRule)
        lock.lock(); trackedWindows.insert(wid); lock.unlock()
        Task {
            _ = await OpacityBridge.shared.send(.setAlpha(wid: wid, alpha: target))
        }
    }
}

/// Singleton bridge OSAX partagé, isolé par module pour permettre les tests.
public final class OpacityBridge: @unchecked Sendable {
    public static let shared: OSAXBridge = OSAXBridge()
}

@_cdecl("roadie_fx_init_opacity")
public func roadie_fx_init_opacity() -> UnsafeMutableRawPointer {
    let vtable = UnsafeMutablePointer<FXModuleVTable>.allocate(capacity: 1)
    let nameStr = strdup("opacity")!
    let versionStr = strdup("0.1.0")!
    vtable.initialize(to: FXModuleVTable(
        name: UnsafePointer(nameStr),
        version: UnsafePointer(versionStr),
        subscribe: { busPtr in
            OpacityModule.shared.subscribe(to: FXEventBus.from(opaquePtr: busPtr))
        },
        shutdown: { OpacityModule.shared.shutdown() }
    ))
    return UnsafeMutableRawPointer(vtable)
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        self.lock(); defer { self.unlock() }; return body()
    }
}
