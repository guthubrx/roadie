import Foundation
import CoreGraphics
import RoadieCore
import RoadieFXCore

/// SPEC-009 RoadieBlur — frosted glass per-app + global. Plafond LOC 150 (cible 100).

public struct BlurRule: Codable, Sendable, Equatable {
    public let bundleID: String
    public let radius: Int

    enum CodingKeys: String, CodingKey {
        case bundleID = "bundle_id"
        case radius
    }
}

public struct BlurConfig: Codable, Sendable {
    public var enabled: Bool = false
    public var defaultRadius: Int = 0
    public var rules: [BlurRule] = []

    public init() {}

    enum CodingKeys: String, CodingKey {
        case enabled
        case defaultRadius = "default_radius"
        case rules
    }
}

/// Logique pure : retourne le radius cible pour un bundleID donné, clampé [0, 100].
/// Match rule explicite > defaultRadius.
public func radius(for bundleID: String, config: BlurConfig) -> Int {
    let r = config.rules.first { $0.bundleID == bundleID }?.radius ?? config.defaultRadius
    return max(0, min(100, r))
}

public final class BlurModule: @unchecked Sendable {
    public static let shared = BlurModule()
    public var config = BlurConfig()
    private var trackedWindows: Set<CGWindowID> = []
    private let lock = NSLock()

    public func subscribe(to bus: FXEventBus) {
        bus.subscribe(to: [.windowCreated, .desktopChanged, .configReloaded]) { [weak self] event in
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
                _ = await BlurBridge.shared.send(.setBlur(wid: wid, radius: 0))
            }
        }
    }

    private func handle(event: FXEvent) {
        guard config.enabled else { return }
        guard let wid = event.wid else { return }
        let bundleID = event.bundleID ?? ""
        let target = radius(for: bundleID, config: config)
        guard target > 0 else { return }
        lock.lock(); trackedWindows.insert(wid); lock.unlock()
        Task { _ = await BlurBridge.shared.send(.setBlur(wid: wid, radius: target)) }
    }
}

public final class BlurBridge: @unchecked Sendable {
    public static let shared: OSAXBridge = OSAXBridge()
}

@_cdecl("roadie_fx_init_blur")
public func roadie_fx_init_blur() -> UnsafeMutableRawPointer {
    let vtable = UnsafeMutablePointer<FXModuleVTable>.allocate(capacity: 1)
    let nameStr = strdup("blur")!
    let versionStr = strdup("0.1.0")!
    vtable.initialize(to: FXModuleVTable(
        name: UnsafePointer(nameStr),
        version: UnsafePointer(versionStr),
        subscribe: { busPtr in
            BlurModule.shared.subscribe(to: FXEventBus.from(opaquePtr: busPtr))
        },
        shutdown: { BlurModule.shared.shutdown() }
    ))
    return UnsafeMutableRawPointer(vtable)
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        self.lock(); defer { self.unlock() }; return body()
    }
}
