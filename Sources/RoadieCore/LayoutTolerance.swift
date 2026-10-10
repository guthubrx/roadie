import CoreGraphics

/// Seuils de tolérance du moteur de disposition, définis en un seul endroit (SPEC-016 FR-041).
/// Les valeurs en points sont des écarts de cadre ; celles liées aux marges se calculent depuis la config.
public enum LayoutTolerance {
    /// Écart au-delà duquel un cadre observé est considéré comme modifié hors de Roadie.
    public static let observedChange: CGFloat = 16
    /// Écart maximal entre un cadre et l'écran pour parler de fenêtre « qui couvre l'écran ».
    /// Ne suffit jamais seul à déclarer un plein écran (SPEC-016 FR-001).
    public static let fullscreenFrame: CGFloat = 48
    /// Rétrécissement refusé par une application au-delà duquel on mémorise un refus de taille.
    public static let clampShrink: CGFloat = 24
    /// Agrandissement minimal (en points) avant de considérer une croissance comme refusée.
    public static let growthMinimum: CGFloat = 64
    /// Agrandissement minimal relatif avant de considérer une croissance comme refusée.
    public static let growthRatio: CGFloat = 0.35

    /// Tolérance sur l'écart entre deux fenêtres voisines, dérivée de la marge intérieure configurée.
    public static func innerGapTolerance(gapsInner: CGFloat) -> CGFloat {
        max(8, gapsInner * 0.5)
    }
}
