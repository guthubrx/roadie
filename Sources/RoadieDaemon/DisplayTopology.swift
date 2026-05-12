import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore

public struct DisplayMatchDecision: Equatable, Sendable {
    public var displayID: DisplayID?
    public var confidence: Double
    public var isAmbiguous: Bool
    public var candidateDisplayIDs: [DisplayID]

    public init(
        displayID: DisplayID?,
        confidence: Double,
        isAmbiguous: Bool,
        candidateDisplayIDs: [DisplayID]
    ) {
        self.displayID = displayID
        self.confidence = confidence
        self.isAmbiguous = isAmbiguous
        self.candidateDisplayIDs = candidateDisplayIDs
    }
}

public enum DisplayTopology {
    public static func recognizeDisplay(
        for fingerprint: DisplayFingerprint,
        in displays: [DisplaySnapshot]
    ) -> DisplayMatchDecision {
        if let previousDisplayID = fingerprint.previousDisplayID,
           displays.contains(where: { $0.id == previousDisplayID }) {
            return DisplayMatchDecision(
                displayID: previousDisplayID,
                confidence: 1.0,
                isAmbiguous: false,
                candidateDisplayIDs: [previousDisplayID]
            )
        }

        let scored = displays
            .map { display in
                let candidate = DisplayFingerprint(display: display)
                return (
                    displayID: display.id,
                    score: fingerprintScore(expected: fingerprint, candidate: candidate)
                )
            }
            .filter { $0.score >= 0.70 }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.displayID.rawValue < rhs.displayID.rawValue
                }
                return lhs.score > rhs.score
            }

        guard let best = scored.first else {
            return DisplayMatchDecision(displayID: nil, confidence: 0, isAmbiguous: false, candidateDisplayIDs: [])
        }

        let tied = scored.filter { abs($0.score - best.score) < 0.001 }
        if tied.count > 1 {
            return DisplayMatchDecision(
                displayID: nil,
                confidence: best.score,
                isAmbiguous: true,
                candidateDisplayIDs: tied.map(\.displayID)
            )
        }

        let runnerUp = scored.dropFirst().first?.score ?? 0
        guard best.score - runnerUp >= 0.15 || runnerUp == 0 else {
            return DisplayMatchDecision(
                displayID: nil,
                confidence: best.score,
                isAmbiguous: true,
                candidateDisplayIDs: scored.prefix(2).map(\.displayID)
            )
        }

        return DisplayMatchDecision(
            displayID: best.displayID,
            confidence: best.score,
            isAmbiguous: false,
            candidateDisplayIDs: [best.displayID]
        )
    }

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

        guard overlap >= minimumRequiredOverlap(for: active, candidate: candidate, direction: direction) else {
            return .infinity
        }
        let overlapPenalty: CGFloat = overlap > 0 ? 0 : 10_000
        return distance + perpendicularGap * 4 + centerDelta * 0.35 + overlapPenalty
    }

    private static func minimumRequiredOverlap(for active: CGRect, candidate: CGRect, direction: Direction) -> CGFloat {
        let activeSpan: CGFloat
        let candidateSpan: CGFloat
        switch direction {
        case .left, .right:
            activeSpan = active.height
            candidateSpan = candidate.height
        case .up, .down:
            activeSpan = active.width
            candidateSpan = candidate.width
        }
        return max(80, min(activeSpan, candidateSpan) * 0.20)
    }

    private static func intervalOverlap(_ lhs: ClosedRange<CGFloat>, _ rhs: ClosedRange<CGFloat>) -> CGFloat {
        max(0, min(lhs.upperBound, rhs.upperBound) - max(lhs.lowerBound, rhs.lowerBound))
    }

    private static func intervalGap(_ lhs: ClosedRange<CGFloat>, _ rhs: ClosedRange<CGFloat>) -> CGFloat {
        if lhs.upperBound < rhs.lowerBound { return rhs.lowerBound - lhs.upperBound }
        if rhs.upperBound < lhs.lowerBound { return lhs.lowerBound - rhs.upperBound }
        return 0
    }

    private static func fingerprintScore(expected: DisplayFingerprint, candidate: DisplayFingerprint) -> Double {
        var score = 0.0
        if expected.nameKey == candidate.nameKey { score += 0.35 }
        if expected.sizeKey == candidate.sizeKey { score += 0.30 }
        if expected.visibleSizeKey == candidate.visibleSizeKey { score += 0.20 }
        if expected.positionKey == candidate.positionKey { score += 0.10 }
        if expected.mainHint == candidate.mainHint { score += 0.05 }
        return score
    }
}
