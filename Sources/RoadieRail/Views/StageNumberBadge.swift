import SwiftUI

/// SPEC-026 — Badge "numéro de stage" rendu en arrière-plan de chaque cellule
/// du navrail. Décalé en haut-gauche pour dépasser visuellement de la pile de
/// thumbnails (= effet "chiffre comme dernière couche, la plus en arrière").
///
/// Universel : rendu identique pour tous les renderers (parallax-45, mosaic,
/// icons-only, hero-preview, stacked-previews). Pas d'interaction (allowsHitTesting=false).
public struct StageNumberBadge: View {
    public let number: String
    public let colorHex: String   // typiquement la couleur active du stage (vert/rouge/...).

    public init(number: String, colorHex: String = "#FFFFFF") {
        self.number = number
        self.colorHex = colorHex
    }

    public var body: some View {
        Text(number)
            .font(.system(size: 88, weight: .black, design: .rounded))
            .foregroundColor(Color(hex: colorHex).opacity(0.20))
            .shadow(color: Color.black.opacity(0.30), radius: 4, x: 0, y: 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .offset(x: -10, y: -22)
            .allowsHitTesting(false)
    }
}
