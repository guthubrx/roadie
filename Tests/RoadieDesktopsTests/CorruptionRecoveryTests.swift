import XCTest
import CoreGraphics
@testable import RoadieDesktops

/// Tests T040 — Récupération sur corruption : un state.toml invalide ne bloque pas le boot.
/// Stratégie de corruption : TOML syntaxiquement valide mais champ obligatoire `id` manquant
/// (déclenche le catch dans DesktopRegistry.load → init vierge FR-013).
final class CorruptionRecoveryTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-corrupt-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func writeValidDesktop(_ desktop: RoadieDesktop) throws {
        let dir = tmpDir.appendingPathComponent("desktops/\(desktop.id)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let toml = serialize(desktop)
        let target = dir.appendingPathComponent("state.toml")
        let tmp = dir.appendingPathComponent("state.toml.tmp")
        try toml.write(to: tmp, atomically: false, encoding: .utf8)
        try FileManager.default.moveItem(at: tmp, to: target)
    }

    private func writeCorruptDesktop(id: Int, content: String) throws {
        let dir = tmpDir.appendingPathComponent("desktops/\(id)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("state.toml")
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - T040 Test 1 : desktop 2 corrompu, desktops 1 et 3 intacts

    func testCorruptDesktop2LoadsBlankOthersIntact() async throws {
        // Desktop 1 : valide avec contenu
        let d1 = RoadieDesktop(
            id: 1, label: "work", layout: .bsp, gapsOuter: 8, gapsInner: 4,
            activeStageID: 1,
            stages: [DesktopStage(id: 1, label: "dev", windows: [101])],
            windows: [WindowEntry(cgwid: 101, bundleID: "com.apple.Terminal",
                                  title: "Term", expectedFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
                                  stageID: 1)]
        )
        try writeValidDesktop(d1)

        // Desktop 2 : TOML valide mais champ `id` manquant → parseDesktop throws → blank
        try writeCorruptDesktop(
            id: 2,
            content: "label = \"orphan\"\nlayout = \"bsp\"\ngaps_outer = 8\ngaps_inner = 4\n"
        )

        // Desktop 3 : valide
        let d3 = RoadieDesktop(
            id: 3, label: "media", layout: .floating, gapsOuter: 0, gapsInner: 0,
            activeStageID: 1,
            stages: [DesktopStage(id: 1)],
            windows: []
        )
        try writeValidDesktop(d3)

        // Boot : ne doit pas throw
        let registry = DesktopRegistry(configDir: tmpDir, count: 3)
        await registry.load()   // FR-013 : silencieux sur corruption

        // Desktop 2 = vierge
        let rd2 = await registry.desktop(id: 2)
        XCTAssertNotNil(rd2, "Desktop 2 doit exister même après corruption")
        XCTAssertEqual(rd2?.id, 2)
        XCTAssertTrue(rd2?.windows.isEmpty ?? false,
                      "Desktop 2 corrompu doit être vierge (windows.isEmpty)")
        XCTAssertNil(rd2?.label, "Label doit être nil (desktop vierge)")

        // Desktop 1 intact
        let rd1 = await registry.desktop(id: 1)
        XCTAssertEqual(rd1?.label, "work")
        XCTAssertEqual(rd1?.windows.count, 1)
        XCTAssertEqual(rd1?.windows.first?.cgwid, 101)

        // Desktop 3 intact
        let rd3 = await registry.desktop(id: 3)
        XCTAssertEqual(rd3?.label, "media")
        XCTAssertEqual(rd3?.layout, .floating)
    }

    // MARK: - T040 Test 2 : toutes les corruptions d'un coup, le registry récupère

    func testAllDesktopsCorruptedRecoverToBlank() async throws {
        // Écrire 3 desktops corrompus (id manquant)
        for n in 1...3 {
            try writeCorruptDesktop(
                id: n,
                content: "label = \"corrupt\"\nlayout = \"bsp\"\n"
            )
        }

        let registry = DesktopRegistry(configDir: tmpDir, count: 3)
        await registry.load()

        // Tous vierges, mais tous présents
        for n in 1...3 {
            let d = await registry.desktop(id: n)
            XCTAssertNotNil(d, "Desktop \(n) doit exister")
            XCTAssertEqual(d?.id, n)
            XCTAssertTrue(d?.windows.isEmpty ?? false)
        }
    }

    // MARK: - T040 Test 3 : desktop absent → blank (pas de fichier)

    func testMissingDesktopLoadsBlank() async {
        // Aucun fichier écrit, juste créer le registry
        let registry = DesktopRegistry(configDir: tmpDir, count: 2)
        await registry.load()

        let d1 = await registry.desktop(id: 1)
        XCTAssertNotNil(d1)
        XCTAssertEqual(d1?.id, 1)
        XCTAssertTrue(d1?.windows.isEmpty ?? false)

        let d2 = await registry.desktop(id: 2)
        XCTAssertNotNil(d2)
        XCTAssertEqual(d2?.id, 2)
    }

    // MARK: - T040 Test 4 : current.txt absent → currentID = defaultFocus (1)

    func testMissingCurrentTxtDefaultsToOne() async throws {
        // Desktop 1 valide
        let d1 = RoadieDesktop(id: 1, stages: [DesktopStage(id: 1)])
        try writeValidDesktop(d1)
        // Pas de current.txt

        let registry = DesktopRegistry(configDir: tmpDir, count: 2)
        await registry.load()

        let currentID = await registry.currentID
        XCTAssertEqual(currentID, 1, "En l'absence de current.txt, currentID doit valoir 1")
    }
}
