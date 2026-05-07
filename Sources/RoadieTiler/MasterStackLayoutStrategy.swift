import CoreGraphics
import RoadieCore

public struct MasterStackLayoutStrategy: LayoutStrategy {
    public var masterRatio: CGFloat

    public init(masterRatio: CGFloat = 0.6) {
        self.masterRatio = masterRatio.clamped(to: 0.1...0.9)
    }

    public func plan(_ request: LayoutRequest) -> LayoutPlan {
        let windows = request.windowIDs
        guard let master = windows.first else { return LayoutPlan(placements: [:]) }

        let rect = request.container.inset(by: request.outerGaps)
        let gap = CGFloat(request.innerGap)
        guard windows.count > 1 else {
            return LayoutPlan(placements: [master: rect.integral])
        }

        let stack = windows.dropFirst()
        let usableWidth = max(0, rect.width - gap)
        let ratio = adaptiveMasterRatio(
            master: master,
            stack: stack,
            rect: rect,
            gap: gap,
            usableWidth: usableWidth,
            currentFrames: request.currentFrames,
            priorityWindowIDs: request.priorityWindowIDs
        )
        let masterWidth = floor(usableWidth * ratio)
        let stackWidth = usableWidth - masterWidth
        var placements: [WindowID: CGRect] = [
            master: CGRect(x: rect.minX, y: rect.minY, width: masterWidth, height: rect.height).integral
        ]

        let usableHeight = max(0, rect.height - gap * CGFloat(stack.count - 1))
        let baseHeight = floor(usableHeight / CGFloat(stack.count))
        var y = rect.minY
        for (index, windowID) in stack.enumerated() {
            let isLast = index == stack.count - 1
            let height = isLast ? rect.maxY - y : baseHeight
            placements[windowID] = CGRect(
                x: rect.minX + masterWidth + gap,
                y: y,
                width: stackWidth,
                height: height
            ).integral
            y += height + gap
        }

        return LayoutPlan(placements: placements)
    }

    private func adaptiveMasterRatio(
        master: WindowID,
        stack: ArraySlice<WindowID>,
        rect: CGRect,
        gap: CGFloat,
        usableWidth: CGFloat,
        currentFrames: [WindowID: CGRect],
        priorityWindowIDs: Set<WindowID>
    ) -> CGFloat {
        guard usableWidth > 0 else { return masterRatio }

        if priorityWindowIDs.contains(master), let masterFrame = currentFrames[master] {
            return (masterFrame.width / usableWidth).clamped(to: 0.1...0.9)
        }
        if containsPriority(stack, priorityWindowIDs),
           let stackFrame = unionFrame(for: stack, in: currentFrames),
           stackFrame.maxX.isClose(to: rect.maxX) {
            return ((stackFrame.minX - gap - rect.minX) / usableWidth).clamped(to: 0.1...0.9)
        }

        var candidates: [CGFloat] = []
        if let masterFrame = currentFrames[master] {
            candidates.append(masterFrame.width / usableWidth)
        }
        if let stackFrame = unionFrame(for: stack, in: currentFrames), stackFrame.maxX.isClose(to: rect.maxX) {
            candidates.append((stackFrame.minX - gap - rect.minX) / usableWidth)
        }

        return candidates
            .map { $0.clamped(to: 0.1...0.9) }
            .max { abs($0 - masterRatio) < abs($1 - masterRatio) } ?? masterRatio
    }
}
