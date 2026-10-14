import Darwin
import Foundation
import Testing
@testable import RoadieDaemon

/// Session 022, round 4, lot T6 : REL-032, REL-041, OBS-002, OBS-003.
/// Les scripts sont lancés contre un faux HOME, avec un faux `launchctl` en tête du PATH : ni le vrai
/// LaunchAgent, ni le vrai Roadie ne sont touchés. Les « composants » sont des copies de `sleep`
/// installées sous `$HOME/.local/bin/roadied`, un chemin reconnu par scripts/stop.
struct Audit022R4LotT6Tests {
    // MARK: - OBS-002 : fin de journal et caractère UTF-8 coupé

    /// Journal de plus de 64 Kio dont le bloc final commence au milieu de `glyph` (coupe après
    /// `keptBytes` octets du caractère). Les dernières lignes sont complètes et valides.
    private static func writeLog(glyph: String, keptBytes: Int, lines: [String]) throws -> URL {
        let glyphBytes = Array(glyph.utf8)
        let tail = lines.map { $0 + "\n" }.joined()
        // Bloc final = octets du glyphe après la coupe + filler + une ligne partielle + lignes finales.
        let blockSize = 64 * 1024
        let carried = glyphBytes.count - keptBytes
        let filler = blockSize - carried - tail.utf8.count - 1
        var data = Data(repeating: UInt8(ascii: "a"), count: 100)
        data.append(contentsOf: glyphBytes)
        data.append(Data(repeating: UInt8(ascii: "b"), count: filler))
        data.append(10)
        data.append(Data(tail.utf8))
        // Le dernier bloc de 64 Kio doit commencer exactement au milieu du glyphe.
        #expect(data.count - blockSize == 100 + keptBytes)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-t6-events-\(UUID().uuidString).jsonl")
        try data.write(to: url)
        return url
    }

