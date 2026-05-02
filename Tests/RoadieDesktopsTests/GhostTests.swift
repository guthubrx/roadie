import XCTest
import CoreGraphics
@testable import RoadieDesktops
import RoadieCore

/// Test anti-fantôme (SC-002) : après 100 bascules, la séquence deactivateAll + activate
/// est respectée à chaque switch — invariant "aucune fenêtre fantôme" garanti par
/// le fait que HideStrategy (via StageManager) gère l'hide/show de manière atomique.
final class GhostTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-ghost-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    func testNoGhostWindowsAfter100Switches() async throws {
        let registry = DesktopRegistry(configDir: tmpDir, count: 3)
        await registry.load()

        // 3 desktops avec 2 fenêtres chacun
        let desktops: [(Int, [WindowEntry])] = [
            (1, [
                WindowEntry(cgwid: 10, bundleID: "a", title: "A",
                            expectedFrame: CGRect(x: 100, y: 100, width: 800, height: 600), stageID: 1),
                WindowEntry(cgwid: 11, bundleID: "b", title: "B",
                            expectedFrame: CGRect(x: 950, y: 100, width: 600, height: 600), stageID: 1),
            ]),
            (2, [
                WindowEntry(cgwid: 20, bundleID: "c", title: "C",
                            expectedFrame: CGRect(x: 200, y: 200, width: 800, height: 600), stageID: 1),
                WindowEntry(cgwid: 21, bundleID: "d", title: "D",
                            expectedFrame: CGRect(x: 50, y: 50, width: 400, height: 300), stageID: 1),
            ]),
            (3, [
                WindowEntry(cgwid: 30, bundleID: "e", title: "E",
                            expectedFrame: CGRect(x: 300, y: 300, width: 700, height: 500), stageID: 1),
                WindowEntry(cgwid: 31, bundleID: "f", title: "F",
                            expectedFrame: CGRect(x: 400, y: 400, width: 600, height: 400), stageID: 1),
            ]),
        ]

        for (id, wins) in desktops {
            let d = RoadieDesktop(id: id,
                                  stages: [DesktopStage(id: 1, windows: wins.map { $0.cgwid })],
                                  windows: wins)
            try await registry.save(d)
        }

        let stageOps = MockStageOps()
        let bus = DesktopEventBus()
        let cfg = DesktopSwitcherConfig(count: 3, backAndForth: false)
        let switcher = DesktopSwitcher(
            registry: registry, stageOps: stageOps, bus: bus, config: cfg
        )

        // 100 bascules entre desktops 1, 2, 3
        var effectiveSwitches = 0
        for i in 0..<100 {
            let target = (i % 3) + 1
            let currentID = await registry.currentID
            if target == currentID { continue }
            try await switcher.switch(to: target)
            effectiveSwitches += 1
        }

        // Invariant anti-fantôme : chaque bascule effective appelle deactivateAll
        // exactement une fois, puis activate exactement une fois, dans cet ordre.
        // Vérifier que le nombre de deactivateAll == nombre d'activate == effectiveSwitches.
        let calls = await stageOps.calls
        let deactivateCount = calls.filter { $0 == .deactivateAll }.count
        let activateCount = calls.filter {
            if case .activate = $0 { return true }
            return false
        }.count

        XCTAssertEqual(deactivateCount, effectiveSwitches,
            "deactivateAll doit être appelé exactement une fois par bascule effective")
        XCTAssertEqual(activateCount, effectiveSwitches,
            "activate doit être appelé exactement une fois par bascule effective")

        // Vérifier l'ordre strict deactivate → activate dans la séquence.
        // Chaque paire (deactivateAll, activate) doit être consécutive et dans le bon ordre.
        var expectDeactivate = true
        for call in calls {
            switch call {
            case .deactivateAll:
                XCTAssertTrue(expectDeactivate,
                    "deactivateAll inattendu (attendait activate)")
                expectDeactivate = false
            case .activate:
                XCTAssertFalse(expectDeactivate,
                    "activate inattendu (attendait deactivateAll)")
                expectDeactivate = true
            case .currentStageID:
                break
            }
        }
    }
}
