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

    private func hasVisiblePixels(_ card: StageCardView) throws -> Bool {
        let bitmap = try #require(NSBitmapImageRep(data: image(card)))
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 {
                return true
            }
        }
        return false
    }

    @Test(arguments: [RailRenderMode.stacked, .mosaic, .parallax, .icons])
    func emptyStageRemainsVisibleWhenLabelsExpireOrAreDisabled(mode: RailRenderMode) throws {
        var config = RailVisualConfig()
        config.mode = mode
        config.stageLabel.visibilitySeconds = 5
        func card(name: String = "Work") -> StageCardView {
            let stage = PersistentStage(id: StageID(rawValue: "1"), name: name)
            return StageCardView(stage: stage, displayLabel: "", isActive: false, accent: .systemBlue,
                          config: config, presentationStates: [:], thumbnails: [:])
        }
        #expect(try hasVisiblePixels(card()))
        config.stageLabel.visibleUntil = Date().addingTimeInterval(5).timeIntervalSince1970
        #expect(try hasVisiblePixels(card()))
        config.stageLabel.visibleUntil = Date().addingTimeInterval(-10).timeIntervalSince1970
        #expect(try hasVisiblePixels(card()))
        config.stageLabel.enabled = false
        config.stageLabel.visibleUntil = Date().addingTimeInterval(5).timeIntervalSince1970
        #expect(try hasVisiblePixels(card()))
        #expect(try image(card()) != image(card(name: "Perso")))
    }

    @Test(arguments: [RailRenderMode.stacked, .mosaic, .parallax, .icons])
    func occupiedStagePositionAndNameAppearAndDisappearTogether(mode: RailRenderMode) throws {
        var config = RailVisualConfig()
        config.mode = mode
        config.stageLabel.visibilitySeconds = 5
        config.stageLabel.fontSize = 20
        config.stageLabel.opacity = 1
        config.stageLabel.zOrder = .above
        let stage = PersistentStage(id: StageID(rawValue: "parked-old-9"), name: "Perso", members: [
            PersistentStageMember(windowID: WindowID(rawValue: 1), bundleID: "fixture", title: "Test",
                                  frame: Rect(x: 0, y: 0, width: 100, height: 100)),
        ])
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
