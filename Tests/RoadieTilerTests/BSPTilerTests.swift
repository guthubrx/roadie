import XCTest
import RoadieCore
@testable import RoadieTiler

final class BSPTilerTests: XCTestCase {
    let rect = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func test_layout_empty_root() {
        let tiler = BSPTiler()
        let root = TilingContainer(orientation: .horizontal)
        let frames = tiler.layout(rect: rect, root: root)
        XCTAssertEqual(frames.count, 0)
    }

    func test_layout_single_window_covers_full_rect() {
        let tiler = BSPTiler()
        let root = TilingContainer(orientation: .horizontal)
        let leaf = WindowLeaf(windowID: 1)
        root.append(leaf)
        let frames = tiler.layout(rect: rect, root: root)
        XCTAssertEqual(frames[1], rect)
    }

    func test_layout_two_windows_equal_horizontal_split() {
        let tiler = BSPTiler()
        let root = TilingContainer(orientation: .horizontal)
        root.append(WindowLeaf(windowID: 1))
        root.append(WindowLeaf(windowID: 2))
        let frames = tiler.layout(rect: rect, root: root)
        XCTAssertEqual(frames[1], CGRect(x: 0, y: 0, width: 500, height: 800))
        XCTAssertEqual(frames[2], CGRect(x: 500, y: 0, width: 500, height: 800))
    }

    func test_layout_two_windows_vertical_split() {
        let tiler = BSPTiler()
        let root = TilingContainer(orientation: .vertical)
        root.append(WindowLeaf(windowID: 1))
        root.append(WindowLeaf(windowID: 2))
        let frames = tiler.layout(rect: rect, root: root)
        XCTAssertEqual(frames[1], CGRect(x: 0, y: 0, width: 1000, height: 400))
        XCTAssertEqual(frames[2], CGRect(x: 0, y: 400, width: 1000, height: 400))
    }

    func test_layout_three_windows_with_weights() {
        let tiler = BSPTiler()
        let root = TilingContainer(orientation: .horizontal)
        root.append(WindowLeaf(windowID: 1, adaptiveWeight: 1))
        root.append(WindowLeaf(windowID: 2, adaptiveWeight: 2))
        root.append(WindowLeaf(windowID: 3, adaptiveWeight: 1))
        let frames = tiler.layout(rect: rect, root: root)
        // total weight = 4, ratios 1/4 2/4 1/4 = 250 500 250
        XCTAssertEqual(frames[1]?.width, 250)
        XCTAssertEqual(frames[2]?.width, 500)
        XCTAssertEqual(frames[3]?.width, 250)
    }

    func test_insert_into_empty_root() {
        let tiler = BSPTiler()
        let root = TilingContainer(orientation: .horizontal)
        let leaf = WindowLeaf(windowID: 42)
        tiler.insert(leaf: leaf, near: nil, in: root)
        XCTAssertEqual(root.children.count, 1)
        XCTAssertTrue(root.children[0] === leaf)
    }

    func test_insert_idempotent() {
        let tiler = BSPTiler()
        let root = TilingContainer(orientation: .horizontal)
        let leaf = WindowLeaf(windowID: 42)
        tiler.insert(leaf: leaf, near: nil, in: root)
        // Insertion d'un autre leaf avec le même windowID = idempotence
        let dupe = WindowLeaf(windowID: 42)
        tiler.insert(leaf: dupe, near: nil, in: root)
        XCTAssertEqual(root.children.count, 1, "duplicate insert should be no-op")
    }

    func test_insert_after_target_creates_subcontainer() {
        let tiler = BSPTiler()
        let root = TilingContainer(orientation: .horizontal)
        let target = WindowLeaf(windowID: 1)
        root.append(target)
        let newLeaf = WindowLeaf(windowID: 2)
        tiler.insert(leaf: newLeaf, near: target, in: root)
        // BSP : un sous-container avec orientation opposée à root
        XCTAssertEqual(root.children.count, 1)
        guard let sub = root.children[0] as? TilingContainer else {
            XCTFail("expected sub-container"); return
        }
        XCTAssertEqual(sub.orientation, .vertical)   // root horizontal → sub vertical
        XCTAssertEqual(sub.children.count, 2)
    }

    func test_remove_normalizes_parent() {
        let tiler = BSPTiler()
        let root = TilingContainer(orientation: .horizontal)
        let l1 = WindowLeaf(windowID: 1)
        let l2 = WindowLeaf(windowID: 2)
        let l3 = WindowLeaf(windowID: 3)
        tiler.insert(leaf: l1, near: nil, in: root)
        tiler.insert(leaf: l2, near: l1, in: root)
        tiler.insert(leaf: l3, near: l2, in: root)
        // Retirer l3 : le sous-container avec l2+l3 doit collapse en l2 seul
        tiler.remove(leaf: l3, from: root)
        // Après normalize, on revient à 2 leaves directes ou 1 container avec 2 leaves
        XCTAssertEqual(root.allLeaves.count, 2)
    }

    func test_layout_skips_invisible_leaves() {
        // Une leaf marquée invisible (minimisée) ne consomme pas d'espace.
        // Les leaves visibles se redistribuent l'espace.
        let tiler = BSPTiler()
        let root = TilingContainer(orientation: .horizontal)
        let l1 = WindowLeaf(windowID: 1)
        let l2 = WindowLeaf(windowID: 2)
        let l3 = WindowLeaf(windowID: 3)
        root.append(l1)
        root.append(l2)
        root.append(l3)
        // Toutes visibles → 3 colonnes égales sur 999 px.
        var frames = tiler.layout(rect: CGRect(x: 0, y: 0, width: 999, height: 800), root: root)
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[1]?.width, 333)
        XCTAssertEqual(frames[2]?.width, 333)
        XCTAssertEqual(frames[3]?.width, 333)
        // Marquer l2 invisible → l1 et l3 partagent 999 px en deux.
        l2.isVisible = false
        frames = tiler.layout(rect: CGRect(x: 0, y: 0, width: 999, height: 800), root: root)
        XCTAssertEqual(frames.count, 2, "l2 should be skipped from layout")
        XCTAssertNil(frames[2])
        XCTAssertEqual(frames[1]?.width, 499.5)
        XCTAssertEqual(frames[3]?.width, 499.5)
        // Re-visible : 3 colonnes égales reviennent. Position de l2 préservée (au milieu).
        l2.isVisible = true
        frames = tiler.layout(rect: CGRect(x: 0, y: 0, width: 999, height: 800), root: root)
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[2]?.origin.x, 333, "l2 should reappear at its original position (middle)")
    }

    func test_focus_neighbor_at_edge_returns_nil() {
        let tiler = BSPTiler()
        let root = TilingContainer(orientation: .horizontal)
        let l1 = WindowLeaf(windowID: 1)
        let l2 = WindowLeaf(windowID: 2)
        root.append(l1)
        root.append(l2)
        // Pas de voisin à gauche de l1
        XCTAssertNil(tiler.focusNeighbor(of: l1, direction: .left, in: root))
        // Voisin à droite de l1 = l2
        XCTAssertTrue(tiler.focusNeighbor(of: l1, direction: .right, in: root) === l2)
    }
}
