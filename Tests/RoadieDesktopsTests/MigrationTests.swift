import XCTest
import CoreGraphics
@testable import RoadieDesktops

/// Tests US6 — Migration V1 et SPEC-003 (T055, SC-004, FR-021-FR-022).
/// Couvre : migration V1→V2, archivage SPEC-003, idempotence.
final class MigrationTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-migration-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - Fixtures

    /// TOML stage V1 minimaliste avec 2 membres.
    private func stageV1TOML(id: String, members: [(cgwid: UInt32, bundle: String)]) -> String {
        var lines = [
            "id = \"\(id)\"",
            "display_name = \"\(id)\"",
            "tiler_strategy = \"bsp\"",
            "last_active_at = 2026-01-01T00:00:00Z",
            "",
            "[[members]]"
        ]
        for (i, m) in members.enumerated() {
            if i > 0 { lines.append("[[members]]") }
            lines += [
                "cg_window_id = \(m.cgwid)",
                "bundle_id = \"\(m.bundle)\"",
                "title_hint = \"Window \(m.cgwid)\"",
                "[members.saved_frame]",
                "x = 100.0",
                "y = 100.0",
                "w = 800.0",
                "h = 600.0",
                ""
            ]
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Migration V1 → V2 (T052, SC-004)

    func testMigrateV1ToV2() async throws {
        let stagesDir = tmpDir.appendingPathComponent("stages")
        let desktopsDir = tmpDir.appendingPathComponent("desktops")
        try FileManager.default.createDirectory(at: stagesDir, withIntermediateDirectories: true)

        // Fixture : 2 stages V1 avec 3 fenêtres au total
        let stage1 = stageV1TOML(id: "code", members: [(12345, "com.apple.Terminal"), (67890, "com.cursor.app")])
        let stage2 = stageV1TOML(id: "comm", members: [(11111, "com.apple.mail")])

        try stage1.write(to: stagesDir.appendingPathComponent("code.toml"), atomically: true, encoding: .utf8)
        try stage2.write(to: stagesDir.appendingPathComponent("comm.toml"), atomically: true, encoding: .utf8)

        // Run migration
        try await migrateV1ToV2(stagesDir: stagesDir, desktopsDir: desktopsDir)

        // Vérification : desktop 1 doit exister
        let targetFile = desktopsDir.appendingPathComponent("1/state.toml")
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetFile.path),
                      "desktops/1/state.toml doit exister après migration")

        let toml = try String(contentsOf: targetFile, encoding: .utf8)
        let desktop = try parseDesktop(from: toml)

        // 2 stages créés
        XCTAssertEqual(desktop.stages.count, 2, "2 stages V1 → 2 DesktopStage")

        // 3 fenêtres au total, 0 perte (SC-004)
        XCTAssertEqual(desktop.windows.count, 3, "3 fenêtres au total, 0 perte (SC-004)")
        let wids = Set(desktop.windows.map { $0.cgwid })
        XCTAssertTrue(wids.contains(12345))
        XCTAssertTrue(wids.contains(67890))
        XCTAssertTrue(wids.contains(11111))
    }

    // MARK: - No-op si stagesDir absent (T052)

    func testMigrateNoopIfStagesDirAbsent() async throws {
        let stagesDir = tmpDir.appendingPathComponent("stages-absent")
        let desktopsDir = tmpDir.appendingPathComponent("desktops")

        // Ne doit pas créer le fichier cible
        try await migrateV1ToV2(stagesDir: stagesDir, desktopsDir: desktopsDir)

        let targetFile = desktopsDir.appendingPathComponent("1/state.toml")
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetFile.path))
    }

    // MARK: - Idempotence (T055) : 2e run ne refait rien

    func testMigrateIdempotent() async throws {
        let stagesDir = tmpDir.appendingPathComponent("stages")
        let desktopsDir = tmpDir.appendingPathComponent("desktops")
        try FileManager.default.createDirectory(at: stagesDir, withIntermediateDirectories: true)

        let stage = stageV1TOML(id: "code", members: [(99, "com.test.app")])
        try stage.write(to: stagesDir.appendingPathComponent("code.toml"), atomically: true, encoding: .utf8)

        // 1er run
        try await migrateV1ToV2(stagesDir: stagesDir, desktopsDir: desktopsDir)
        let targetFile = desktopsDir.appendingPathComponent("1/state.toml")
        let firstContent = try String(contentsOf: targetFile, encoding: .utf8)

        // 2e run → ne doit rien modifier (idempotence)
        try await migrateV1ToV2(stagesDir: stagesDir, desktopsDir: desktopsDir)
        let secondContent = try String(contentsOf: targetFile, encoding: .utf8)
        XCTAssertEqual(firstContent, secondContent, "2e run ne doit pas modifier le fichier")
    }

    // MARK: - Archive SPEC-003 (T053, FR-022)

    func testArchiveSpec003Dirs() throws {
        let desktopsDir = tmpDir.appendingPathComponent("desktops")
        try FileManager.default.createDirectory(at: desktopsDir, withIntermediateDirectories: true)

        let uuid1 = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
        let uuid2 = "B2C3D4E5-F6A7-8901-BCDE-F12345678901"
        let normalDir = "1"   // desktop SPEC-011, ne doit PAS être archivé

        for name in [uuid1, uuid2, normalDir] {
            let dir = desktopsDir.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        try archiveSpec003LegacyDirs(desktopsDir: desktopsDir)

        let fm = FileManager.default
        // Les UUIDs doivent être archivés
        XCTAssertFalse(fm.fileExists(atPath: desktopsDir.appendingPathComponent(uuid1).path),
                       "UUID dir doit être renommé")
        XCTAssertTrue(fm.fileExists(atPath: desktopsDir.appendingPathComponent(".archived-spec003-\(uuid1)").path),
                      "Dossier archivé doit exister")
        XCTAssertFalse(fm.fileExists(atPath: desktopsDir.appendingPathComponent(uuid2).path))
        XCTAssertTrue(fm.fileExists(atPath: desktopsDir.appendingPathComponent(".archived-spec003-\(uuid2)").path))

        // Le dossier "1" ne doit PAS être touché
        XCTAssertTrue(fm.fileExists(atPath: desktopsDir.appendingPathComponent(normalDir).path),
                      "Desktop SPEC-011 ne doit pas être archivé")
    }

    // MARK: - stagesDir conservé après migration (read-only pour rollback)

    func testStagesDirPreservedAfterMigration() async throws {
        let stagesDir = tmpDir.appendingPathComponent("stages")
        let desktopsDir = tmpDir.appendingPathComponent("desktops")
        try FileManager.default.createDirectory(at: stagesDir, withIntermediateDirectories: true)

        let stage = stageV1TOML(id: "code", members: [(77, "com.test.rollback")])
        try stage.write(to: stagesDir.appendingPathComponent("code.toml"), atomically: true, encoding: .utf8)

        try await migrateV1ToV2(stagesDir: stagesDir, desktopsDir: desktopsDir)

        // stagesDir doit TOUJOURS exister après la migration (rollback possible)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagesDir.path),
                      "stagesDir doit être conservé (read-only) après migration")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: stagesDir.appendingPathComponent("code.toml").path),
                      "Fichier stage V1 doit être conservé")
    }
}
