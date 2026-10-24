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
    /// Contour de la fenêtre sélectionnée (au départ la fenêtre active) : couleur `#RRGGBB[AA]`, épaisseur 1–8 points.
    public var selectionColor: String
    public var selectionWidth: Double

    public init(enabled: Bool = true, presentation: String = "archipelago", loupe: Bool = true,
                magnification: Double = 150, hotkey: String = "", backgroundBlur: Double = 20,
                selectionColor: String = "#66C2F7", selectionWidth: Double = 2) {
        self.enabled = enabled
        self.presentation = ["archipelago", "bays"].contains(presentation) ? presentation : "archipelago"
        self.loupe = loupe
        self.magnification = magnification.isFinite ? min(250, max(100, magnification)) : 150
        self.hotkey = TargetGridConfig.normalizedKey(hotkey, fallback: "")
        self.backgroundBlur = backgroundBlur.isFinite ? min(100, max(0, backgroundBlur)) : 20
        self.selectionColor = selectionColor
        self.selectionWidth = selectionWidth.isFinite ? min(8, max(1, selectionWidth)) : 2
    }

    enum CodingKeys: String, CodingKey {
        case enabled, presentation, loupe, magnification, hotkey
        case backgroundBlur = "background_blur"
        case selectionColor = "selection_color"
        case selectionWidth = "selection_width"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
                  presentation: try c.decodeIfPresent(String.self, forKey: .presentation) ?? "archipelago",
                  loupe: try c.decodeIfPresent(Bool.self, forKey: .loupe) ?? true,
                  magnification: try c.decodeFlexibleDouble(forKey: .magnification) ?? 150,
                  hotkey: try c.decodeIfPresent(String.self, forKey: .hotkey) ?? "",
                  backgroundBlur: try c.decodeFlexibleDouble(forKey: .backgroundBlur) ?? 20,
                  selectionColor: try c.decodeIfPresent(String.self, forKey: .selectionColor) ?? "#66C2F7",
                  selectionWidth: try c.decodeFlexibleDouble(forKey: .selectionWidth) ?? 2)
    }
}
