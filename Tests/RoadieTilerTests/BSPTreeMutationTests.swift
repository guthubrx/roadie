import CoreGraphics
import Testing
import RoadieCore
import RoadieTiler

@Suite
struct BSPTreeMutationTests {
    private func win(_ n: Int) -> WindowID { WindowID(rawValue: UInt32(n)) }
    private let container = CGRect(x: 0, y: 0, width: 1000, height: 600)

    // MARK: - Swap

    @Test
    func swapPermutesTwoLeavesKeepingStructure() {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2)))
        let after = tree.swapping(win(1), win(2))
        guard case .split(let o, let r, let f, let s) = after else { Issue.record("split"); return }
        #expect(o == .vertical)
        #expect(r == 0.5)
        #expect(f == .leaf(win(2)))
        #expect(s == .leaf(win(1)))
    }

    @Test
    func swapDeepLeavesPreservesOtherNodes() {
        let tree = BSPTree.split(
            orientation: .vertical, ratio: 0.5,
            first: .leaf(win(1)),
            second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(win(2)), second: .leaf(win(3)))
        )
        let after = tree.swapping(win(1), win(3))
        // w1 et w3 échangés, w2 inchangé, structure identique.
        #expect(after.windowIDs == [win(3), win(2), win(1)])
    }

    @Test
    func swapNoOpWhenWindowMissing() {
        let tree = BSPTree.leaf(win(1))
        #expect(tree.swapping(win(1), win(9)) == tree)
    }

    // MARK: - Warp

    @Test
    func warpMovesWindowNextToNeighbor() {
        // [w1 | w2] : warp w1 à côté de w2 (à droite) → w1 quitte la gauche, divise w2.
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2)))
        let after = tree.warping(win(1), nextTo: win(2), side: .right, containerIsWide: true)
        // w1 retiré → racine devient w2, puis w2 divisé avec w1 à droite.
        #expect(Set(after.windowIDs) == Set([win(1), win(2)]))
        guard case .split(_, _, let first, let second) = after else { Issue.record("split"); return }
        #expect(first == .leaf(win(2)))
        #expect(second == .leaf(win(1)))
    }

    @Test
    func warpSiblingRecoversSpaceThenReinserts() {
        // [w1 | [w2 / w3]] : warp w2 à côté de w1 → w3 récupère la moitié droite, w2 rejoint w1.
        let tree = BSPTree.split(
            orientation: .vertical, ratio: 0.5,
            first: .leaf(win(1)),
            second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(win(2)), second: .leaf(win(3)))
        )
        let after = tree.warping(win(2), nextTo: win(1), side: .left, containerIsWide: true)
        #expect(Set(after.windowIDs) == Set([win(1), win(2), win(3)]))
        // w3 ne doit plus être dans un split avec w2.
        #expect(after.contains(win(3)))
    }

    // MARK: - Resize

    @Test
    func resizeAdjustsVerticalSplitRatio() {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2)))
        // Agrandir w1 (dans first) horizontalement de +0.2.
        let after = tree.resizing(window: win(1), orientation: .vertical, delta: 0.2)
        guard case .split(_, let r, _, _) = after else { Issue.record("split"); return }
        #expect(abs(r - 0.7) < 0.0001)
    }

    @Test
    func resizeWindowInSecondShrinksFirst() {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2)))
        // Agrandir w2 (dans second) → first diminue.
        let after = tree.resizing(window: win(2), orientation: .vertical, delta: 0.2)
        guard case .split(_, let r, _, _) = after else { Issue.record("split"); return }
        #expect(abs(r - 0.3) < 0.0001)
    }

    @Test
    func resizeClampsRatio() {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.9, first: .leaf(win(1)), second: .leaf(win(2)))
        let after = tree.resizing(window: win(1), orientation: .vertical, delta: 0.5)
        guard case .split(_, let r, _, _) = after else { Issue.record("split"); return }
        #expect(r <= 0.95)
    }

    @Test
    func resizeWrongOrientationIsNoOp() {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2)))
        // Demander un resize horizontal sur un arbre purement vertical → pas de split horizontal → no-op.
        let after = tree.resizing(window: win(1), orientation: .horizontal, delta: 0.2)
        #expect(after == tree)
    }

    @Test
    func resizeTargetsDeepestMatchingOrientation() {
        // [ [w1|w2] / w3 ] : resize w1 horizontalement → ajuste le split vertical interne [w1|w2].
        let tree = BSPTree.split(
            orientation: .horizontal, ratio: 0.5,
            first: .split(orientation: .vertical, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2))),
            second: .leaf(win(3))
        )
        let after = tree.resizing(window: win(1), orientation: .vertical, delta: 0.2)
        guard case .split(_, let outerRatio, let inner, _) = after,
              case .split(_, let innerRatio, _, _) = inner else { Issue.record("structure"); return }
        #expect(abs(outerRatio - 0.5) < 0.0001) // split externe inchangé
        #expect(abs(innerRatio - 0.7) < 0.0001) // split interne ajusté
    }
}
