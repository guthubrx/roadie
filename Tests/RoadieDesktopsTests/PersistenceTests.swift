import XCTest
import CoreGraphics
@testable import RoadieDesktops

/// Tests T039 — Persistance complète : save puis load restitue l'état identique.
/// Couvre currentID, recentID, labels, layouts, gaps, stages, windows, expectedFrame.
final class PersistenceTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-persist-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeRegistry(count: Int = 3) -> DesktopRegistry {
        DesktopRegistry(configDir: tmpDir, displayUUID: "TEST-UUID-0001", count: count)
    }

    private func makeDesktop1() -> RoadieDesktop {
        RoadieDesktop(
            id: 1,
            label: "code",
            layout: .bsp,
            gapsOuter: 12,
            gapsInner: 6,
            activeStageID: 2,
            stages: [
                DesktopStage(id: 1, label: "dev", windows: [100, 200]),
                DesktopStage(id: 2, label: "test", windows: [300]),
            ],
            windows: [
                WindowEntry(cgwid: 100, bundleID: "com.apple.Terminal",
                            title: "Terminal", expectedFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
                            stageID: 1),
                WindowEntry(cgwid: 200, bundleID: "com.github.electron",
                            title: "Cursor", expectedFrame: CGRect(x: 810, y: 0, width: 790, height: 600),
                            stageID: 1),
                WindowEntry(cgwid: 300, bundleID: "com.apple.Xcode",
                            title: "Xcode", expectedFrame: CGRect(x: 0, y: 610, width: 1600, height: 400),
                            stageID: 2),
            ]
        )
    }

    private func makeDesktop2() -> RoadieDesktop {
        RoadieDesktop(
            id: 2,
            label: "comm",
            layout: .masterStack,
            gapsOuter: 8,
            gapsInner: 4,
            activeStageID: 1,
            stages: [DesktopStage(id: 1, label: "chat", windows: [400])],
            windows: [
                WindowEntry(cgwid: 400, bundleID: "com.tinyspeck.slackmacgap",
                            title: "Slack", expectedFrame: CGRect(x: 0, y: 0, width: 1600, height: 900),
                            stageID: 1),
            ]
        )
    }

    private func makeDesktop3() -> RoadieDesktop {
        RoadieDesktop(
            id: 3,
            label: nil,
            layout: .floating,
            gapsOuter: 0,
            gapsInner: 0,
            activeStageID: 1,
            stages: [DesktopStage(id: 1)],
            windows: []
        )
    }

    // MARK: - T039 Test 1 : full restoration après kill simulé

    func testFullRestorationAfterReload() async throws {
        let r1 = makeRegistry()
        await r1.load()

        let d1 = makeDesktop1()
        let d2 = makeDesktop2()
        let d3 = makeDesktop3()

        try await r1.save(d1)
        try await r1.save(d2)
        try await r1.save(d3)
        await r1.setCurrent(id: 2)
        try await r1.saveCurrentID()

        // "Kill" simulé : nouveau registry depuis le même configDir
        let r2 = makeRegistry()
        await r2.load()

        // Vérifier currentID
        let currentID = await r2.currentID
        XCTAssertEqual(currentID, 2, "currentID doit être restauré à 2")

        // Desktop 1 : labels, layout, gaps, stages, windows
        let rd1 = await r2.desktop(id: 1)
        XCTAssertNotNil(rd1)
        XCTAssertEqual(rd1?.label, "code")
        XCTAssertEqual(rd1?.layout, .bsp)
        XCTAssertEqual(rd1?.gapsOuter, 12)
        XCTAssertEqual(rd1?.gapsInner, 6)
        XCTAssertEqual(rd1?.activeStageID, 2)
        XCTAssertEqual(rd1?.stages.count, 2)
        XCTAssertEqual(rd1?.stages.first?.label, "dev")
        XCTAssertEqual(rd1?.windows.count, 3)

        // Desktop 1 : expectedFrame préservée
        let w100 = rd1?.windows.first(where: { $0.cgwid == 100 })
        XCTAssertEqual(w100?.expectedFrame, CGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertEqual(w100?.bundleID, "com.apple.Terminal")

        // Desktop 2
        let rd2 = await r2.desktop(id: 2)
        XCTAssertEqual(rd2?.label, "comm")
        XCTAssertEqual(rd2?.layout, .masterStack)
        XCTAssertEqual(rd2?.windows.count, 1)
        XCTAssertEqual(rd2?.windows.first?.cgwid, 400)

        // Desktop 3 : floating, pas de label, pas de fenêtres
        let rd3 = await r2.desktop(id: 3)
        XCTAssertNil(rd3?.label)
        XCTAssertEqual(rd3?.layout, .floating)
        XCTAssertEqual(rd3?.gapsOuter, 0)
        XCTAssertTrue(rd3?.windows.isEmpty ?? false)
    }

    // MARK: - T039 Test 2 : stages préservés per-desktop

    func testStagesPerDesktopPreserved() async throws {
        let r1 = makeRegistry()
        await r1.load()

        let d1 = makeDesktop1()  // activeStageID=2, 2 stages
        let d2 = makeDesktop2()  // activeStageID=1, 1 stage
        try await r1.save(d1)
        try await r1.save(d2)

        let r2 = makeRegistry()
        await r2.load()

        let rd1 = await r2.desktop(id: 1)
        XCTAssertEqual(rd1?.activeStageID, 2)
        let stageIDs1 = rd1?.stages.map { $0.id } ?? []
        XCTAssertEqual(Set(stageIDs1), Set([1, 2]))

        let rd2 = await r2.desktop(id: 2)
        XCTAssertEqual(rd2?.activeStageID, 1)
        XCTAssertEqual(rd2?.stages.count, 1)
    }

    // MARK: - T039 Test 3 : saveAll() persiste tous les desktops

    func testSaveAllPersistsEverything() async throws {
        let r1 = makeRegistry()
        await r1.load()

        // Muter via save individuel (saveAll iterates desktops map)
        try await r1.save(makeDesktop1())
        try await r1.save(makeDesktop2())
        try await r1.save(makeDesktop3())
        await r1.setCurrent(id: 3)
        try await r1.saveAll()

        let r2 = makeRegistry()
        await r2.load()

        let currentID = await r2.currentID
        XCTAssertEqual(currentID, 3)

        let d2 = await r2.desktop(id: 2)
        XCTAssertEqual(d2?.label, "comm")

        let d3 = await r2.desktop(id: 3)
        XCTAssertEqual(d3?.layout, .floating)
    }
}
