import Foundation
import Darwin

/// Verrou inter-process base sur `flock(2)` POSIX. Resout les race conditions
/// observees en mode atomique SPEC-011 quand plusieurs process roadied
/// (tiler, rail, border, focus-mouse, etc.) lisent-modifient-ecrivent le meme
/// fichier d'etat (`~/.roadies/stages.json`, `intent.json`, etc.).
///
/// Le verrou est advisory : tous les acteurs DOIVENT utiliser FileLock pour que
/// la synchronisation fonctionne. Un process qui write sans lock pourrait
/// toujours corrompre l'etat (mais Roadie centralise tous ses writes via
/// `JSONPersistence`).
///
/// Le fichier de lock est distinct du fichier de donnees (suffixe `.lock`) pour
/// pouvoir le supprimer/recreer sans toucher aux donnees, et pour que le file
/// descriptor du lock soit independant du file descriptor du fichier reel.
public final class FileLock {
    public enum Mode: Sendable {
        case shared      // flock LOCK_SH — plusieurs lecteurs concurrents
        case exclusive   // flock LOCK_EX — un seul writer
    }

    public enum LockError: Error, CustomStringConvertible {
        case openFailed(path: String, errno: Int32)
        case lockFailed(path: String, errno: Int32)

        public var description: String {
            switch self {
            case .openFailed(let path, let err):
                return "FileLock open(\(path)) failed: errno=\(err) (\(String(cString: strerror(err))))"
            case .lockFailed(let path, let err):
                return "FileLock flock(\(path)) failed: errno=\(err) (\(String(cString: strerror(err))))"
            }
        }
    }

    private let path: String
    private var fileDescriptor: Int32 = -1

    public init(path: String) {
        self.path = path
    }

    /// Resout le chemin du fichier de lock associe a un fichier de donnees.
    /// `~/.roadies/stages.json` -> `~/.roadies/stages.json.lock`
    public static func lockPath(for dataURL: URL) -> String {
        "\(dataURL.path).lock"
    }

    /// Acquire le verrou, bloquant jusqu'a obtention.
    public func acquire(mode: Mode = .exclusive) throws {
        let directory = (path as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: directory) {
            try? FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true
            )
        }
        let fd = open(path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else {
            throw LockError.openFailed(path: path, errno: errno)
        }
        let op: Int32 = (mode == .exclusive) ? LOCK_EX : LOCK_SH
        if flock(fd, op) != 0 {
            let err = errno
            close(fd)
            throw LockError.lockFailed(path: path, errno: err)
        }
        fileDescriptor = fd
    }

    /// Release le verrou et ferme le file descriptor.
    public func release() {
        guard fileDescriptor >= 0 else { return }
        _ = flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
        fileDescriptor = -1
    }

    deinit {
        release()
    }

    /// Helper qui acquire, execute le bloc, et release meme en cas de throw.
    public static func withLock<T>(
        path: String,
        mode: Mode = .exclusive,
        block: () throws -> T
    ) throws -> T {
        let lock = FileLock(path: path)
        try lock.acquire(mode: mode)
        defer { lock.release() }
        return try block()
    }
}
