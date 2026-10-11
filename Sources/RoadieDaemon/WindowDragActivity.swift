import Foundation
import RoadieCore

public final class WindowDragActivity: @unchecked Sendable {
    public static let shared = WindowDragActivity(enabled: !TestEnvironment.isRunningTests)

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
        activeUntil = max(activeUntil, now.addingTimeInterval(holdSeconds), readLocked()?.expiry ?? .distantPast)
        writeActiveUntilLocked(activeUntil, windowID: windowID)
    }

    public func finish(now: Date = Date(), graceSeconds: TimeInterval = 0.9) {
        guard enabled else { return }
        lock.lock()
        defer { lock.unlock() }
        activeWindowID = nil
        activeUntil = max(activeUntil, now.addingTimeInterval(graceSeconds), readLocked()?.expiry ?? .distantPast)
        writeActiveUntilLocked(activeUntil, windowID: nil)
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        activeWindowID = nil
        activeUntil = .distantPast
        try? FileManager.default.removeItem(at: url)
    }

    /// Glisser en cours, ou grâce de fin de glisser encore due. `includingReleaseGrace: false`
    /// (modes à arbre, A11) : seul un glisser en cours compte ; le relâchement déclenche la passe.
    /// Le fichier partagé fait foi entre processus : sa seconde ligne porte la fenêtre glissée,
    /// vide après `finish`.
    public func isActive(now: Date = Date(), includingReleaseGrace: Bool = true) -> Bool {
        guard enabled else { return false }
        lock.lock()
        defer { lock.unlock() }
        let stored = readLocked()
        activeUntil = max(activeUntil, stored?.expiry ?? .distantPast)
        if now <= activeUntil {
            return includingReleaseGrace || (stored?.dragging ?? (activeWindowID != nil))
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

    private func readLocked() -> (expiry: Date, dragging: Bool)? {
        guard let payload = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = payload.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first, let timestamp = TimeInterval(first) else { return nil }
        let dragging = lines.count > 1 && !lines[1].isEmpty
        return (Date(timeIntervalSince1970: timestamp), dragging)
    }
}
