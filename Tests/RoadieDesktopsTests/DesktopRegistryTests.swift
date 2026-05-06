import XCTest
import CoreGraphics
@testable import RoadieDesktops

final class DesktopRegistryTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-registry-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - Load / Save round-trip (T018)

    func testLoadSaveRoundTrip() async throws {
        let registry = DesktopRegistry(configDir: tmpDir, displayUUID: "TEST-UUID-0001", count: 3)

        let desktop = RoadieDesktop(
            id: 2, label: "comm", layout: .bsp,
            gapsOuter: 8, gapsInner: 4, activeStageID: 1,
            stages: [DesktopStage(id: 1, label: nil, windows: [42])],
            windows: [WindowEntry(cgwid: 42, bundleID: "com.apple.mail",
                                  title: "Mail", expectedFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
                                  stageID: 1)]
        )
        try await registry.save(desktop)

        // Nouveau registry depuis le même configDir
        let registry2 = DesktopRegistry(configDir: tmpDir, displayUUID: "TEST-UUID-0001", count: 3)
        await registry2.load()

        let loaded = await registry2.desktop(id: 2)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.label, "comm")
        XCTAssertEqual(loaded?.windows.count, 1)
        XCTAssertEqual(loaded?.windows.first?.cgwid, 42)
    }

    // MARK: - setCurrent met à jour recentID (T018)

    func testSetCurrentUpdatesRecentID() async {
        let registry = DesktopRegistry(configDir: tmpDir, displayUUID: "TEST-UUID-0001", count: 5)
        await registry.load()

        await registry.setCurrent(id: 3)
        let recent1 = await registry.recentID
        let current1 = await registry.currentID
        XCTAssertEqual(current1, 3)
        XCTAssertEqual(recent1, 1)   // 1 était le courant initial

        await registry.setCurrent(id: 5)
        let recent2 = await registry.recentID
        let current2 = await registry.currentID
        XCTAssertEqual(current2, 5)
        XCTAssertEqual(recent2, 3)
    }

    // MARK: - setCurrent avec même ID = pas de changement recentID

    func testSetCurrentSameIDIsNoop() async {
        let registry = DesktopRegistry(configDir: tmpDir, displayUUID: "TEST-UUID-0001", count: 5)
        await registry.load()

        await registry.setCurrent(id: 3)
        let recentBefore = await registry.recentID
        await registry.setCurrent(id: 3)   // même ID
        let recentAfter = await registry.recentID
        XCTAssertEqual(recentBefore, recentAfter)
    }

    // MARK: - Fichier corrompu → init vierge + continue (FR-013, T018)

    func testCorruptedFileLogsAndInitializesBlank() async throws {
        // Écrire un TOML syntaxiquement valide mais sémantiquement incorrect
        // pour le desktop 2 (champ obligatoire `id` manquant). TOMLKit s'appuie
        // sur toml++ (C++) qui assert-crashe sur certains TOML totalement
        // aberrants au lieu de throw. On choisit donc une corruption sémantique
        // qui passe le parser TOML mais échoue dans parseDesktop, ce qui
        // déclenche le catch et la voie blank-init (FR-013).
        let dir = tmpDir.appendingPathComponent("desktops/2")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("state.toml")
        try "label = \"orphan\"\nlayout = \"bsp\"\n".write(to: url, atomically: true, encoding: .utf8)

        let registry = DesktopRegistry(configDir: tmpDir, displayUUID: "TEST-UUID-0001", count: 3)
        await registry.load()   // ne doit pas throw

        let d2 = await registry.desktop(id: 2)
        XCTAssertNotNil(d2)
        XCTAssertEqual(d2?.id, 2)
        XCTAssertTrue(d2?.windows.isEmpty ?? false)  // état vierge
    }

    // MARK: - windows(of:) retourne les cgwids corrects

    func testWindowsOfDesktop() async throws {
        let registry = DesktopRegistry(configDir: tmpDir, displayUUID: "TEST-UUID-0001", count: 2)

        let desktop = RoadieDesktop(
            id: 1, stages: [DesktopStage(id: 1, windows: [10, 20])],
            windows: [
                WindowEntry(cgwid: 10, bundleID: "a", title: "A",
                            expectedFrame: .zero, stageID: 1),
                WindowEntry(cgwid: 20, bundleID: "b", title: "B",
                            expectedFrame: .zero, stageID: 1)
            ]
        )
        try await registry.save(desktop)

        let wids = await registry.windows(of: 1)
        XCTAssertEqual(Set(wids), Set([10, 20]))
    }

    // MARK: - Desktop absent → blank (load sans fichier)

    func testMissingFileLoadsBlank() async {
        let registry = DesktopRegistry(configDir: tmpDir, displayUUID: "TEST-UUID-0001", count: 3)
        await registry.load()
        let d3 = await registry.desktop(id: 3)
        XCTAssertNotNil(d3)
        XCTAssertEqual(d3?.id, 3)
    }

    // MARK: - assignWindow enregistre dans windows[] et stages[].windows (pont daemon SPEC-011)

    func testAssignWindowPopulatesWindowsAndStage() async throws {
        let registry = DesktopRegistry(configDir: tmpDir, displayUUID: "TEST-UUID-0001", count: 3)
        await registry.load()

        let entry = WindowEntry(
            cgwid: 99, bundleID: "com.apple.safari", title: "Safari",
            expectedFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            stageID: 1
        )
        let currentID = await registry.currentID
        try await registry.assignWindow(entry, to: currentID)

        let desktop = await registry.desktop(id: currentID)
        // La fenêtre doit apparaître dans windows[]
        XCTAssertTrue(desktop?.windows.contains { $0.cgwid == 99 } ?? false)
        // La fenêtre doit apparaître dans le stage par défaut
        let stageWids = desktop?.stages.first?.windows ?? []
        XCTAssertTrue(stageWids.contains(99))
        // windows(of:) doit retourner le cgwid
        let wids = await registry.windows(of: currentID)
        XCTAssertTrue(wids.contains(CGWindowID(99)))
    }

    // MARK: - assignWindow évite les doublons

    func testAssignWindowNoDuplicate() async throws {
        let registry = DesktopRegistry(configDir: tmpDir, displayUUID: "TEST-UUID-0001", count: 3)
        await registry.load()

        let entry = WindowEntry(
            cgwid: 77, bundleID: "com.apple.terminal", title: "Terminal",
            expectedFrame: .zero, stageID: 1
        )
        try await registry.assignWindow(entry, to: 1)
        try await registry.assignWindow(entry, to: 1)  // 2e appel = idempotent

        let desktop = await registry.desktop(id: 1)
        let count = desktop?.windows.filter { $0.cgwid == 77 }.count ?? 0
        XCTAssertEqual(count, 1)
        let stageCount = desktop?.stages.first?.windows.filter { $0 == 77 }.count ?? 0
        XCTAssertEqual(stageCount, 1)
    }

    // MARK: - updateExpectedFrame persiste la nouvelle frame (FR-005)

    func testUpdateExpectedFramePersistsNewFrame() async throws {
        let registry = DesktopRegistry(configDir: tmpDir, displayUUID: "TEST-UUID-0001", count: 3)
        await registry.load()

        let initial = CGRect(x: 100, y: 100, width: 800, height: 600)
        let updated = CGRect(x: 200, y: 200, width: 1000, height: 700)
        let entry = WindowEntry(
            cgwid: 11, bundleID: "com.example.iterm", title: "iTerm2",
            expectedFrame: initial, stageID: 1
        )
        try await registry.assignWindow(entry, to: 1)

        // Mise à jour de la frame après déplacement/redimensionnement utilisateur
        try await registry.updateExpectedFrame(cgwid: 11, desktopID: 1, frame: updated)

        // Save + reload : la nouvelle frame doit survivre à la persistance
        let registry2 = DesktopRegistry(configDir: tmpDir, displayUUID: "TEST-UUID-0001", count: 3)
        await registry2.load()

        let loaded = await registry2.expectedFrame(cgwid: 11, desktopID: 1)
        XCTAssertEqual(loaded, updated, "expectedFrame doit être la frame mise à jour, pas l'initiale")
    }

    // MARK: - desktopID(for:) retourne l'ID correct (FR-005 lookup inverse)

    func testDesktopIDForCgwid() async throws {
        let registry = DesktopRegistry(configDir: tmpDir, displayUUID: "TEST-UUID-0001", count: 3)
        await registry.load()

        let entry = WindowEntry(
            cgwid: 77, bundleID: "com.apple.safari", title: "Safari",
            expectedFrame: .zero, stageID: 1
        )
        try await registry.assignWindow(entry, to: 2)

        let found = await registry.desktopID(for: 77)
        XCTAssertEqual(found, 2)

        let notFound = await registry.desktopID(for: 999)
        XCTAssertNil(notFound)
    }

    // MARK: - removeWindow retire la fenêtre de tous les desktops (pont destruction SPEC-011)

    func testRemoveWindowCleansAllDesktops() async throws {
        let registry = DesktopRegistry(configDir: tmpDir, displayUUID: "TEST-UUID-0001", count: 3)
        await registry.load()

        // Enregistrer la même fenêtre dans desktop 1 et 2
        let entry = WindowEntry(
            cgwid: 55, bundleID: "com.example.app", title: "App",
            expectedFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
            stageID: 1
        )
        try await registry.assignWindow(entry, to: 1)
        try await registry.assignWindow(entry, to: 2)

        await registry.removeWindow(cgwid: 55)

        let d1 = await registry.desktop(id: 1)
        let d2 = await registry.desktop(id: 2)
        XCTAssertFalse(d1?.windows.contains { $0.cgwid == 55 } ?? true)
        XCTAssertFalse(d2?.windows.contains { $0.cgwid == 55 } ?? true)
        XCTAssertFalse(d1?.stages.first?.windows.contains(55) ?? true)
        XCTAssertFalse(d2?.stages.first?.windows.contains(55) ?? true)
    }
}
