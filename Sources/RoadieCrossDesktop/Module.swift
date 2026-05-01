import Foundation
import CoreGraphics
import RoadieCore
import RoadieFXCore

/// SPEC-010 RoadieCrossDesktop — manipulation programmatique cross-desktop.
/// Plafond LOC strict 450 (cible 300). Force-tiling P3 reportable.

public final class CrossDesktopModule: @unchecked Sendable {
    public static let shared = CrossDesktopModule()
    public var config = CrossDesktopConfig()
    public lazy var handler: CommandHandler = makeHandler()
    private let lock = NSLock()

    public func subscribe(to bus: FXEventBus) {
        bus.subscribe(to: [.windowCreated, .configReloaded]) { [weak self] event in
            self?.handle(event: event)
        }
    }

    public func shutdown() {
        // Restaure les niveaux + sticky des wid trackés.
        let backups = handler.tracker.restoreAll()
        Task {
            for (wid, backup) in backups {
                _ = await CrossDesktopBridge.shared.send(.setLevel(wid: wid, level: backup.originalLevel))
                if backup.wasSticky == false {
                    _ = await CrossDesktopBridge.shared.send(.setSticky(wid: wid, sticky: false))
                }
            }
        }
    }

    public func setConfig(_ cfg: CrossDesktopConfig) {
        lock.lock(); config = cfg; lock.unlock()
        // Recompute handler avec nouvelles rules
        let _ = makeHandler()
    }

    private func handle(event: FXEvent) {
        guard config.enabled else { return }
        guard event.kind == .windowCreated else { return }
        guard let wid = event.wid, let bundleID = event.bundleID else { return }
        Task { await handler.handleWindowCreated(wid: wid, bundleID: bundleID) }
    }

    private func makeHandler() -> CommandHandler {
        let engine = PinEngine(rules: config.pinRules,
                               labelResolver: { _ in nil },   // À câbler post-merge SPEC-003 API
                               indexResolver: { _ in nil })
        return CommandHandler(bridge: CrossDesktopBridge.shared, pinEngine: engine)
    }
}

public final class CrossDesktopBridge: @unchecked Sendable {
    public static let shared: OSAXBridge = OSAXBridge()
}

@_cdecl("module_init")
public func module_init() -> UnsafeMutableRawPointer {
    let vtable = UnsafeMutablePointer<FXModuleVTable>.allocate(capacity: 1)
    let nameStr = strdup("crossdesktop")!
    let versionStr = strdup("0.1.0")!
    vtable.initialize(to: FXModuleVTable(
        name: UnsafePointer(nameStr),
        version: UnsafePointer(versionStr),
        subscribe: { busPtr in
            CrossDesktopModule.shared.subscribe(to: FXEventBus.from(opaquePtr: busPtr))
        },
        shutdown: { CrossDesktopModule.shared.shutdown() }
    ))
    return UnsafeMutableRawPointer(vtable)
}
