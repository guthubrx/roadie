import CoreGraphics
import RoadieCore

public struct LayoutRequest: Equatable, Sendable {
    public var scope: StageScope
    public var mode: WindowManagementMode
    public var container: CGRect
    public var windowIDs: [WindowID]
    public var currentFrames: [WindowID: CGRect]
    public var priorityWindowIDs: Set<WindowID>
    public var splitPolicy: String
    public var outerGaps: Insets
    public var innerGap: Double

    public init(
        scope: StageScope,
        mode: WindowManagementMode,
        container: CGRect,
        windowIDs: [WindowID],
        currentFrames: [WindowID: CGRect] = [:],
        priorityWindowIDs: Set<WindowID> = [],
        splitPolicy: String = "balanced",
        outerGaps: Insets = .zero,
        innerGap: Double = 0
    ) {
        self.scope = scope
        self.mode = mode
        self.container = container
        self.windowIDs = windowIDs
        self.currentFrames = currentFrames
        self.priorityWindowIDs = priorityWindowIDs
        self.splitPolicy = splitPolicy
        self.outerGaps = outerGaps
        self.innerGap = max(0, innerGap)
    }
}

public struct LayoutPlan: Equatable, Sendable {
    public var placements: [WindowID: CGRect]

    public init(placements: [WindowID: CGRect]) {
        self.placements = placements
    }
}

public struct LayoutCommand: Equatable, Sendable {
    public let windowID: WindowID
    public let frame: CGRect

    public init(windowID: WindowID, frame: CGRect) {
        self.windowID = windowID
        self.frame = frame
    }
}

public enum LayoutPlanner {
    public static func plan(_ request: LayoutRequest) -> LayoutPlan {
        switch request.mode {
        case .bsp:
            return BSPLayoutStrategy().plan(request)
        case .mutableBsp:
            return MutableBSPLayoutStrategy().plan(request)
        case .masterStack:
            return MasterStackLayoutStrategy().plan(request)
        case .float:
            return FloatLayoutStrategy().plan(request)
        }
    }
}

public enum LayoutDiff {
    public static func commands(previous: LayoutPlan?, next: LayoutPlan) -> [LayoutCommand] {
        next.placements.keys.sorted().compactMap { windowID in
            guard let nextFrame = next.placements[windowID] else { return nil }
            if let previousFrame = previous?.placements[windowID],
               previousFrame.isClose(to: nextFrame, positionTolerance: 1, sizeTolerance: 1) {
                return nil
            }
            return LayoutCommand(windowID: windowID, frame: nextFrame)
        }
    }
}

private extension CGRect {
    func isClose(to other: CGRect, positionTolerance: CGFloat = 48, sizeTolerance: CGFloat = 48) -> Bool {
        abs(minX - other.minX) <= positionTolerance
            && abs(minY - other.minY) <= positionTolerance
            && abs(width - other.width) <= sizeTolerance
            && abs(height - other.height) <= sizeTolerance
    }
}
