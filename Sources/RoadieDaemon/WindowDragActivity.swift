import Foundation
import RoadieCore

public final class WindowDragActivity: @unchecked Sendable {
    public static let shared = WindowDragActivity()

    private let lock = NSLock()
    private var activeWindowID: WindowID?
    private var activeUntil: Date = .distantPast

    public init() {}

    public func markActive(windowID: WindowID, now: Date = Date(), holdSeconds: TimeInterval = 1.5) {
        lock.lock()
        activeWindowID = windowID
        activeUntil = max(activeUntil, now.addingTimeInterval(holdSeconds))
        lock.unlock()
    }

    public func finish(now: Date = Date(), graceSeconds: TimeInterval = 0.9) {
        lock.lock()
        activeWindowID = nil
        activeUntil = max(activeUntil, now.addingTimeInterval(graceSeconds))
        lock.unlock()
    }

    public func reset() {
        lock.lock()
        activeWindowID = nil
        activeUntil = .distantPast
        lock.unlock()
    }

    public func isActive(now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if now <= activeUntil {
            return true
        }
        activeWindowID = nil
        activeUntil = .distantPast
        return false
    }
}
