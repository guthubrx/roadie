import Foundation

public final class LayoutCommandActivity: @unchecked Sendable {
    public static let shared = LayoutCommandActivity(enabled: !LayoutCommandActivity.isRunningTests)

    private let lock = NSLock()
    private let url: URL
    private let enabled: Bool

    public init(path: String = "~/.local/state/roadies/layout-command-activity", enabled: Bool = true) {
        self.url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        self.enabled = enabled
    }

    public func markActive(reason: String, now: Date = Date(), holdSeconds: TimeInterval = 2.0) {
        guard enabled else { return }
        writeActiveUntil(max(currentExpiry(), now.addingTimeInterval(holdSeconds)), reason: reason)
    }

    public func finish(reason: String = "finished", now: Date = Date(), graceSeconds: TimeInterval = 1.2) {
        guard enabled else { return }
        writeActiveUntil(max(currentExpiry(), now.addingTimeInterval(graceSeconds)), reason: reason)
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: url)
    }

    public func isActive(now: Date = Date()) -> Bool {
        guard enabled else { return false }
        return activeUntil(now: now) != nil
    }

    public func activeUntil(now: Date = Date()) -> Date? {
        guard enabled else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let expiry = readExpiryLocked() else { return nil }
        if now <= expiry {
            return expiry
        }
        try? FileManager.default.removeItem(at: url)
        return nil
    }

    private func currentExpiry() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return readExpiryLocked() ?? .distantPast
    }

    private func writeActiveUntil(_ expiry: Date, reason: String) {
        lock.lock()
        defer { lock.unlock() }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sanitizedReason = reason.replacingOccurrences(of: "\n", with: " ")
        let payload = "\(expiry.timeIntervalSince1970)\n\(sanitizedReason)\n"
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
