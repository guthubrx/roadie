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
        // Pas de frame(maxWidth/maxHeight: .infinity) : sinon le ZStack se
        // redimensionne sur infinity et la cellule devient géante (bug observé).
        // Le badge est positionné dans le coin haut-gauche via le ZStack alignment
        // côté StageStackView, puis l'offset le fait dépasser légèrement.
        Text(number)
            .font(.system(size: 64, weight: .black, design: .rounded))
            .foregroundColor(Color(hex: colorHex).opacity(0.38))
            .shadow(color: Color.black.opacity(0.45), radius: 3, x: 0, y: 1)
            .offset(x: -28, y: -32)
            .allowsHitTesting(false)
            .fixedSize()
    }
}
