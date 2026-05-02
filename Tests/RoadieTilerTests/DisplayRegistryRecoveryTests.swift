import XCTest
import RoadieCore
@testable import RoadieTiler

// MARK: - DisplayRegistryRecoveryTests (SPEC-012 T030, T031)
//
// Teste la logique de recovery branch/débranch :
// - clampFrameToVisible (helper pur)
// - moveWindow + clearDisplayRoot + initDisplayRoot (cycle connect/disconnect)
//
// LayoutEngine est @MainActor.

@MainActor
final class DisplayRegistryRecoveryTests: XCTestCase {

    private let display1ID: CGDirectDisplayID = 3001
    private let display2ID: CGDirectDisplayID = 3002
    private let primaryFrame = CGRect(x: 0,    y: 0, width: 1280, height: 800)
    private let externalFrame = CGRect(x: 1280, y: 0, width: 2560, height: 1440)

    override func setUp() {
        super.setUp()
        BSPTiler.register()
        MasterStackTiler.register()
    }

    override func tearDown() {
        TilerRegistry.reset()
        super.tearDown()
    }

    // MARK: T030a : clampFrameToVisible — helper pur

    func test_clampFrame_window_fits() {
        let visible = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let frame = CGRect(x: 200, y: 100, width: 400, height: 300)
        let result = clampFrameToVisible(frame, in: visible)
        XCTAssertTrue(visible.contains(result),
                      "Un frame qui tient doit rester dans la zone visible")
    }

    func test_clampFrame_window_too_wide() {
        let visible = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let frame = CGRect(x: 0, y: 0, width: 1300, height: 400)
        let result = clampFrameToVisible(frame, in: visible)
        XCTAssertLessThanOrEqual(result.width, visible.width,
                                 "La largeur doit être réduite pour tenir dans visible")
    }

    func test_clampFrame_window_too_tall() {
        let visible = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let frame = CGRect(x: 0, y: 0, width: 400, height: 850)
        let result = clampFrameToVisible(frame, in: visible)
        XCTAssertLessThanOrEqual(result.height, visible.height,
                                 "La hauteur doit être réduite pour tenir dans visible")
    }

    func test_clampFrame_window_out_of_bounds_right() {
        let visible = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let frame = CGRect(x: 1200, y: 100, width: 400, height: 300)
        let result = clampFrameToVisible(frame, in: visible)
        XCTAssertLessThanOrEqual(result.maxX, visible.maxX + 1,
                                 "Le bord droit ne doit pas dépasser visible.maxX")
    }

    func test_clampFrame_window_out_of_bounds_bottom() {
        let visible = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let frame = CGRect(x: 100, y: 750, width: 400, height: 300)
        let result = clampFrameToVisible(frame, in: visible)
        XCTAssertLessThanOrEqual(result.maxY, visible.maxY + 1,
                                 "Le bord bas ne doit pas dépasser visible.maxY")
    }

    // MARK: T030b : migration des fenêtres au débranch d'un display

    func test_migration_windows_moved_to_primary_on_disconnect() throws {
        let registry = WindowRegistry()
        let engine = try LayoutEngine(registry: registry)

        // Fenêtres sur le display externe.
        engine.insertWindow(101, focusedID: nil, displayID: display2ID)
        engine.insertWindow(102, focusedID: nil, displayID: display2ID)
        // Une fenêtre sur le primary.
        engine.insertWindow(100, focusedID: nil, displayID: display1ID)

        // Simuler la migration : moveWindow + clearDisplayRoot.
        let wids = engine.workspace.rootsByDisplay[display2ID]!.allLeaves.map { $0.windowID }
        XCTAssertEqual(Set(wids), Set([101, 102]), "Les deux wids doivent être sur display2")

        for wid in wids {
            _ = engine.moveWindow(wid, fromDisplay: display2ID, toDisplay: display1ID)
        }
        engine.clearDisplayRoot(for: display2ID)

        // Vérifications post-migration.
        XCTAssertNil(engine.workspace.rootsByDisplay[display2ID],
                     "Le root display2 doit être supprimé après clearDisplayRoot")

        let root1 = engine.workspace.rootsByDisplay[display1ID]!
        for wid in wids {
            XCTAssertNotNil(TreeNode.find(windowID: wid, in: root1),
                            "wid\(wid) doit être migré vers display1")
        }
        // La fenêtre primaire doit rester.
        XCTAssertNotNil(TreeNode.find(windowID: 100, in: root1), "wid100 doit rester dans display1")
    }

