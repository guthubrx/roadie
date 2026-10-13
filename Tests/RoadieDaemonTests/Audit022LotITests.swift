import Foundation
import Darwin
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

/// Session 022, lot I : canal CLI-daemon, abonnement aux événements, rotation des logs,
/// persistance JSON et `config reload`. Aucun test ne touche à `~/.roadies` ni à `~/.local/state`.
@MainActor
@Suite(.serialized)
struct Audit022LotITests {
    // MARK: - Aides

    private func router(
        configReload: ConfigReloadService = ConfigReloadService(eventLog: EventLog(path: tempPath("lot-i-reload-events"))),
        railRuntimeStore: RailRuntimeStateStore = RailRuntimeStateStore(path: tempPath("lot-i-rail"))
    ) -> CLICommandRouter {
        CLICommandRouter(makeService: { _ in
            let provider = PowerUserProvider(windows: [powerWindow(1, x: 0)])
            return SnapshotService(
                provider: provider,
                frameWriter: PowerUserWriter(provider: provider),
                config: RoadieConfig(),
                intentStore: LayoutIntentStore(path: tempPath("lot-i-intents")),
                stageStore: StageStore(path: tempPath("lot-i-stages")),
                events: EventLog(path: tempPath("lot-i-events")),
                persistStateChanges: false
            )
        }, configReload: configReload, railRuntimeStore: railRuntimeStore)
    }

    /// Chemin court : `sun_path` est limité à 104 octets.
    private func socketPath() -> String {
        "/tmp/roadie-test-\(UUID().uuidString.prefix(8)).sock"
    }

    private func tempDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - REL-015 : socket vivant sans fichier pid

