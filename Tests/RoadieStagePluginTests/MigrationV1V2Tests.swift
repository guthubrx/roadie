import XCTest
import RoadieCore
@testable import RoadieStagePlugin

final class MigrationV1V2Tests: XCTestCase {

    private var tmpDir: String!
    private let testUUID = "TEST-DISPLAY-UUID-0001"

    override func setUp() {
        super.setUp()
        tmpDir = (FileManager.default.temporaryDirectory.path as NSString)
            .appendingPathComponent("roadie-mig-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tmpDir)
        try? FileManager.default.removeItem(atPath: tmpDir + ".v1.bak")
        super.tearDown()
    }

    // MARK: - Helpers

    /// Crée N fichiers `<n>.toml` vides dans tmpDir.
    private func createFlatTOMLFiles(count: Int) {
        for i in 1...count {
            let path = "\(tmpDir!)/\(i).toml"
            try! "".write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private func makeMigration() -> MigrationV1V2 {
        MigrationV1V2(stagesDir: tmpDir, mainDisplayUUID: testUUID)
    }

    // MARK: - testHappyPath

    func test_happy_path_migrates_five_files() throws {
        createFlatTOMLFiles(count: 5)

        let migration = makeMigration()
        let report = try migration.runIfNeeded()

        XCTAssertNotNil(report, "La migration doit retourner un Report")
        XCTAssertEqual(report?.migratedCount, 5)
        XCTAssertEqual(report?.targetDisplayUUID, testUUID)

        // Vérifier que les 5 fichiers sont dans <UUID>/1/
        let targetDir = "\(tmpDir!)/\(testUUID)/1"
        let moved = (try? FileManager.default.contentsOfDirectory(atPath: targetDir)) ?? []
        let tomlFiles = moved.filter { $0.hasSuffix(".toml") }
        XCTAssertEqual(tomlFiles.count, 5, "5 fichiers doivent être dans \(targetDir)")

        // Vérifier que le backup a été créé
        let backupPath = tmpDir! + ".v1.bak"
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupPath),
                      "Le dossier backup .v1.bak doit exister")
        XCTAssertEqual(report?.backupPath, backupPath)
    }

    func test_happy_path_durationMs_is_non_negative() throws {
        createFlatTOMLFiles(count: 3)
        let report = try makeMigration().runIfNeeded()
        XCTAssertGreaterThanOrEqual(report?.durationMs ?? -1, 0)
    }

    // MARK: - testIdempotent

    func test_idempotent_second_run_returns_nil() throws {
        createFlatTOMLFiles(count: 3)
        let migration = makeMigration()

        let first = try migration.runIfNeeded()
        XCTAssertNotNil(first, "Première exécution doit migrer")

        let second = try migration.runIfNeeded()
        XCTAssertNil(second, "Deuxième exécution doit retourner nil (idempotent)")
    }

    // MARK: - testRecoveryBackupPresent

    func test_backup_already_present_returns_nil_and_does_not_modify() throws {
        // Créer le backup manuellement (simule migration déjà faite)
        let backupPath = tmpDir! + ".v1.bak"
        try FileManager.default.createDirectory(atPath: backupPath, withIntermediateDirectories: true)

        // Créer aussi des fichiers flat (qui ne doivent PAS être déplacés)
        createFlatTOMLFiles(count: 2)

        let result = try makeMigration().runIfNeeded()
        XCTAssertNil(result, "Backup présent → nil retourné")

        // Vérifier que les fichiers flat sont TOUJOURS dans tmpDir (pas déplacés)
        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: tmpDir!)) ?? []
        let tomlFiles = remaining.filter { $0.hasSuffix(".toml") }
        XCTAssertEqual(tomlFiles.count, 2, "Les fichiers flat ne doivent pas avoir été déplacés")
    }

    // MARK: - testNoMigrationIfEmpty

    func test_empty_dir_returns_nil() throws {
        // Dossier vide : aucun fichier .toml
        let result = try makeMigration().runIfNeeded()
        XCTAssertNil(result, "Dossier vide → nil (rien à migrer)")
    }

    func test_only_subdirectories_returns_nil() throws {
        // Contient déjà des sous-dossiers (structure V2)
        let subdir = "\(tmpDir!)/SOME-UUID/1"
        try FileManager.default.createDirectory(atPath: subdir, withIntermediateDirectories: true)
        try "".write(toFile: "\(subdir)/1.toml", atomically: true, encoding: .utf8)

        let result = try makeMigration().runIfNeeded()
        XCTAssertNil(result, "Structure V2 déjà présente sans fichiers flat → nil")
    }

    func test_active_toml_not_migrated() throws {
        // active.toml doit être ignoré par la migration
        try "".write(toFile: "\(tmpDir!)/active.toml", atomically: true, encoding: .utf8)

        let result = try makeMigration().runIfNeeded()
        XCTAssertNil(result, "active.toml seul ne déclenche pas la migration")
    }

    // MARK: - testMixedContentOnlyFlatMigrated

    func test_only_top_level_toml_files_are_migrated() throws {
        // 2 fichiers flat + 1 sous-dossier avec un .toml
        createFlatTOMLFiles(count: 2)
        let subdir = "\(tmpDir!)/\(testUUID)/1"
        try FileManager.default.createDirectory(atPath: subdir, withIntermediateDirectories: true)
        try "".write(toFile: "\(subdir)/existing.toml", atomically: true, encoding: .utf8)

        // Avec 2 fichiers flat, la migration doit se déclencher
        let report = try makeMigration().runIfNeeded()
        XCTAssertNotNil(report)
        // migratedCount = 2 (pas le fichier dans le sous-dossier)
        XCTAssertEqual(report?.migratedCount, 2)
    }
}
