import CoreGraphics
import Testing
import RoadieCore
import RoadieTiler

@Suite
struct LayoutPlannerTests {
    private let scope = StageScope(
        displayID: DisplayID(rawValue: "display-a"),
        desktopID: DesktopID(rawValue: 1),
        stageID: StageID(rawValue: "1")
    )

    @Test
    func bspSplitsTwoWindowsHorizontallyWhenWide() {
        let a = WindowID(rawValue: 1)
        let b = WindowID(rawValue: 2)
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .bsp,
            container: CGRect(x: 0, y: 0, width: 1000, height: 500),
            windowIDs: [a, b],
            innerGap: 10
        ))

        #expect(plan.placements[a] == CGRect(x: 0, y: 0, width: 495, height: 500))
        #expect(plan.placements[b] == CGRect(x: 505, y: 0, width: 495, height: 500))
    }

    @Test
    func mutableBspNewWindowSplits5050IgnoringArbitraryMacOSFrame() {
        // Reproduit le bug : une nouvelle fenetre arrive avec une frame macOS arbitraire
        // (petite, x=150 w=491). Sans le fix, mutableBsp herite de ce ratio (~13%).
        // Avec le fix (newWindowIDs), elle doit obtenir 50/50.
        let existing = WindowID(rawValue: 1) // grosse fenetre existante
        let fresh = WindowID(rawValue: 2)    // nouvelle fenetre
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .mutableBsp,
            container: CGRect(x: 0, y: 0, width: 1000, height: 500),
            windowIDs: [fresh, existing],
            currentFrames: [
                existing: CGRect(x: 350, y: 0, width: 650, height: 500),
                fresh: CGRect(x: 0, y: 0, width: 200, height: 500) // frame macOS arbitraire
            ],
            newWindowIDs: [fresh],
            innerGap: 10
        ))
        // 50/50 attendu : chacune ~495 de large.
        #expect(plan.placements[fresh] == CGRect(x: 0, y: 0, width: 495, height: 500))
        #expect(plan.placements[existing] == CGRect(x: 505, y: 0, width: 495, height: 500))
    }

    @Test
    func mutableBspRespectsExistingRatioWhenNoNewWindow() {
        // Sans nouvelle fenetre, mutableBsp doit preserver le ratio existant (resize manuel).
        let a = WindowID(rawValue: 1)
        let b = WindowID(rawValue: 2)
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .mutableBsp,
            container: CGRect(x: 0, y: 0, width: 1000, height: 500),
            windowIDs: [a, b],
            currentFrames: [
                a: CGRect(x: 0, y: 0, width: 300, height: 500),
                b: CGRect(x: 310, y: 0, width: 690, height: 500)
            ],
            innerGap: 10
        ))
        // Ratio preserve : a ~30%, b ~70%.
        #expect((plan.placements[a]?.width ?? 0) < 400)
        #expect((plan.placements[b]?.width ?? 0) > 500)
    }

    @Test
    func bspNewWindowSplits5050IgnoringArbitraryMacOSFrame() {
        let existing = WindowID(rawValue: 1)
        let fresh = WindowID(rawValue: 2)
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .bsp,
            container: CGRect(x: 0, y: 0, width: 1000, height: 500),
            windowIDs: [fresh, existing],
            currentFrames: [
                existing: CGRect(x: 150, y: 0, width: 850, height: 500),
                fresh: CGRect(x: 0, y: 0, width: 150, height: 500)
            ],
            newWindowIDs: [fresh],
            innerGap: 10
        ))
        #expect(plan.placements[fresh] == CGRect(x: 0, y: 0, width: 495, height: 500))
        #expect(plan.placements[existing] == CGRect(x: 505, y: 0, width: 495, height: 500))
    }

    @Test
    func bspKeepsMinimalVerticalTitleBarSeamWhenInnerGapIsZero() {
        let a = WindowID(rawValue: 1)
        let b = WindowID(rawValue: 2)
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .bsp,
            container: CGRect(x: 0, y: 0, width: 500, height: 1000),
            windowIDs: [a, b],
            innerGap: 0
        ))

        #expect(plan.placements[a] == CGRect(x: 0, y: 0, width: 500, height: 499))
        #expect(plan.placements[b] == CGRect(x: 0, y: 500, width: 500, height: 500))
    }

    @Test
    func bspDwindleKeepsSplittingTheRemainder() {
        let a = WindowID(rawValue: 1)
        let b = WindowID(rawValue: 2)
        let c = WindowID(rawValue: 3)
        let d = WindowID(rawValue: 4)
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .bsp,
            container: CGRect(x: 0, y: 0, width: 1000, height: 500),
            windowIDs: [a, b, c, d],
            splitPolicy: "dwindle",
            innerGap: 10
        ))

        #expect(plan.placements[a] == CGRect(x: 0, y: 0, width: 495, height: 500))
        #expect(plan.placements[b] == CGRect(x: 505, y: 0, width: 495, height: 245))
        #expect(plan.placements[c] == CGRect(x: 505, y: 255, width: 242, height: 245))
        #expect(plan.placements[d] == CGRect(x: 757, y: 255, width: 243, height: 245))
    }

    @Test
    func bspPreservesManualHorizontalResizeAsSplitRatio() {
        let a = WindowID(rawValue: 1)
        let b = WindowID(rawValue: 2)
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .bsp,
            container: CGRect(x: 0, y: 0, width: 1000, height: 500),
            windowIDs: [a, b],
            currentFrames: [
                a: CGRect(x: 0, y: 0, width: 700, height: 500),
                b: CGRect(x: 710, y: 0, width: 290, height: 500),
            ],
            priorityWindowIDs: [a],
            innerGap: 10
        ))

        #expect(plan.placements[a] == CGRect(x: 0, y: 0, width: 700, height: 500))
        #expect(plan.placements[b] == CGRect(x: 710, y: 0, width: 290, height: 500))
    }

    @Test
    func bspKeepsLeftWindowManualResizeAndMovesRightWindow() {
        let a = WindowID(rawValue: 1)
        let b = WindowID(rawValue: 2)
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .bsp,
            container: CGRect(x: 0, y: 0, width: 1000, height: 500),
            windowIDs: [a, b],
            currentFrames: [
                a: CGRect(x: 0, y: 0, width: 700, height: 500),
                b: CGRect(x: 505, y: 0, width: 495, height: 500),
            ],
            priorityWindowIDs: [a],
            innerGap: 10
        ))

        #expect(plan.placements[a] == CGRect(x: 0, y: 0, width: 700, height: 500))
        #expect(plan.placements[b] == CGRect(x: 710, y: 0, width: 290, height: 500))
    }

    @Test
    func bspKeepsRightWindowManualResizeAndMovesLeftWindow() {
        let a = WindowID(rawValue: 1)
        let b = WindowID(rawValue: 2)
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .bsp,
            container: CGRect(x: 0, y: 0, width: 1000, height: 500),
            windowIDs: [a, b],
            currentFrames: [
                a: CGRect(x: 0, y: 0, width: 495, height: 500),
                b: CGRect(x: 300, y: 0, width: 700, height: 500),
            ],
            priorityWindowIDs: [b],
            innerGap: 10
        ))

        #expect(plan.placements[a] == CGRect(x: 0, y: 0, width: 290, height: 500))
        #expect(plan.placements[b] == CGRect(x: 300, y: 0, width: 700, height: 500))
    }

    @Test
    func bspPriorityRightWindowWinsAgainstStaleLeftEdge() {
        let a = WindowID(rawValue: 1)
        let b = WindowID(rawValue: 2)
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .bsp,
            container: CGRect(x: 0, y: 0, width: 500, height: 1000),
            windowIDs: [a, b],
            currentFrames: [
                a: CGRect(x: 0, y: 0, width: 500, height: 800),
                b: CGRect(x: 0, y: 500, width: 500, height: 500),
            ],
            priorityWindowIDs: [b],
            innerGap: 10
        ))

        #expect(plan.placements[a] == CGRect(x: 0, y: 0, width: 500, height: 490))
        #expect(plan.placements[b] == CGRect(x: 0, y: 500, width: 500, height: 500))
    }

    @Test
    func bspKeepsBottomPrioritySizeWhenOuterEdgeWasDraggedInward() {
        let a = WindowID(rawValue: 1)
        let b = WindowID(rawValue: 2)
        let c = WindowID(rawValue: 3)
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .bsp,
            container: CGRect(x: 0, y: 0, width: 1000, height: 1000),
            windowIDs: [a, b, c],
            currentFrames: [
                a: CGRect(x: 0, y: 0, width: 495, height: 1000),
                b: CGRect(x: 505, y: 0, width: 495, height: 495),
                c: CGRect(x: 505, y: 505, width: 350, height: 300),
            ],
            priorityWindowIDs: [c],
            innerGap: 10
        ))

        #expect(plan.placements[a] == CGRect(x: 0, y: 0, width: 640, height: 1000))
        #expect(plan.placements[b] == CGRect(x: 650, y: 0, width: 350, height: 690))
        #expect(plan.placements[c] == CGRect(x: 650, y: 700, width: 350, height: 300))
    }

    @Test
    func bspBalancedIgnoresStaleRatiosWithoutPriorityWindow() {
        let a = WindowID(rawValue: 1)
        let b = WindowID(rawValue: 2)
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .bsp,
            container: CGRect(x: 0, y: 0, width: 1000, height: 500),
            windowIDs: [a, b],
            currentFrames: [
                a: CGRect(x: 0, y: 0, width: 800, height: 500),
                b: CGRect(x: 810, y: 0, width: 190, height: 500),
            ],
            splitPolicy: "balanced",
            innerGap: 10
        ))

        #expect(plan.placements[a] == CGRect(x: 0, y: 0, width: 495, height: 500))
        #expect(plan.placements[b] == CGRect(x: 505, y: 0, width: 495, height: 500))
    }

    @Test
    func mutableBspPreservesObservedRatioWithoutPriorityWindow() {
        let a = WindowID(rawValue: 1)
        let b = WindowID(rawValue: 2)
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .mutableBsp,
            container: CGRect(x: 0, y: 0, width: 1000, height: 500),
            windowIDs: [a, b],
            currentFrames: [
                a: CGRect(x: 0, y: 0, width: 800, height: 500),
                b: CGRect(x: 810, y: 0, width: 190, height: 500),
            ],
            splitPolicy: "balanced",
            innerGap: 10
        ))

        #expect(plan.placements[a] == CGRect(x: 0, y: 0, width: 800, height: 500))
        #expect(plan.placements[b] == CGRect(x: 810, y: 0, width: 190, height: 500))
    }

    @Test
    func mutableBspPreservesObservedVerticalSplitOnWideContainer() {
        let a = WindowID(rawValue: 1)
        let b = WindowID(rawValue: 2)
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .mutableBsp,
            container: CGRect(x: 0, y: 0, width: 1000, height: 500),
            windowIDs: [a, b],
            currentFrames: [
                a: CGRect(x: 0, y: 0, width: 1000, height: 300),
                b: CGRect(x: 0, y: 310, width: 1000, height: 190),
            ],
            splitPolicy: "balanced",
            innerGap: 10
        ))

        #expect(plan.placements[a] == CGRect(x: 0, y: 0, width: 1000, height: 300))
        #expect(plan.placements[b] == CGRect(x: 0, y: 310, width: 1000, height: 190))
    }

    @Test
    func mutableBspPreservesObservedVerticalStackForThreeWindows() {
        let a = WindowID(rawValue: 1)
        let b = WindowID(rawValue: 2)
        let c = WindowID(rawValue: 3)
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .mutableBsp,
            container: CGRect(x: 0, y: 0, width: 1000, height: 900),
            windowIDs: [a, b, c],
            currentFrames: [
                a: CGRect(x: 0, y: 0, width: 1000, height: 290),
                b: CGRect(x: 0, y: 300, width: 1000, height: 290),
                c: CGRect(x: 0, y: 600, width: 1000, height: 300),
            ],
            splitPolicy: "balanced",
            innerGap: 10
        ))

        #expect(plan.placements[a] == CGRect(x: 0, y: 0, width: 1000, height: 290))
        #expect(plan.placements[b] == CGRect(x: 0, y: 300, width: 1000, height: 290))
        #expect(plan.placements[c] == CGRect(x: 0, y: 600, width: 1000, height: 300))
    }

    @Test
    func mutableBspFallsBackToBalancedPlanWithoutObservedFrames() {
        let a = WindowID(rawValue: 1)
        let b = WindowID(rawValue: 2)
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .mutableBsp,
            container: CGRect(x: 0, y: 0, width: 1000, height: 500),
            windowIDs: [a, b],
            innerGap: 10
        ))

        #expect(plan.placements[a] == CGRect(x: 0, y: 0, width: 495, height: 500))
        #expect(plan.placements[b] == CGRect(x: 505, y: 0, width: 495, height: 500))
    }

    @Test
    func mutableBspModeParsesUserFacingAliases() {
        #expect(WindowManagementMode(roadieValue: "mutableBsp") == .mutableBsp)
        #expect(WindowManagementMode(roadieValue: "mutable_bsp") == .mutableBsp)
        #expect(WindowManagementMode(roadieValue: "mutable-bsp") == .mutableBsp)
    }

    @Test
    func bspPreservesManualVerticalResizeAsSplitRatio() {
        let a = WindowID(rawValue: 1)
        let b = WindowID(rawValue: 2)
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .bsp,
            container: CGRect(x: 0, y: 0, width: 500, height: 1000),
            windowIDs: [a, b],
            currentFrames: [
                a: CGRect(x: 0, y: 0, width: 500, height: 650),
                b: CGRect(x: 0, y: 660, width: 500, height: 340),
            ],
            priorityWindowIDs: [a],
            innerGap: 10
        ))

        #expect(plan.placements[a] == CGRect(x: 0, y: 0, width: 500, height: 650))
        #expect(plan.placements[b] == CGRect(x: 0, y: 660, width: 500, height: 340))
    }

    @Test
    func masterStackKeepsFirstWindowAsMaster() {
        let a = WindowID(rawValue: 1)
        let b = WindowID(rawValue: 2)
        let c = WindowID(rawValue: 3)
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .masterStack,
            container: CGRect(x: 0, y: 0, width: 1000, height: 500),
            windowIDs: [a, b, c],
            innerGap: 10
        ))

        #expect(plan.placements[a] == CGRect(x: 0, y: 0, width: 594, height: 500))
        #expect(plan.placements[b] == CGRect(x: 604, y: 0, width: 396, height: 245))
        #expect(plan.placements[c] == CGRect(x: 604, y: 255, width: 396, height: 245))
    }

    @Test
    func masterStackPreservesManualMasterResizeAsRatio() {
        let a = WindowID(rawValue: 1)
        let b = WindowID(rawValue: 2)
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .masterStack,
            container: CGRect(x: 0, y: 0, width: 1000, height: 500),
            windowIDs: [a, b],
            currentFrames: [
                a: CGRect(x: 0, y: 0, width: 700, height: 500),
                b: CGRect(x: 710, y: 0, width: 290, height: 500),
            ],
            innerGap: 10
        ))

        #expect(plan.placements[a] == CGRect(x: 0, y: 0, width: 700, height: 500))
        #expect(plan.placements[b] == CGRect(x: 710, y: 0, width: 290, height: 500))
    }

    @Test
    func masterStackKeepsStackManualResizeAndMovesMaster() {
        let a = WindowID(rawValue: 1)
        let b = WindowID(rawValue: 2)
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .masterStack,
            container: CGRect(x: 0, y: 0, width: 1000, height: 500),
            windowIDs: [a, b],
            currentFrames: [
                a: CGRect(x: 0, y: 0, width: 594, height: 500),
                b: CGRect(x: 300, y: 0, width: 700, height: 500),
            ],
            innerGap: 10
        ))

        #expect(plan.placements[a] == CGRect(x: 0, y: 0, width: 290, height: 500))
        #expect(plan.placements[b] == CGRect(x: 300, y: 0, width: 700, height: 500))
    }

    @Test
    func floatModePreservesKnownFramesAndIgnoresUnknownFrames() {
        let a = WindowID(rawValue: 1)
        let b = WindowID(rawValue: 2)
        let existing = CGRect(x: 20, y: 30, width: 400, height: 300)
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .float,
            container: CGRect(x: 0, y: 0, width: 1000, height: 500),
            windowIDs: [a, b],
            currentFrames: [a: existing]
        ))

        #expect(plan.placements == [a: existing])
    }

    @Test
    func diffProducesNoCommandsForIdenticalPlan() {
        let a = WindowID(rawValue: 1)
        let plan = LayoutPlan(placements: [
            a: CGRect(x: 0, y: 0, width: 100, height: 100)
        ])

        #expect(LayoutDiff.commands(previous: plan, next: plan).isEmpty)
    }

    @Test
    func diffKeepsSmallIntentionalGapChanges() {
        let a = WindowID(rawValue: 1)
        let previous = LayoutPlan(placements: [
            a: CGRect(x: 100, y: 100, width: 500, height: 500)
        ])
        let next = LayoutPlan(placements: [
            a: CGRect(x: 100, y: 100, width: 492, height: 500)
        ])

        #expect(LayoutDiff.commands(previous: previous, next: next).map(\.windowID) == [a])
    }

    @Test
    func diffProducesCommandsForChangedFramesInStableOrder() {
        let a = WindowID(rawValue: 2)
        let b = WindowID(rawValue: 1)
        let next = LayoutPlan(placements: [
            a: CGRect(x: 0, y: 0, width: 100, height: 100),
            b: CGRect(x: 100, y: 0, width: 100, height: 100),
        ])

        let commands = LayoutDiff.commands(previous: nil, next: next)

        #expect(commands.map(\.windowID) == [b, a])
    }
}
