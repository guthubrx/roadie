import Foundation
import Darwin
import Testing
import RoadieCore
@testable import RoadieDaemon

/// Session 022, round 2, lot C : exclusion entre le repli local de la CLI et le démarrage du
/// daemon (R1-03, REL-015) ; rupture signalée et lecture par descripteur lors de la rotation du
/// journal d'événements (R1-11, REL-018). Aucun test ne touche à `~/.roadies`.
@Suite(.serialized)
struct Audit022R2LotCTests {
    // MARK: - Aides

    /// Valeur partagée entre fils, protégée par un verrou.
    private final class Box<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: T
        init(_ value: T) { stored = value }
        var value: T {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }

    private func uniqueComponent() -> String {
        "r2c-\(UUID().uuidString.prefix(8))"
    }

    /// Chemin du verrou d'instance de `component` dans le répertoire de test de `ComponentLockFile`.
    private func lockPath(for component: String) -> String {
        (ComponentLockFile.pidFilePath(for: component) as NSString).deletingPathExtension + ".lock"
    }

    /// Socket inexistant : la sonde de connexion échoue.
    private func missingSocketPath() -> String {
        "/tmp/roadie-r2c-\(UUID().uuidString.prefix(8)).sock"
    }

    // MARK: - R1-03 (REL-015) : exclusion repli local / démarrage du daemon

    /// Un daemon qui démarre pendant une exécution locale attend sa fin avant de se déclarer
    /// (pid) : les deux ne tournent jamais en même temps.
    @Test
    func daemonStartWaitsForRunningLocalExecution() throws {
        let component = uniqueComponent()
        let lockPath = lockPath(for: component)
        let pidPath = ComponentLockFile.pidFilePath(for: component)
        let daemonLock = ComponentLockFile(component: component, guardsLocalExecution: true)
        defer { daemonLock.release() }
        let acquiredAt = Box<Date?>(nil)
        let localEndedAt = Box<Date?>(nil)
        let pidSeenDuringLocal = Box(false)

        let response = CommandSocketClient.execute(argv: ["focus", "left"], cwd: nil, socketPath: missingSocketPath(), lockPath: lockPath) {
            Thread.detachNewThread {
                try? daemonLock.acquire()
                acquiredAt.value = Date()
            }
            // Le daemon a le temps de prendre son verrou d'instance et d'attendre.
            Thread.sleep(forTimeInterval: 0.4)
            pidSeenDuringLocal.value = FileManager.default.fileExists(atPath: pidPath)
            localEndedAt.value = Date()
            return CLIResponse(exitCode: 0, stdout: "local\n")
        }

        #expect(response.stdout == "local\n")
        let deadline = Date().addingTimeInterval(5)
        while acquiredAt.value == nil, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        let acquired = try #require(acquiredAt.value)
        let ended = try #require(localEndedAt.value)
        #expect(acquired >= ended)
        #expect(!pidSeenDuringLocal.value)
        #expect(FileManager.default.fileExists(atPath: pidPath))
    }

    /// Daemon qui tient ses verrous sans pid ni socket (fenêtre de démarrage, pid supprimé) :
    /// aucun repli local, erreur explicite.
    @Test
    func daemonHoldingLocksWithoutPidOrSocketBlocksLocalFallback() throws {
        let component = uniqueComponent()
        let daemonLock = ComponentLockFile(component: component, guardsLocalExecution: true)
        try daemonLock.acquire()
        defer { daemonLock.release() }
        try FileManager.default.removeItem(atPath: ComponentLockFile.pidFilePath(for: component))
        let runs = Box(0)

        let response = CommandSocketClient.execute(argv: ["focus", "left"], cwd: nil, socketPath: missingSocketPath(), lockPath: lockPath(for: component)) {
            runs.value += 1
            return CLIResponse(exitCode: 0, stdout: "local\n")
        }

        #expect(runs.value == 0)
        #expect(response.exitCode == 69)
    }