    func test_init_display_root_on_connect() throws {
        let registry = WindowRegistry()
        let engine = try LayoutEngine(registry: registry)

        // Le display2 n'existe pas encore.
        XCTAssertNil(engine.workspace.rootsByDisplay[display2ID])

        // Simuler le branchement.
        engine.initDisplayRoot(for: display2ID)
        let root2 = engine.workspace.rootsByDisplay[display2ID]
        XCTAssertNotNil(root2, "Le root display2 doit être créé au branchement")
        XCTAssertEqual(root2!.children.count, 0, "Le root doit être vide au branchement")
    }

    // MARK: T031 : perf — 10 cycles connect/disconnect < 5 s

    func test_connect_disconnect_cycles_perf() throws {
        let registry = WindowRegistry()
        let engine = try LayoutEngine(registry: registry)

        // Pré-peupler le display primaire avec quelques fenêtres.
        for wid in WindowID(200)..<WindowID(210) {
            engine.insertWindow(wid, focusedID: nil, displayID: display1ID)
        }

        let start = Date()
        let cycleCount = 10

        for cycle in 0..<cycleCount {
            // Branchement display2 avec 2 fenêtres.
            engine.initDisplayRoot(for: display2ID)
            let wid1 = WindowID(300 + UInt32(cycle) * 2)
            let wid2 = WindowID(300 + UInt32(cycle) * 2 + 1)
            engine.insertWindow(wid1, focusedID: nil, displayID: display2ID)
            engine.insertWindow(wid2, focusedID: nil, displayID: display2ID)

            // Débranch : migrer vers primary.
            let wids = engine.workspace.rootsByDisplay[display2ID]?.allLeaves.map { $0.windowID } ?? []
            for wid in wids {
                _ = engine.moveWindow(wid, fromDisplay: display2ID, toDisplay: display1ID)
            }
            engine.clearDisplayRoot(for: display2ID)

            // Nettoyage pour le prochain cycle : retirer les wids migrés du primary.
            for wid in wids {
                engine.removeWindow(wid)
            }
        }

        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 5.0,
                          "10 cycles connect/disconnect doivent s'exécuter en < 5 s (SC-003), elapsed: \(elapsed)")

        // Vérifier l'absence de racines fantômes (SC-006).
        XCTAssertNil(engine.workspace.rootsByDisplay[display2ID],
                     "Pas de root fantôme display2 après 10 cycles")
    }
}

// MARK: - Helper pur extrait pour tests (équivalent de Daemon.clampFrameToVisible)

/// Copie exacte de la logique dans Daemon.clampFrameToVisible (T027).
/// Testée ici en isolation sans dépendance sur roadied.
private func clampFrameToVisible(_ frame: CGRect, in visible: CGRect) -> CGRect {
    var origin = frame.origin
    var size = frame.size
    if size.width > visible.width * 0.95 { size.width = visible.width * 0.8 }
    if size.height > visible.height * 0.95 { size.height = visible.height * 0.8 }
    if origin.x < visible.minX { origin.x = visible.minX + 10 }
    if origin.y < visible.minY { origin.y = visible.minY + 10 }
    if origin.x + size.width > visible.maxX { origin.x = visible.maxX - size.width - 10 }
    if origin.y + size.height > visible.maxY { origin.y = visible.maxY - size.height - 10 }
    return CGRect(origin: origin, size: size)
}
