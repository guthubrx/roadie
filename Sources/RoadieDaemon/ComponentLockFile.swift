import Foundation
import Darwin

public enum ComponentLockError: Error, Equatable {
    case alreadyRunning(pid: Int32)
    case ioFailure(path: String, underlying: String)
    /// Une commande `roadie` exécutée en local tient encore la réservation au-delà du délai.
    case localExecutionBusy(path: String)
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
/// Exclusion avec le repli local de la CLI (REL-015) : avec `guardsLocalExecution`, le detenteur
/// prend aussi `<component>.local.lock` en exclusif et le garde toute sa vie. La CLI le prend en
/// partage (`LOCK_SH|LOCK_NB`) avant ses sondes et le garde pendant toute l'execution locale.
/// Ce second fichier evite le piege d'un `LOCK_SH` sur le verrou d'instance, qui ferait echouer un
/// demarrage concurrent (« already running »). Ordre au demarrage : verrou d'instance (non
/// bloquant), puis attente bornee de la reservation locale, puis seulement le fichier pid.
/// Pas d'interblocage : la CLI ne prend jamais le verrou d'instance et n'attend jamais la
/// reservation (echec immediat = daemon present) ; le daemon n'attend qu'un temps borne.
///
/// En test (nom de process contenant "test"), le repertoire est isole dans NSTemporaryDirectory.
///
/// `@unchecked Sendable` : l'etat mutable, `fileDescriptor` et `localExecutionDescriptor`, n'est
/// lu et modifie que sous `stateLock` (acquire, release, deinit).
public final class ComponentLockFile: @unchecked Sendable {
    public let component: String
    private let path: String
    private let lockPath: String
    private let stateLock = NSLock()
    private var fileDescriptor: Int32 = -1
    private let guardsLocalExecution: Bool
    private var localExecutionDescriptor: Int32 = -1

    /// Delai maximal d'attente de la fin des executions locales en cours au demarrage.
    public static let defaultLocalExecutionTimeout: TimeInterval = 10

    public init(component: String, guardsLocalExecution: Bool = false) {
        self.component = component
        self.guardsLocalExecution = guardsLocalExecution
        self.path = Self.pidFilePath(for: component)
        self.lockPath = "\(Self.pidDirectory())/\(component).lock"
    }

    /// Fichier de reservation des executions locales associe au verrou d'instance `lockPath`
    /// (`roadied.lock` -> `roadied.local.lock`). Nom partage par le daemon et la CLI.
    public static func localExecutionLockPath(forLockPath lockPath: String) -> String {
        (lockPath as NSString).deletingPathExtension + ".local.lock"
    }

    public static func pidFilePath(for component: String) -> String {
        let baseDir = pidDirectory()
        return "\(baseDir)/\(component).pid"
    }

    private static func pidDirectory() -> String {
        if TestEnvironment.isRunningTests {
            return "\(NSTemporaryDirectory())roadie-test-locks-\(ProcessInfo.processInfo.processIdentifier)"
        }
        return NSString(string: "~/.roadies").expandingTildeInPath
    }

    /// Acquiert le verrou. Throw `alreadyRunning(pid:)` si un autre detenteur le tient deja
    /// (y compris un autre descripteur du meme process). Idempotent pour ce detenteur.
    public func acquire(localExecutionTimeout: TimeInterval = defaultLocalExecutionTimeout) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
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

        if guardsLocalExecution {
            do {
                localExecutionDescriptor = try Self.waitExclusive(
                    path: Self.localExecutionLockPath(forLockPath: lockPath),
                    timeout: localExecutionTimeout
                )
            } catch {
                releaseLocked()
                throw error
            }
        }

        let myPid = ProcessInfo.processInfo.processIdentifier
        do {
            try "\(myPid)\n".write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            releaseLocked()
            throw ComponentLockError.ioFailure(path: path, underlying: "\(error)")
        }
    }

    /// Libere le verrou. Idempotent. Supprime le fichier PID seulement s'il contient le PID
    /// courant. Le fichier .lock reste en place : le supprimer ouvrirait une course avec un
    /// process qui l'a deja ouvert.
    public func release() {
        stateLock.withLock { releaseLocked() }
    }

    /// Corps de `release`, `stateLock` deja tenu (NSLock non reentrant).
    private func releaseLocked() {
        guard fileDescriptor >= 0 else { return }
        if Self.readPid(at: path) == ProcessInfo.processInfo.processIdentifier {
            try? FileManager.default.removeItem(atPath: path)
        }
        if localExecutionDescriptor >= 0 {
            _ = flock(localExecutionDescriptor, LOCK_UN)
            close(localExecutionDescriptor)
            localExecutionDescriptor = -1
        }
        _ = flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
        fileDescriptor = -1
    }

    /// Prend `path` en exclusif en attendant au plus `timeout` la fin des detenteurs partages.
    /// Sondage `LOCK_NB` toutes les 20 ms plutot qu'un `flock` bloquant : le delai reste borne.
    private static func waitExclusive(path: String, timeout: TimeInterval) throws -> Int32 {
        let fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else {
            throw ComponentLockError.ioFailure(path: path, underlying: String(cString: strerror(errno)))
        }
        let deadline = Date().addingTimeInterval(timeout)
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let err = errno
            guard err == EWOULDBLOCK, Date() < deadline else {
                close(fd)
                if err == EWOULDBLOCK { throw ComponentLockError.localExecutionBusy(path: path) }
                throw ComponentLockError.ioFailure(path: path, underlying: String(cString: strerror(err)))
            }
            usleep(20_000)
        }
        return fd
    }

    deinit {
        release()
    }

    /// Inventaire des verrous actifs. Filtre les PID staling.
    /// La vivacite est testee par `ProcessLiveness.isAlive` et non par une sonde `flock` : une sonde
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
            guard let pid = readPid(at: fullPath), ProcessLiveness.isAlive(pid) else { continue }
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
}
