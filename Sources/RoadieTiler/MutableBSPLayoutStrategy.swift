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
            let gap = innerGap
            let usableWidth = max(0, rect.width - gap)
            let ratio = splitRatio(
                left: leftWindows,
                right: rightWindows,
                rect: rect,
                horizontal: true,
                innerGap: gap,
                currentFrames: currentFrames
            )
            let leftWidth = floor(usableWidth * ratio)
            let rightWidth = usableWidth - leftWidth
            let leftRect = CGRect(x: rect.minX, y: rect.minY, width: leftWidth, height: rect.height)
            let rightRect = CGRect(x: rect.minX + leftWidth + gap, y: rect.minY, width: rightWidth, height: rect.height)
            split(windows: leftWindows, rect: leftRect, innerGap: innerGap, currentFrames: currentFrames, splitPolicy: splitPolicy, placements: &placements)
            split(windows: rightWindows, rect: rightRect, innerGap: innerGap, currentFrames: currentFrames, splitPolicy: splitPolicy, placements: &placements)
        } else {
            let gap = max(innerGap, titleBarSeamGap)
            let usableHeight = max(0, rect.height - gap)
            let ratio = splitRatio(
                left: leftWindows,
                right: rightWindows,
                rect: rect,
                horizontal: false,
                innerGap: gap,
                currentFrames: currentFrames
            )
            let topHeight = floor(usableHeight * ratio)
            let bottomHeight = usableHeight - topHeight
            let topRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: topHeight)
            let bottomRect = CGRect(x: rect.minX, y: rect.minY + topHeight + gap, width: rect.width, height: bottomHeight)
            split(windows: leftWindows, rect: topRect, innerGap: innerGap, currentFrames: currentFrames, splitPolicy: splitPolicy, placements: &placements)
            split(windows: rightWindows, rect: bottomRect, innerGap: innerGap, currentFrames: currentFrames, splitPolicy: splitPolicy, placements: &placements)
        }
    }

    private func splitRatio(
        left: ArraySlice<WindowID>,
        right: ArraySlice<WindowID>,
        rect: CGRect,
        horizontal: Bool,
        innerGap: CGFloat,
        currentFrames: [WindowID: CGRect]
    ) -> CGFloat {
        guard let leftFrame = unionFrame(for: left, in: currentFrames),
              let rightFrame = unionFrame(for: right, in: currentFrames)
        else { return 0.5 }

        let usableExtent = horizontal ? rect.width - innerGap : rect.height - innerGap
        guard usableExtent > 0 else { return 0.5 }

        if managedSplitLooksUsable(leftFrame: leftFrame, rightFrame: rightFrame, rect: rect, horizontal: horizontal) {
            let edge = horizontal ? leftFrame.maxX - rect.minX : leftFrame.maxY - rect.minY
            return (edge / usableExtent).clamped(to: 0.1...0.9)
        }

        let leftExtent = horizontal ? leftFrame.width : leftFrame.height
        let rightExtent = horizontal ? rightFrame.width : rightFrame.height
        let totalObserved = leftExtent + rightExtent
        guard totalObserved > 0 else { return 0.5 }
        return (leftExtent / totalObserved).clamped(to: 0.1...0.9)
    }

    private func managedSplitLooksUsable(leftFrame: CGRect, rightFrame: CGRect, rect: CGRect, horizontal: Bool) -> Bool {
        let tolerance = CGFloat(24)
        if horizontal {
            return leftFrame.minX.isClose(to: rect.minX, tolerance: tolerance)
                && rightFrame.maxX.isClose(to: rect.maxX, tolerance: tolerance)
                && leftFrame.maxX <= rightFrame.minX + tolerance
        }
        return leftFrame.minY.isClose(to: rect.minY, tolerance: tolerance)
            && rightFrame.maxY.isClose(to: rect.maxY, tolerance: tolerance)
            && leftFrame.maxY <= rightFrame.minY + tolerance
    }
}
