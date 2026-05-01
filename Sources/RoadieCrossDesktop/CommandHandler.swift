import Foundation
import CoreGraphics
import RoadieFXCore

/// Codes d'exit pour les commandes CLI `roadie window space|stick|pin`.
public enum CommandExitCode: Int32 {
    case ok = 0
    case invalidArgument = 2
    case daemonNotJoinable = 3
    case moduleNotLoaded = 4
    case desktopNotFound = 5
}

/// Tracker pour restauration au shutdown : niveau original + état sticky.
public struct WindowStateBackup: Sendable {
    public let originalLevel: Int
    public let wasSticky: Bool
}

public final class LevelTracker: @unchecked Sendable {
    private var original: [CGWindowID: WindowStateBackup] = [:]
    private let lock = NSLock()

    public func track(wid: CGWindowID, backup: WindowStateBackup) {
        lock.lock(); original[wid] = backup; lock.unlock()
    }

    public func restoreAll() -> [(CGWindowID, WindowStateBackup)] {
        lock.lock(); defer { lock.unlock() }
        let snap = Array(original)
        original.removeAll()
        return snap
    }
}

/// Handlers pour les sous-commandes CLI. Délègue à OSAXBridge.
public final class CommandHandler: @unchecked Sendable {
    private let bridge: OSAXBridge
    private let pinEngine: PinEngine
    public let tracker = LevelTracker()

    public init(bridge: OSAXBridge, pinEngine: PinEngine) {
        self.bridge = bridge
        self.pinEngine = pinEngine
    }

    /// `roadie window space <selector>` : déplace la fenêtre frontmost vers
    /// le desktop indiqué par selector (label ou index).
    public func handleSpace(selector: String,
                            frontmostWID: CGWindowID,
                            labelResolver: (String) -> String?,
                            indexResolver: (Int) -> String?) async -> CommandExitCode {
        let target: String?
        if let idx = Int(selector) {
            target = indexResolver(idx)
        } else {
            target = labelResolver(selector)
        }
        guard let uuid = target else { return .desktopNotFound }
        let result = await bridge.send(.moveWindowToSpace(wid: frontmostWID, spaceUUID: uuid))
        return result.isOK ? .ok : .desktopNotFound
    }

    /// `roadie window stick [bool]` : pose ou retire le sticky flag.
    public func handleSticky(wid: CGWindowID, sticky: Bool,
                             previousSticky: Bool = false) async -> CommandExitCode {
        tracker.track(wid: wid, backup: WindowStateBackup(originalLevel: 0, wasSticky: previousSticky))
        let result = await bridge.send(.setSticky(wid: wid, sticky: sticky))
        return result.isOK ? .ok : .invalidArgument
    }

    /// `roadie window pin|unpin` : level floating (24) ou normal (0).
    public func handlePin(wid: CGWindowID, pinned: Bool, previousLevel: Int = 0) async -> CommandExitCode {
        tracker.track(wid: wid, backup: WindowStateBackup(originalLevel: previousLevel, wasSticky: false))
        let level = pinned ? 24 : 0
        let result = await bridge.send(.setLevel(wid: wid, level: level))
        return result.isOK ? .ok : .invalidArgument
    }

    /// Pinning auto sur window_created si rule match.
    public func handleWindowCreated(wid: CGWindowID, bundleID: String) async {
        guard let target = pinEngine.target(forBundleID: bundleID) else { return }
        _ = await bridge.send(.moveWindowToSpace(wid: wid, spaceUUID: target))
    }
}
