import Foundation
import RoadieCore

public final class WindowDragActivity: @unchecked Sendable {
    public static let shared = WindowDragActivity(enabled: !WindowDragActivity.isRunningTests)

    private let lock = NSLock()
    private let url: URL
    private let enabled: Bool
    private var activeWindowID: WindowID?
    private var activeUntil: Date = .distantPast

    public init(path: String = "~/.local/state/roadies/window-drag-activity", enabled: Bool = true) {
        self.url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        self.enabled = enabled
    }

    public func markActive(windowID: WindowID, now: Date = Date(), holdSeconds: TimeInterval = 1.5) {
        guard enabled else { return }
        lock.lock()
        defer { lock.unlock() }
        activeWindowID = windowID
        activeUntil = max(activeUntil, now.addingTimeInterval(holdSeconds), readExpiryLocked() ?? .distantPast)
        writeActiveUntilLocked(activeUntil, windowID: windowID)
    }

    public func finish(now: Date = Date(), graceSeconds: TimeInterval = 0.9) {
        guard enabled else { return }
        lock.lock()
        defer { lock.unlock() }
        activeWindowID = nil
        activeUntil = max(activeUntil, now.addingTimeInterval(graceSeconds), readExpiryLocked() ?? .distantPast)
        writeActiveUntilLocked(activeUntil, windowID: nil)
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        activeWindowID = nil
        activeUntil = .distantPast
        try? FileManager.default.removeItem(at: url)
    }

    public func isActive(now: Date = Date()) -> Bool {
        guard enabled else { return false }
        lock.lock()
        defer { lock.unlock() }
        activeUntil = max(activeUntil, readExpiryLocked() ?? .distantPast)
        if now <= activeUntil {
            return true
        }
        activeWindowID = nil
        activeUntil = .distantPast
        try? FileManager.default.removeItem(at: url)
        return false
    }

    private func writeActiveUntilLocked(_ expiry: Date, windowID: WindowID?) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let window = windowID.map { String($0.rawValue) } ?? ""
        let payload = "\(expiry.timeIntervalSince1970)\n\(window)\n"
        try? payload.write(to: url, atomically: true, encoding: .utf8)
    }

    private func readExpiryLocked() -> Date? {
        guard let payload = try? String(contentsOf: url, encoding: .utf8),
              let firstLine = payload.split(separator: "\n", maxSplits: 1).first,
              let timestamp = TimeInterval(firstLine)
        else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.processName.contains("xctest")
            || ProcessInfo.processInfo.processName.contains("PackageTests")
            || Bundle.main.bundlePath.contains(".xctest")
            || CommandLine.arguments.contains { $0.contains(".xctest") || $0.contains("PackageTests") }
    }
}
