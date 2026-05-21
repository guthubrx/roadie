import Foundation
import Darwin

public enum ComponentLockError: Error, Equatable {
    case alreadyRunning(pid: Int32)
    case ioFailure(path: String, underlying: String)
}

/// Verrou PID par composant pour permettre de lancer chaque sous-commande roadied
/// (rail, tiler, border, ...) en isolation tout en evitant les doublons.
///
/// Le fichier est ~/.roadies/<component>.pid (~/.roadies/spec011-test-XXXX.pid
/// pour les tests, isole par UUID pour ne pas perturber un daemon reel).
public struct ComponentLockFile: Sendable {
    public let component: String
    private let path: String

    public init(component: String) {
        self.component = component
        self.path = Self.pidFilePath(for: component)
    }

    public static func pidFilePath(for component: String) -> String {
        let baseDir = pidDirectory()
        return "\(baseDir)/\(component).pid"
    }

    private static func pidDirectory() -> String {
        if ProcessInfo.processInfo.processName.lowercased().contains("test") {
            return "\(NSTemporaryDirectory())roadie-test-locks-\(ProcessInfo.processInfo.processIdentifier)"
        }
        return NSString(string: "~/.roadies").expandingTildeInPath
    }

    /// Acquiert le verrou. Throw `alreadyRunning(pid:)` si un autre process vivant
    /// detient deja le lock. Ecrase un PID stale automatiquement.
    public func acquire() throws {
        let manager = FileManager.default
        let directory = (path as NSString).deletingLastPathComponent
        do {
            try manager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        } catch {
            throw ComponentLockError.ioFailure(path: directory, underlying: "\(error)")
        }

        if let existingPid = Self.readPid(at: path), Self.isAlive(pid: existingPid) {
            throw ComponentLockError.alreadyRunning(pid: existingPid)
        }

        let myPid = ProcessInfo.processInfo.processIdentifier
        do {
            try "\(myPid)\n".write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            throw ComponentLockError.ioFailure(path: path, underlying: "\(error)")
        }
    }

    /// Libere le verrou. Idempotent — supprime le fichier s'il existe et contient
    /// le PID courant. Ne supprime pas un fichier qui appartient a un autre process
    /// (anti-corruption en cas d'appel apres acquire echoue).
    public func release() {
        guard let pid = Self.readPid(at: path) else { return }
        guard pid == ProcessInfo.processInfo.processIdentifier else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Inventaire des verrous actifs. Filtre les PID staling.
    public static func registry() -> [(component: String, pid: Int32, startedAt: Date)] {
        let directory = pidDirectory()
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(atPath: directory) else {
            return []
        }
        var result: [(component: String, pid: Int32, startedAt: Date)] = []
        for entry in entries where entry.hasSuffix(".pid") {
            let component = String(entry.dropLast(4))
            let fullPath = "\(directory)/\(entry)"
            guard let pid = readPid(at: fullPath), isAlive(pid: pid) else { continue }
            let attrs = try? manager.attributesOfItem(atPath: fullPath)
            let startedAt = (attrs?[.modificationDate] as? Date) ?? Date()
            result.append((component: component, pid: pid, startedAt: startedAt))
        }
        return result.sorted { $0.component < $1.component }
    }

    private static func readPid(at path: String) -> Int32? {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int32(trimmed)
    }

    private static func isAlive(pid: Int32) -> Bool {
        // kill(pid, 0) renvoie 0 si le process existe (et qu'on a la permission de
        // signaler). EPERM aussi indique un process vivant. ESRCH = stale.
        let result = kill(pid, 0)
        if result == 0 { return true }
        return errno != ESRCH
    }
}
