import CoreGraphics
import Testing
import RoadieCore
import RoadieTiler

/// Session 022, round 4, lot T1 : `BSPLayoutStrategy` (PERF-008 : plan sans priorité en O(n),
/// REL-033 : espacement borné au conteneur).
@Suite
struct Audit022R4LotT1Tests {
    private func win(_ n: Int) -> WindowID { WindowID(rawValue: UInt32(n)) }
    private let scope = StageScope(
        displayID: DisplayID(rawValue: "display-a"),
        desktopID: DesktopID(rawValue: 1),
        stageID: StageID(rawValue: "1")
    )

    private func bspRequest(
        container: CGRect,
        windowIDs: [WindowID],
        currentFrames: [WindowID: CGRect] = [:],
        priorityWindowIDs: Set<WindowID> = [],
        newWindowIDs: Set<WindowID> = [],
        splitPolicy: String,
        innerGap: Double
    ) -> LayoutRequest {
        LayoutRequest(
            scope: scope,
            mode: .bsp,
            container: container,
            windowIDs: windowIDs,
            currentFrames: currentFrames,
            priorityWindowIDs: priorityWindowIDs,
            newWindowIDs: newWindowIDs,
            splitPolicy: splitPolicy,
            innerGap: innerGap
        )
    }

    // MARK: - REL-033 : un espacement plus grand que le conteneur reste dans le conteneur

    @Test(arguments: ["balanced", "dwindle"])
    func rel033OversizedGapKeepsTilesInsideContainer(splitPolicy: String) {
        for container in [CGRect(x: 0, y: 0, width: 1000, height: 500), CGRect(x: 0, y: 0, width: 500, height: 1000)] {
            for count in 2...4 {
                let ids = (1...count).map(win)
                let plan = LayoutPlanner.plan(bspRequest(
                    container: container, windowIDs: ids, splitPolicy: splitPolicy, innerGap: 1500
                ))
                #expect(plan.placements.count == count)
                for id in ids {
                    let frame = plan.placements[id] ?? .null
                    #expect(container.contains(frame), "\(splitPolicy) \(container) \(id) : \(frame)")
                    #expect(frame.width > 0 && frame.height > 0, "\(splitPolicy) \(container) \(id) : \(frame)")
                }
            }
        }
    }

    @Test
    func rel033OversizedGapLeavesMinimumExtentOnBothSides() {
        let plan = LayoutPlanner.plan(bspRequest(
            container: CGRect(x: 0, y: 0, width: 1000, height: 500),
            windowIDs: [win(1), win(2)], splitPolicy: "balanced", innerGap: 1500
        ))
        #expect(plan.placements[win(1)] == CGRect(x: 0, y: 0, width: 10, height: 500))
        #expect(plan.placements[win(2)] == CGRect(x: 990, y: 0, width: 10, height: 500))
    }

    @Test
    func rel033GapThatFitsIsUnchanged() {
        let wide = LayoutPlanner.plan(bspRequest(
            container: CGRect(x: 0, y: 0, width: 1000, height: 500),
            windowIDs: [win(1), win(2)], splitPolicy: "balanced", innerGap: 10
        ))
        #expect(wide.placements[win(1)] == CGRect(x: 0, y: 0, width: 495, height: 500))
        #expect(wide.placements[win(2)] == CGRect(x: 505, y: 0, width: 495, height: 500))
        let tall = LayoutPlanner.plan(bspRequest(
            container: CGRect(x: 0, y: 0, width: 500, height: 1000),
            windowIDs: [win(1), win(2)], splitPolicy: "balanced", innerGap: 0
        ))
        #expect(tall.placements[win(1)] == CGRect(x: 0, y: 0, width: 500, height: 499))
        #expect(tall.placements[win(2)] == CGRect(x: 0, y: 500, width: 500, height: 500))
    }

    // MARK: - PERF-008 : mêmes placements que l'ancien calcul du ratio

    @Test(arguments: ["balanced", "dwindle"])
    func perf008PlacementsMatchReferenceAlgorithm(splitPolicy: String) {
        var rng = Lcg(seed: 0x5EED_0080)
        let containers = [
            CGRect(x: 0, y: 25, width: 1440, height: 875),
            CGRect(x: -1920, y: 0, width: 1080, height: 1920),
            CGRect(x: 0, y: 0, width: 300, height: 120)
        ]
        for container in containers {
            for count in [1, 2, 3, 5, 8, 13, 50] {
                let ids = (1...count).map(win)
                for scenario in 0..<6 {
                    let innerGap = Double([0, 1, 8, 10, 40, 1500][scenario])
                    // Frames : absentes, plan précédent (split géré) ou arbitraires.
                    var frames: [WindowID: CGRect] = [:]
                    if scenario % 3 == 1 {
                        frames = LayoutPlanner.plan(bspRequest(
                            container: container, windowIDs: ids, splitPolicy: splitPolicy, innerGap: innerGap
                        )).placements
                    } else if scenario % 3 == 2 {
                        for id in ids {
                            frames[id] = CGRect(
                                x: container.minX + rng.next(in: 0...container.width),
                                y: container.minY + rng.next(in: 0...container.height),
                                width: rng.next(in: 1...container.width),
                                height: rng.next(in: 1...container.height)
                            )
                        }
                    }
                    let priorities: [Set<WindowID>] = [[], [ids[ids.count / 2]], Set(ids.prefix(2))]
                    let news: [Set<WindowID>] = [[], [ids.last!]]
                    for priority in priorities {
                        for fresh in news {
                            let request = bspRequest(
                                container: container, windowIDs: ids, currentFrames: frames,
                                priorityWindowIDs: priority, newWindowIDs: fresh,
                                splitPolicy: splitPolicy, innerGap: innerGap
                            )
                            let actual = LayoutPlanner.plan(request).placements
                            let expected = ReferenceBSP.plan(request)
                            #expect(actual == expected, "\(splitPolicy) n=\(count) \(container) gap=\(innerGap) prio=\(priority.count) new=\(fresh.count)")
                        }
                    }
                }
            }
        }
    }
}

