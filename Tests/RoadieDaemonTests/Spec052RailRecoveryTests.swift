import AppKit
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages
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
        let viewport = panel.convertToScreen(panel.stageScrollView.frame)
        #expect(viewport.minY >= screen.visibleFrame.minY)
        #expect(viewport.maxY <= screen.visibleFrame.maxY)
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
    func occupiedAndEmptyStagesCanEachBeReorderedDespiteInterleavedPersistentRanks() throws {
        let screen = try #require(NSScreen.screens.first)
        var config = RailVisualConfig.load(settings: RailSettings.load(raw: ""))
        config.headerPosition = .hidden
        config.stagesPosition = .top
        let emptyA = PersistentStage(id: StageID(rawValue: "emptyA"), name: "Reserve A")
        let emptyB = PersistentStage(id: StageID(rawValue: "emptyB"), name: "Reserve B")
        let fullA = PersistentStage(id: StageID(rawValue: "fullA"), name: "Work A", members: [member(1)])
        let fullB = PersistentStage(id: StageID(rawValue: "fullB"), name: "Work B", members: [member(2)])
        let scope = PersistentStageScope(displayID: DisplayID(rawValue: "fixture"),
                                        stages: [emptyA, fullA, emptyB, fullB])
        let live: Set<WindowID> = [WindowID(rawValue: 1), WindowID(rawValue: 2)]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("reorder052-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let panel = RailPanel()
        panel.position(on: screen, displayID: scope.displayID, config: config,
                       runtimeStore: RailRuntimeStateStore(path: directory.appendingPathComponent("runtime.json").path))
        for (sourceID, targetID, expected) in [
            (fullA.id, fullB.id, [fullB.id, fullA.id, emptyA.id, emptyB.id]),
            (emptyA.id, emptyB.id, [fullA.id, fullB.id, emptyB.id, emptyA.id])
        ] {
            panel.render(content: RailDisplayContent(scope: scope, presentationStates: [:], liveWindowIDs: live),
                         displayName: "Test", config: config, thumbnails: RailThumbnailStore(),
                         recordingStatus: nil, recordingIndicatorBottomOffset: 0)
            let target = try #require(panel.stack.arrangedSubviews.compactMap { $0 as? StageCardView }
                .first { $0.stageID == targetID })
            let targetFrame = panel.stack.convert(target.previewDisplayFrames().first ?? target.bounds, from: target)
            let point = panel.convertPoint(toScreen: panel.stack.convert(
                CGPoint(x: 50, y: targetFrame.midY - 10), to: nil))
            let position = try #require(panel.stageReorderPosition(at: point, sourceStageID: sourceID))
            panel.showStageReorderPreview(at: point, sourceStageID: sourceID)
            let overlay = try #require(panel.stack.subviews.compactMap { $0 as? RailStageReorderPreviewView }.first)
            #expect(overlay.subviews.compactMap { $0 as? StageCardView }.map(\.stageID) == expected)
            var committed = scope
            let reordered = committed.reorderStage(sourceID, to: position)
            #expect(reordered)
            #expect(StagePresentationOrder(scope: committed, liveWindowIDs: live).visibleStageIDs == expected)
            panel.hideStageReorderPreview()
        }
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
    func draggingWithoutManagedTargetNeverAcquires() {
        let input = UserInputActivity()
        var acquisitions = 0
        input.observeGestures(target: { _ in nil }, onDragStart: { _ in acquisitions += 1 }, onRelease: { _ in })
        input.mouseDown(at: .zero)
        for _ in 0..<20 { input.mouseDragged() }
        input.mouseUp(leftButton: true)
        #expect(acquisitions == 0)
        #expect(input.takeGesture() == nil)
    }

    @Test(arguments: [false, true])
    func gestureAnchorIsDiscardedWhenGeometryIsInvalidated(destroyed: Bool) {
        let state = SnapshotProcessState()
        let snapshot = DaemonSnapshot(permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [], windows: [], state: RoadieState())
        state.publish(snapshot, followFocus: true, maxAge: 0.15, at: Date(), stateStamp: [],
                      config: RoadieConfig(), observationGeneration: 0)
        #expect(state.latestPublishedSnapshot() != nil)
        if destroyed { state.noteDestroyed(WindowID(rawValue: 1), at: Date()) }
        else { state.invalidatePublished() }
        #expect(state.latestPublishedSnapshot() == nil)
    }

    @Test
    func focusOnlyInvalidationPreservesTheGestureAnchorAndWrittenFrames() throws {
        let state = SnapshotProcessState()
        let window = powerWindow(1, x: 0)
        let snapshot = DaemonSnapshot(permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [], windows: [ScopedWindowSnapshot(window: window, scope: nil)], state: RoadieState())
        state.publish(snapshot, followFocus: true, maxAge: 0.15, at: Date(), stateStamp: [],
                      config: RoadieConfig(), observationGeneration: 0)
        let frame = Rect(x: 20, y: 30, width: 400, height: 300)
        state.republish(frames: [window.id: frame])
        state.invalidatePublished(preservingGesture: true)
        let anchor = try #require(state.latestPublishedSnapshot())
        #expect(anchor.windows.first?.window.frame == frame)
    }

    @Test
    func parkingDoesNotReplaceTheActiveEmptyStage() throws {
        let host = powerDisplay("host")
        let external = powerDisplay("external", index: 2, x: 1000)
        let empty = PersistentStage(id: StageID(rawValue: "reserved"), name: "Work")
        let full = PersistentStage(id: StageID(rawValue: "work"), name: "Work", members: [member(1)])
        var state = PersistentStageState(scopes: [
            PersistentStageScope(displayID: host.id, activeStageID: empty.id, stages: [empty]),
            PersistentStageScope(displayID: external.id, activeStageID: full.id, stages: [full])
        ], activeDisplayID: host.id)
        let date = Date(timeIntervalSince1970: 1000)
        _ = DisplayParkingService().transition(state: &state, liveDisplays: [host], windows: [], now: date)
        _ = DisplayParkingService().transition(state: &state, liveDisplays: [host], windows: [], now: date.addingTimeInterval(61))
        let scope = try #require(state.scopes.first { $0.displayID == host.id })
        #expect(scope.activeStageID == empty.id)
        #expect(scope.stages.first { $0.id == empty.id }?.members.isEmpty == true)
        #expect(scope.stages.filter { !$0.members.isEmpty }.flatMap(\.members).map(\.windowID) == [WindowID(rawValue: 1)])
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
            PersistentStageScope(displayID: host.id, activeStageID: StageID(rawValue: "home"), stages: [
                PersistentStage(id: StageID(rawValue: "home"), name: "Home", members: [member(2)]),
                PersistentStage(id: StageID(rawValue: "reserved"), name: "Work")
            ]),
            PersistentStageScope(displayID: external.id, activeStageID: full.id, stages: [full])
        ], activeDisplayID: host.id)
        for cycle in 0..<4 {
            let date = Date(timeIntervalSince1970: Double(1000 + cycle * 1000))
            _ = service.transition(state: &state, liveDisplays: [host], windows: [], now: date)
            _ = service.transition(state: &state, liveDisplays: [host], windows: [], now: date.addingTimeInterval(61))
            let parked = try #require(state.scopes.first { $0.displayID == host.id })
            #expect(parked.stages.count == 2)
            #expect(parked.stages.first { $0.name == "Work" }?.members.map(\.windowID) == [WindowID(rawValue: 1)])
            _ = service.transition(state: &state, liveDisplays: [host, external], windows: [], now: date.addingTimeInterval(100))
            let restored = try #require(state.scopes.first { $0.displayID == external.id })
            #expect(restored.stages.count == 1)
            #expect(restored.stages[0].id == full.id)
            #expect(restored.stages[0].members.map(\.windowID) == [WindowID(rawValue: 1)])
        }
    }
}
