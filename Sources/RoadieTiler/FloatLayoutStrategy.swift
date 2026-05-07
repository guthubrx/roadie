import CoreGraphics
import RoadieCore

public struct FloatLayoutStrategy: LayoutStrategy {
    public init() {}

    public func plan(_ request: LayoutRequest) -> LayoutPlan {
        var placements: [WindowID: CGRect] = [:]
        for windowID in request.windowIDs {
            if let frame = request.currentFrames[windowID] {
                placements[windowID] = frame
            }
        }
        return LayoutPlan(placements: placements)
    }
}
