import Foundation
import CoreGraphics
import RoadieFXCore

/// Propriété animable d'une fenêtre.
public enum AnimatedProperty: String, Sendable {
    case alpha
    case scale
    case translateX
    case translateY
    case frame
}

/// Valeur portée par une Animation (scalar pour α/scale/translate, rect pour frame).
public enum AnimationValue: Sendable, Equatable {
    case scalar(Double)
    case rect(CGRect)

    /// Lerp linéaire entre 2 valeurs ; eased par le caller via Bézier.
    public static func lerp(from: AnimationValue, to: AnimationValue, t: Double) -> AnimationValue {
        switch (from, to) {
        case (.scalar(let a), .scalar(let b)):
            return .scalar(a + (b - a) * t)
        case (.rect(let a), .rect(let b)):
            return .rect(CGRect(
                x: a.origin.x + (b.origin.x - a.origin.x) * CGFloat(t),
                y: a.origin.y + (b.origin.y - a.origin.y) * CGFloat(t),
                width: a.size.width + (b.size.width - a.size.width) * CGFloat(t),
                height: a.size.height + (b.size.height - a.size.height) * CGFloat(t)
            ))
        default:
            return to
        }
    }
}

/// Clé d'unicité pour coalescing dans la queue : 2 anims sur même (wid, property)
/// → la nouvelle remplace l'ancienne.
public struct AnimationKey: Hashable, Sendable {
    public let wid: CGWindowID
    public let property: AnimatedProperty
    public init(wid: CGWindowID, property: AnimatedProperty) {
        self.wid = wid; self.property = property
    }
}

/// Une animation en cours.
public struct Animation: Sendable {
    public let id: UUID
    public let wid: CGWindowID
    public let property: AnimatedProperty
    public let from: AnimationValue
    public let to: AnimationValue
    public let curve: BezierCurve
    public let startTime: TimeInterval
    public let duration: TimeInterval

    public init(wid: CGWindowID,
                property: AnimatedProperty,
                from: AnimationValue,
                to: AnimationValue,
                curve: BezierCurve,
                startTime: TimeInterval,
                duration: TimeInterval) {
        self.id = UUID()
        self.wid = wid
        self.property = property
        self.from = from
        self.to = to
        self.curve = curve
        self.startTime = startTime
        self.duration = duration
    }

    public var key: AnimationKey { AnimationKey(wid: wid, property: property) }

    /// Valeur interpolée à `now`. Retourne nil si l'animation est terminée.
    public func value(at now: TimeInterval) -> AnimationValue? {
        let progress = (now - startTime) / duration
        guard progress < 1.0 else { return nil }
        let easedT = curve.sample(max(0.0, progress))
        return AnimationValue.lerp(from: from, to: to, t: easedT)
    }

    /// Convertit en commande OSAX selon la propriété.
    public func toCommand(value: AnimationValue) -> OSAXCommand? {
        switch (property, value) {
        case (.alpha, .scalar(let a)):
            return .setAlpha(wid: wid, alpha: a)
        case (.scale, .scalar(let s)):
            return .setTransform(wid: wid, scale: s, tx: 0, ty: 0)
        case (.translateX, .scalar(let x)):
            return .setTransform(wid: wid, scale: 1.0, tx: x, ty: 0)
        case (.translateY, .scalar(let y)):
            return .setTransform(wid: wid, scale: 1.0, tx: 0, ty: y)
        case (.frame, .rect):
            // V1 : pas de OSAXCommand.setFrame (à étendre dans osax). On no-op pour l'instant.
            return nil
        default:
            return nil
        }
    }
}