    /// Exécution locale qui dépasse le délai : le démarrage échoue proprement, sans pid ni verrou
    /// d'instance conservé ; il réussit une fois l'exécution locale terminée.
    @Test
    func daemonStartFailsAfterTimeoutAndReleasesInstanceLock() throws {
        let component = uniqueComponent()
        let localLockPath = ComponentLockFile.localExecutionLockPath(forLockPath: lockPath(for: component))
        try FileManager.default.createDirectory(
            atPath: (localLockPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        let fd = open(localLockPath, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        #expect(fd >= 0)
        #expect(flock(fd, LOCK_SH) == 0)

        let daemonLock = ComponentLockFile(component: component, guardsLocalExecution: true)
        #expect(throws: ComponentLockError.localExecutionBusy(path: localLockPath)) {
            try daemonLock.acquire(localExecutionTimeout: 0.2)
        }
        #expect(!FileManager.default.fileExists(atPath: ComponentLockFile.pidFilePath(for: component)))

        close(fd)
        let next = ComponentLockFile(component: component, guardsLocalExecution: true)
        try next.acquire(localExecutionTimeout: 0.2)
        next.release()
    }

    /// Commande non routée vers le daemon : exécution locale directe, même daemon présent.
    @Test
    func nonRoutedCommandRunsLocallyEvenWhenDaemonHoldsLocks() throws {
        let component = uniqueComponent()
        let daemonLock = ComponentLockFile(component: component, guardsLocalExecution: true)
        try daemonLock.acquire()
        defer { daemonLock.release() }

        let response = CommandSocketClient.execute(argv: ["windows", "list"], cwd: nil, socketPath: missingSocketPath(), lockPath: lockPath(for: component)) {
            CLIResponse(exitCode: 0, stdout: "local\n")
        }
        #expect(response.stdout == "local\n")
    }

    // MARK: - R1-11 (REL-018) : rupture signalée, lecture par descripteur

    private func tempDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func appendTypes(_ types: [String], to path: String) {
        let log = EventLog(path: path)
        types.forEach { log.append(RoadieEvent(type: $0)) }
    }

    @Test
    func missingRotatedGenerationIsReportedAsGap() throws {
        let directory = try tempDirectory("r2c-events-gap")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("events.jsonl").path
        let service = EventSubscriptionService(path: path)

        appendTypes(["a1"], to: path)
        let first = service.readAvailable(from: service.start())
        appendTypes(["b1"], to: path)
        // Rotation puis suppression de l'ancienne génération par la rétention : b1 est perdu.
        try FileManager.default.moveItem(atPath: path, toPath: path + ".1")
        try FileManager.default.removeItem(atPath: path + ".1")
        appendTypes(["c1"], to: path)

        let second = service.readAvailable(from: first.cursor)
        #expect(second.events.map(\.type) == [EventSubscriptionService.gapEventType, "c1"])
        #expect(second.events.first?.payload["reason"] == .string("rotated_generation_missing"))
        #expect(service.readAvailable(from: second.cursor).events.isEmpty)
    }

    @Test
    func gapIsReportedEvenWhenTypeFilterExcludesIt() throws {
        let directory = try tempDirectory("r2c-events-gap-filter")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("events.jsonl").path
        let service = EventSubscriptionService(path: path)
        let options = EventSubscriptionOptions(types: ["c1"])

        appendTypes(["a1"], to: path)
        let first = service.readAvailable(from: service.start(), options: options)
        try FileManager.default.removeItem(atPath: path)
        appendTypes(["b1", "c1"], to: path)

        let second = service.readAvailable(from: first.cursor, options: options)
        #expect(second.events.map(\.type) == [EventSubscriptionService.gapEventType, "c1"])
    }

    @Test
    func fileTruncatedInPlaceIsReportedAsGap() throws {
        let directory = try tempDirectory("r2c-events-truncated")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("events.jsonl").path
        let service = EventSubscriptionService(path: path)

        appendTypes(["a1", "a2"], to: path)
        let first = service.readAvailable(from: service.start())
        let handle = try #require(FileHandle(forWritingAtPath: path))
        try handle.truncate(atOffset: 0)
        try handle.close()
        appendTypes(["b1"], to: path)

        let second = service.readAvailable(from: first.cursor)
        #expect(second.events.map(\.type) == [EventSubscriptionService.gapEventType, "b1"])
        #expect(second.events.first?.payload["reason"] == .string("file_truncated"))
    }

    /// Génération `.1` qui désigne déjà le fichier ouvert comme courant (rotation entre l'ouverture
    /// du fichier courant et la recherche des générations, simulée par un lien physique) : son
    /// contenu n'est lu qu'une fois.
    @Test
    func generationSharingCurrentInodeIsNotReadTwice() throws {
        let directory = try tempDirectory("r2c-events-link")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("events.jsonl").path
        let service = EventSubscriptionService(path: path)

        appendTypes(["a1"], to: path)
        let first = service.readAvailable(from: service.start())
        appendTypes(["b1"], to: path)
        try FileManager.default.moveItem(atPath: path, toPath: path + ".2")
        appendTypes(["c1"], to: path)
        #expect(link(path, path + ".1") == 0)

        let second = service.readAvailable(from: first.cursor)
        #expect(second.events.map(\.type) == ["b1", "c1"])
    }
}
