import Foundation

/// Fenêtre d'activité des commandes de disposition, partagée entre processus via un fichier.
/// Les écritures (lecture du délai courant puis prolongation) se font sous `FileLock` exclusif :
/// le verrou protège à la fois les threads du processus (un descripteur par prise) et les autres
/// processus. Les lectures restent sans verrou (écriture atomique par rename).
/// Aucun état mutable en mémoire : la classe est `Sendable` sans `@unchecked`.
public final class LayoutCommandActivity: Sendable {
    public static let shared = LayoutCommandActivity(enabled: !LayoutCommandActivity.isRunningTests)

    private let url: URL
    private let enabled: Bool

    public init(path: String = "~/.local/state/roadies/layout-command-activity", enabled: Bool = true) {
        self.url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        self.enabled = enabled
    }

    public func markActive(reason: String, now: Date = Date(), holdSeconds: TimeInterval = 2.0) {
        guard enabled else { return }
        extendActiveUntil(now.addingTimeInterval(holdSeconds), reason: reason)
    }

    public func finish(reason: String = "finished", now: Date = Date(), graceSeconds: TimeInterval = 1.2) {
        guard enabled else { return }
        extendActiveUntil(now.addingTimeInterval(graceSeconds), reason: reason)
    }

    public func reset() {
        withFileLock { try? FileManager.default.removeItem(at: url) }
    }

    public func isActive(now: Date = Date()) -> Bool {
        guard enabled else { return false }
        return activeUntil(now: now) != nil
    }

    /// Lecture seule : un délai expiré est simplement ignoré. Le fichier n'est plus supprimé ici,
    /// car une suppression sans verrou pouvait effacer une prolongation écrite entre-temps.
    public func activeUntil(now: Date = Date()) -> Date? {
        guard enabled, let expiry = readExpiry(), now <= expiry else { return nil }
        return expiry
    }

    /// Prolonge le délai (jamais de raccourcissement) en une transaction exclusive.
    private func extendActiveUntil(_ candidate: Date, reason: String) {
        withFileLock {
            let expiry = max(readExpiry() ?? .distantPast, candidate)
            let sanitizedReason = reason.replacingOccurrences(of: "\n", with: " ")
            let payload = "\(expiry.timeIntervalSince1970)\n\(sanitizedReason)\n"
            try? payload.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func withFileLock(_ body: () -> Void) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileLock.withLock(path: FileLock.lockPath(for: url), mode: .exclusive, block: body)
        } catch {
            fputs("roadie: layout command activity not updated: \(error)\n", stderr)
        }
    }

    private func readExpiry() -> Date? {
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
