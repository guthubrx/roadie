import AppKit
import Foundation
import RoadieAX
import RoadieCore
import Testing
@testable import RoadieDaemon

@Suite @MainActor
struct Spec052RailRecoveryTests {
    private func member(_ id: UInt32) -> PersistentStageMember {
        PersistentStageMember(windowID: WindowID(rawValue: id), bundleID: "fixture", title: "Test",
                              frame: Rect(x: 0, y: 0, width: 200, height: 200))
    }

    @Test
    func occupiedStagesComeFirstWithTheSameRanksInDestinations() {
        let empty = PersistentStage(id: StageID(rawValue: "empty"), name: "Reserved")
        let full = PersistentStage(id: StageID(rawValue: "full"), name: "Work", members: [member(1)])
        let scope = PersistentStageScope(displayID: DisplayID(rawValue: "fixture"), stages: [empty, full])
        let order = StagePresentationOrder(scope: scope, liveWindowIDs: [WindowID(rawValue: 1)])
        #expect(order.visibleStageIDs == [full.id, empty.id])
        #expect(order.stageID(at: 1) == full.id)
        #expect(scope.stages.map(\.id) == [empty.id, full.id])
    }

    @Test
    func overflowingRailKeepsScreenHeightAndLastCardCanBeScrolledIntoView() throws {
        let screen = try #require(NSScreen.screens.first)
        var config = RailVisualConfig.load(settings: RailSettings.load(raw: ""))
        config.headerPosition = .hidden
        config.slotHeight = 120
        config.stagesPosition = .top
        let stages = (1...30).map { PersistentStage(id: StageID(rawValue: "\($0)"), name: "Work \($0)", members: [member(UInt32($0))]) }
        let scope = PersistentStageScope(displayID: DisplayID(rawValue: "fixture"), stages: stages)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rail052-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let panel = RailPanel()
        panel.position(on: screen, displayID: scope.displayID, config: config,
                       runtimeStore: RailRuntimeStateStore(path: dir.appendingPathComponent("runtime.json").path))
        panel.render(content: RailDisplayContent(scope: scope, presentationStates: [:],
            liveWindowIDs: Set(stages.flatMap { $0.members.map(\.windowID) })), displayName: "Test",
            config: config, thumbnails: RailThumbnailStore(), recordingStatus: nil, recordingIndicatorBottomOffset: 0)
        #expect(panel.frame.height == screen.frame.height)
        #expect(panel.stack.frame.height > panel.stageScrollView.contentView.bounds.height)
        let last = try #require(panel.stack.arrangedSubviews.compactMap { $0 as? StageCardView }.last)
        panel.stack.scrollToVisible(last.frame)
        let clip = panel.stageScrollView.contentView
        #expect(clip.bounds.intersects(last.frame))
        let local = last.previewDisplayFrames().first.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: 50, y: last.bounds.midY)
        let point = panel.convertPoint(toScreen: last.convert(local, to: nil))
        #expect(panel.stageID(at: point) == last.stageID)
    }

    @Test
    func simpleClicksNeverAcquireAndOnlyFirstDragRefreshes() {
        let input = UserInputActivity()
        var acquisitions = 0
        let frame = CGRect(x: 10, y: 20, width: 500, height: 400)
        input.observeGestures(target: { _ in (1, frame) }, onDragStart: { gesture in
            acquisitions += 1
            #expect(gesture.startFrame == frame)
        }, onRelease: { _ in })
        for _ in 0..<10 { input.mouseDown(at: .zero); input.mouseUp(leftButton: true); _ = input.takeGesture() }
        #expect(acquisitions == 0)
        input.mouseDown(at: .zero)
        for _ in 0..<20 { input.mouseDragged() }
        #expect(acquisitions == 1)
        input.mouseUp(leftButton: true)
        #expect(input.takeGesture()?.didDrag == true)
        input.mouseDown(at: .zero)
        input.claimExplicitResize()
        input.mouseDragged()
        #expect(acquisitions == 1)
    }

    @Test
    func ambiguousEmptyNamesAndOccupiedStagesAreNotMerged() {
        let service = DisplayParkingService()
        let host = powerDisplay("host")
        let external = powerDisplay("external", index: 2, x: 1000)
        let full = PersistentStage(id: StageID(rawValue: "work"), name: "Work", members: [member(1)])
        var state = PersistentStageState(scopes: [
            PersistentStageScope(displayID: host.id, stages: [
                PersistentStage(id: StageID(rawValue: "a"), name: "Work"),
                PersistentStage(id: StageID(rawValue: "b"), name: "Work"),
                PersistentStage(id: StageID(rawValue: "c"), name: "Work", members: [member(2)])
            ]),
            PersistentStageScope(displayID: external.id, activeStageID: full.id, stages: [full])
        ], activeDisplayID: host.id)
        _ = service.transition(state: &state, liveDisplays: [host], windows: [], now: Date())
        let scope = state.scopes.first { $0.displayID == host.id }
        #expect(scope?.stages.count == 4)
        #expect(scope?.stages.first { $0.id.rawValue == "c" }?.members.map(\.windowID) == [WindowID(rawValue: 2)])
    }

    @Test
    func repeatedLongDisconnectsReuseCompatibleSlotsAndPreserveMembers() throws {
        let service = DisplayParkingService()
        let host = powerDisplay("host")
        let external = powerDisplay("external", index: 2, x: 1000)
        let full = PersistentStage(id: StageID(rawValue: "work"), name: "Work", members: [member(1)])
        var state = PersistentStageState(scopes: [
            PersistentStageScope(displayID: host.id, stages: [PersistentStage(id: StageID(rawValue: "reserved"), name: "Work")]),
            PersistentStageScope(displayID: external.id, activeStageID: full.id, stages: [full])
        ], activeDisplayID: host.id)
        for cycle in 0..<4 {
            let date = Date(timeIntervalSince1970: Double(1000 + cycle * 1000))
            _ = service.transition(state: &state, liveDisplays: [host], windows: [], now: date)
            _ = service.transition(state: &state, liveDisplays: [host], windows: [], now: date.addingTimeInterval(61))
            let parked = try #require(state.scopes.first { $0.displayID == host.id })
            #expect(parked.stages.count == 1)
            #expect(parked.stages[0].members.map(\.windowID) == [WindowID(rawValue: 1)])
            _ = service.transition(state: &state, liveDisplays: [host, external], windows: [], now: date.addingTimeInterval(100))
            let restored = try #require(state.scopes.first { $0.displayID == external.id })
            #expect(restored.stages.count == 1)
            #expect(restored.stages[0].id == full.id)
            #expect(restored.stages[0].members.map(\.windowID) == [WindowID(rawValue: 1)])
        }
    }
}
