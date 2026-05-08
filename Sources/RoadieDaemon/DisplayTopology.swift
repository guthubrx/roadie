import CoreGraphics
import Foundation
import RoadieAX

public enum DisplayTopology {
    public static func neighbor(
        from display: DisplaySnapshot,
        direction: Direction,
        in displays: [DisplaySnapshot]
    ) -> DisplaySnapshot? {
        displays
            .filter { $0.id != display.id }
            .compactMap { candidate -> (display: DisplaySnapshot, score: CGFloat)? in
                let score = neighborScore(from: display.frame.cgRect, to: candidate.frame.cgRect, direction: direction)
                return score.isFinite ? (candidate, score) : nil
            }
            .min { lhs, rhs in lhs.score < rhs.score }?
            .display
    }

    private static func neighborScore(from active: CGRect, to candidate: CGRect, direction: Direction) -> CGFloat {
        let distance: CGFloat
        let overlap: CGFloat
        let perpendicularGap: CGFloat
        let centerDelta: CGFloat

        switch direction {
        case .left:
            guard candidate.midX < active.midX else { return .infinity }
            distance = max(0, active.minX - candidate.maxX)
            overlap = intervalOverlap(active.minY...active.maxY, candidate.minY...candidate.maxY)
            perpendicularGap = intervalGap(active.minY...active.maxY, candidate.minY...candidate.maxY)
            centerDelta = abs(candidate.midY - active.midY)
        case .right:
            guard candidate.midX > active.midX else { return .infinity }
            distance = max(0, candidate.minX - active.maxX)
            overlap = intervalOverlap(active.minY...active.maxY, candidate.minY...candidate.maxY)
            perpendicularGap = intervalGap(active.minY...active.maxY, candidate.minY...candidate.maxY)
            centerDelta = abs(candidate.midY - active.midY)
        case .up:
            guard candidate.midY < active.midY else { return .infinity }
            distance = max(0, active.minY - candidate.maxY)
            overlap = intervalOverlap(active.minX...active.maxX, candidate.minX...candidate.maxX)
            perpendicularGap = intervalGap(active.minX...active.maxX, candidate.minX...candidate.maxX)
            centerDelta = abs(candidate.midX - active.midX)
        case .down:
            guard candidate.midY > active.midY else { return .infinity }
            distance = max(0, candidate.minY - active.maxY)
            overlap = intervalOverlap(active.minX...active.maxX, candidate.minX...candidate.maxX)
            perpendicularGap = intervalGap(active.minX...active.maxX, candidate.minX...candidate.maxX)
            centerDelta = abs(candidate.midX - active.midX)
        }

        let overlapPenalty: CGFloat = overlap > 0 ? 0 : 10_000
        return distance + perpendicularGap * 4 + centerDelta * 0.35 + overlapPenalty
    }

    private static func intervalOverlap(_ lhs: ClosedRange<CGFloat>, _ rhs: ClosedRange<CGFloat>) -> CGFloat {
        max(0, min(lhs.upperBound, rhs.upperBound) - max(lhs.lowerBound, rhs.lowerBound))
    }

    private static func intervalGap(_ lhs: ClosedRange<CGFloat>, _ rhs: ClosedRange<CGFloat>) -> CGFloat {
        if lhs.upperBound < rhs.lowerBound { return rhs.lowerBound - lhs.upperBound }
        if rhs.upperBound < lhs.lowerBound { return lhs.lowerBound - rhs.upperBound }
        return 0
    }
}
