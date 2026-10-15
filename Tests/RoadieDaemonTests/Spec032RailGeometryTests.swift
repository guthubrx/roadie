import AppKit
import Foundation
import RoadieAX
import RoadieCore
import Testing
@testable import RoadieDaemon

@Suite @MainActor
struct Spec032RailGeometryTests {
    private func member(_ id: UInt32) -> PersistentStageMember {
        PersistentStageMember(windowID: WindowID(rawValue: id), bundleID: "com.example.geometry", title: "Test",
                              frame: Rect(x: 0, y: 0, width: 100, height: 100))
    }

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
        scale_per_layer = 0.08
        leading_padding = 0
        trailing_padding = 8
        vertical_padding = 12
        [fx.rail.stages]
        slot_height = 120
        gap = 13
        [fx.rail.stage_labels]
        font_size = 28
        """))
    }

    private func card(count: Int, config: RailVisualConfig) -> StageCardView {
        let stage = PersistentStage(id: StageID(rawValue: "1"), name: "Work", members: (0..<count).map { member(UInt32($0 + 1)) })
        return StageCardView(stage: stage, displayLabel: "Work", isActive: false, accent: .systemGreen,
                             config: config, presentationStates: [:], thumbnails: [:])
    }

    @Test func slotHeightIsWritableAndPartOfRefreshSignature() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rail032-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("roadies.toml").path
        try "".write(toFile: path, atomically: false, encoding: .utf8)
        let before = RailSettings.load(path: path)
        let service = SettingsService(configPath: path, afterWrite: {})
        guard case .applied = service.set("rail.stages.slot_height", to: "120") else {
            Issue.record("Réglage de hauteur absent du catalogue")
            return
        }
        let after = RailSettings.load(path: path)
        #expect(after.stages.slotHeight == 120)
        #expect(after != before)
        #expect(RailVisualConfig.load(settings: after).slotHeight == 120)
        #expect(RailSettings.load(raw: "[fx.rail.stages]\nslot_height = 999").stages.slotHeight == 320)
        #expect(RailSettings.load(raw: "[fx.rail.stages]\nslot_height = -10").stages.slotHeight == 0)
    }

    @Test func namedEmptyAndOccupiedSlotsKeepSameHeightWithoutChangingRanks() {
        let config = config()
        for count in 0...5 {
            #expect(card(count: count, config: config).bounds.height == 120)
        }
        var automatic = config
        automatic.slotHeight = 0
        #expect(card(count: 1, config: automatic).bounds.height == 184)
        var minimum = config
        minimum.slotHeight = 1
        #expect(card(count: 1, config: minimum).bounds.height == 80)
    }

    @Test(arguments: [90.0, 150.0, 320.0], [0.0, 35.0, 75.0])
    func foregroundStaysAlignedAndEveryWindowRemainsClickable(width: Double, rotation: Double) async throws {
        var config = config()
        config.railWidth = width
        config.parallaxRotation = rotation
        let reference = try #require(card(count: 1, config: config).previewDisplayFrames().first)
        for count in 1...5 {
            let view = card(count: count, config: config)
            let frames = view.previewDisplayFrames()
            let front = try #require(frames.first)
            #expect(abs(front.minX - reference.minX) < 0.001)
            #expect(abs(front.maxX - reference.maxX) < 0.001)
            for frame in frames {
                #expect(frame.minX >= 3.99)
                #expect(frame.maxX <= width - 16 + 0.01)
            }
            #expect(view.windowID(at: CGPoint(x: front.midX, y: front.midY)) == WindowID(rawValue: 1))
            guard count == 5 else { continue }
            var found: Set<WindowID> = []
            for y in stride(from: 0, through: Int(view.bounds.height), by: 2) {
                if y.isMultiple(of: 10) { await Task.yield() }
                for x in stride(from: 0, through: Int(width - 12), by: 2) {
                    if let id = view.windowID(at: CGPoint(x: x, y: y)) { found.insert(id) }
                }
            }
            #expect(found == Set((1...count).map { WindowID(rawValue: UInt32($0)) }))
        }
    }

    @Test func actualPanelSpacingAndDropIndicatorUseSameSlots() throws {
        let screen = try #require(NSScreen.screens.first)
        var config = config()
        config.headerPosition = .hidden
        config.stagesPosition = .top
        let stages = ["word", "firefox", "t3"].enumerated().map { index, id in
            PersistentStage(id: StageID(rawValue: id), name: id, members: [member(UInt32(index + 1))])
        }
        let scope = PersistentStageScope(displayID: DisplayID(rawValue: "test"), stages: stages)
        let panel = RailPanel()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rail032-panel-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        panel.position(on: screen, displayID: scope.displayID, config: config,
                       runtimeStore: RailRuntimeStateStore(path: directory.appendingPathComponent("runtime.json").path))
        panel.render(content: RailDisplayContent(scope: scope, presentationStates: [:], liveWindowIDs: Set(stages.flatMap { $0.members.map(\.windowID) })),
                     displayName: "Test", config: config, thumbnails: RailThumbnailStore(), recordingStatus: nil, recordingIndicatorBottomOffset: 0)
        let stack = try #require(panel.contentView as? RailStackView)
        stack.layoutSubtreeIfNeeded()
        let cards = stack.arrangedSubviews.compactMap { $0 as? StageCardView }
        #expect(cards.map(\.stageID) == stages.map(\.id))
        #expect(abs(cards[0].frame.midY - cards[1].frame.midY - 133) < 0.01)
        #expect(abs(cards[1].frame.midY - cards[2].frame.midY - 133) < 0.01)
        let source = stages[2].id
        // Déposer T3 juste au-dessus de Firefox doit donner le rang 2 et un trait entre Word et Firefox.
        let targetPreview = try #require(cards[1].previewDisplayFrames().first)
        let targetFrame = stack.convert(targetPreview, from: cards[1])
        let local = CGPoint(x: 50, y: targetFrame.midY + 10)
        let point = panel.convertPoint(toScreen: stack.convert(local, to: nil))
        #expect(panel.stageReorderPosition(at: point, sourceStageID: source) == 2)
        panel.showStageReorderPreview(at: point, sourceStageID: source)
        let line = try #require(stack.insertionY)
        #expect(line > cards[1].frame.maxY && line < cards[0].frame.minY)
        var changed = scope
        let reordered = changed.reorderStage(source, to: 2)
        #expect(reordered)
        #expect(changed.stages.map(\.id.rawValue) == ["word", "t3", "firefox"])
        panel.showStageReorderPreview(at: CGPoint(x: panel.frame.maxX + 30, y: point.y), sourceStageID: source)
        #expect(stack.insertionY == nil)
        panel.showStageReorderPreview(at: point, sourceStageID: source)
        panel.hideStageReorderPreview()
        #expect(stack.insertionY == nil)
    }
}
