import AppKit
import RoadieCore
import Testing
@testable import RoadieDaemon

@Suite
@MainActor
struct Spec031StageLabelsTests {
    private func image(_ card: StageCardView) throws -> Data {
        let image = try #require(card.snapshotImage())
        return try #require(image.tiffRepresentation)
    }

    @Test(arguments: [RailRenderMode.stacked, .mosaic, .parallax, .icons])
    func positionAndNameAppearAndDisappearTogether(mode: RailRenderMode) throws {
        var config = RailVisualConfig()
        config.mode = mode
        config.stageLabel.visibilitySeconds = 5
        config.stageLabel.fontSize = 20
        config.stageLabel.opacity = 1
        config.stageLabel.zOrder = .above
        let stage = PersistentStage(id: StageID(rawValue: "parked-old-9"), name: "Perso")
        func card(_ label: String, position: Int? = nil) -> StageCardView {
            StageCardView(stage: stage, displayLabel: label, isActive: false, accent: .systemBlue,
                          config: config, presentationStates: [:], thumbnails: [:], position: position)
        }

        let hidden = card("Perso", position: 12)
        #expect(try image(hidden) == image(card("")))
        #expect(hidden.bounds == card("Perso").bounds)

        config.stageLabel.visibleUntil = Date().addingTimeInterval(5).timeIntervalSince1970
        let visible = card("Perso", position: 12)
        #expect(try image(visible) == image(card("12 — Perso")))
        #expect(try image(visible) != image(card("Perso")))
        #expect(visible.bounds == hidden.bounds)

        config.stageLabel.visibleUntil = Date().addingTimeInterval(-10).timeIntervalSince1970
        #expect(try image(card("Perso", position: 12)) == image(card("")))
        config.stageLabel.enabled = false
        config.stageLabel.visibleUntil = Date().addingTimeInterval(5).timeIntervalSince1970
        #expect(try image(card("Perso", position: 12)) == image(card("")))
        #expect(stage.name == "Perso")
        #expect(stage.id.rawValue == "parked-old-9")
    }
}
