import CoreGraphics
import Foundation
import Testing
import RoadieCore
import RoadieTiler

@Suite
struct BSPTreeTests {
    private func win(_ n: Int) -> WindowID { WindowID(rawValue: UInt32(n)) }
    private let container = CGRect(x: 0, y: 0, width: 1000, height: 600)

    @Test
    func placeSingleLeafFillsContainer() {
        let tree = BSPTree.leaf(win(1))
        let p = tree.place(in: container, innerGap: 0)
        #expect(p[win(1)] == container.integral)
    }

    @Test
    func placeVerticalSplitFiftyFifty() {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2)))
        let p = tree.place(in: container, innerGap: 0)
        #expect(p[win(1)] == CGRect(x: 0, y: 0, width: 500, height: 600))
        #expect(p[win(2)] == CGRect(x: 500, y: 0, width: 500, height: 600))
    }

    @Test
    func placeHorizontalSplitStacks() {
        let tree = BSPTree.split(orientation: .horizontal, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2)))
        let p = tree.place(in: container, innerGap: 0)
        #expect(p[win(1)] == CGRect(x: 0, y: 0, width: 1000, height: 300))
        #expect(p[win(2)] == CGRect(x: 0, y: 300, width: 1000, height: 300))
    }

    @Test
    func windowIDsAreInOrder() {
        let tree = BSPTree.split(
            orientation: .vertical, ratio: 0.5,
            first: .leaf(win(1)),
            second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(win(2)), second: .leaf(win(3)))
        )
        #expect(tree.windowIDs == [win(1), win(2), win(3)])
    }

    // MARK: - Insertion (cœur yabai)

    @Test
    func insertIntoEmptyBecomesRoot() {
        let tree = BSPTree.empty.inserting(win(1), nextTo: nil, side: .right, containerIsWide: true)
        #expect(tree == .leaf(win(1)))
    }

    @Test
    func insertOnFocusedLeafSplitsOnlyThatLeaf() {
        // Arbre : [w1 | w2]. Focus w1. Insérer w3 à droite.
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2)))
        let after = tree.inserting(win(3), nextTo: win(1), side: .right, containerIsWide: true)

        // w2 ne doit pas avoir bougé dans la structure : il reste le `second` de la racine.
        guard case .split(_, _, let first, let second) = after else {
            Issue.record("expected split root"); return
        }
        #expect(second == .leaf(win(2)))
        // w1 a été divisé avec w3.
        #expect(first.windowIDs == [win(1), win(3)])
        #expect(after.windowIDs == [win(1), win(3), win(2)])
    }

    @Test
    func insertSideRightPlacesNewWindowSecond() {
        let tree = BSPTree.leaf(win(1)).inserting(win(2), nextTo: win(1), side: .right, containerIsWide: true)
        guard case .split(_, _, let first, let second) = tree else { Issue.record("split"); return }
        #expect(first == .leaf(win(1)))
        #expect(second == .leaf(win(2)))
    }

    @Test
    func insertSideLeftPlacesNewWindowFirst() {
        let tree = BSPTree.leaf(win(1)).inserting(win(2), nextTo: win(1), side: .left, containerIsWide: true)
        guard case .split(_, _, let first, let second) = tree else { Issue.record("split"); return }
        #expect(first == .leaf(win(2)))
        #expect(second == .leaf(win(1)))
    }

    @Test
    func insertOrientationFollowsContainerShape() {
        let wide = BSPTree.leaf(win(1)).inserting(win(2), nextTo: win(1), side: .right, containerIsWide: true)
        let tall = BSPTree.leaf(win(1)).inserting(win(2), nextTo: win(1), side: .right, containerIsWide: false)
        guard case .split(let wideOrient, _, _, _) = wide,
              case .split(let tallOrient, _, _, _) = tall else { Issue.record("splits"); return }
        #expect(wideOrient == .vertical)
        #expect(tallOrient == .horizontal)
    }

    @Test
    func insertOnFocusDoesNotMoveOtherWindowsFrames() {
        // 3 fenêtres : w1 (gauche), w2+w3 (droite empilées). Focus w1, on insère w4.
        let tree = BSPTree.split(
            orientation: .vertical, ratio: 0.5,
            first: .leaf(win(1)),
            second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(win(2)), second: .leaf(win(3)))
        )
        let before = tree.place(in: container, innerGap: 0)
        let after = tree.inserting(win(4), nextTo: win(1), side: .right, containerIsWide: true)
                        .place(in: container, innerGap: 0)
        // w2 et w3 ne doivent pas avoir bougé (ils sont dans l'autre moitié).
        #expect(after[win(2)] == before[win(2)])
        #expect(after[win(3)] == before[win(3)])
    }

    // MARK: - Suppression

    @Test
    func removeLeafLeavesSiblingInPlace() {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2)))
        let after = tree.removing(win(1))
        #expect(after == .leaf(win(2)))
    }

    @Test
    func removeSiblingRecoversSpace() {
        // [w1 | [w2 / w3]] — retirer w2 → [w1 | w3]
        let tree = BSPTree.split(
            orientation: .vertical, ratio: 0.5,
            first: .leaf(win(1)),
            second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(win(2)), second: .leaf(win(3)))
        )
        let after = tree.removing(win(2))
        #expect(after.windowIDs == [win(1), win(3)])
        let p = after.place(in: container, innerGap: 0)
        // w3 récupère toute la moitié droite.
        #expect(p[win(3)] == CGRect(x: 500, y: 0, width: 500, height: 600))
    }

    @Test
    func removeLastWindowYieldsEmpty() {
        #expect(BSPTree.leaf(win(1)).removing(win(1)) == .empty)
    }

    // MARK: - Reconciliation

    @Test
    func reconcileInsertsNewAndRemovesGone() {
        // Arbre [w1 | w2]. Réalité : w1 et w3 (w2 fermée, w3 ouverte). Focus w1.
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2)))
        let after = tree.reconciled(liveWindowIDs: [win(1), win(3)], focus: win(1), side: .right, containerIsWide: true)
        #expect(Set(after.windowIDs) == Set([win(1), win(3)]))
        #expect(!after.contains(win(2)))
    }

    @Test
    func balancedFromListProducesAllWindows() {
        let tree = BSPTree.balanced(from: [win(1), win(2), win(3), win(4)], containerIsWide: true)
        #expect(Set(tree.windowIDs) == Set([win(1), win(2), win(3), win(4)]))
    }

    @Test
    func codableRoundTrip() throws {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.4, first: .leaf(win(1)), second: .leaf(win(2)))
        let data = try JSONEncoder().encode(tree)
        let decoded = try JSONDecoder().decode(BSPTree.self, from: data)
        #expect(decoded == tree)
    }
}
