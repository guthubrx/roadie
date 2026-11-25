import CoreGraphics
import Foundation
import RoadieCore
import RoadieTiler
import XCTest

final class Spec165TabbedBSPTreeTests: XCTestCase {
    private let w1 = WindowID(rawValue: 1)
    private let w2 = WindowID(rawValue: 2)
    private let w3 = WindowID(rawValue: 3)
    private let w4 = WindowID(rawValue: 4)
    private let container = CGRect(x: 0, y: 0, width: 1200, height: 800)

    func testNormalizedTabGroupEnforcesInvariants() {
        XCTAssertEqual(BSPTree.normalizedTabGroup([]), .empty)
        XCTAssertEqual(BSPTree.normalizedTabGroup([w1]), .leaf(w1))
        XCTAssertEqual(BSPTree.normalizedTabGroup([w1, w1]), .leaf(w1))
        XCTAssertEqual(
            BSPTree.normalizedTabGroup([w1, w2, w1], active: w3),
            .tabGroup(windowIDs: [w1, w2], active: w1)
        )
        XCTAssertEqual(
            BSPTree.normalizedTabGroup([w1, w2, w3], active: w2),
            .tabGroup(windowIDs: [w1, w2, w3], active: w2)
        )
    }

    func testCodableBackwardCompatibilityAndTabGroupRoundTrip() throws {
        // Ancien arbre sans tabGroup : encodage/décodage strictement conservé
        let legacy: BSPTree = .split(orientation: .vertical, ratio: 0.4, first: .leaf(w1), second: .leaf(w2))
        let legacyData = try JSONEncoder().encode(legacy)
        XCTAssertEqual(try JSONDecoder().decode(BSPTree.self, from: legacyData), legacy)

        // Nouvel arbre mixte avec tabGroup
        let tabbed: BSPTree = .split(
            orientation: .vertical,
            ratio: 0.5,
            first: .leaf(w1),
            second: .tabGroup(windowIDs: [w2, w3], active: w3)
        )
        let tabbedData = try JSONEncoder().encode(tabbed)
        XCTAssertEqual(try JSONDecoder().decode(BSPTree.self, from: tabbedData), tabbed)
    }

    func testStackingOntoLeafAndOntoExistingTabGroup() {
        let initial: BSPTree = .split(
            orientation: .vertical,
            ratio: 0.5,
            first: .leaf(w1),
            second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(w2), second: .leaf(w3))
        )
        let stacked = initial.stacking(w3, onto: w2)
        XCTAssertEqual(
            stacked,
            .split(
                orientation: .vertical,
                ratio: 0.5,
                first: .leaf(w1),
                second: .tabGroup(windowIDs: [w2, w3], active: w3)
            )
        )
        XCTAssertEqual(stacked.windowIDs, [w1, w2, w3])
        XCTAssertEqual(stacked.activeWindowIDs, [w1, w3])
        XCTAssertEqual(stacked.tabGroups.count, 1)

        // Empiler une 4e fenêtre (déjà insérée ailleurs) dans le groupe existant
        let withFourth = stacked.inserting(w4, nextTo: w1, side: .right, containerIsWide: true)
        let stacked4 = withFourth.stacking(w4, onto: w2)
        XCTAssertEqual(
            stacked4.tabGroup(containing: w2)?.windowIDs,
            [w2, w3, w4]
        )
        XCTAssertEqual(stacked4.tabGroup(containing: w2)?.active, w4)

