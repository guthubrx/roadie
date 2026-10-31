import Foundation

public enum AnimationAction: String, CaseIterable, Codable, Sendable {
    case move, stage, appearance, rail, launcher, switcher, overview
}

public enum MotionCurve: String, Codable, Sendable {
    case linear, easeOut = "ease_out", easeInOut = "ease_in_out", spring

    /// O(1). Le ressort utilise son état et sa vitesse, pas cette courbe temporelle.
    public func progress(_ time: Double) -> Double {
        let t = min(1, max(0, time))
        switch self {
        case .linear, .spring: return t
        case .easeOut: return 1 - pow(1 - t, 3)
        case .easeInOut: return t * t * (3 - 2 * t)
        }
    }
}

public struct MotionPolicy: Equatable, Sendable {
    public var enabled: Bool
    public var curve: MotionCurve
    public var duration: Double
    public var intensity: Double
    public var stiffness: Double
    public var damping: Double

    public init(enabled: Bool = true, curve: MotionCurve = .easeOut, duration: Double = 0.16,
                intensity: Double = 1, stiffness: Double = 700, damping: Double = 1) {
        self.enabled = enabled
        self.curve = curve
        self.duration = min(1, max(0, duration))
        self.intensity = min(1, max(0, intensity))
        self.stiffness = min(1500, max(50, stiffness))
        self.damping = min(2, max(0.3, damping))
    }
}

/// Solution analytique d'un ressort amorti : pas de sous-pas ni dérive dépendant de la cadence.
/// Un retarget conserve naturellement la valeur et la vitesse. O(1).
public struct MotionValue: Equatable, Sendable {
    public var value: Double
    public var velocity: Double
    public init(value: Double, velocity: Double = 0) { self.value = value; self.velocity = velocity }

    public mutating func advance(toward target: Double, dt: Double, stiffness: Double, damping: Double) {
        guard dt > 0, dt.isFinite, target.isFinite else { return }
        let t = min(dt, 0.1), w = sqrt(max(1, stiffness)), z = max(0.01, damping)
        let y = value - target, v = velocity
        let next: Double, speed: Double
        if abs(z - 1) < 0.0001 {
            let e = exp(-w * t), c = v + w * y
            next = e * (y + c * t)
            speed = e * (v - w * c * t)
        } else if z < 1 {
            let wd = w * sqrt(1 - z * z), e = exp(-z * w * t)
            let c = cos(wd * t), s = sin(wd * t)
            next = e * (y * c + (v + z * w * y) / wd * s)
            speed = e * (v * c - (z * w * v + w * w * y) / wd * s)
        } else {
            let r1 = -w * (z - sqrt(z * z - 1)), r2 = -w * (z + sqrt(z * z - 1))
            let a = (v - r2 * y) / (r1 - r2), b = y - a
            next = a * exp(r1 * t) + b * exp(r2 * t)
            speed = a * r1 * exp(r1 * t) + b * r2 * exp(r2 * t)
        }
        value = target + next
        velocity = speed
    }
}

/// Valeurs absentes : héritage de la politique commune. La courbe "inherit" est explicite dans l'UI.
public struct AnimationOverrides: Equatable, Codable, Sendable {
    public var enabled = true
    public var curve = "inherit"
    public var durationMS: Double?
    public var intensity: Double?
    public var stiffness: Double?
    public var damping: Double?
    public init() {}
    enum CodingKeys: String, CodingKey { case enabled, curve, durationMS = "duration_ms", intensity, stiffness, damping }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        curve = try c.decodeIfPresent(String.self, forKey: .curve) ?? "inherit"
        guard curve == "inherit" || MotionCurve(rawValue: curve) != nil else {
            throw DecodingError.dataCorruptedError(forKey: .curve, in: c, debugDescription: "unknown animation curve")
        }
        func number(_ key: CodingKeys, _ range: ClosedRange<Double>) throws -> Double? {
            guard let value = try c.decodeFlexibleDouble(forKey: key) else { return nil }
            guard value.isFinite, range.contains(value) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "animation value outside \(range)")
            }
            return value
        }
        durationMS = try number(.durationMS, 0...1000)
        intensity = try number(.intensity, 0...1)
        stiffness = try number(.stiffness, 50...1500)
        damping = try number(.damping, 0.3...2)
    }
}

