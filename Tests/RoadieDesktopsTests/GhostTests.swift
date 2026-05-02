import XCTest
import CoreGraphics
@testable import RoadieDesktops
import RoadieCore

/// Test anti-fantôme : après 100 bascules, aucune fenêtre n'est laissée offscreen
/// à tort — les fenêtres du desktop courant sont toujours à leur expectedFrame (SC-002).
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

        let mover = MockWindowMover()
        let bus = DesktopEventBus()
        let cfg = DesktopSwitcherConfig(count: 3, backAndForth: false)
        let switcher = DesktopSwitcher(
            registry: registry, mover: mover, bus: bus, config: cfg
        )

        // 100 bascules entre desktops 1, 2, 3
        for i in 0..<100 {
            let target = (i % 3) + 1
            let currentID = await registry.currentID
            if target == currentID { continue }
            try await switcher.switch(to: target)
        }

        // Après stabilisation, vérifier que les fenêtres du desktop courant
        // ne sont PAS offscreen (leur dernière position doit être leur expectedFrame)
        let finalCurrentID = await registry.currentID
        let finalDesktop = await registry.desktop(id: finalCurrentID)
        let moves = await mover.moves
        let offscreenThreshold: CGFloat = -10000

        for win in finalDesktop?.windows ?? [] {
            let lastPos = moves.last(where: { $0.cgwid == win.cgwid })?.point
            if let pos = lastPos {
                XCTAssertGreaterThan(pos.x, offscreenThreshold,
                    "Window \(win.cgwid) of current desktop \(finalCurrentID) is offscreen at x=\(pos.x)")
                XCTAssertGreaterThan(pos.y, offscreenThreshold,
                    "Window \(win.cgwid) of current desktop \(finalCurrentID) is offscreen at y=\(pos.y)")
            }
        }

        // Vérifier que les fenêtres des autres desktops SONT offscreen
        for (id, wins) in desktops where id != finalCurrentID {
            for win in wins {
                let lastPos = moves.last(where: { $0.cgwid == win.cgwid })?.point
                if let pos = lastPos {
                    XCTAssertLessThanOrEqual(pos.x, offscreenThreshold,
                        "Window \(win.cgwid) of desktop \(id) should be offscreen, got x=\(pos.x)")
                }
            }
        }
    }
}
