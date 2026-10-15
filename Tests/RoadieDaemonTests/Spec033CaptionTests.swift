import AppKit
import Foundation
import RoadieCore
import Testing
@testable import RoadieDaemon

@Suite @MainActor
struct Spec033CaptionTests {
    private func config() -> RailVisualConfig {
        RailVisualConfig.load(settings: RailSettings.load(raw: """
        [fx.rail]
        renderer = "parallax-45"
        width = 150
        [fx.rail.parallax]
        width = 120
        height = 78
        offset_x = 15
        offset_y = 10
        leading_padding = 0
        trailing_padding = 8
        [fx.rail.stages]
        slot_height = 112
        [fx.rail.stage_labels]
        font_size = 28
        caption_font_size = 14
        gap = 4
        placement = "below"
        """))
    }

    private func card(_ count: Int, config: RailVisualConfig, label: String = "3 — Com") -> StageCardView {
        let stage = PersistentStage(id: StageID(rawValue: "8"), name: "Com", members: (0..<count).map {
            PersistentStageMember(windowID: WindowID(rawValue: UInt32($0 + 1)), bundleID: "com.example.caption", title: "Test",
                                  frame: Rect(x: 0, y: 0, width: 100, height: 100))
        })
        return StageCardView(stage: stage, displayLabel: label, isActive: false, accent: .systemGreen,
                             config: config, presentationStates: [:], thumbnails: [:])
    }

    @Test func captionSettingsAreWritableAndIndependentFromDetails() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("caption033-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("config.toml").path
        try "[fx.rail.stage_labels]\nfont_size = 28\n".write(toFile: path, atomically: true, encoding: .utf8)
        let service = SettingsService(configPath: path, afterWrite: {})
        for (key, value) in [("caption_font_size", "14"), ("gap", "4"), ("follows_perspective", "true")] {
            guard case .applied = service.set("rail.stage_labels." + key, to: value) else {
                Issue.record("Réglage refusé : \(key)"); return
            }
        }
        let settings = RailSettings.load(path: path)
        let visual = RailVisualConfig.load(settings: settings)
        #expect(visual.stageLabel.font.pointSize == 28)
        #expect(visual.stageLabel.captionFont.pointSize == 14)
        #expect(visual.stageLabel.gap == 4)
        #expect(visual.stageLabel.followsPerspective)
        #expect(settings.stageLabel.fontSize == 28)
    }

    @Test(arguments: [false, true], [0.0, 4.0, 12.0])
    func captionStaysBelowDrawingWithExactGapAndNoCollision(perspective: Bool, gap: Double) throws {
        var config = config()
        config.stageLabel.followsPerspective = perspective
        config.stageLabel.gap = gap
        var previous: CGRect?
        for count in 0...5 {
            let view = card(count, config: config)
            let layout = view.stageLabelLayout()
            let frame = layout.rect.applying(layout.transform)
            #expect(frame.minY >= -0.001 && frame.maxY <= view.bounds.height + 0.001)
            #expect(frame.minX >= 0 && frame.maxX <= config.railWidth - 12)
            #expect(layout.transform.isIdentity == !perspective)
            #expect(view.bounds.height == 112)
            if count > 0 {
                let previews = view.previewDisplayFrames()
                let front = try #require(previews.first)
                #expect(abs(front.minY - frame.maxY - gap) < 0.001)
                #expect(abs(front.midX - frame.midX) < 0.001)
                for preview in previews {
                    #expect(preview.maxY <= view.bounds.height + 0.001)
                    #expect(preview.minY >= frame.maxY + gap - 0.001)
                }
                if let previous { #expect(previous == frame) }
                previous = frame
            }
        }
    }

    @Test(arguments: [false, true])
    func captionRemainsTemporaryWithoutChangingSlotOrPreview(perspective: Bool) throws {
        var config = config()
        config.stageLabel.followsPerspective = perspective
        config.stageLabel.visibilitySeconds = 5
        func pixels(_ view: StageCardView) throws -> Data { try #require(view.snapshotImage()?.tiffRepresentation) }
        let hidden = card(1, config: config)
        #expect(try pixels(hidden) == pixels(card(1, config: config, label: "")))
        config.stageLabel.visibleUntil = Date().addingTimeInterval(5).timeIntervalSince1970
        let shown = card(1, config: config)
        #expect(try pixels(shown) != pixels(card(1, config: config, label: "")))
        #expect(shown.bounds == hidden.bounds)
        #expect(shown.previewDisplayFrames() == hidden.previewDisplayFrames())
        config.stageLabel.visibleUntil = Date().addingTimeInterval(-10).timeIntervalSince1970
        #expect(try pixels(card(1, config: config)) == pixels(card(1, config: config, label: "")))
    }
}
