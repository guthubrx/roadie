import XCTest
import RoadieCore
@testable import RoadieTiler

// MARK: - T019 : tests multi-display LayoutEngine (SC-001, FR-024)
//
// LayoutEngine et WindowRegistry sont @MainActor — la classe de test doit l'être aussi.

@MainActor
final class LayoutEngineMultiDisplayTests: XCTestCase {

    private let display1ID: CGDirectDisplayID = 1001
    private let display2ID: CGDirectDisplayID = 1002
    private let rect1 = CGRect(x: 0, y: 0, width: 1280, height: 800)
    private let rect2 = CGRect(x: 1280, y: 0, width: 2560, height: 1440)

    override func setUp() {
        super.setUp()
        BSPTiler.register()
        MasterStackTiler.register()
    }

    override func tearDown() {
        TilerRegistry.reset()
        super.tearDown()
    }

    // MARK: - SC-001 : chaque fenêtre tient dans le rect de son écran

    func test_insertWindow_explicit_displayID_routes_correctly() throws {
        let registry = WindowRegistry()
        let engine = try LayoutEngine(registry: registry)

        engine.insertWindow(1, focusedID: nil, displayID: display1ID)
        engine.insertWindow(2, focusedID: nil, displayID: display2ID)

        let root1 = engine.workspace.rootsByDisplay[display1ID]
        let root2 = engine.workspace.rootsByDisplay[display2ID]
        XCTAssertNotNil(root1, "root display1 doit exister")
        XCTAssertNotNil(root2, "root display2 doit exister")
        XCTAssertNotNil(TreeNode.find(windowID: 1, in: root1!), "wid1 dans root1")
        XCTAssertNotNil(TreeNode.find(windowID: 2, in: root2!), "wid2 dans root2")
        XCTAssertNil(TreeNode.find(windowID: 1, in: root2!), "wid1 absent de root2")
        XCTAssertNil(TreeNode.find(windowID: 2, in: root1!), "wid2 absent de root1")
    }

    func test_tiler_layout_produces_frames_within_display_rect() throws {
        let registry = WindowRegistry()
        let engine = try LayoutEngine(registry: registry)

        engine.insertWindow(1, focusedID: nil, displayID: display1ID)
        engine.insertWindow(2, focusedID: nil, displayID: display1ID)
        engine.insertWindow(3, focusedID: nil, displayID: display2ID)
        engine.insertWindow(4, focusedID: nil, displayID: display2ID)

        // Layout manuel pour chaque display (simulation applyAll sans AX).
        let root1 = engine.workspace.rootsByDisplay[display1ID]!
        let root2 = engine.workspace.rootsByDisplay[display2ID]!
        let tiler = BSPTiler()
        let frames1 = tiler.layout(rect: rect1, root: root1)
        let frames2 = tiler.layout(rect: rect2, root: root2)

        // wid1 et wid2 doivent être dans rect1.
        for wid in [WindowID(1), WindowID(2)] {
            let frame = try XCTUnwrap(frames1[wid], "frame wid\(wid) introuvable display1")
            XCTAssertTrue(rect1.contains(frame), "wid\(wid) hors de rect1: \(frame)")
        }
        // wid3 et wid4 doivent être dans rect2.
        for wid in [WindowID(3), WindowID(4)] {
            let frame = try XCTUnwrap(frames2[wid], "frame wid\(wid) introuvable display2")
            XCTAssertTrue(rect2.contains(frame), "wid\(wid) hors de rect2: \(frame)")
        }
        // Pas de cross-display dans les frames.
        XCTAssertNil(frames2[1], "wid1 ne doit pas être dans display2")
        XCTAssertNil(frames2[2], "wid2 ne doit pas être dans display2")
        XCTAssertNil(frames1[3], "wid3 ne doit pas être dans display1")
        XCTAssertNil(frames1[4], "wid4 ne doit pas être dans display1")
    }

    // MARK: - FR-024 : compat mono-écran via rootNode getter

    func test_rootNode_getter_returns_primary_root() throws {
        let registry = WindowRegistry()
        let engine = try LayoutEngine(registry: registry)

        let primaryID = CGMainDisplayID()
        let rootViaPrimary = engine.workspace.rootsByDisplay[primaryID]
        let rootViaGetter  = engine.workspace.rootNode
        XCTAssertTrue(rootViaPrimary === rootViaGetter,
                      "rootNode doit pointer sur rootsByDisplay[CGMainDisplayID()]")
    }

    func test_insertWindow_no_displayID_falls_back_to_primary() throws {
        let registry = WindowRegistry()
        let engine = try LayoutEngine(registry: registry)

        // Sans displayID et sans frame connue → fallback CGMainDisplayID.
        engine.insertWindow(99, focusedID: nil)
        let primaryRoot = engine.workspace.rootsByDisplay[CGMainDisplayID()]!
        XCTAssertNotNil(TreeNode.find(windowID: 99, in: primaryRoot),
                        "wid99 doit être dans le root primary")
    }

    func test_setLeafVisible_finds_leaf_in_any_root() throws {
        let registry = WindowRegistry()
        let engine = try LayoutEngine(registry: registry)

        engine.insertWindow(10, focusedID: nil, displayID: display1ID)
        engine.insertWindow(20, focusedID: nil, displayID: display2ID)

        let found10 = engine.setLeafVisible(10, false)
        let found20 = engine.setLeafVisible(20, false)
        XCTAssertTrue(found10, "setLeafVisible wid10 doit retourner true")
        XCTAssertTrue(found20, "setLeafVisible wid20 doit retourner true")

        let notFound = engine.setLeafVisible(999, true)
        XCTAssertFalse(notFound, "setLeafVisible wid999 inexistant doit retourner false")
    }

    func test_removeWindow_removes_from_correct_display() throws {
        let registry = WindowRegistry()
        let engine = try LayoutEngine(registry: registry)

        engine.insertWindow(5, focusedID: nil, displayID: display1ID)
        engine.insertWindow(6, focusedID: nil, displayID: display2ID)
        engine.removeWindow(5)

        let root1 = engine.workspace.rootsByDisplay[display1ID]!
        let root2 = engine.workspace.rootsByDisplay[display2ID]!
        XCTAssertNil(TreeNode.find(windowID: 5, in: root1), "wid5 doit être retiré de root1")
        XCTAssertNotNil(TreeNode.find(windowID: 6, in: root2), "wid6 doit rester dans root2")
    }

    func test_setStrategy_rebuilds_all_roots() throws {
        let registry = WindowRegistry()
        let engine = try LayoutEngine(registry: registry)

        engine.insertWindow(1, focusedID: nil, displayID: display1ID)
        engine.insertWindow(2, focusedID: nil, displayID: display2ID)
        try engine.setStrategy(.masterStack)

        let root1 = engine.workspace.rootsByDisplay[display1ID]!
        let root2 = engine.workspace.rootsByDisplay[display2ID]!
        XCTAssertNotNil(TreeNode.find(windowID: 1, in: root1), "wid1 doit survivre à setStrategy")
        XCTAssertNotNil(TreeNode.find(windowID: 2, in: root2), "wid2 doit survivre à setStrategy")
    }
}
