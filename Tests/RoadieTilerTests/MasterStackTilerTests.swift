import XCTest
import RoadieCore
@testable import RoadieTiler

final class MasterStackTilerTests: XCTestCase {
    let rect = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func test_layout_single_window() {
        let tiler = MasterStackTiler()
        let root = TilingContainer(orientation: .horizontal)
        let leaf = WindowLeaf(windowID: 1)
        tiler.insert(leaf: leaf, near: nil, in: root)
        let frames = tiler.layout(rect: rect, root: root)
        XCTAssertEqual(frames[1], rect)
    }

    func test_layout_two_windows_master_left_stack_right() {
        let tiler = MasterStackTiler(masterRatio: 0.6)
        let root = TilingContainer(orientation: .horizontal)
        let l1 = WindowLeaf(windowID: 1)
        let l2 = WindowLeaf(windowID: 2)
        tiler.insert(leaf: l1, near: nil, in: root)
        tiler.insert(leaf: l2, near: nil, in: root)
        let frames = tiler.layout(rect: rect, root: root)
        // Master 60% à gauche, stack 40% à droite avec 1 leaf qui prend tout
        XCTAssertEqual(frames[1]?.width, 600)
        XCTAssertEqual(frames[2]?.width, 400)
        XCTAssertEqual(frames[2]?.height, 800)
    }

    func test_layout_three_windows_stack_split() {
        let tiler = MasterStackTiler(masterRatio: 0.6)
        let root = TilingContainer(orientation: .horizontal)
        for i in 1...3 {
            tiler.insert(leaf: WindowLeaf(windowID: WindowID(i)), near: nil, in: root)
        }
        let frames = tiler.layout(rect: rect, root: root)
        XCTAssertEqual(frames[1]?.width, 600)
        // Stack contient 2 leaves verticalement, chacune 400 px de haut, largeur 400
        XCTAssertEqual(frames[2]?.width, 400)
        XCTAssertEqual(frames[2]?.height, 400)
        XCTAssertEqual(frames[3]?.width, 400)
        XCTAssertEqual(frames[3]?.height, 400)
    }

    func test_remove_promotes_first_stack_to_master() {
        let tiler = MasterStackTiler()
        let root = TilingContainer(orientation: .horizontal)
        let l1 = WindowLeaf(windowID: 1)
        let l2 = WindowLeaf(windowID: 2)
        let l3 = WindowLeaf(windowID: 3)
        tiler.insert(leaf: l1, near: nil, in: root)
        tiler.insert(leaf: l2, near: nil, in: root)
        tiler.insert(leaf: l3, near: nil, in: root)
        // Retirer le master
        tiler.remove(leaf: l1, from: root)
        // Maintenant l2 devrait être le nouveau master
        XCTAssertEqual(root.allLeaves.count, 2)
    }

    func test_focus_master_to_stack() {
        let tiler = MasterStackTiler()
        let root = TilingContainer(orientation: .horizontal)
        let master = WindowLeaf(windowID: 1)
        let stackTop = WindowLeaf(windowID: 2)
        tiler.insert(leaf: master, near: nil, in: root)
        tiler.insert(leaf: stackTop, near: nil, in: root)
        // Right depuis master = stackTop
        let neighbor = tiler.focusNeighbor(of: master, direction: .right, in: root)
        XCTAssertNotNil(neighbor)
        XCTAssertEqual(neighbor?.windowID, 2)
    }

    func test_focus_stack_to_master() {
        let tiler = MasterStackTiler()
        let root = TilingContainer(orientation: .horizontal)
        let master = WindowLeaf(windowID: 1)
        let stackLeaf = WindowLeaf(windowID: 2)
        tiler.insert(leaf: master, near: nil, in: root)
        tiler.insert(leaf: stackLeaf, near: nil, in: root)
        // Left depuis stackLeaf = master
        let neighbor = tiler.focusNeighbor(of: stackLeaf, direction: .left, in: root)
        XCTAssertNotNil(neighbor)
        XCTAssertEqual(neighbor?.windowID, 1)
    }
}
