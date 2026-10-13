import Foundation
import Testing
import RoadieDaemon

@Suite
struct FileAdministrationTests {
    @Test
    func cleanupKeepsOnlyRecentGeneratedBackupsAndArchives() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-admin-\(UUID().uuidString)")
        let roadies = base.appendingPathComponent(".roadies")
        let local = base.appendingPathComponent(".local/state/roadies")
        let config = base.appendingPathComponent(".config/roadies")
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: roadies, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)

        try Data(repeating: 1, count: 32).write(to: roadies.appendingPathComponent("events.jsonl"))
        try Data(repeating: 1, count: 32).write(to: roadies.appendingPathComponent("events.jsonl.1"))
        try Data(repeating: 2, count: 32).write(to: roadies.appendingPathComponent("roadied.stdout.log"))
        try Data(repeating: 3, count: 32).write(to: roadies.appendingPathComponent("roadied.stdout.log.1"))
        try Data(repeating: 4, count: 3).write(to: roadies.appendingPathComponent("roadied.stderr.log"))
        for index in 0..<5 {
            let archive = config.appendingPathComponent("stages.v1.bak.archived-\(index)")
            try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
            try "stage".write(to: archive.appendingPathComponent("1.toml"), atomically: true, encoding: .utf8)
        }
        for index in 0..<5 {
            try "backup".write(
                to: config.appendingPathComponent("roadies.toml.bak-\(index)"),
                atomically: true,
                encoding: .utf8
            )
        }

        let service = FileAdministrationService(
            roadiesPath: roadies.path,
            localStatePath: local.path,
            configPath: config.path,
            policy: FileAdminPolicy(
                maxEventLogBytes: 10,
                maxLogBytes: 10,
                retainedBackups: 2,
                retainedLegacyArchiveDirectories: 2
            )
        )
        let dryRun = service.run(dryRun: true)
        #expect(dryRun.candidateCount > 0)
        #expect(FileManager.default.fileExists(atPath: roadies.appendingPathComponent("events.jsonl").path))

        let rotations = dryRun.actions.filter { $0.path.hasSuffix(".log") }
        #expect(rotations.map(\.kind) == [.rotate])
        #expect(FileManager.default.fileExists(atPath: roadies.appendingPathComponent("roadied.stdout.log").path))

        let applied = service.run(dryRun: false)
        // Rotation : le log courant est copié en .1 (ancien .1 écrasé) puis tronqué sur place (OBS-001).
        let stdoutBackup = try Data(contentsOf: roadies.appendingPathComponent("roadied.stdout.log.1"))
        #expect(stdoutBackup == Data(repeating: 2, count: 32))
        #expect(try Data(contentsOf: roadies.appendingPathComponent("roadied.stdout.log")).isEmpty)
        #expect(FileManager.default.fileExists(atPath: roadies.appendingPathComponent("roadied.stderr.log").path))
        #expect(applied.actions.contains { $0.applied })
        #expect(!FileManager.default.fileExists(atPath: roadies.appendingPathComponent("events.jsonl.1").path))
        #expect(!FileManager.default.fileExists(atPath: roadies.appendingPathComponent("events.jsonl.2").path))
        let remainingArchives = try FileManager.default.contentsOfDirectory(atPath: config.path)
            .filter { $0.hasPrefix("stages.v1.bak.archived-") }
        #expect(remainingArchives.count == 2)
        let remainingConfigBackups = try FileManager.default.contentsOfDirectory(atPath: config.path)
            .filter { $0.hasPrefix("roadies.toml.b") }
        #expect(remainingConfigBackups.count == 3)
    }
}