        // Empiler sur soi-même = no-op ; empiler sur un co-onglet = sélectionne source
        XCTAssertEqual(stacked4.stacking(w2, onto: w2), stacked4)
        XCTAssertEqual(stacked4.stacking(w2, onto: w3).tabGroup(containing: w2)?.active, w2)
    }

    func testRemovingFromTabGroupCollapsesTwoToOneAndSelectsAdjacent() {
        let threeTabs: BSPTree = .split(
            orientation: .vertical,
            ratio: 0.5,
            first: .leaf(w1),
            second: .tabGroup(windowIDs: [w2, w3, w4], active: w4)
        )
        let afterRemoveActive = threeTabs.removing(w4)
        XCTAssertEqual(
            afterRemoveActive,
            .split(
                orientation: .vertical,
                ratio: 0.5,
                first: .leaf(w1),
                second: .tabGroup(windowIDs: [w2, w3], active: w3)
            )
        )
        // Retirer l'un des 2 derniers replie automatiquement en .leaf
        let afterCollapse = afterRemoveActive.removing(w3)
        XCTAssertEqual(
            afterCollapse,
            .split(orientation: .vertical, ratio: 0.5, first: .leaf(w1), second: .leaf(w2))
        )
        XCTAssertTrue(afterCollapse.tabGroups.isEmpty)
    }

    func testPlaceAndTabBarFramesGeometryAndPlainTreeInvariance() {
        let plain: BSPTree = .split(orientation: .vertical, ratio: 0.5, first: .leaf(w1), second: .leaf(w2))
        XCTAssertEqual(
            plain.place(in: container, innerGap: 10, tabBarHeight: 28),
            plain.place(in: container, innerGap: 10)
        )
        XCTAssertTrue(plain.tabBarFrames(in: container, innerGap: 10, tabBarHeight: 28).isEmpty)

        let tabbed: BSPTree = .split(
            orientation: .vertical,
            ratio: 0.5,
            first: .leaf(w1),
            second: .tabGroup(windowIDs: [w2, w3], active: w3)
        )
        let frames = tabbed.place(in: container, innerGap: 10, tabBarHeight: 28)
        let bars = tabbed.tabBarFrames(in: container, innerGap: 10, tabBarHeight: 28)
        XCTAssertEqual(bars.count, 1)
        let bar = bars[0]
        XCTAssertEqual(bar.windowIDs, [w2, w3])
        XCTAssertEqual(bar.active, w3)
        XCTAssertEqual(bar.barFrame.height, 28)
        XCTAssertEqual(bar.barFrame.minY, container.minY)
        XCTAssertEqual(bar.barFrame.minX, bar.tileFrame.minX)
        XCTAssertEqual(bar.barFrame.width, bar.tileFrame.width)

        // Les deux fenêtres du groupe ont le même cadre exactement sous la barre + 4 pt
        XCTAssertEqual(frames[w2], frames[w3])
        XCTAssertEqual(frames[w2]?.minY, bar.barFrame.maxY + BSPTree.tabBarGap)
        XCTAssertEqual(frames[w2]?.maxY, bar.tileFrame.maxY)
        // La tuile gauche simple occupe toujours toute la hauteur
        XCTAssertEqual(frames[w1]?.height, container.height)

        // Plancher de sécurité : tuile trop petite en hauteur -> pas de barre
        let tiny = CGRect(x: 0, y: 0, width: 600, height: 130)
        XCTAssertTrue(tabbed.tabBarFrames(in: tiny, innerGap: 8, tabBarHeight: 28).isEmpty)
        let tinyFrames = tabbed.place(in: tiny, innerGap: 8, tabBarHeight: 28)
        XCTAssertEqual(tinyFrames[w2]?.height, tiny.height)
    }

    func testUnstackingCyclingSelectingAndReorderingTabs() {
        let tabbed: BSPTree = .split(
            orientation: .vertical,
            ratio: 0.5,
            first: .leaf(w1),
            second: .tabGroup(windowIDs: [w2, w3, w4], active: w2)
        )

        // Cycle forward & wrap
        let step1 = tabbed.cyclingTab(from: w2, delta: 1)
        XCTAssertEqual(step1?.nextActive, w3)
        let stepBack = tabbed.cyclingTab(from: w2, delta: -1)
        XCTAssertEqual(stepBack?.nextActive, w4)
        XCTAssertNil(tabbed.cyclingTab(from: w1, delta: 1))

        // Reorder left/right and by index
        let movedRight = tabbed.reorderingTab(w2, delta: 1)
        XCTAssertEqual(movedRight.tabGroup(containing: w2)?.windowIDs, [w3, w2, w4])
        let movedToEnd = tabbed.reorderingTab(w2, toIndex: 2)
        XCTAssertEqual(movedToEnd.tabGroup(containing: w2)?.windowIDs, [w3, w4, w2])
        // Clamped no-op at edge
        XCTAssertEqual(tabbed.reorderingTab(w2, delta: -1), tabbed)

        // Unstack splits the remaining tab group tile
        let unstacked = tabbed.unstacking(w4, side: .right, containerIsWide: true)
        XCTAssertEqual(
            unstacked,
            .split(
                orientation: .vertical,
                ratio: 0.5,
                first: .leaf(w1),
                second: .split(
                    orientation: .vertical,
                    ratio: 0.5,
                    first: .tabGroup(windowIDs: [w2, w3], active: w2),
                    second: .leaf(w4)
                )
            )
        )
    }

    func testProjectionDividersNativeResizeRotateMirrorAndStrategy() {
        let tabbed: BSPTree = .split(
            orientation: .vertical,
            ratio: 0.5,
            first: .leaf(w1),
            second: .tabGroup(windowIDs: [w2, w3], active: w3)
        )

        // Projection avec une fenêtre temporairement absente replie en feuille simple
        let projected = tabbed.projected(excluding: [w3])
        XCTAssertEqual(projected, .split(orientation: .vertical, ratio: 0.5, first: .leaf(w1), second: .leaf(w2)))

        // Insertion à côté d'un membre du groupe coupe la tuile entière sans casser le groupe
        let inserted = tabbed.inserting(w4, nextTo: w2, side: .right, containerIsWide: false)
        XCTAssertEqual(inserted.tabGroup(containing: w2)?.windowIDs, [w2, w3])
        XCTAssertTrue(inserted.contains(w4))

        // BSPDivider détecte et déplace la séparation entre leaf et tabGroup
        let divs = tabbed.dividers(in: container, innerGap: 10)
        XCTAssertEqual(divs.count, 1)
        let moved = tabbed.movingDivider(at: divs[0].path, to: CGPoint(x: 400, y: 400), in: container, innerGap: 10)
        XCTAssertNotNil(moved)
        XCTAssertEqual(moved?.tabGroup(containing: w2)?.windowIDs, [w2, w3])

        // BSPNativeResize sur un onglet redimensionne la tuile entière et met à jour les deux onglets
        let resize = BSPNativeResize(tree: tabbed, windowID: w3, in: container, innerGap: 10, tabBarHeight: 28)
        XCTAssertEqual(resize?.movableEdges, [.left])
        let initialFrames = tabbed.place(in: container, innerGap: 10, tabBarHeight: 28)
        let grown = CGRect(
            x: initialFrames[w3]!.minX - 100,
            y: initialFrames[w3]!.minY,
            width: initialFrames[w3]!.width + 100,
            height: initialFrames[w3]!.height
        )
        let resized = resize?.layout(observedFrame: grown)
        XCTAssertNotNil(resized)
        XCTAssertEqual(resized?.frames[w2], resized?.frames[w3])
        XCTAssertEqual(resized?.frames[w3]?.minY, 28 + BSPTree.tabBarGap)

        // Rotation 90° & miroir préservent le tabGroup
        XCTAssertEqual(tabbed.rotated90().tabGroup(containing: w2)?.windowIDs, [w2, w3])
        XCTAssertEqual(tabbed.mirrored(.x).tabGroup(containing: w2)?.windowIDs, [w2, w3])

        // SpatialBSPLayoutStrategy respecte tabbedBarHeight
        let plan = SpatialBSPLayoutStrategy().plan(LayoutRequest(
            scope: StageScope(displayID: DisplayID(rawValue: "main"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1")),
            mode: .spatialBsp,
            container: container,
            windowIDs: [w1, w2, w3],
            bspTree: tabbed,
            innerGap: 10,
            tabbedBarHeight: 32
        ))
        XCTAssertEqual(plan.placements[w2], plan.placements[w3])
        XCTAssertEqual(plan.placements[w2]?.minY, 32 + BSPTree.tabBarGap)
    }
}