/// Générateur pseudo-aléatoire déterministe (congruentiel linéaire) pour des cas reproductibles.
private struct Lcg {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next(in range: ClosedRange<CGFloat>) -> CGFloat {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let unit = CGFloat(state >> 11) / CGFloat(1 << 53)
        return (range.lowerBound + unit * (range.upperBound - range.lowerBound)).rounded()
    }
}

/// Ancien algorithme BSP (calcul du ratio qui parcourt les sous-listes même sans priorité),
/// avec l'espacement borné de REL-033, gardé comme référence des placements attendus.
private enum ReferenceBSP {
    static func plan(_ request: LayoutRequest) -> [WindowID: CGRect] {
        var placements: [WindowID: CGRect] = [:]
        guard !request.windowIDs.isEmpty else { return placements }
        split(request.windowIDs[...], request.container.inset(by: request.outerGaps), CGFloat(request.innerGap), request, &placements)
        return placements
    }

    private static func boundedGap(_ gap: CGFloat, extent: CGFloat) -> CGFloat {
        min(gap, max(0, extent - 2 * 10))
    }

    private static func split(
        _ windows: ArraySlice<WindowID>, _ rect: CGRect, _ innerGap: CGFloat,
        _ request: LayoutRequest, _ placements: inout [WindowID: CGRect]
    ) {
        guard let first = windows.first else { return }
        guard windows.count > 1 else {
            placements[first] = rect.integral
            return
        }
        let leftCount = request.splitPolicy == "dwindle" ? 1 : windows.count / 2
        let left = windows.prefix(leftCount)
        let right = windows.dropFirst(leftCount)
        if rect.width >= rect.height {
            let gap = boundedGap(innerGap, extent: rect.width)
            let usable = max(0, rect.width - gap)
            let r = ratio(left, right, rect, true, gap, request)
            let leftWidth = floor(usable * r)
            split(left, CGRect(x: rect.minX, y: rect.minY, width: leftWidth, height: rect.height), innerGap, request, &placements)
            split(right, CGRect(x: rect.minX + leftWidth + gap, y: rect.minY, width: usable - leftWidth, height: rect.height), innerGap, request, &placements)
        } else {
            let gap = boundedGap(max(innerGap, 1), extent: rect.height)
            let usable = max(0, rect.height - gap)
            let r = ratio(left, right, rect, false, gap, request)
            let topHeight = floor(usable * r)
            split(left, CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: topHeight), innerGap, request, &placements)
            split(right, CGRect(x: rect.minX, y: rect.minY + topHeight + gap, width: rect.width, height: usable - topHeight), innerGap, request, &placements)
        }
    }

    private static func union(_ ids: some Sequence<WindowID>, _ frames: [WindowID: CGRect]) -> CGRect? {
        let known = ids.compactMap { frames[$0] }
        guard var result = known.first else { return nil }
        for frame in known.dropFirst() { result = result.union(frame) }
        return result
    }

    private static func clamp(_ value: CGFloat) -> CGFloat { min(0.9, max(0.1, value)) }

    private static func ratio(
        _ left: ArraySlice<WindowID>, _ right: ArraySlice<WindowID>, _ rect: CGRect,
        _ horizontal: Bool, _ innerGap: CGFloat, _ request: LayoutRequest
    ) -> CGFloat {
        let priority = request.priorityWindowIDs
        let fresh = request.newWindowIDs
        let frames = request.currentFrames
        let anyPriority = left.contains { priority.contains($0) } || right.contains { priority.contains($0) }
        if !anyPriority, left.contains(where: { fresh.contains($0) }) || right.contains(where: { fresh.contains($0) }) {
            return 0.5
        }
        guard let leftFrame = union(left, frames), let rightFrame = union(right, frames) else { return 0.5 }
        let usable = horizontal ? rect.width - innerGap : rect.height - innerGap
        guard usable > 0 else { return 0.5 }
        let priorityLeft = union(left.filter { priority.contains($0) }, frames)
        let priorityRight = union(right.filter { priority.contains($0) }, frames)
        let managed = horizontal
            ? abs(leftFrame.minX - rect.minX) <= 12 && abs(rightFrame.maxX - rect.maxX) <= 12
            : abs(leftFrame.minY - rect.minY) <= 12 && abs(rightFrame.maxY - rect.maxY) <= 12
        guard managed else {
            if let priorityLeft { return clamp((horizontal ? priorityLeft.width : priorityLeft.height) / usable) }
            if let priorityRight { return clamp((usable - (horizontal ? priorityRight.width : priorityRight.height)) / usable) }
            return 0.5
        }
        let leftEdge = horizontal ? leftFrame.maxX - rect.minX : leftFrame.maxY - rect.minY
        let rightEdge = horizontal ? rightFrame.minX - innerGap - rect.minX : rightFrame.minY - innerGap - rect.minY
        if let priorityLeft {
            let extent = horizontal ? priorityLeft.width : priorityLeft.height
            return clamp(left.allSatisfy { priority.contains($0) } ? leftEdge / usable : extent / usable)
        }
        if let priorityRight {
            let extent = horizontal ? priorityRight.width : priorityRight.height
            return clamp(right.allSatisfy { priority.contains($0) } ? rightEdge / usable : (usable - extent) / usable)
        }
        return 0.5
    }
}
