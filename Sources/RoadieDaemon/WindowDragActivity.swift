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

    /// Fin d'un glisser avec la grâce de relâchement. `droppedWindowID` : fenêtre d'un dépôt reconnu
    /// (T216) ; sa preuve est écrite dans le fichier partagé, lue par `lastDrop()`.
    public func finish(now: Date = Date(), graceSeconds: TimeInterval = 0.9, droppedWindowID: WindowID? = nil) {
        guard enabled else { return }
        lock.lock()
        defer { lock.unlock() }
        activeWindowID = nil
        activeUntil = max(activeUntil, now.addingTimeInterval(graceSeconds), readLocked()?.expiry ?? .distantPast)
        writeActiveUntilLocked(activeUntil, windowID: nil, drop: droppedWindowID.map { ($0, now) })
    }

    /// Relâchement sans dépôt reconnu (T216) : le glisser cesse tout de suite, sans grâce. Le geste
    /// suit alors A17 (retour à l'arbre ou ajustement de frontière).
    public func release(now: Date = Date()) {
        guard enabled else { return }
        lock.lock()
        defer { lock.unlock() }
        activeWindowID = nil
        activeUntil = now
        writeActiveUntilLocked(now, windowID: nil)
    }

    /// Dernier dépôt reconnu, encore présent dans le fichier partagé (jusqu'à la fin de la grâce).
    /// Preuve, pour le maintien d'un autre processus, qu'une session de geste sur cette fenêtre,
    /// ouverte avant `at`, a été consommée par un dépôt (A17, T216). O(1).
    public func lastDrop() -> (windowID: WindowID, at: Date)? {
        guard enabled else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return readLocked()?.drop
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

    /// Fichier partagé : échéance, fenêtre glissée (vide hors glisser), puis le dépôt reconnu
    /// (« fenêtre instant ») s'il y en a un.
    private func writeActiveUntilLocked(_ expiry: Date, windowID: WindowID?, drop: (WindowID, Date)? = nil) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let window = windowID.map { String($0.rawValue) } ?? ""
        let dropLine = drop.map { "\($0.0.rawValue) \($0.1.timeIntervalSince1970)" } ?? ""
        let payload = "\(expiry.timeIntervalSince1970)\n\(window)\n\(dropLine)\n"
        try? payload.write(to: url, atomically: true, encoding: .utf8)
    }

    private func readLocked() -> (expiry: Date, dragging: Bool, drop: (windowID: WindowID, at: Date)?)? {
        guard let payload = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = payload.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first, let timestamp = TimeInterval(first) else { return nil }
        let dragging = lines.count > 1 && !lines[1].isEmpty
        let dropFields = lines.count > 2 ? lines[2].split(separator: " ") : []
        let drop = dropFields.count == 2
            ? UInt32(dropFields[0]).flatMap { id in
                TimeInterval(dropFields[1]).map { (WindowID(rawValue: id), Date(timeIntervalSince1970: $0)) }
            }
            : nil
        return (Date(timeIntervalSince1970: timestamp), dragging, drop)
    }
}
