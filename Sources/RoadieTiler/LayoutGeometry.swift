import CoreGraphics
import RoadieCore

func unionFrame(for windowIDs: ArraySlice<WindowID>, in frames: [WindowID: CGRect]) -> CGRect? {
    let knownFrames = windowIDs.compactMap { frames[$0] }
    guard var result = knownFrames.first else { return nil }
    for frame in knownFrames.dropFirst() {
        result = result.union(frame)
    }
    return result
}

func containsPriority(_ windowIDs: ArraySlice<WindowID>, _ priorityWindowIDs: Set<WindowID>) -> Bool {
    windowIDs.contains { priorityWindowIDs.contains($0) }
}

extension CGFloat {
    func isClose(to other: CGFloat, tolerance: CGFloat = 48) -> Bool {
        abs(self - other) <= tolerance
    }

    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
