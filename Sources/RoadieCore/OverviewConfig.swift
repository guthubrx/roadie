import Foundation

/// Réglages indépendants de la vue globale. Le pourcentage règle la loupe de fenêtre.
public struct OverviewConfig: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var presentation: String
    public var loupe: Bool
    public var magnification: Double
    public var hotkey: String
    /// Flou du fond d’écran, de 0 (net) à 100 (très flou). Défaut léger : 20.
    public var backgroundBlur: Double

    public init(enabled: Bool = true, presentation: String = "archipelago", loupe: Bool = true,
                magnification: Double = 150, hotkey: String = "", backgroundBlur: Double = 20) {
        self.enabled = enabled
        self.presentation = ["archipelago", "bays"].contains(presentation) ? presentation : "archipelago"
        self.loupe = loupe
        self.magnification = magnification.isFinite ? min(250, max(100, magnification)) : 150
        self.hotkey = TargetGridConfig.normalizedKey(hotkey, fallback: "")
        self.backgroundBlur = backgroundBlur.isFinite ? min(100, max(0, backgroundBlur)) : 20
    }

    enum CodingKeys: String, CodingKey {
        case enabled, presentation, loupe, magnification, hotkey
        case backgroundBlur = "background_blur"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
                  presentation: try c.decodeIfPresent(String.self, forKey: .presentation) ?? "archipelago",
                  loupe: try c.decodeIfPresent(Bool.self, forKey: .loupe) ?? true,
                  magnification: try c.decodeFlexibleDouble(forKey: .magnification) ?? 150,
                  hotkey: try c.decodeIfPresent(String.self, forKey: .hotkey) ?? "",
                  backgroundBlur: try c.decodeFlexibleDouble(forKey: .backgroundBlur) ?? 20)
    }
}
