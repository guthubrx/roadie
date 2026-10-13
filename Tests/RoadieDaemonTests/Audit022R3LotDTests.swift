import CoreGraphics
import Testing
@testable import RoadieDaemon

/// Session 022, round 3, lot D : R2-05 (géométrie de la pastille de groupe de la bordure).
/// R2-06 est couvert dans `Audit022R2LotGTests`.
struct Audit022R3LotDTests {
    private let thickness: CGFloat = 2
    private let textSize = CGSize(width: 40, height: 14)

    /// Cas normal : même position et même taille qu'avant la borne.
    @Test
    func normalCaseKeepsOriginalGeometry() throws {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let geometry = try #require(BorderGroupPill.geometry(bounds: bounds, thickness: thickness, textSize: textSize))
        #expect(geometry.pill == CGRect(x: 400 - 2 - 8 - 52, y: 300 - 2 - 6 - 18, width: 52, height: 18))
        #expect(geometry.text == CGRect(x: geometry.pill.minX + 6, y: geometry.pill.minY + 2, width: 40, height: 14))
    }

    /// Libellé long sur fenêtre étroite : largeur bornée, origine dans la bordure, texte contenu.
    @Test
    func longLabelOnNarrowWindowIsClamped() throws {
        let bounds = CGRect(x: 0, y: 0, width: 80, height: 200)
        let long = CGSize(width: 300, height: 14)
        let geometry = try #require(BorderGroupPill.geometry(bounds: bounds, thickness: thickness, textSize: long))
        #expect(geometry.pill.minX >= thickness + BorderGroupPill.rightMargin)
        #expect(geometry.pill.maxX == bounds.maxX - thickness - BorderGroupPill.rightMargin)
        #expect(geometry.pill.width == 80 - 2 * (thickness + BorderGroupPill.rightMargin))
        #expect(geometry.text.width == geometry.pill.width - 12)
        #expect(geometry.text.minX >= geometry.pill.minX)
        #expect(geometry.text.maxX <= geometry.pill.maxX)
    }

    /// Fenêtre très petite (largeur ou hauteur) : aucune pastille.
    @Test
    func tinyWindowDrawsNothing() {
        #expect(BorderGroupPill.geometry(bounds: CGRect(x: 0, y: 0, width: 30, height: 200), thickness: thickness, textSize: textSize) == nil)
        #expect(BorderGroupPill.geometry(bounds: CGRect(x: 0, y: 0, width: 400, height: 25), thickness: thickness, textSize: textSize) == nil)
        #expect(BorderGroupPill.geometry(bounds: .zero, thickness: thickness, textSize: textSize) == nil)
    }

    /// Cas limite : à la largeur minimale exacte, la pastille tient.
    @Test
    func minimumWidthStillFits() throws {
        let width = 2 * (thickness + BorderGroupPill.rightMargin) + BorderGroupPill.minimumTextWidth + 12
        let geometry = try #require(BorderGroupPill.geometry(
            bounds: CGRect(x: 0, y: 0, width: width, height: 200), thickness: thickness, textSize: CGSize(width: 100, height: 14)
        ))
        #expect(geometry.pill.minX == thickness + BorderGroupPill.rightMargin)
        #expect(geometry.text.width == BorderGroupPill.minimumTextWidth)
    }
}
