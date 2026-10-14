import AppKit
import Foundation
import RoadieAX
import RoadieCore
import Testing
@testable import RoadieDaemon

@MainActor
struct RailTypographyTests {
    @Test func atomicSettingsWritesRefreshIndependentRailFonts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rail-fonts-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("roadies.toml").path
        try "".write(toFile: path, atomically: false, encoding: .utf8)
        let service = SettingsService(configPath: path, afterWrite: {})
        var observed = RailSettings.load(path: path)
        let watcher = RailFileWatcher(path: { path }, onChange: { observed = RailSettings.load(path: path) })
        watcher.start()
        defer { watcher.stop() }

        let changes: [(String, Double)] = [
            ("rail.header.display.font_size", 20),
            ("rail.header.desktop.font_size", 24),
            ("rail.stage_labels.font_size", 28),
            ("rail.stage_labels.font_size", 18), // Même taille de fichier : le cache doit aussi changer.
        ]
        for (key, value) in changes {
            guard case .applied = service.set(key, to: String(value)) else {
                Issue.record("écriture refusée : \(key)")
                return
            }
            let expected = RailSettings.load(path: path)
            for _ in 0..<100 where observed != expected {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(observed == expected, "le remplacement atomique doit réarmer le watcher")
        }
        #expect(observed.displayLabel.fontSize == 20)
        #expect(observed.desktopLabel.fontSize == 24)
        #expect(observed.stageLabel.fontSize == 18)
    }

    @Test func largeFontsGrowHeaderCardsAndRecordingIndicator() {
        let small = RailVisualConfig.load(settings: RailSettings.load(raw: ""))
        let large = RailVisualConfig.load(settings: RailSettings.load(raw: """
        [fx.rail.header.display]
        font_size = 40
        [fx.rail.header.desktop]
        font_size = 32
        [fx.rail.stage_labels]
        font_size = 28
        """))
        #expect(large.headerHeight >= large.displayLabel.lineHeight + large.desktopLabel.lineHeight + 2)
        #expect(large.headerHeight > small.headerHeight)
        #expect(StageCardView.height(for: large) > StageCardView.height(for: small))
        #expect(large.stageLabel.lineHeight >= large.stageLabel.font.ascender - large.stageLabel.font.descender)
        let status = TargetRecordingStatus(name: "demo", startedAt: .now, pid: 1, outputPath: "/tmp/demo.mov")
        let smallIndicator = RecordingIndicatorView(status: status, textConfig: small.stageLabel)
        let largeIndicator = RecordingIndicatorView(status: status, textConfig: large.stageLabel)
        #expect(largeIndicator.intrinsicContentSize.height > smallIndicator.intrinsicContentSize.height)
        #expect(largeIndicator.intrinsicContentSize.height - 12 >= large.stageLabel.lineHeight)
        let labelWidth = ("record" as NSString).size(withAttributes: [.font: large.stageLabel.font]).width
        #expect(largeIndicator.intrinsicContentSize.width - 32 >= labelWidth)
    }

    @Test(arguments: [90.0, 150.0, 320.0])
    func largeIconFontsKeepAllSixClickTargetsWithinCard(railWidth: Double) {
        var config = RailVisualConfig.load(settings: RailSettings.load(raw: """
        [fx.rail.stage_labels]
        font_size = 28
        """))
        config.mode = .icons
        config.railWidth = CGFloat(railWidth)
        for count in [6, 8] {
            let members = (1...count).map { index in
                PersistentStageMember(windowID: WindowID(rawValue: UInt32(index)), bundleID: "com.example.app", title: "w", frame: Rect(x: 0, y: 0, width: 100, height: 100))
            }
            let card = StageCardView(stage: PersistentStage(id: StageID(rawValue: "1"), members: members), displayLabel: "Stage", isActive: false, accent: .systemGreen, config: config, presentationStates: [:], thumbnails: [:])
            #expect(card.bounds.width == CGFloat(railWidth) - 12)
            #expect(card.bounds.height == StageCardView.height(for: config, memberCount: count))
            let frames = card.iconDisplayFrames()
            #expect(frames.count == (count > 6 ? 7 : 6))
            for frame in frames {
                #expect(card.bounds.contains(frame), "icône ou compteur hors de la carte : \(frame)")
            }
            var found: Set<WindowID> = []
            // Balayage des zones de clic, sans capture ni écran réel.
            for y in stride(from: 0, through: Int(card.bounds.height), by: 2) {
                for x in stride(from: 0, through: Int(card.bounds.width), by: 2) {
                    if let id = card.windowID(at: CGPoint(x: x, y: y)) { found.insert(id) }
                }
            }
            #expect(found == Set(members.prefix(6).map(\.windowID)))
            if count > 6, let counter = frames.last {
                #expect(card.windowID(at: CGPoint(x: counter.midX, y: counter.midY)) == nil)
            }
        }
    }
}
