import CoreGraphics
import Foundation
import Testing
import RoadieCore
import RoadieTiler

/// Session 022, lot C : PERF-002 (plan BSP), REL-030 (master_ratio), REL-031 (espacement excessif).
@Suite
struct Audit022LotCTests {
    private func win(_ n: Int) -> WindowID { WindowID(rawValue: UInt32(n)) }
    private let scope = StageScope(
        displayID: DisplayID(rawValue: "display-a"),
        desktopID: DesktopID(rawValue: 1),
        stageID: StageID(rawValue: "1")
    )
    private let container = CGRect(x: 0, y: 0, width: 1000, height: 500)

    // MARK: - PERF-002 : résultats identiques à l'ancien algorithme

    /// Ancien algorithme de `SpatialBSPLayoutStrategy.plan`, gardé comme référence.
    private func referencePlan(_ request: LayoutRequest) -> [WindowID: CGRect] {
        let windows = request.windowIDs
        guard !windows.isEmpty else { return [:] }
        let rect = request.container.inset(by: request.outerGaps)
        let gap = CGFloat(request.innerGap)
        let full = request.bspTree ?? .empty
        var tree = full.projected(excluding: Set(full.windowIDs).subtracting(Set(windows)))
        var previous: WindowID?
        for id in windows where !tree.contains(id) {
            tree = tree.inserting(id, at: previous, side: .right, in: rect, innerGap: gap)
            previous = id
        }
        return tree.place(in: rect, innerGap: gap)
    }

    /// Arbre en chaîne : chaque fenêtre coupe la précédente.
    private func chainTree(_ count: Int) -> BSPTree {
        (1...count).reduce(BSPTree.empty) { tree, n in
            tree.inserting(win(n), at: n > 1 ? win(n - 1) : nil, side: .right, in: container, innerGap: 4)
        }
    }

    private func spatialRequest(_ windows: [WindowID], tree: BSPTree?) -> LayoutRequest {
        LayoutRequest(
            scope: scope,
            mode: .spatialBsp,
            container: container,
            windowIDs: windows,
            bspTree: tree,
            outerGaps: Insets(top: 5, right: 5, bottom: 5, left: 5),
            innerGap: 4
        )
    }

    @Test
    func perf002FullTreeMatchesReference() {
        let tree = chainTree(12)
        let request = spatialRequest((1...12).map(win), tree: tree)
        let plan = LayoutPlanner.plan(request)
        #expect(plan.placements == referencePlan(request))
        #expect(plan.placements.count == 12)
    }

    @Test
    func perf002ProjectionMatchesReference() {
        let tree = chainTree(8)
        let request = spatialRequest([win(1), win(3), win(4), win(8)], tree: tree)
        let plan = LayoutPlanner.plan(request)
        #expect(plan.placements == referencePlan(request))
        #expect(Set(plan.placements.keys) == [win(1), win(3), win(4), win(8)])
    }

    @Test
    func perf002MissingWindowsAndDuplicatesMatchReference() {
        let tree = chainTree(4)
        let windows = [win(2), win(9), win(4), win(10), win(9), win(2), win(11)]
        let request = spatialRequest(windows, tree: tree)
        let plan = LayoutPlanner.plan(request)
        #expect(plan.placements == referencePlan(request))
        #expect(Set(plan.placements.keys) == [win(2), win(4), win(9), win(10), win(11)])
    }

    @Test
    func perf002MissingTreeMatchesReference() {
        let request = spatialRequest([win(1), win(2), win(3)], tree: nil)
        #expect(LayoutPlanner.plan(request).placements == referencePlan(request))
    }

    // MARK: - REL-030 : master_ratio arrive au moteur

    private func masterStackRequest(_ windows: [WindowID], innerGap: Double = 0, masterRatio: Double = 0.6) -> LayoutRequest {
        LayoutRequest(
            scope: scope,
            mode: .masterStack,
            container: container,
            windowIDs: windows,
            innerGap: innerGap,
            masterRatio: masterRatio
        )
    }

    @Test
    func rel030ConfiguredMasterRatioDrivesMasterWidth() {
        let plan = LayoutPlanner.plan(masterStackRequest([win(1), win(2)], masterRatio: 0.8))
        #expect(plan.placements[win(1)] == CGRect(x: 0, y: 0, width: 800, height: 500))
        #expect(plan.placements[win(2)] == CGRect(x: 800, y: 0, width: 200, height: 500))

        let other = LayoutPlanner.plan(masterStackRequest([win(1), win(2)], masterRatio: 0.7))
        #expect(other.placements[win(1)]?.width == 700)
    }

    @Test
    func rel030DefaultMasterRatioUnchanged() {
        let request = LayoutRequest(scope: scope, mode: .masterStack, container: container, windowIDs: [win(1), win(2)])
        #expect(request.masterRatio == 0.6)
        #expect(LayoutPlanner.plan(request).placements[win(1)]?.width == 600)
    }

    @Test
    func rel030MasterRatioDecodedFromTOMLReachesPlan() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("audit022-lotc-\(UUID().uuidString).toml").path
        try "[tiling]\nmaster_ratio = 0.8\n".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let config = try RoadieConfigLoader.load(from: path)
        #expect(config.tiling.masterRatio == 0.8)
        let plan = LayoutPlanner.plan(masterStackRequest([win(1), win(2)], masterRatio: config.tiling.masterRatio))
        #expect(plan.placements[win(1)]?.width == 800)
    }

    // MARK: - REL-031 : aucune tuile hors du conteneur

    private func expectInsideAndNotEmpty(_ plan: LayoutPlan, count: Int) {
        #expect(plan.placements.count == count)
        for frame in plan.placements.values {
            #expect(frame.width > 0 && frame.height > 0, "tuile vide : \(frame)")
            #expect(container.contains(frame), "tuile hors du conteneur : \(frame)")
        }
    }

    @Test
    func rel031ExcessiveGapKeepsTilesInsideContainer() {
        // Sonde de l'audit : 1000×500, trois fenêtres, innerGap = 600.
        let plan = LayoutPlanner.plan(masterStackRequest([win(1), win(2), win(3)], innerGap: 600))
        expectInsideAndNotEmpty(plan, count: 3)
    }

    @Test
    func rel031InfiniteGapKeepsTilesInsideContainer() {
        let plan = LayoutPlanner.plan(masterStackRequest([win(1), win(2), win(3), win(4)], innerGap: .infinity))
        expectInsideAndNotEmpty(plan, count: 4)
    }

    @Test
    func rel031NormalGapsUnchanged() {
        let zero = LayoutPlanner.plan(masterStackRequest([win(1), win(2), win(3)]))
        #expect(zero.placements[win(1)] == CGRect(x: 0, y: 0, width: 600, height: 500))
        #expect(zero.placements[win(2)] == CGRect(x: 600, y: 0, width: 400, height: 250))
        #expect(zero.placements[win(3)] == CGRect(x: 600, y: 250, width: 400, height: 250))

        let normal = LayoutPlanner.plan(masterStackRequest([win(1), win(2), win(3)], innerGap: 10))
        #expect(normal.placements[win(1)] == CGRect(x: 0, y: 0, width: 594, height: 500))
        #expect(normal.placements[win(2)] == CGRect(x: 604, y: 0, width: 396, height: 245))
        #expect(normal.placements[win(3)] == CGRect(x: 604, y: 255, width: 396, height: 245))
    }

    @Test
    func rel031SingleWindowFillsContainer() {
        let plan = LayoutPlanner.plan(masterStackRequest([win(1)], innerGap: 600))
        #expect(plan.placements == [win(1): container])
    }
}