public struct AnimationsConfig: Equatable, Codable, Sendable {
    public var enabled = false
    public var profile = "subtle"
    public var curve = "inherit"
    public var durationMS: Double?
    public var intensity: Double?
    public var stiffness: Double?
    public var damping: Double?
    public var move = AnimationOverrides()
    public var stage = AnimationOverrides()
    public var appearance = AnimationOverrides()
    public var rail = AnimationOverrides()
    public var launcher = AnimationOverrides()
    public var switcher = AnimationOverrides()
    public var overview = AnimationOverrides()
    public init() {}

    enum CodingKeys: String, CodingKey {
        case enabled, profile, curve,
             durationMS = "duration_ms", intensity, stiffness, damping,
             move, stage, appearance, rail, launcher, switcher, overview
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let shared = try AnimationOverrides(from: decoder)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        profile = try c.decodeIfPresent(String.self, forKey: .profile) ?? "subtle"
        guard ["none", "subtle", "smooth", "expressive"].contains(profile) else {
            throw DecodingError.dataCorruptedError(forKey: .profile, in: c, debugDescription: "unknown animation profile")
        }
        curve = shared.curve; durationMS = shared.durationMS; intensity = shared.intensity
        stiffness = shared.stiffness; damping = shared.damping
        move = try c.decodeIfPresent(AnimationOverrides.self, forKey: .move) ?? AnimationOverrides()
        stage = try c.decodeIfPresent(AnimationOverrides.self, forKey: .stage) ?? AnimationOverrides()
        appearance = try c.decodeIfPresent(AnimationOverrides.self, forKey: .appearance) ?? AnimationOverrides()
        rail = try c.decodeIfPresent(AnimationOverrides.self, forKey: .rail) ?? AnimationOverrides()
        launcher = try c.decodeIfPresent(AnimationOverrides.self, forKey: .launcher) ?? AnimationOverrides()
        switcher = try c.decodeIfPresent(AnimationOverrides.self, forKey: .switcher) ?? AnimationOverrides()
        overview = try c.decodeIfPresent(AnimationOverrides.self, forKey: .overview) ?? AnimationOverrides()
    }

    public func overrides(for action: AnimationAction) -> AnimationOverrides {
        switch action {
        case .move: move
        case .stage: stage
        case .appearance: appearance
        case .rail: rail
        case .launcher: launcher
        case .switcher: switcher
        case .overview: overview
        }
    }

    /// O(1). Les surcharges d'action gagnent, puis les valeurs communes, puis le profil.
    public func policy(for action: AnimationAction, legacyDuration: Double? = nil, usesAppearanceDefaults: Bool = false) -> MotionPolicy {
        var values = overrides(for: action)
        if usesAppearanceDefaults, action != .appearance {
            values.enabled = values.enabled && appearance.enabled
            if values.curve == "inherit" { values.curve = appearance.curve }
            values.durationMS = values.durationMS ?? appearance.durationMS
            values.intensity = values.intensity ?? appearance.intensity
            values.stiffness = values.stiffness ?? appearance.stiffness
            values.damping = values.damping ?? appearance.damping
        }
        var base: MotionPolicy
        switch profile {
        case "smooth": base = MotionPolicy(curve: .easeInOut, duration: 0.25, intensity: 0.65)
        case "expressive": base = MotionPolicy(curve: .spring, duration: 0.38, intensity: 1, stiffness: 650, damping: 0.75)
        default: base = MotionPolicy(curve: .easeOut, duration: 0.16, intensity: 0.35)
        }
        base.curve = MotionCurve(rawValue: values.curve) ?? MotionCurve(rawValue: curve) ?? base.curve
        base.duration = (values.durationMS ?? durationMS).map { $0 / 1000 } ?? legacyDuration ?? base.duration
        base.intensity = values.intensity ?? intensity ?? base.intensity
        base.stiffness = values.stiffness ?? stiffness ?? base.stiffness
        base.damping = values.damping ?? damping ?? base.damping
        base.enabled = enabled && values.enabled && profile != "none" && base.intensity > 0
            && (base.curve == .spring || base.duration > 0)
        return base
    }
}
