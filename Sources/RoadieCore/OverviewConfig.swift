import Foundation

/// Réglages indépendants de la vue globale. Le pourcentage règle la loupe de fenêtre.
public struct OverviewConfig: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var presentation: String
    public var loupe: Bool
    public var magnification: Double
    public var hotkey: String

    public init(enabled: Bool = true, presentation: String = "archipelago", loupe: Bool = true,
                magnification: Double = 150, hotkey: String = "") {
        self.enabled = enabled
        self.presentation = ["archipelago", "bays"].contains(presentation) ? presentation : "archipelago"
        self.loupe = loupe
        self.magnification = magnification.isFinite ? min(250, max(100, magnification)) : 150
        self.hotkey = TargetGridConfig.normalizedKey(hotkey, fallback: "")
    }

    enum CodingKeys: String, CodingKey { case enabled, presentation, loupe, magnification, hotkey }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
                  presentation: try c.decodeIfPresent(String.self, forKey: .presentation) ?? "archipelago",
                  loupe: try c.decodeIfPresent(Bool.self, forKey: .loupe) ?? true,
                  magnification: try c.decodeFlexibleDouble(forKey: .magnification) ?? 150,
                  hotkey: try c.decodeIfPresent(String.self, forKey: .hotkey) ?? "")
    }
}
