import XCTest
import RoadieCore
@testable import RoadieTiler

final class TreeNodeTests: XCTestCase {
    func test_leaf_init_default_weight() {
        let leaf = WindowLeaf(windowID: 1)
        XCTAssertEqual(leaf.adaptiveWeight, 1.0, accuracy: 0.0001)
        XCTAssertNil(leaf.parent)
    }

    func test_container_append_sets_parent() {
        let root = TilingContainer(orientation: .horizontal)
        let leaf = WindowLeaf(windowID: 42)
        root.append(leaf)
        XCTAssertTrue(leaf.parent === root)
        XCTAssertEqual(root.children.count, 1)
    }

    func test_container_remove_clears_parent() {
        let root = TilingContainer(orientation: .horizontal)
        let leaf = WindowLeaf(windowID: 42)
        root.append(leaf)
        root.remove(leaf)
        XCTAssertNil(leaf.parent)
        XCTAssertEqual(root.children.count, 0)
    }

    func test_index_of() {
        let root = TilingContainer(orientation: .vertical)
        let leaves = (1...3).map { WindowLeaf(windowID: WindowID($0)) }
        leaves.forEach { root.append($0) }
        XCTAssertEqual(root.index(of: leaves[0]), 0)
        XCTAssertEqual(root.index(of: leaves[2]), 2)
    }

    func test_allLeaves_recursive() {
        let root = TilingContainer(orientation: .horizontal)
        let leaf1 = WindowLeaf(windowID: 1)
        let sub = TilingContainer(orientation: .vertical)
        let leaf2 = WindowLeaf(windowID: 2)
        let leaf3 = WindowLeaf(windowID: 3)
        sub.append(leaf2)
        sub.append(leaf3)
        root.append(leaf1)
        root.append(sub)
        let leaves = root.allLeaves
        XCTAssertEqual(leaves.count, 3)
        XCTAssertEqual(Set(leaves.map { $0.windowID }), Set([1, 2, 3]))
    }

    func test_normalize_collapses_single_child() {
        let root = TilingContainer(orientation: .horizontal)
        let sub = TilingContainer(orientation: .vertical)
        let leaf = WindowLeaf(windowID: 99)
        sub.append(leaf)
        root.append(sub)
        sub.normalize()
        // Après normalize, le leaf doit être enfant direct de root.
        XCTAssertTrue(leaf.parent === root)
        XCTAssertFalse(root.children.contains { $0 === sub })
    }

    func test_normalize_removes_empty_container() {
        let root = TilingContainer(orientation: .horizontal)
        let leaf = WindowLeaf(windowID: 1)
        let empty = TilingContainer(orientation: .vertical)
        root.append(leaf)
        root.append(empty)
        empty.normalize()
        XCTAssertEqual(root.children.count, 1)
        XCTAssertTrue(root.children[0] === leaf)
    }

    func test_find_window_id() {
        let root = TilingContainer(orientation: .horizontal)
        let leaf1 = WindowLeaf(windowID: 1)
        let sub = TilingContainer(orientation: .vertical)
        let leaf2 = WindowLeaf(windowID: 42)
        sub.append(leaf2)
        root.append(leaf1)
        root.append(sub)
        let found = TreeNode.find(windowID: 42, in: root)
        XCTAssertNotNil(found)
        XCTAssertTrue(found === leaf2)
        XCTAssertNil(TreeNode.find(windowID: 9999, in: root))
    }
}