    @Test(arguments: [("é", 1), ("😀", 1), ("😀", 2), ("😀", 3)])
    func tailSurvivesUTF8CharacterCutByChunkBoundary(glyph: String, keptBytes: Int) throws {
        let lines = [#"{"a":1}"#, #"{"b":2}"#, #"{"c":3}"#]
        let url = try Self.writeLog(glyph: glyph, keptBytes: keptBytes, lines: lines)
        defer { try? FileManager.default.removeItem(at: url) }

        let log = EventLog(path: url.path)
        #expect(log.tail(limit: 1) == [lines[2]])
        #expect(log.tail(limit: 2) == Array(lines.suffix(2)))
    }

    @Test
    func tailKeepsCompleteLinesWhenAnotherLineIsInvalidUTF8() throws {
        var data = Data("{\"a\":1}\n".utf8)
        data.append(contentsOf: [0xC3, 0x28, 10])
        data.append(Data("{\"c\":3}\n".utf8))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-t6-events-\(UUID().uuidString).jsonl")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let tail = EventLog(path: url.path).tail(limit: 3)
        #expect(tail.count == 3)
        #expect(tail.first == #"{"a":1}"#)
        #expect(tail.last == #"{"c":3}"#)
    }

    // MARK: - OBS-003 : suppression refusée

    /// Gestionnaire de fichiers dont toute suppression échoue (permission refusée).
    private final class DenyingFileManager: FileManager, @unchecked Sendable {
        override func removeItem(at URL: URL) throws {
            throw CocoaError(.fileWriteNoPermission)
        }
    }

    private static func makeCleanupTree() throws -> (base: URL, roadies: URL, config: URL, policy: FileAdminPolicy) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-t6-admin-\(UUID().uuidString)")
        let roadies = base.appendingPathComponent(".roadies")
        let config = base.appendingPathComponent(".config/roadies")
        try FileManager.default.createDirectory(at: roadies, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        // Trois sauvegardes de configuration en trop, une sauvegarde d'événements trop ancienne, un .DS_Store.
        for index in 0..<6 {
            try "backup".write(to: config.appendingPathComponent("roadies.toml.bak-\(index)"), atomically: true, encoding: .utf8)
        }
        try "x".write(to: roadies.appendingPathComponent("events.jsonl.5"), atomically: true, encoding: .utf8)
        try "x".write(to: config.appendingPathComponent(".DS_Store"), atomically: true, encoding: .utf8)
        return (base, roadies, config, FileAdminPolicy(retainedBackups: 2))
    }

    @Test
    func refusedRemovalIsNotReportedAsApplied() throws {
        let tree = try Self.makeCleanupTree()
        defer { try? FileManager.default.removeItem(at: tree.base) }
        let service = FileAdministrationService(
            roadiesPath: tree.roadies.path,
            localStatePath: tree.base.appendingPathComponent("state").path,
            configPath: tree.config.path,
            policy: tree.policy,
            manager: DenyingFileManager()
        )

        let report = service.run(dryRun: false)

        let deletions = report.actions.filter { $0.kind == .delete }
        // 3 sauvegardes de configuration, 1 sauvegarde d'événements, 1 .DS_Store.
        #expect(deletions.count == 5)
        #expect(deletions.allSatisfy { !$0.applied })
        let remaining = try FileManager.default.contentsOfDirectory(atPath: tree.config.path)
        #expect(remaining.filter { $0.hasPrefix("roadies.toml.bak-") }.count == 6)
        #expect(FileManager.default.fileExists(atPath: tree.roadies.appendingPathComponent("events.jsonl.5").path))
        #expect(FileManager.default.fileExists(atPath: tree.config.appendingPathComponent(".DS_Store").path))
    }

    @Test
    func successfulRemovalIsStillReportedAsApplied() throws {
        let tree = try Self.makeCleanupTree()
        defer { try? FileManager.default.removeItem(at: tree.base) }
        let service = FileAdministrationService(
            roadiesPath: tree.roadies.path,
            localStatePath: tree.base.appendingPathComponent("state").path,
            configPath: tree.config.path,
            policy: tree.policy
        )

        let report = service.run(dryRun: false)

        let deletions = report.actions.filter { $0.kind == .delete }
        #expect(deletions.count == 5)
        #expect(deletions.allSatisfy { $0.applied })
        #expect(!FileManager.default.fileExists(atPath: tree.roadies.appendingPathComponent("events.jsonl.5").path))
        #expect(!FileManager.default.fileExists(atPath: tree.config.appendingPathComponent(".DS_Store").path))
    }

    // MARK: - Scripts : faux environnement

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Faux HOME : `~/.roadies`, `~/.local/bin`, `~/Library/LaunchAgents` et un `launchctl` qui répond
    /// « non chargé » pour que scripts/stop n'appelle jamais le vrai launchd.
    private struct FakeHome {
        let base: URL
        var home: URL { base.appendingPathComponent("home") }
        var roadies: URL { home.appendingPathComponent(".roadies") }
        var localBin: URL { home.appendingPathComponent(".local/bin") }
        var plist: URL { home.appendingPathComponent("Library/LaunchAgents/com.roadie.roadied.plist") }
        var fakeBin: URL { base.appendingPathComponent("fakebin") }

        init() throws {
            base = FileManager.default.temporaryDirectory
                .appendingPathComponent("roadie-t6-env-\(UUID().uuidString)")
            let manager = FileManager.default
            try manager.createDirectory(at: roadies, withIntermediateDirectories: true)
            try manager.createDirectory(at: localBin, withIntermediateDirectories: true)
            try manager.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.createDirectory(at: fakeBin, withIntermediateDirectories: true)
            try "<plist/>".write(to: plist, atomically: true, encoding: .utf8)
            try Self.writeExecutable("#!/bin/sh\nexit 1\n", to: fakeBin.appendingPathComponent("launchctl"))
            // `roadie restore unhide-all` de scripts/uninstall : sans effet.
            try Self.writeExecutable("#!/bin/sh\nexit 0\n", to: localBin.appendingPathComponent("roadie"))
        }

        func cleanup() { try? FileManager.default.removeItem(at: base) }

        static func writeExecutable(_ text: String, to url: URL) throws {
            try text.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        /// Lance une copie de `sleep` nommée `roadied` (chemin reconnu par scripts/stop) et écrit son pidfile.
        func startComponent(_ name: String, executableName: String = "roadied") throws -> Process {
            let executable = localBin.appendingPathComponent(executableName)
            if !FileManager.default.fileExists(atPath: executable.path) {
                try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: executable)
            }
            let process = Process()
            process.executableURL = executable
            process.arguments = ["300"]
            try process.run()
            try "\(process.processIdentifier)\n".write(
                to: roadies.appendingPathComponent("\(name).pid"), atomically: true, encoding: .utf8)
            return process
        }

        /// Composant qui ignore SIGTERM (copie de bash installée sous le nom `roadied`).
        func startStubbornComponent(_ name: String) throws -> Process {
            let executable = localBin.appendingPathComponent("roadied")
            if !FileManager.default.fileExists(atPath: executable.path) {
                try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/bash"), to: executable)
            }
            let process = Process()
            process.executableURL = executable
            process.arguments = ["-c", "trap '' TERM; while :; do sleep 0.2; done"]
            try process.run()
            try "\(process.processIdentifier)\n".write(
                to: roadies.appendingPathComponent("\(name).pid"), atomically: true, encoding: .utf8)
            return process
        }
    }

    private struct ScriptResult {
        var status: Int32
        var stdout: String
        var stderr: String
    }

    /// Lance `bash <script>` avec un environnement minimal ; échoue (kill) au-delà de `timeout` secondes.
    private static func runScript(
        _ script: URL, in env: FakeHome, extraEnvironment: [String: String] = [:], timeout: TimeInterval = 60
    ) throws -> ScriptResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        var environment = [
            "HOME": env.home.path,
            "PATH": "\(env.fakeBin.path):/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": env.base.path + "/",
        ]
        environment.merge(extraEnvironment) { _, new in new }
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return ScriptResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private static func isAlive(_ process: Process) -> Bool {
        process.isRunning
    }

    private static let components = ["rail", "border", "focus-mouse", "titlebar-menu", "target-mode"]

    // MARK: - REL-032 : arrêt des composants modulaires

    @Test
    func stopScriptStopsEveryModularComponent() throws {
        let env = try FakeHome()
        defer { env.cleanup() }
        let processes = try Self.components.map { try env.startComponent($0) }
        defer { processes.forEach { if $0.isRunning { kill($0.processIdentifier, SIGKILL) } } }

        let result = try Self.runScript(Self.repoRoot.appendingPathComponent("scripts/stop"), in: env)

        #expect(result.status == 0, "stderr: \(result.stderr)")
        #expect(processes.allSatisfy { !Self.isAlive($0) })
        for name in Self.components {
            #expect(!FileManager.default.fileExists(atPath: env.roadies.appendingPathComponent("\(name).pid").path))
        }
    }

    @Test
    func stopScriptRefusesComponentWithUnknownExecutable() throws {
        let env = try FakeHome()
        defer { env.cleanup() }
        let foreign = try env.startComponent("rail", executableName: "other")
        let regular = try env.startComponent("border")
        defer { [foreign, regular].forEach { if $0.isRunning { kill($0.processIdentifier, SIGKILL) } } }

        let result = try Self.runScript(Self.repoRoot.appendingPathComponent("scripts/stop"), in: env)

        #expect(result.status == 1)
        #expect(result.stderr.contains("exécutable non reconnu"))
        #expect(Self.isAlive(foreign))
        #expect(FileManager.default.fileExists(atPath: env.roadies.appendingPathComponent("rail.pid").path))
        // Les autres composants sont quand même arrêtés.
        #expect(!Self.isAlive(regular))
    }

    @Test
    func uninstallRemovesNothingWhileAComponentResistsStop() throws {
        let env = try FakeHome()
        defer { env.cleanup() }
        let stubborn = try env.startStubbornComponent("focus-mouse")
        defer { if stubborn.isRunning { kill(stubborn.processIdentifier, SIGKILL) } }

        let result = try Self.runScript(Self.repoRoot.appendingPathComponent("scripts/uninstall"), in: env)

        #expect(result.status == 1)
        #expect(result.stderr.contains("encore vivant"))
        #expect(Self.isAlive(stubborn))
        #expect(FileManager.default.fileExists(atPath: env.plist.path))
        #expect(FileManager.default.fileExists(atPath: env.localBin.appendingPathComponent("roadied").path))
        #expect(FileManager.default.fileExists(atPath: env.localBin.appendingPathComponent("roadie").path))
    }

    @Test
    func uninstallStopsComponentsThenRemovesInstalledFiles() throws {
        let env = try FakeHome()
        defer { env.cleanup() }
        let processes = try ["rail", "titlebar-menu"].map { try env.startComponent($0) }
        defer { processes.forEach { if $0.isRunning { kill($0.processIdentifier, SIGKILL) } } }

        let result = try Self.runScript(Self.repoRoot.appendingPathComponent("scripts/uninstall"), in: env)

        #expect(result.status == 0, "stderr: \(result.stderr)")
        #expect(processes.allSatisfy { !Self.isAlive($0) })
        #expect(!FileManager.default.fileExists(atPath: env.plist.path))
        #expect(!FileManager.default.fileExists(atPath: env.localBin.appendingPathComponent("roadied").path))
    }

    // MARK: - REL-041 : dossier HOME temporaire du lanceur de tests

    /// Copie scripts/test à côté d'un faux `with-xcode` qui note son HOME puis sort avec `FAKE_EXIT`.
    private static func runTestLauncher(exitCode: Int32) throws -> (result: ScriptResult, recordedHome: String, leftovers: [String]) {
        let env = try FakeHome()
        defer { env.cleanup() }
        let scripts = env.base.appendingPathComponent("scripts")
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: repoRoot.appendingPathComponent("scripts/test"), to: scripts.appendingPathComponent("test"))
        try FakeHome.writeExecutable(
            "#!/bin/sh\necho \"$HOME\" > \"$FAKE_RECORD\"\n[ -d \"$HOME\" ] || exit 99\nexit \"$FAKE_EXIT\"\n",
            to: scripts.appendingPathComponent("with-xcode"))
        let record = env.base.appendingPathComponent("record.txt")
        let result = try runScript(
            scripts.appendingPathComponent("test"), in: env,
            extraEnvironment: ["FAKE_EXIT": String(exitCode), "FAKE_RECORD": record.path])
        let recorded = ((try? String(contentsOf: record, encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let leftovers = (try FileManager.default.contentsOfDirectory(atPath: env.base.path))
            .filter { $0.hasPrefix("roadie-test-home.") }
        return (result, recorded, leftovers)
    }

    @Test(arguments: [Int32(0), Int32(3)])
    func testLauncherRemovesItsTemporaryHomeAndKeepsExitCode(exitCode: Int32) throws {
        let outcome = try Self.runTestLauncher(exitCode: exitCode)

        #expect(outcome.result.status == exitCode, "stderr: \(outcome.result.stderr)")
        #expect(outcome.recordedHome.contains("roadie-test-home."))
        #expect(outcome.leftovers.isEmpty)
    }
}
