import Foundation

/// Section `[fx.borders]` du roadies.toml.
public struct BordersConfig: Codable, Sendable {
    public var enabled: Bool = false
    public var thickness: Int = 2
    public var activeColor: String = "#7AA2F7"
    public var inactiveColor: String = "#414868"
    public var pulseOnFocus: Bool = true
    public var stageOverrides: [StageOverride] = []

    public init() {}

    enum CodingKeys: String, CodingKey {
        case enabled, thickness
        case activeColor = "active_color"
        case inactiveColor = "inactive_color"
        case pulseOnFocus = "pulse_on_focus"
        case stageOverrides = "stage_overrides"
    }

    /// Validation : thickness ∈ [0, 20]. Hors range = clamp + log warning.
    public var clampedThickness: Int {
        max(0, min(20, thickness))
    }
}

public struct StageOverride: Codable, Sendable, Equatable {
    public let stageID: String
    public let activeColor: String?

    enum CodingKeys: String, CodingKey {
        case stageID = "stage_id"
        case activeColor = "active_color"
    }
}

/// Représentation RGBA d'une couleur (0-255).
public struct RGBA: Sendable, Equatable {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8
    public let a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
}

/// Parse une couleur hex `#RRGGBB` ou `#RRGGBBAA`. Retourne nil si format invalide.
public func parseHexColor(_ hex: String) -> RGBA? {
    var s = hex
    if s.hasPrefix("#") { s.removeFirst() }
    let len = s.count
    guard len == 6 || len == 8 else { return nil }
    var rgba: UInt64 = 0
    guard Scanner(string: s).scanHexInt64(&rgba) else { return nil }
    if len == 6 {
        return RGBA(r: UInt8((rgba >> 16) & 0xFF),
                    g: UInt8((rgba >> 8) & 0xFF),
                    b: UInt8(rgba & 0xFF))
    } else {
        return RGBA(r: UInt8((rgba >> 24) & 0xFF),
                    g: UInt8((rgba >> 16) & 0xFF),
                    b: UInt8((rgba >> 8) & 0xFF),
                    a: UInt8(rgba & 0xFF))
    }
}

/// Résolution couleur active selon stage courant. Retourne la couleur globale si
/// aucun override match.
public func activeColor(forStage stageID: String?,
                        config: BordersConfig) -> String {
    if let sid = stageID,
       let override = config.stageOverrides.first(where: { $0.stageID == sid }),
       let c = override.activeColor {
        return c
    }
    return config.activeColor
}
