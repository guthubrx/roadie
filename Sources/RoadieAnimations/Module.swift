import Foundation
import RoadieCore
import RoadieFXCore

/// SPEC-007 RoadieAnimations — engine d'animations 60-120 FPS Bézier-style.
/// Plafond LOC strict : 700 (cible 500). Composé de 6 fichiers Swift bornés.

public final class AnimationsModule: @unchecked Sendable {
    public static let shared = AnimationsModule()
    public var config = AnimationsConfig()
    public let queue = AnimationQueue(maxConcurrent: 20)
    public lazy var loop = AnimationLoop()
    public var router: EventRouter?
    private var loopTickID: UUID?

    public func subscribe(to bus: FXEventBus) {
        let r = EventRouter(config: config, queue: queue)
        self.router = r
        bus.subscribe(to: [.windowCreated, .windowDestroyed, .windowFocused,
                          .windowResized, .desktopChanged, .stageChanged,
                          .configReloaded]) { [weak self] event in
            self?.router?.handle(event: event)
        }
        startLoop()
    }

    public func shutdown() {
        if let id = loopTickID { loop.unregister(id) }
        loop.stop()
        Task { await queue.cancelAll() }
    }

    public func setConfig(_ cfg: AnimationsConfig) {
        self.config = cfg
        self.router = EventRouter(config: cfg, queue: queue)
    }

    private func startLoop() {
        let q = queue
        let id = loop.register { now in
            Task {
                let cmds = await q.tick(now: now)
                if !cmds.isEmpty {
                    _ = await AnimationsBridge.shared.batchSend(cmds)
                }
            }
        }
        loopTickID = id
        loop.start()
    }

    /// API publique appelable par les modules pairs (SPEC-006/008).
    public func requestAnimation(_ animation: Animation) async {
        await queue.enqueue(animation)
    }
}

/// Singleton bridge OSAX pour ce module.
public final class AnimationsBridge: @unchecked Sendable {
    public static let shared: OSAXBridge = OSAXBridge()
}

@_cdecl("module_init")
public func module_init() -> UnsafeMutableRawPointer {
    let vtable = UnsafeMutablePointer<FXModuleVTable>.allocate(capacity: 1)
    let nameStr = strdup("animations")!
    let versionStr = strdup("0.1.0")!
    vtable.initialize(to: FXModuleVTable(
        name: UnsafePointer(nameStr),
        version: UnsafePointer(versionStr),
        subscribe: { busPtr in
            AnimationsModule.shared.subscribe(to: FXEventBus.from(opaquePtr: busPtr))
        },
        shutdown: { AnimationsModule.shared.shutdown() }
    ))
    return UnsafeMutableRawPointer(vtable)
}
