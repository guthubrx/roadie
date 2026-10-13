import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

/// Session 022, round 4, lot T8 : REL-039 (rang de réorganisation du rail converti dans l'ordre complet
/// des stages, stages vides comprises) et REL-040 (clic parallax testé sur la vignette réellement dessinée).
@MainActor
struct Audit022R4LotT8Tests {
    // MARK: - REL-039

    private static func id(_ raw: String) -> StageID { StageID(rawValue: raw) }

    private static func member(_ raw: UInt32) -> PersistentStageMember {
        PersistentStageMember(
            windowID: WindowID(rawValue: raw),
            bundleID: "com.example.app\(raw)",
            title: "w\(raw)",
            frame: Rect(x: 0, y: 0, width: 100, height: 100)
        )
    }

    /// Stages dans l'ordre persistant : un identifiant suivi d'un nombre de membres (0 = stage vide).
    private static func scope(_ layout: [(String, Int)]) -> PersistentStageScope {
        var window: UInt32 = 0
        let stages = layout.map { raw, count -> PersistentStage in
            let members = (0..<count).map { _ -> PersistentStageMember in
                window += 1
                return member(window)
            }
            return PersistentStage(id: id(raw), members: members)
        }
        return PersistentStageScope(displayID: DisplayID(rawValue: "d"), stages: stages)
    }

    /// Chemin panneau -> store : rang calculé par le rail puis appliqué par reorderStage.
    /// Retourne l'ordre visible (stages non vides) après la réorganisation.
    private static func visibleOrderAfterDrop(
        _ layout: [(String, Int)],
        source: String,
        targets: [(String, CGFloat)],
        pointY: CGFloat
    ) -> [String]? {
        var scope = scope(layout)
        guard let position = RailPanel.persistentReorderPosition(
            pointY: pointY,
            targets: targets.map { (stageID: id($0.0), midY: $0.1) },
            orderedStageIDs: scope.stages.map(\.id),
            sourceStageID: id(source)
        ) else { return nil }
        let reordered = scope.reorderStage(id(source), to: position)
        #expect(reordered)
        return scope.stages.filter { !$0.members.isEmpty }.map(\.id.rawValue)
    }

    @Test func rel039GlisserSousLaDerniereCarteMalgreUneStageVideAvant() {
        // [1 vide, 2, 3] ; le rail montre [2, 3] ; glisser 2 sous la carte 3 (y plus petit en AppKit).
        let order = Self.visibleOrderAfterDrop(
            [("1", 0), ("2", 1), ("3", 1)], source: "2", targets: [("3", 100)], pointY: 50
        )
        #expect(order == ["3", "2"])
    }

    @Test func rel039GlisserEntreDeuxCartesSepareesParUneStageVide() {
        // [1, 2 vide, 3, 4] ; le rail montre [1, 3, 4] ; glisser 1 entre 3 et 4.
        let order = Self.visibleOrderAfterDrop(
            [("1", 1), ("2", 0), ("3", 1), ("4", 1)],
            source: "1", targets: [("3", 200), ("4", 100)], pointY: 150
        )
        #expect(order == ["3", "1", "4"])
    }

    @Test func rel039GlisserVersLeHautAvecStagesVides() {
        // [0 vide, 1, 2 vide, 3] ; glisser 3 au-dessus de 1.
        let order = Self.visibleOrderAfterDrop(
            [("0", 0), ("1", 1), ("2", 0), ("3", 1)],
            source: "3", targets: [("1", 200)], pointY: 250
        )
        #expect(order == ["3", "1"])
    }

    @Test func rel039GlisserApresLaDerniereCarteAvecStageVideApres() {
        // [2, 3, 4 vide] ; glisser 2 sous 3 : la stage vide finale ne doit pas gêner.
        let order = Self.visibleOrderAfterDrop(
            [("2", 1), ("3", 1), ("4", 0)], source: "2", targets: [("3", 100)], pointY: 50
        )
        #expect(order == ["3", "2"])
    }

    @Test func rel039UneSeuleCarteNeDonneAucunRang() {
        let position = RailPanel.persistentReorderPosition(
            pointY: 50,
            targets: [],
            orderedStageIDs: [Self.id("1"), Self.id("2")],
            sourceStageID: Self.id("2")
        )
        #expect(position == nil)
    }

    // MARK: - REL-040

    private static func card(mode: RailRenderMode, rotation: CGFloat = 35) -> StageCardView {
        var config = RailVisualConfig()
        config.mode = mode
        config.parallaxRotation = rotation
        let stage = PersistentStage(id: id("1"), members: [member(1), member(2)])
        let card = StageCardView(
            stage: stage,
            displayLabel: "1",
            isActive: false,
            accent: .systemGreen,
            config: config,
            presentationStates: [:],
            thumbnails: [:]
        )
        // Carte de 224×170 du scénario de l'audit (hauteur max(150, 104 + 66)).
        card.frame = CGRect(x: 0, y: 0, width: 224, height: 170)
        return card
    }

    @Test func rel040TransformeeParallaxCommuneAuDessin() {
        let rect = CGRect(x: 30.6, y: 42, width: 160, height: 86)
        let drawnMinX = CGPoint(x: rect.minX, y: rect.midY)
            .applying(StageCardView.parallaxTransform(for: rect, rotation: 35)).x
        #expect(abs(drawnMinX - 45.06784) < 0.001)
        #expect(StageCardView.parallaxTransform(for: rect, rotation: 0).isIdentity)
        // Rotation bornée à 75° et compression bornée à 0,45 : la transformée reste inversible.
        let clamped = StageCardView.parallaxTransform(for: rect, rotation: 120)
        #expect(abs(clamped.a - 0.45) < 0.0001)
        #expect(abs(clamped.b - sin(75 * CGFloat.pi / 180) * 0.12) < 0.0001)
    }

    @Test func rel040LeClicParallaxViseLaVignetteDessinee() {
        let card = Self.card(mode: .parallax)
        // (35, 90) est dans le rectangle brut du premier aperçu mais hors de sa forme dessinée ;
        // seule la seconde vignette est visible à cet endroit.
        #expect(card.windowID(at: CGPoint(x: 35, y: 90)) == WindowID(rawValue: 2))
        // Le centre du premier aperçu reste à la première vignette, dessinée au-dessus.
        #expect(card.windowID(at: CGPoint(x: 110.6, y: 85)) == WindowID(rawValue: 1))
    }

    @Test func rel040LePointDePriseUtiliseLePointLocalDeLaVignette() throws {
        let card = Self.card(mode: .parallax)
        let payload = try #require(card.dragPayload(at: CGPoint(x: 35, y: 90)))
        #expect(payload.windowID == WindowID(rawValue: 2))
        // Second aperçu brut (12, 63.44, 147.2, 79.12) ; point local (23.82881, 94.25166).
        #expect(abs(payload.grabUnit.x - (23.82881 - 12) / 147.2) < 0.001)
        #expect(abs(payload.grabUnit.y - (94.25166 - 63.44) / 79.12) < 0.001)
    }

    @Test func rel040SansRotationLeClicParallaxResteSurLesRectanglesBruts() {
        let card = Self.card(mode: .parallax, rotation: 0)
        #expect(card.windowID(at: CGPoint(x: 35, y: 90)) == WindowID(rawValue: 1))
    }

    @Test func rel040LeModeStackedGardeLesRectanglesBruts() {
        let card = Self.card(mode: .stacked)
        // Sans transformée, l'aperçu 0 (au-dessus) gagne sur toute sa surface brute.
        #expect(card.windowID(at: CGPoint(x: 35, y: 90)) == WindowID(rawValue: 1))
    }
}
