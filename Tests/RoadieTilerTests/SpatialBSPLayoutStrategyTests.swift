import CoreGraphics
import Testing
import RoadieCore
import RoadieTiler

@Suite
struct SpatialBSPLayoutStrategyTests {
    private func win(_ n: Int) -> WindowID { WindowID(rawValue: UInt32(n)) }
    private let scope = StageScope(
        displayID: DisplayID(rawValue: "display-a"),
        desktopID: DesktopID(rawValue: 1),
        stageID: StageID(rawValue: "1")
    )

    @Test
    func placesAccordingToProvidedTree() {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2)))
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .spatialBsp,
            container: CGRect(x: 0, y: 0, width: 1000, height: 500),
            windowIDs: [win(1), win(2)],
            bspTree: tree,
            innerGap: 0
        ))
        #expect(plan.placements[win(1)] == CGRect(x: 0, y: 0, width: 500, height: 500))
        #expect(plan.placements[win(2)] == CGRect(x: 500, y: 0, width: 500, height: 500))
    }

    @Test
    func fallsBackToBalancedWhenTreeMissing() {
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .spatialBsp,
            container: CGRect(x: 0, y: 0, width: 1000, height: 500),
            windowIDs: [win(1), win(2)],
            bspTree: nil,
            innerGap: 0
        ))
        // Repli équilibré : 2 colonnes.
        #expect(plan.placements.count == 2)
        #expect(plan.placements[win(1)] != nil)
        #expect(plan.placements[win(2)] != nil)
    }

    @Test
    func fallsBackWhenTreeDesynced() {
        // Arbre ne contient que w1, mais on demande w1+w2 → repli équilibré.
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .spatialBsp,
            container: CGRect(x: 0, y: 0, width: 1000, height: 500),
            windowIDs: [win(1), win(2)],
            bspTree: .leaf(win(1)),
            innerGap: 0
        ))
        #expect(plan.placements[win(1)] != nil)
        #expect(plan.placements[win(2)] != nil)
    }

    @Test
    func everyWindowGetsAFrameAfterFocusedInsertion() {
        // Simule l'état après insertion focalisée de w3 à côté de w1.
        let tree = BSPTree
            .split(orientation: .vertical, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2)))
            .inserting(win(3), nextTo: win(1), side: .right, containerIsWide: true)
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .spatialBsp,
            container: CGRect(x: 0, y: 0, width: 1000, height: 500),
            windowIDs: tree.windowIDs,
            bspTree: tree,
            innerGap: 0
        ))
        #expect(plan.placements[win(1)] != nil)
        #expect(plan.placements[win(2)] != nil)
        #expect(plan.placements[win(3)] != nil)
        // w2 garde la moitié droite entière (insertion n'a touché que la gauche).
        #expect(plan.placements[win(2)] == CGRect(x: 500, y: 0, width: 500, height: 500))
    }

    /// SPEC-017 T043 : une feuille gardée pour une fenêtre absente ne prend pas de place, et
    /// une fenêtre inconnue de l'arbre est insérée sans jeter la structure existante.
    @Test
    func placesFromProjectedTreeAndKeepsStructureForUnknownWindow() {
        let tree = BSPTree.split(
            orientation: .vertical, ratio: 0.7,
            first: .leaf(win(1)),
            second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(win(2)), second: .leaf(win(3)))
        )
        let container = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let absent = LayoutPlanner.plan(LayoutRequest(
            scope: scope, mode: .spatialBsp, container: container,
            windowIDs: [win(1), win(2)], bspTree: tree, innerGap: 0
        ))
        #expect(absent.placements[win(1)] == CGRect(x: 0, y: 0, width: 700, height: 500))
        #expect(absent.placements[win(2)] == CGRect(x: 700, y: 0, width: 300, height: 500))
        #expect(absent.placements[win(3)] == nil)

        let unknown = LayoutPlanner.plan(LayoutRequest(
            scope: scope, mode: .spatialBsp, container: container,
            windowIDs: [win(1), win(2), win(4)], bspTree: tree, innerGap: 0
        ))
        // w1 garde sa colonne de 70 % ; w4 coupe la première feuille (w1) faute d'ancre.
        #expect(unknown.placements.count == 3)
        #expect(unknown.placements[win(2)] == CGRect(x: 700, y: 0, width: 300, height: 500))
    }

    @Test
    func respectsKnownMinimumSizesInSpatialBSP() {
        // Cas réel observé (session 162) : 2 fenêtres empilées dans 900×1078, la seconde refuse sous 582 px.
        let verticalStack = BSPTree.split(orientation: .horizontal, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2)))
        let container = CGRect(x: 0, y: 0, width: 900, height: 1078)
        let spatialPlan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .spatialBsp,
            container: container,
            windowIDs: [win(1), win(2)],
            bspTree: verticalStack,
            innerGap: 10,
            minimumSizes: [win(2): CGSize(width: 0, height: 582)]
        ))
        #expect(spatialPlan.placements[win(2)]?.height == 582)
        #expect(spatialPlan.placements[win(1)]?.height == 486)

        // Si le ratio existant satisfait déjà les minimums, le ratio utilisateur reste intact.
        let wideTree = BSPTree.split(orientation: .vertical, ratio: 0.7, first: .leaf(win(1)), second: .leaf(win(2)))
        let preserved = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .spatialBsp,
            container: CGRect(x: 0, y: 0, width: 1000, height: 500),
            windowIDs: [win(1), win(2)],
            bspTree: wideTree,
            innerGap: 0,
            minimumSizes: [win(1): CGSize(width: 500, height: 0), win(2): CGSize(width: 250, height: 0)]
        ))
        #expect(preserved.placements[win(1)]?.width == 700)
        #expect(preserved.placements[win(2)]?.width == 300)

        // Si la somme des minimums dépasse le conteneur (infaisable), le ratio d'origine reste conservé.
        let infeasible = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .spatialBsp,
            container: CGRect(x: 0, y: 0, width: 1000, height: 500),
            windowIDs: [win(1), win(2)],
            bspTree: wideTree,
            innerGap: 0,
            minimumSizes: [win(1): CGSize(width: 700, height: 0), win(2): CGSize(width: 600, height: 0)]
        ))
        #expect(infeasible.placements[win(1)]?.width == 700)
        #expect(infeasible.placements[win(2)]?.width == 300)
    }

    @Test
    func nestedSpatialBSPTreeReservesGapAndMinimumFloor() {
        // Deux splits verticaux imbriqués : largeur 1010, gap 10, ratio racine 0,4,
        // minimum 400 sur la première feuille -> la sous-branche gauche réserve 400 + minimumChildExtent(10) + 10 = 420 px.
        let nested = BSPTree.split(
            orientation: .vertical, ratio: 0.4,
            first: .split(orientation: .vertical, ratio: 0.5, first: .leaf(win(1)), second: .leaf(win(2))),
            second: .leaf(win(3))
        )
        let nestedPlan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .spatialBsp,
            container: CGRect(x: 0, y: 0, width: 1010, height: 500),
            windowIDs: [win(1), win(2), win(3)],
            bspTree: nested,
            innerGap: 10,
            minimumSizes: [win(1): CGSize(width: 400, height: 0)]
        ))
        #expect(nestedPlan.placements[win(1)]?.width == 400)
        #expect(nestedPlan.placements[win(2)]?.width == 10)
        #expect(nestedPlan.placements[win(3)]?.width == 580)
    }
}
