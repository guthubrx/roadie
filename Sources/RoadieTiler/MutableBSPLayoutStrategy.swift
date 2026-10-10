import CoreGraphics
import RoadieCore

public struct MutableBSPLayoutStrategy: LayoutStrategy {
    private let titleBarSeamGap: CGFloat = 1

    public init() {}

    public func plan(_ request: LayoutRequest) -> LayoutPlan {
        let windows = request.windowIDs
        guard !windows.isEmpty else { return LayoutPlan(placements: [:]) }

        var placements: [WindowID: CGRect] = [:]
        split(
            windows: windows[...],
            rect: request.container.inset(by: request.outerGaps),
            innerGap: CGFloat(request.innerGap),
            currentFrames: request.currentFrames,
            priorityWindowIDs: request.priorityWindowIDs,
            newWindowIDs: request.newWindowIDs,
            splitPolicy: request.splitPolicy,
            placements: &placements
        )
        return LayoutPlan(placements: placements)
    }

    private func split(
        windows: ArraySlice<WindowID>,
        rect: CGRect,
        innerGap: CGFloat,
        currentFrames: [WindowID: CGRect],
        priorityWindowIDs: Set<WindowID>,
        newWindowIDs: Set<WindowID>,
        splitPolicy: String,
        placements: inout [WindowID: CGRect]
    ) {
        guard let first = windows.first else { return }
        guard windows.count > 1 else {
            placements[first] = rect.integral
            return
        }

        let leftCount = splitPolicy == "dwindle" ? 1 : windows.count / 2
        let leftWindows = windows.prefix(leftCount)
        let rightWindows = windows.dropFirst(leftCount)
        let horizontal = splitHorizontally(
            left: leftWindows,
            right: rightWindows,
            rect: rect,
            currentFrames: currentFrames
        )

        if horizontal {
            let gap = innerGap
            let usableWidth = max(0, rect.width - gap)
            let ratio = splitRatio(
                left: leftWindows,
                right: rightWindows,
                rect: rect,
                horizontal: true,
                innerGap: gap,
                currentFrames: currentFrames,
                priorityWindowIDs: priorityWindowIDs,
                newWindowIDs: newWindowIDs
            )
            let leftWidth = floor(usableWidth * ratio)
            let rightWidth = usableWidth - leftWidth
            let leftRect = CGRect(x: rect.minX, y: rect.minY, width: leftWidth, height: rect.height)
            let rightRect = CGRect(x: rect.minX + leftWidth + gap, y: rect.minY, width: rightWidth, height: rect.height)
            split(windows: leftWindows, rect: leftRect, innerGap: innerGap, currentFrames: currentFrames, priorityWindowIDs: priorityWindowIDs, newWindowIDs: newWindowIDs, splitPolicy: splitPolicy, placements: &placements)
            split(windows: rightWindows, rect: rightRect, innerGap: innerGap, currentFrames: currentFrames, priorityWindowIDs: priorityWindowIDs, newWindowIDs: newWindowIDs, splitPolicy: splitPolicy, placements: &placements)
        } else {
            let gap = max(innerGap, titleBarSeamGap)
            let usableHeight = max(0, rect.height - gap)
            let ratio = splitRatio(
                left: leftWindows,
                right: rightWindows,
                rect: rect,
                horizontal: false,
                innerGap: gap,
                currentFrames: currentFrames,
                priorityWindowIDs: priorityWindowIDs,
                newWindowIDs: newWindowIDs
            )
            let topHeight = floor(usableHeight * ratio)
            let bottomHeight = usableHeight - topHeight
            let topRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: topHeight)
            let bottomRect = CGRect(x: rect.minX, y: rect.minY + topHeight + gap, width: rect.width, height: bottomHeight)
            split(windows: leftWindows, rect: topRect, innerGap: innerGap, currentFrames: currentFrames, priorityWindowIDs: priorityWindowIDs, newWindowIDs: newWindowIDs, splitPolicy: splitPolicy, placements: &placements)
            split(windows: rightWindows, rect: bottomRect, innerGap: innerGap, currentFrames: currentFrames, priorityWindowIDs: priorityWindowIDs, newWindowIDs: newWindowIDs, splitPolicy: splitPolicy, placements: &placements)
        }
    }

    private func splitRatio(
        left: ArraySlice<WindowID>,
        right: ArraySlice<WindowID>,
        rect: CGRect,
        horizontal: Bool,
        innerGap: CGFloat,
        currentFrames: [WindowID: CGRect],
        priorityWindowIDs: Set<WindowID>,
        newWindowIDs: Set<WindowID>
    ) -> CGFloat {
        // Une nouvelle fenetre n'a pas de taille "voulue" : sa frame courante est la
        // position arbitraire de macOS. On split donc 50/50 plutot que d'heriter de
        // cette frame. Exception : si un resize explicite (priority) est en cours dans
        // ce split, on laisse le calcul priority habituel (le resize gagne, meme si
        // l'autre cote est une nouvelle fenetre).
        let anyPriority = left.contains { priorityWindowIDs.contains($0) }
            || right.contains { priorityWindowIDs.contains($0) }
        if !anyPriority {
            let leftHasNew = left.contains { newWindowIDs.contains($0) }
            let rightHasNew = right.contains { newWindowIDs.contains($0) }
            if leftHasNew || rightHasNew {
                return 0.5
            }
        }

        guard let leftFrame = unionFrame(for: left, in: currentFrames),
              let rightFrame = unionFrame(for: right, in: currentFrames)
        else { return 0.5 }

        let usableExtent = horizontal ? rect.width - innerGap : rect.height - innerGap
        guard usableExtent > 0 else { return 0.5 }

        let priorityLeftFrame = unionPriorityFrame(for: left, in: currentFrames, priorityWindowIDs: priorityWindowIDs)
        let priorityRightFrame = unionPriorityFrame(for: right, in: currentFrames, priorityWindowIDs: priorityWindowIDs)
        if let priorityLeftFrame {
            let leftEdge = horizontal ? priorityLeftFrame.maxX - rect.minX : priorityLeftFrame.maxY - rect.minY
            let extent = horizontal ? priorityLeftFrame.width : priorityLeftFrame.height
            let ratio = containsOnlyPriority(left, priorityWindowIDs) ? leftEdge / usableExtent : extent / usableExtent
            return ratio.clamped(to: 0.1...0.9)
        }
        if let priorityRightFrame {
            let rightEdge = horizontal ? priorityRightFrame.minX - innerGap - rect.minX : priorityRightFrame.minY - innerGap - rect.minY
            let extent = horizontal ? priorityRightFrame.width : priorityRightFrame.height
            let ratio = containsOnlyPriority(right, priorityWindowIDs) ? rightEdge / usableExtent : (usableExtent - extent) / usableExtent
            return ratio.clamped(to: 0.1...0.9)
        }

        if managedSplitLooksUsable(leftFrame: leftFrame, rightFrame: rightFrame, rect: rect, horizontal: horizontal, innerGap: innerGap) {
            let edge = horizontal ? leftFrame.maxX - rect.minX : leftFrame.maxY - rect.minY
            return (edge / usableExtent).clamped(to: 0.1...0.9)
        }

        let leftExtent = horizontal ? leftFrame.width : leftFrame.height
        let rightExtent = horizontal ? rightFrame.width : rightFrame.height
        let totalObserved = leftExtent + rightExtent
        guard totalObserved > 0 else { return 0.5 }
        return (leftExtent / totalObserved).clamped(to: 0.1...0.9)
    }

    private func unionPriorityFrame(
        for windows: ArraySlice<WindowID>,
        in currentFrames: [WindowID: CGRect],
        priorityWindowIDs: Set<WindowID>
    ) -> CGRect? {
        let filtered = windows.filter { priorityWindowIDs.contains($0) }
        return unionFrame(for: filtered[...], in: currentFrames)
    }

    private func containsOnlyPriority(_ windows: ArraySlice<WindowID>, _ priorityWindowIDs: Set<WindowID>) -> Bool {
        windows.allSatisfy { priorityWindowIDs.contains($0) }
    }

    private func splitHorizontally(
        left: ArraySlice<WindowID>,
        right: ArraySlice<WindowID>,
        rect: CGRect,
        currentFrames: [WindowID: CGRect]
    ) -> Bool {
        guard let leftFrame = unionFrame(for: left, in: currentFrames),
              let rightFrame = unionFrame(for: right, in: currentFrames)
        else {
            return rect.width >= rect.height
        }

        let tolerance = CGFloat(24)
        let xOverlap = overlap(
            leftFrame.minX...leftFrame.maxX,
            rightFrame.minX...rightFrame.maxX
        )
        let yOverlap = overlap(
            leftFrame.minY...leftFrame.maxY,
            rightFrame.minY...rightFrame.maxY
        )
        let xOverlapRatio = xOverlap / max(1, min(leftFrame.width, rightFrame.width))
        let yOverlapRatio = yOverlap / max(1, min(leftFrame.height, rightFrame.height))

        let sideBySide = yOverlapRatio >= 0.45
            && (leftFrame.maxX <= rightFrame.minX + tolerance || rightFrame.maxX <= leftFrame.minX + tolerance)
        if sideBySide {
            return true
        }

        let stacked = xOverlapRatio >= 0.45
            && (leftFrame.maxY <= rightFrame.minY + tolerance || rightFrame.maxY <= leftFrame.minY + tolerance)
        if stacked {
            return false
        }

        if abs(xOverlapRatio - yOverlapRatio) >= 0.15 {
            return yOverlapRatio > xOverlapRatio
        }

        return rect.width >= rect.height
    }

    private func overlap(_ lhs: ClosedRange<CGFloat>, _ rhs: ClosedRange<CGFloat>) -> CGFloat {
        max(0, min(lhs.upperBound, rhs.upperBound) - max(lhs.lowerBound, rhs.lowerBound))
    }

    // L'écart signé entre les deux côtés (négatif = chevauchement) doit rester proche de la
    // marge intérieure configurée ; la tolérance en dérive (SPEC-016 FR-041).
    private func managedSplitLooksUsable(
        leftFrame: CGRect,
        rightFrame: CGRect,
        rect: CGRect,
        horizontal: Bool,
        innerGap: CGFloat
    ) -> Bool {
        let edgeTolerance = CGFloat(24)
        let gapTolerance = LayoutTolerance.innerGapTolerance(gapsInner: innerGap)
        if horizontal {
            return leftFrame.minX.isClose(to: rect.minX, tolerance: edgeTolerance)
                && rightFrame.maxX.isClose(to: rect.maxX, tolerance: edgeTolerance)
                && abs(rightFrame.minX - leftFrame.maxX - innerGap) <= gapTolerance
        }
        return leftFrame.minY.isClose(to: rect.minY, tolerance: edgeTolerance)
            && rightFrame.maxY.isClose(to: rect.maxY, tolerance: edgeTolerance)
            && abs(rightFrame.minY - leftFrame.maxY - innerGap) <= gapTolerance
    }
}
