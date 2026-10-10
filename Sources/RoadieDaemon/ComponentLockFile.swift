import Foundation
import Darwin

public enum ComponentLockError: Error, Equatable {
    case alreadyRunning(pid: Int32)
    case ioFailure(path: String, underlying: String)
}

/// Verrou d'instance par composant (SPEC-016 R9). Le verrou est un `flock(LOCK_EX|LOCK_NB)`
/// sur ~/.roadies/<component>.lock, tenu par le descripteur ouvert pendant toute la vie du
/// process : le noyau le libere aussi en cas de crash, sans PID stale ni fenetre de course
/// entre test et ecriture. Le fichier ~/.roadies/<component>.pid n'est qu'informatif
/// (diagnostic, `registry()`).
///
/// `FileLock` n'est pas reutilise : son `acquire` est bloquant, alors qu'un second demarrage
/// doit echouer tout de suite.
///
/// En test (nom de process contenant "test"), le repertoire est isole dans NSTemporaryDirectory.
public final class ComponentLockFile: @unchecked Sendable {
    public let component: String
    private let path: String
    private let lockPath: String
    private var fileDescriptor: Int32 = -1

    public init(component: String) {
        self.component = component
        self.path = Self.pidFilePath(for: component)
        self.lockPath = "\(Self.pidDirectory())/\(component).lock"
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

    /// Acquiert le verrou. Throw `alreadyRunning(pid:)` si un autre detenteur le tient deja
    /// (y compris un autre descripteur du meme process). Idempotent pour ce detenteur.
    public func acquire() throws {
        guard fileDescriptor < 0 else { return }
        let directory = (path as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        } catch {
            throw ComponentLockError.ioFailure(path: directory, underlying: "\(error)")
        }

        // O_CLOEXEC : un process enfant (restore-watch) ne doit pas heriter du verrou.
        let fd = open(lockPath, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else {
            throw ComponentLockError.ioFailure(path: lockPath, underlying: String(cString: strerror(errno)))
        }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let err = errno
            close(fd)
            if err == EWOULDBLOCK {
                throw ComponentLockError.alreadyRunning(pid: Self.readPid(at: path) ?? 0)
            }
            throw ComponentLockError.ioFailure(path: lockPath, underlying: String(cString: strerror(err)))
        }
        fileDescriptor = fd

        let myPid = ProcessInfo.processInfo.processIdentifier
        do {
            try "\(myPid)\n".write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            release()
            throw ComponentLockError.ioFailure(path: path, underlying: "\(error)")
        }
    }

    /// Libere le verrou. Idempotent. Supprime le fichier PID seulement s'il contient le PID
    /// courant. Le fichier .lock reste en place : le supprimer ouvrirait une course avec un
    /// process qui l'a deja ouvert.
    public func release() {
        guard fileDescriptor >= 0 else { return }
        if Self.readPid(at: path) == ProcessInfo.processInfo.processIdentifier {
            try? FileManager.default.removeItem(atPath: path)
        }
        _ = flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
        fileDescriptor = -1
    }

    deinit {
        release()
    }

    /// Inventaire des verrous actifs. Filtre les PID staling.
    /// La vivacite est testee par `kill(pid, 0)` et non par une sonde `flock` : une sonde
    /// pourrait faire echouer un demarrage concurrent.
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
