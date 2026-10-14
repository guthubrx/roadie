import CoreGraphics
import Foundation
import Testing
import RoadieCore
import RoadieTiler

/// Session 022, round 2, lot F : R1-01 (`BSPTree.windowIDs` en O(n)), `BSPTree.childRects`
/// (espacement plus grand que le conteneur), R1-08 (REL-030 : nouvelles fenêtres et `master_ratio`).
@Suite
struct Audit022R2LotFTests {
    private func win(_ n: Int) -> WindowID { WindowID(rawValue: UInt32(n)) }
    private let scope = StageScope(
        displayID: DisplayID(rawValue: "display-a"),
        desktopID: DesktopID(rawValue: 1),
        stageID: StageID(rawValue: "1")
    )

    // MARK: - R1-01 : BSPTree.windowIDs, même ordre qu'avant, en O(n)

    /// Ancienne implémentation (concaténation récursive), gardée comme référence d'ordre.
    private func referenceIDs(_ tree: BSPTree) -> [WindowID] {
        switch tree {
        case .empty: return []
        case .leaf(let id): return [id]
        case .split(_, _, let first, let second): return referenceIDs(first) + referenceIDs(second)
        }
    }

    private func chain(_ count: Int, side: BSPInsertionSide) -> BSPTree {
        (1...count).reduce(BSPTree.empty) { tree, k in
            tree.inserting(win(k), nextTo: k > 1 ? win(k - 1) : nil, side: side, containerIsWide: k % 2 == 0)
        }
    }

    @Test
    func r101WindowIDsKeepTraversalOrder() {
        #expect(BSPTree.empty.windowIDs.isEmpty)
        #expect(BSPTree.leaf(win(7)).windowIDs == [win(7)])
        for side in [BSPInsertionSide.right, .left] {
            let tree = chain(40, side: side)
            #expect(tree.windowIDs == referenceIDs(tree))
            #expect(tree.windowIDs.count == 40)
        }
        // Arbre non en chaîne : la deuxième feuille reçoit une division dans chaque sous-arbre.
        let balanced = BSPTree.split(
            orientation: .vertical, ratio: 0.5,
            first: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2))),
            second: .split(orientation: .horizontal, ratio: 0.3, first: .leaf(win(3)), second: .leaf(win(4)))
        )
        #expect(balanced.windowIDs == [win(1), win(2), win(3), win(4)])
    }

    // MARK: - BSPTree.childRects : espacement plus grand que le conteneur

    private func twoLeaves(_ orientation: BSPOrientation) -> BSPTree {
        .split(orientation: orientation, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2)))
    }

    @Test
    func childRectsKeepBothChildrenInsideContainerWhenGapExceedsIt() {
        let container = CGRect(x: 0, y: 0, width: 100, height: 80)
        for orientation in [BSPOrientation.vertical, .horizontal] {
            for gap in [CGFloat(95), 500, .infinity] {
                let placed = twoLeaves(orientation).place(in: container, innerGap: gap)
                #expect(placed.count == 2)
                for frame in placed.values {
                    #expect(frame.width > 0 && frame.height > 0)
                    #expect(container.contains(frame))
                }
                #expect(!(placed[win(1)]!.intersects(placed[win(2)]!)))
            }
        }
    }

    @Test
    func childRectsUnchangedWhenGapFits() {
        let container = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let vertical = twoLeaves(.vertical).place(in: container, innerGap: 4)
        #expect(vertical[win(1)] == CGRect(x: 0, y: 0, width: 498, height: 500))
        #expect(vertical[win(2)] == CGRect(x: 502, y: 0, width: 498, height: 500))
        let horizontal = twoLeaves(.horizontal).place(in: container, innerGap: 0)
        #expect(horizontal[win(1)] == CGRect(x: 0, y: 0, width: 1000, height: 249))
        #expect(horizontal[win(2)] == CGRect(x: 0, y: 250, width: 1000, height: 250))
    }

    // MARK: - R1-08 : nouvelles fenêtres suivent master_ratio, géométrie existante préservée

    private let container = CGRect(x: 0, y: 0, width: 1000, height: 500)

    private func masterRequest(
        _ windows: [WindowID],
        frames: [WindowID: CGRect],
        newWindowIDs: Set<WindowID> = [],
        priority: Set<WindowID> = [],
        masterRatio: Double = 0.6
    ) -> LayoutRequest {
        LayoutRequest(
            scope: scope, mode: .masterStack, container: container, windowIDs: windows,
            currentFrames: frames, priorityWindowIDs: priority, newWindowIDs: newWindowIDs,
            masterRatio: masterRatio
        )
    }

    @Test
    func r108NewWindowsWithArbitraryWidthsFollowConfiguredRatio() {
        // Largeurs arbitraires données par macOS : maître 300, pile collée au bord droit.
        let frames = [
            win(1): CGRect(x: 0, y: 0, width: 300, height: 300),
            win(2): CGRect(x: 700, y: 0, width: 300, height: 300),
        ]
        let plan = LayoutPlanner.plan(masterRequest([win(1), win(2)], frames: frames, newWindowIDs: [win(1), win(2)], masterRatio: 0.8))
        #expect(plan.placements[win(1)]?.width == 800)
        #expect(plan.placements[win(2)]?.minX == 800)
    }

    @Test
    func r108ExistingGeometryIsStillPreserved() {
        let frames = [
            win(1): CGRect(x: 0, y: 0, width: 300, height: 300),
            win(2): CGRect(x: 700, y: 0, width: 300, height: 300),
        ]
        // Fenêtres déjà disposées : la largeur la plus éloignée du ratio configuré (0,8) est gardée.
        let plan = LayoutPlanner.plan(masterRequest([win(1), win(2)], frames: frames, masterRatio: 0.8))
        #expect(plan.placements[win(1)]?.width == 300)
    }

    @Test
    func r108NewStackWindowJoiningExistingMasterKeepsMasterWidth() {
        let frames = [
            win(1): CGRect(x: 0, y: 0, width: 300, height: 500),
            win(2): CGRect(x: 300, y: 0, width: 700, height: 250),
            win(3): CGRect(x: 120, y: 90, width: 640, height: 400),
        ]
        let plan = LayoutPlanner.plan(masterRequest([win(1), win(2), win(3)], frames: frames, newWindowIDs: [win(3)], masterRatio: 0.8))
        #expect(plan.placements[win(1)]?.width == 300)
        #expect(plan.placements[win(3)]?.minX == 300)
    }

    @Test
    func r108NewMasterJoiningExistingStackKeepsStackEdge() {
        let frames = [
            win(1): CGRect(x: 37, y: 41, width: 410, height: 300),
            win(2): CGRect(x: 600, y: 0, width: 400, height: 500),
        ]
        let plan = LayoutPlanner.plan(masterRequest([win(1), win(2)], frames: frames, newWindowIDs: [win(1)], masterRatio: 0.2))
        #expect(plan.placements[win(2)]?.minX == 600)
        #expect(plan.placements[win(1)]?.width == 600)
    }

    @Test
    func r108ManualResizeOfNewlyListedWindowsStillWinsViaPriority() {
        let frames = [
            win(1): CGRect(x: 0, y: 0, width: 400, height: 500),
            win(2): CGRect(x: 400, y: 0, width: 600, height: 500),
        ]
        let plan = LayoutPlanner.plan(masterRequest([win(1), win(2)], frames: frames, priority: [win(1)], masterRatio: 0.8))
        #expect(plan.placements[win(1)]?.width == 400)
    }
}
