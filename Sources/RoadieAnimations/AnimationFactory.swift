import Foundation
import CoreGraphics
import RoadieFXCore

/// Contexte transmis à AnimationFactory pour calculer from/to selon event + état.
public struct EventContext: Sendable {
    public let eventKind: String
    public let timestamp: TimeInterval
    public let wid: CGWindowID?
    public let currentFrame: CGRect?
    public let currentAlpha: Double?
    public let currentScale: Double?
    public let screenWidth: Double?
    public let screenHeight: Double?

    public init(eventKind: String,
                timestamp: TimeInterval = Date().timeIntervalSince1970,
                wid: CGWindowID? = nil,
                currentFrame: CGRect? = nil,
                currentAlpha: Double? = nil,
                currentScale: Double? = nil,
                screenWidth: Double? = nil,
                screenHeight: Double? = nil) {
        self.eventKind = eventKind
        self.timestamp = timestamp
        self.wid = wid
        self.currentFrame = currentFrame
        self.currentAlpha = currentAlpha
        self.currentScale = currentScale
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
    }
}

/// Crée des Animation à partir d'une règle config + contexte d'événement.
/// Modes spéciaux (`pulse`, `crossfade`) génèrent plusieurs animations.
public enum AnimationFactory {
    public static func make(rule: EventRule,
                            context: EventContext,
                            curveLib: BezierLibrary) -> [Animation] {
        guard let wid = context.wid else { return [] }
        guard let curve = curveLib.curve(named: rule.curve) else { return [] }
        let duration = TimeInterval(rule.durationMs) / 1000.0
        let start = context.timestamp

        // Mode pulse : génère 2 animations consécutives (1.0 → 1.02 sur 1ère moitié,
        // 1.02 → 1.0 sur 2ème) sur la propriété scale.
        if rule.mode == "pulse" {
            return makePulse(wid: wid, curve: curve, duration: duration, start: start)
        }

        var animations: [Animation] = []
        for propName in rule.properties {
            guard let prop = AnimatedProperty(rawValue: propName) else { continue }
            if let anim = makeOne(prop: prop, rule: rule, context: context,
                                  curve: curve, duration: duration, start: start) {
                animations.append(anim)
            }
        }
        return animations
    }

    private static func makePulse(wid: CGWindowID, curve: BezierCurve,
                                  duration: TimeInterval, start: TimeInterval) -> [Animation] {
        let half = duration / 2.0
        let up = Animation(wid: wid, property: .scale,
                           from: .scalar(1.0), to: .scalar(1.02),
                           curve: curve, startTime: start, duration: half)
        let down = Animation(wid: wid, property: .scale,
                             from: .scalar(1.02), to: .scalar(1.0),
                             curve: curve, startTime: start + half, duration: half)
        return [up, down]
    }

    private static func makeOne(prop: AnimatedProperty,
                                rule: EventRule,
                                context: EventContext,
                                curve: BezierCurve,
                                duration: TimeInterval,
                                start: TimeInterval) -> Animation? {
        guard let wid = context.wid else { return nil }
        let (from, to) = computeFromTo(prop: prop, rule: rule, context: context)
        guard let f = from, let t = to else { return nil }
        return Animation(wid: wid, property: prop, from: f, to: t,
                         curve: curve, startTime: start, duration: duration)
    }

    /// Détermine (from, to) selon (event, property, context).
    /// Heuristiques :
    /// - window_open + alpha → 0 → 1
    /// - window_open + scale → 0.85 → 1
    /// - window_close + alpha → 1 → 0
    /// - window_close + scale → 1 → 0.85
    /// - desktop_changed + translateX (direction=horizontal) → 0 → ±screenWidth
    /// - stage_changed + alpha (mode=crossfade) → 1 → 0 (l'inverse géré par 2e anim)
    /// - window_focused + scale (mode=pulse) géré dans makePulse
    /// - window_resized + frame → currentFrame → ?? (à fournir externally)
    private static func computeFromTo(prop: AnimatedProperty,
                                      rule: EventRule,
                                      context: EventContext) -> (AnimationValue?, AnimationValue?) {
        switch (rule.event, prop) {
        case ("window_open", .alpha):
            return (.scalar(0.0), .scalar(1.0))
        case ("window_open", .scale):
            return (.scalar(0.85), .scalar(1.0))
        case ("window_close", .alpha):
            return (.scalar(context.currentAlpha ?? 1.0), .scalar(0.0))
        case ("window_close", .scale):
            return (.scalar(context.currentScale ?? 1.0), .scalar(0.85))
        case ("desktop_changed", .translateX):
            let w = context.screenWidth ?? 1440.0
            return (.scalar(0.0), .scalar(rule.direction == "horizontal" ? -w : w))
        case ("stage_changed", .alpha):
            // Crossfade sortant : 1 → 0 (l'entrant est géré séparément par 2e Animation)
            return (.scalar(context.currentAlpha ?? 1.0), .scalar(0.0))
        default:
            return (nil, nil)
        }
    }
}
