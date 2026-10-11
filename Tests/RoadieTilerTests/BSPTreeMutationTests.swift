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
}
