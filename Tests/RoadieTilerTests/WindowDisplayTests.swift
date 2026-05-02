import XCTest
import RoadieCore
@testable import RoadieTiler

// MARK: - WindowDisplayTests (SPEC-012 T024, T025)
//
// Tests unitaires de `LayoutEngine.moveWindow` (T021).
// LayoutEngine est @MainActor — la classe doit l'être aussi.

@MainActor
final class WindowDisplayTests: XCTestCase {

    private let display1ID: CGDirectDisplayID = 2001
    private let display2ID: CGDirectDisplayID = 2002

    override func setUp() {
        super.setUp()
        BSPTiler.register()
        MasterStackTiler.register()
    }

    override func tearDown() {
        TilerRegistry.reset()
        super.tearDown()
    }

    // MARK: T024 : déplacement entre displays

    func test_moveWindow_transfers_leaf_to_dst_root() throws {
        let registry = WindowRegistry()
        let engine = try LayoutEngine(registry: registry)

        engine.insertWindow(10, focusedID: nil, displayID: display1ID)
        engine.insertWindow(20, focusedID: nil, displayID: display2ID)

        // Avant : wid10 dans display1, wid20 dans display2.
        let root1Before = engine.workspace.rootsByDisplay[display1ID]!
        let root2Before = engine.workspace.rootsByDisplay[display2ID]!
        XCTAssertNotNil(TreeNode.find(windowID: 10, in: root1Before), "wid10 doit être dans display1 avant move")
        XCTAssertNil(TreeNode.find(windowID: 10, in: root2Before), "wid10 ne doit pas être dans display2 avant move")

        let moved = engine.moveWindow(10, fromDisplay: display1ID, toDisplay: display2ID)
        XCTAssertTrue(moved, "moveWindow doit retourner true")

        // Après : wid10 doit être dans display2, pas dans display1.
        let root1After = engine.workspace.rootsByDisplay[display1ID]!
        let root2After = engine.workspace.rootsByDisplay[display2ID]!
        XCTAssertNil(TreeNode.find(windowID: 10, in: root1After), "wid10 doit avoir quitté display1")
        XCTAssertNotNil(TreeNode.find(windowID: 10, in: root2After), "wid10 doit être dans display2")
        // wid20 reste intact.
        XCTAssertNotNil(TreeNode.find(windowID: 20, in: root2After), "wid20 doit rester dans display2")
    }

    func test_moveWindow_preserves_visibility() throws {
        let registry = WindowRegistry()
        let engine = try LayoutEngine(registry: registry)

        engine.insertWindow(11, focusedID: nil, displayID: display1ID)
        // Marquer invisible (minimisée).
        _ = engine.setLeafVisible(11, false)

        let moved = engine.moveWindow(11, fromDisplay: display1ID, toDisplay: display2ID)
        XCTAssertTrue(moved)

        let root2 = engine.workspace.rootsByDisplay[display2ID]!
        let leaf = TreeNode.find(windowID: 11, in: root2)
        XCTAssertNotNil(leaf, "wid11 doit être dans display2")
        XCTAssertFalse(leaf!.isVisible, "la visibilité (false) doit être préservée après move")
    }

    func test_moveWindow_creates_dst_root_if_absent() throws {
        let registry = WindowRegistry()
        let engine = try LayoutEngine(registry: registry)

        engine.insertWindow(30, focusedID: nil, displayID: display1ID)
        // display2 n'existe pas encore dans rootsByDisplay.
        XCTAssertNil(engine.workspace.rootsByDisplay[display2ID], "display2 ne doit pas exister avant move")

        let moved = engine.moveWindow(30, fromDisplay: display1ID, toDisplay: display2ID)
        XCTAssertTrue(moved)
        XCTAssertNotNil(engine.workspace.rootsByDisplay[display2ID], "display2 doit être créé par moveWindow")

        let root2 = engine.workspace.rootsByDisplay[display2ID]!
        XCTAssertNotNil(TreeNode.find(windowID: 30, in: root2), "wid30 doit être dans display2")
    }

    // MARK: T025 : selector invalide (hors range) → false

    func test_moveWindow_unknown_src_returns_false() throws {
        let registry = WindowRegistry()
        let engine = try LayoutEngine(registry: registry)

        engine.insertWindow(40, focusedID: nil, displayID: display1ID)

        // display2 est inconnu comme src (wid40 n'y est pas).
        let result = engine.moveWindow(40, fromDisplay: display2ID, toDisplay: display1ID)
        XCTAssertFalse(result, "moveWindow avec src inconnu doit retourner false")

        // wid40 doit rester dans display1 inchangé.
        let root1 = engine.workspace.rootsByDisplay[display1ID]!
        XCTAssertNotNil(TreeNode.find(windowID: 40, in: root1), "wid40 ne doit pas disparaître")
    }

    func test_moveWindow_wid_not_in_src_returns_false() throws {
        let registry = WindowRegistry()
        let engine = try LayoutEngine(registry: registry)

        engine.insertWindow(50, focusedID: nil, displayID: display1ID)
        engine.insertWindow(60, focusedID: nil, displayID: display2ID)

        // wid50 est dans display1, pas display2 — tentative de move depuis display2.
        let result = engine.moveWindow(50, fromDisplay: display2ID, toDisplay: display1ID)
        XCTAssertFalse(result, "moveWindow avec wid absent du src doit retourner false")
    }

    // MARK: clearDisplayRoot / initDisplayRoot

    func test_clearDisplayRoot_removes_root() throws {
        let registry = WindowRegistry()
        let engine = try LayoutEngine(registry: registry)

        engine.insertWindow(70, focusedID: nil, displayID: display1ID)
        XCTAssertNotNil(engine.workspace.rootsByDisplay[display1ID])

        engine.clearDisplayRoot(for: display1ID)
        XCTAssertNil(engine.workspace.rootsByDisplay[display1ID], "clearDisplayRoot doit supprimer le root")
    }

    func test_initDisplayRoot_creates_root_once() throws {
        let registry = WindowRegistry()
        let engine = try LayoutEngine(registry: registry)

        XCTAssertNil(engine.workspace.rootsByDisplay[display2ID], "display2 doit être absent initialement")
        engine.initDisplayRoot(for: display2ID)
        XCTAssertNotNil(engine.workspace.rootsByDisplay[display2ID], "initDisplayRoot doit créer le root")

        // Un deuxième appel ne doit pas écraser le root existant.
        let root = engine.workspace.rootsByDisplay[display2ID]!
        engine.insertWindow(80, focusedID: nil, displayID: display2ID)
        engine.initDisplayRoot(for: display2ID)
        XCTAssertTrue(engine.workspace.rootsByDisplay[display2ID]! === root,
                      "initDisplayRoot ne doit pas écraser un root existant")
    }
}
