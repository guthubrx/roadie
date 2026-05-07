import CoreGraphics
import RoadieCore

public struct BSPLayoutStrategy: LayoutStrategy {
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
        let horizontal = rect.width >= rect.height

        if horizontal {
            splitHorizontally(
                leftWindows: leftWindows,
                rightWindows: rightWindows,
                rect: rect,
                innerGap: innerGap,
                currentFrames: currentFrames,
                priorityWindowIDs: priorityWindowIDs,
                splitPolicy: splitPolicy,
                placements: &placements
            )
        } else {
            splitVertically(
                topWindows: leftWindows,
                bottomWindows: rightWindows,
                rect: rect,
                innerGap: innerGap,
                currentFrames: currentFrames,
                priorityWindowIDs: priorityWindowIDs,
                splitPolicy: splitPolicy,
                placements: &placements
            )
        }
    }

    private func splitHorizontally(
        leftWindows: ArraySlice<WindowID>,
        rightWindows: ArraySlice<WindowID>,
        rect: CGRect,
        innerGap: CGFloat,
        currentFrames: [WindowID: CGRect],
        priorityWindowIDs: Set<WindowID>,
        splitPolicy: String,
        placements: inout [WindowID: CGRect]
    ) {
        let usableWidth = max(0, rect.width - innerGap)
        let ratio = splitRatio(
            left: leftWindows,
            right: rightWindows,
            rect: rect,
            horizontal: true,
            innerGap: innerGap,
            currentFrames: currentFrames,
            priorityWindowIDs: priorityWindowIDs
        )
        let leftWidth = floor(usableWidth * ratio)
        let rightWidth = usableWidth - leftWidth
        let leftRect = CGRect(x: rect.minX, y: rect.minY, width: leftWidth, height: rect.height)
        let rightRect = CGRect(x: rect.minX + leftWidth + innerGap, y: rect.minY, width: rightWidth, height: rect.height)

        split(windows: leftWindows, rect: leftRect, innerGap: innerGap, currentFrames: currentFrames, priorityWindowIDs: priorityWindowIDs, splitPolicy: splitPolicy, placements: &placements)
        split(windows: rightWindows, rect: rightRect, innerGap: innerGap, currentFrames: currentFrames, priorityWindowIDs: priorityWindowIDs, splitPolicy: splitPolicy, placements: &placements)
    }

    private func splitVertically(
        topWindows: ArraySlice<WindowID>,
        bottomWindows: ArraySlice<WindowID>,
        rect: CGRect,
        innerGap: CGFloat,
        currentFrames: [WindowID: CGRect],
        priorityWindowIDs: Set<WindowID>,
        splitPolicy: String,
        placements: inout [WindowID: CGRect]
    ) {
        let effectiveGap = max(innerGap, titleBarSeamGap)
        let usableHeight = max(0, rect.height - effectiveGap)
        let ratio = splitRatio(
            left: topWindows,
            right: bottomWindows,
            rect: rect,
            horizontal: false,
            innerGap: effectiveGap,
            currentFrames: currentFrames,
            priorityWindowIDs: priorityWindowIDs
        )
        let topHeight = floor(usableHeight * ratio)
        let bottomHeight = usableHeight - topHeight
        let topRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: topHeight)
        let bottomRect = CGRect(x: rect.minX, y: rect.minY + topHeight + effectiveGap, width: rect.width, height: bottomHeight)

        split(windows: topWindows, rect: topRect, innerGap: innerGap, currentFrames: currentFrames, priorityWindowIDs: priorityWindowIDs, splitPolicy: splitPolicy, placements: &placements)
        split(windows: bottomWindows, rect: bottomRect, innerGap: innerGap, currentFrames: currentFrames, priorityWindowIDs: priorityWindowIDs, splitPolicy: splitPolicy, placements: &placements)
    }

    private func splitRatio(
        left: ArraySlice<WindowID>,
        right: ArraySlice<WindowID>,
        rect: CGRect,
        horizontal: Bool,
        innerGap: CGFloat,
        currentFrames: [WindowID: CGRect],
        priorityWindowIDs: Set<WindowID>
    ) -> CGFloat {
        guard let leftFrame = unionFrame(for: left, in: currentFrames),
              let rightFrame = unionFrame(for: right, in: currentFrames)
        else { return 0.5 }

        let usableExtent = horizontal ? rect.width - innerGap : rect.height - innerGap
        guard usableExtent > 0 else { return 0.5 }

        let priorityLeftFrame = unionPriorityFrame(for: left, in: currentFrames, priorityWindowIDs: priorityWindowIDs)
        let priorityRightFrame = unionPriorityFrame(for: right, in: currentFrames, priorityWindowIDs: priorityWindowIDs)

        guard isManagedSplit(leftFrame: leftFrame, rightFrame: rightFrame, rect: rect, horizontal: horizontal) else {
            if let priorityLeftFrame {
                let extent = horizontal ? priorityLeftFrame.width : priorityLeftFrame.height
                return (extent / usableExtent).clamped(to: 0.1...0.9)
            }
            if let priorityRightFrame {
                let extent = horizontal ? priorityRightFrame.width : priorityRightFrame.height
                return ((usableExtent - extent) / usableExtent).clamped(to: 0.1...0.9)
            }
            return 0.5
        }

        let leftEdge = horizontal ? leftFrame.maxX - rect.minX : leftFrame.maxY - rect.minY
        let rightEdge = horizontal ? rightFrame.minX - innerGap - rect.minX : rightFrame.minY - innerGap - rect.minY

        if let priorityLeftFrame {
            let priorityExtent = horizontal ? priorityLeftFrame.width : priorityLeftFrame.height
            let ratio = containsOnlyPriority(left, priorityWindowIDs) ? leftEdge / usableExtent : priorityExtent / usableExtent
            return ratio.clamped(to: 0.1...0.9)
        }
        if let priorityRightFrame {
            let priorityExtent = horizontal ? priorityRightFrame.width : priorityRightFrame.height
            let ratio = containsOnlyPriority(right, priorityWindowIDs) ? rightEdge / usableExtent : (usableExtent - priorityExtent) / usableExtent
            return ratio.clamped(to: 0.1...0.9)
        }
        return 0.5
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

    private func isManagedSplit(leftFrame: CGRect, rightFrame: CGRect, rect: CGRect, horizontal: Bool) -> Bool {
        if horizontal {
            return leftFrame.minX.isClose(to: rect.minX) && rightFrame.maxX.isClose(to: rect.maxX)
        }
        return leftFrame.minY.isClose(to: rect.minY) && rightFrame.maxY.isClose(to: rect.maxY)
    }
}
