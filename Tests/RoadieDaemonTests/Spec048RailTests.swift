import AppKit
import Foundation
import RoadieAX
import RoadieCore
import Testing
@testable import RoadieDaemon

/// SPEC-048 C-01 et C-03 : énumération ScreenCaptureKit évitée, vignettes mises à jour en place.
@Suite @MainActor
struct Spec048RailTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    @Test func cachedWindowsNeedNoEnumeration() {
        let ids = [WindowID(rawValue: 1), WindowID(rawValue: 2)]
        #expect(!RailThumbnailStore.needsEnumeration(requested: ids, cached: Set(ids), absentUntil: [:], now: now))
        #expect(RailThumbnailStore.needsEnumeration(requested: ids, cached: [ids[0]], absentUntil: [:], now: now))
    }

    @Test func absentWindowWaitsBeforeAnotherEnumeration() {
        let id = WindowID(rawValue: 3)
        let absent = [id: now.addingTimeInterval(5)]
        #expect(!RailThumbnailStore.needsEnumeration(requested: [id], cached: [], absentUntil: absent, now: now))
        #expect(RailThumbnailStore.needsEnumeration(requested: [id], cached: [],
                                                    absentUntil: absent, now: now.addingTimeInterval(5)))
    }

    private func member(_ id: UInt32) -> PersistentStageMember {
        PersistentStageMember(windowID: WindowID(rawValue: id), bundleID: "com.example.rail048", title: "Test",
                              frame: Rect(x: 0, y: 0, width: 100, height: 100))
    }

    @Test func thumbnailRefreshKeepsTheExistingCards() throws {
        let screen = try #require(NSScreen.screens.first)
        let config = RailVisualConfig.load(settings: RailSettings.load(raw: ""))
        let stages = ["a", "b"].enumerated().map { index, id in
            PersistentStage(id: StageID(rawValue: id), name: id, members: [member(UInt32(index + 1))])
        }
        let scope = PersistentStageScope(displayID: DisplayID(rawValue: "test048"), stages: stages)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rail048-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let panel = RailPanel()
        panel.position(on: screen, displayID: scope.displayID, config: config,
                       runtimeStore: RailRuntimeStateStore(path: directory.appendingPathComponent("runtime.json").path))
        let store = RailThumbnailStore()
        panel.render(content: RailDisplayContent(scope: scope, presentationStates: [:],
                                                 liveWindowIDs: Set(stages.flatMap { $0.members.map(\.windowID) })),
                     displayName: "Test", config: config, thumbnails: store, recordingStatus: nil,
                     recordingIndicatorBottomOffset: 0)
        let stack = try #require(panel.contentView as? RailStackView)
        let before = stack.arrangedSubviews.compactMap { $0 as? StageCardView }
        #expect(before.count == 2)

        panel.refreshThumbnails(store)

        let after = stack.arrangedSubviews.compactMap { $0 as? StageCardView }
        #expect(after.count == before.count)
        #expect(zip(before, after).allSatisfy { $0 === $1 })
    }

    /// SPEC-051 C-06 : un rail replié ne capture pas ; son dépliage relance le rafraîchissement.
    @Test func collapsedRailReportsItsRevealOnce() throws {
        let screen = try #require(NSScreen.screens.first)
        var config = RailVisualConfig.load(settings: RailSettings.load(raw: ""))
        config.autoHide = true
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rail051-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let panel = RailPanel()
        var reveals: [DisplayID] = []
        panel.onRevealed = { reveals.append($0) }
        panel.position(on: screen, displayID: DisplayID(rawValue: "test051"), config: config,
                       runtimeStore: RailRuntimeStateStore(path: directory.appendingPathComponent("runtime.json").path))
        #expect(panel.isRailCollapsed)

        #expect(panel.revealIfCollapsed())

        #expect(!panel.isRailCollapsed)
        #expect(reveals == [DisplayID(rawValue: "test051")])
        #expect(!panel.revealIfCollapsed())
        #expect(reveals.count == 1)
    }

    @Test func cardRedrawsOnlyWhenAnImageChanges() {
        let config = RailVisualConfig.load(settings: RailSettings.load(raw: ""))
        let stage = PersistentStage(id: StageID(rawValue: "a"), name: "a", members: [member(1)])
        let image = NSImage(size: NSSize(width: 4, height: 4))
        let card = StageCardView(stage: stage, displayLabel: "a", isActive: false, accent: .systemBlue, config: config,
                                 presentationStates: [:], thumbnails: [WindowID(rawValue: 1): image])
        #expect(!card.updateThumbnails([WindowID(rawValue: 1): image]))
        #expect(card.updateThumbnails([WindowID(rawValue: 1): NSImage(size: NSSize(width: 4, height: 4))]))
        #expect(card.members.map(\.windowID) == [WindowID(rawValue: 1)])
    }
}

/// SPEC-048 C-02 : le statut d'enregistrement n'est relu qu'après un signal ou la fin du processus.
@Suite
struct Spec048RecordingStatusTests {
    private let status = TargetRecordingStatus(name: "macro", startedAt: Date(timeIntervalSince1970: 1), pid: 42,
                                               outputPath: "/tmp/macro.json")

    @Test func cachedStatusIsKeptWithoutReading() {
        var loads = 0
        let result = RailController.recordingStatus(cached: status, dirty: false, isAlive: { _ in true },
                                                    load: { loads += 1; return nil })
        #expect(result == status)
        #expect(loads == 0)
    }

    @Test func signalOrEndedRecorderReadsAgain() {
        var loads = 0
        _ = RailController.recordingStatus(cached: status, dirty: true, isAlive: { _ in true },
                                           load: { loads += 1; return nil })
        let ended = RailController.recordingStatus(cached: status, dirty: false, isAlive: { _ in false },
                                                   load: { loads += 1; return nil })
        #expect(ended == nil)
        #expect(loads == 2)
    }

    @Test func noRecordingStaysWithoutReading() {
        var loads = 0
        #expect(RailController.recordingStatus(cached: nil, dirty: false, isAlive: { _ in true },
                                               load: { loads += 1; return nil }) == nil)
        #expect(loads == 0)
    }
}