    /// Compteur d'exécutions locales, utilisable depuis une tâche détachée.
    private final class LocalRuns: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.withLock { value += 1 } }
        var count: Int { lock.withLock { value } }
    }

    @Test
    func daemonListeningOnSocketIsUsedEvenWithoutPidFile() async throws {
        let path = socketPath()
        let server = try #require(CommandSocketServer.start(router: router(), path: path))
        defer { server.stop() }
        // Verrou et pid absents : l'ancien test « pid vivant » concluait à un daemon absent.
        let lockPath = tempPath("lot-i-no-pid-lock")
        let runs = LocalRuns()

        let response = await Task.detached {
            CommandSocketClient.execute(argv: ["focus"], cwd: nil, socketPath: path, lockPath: lockPath) {
                runs.increment()
                return CLIResponse(exitCode: 0, stdout: "local\n")
            }
        }.value

        #expect(runs.count == 0)
        // Réponse du routeur du daemon (focus sans direction), pas du repli local.
        #expect(response.exitCode == 64)
        #expect(response.stderr.contains("focus requires"))
    }

    @Test
    func staleSocketFileWithoutListenerStillFallsBackLocally() async throws {
        let path = socketPath()
        // Socket périmé : fichier créé par bind, sans listen, puis descripteur fermé.
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
            buffer[pathBytes.count] = 0
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        close(fd)
        defer { unlink(path) }
        #expect(bound == 0)

        let lockPath = tempPath("lot-i-stale-lock")
        let runs = LocalRuns()
        let response = await Task.detached {
            CommandSocketClient.execute(argv: ["focus", "left"], cwd: nil, socketPath: path, lockPath: lockPath) {
                runs.increment()
                return CLIResponse(exitCode: 0, stdout: "local\n")
            }
        }.value
        #expect(runs.count == 1)
        #expect(response.stdout == "local\n")
    }

    // MARK: - PERF-007 : lecteur de ligne

    /// Écrit `fragments` dans un socketpair depuis un fil séparé, puis lit avec `readLine`.
    private func readLine(
        fragments: [[UInt8]],
        limit: Int,
        closeWriter: Bool = true
    ) -> CommandSocketIO.ReadResult {
        var fds: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        let reader = fds[0]
        let writer = fds[1]
        CommandSocketIO.prepare(reader)
        let feeder = Thread {
            for fragment in fragments {
                var offset = 0
                while offset < fragment.count {
                    let written = fragment[offset...].withUnsafeBytes { Darwin.send(writer, $0.baseAddress, $0.count, 0) }
                    if written > 0 { offset += written } else { usleep(200) }
                }
            }
            if closeWriter { close(writer) }
        }
        feeder.start()
        let result = CommandSocketIO.readLine(reader, limit: limit, deadline: Date().addingTimeInterval(10))
        close(reader)
        if !closeWriter { close(writer) }
        return result
    }

    @Test
    func readLineAssemblesFragmentsAndIgnoresDataAfterNewline() {
        let line = [UInt8](repeating: 0x61, count: 10_000)
        var tail = line
        tail.append(0x0A)
        tail.append(contentsOf: Array("suite".utf8))
        let result = readLine(fragments: [Array(line[0..<3000]), Array(tail[3000...])], limit: .max)
        guard case .line(let data) = result else { Issue.record("expected a line, got \(result)"); return }
        #expect(Array(data) == line)
    }

    @Test
    func readLineHandlesNewlineAtChunkBoundaryAndEmptyLine() {
        // Saut de ligne exactement après un fragment de 4096 octets.
        let line = [UInt8](repeating: 0x62, count: 4096)
        let result = readLine(fragments: [line, [0x0A]], limit: .max)
        guard case .line(let data) = result else { Issue.record("expected a line, got \(result)"); return }
        #expect(Array(data) == line)

        let empty = readLine(fragments: [[0x0A]], limit: 10)
        guard case .line(let emptyData) = empty else { Issue.record("expected an empty line, got \(empty)"); return }
        #expect(emptyData.isEmpty)
    }

    @Test
    func readLineKeepsEndOfStreamAndSizeRules() {
        // Fin de flux sans saut de ligne : le contenu reçu est la ligne.
        let partial = readLine(fragments: [Array("abc".utf8)], limit: 100)
        guard case .line(let data) = partial else { Issue.record("expected a line, got \(partial)"); return }
        #expect(String(decoding: data, as: UTF8.self) == "abc")

        // Flux vide : échec.
        guard case .failed = readLine(fragments: [], limit: 100) else { Issue.record("expected failure"); return }

        // Ligne au-dessus de la limite, avec ou sans saut de ligne.
        let big = [UInt8](repeating: 0x63, count: 200)
        guard case .tooLarge = readLine(fragments: [big, [0x0A]], limit: 100) else { Issue.record("expected tooLarge (newline)"); return }
        guard case .tooLarge = readLine(fragments: [big], limit: 100, closeWriter: false) else { Issue.record("expected tooLarge (no newline)"); return }

        // Ligne exactement à la limite : acceptée.
        let exact = [UInt8](repeating: 0x64, count: 100)
        guard case .line(let exactData) = readLine(fragments: [exact, [0x0A]], limit: 100) else { Issue.record("expected a line at the limit"); return }
        #expect(exactData.count == 100)
    }

    // MARK: - REL-018 : rotation du journal d'événements

    private func appendTypes(_ types: [String], to path: String) {
        let log = EventLog(path: path)
        types.forEach { log.append(RoadieEvent(type: $0)) }
    }

    @Test
    func subscriptionReadsRotatedGenerationBeforeReplacementFile() throws {
        let directory = try tempDirectory("lot-i-events")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("events.jsonl").path
        let service = EventSubscriptionService(path: path)

        appendTypes(["a1"], to: path)
        let first = service.readAvailable(from: service.start())
        #expect(first.events.map(\.type) == ["a1"])

        // B arrive, puis le journal tourne avant la lecture suivante ; le nouveau fichier est plus
        // long que le curseur (l'ancien code reprenait au milieu de C1 et perdait B).
        appendTypes(["b1"], to: path)
        try FileManager.default.moveItem(atPath: path, toPath: path + ".1")
        appendTypes(["c1", "c2", "c3"], to: path)

        let second = service.readAvailable(from: first.cursor)
        #expect(second.events.map(\.type) == ["b1", "c1", "c2", "c3"])

        // Rien n'est relu ensuite.
        #expect(service.readAvailable(from: second.cursor).events.isEmpty)
    }

    @Test
    func subscriptionFollowsTwoSuccessiveRotations() throws {
        let directory = try tempDirectory("lot-i-events2")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("events.jsonl").path
        let service = EventSubscriptionService(path: path)

        appendTypes(["a1"], to: path)
        let first = service.readAvailable(from: service.start())

        appendTypes(["b1"], to: path)
        try FileManager.default.moveItem(atPath: path, toPath: path + ".1")
        appendTypes(["c1"], to: path)
        try FileManager.default.moveItem(atPath: path + ".1", toPath: path + ".2")
        try FileManager.default.moveItem(atPath: path, toPath: path + ".1")
        appendTypes(["d1"], to: path)

        let second = service.readAvailable(from: first.cursor)
        #expect(second.events.map(\.type) == ["b1", "c1", "d1"])
    }

    @Test
    func subscriptionStartedFromNowSkipsHistoryButFollowsRotation() throws {
        let directory = try tempDirectory("lot-i-events3")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("events.jsonl").path
        let service = EventSubscriptionService(path: path)

        appendTypes(["old"], to: path)
        let cursor = service.start(options: EventSubscriptionOptions(fromNow: true))
        appendTypes(["b1"], to: path)
        try FileManager.default.moveItem(atPath: path, toPath: path + ".1")
        appendTypes(["c1"], to: path)

        #expect(service.readAvailable(from: cursor).events.map(\.type) == ["b1", "c1"])
    }

    // MARK: - OBS-001 : rotation des logs ouverts

    @Test
    func daemonLogRotationKeepsOpenDescriptorWritingToCurrentLog() throws {
        let roadies = try tempDirectory("lot-i-logs")
        defer { try? FileManager.default.removeItem(at: roadies) }
        let log = roadies.appendingPathComponent("roadied.stdout.log")
        let service = FileAdministrationService(
            roadiesPath: roadies.path,
            localStatePath: roadies.appendingPathComponent("state").path,
            configPath: roadies.appendingPathComponent("config").path,
            policy: FileAdminPolicy(maxEventLogBytes: 1_000_000, maxLogBytes: 10, retainedBackups: 2, retainedLegacyArchiveDirectories: 2)
        )

        // Descripteur ouvert en ajout, comme celui que launchd donne au daemon.
        let fd = open(log.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        defer { close(fd) }
        func write(_ text: String) { _ = text.withCString { Darwin.write(fd, $0, strlen($0)) } }

        write("première génération, assez longue\n")
        let first = service.run(dryRun: false)
        #expect(first.actions.contains { $0.path == log.path && $0.applied })

        write("nouvelle ligne\n")
        #expect(try String(contentsOf: log, encoding: .utf8) == "nouvelle ligne\n")
        #expect(try String(contentsOf: URL(fileURLWithPath: log.path + ".1"), encoding: .utf8) == "première génération, assez longue\n")

        // La rotation suivante fonctionne encore : le fichier courant reste celui qui grossit.
        write("une autre ligne assez longue\n")
        let second = service.run(dryRun: false)
        #expect(second.actions.contains { $0.path == log.path && $0.applied })
        #expect(try String(contentsOf: log, encoding: .utf8).isEmpty)
        #expect(try String(contentsOf: URL(fileURLWithPath: log.path + ".1"), encoding: .utf8) == "nouvelle ligne\nune autre ligne assez longue\n")
    }

    // MARK: - REL-021 : mutation non persistée

    private struct Counter: Codable, Equatable {
        var value = 0
    }

    @Test
    func mutateCheckedPersistsAndReturnsOutput() throws {
        let directory = try tempDirectory("lot-i-json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("counter.json")

        let output = try JSONPersistence.mutateChecked(Counter.self, at: url, default: Counter(), label: "counter") { state -> Int in
            state.value = 7
            return 42
        }
        #expect(output == 42)
        #expect(JSONPersistence.load(Counter.self, from: url, default: Counter()).value == 7)
    }

    @Test
    func mutateCheckedRefusesUnreadableFileWithoutRunningBodyOrTouchingFile() throws {
        let directory = try tempDirectory("lot-i-json-corrupt")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("counter.json")
        let garbage = Data("{ pas du json".utf8)
        try garbage.write(to: url)

        var bodyRan = false
        #expect(throws: JSONPersistence.PersistenceError.self) {
            try JSONPersistence.mutateChecked(Counter.self, at: url, default: Counter(), label: "counter") { state in
                bodyRan = true
                state.value = 1
            }
        }
        #expect(!bodyRan)
        #expect(try Data(contentsOf: url) == garbage)

        // Le contrat historique de `mutate` ne change pas : résultat rendu, rien d'écrit.
        let legacy = JSONPersistence.mutate(Counter.self, at: url, default: Counter(), label: "counter") { state -> Int in
            state.value = 1
            return 5
        }
        #expect(legacy == 5)
        #expect(try Data(contentsOf: url) == garbage)
    }

    @Test
    func mutateCheckedReportsLockFailureAndKeepsFile() throws {
        let directory = try tempDirectory("lot-i-json-readonly")
        defer {
            chmod(directory.path, 0o700)
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("counter.json")
        try JSONEncoder().encode(Counter(value: 3)).write(to: url)
        let before = try Data(contentsOf: url)
        // Dossier en lecture seule : le fichier de verrou ne peut pas être créé.
        chmod(directory.path, 0o500)
        guard access(directory.path, W_OK) != 0 else { return } // exécution en administrateur : cas non reproductible

        #expect(throws: JSONPersistence.PersistenceError.self) {
            try JSONPersistence.mutateChecked(Counter.self, at: url, default: Counter(), label: "counter") { $0.value = 9 }
        }
        #expect(try Data(contentsOf: url) == before)
    }

    @Test
    func railPinExitsNonZeroWhenStateIsNotPersisted() throws {
        let directory = try tempDirectory("lot-i-rail-corrupt")
        defer { try? FileManager.default.removeItem(at: directory) }
        let railPath = directory.appendingPathComponent("rail.json").path
        let garbage = Data("{ pas du json".utf8)
        try garbage.write(to: URL(fileURLWithPath: railPath))

        let response = router(railRuntimeStore: RailRuntimeStateStore(path: railPath)).run(["rail", "pin"])

        #expect(response.exitCode == 1)
        #expect(response.stderr.contains("not persisted"))
        #expect(!response.stdout.contains("pinned=true"))
        #expect(try Data(contentsOf: URL(fileURLWithPath: railPath)) == garbage)
    }

    @Test
    func railPinStillSucceedsWhenStateIsWritable() throws {
        let directory = try tempDirectory("lot-i-rail-ok")
        defer { try? FileManager.default.removeItem(at: directory) }
        let railPath = directory.appendingPathComponent("rail.json").path

        let pin = router(railRuntimeStore: RailRuntimeStateStore(path: railPath)).run(["rail", "pin"])
        #expect(pin.exitCode == 0)
        #expect(pin.stdout.contains("pinned=true"))
        let unpin = router(railRuntimeStore: RailRuntimeStateStore(path: railPath)).run(["rail", "unpin"])
        #expect(unpin.exitCode == 0)
        #expect(unpin.stdout.contains("pinned=false"))
    }

    // MARK: - REL-014 : config reload

    @Test
    func configReloadIsRoutedToDaemon() {
        #expect(CLICommandRouter.isDaemonRouted(["config", "reload"]))
        #expect(CLICommandRouter.isDaemonRouted(["config", "reload", "--config", "/tmp/x.toml"]))
        #expect(!CLICommandRouter.isDaemonRouted(["config", "show"]))
        #expect(!CLICommandRouter.isDaemonRouted(["config", "validate"]))
        #expect(!CLICommandRouter.isDaemonRouted(["config", "reload", "--help"]))
    }

    @Test
    func configReloadChangesTheInjectedSharedService() async throws {
        let directory = try tempDirectory("lot-i-config")
        defer { try? FileManager.default.removeItem(at: directory) }
        let alternate = directory.appendingPathComponent("alternate.toml")
        try "[tiling]\ngaps_inner = 31\n".write(to: alternate, atomically: true, encoding: .utf8)
        let service = ConfigReloadService(eventLog: EventLog(path: tempPath("lot-i-config-events")))
        let previousPath = service.state.activePath

        let response = router(configReload: service).run(["config", "reload", "--config", alternate.path])

        #expect(response.exitCode == 0)
        #expect(response.stdout.contains("status=applied"))
        #expect(service.state.activePath == alternate.path)
        #expect(service.state.activePath != previousPath)
    }

    @Test
    func invalidConfigReloadKeepsPreviousConfigurationAndExitsNonZero() throws {
        let directory = try tempDirectory("lot-i-config-invalid")
        defer { try? FileManager.default.removeItem(at: directory) }
        let invalid = directory.appendingPathComponent("invalid.toml")
        try "[tiling\ngaps_inner = ".write(to: invalid, atomically: true, encoding: .utf8)
        let service = ConfigReloadService(eventLog: EventLog(path: tempPath("lot-i-config-events")))
        let previousPath = service.state.activePath

        let response = router(configReload: service).run(["config", "reload", "--config", invalid.path])

        #expect(response.exitCode == 1)
        #expect(service.state.activePath == previousPath)
    }

    // MARK: - Suggestions du lot D

    @Test
    func emptyStageIdAndNonPositiveReorderPositionAreUsageErrors() {
        let create = router().run(["stage", "create", ""])
        #expect(create.exitCode == 64)
        let zero = router().run(["stage", "reorder", "2", "0"])
        #expect(zero.exitCode == 64)
        let negative = router().run(["stage", "reorder", "2", "-3"])
        #expect(negative.exitCode == 64)
    }
}
