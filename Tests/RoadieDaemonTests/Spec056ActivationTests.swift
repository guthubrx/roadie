import Foundation
import CoreGraphics
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

@Suite
struct Spec056ActivationTests {
    @Test
    func activationJoinsOwnerDisplayAndStageWithoutChangingOwnership() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let second = powerDisplay("display-2", index: 2, x: 1000)
        let other = spec056Window(1, x: 100)
        let target = spec056Window(2, x: 1100)
        let provider = PowerUserProvider(displays: [main, second], windows: [other, target])
        provider.focusedID = other.id
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("spec056-activation"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: main.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: other.id, members: [spec056Member(other)]),
            ]),
            PersistentStageScope(displayID: second.id, activeStageID: StageID(rawValue: "2"), stages: [
                PersistentStage(id: StageID(rawValue: "2"), members: [spec056Member(target)]),
            ]),
        ]))
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store)
        let owner = store.state().stageScope(for: target.id)
        let entry = WindowSwitcherEntry(window: target, scope: owner)

        let result = WindowSwitcherService(service: service).activate(entry)

        #expect(result.changed)
        #expect(writer.focused.last == target.id)
        #expect(store.state().stageScope(for: target.id) == owner)
        #expect(owner?.displayID == second.id)
        #expect(owner?.stageID == StageID(rawValue: "2"))
    }

    @Test func activationChangesDesktopAndStageWithoutMovingMembers() throws {
        let current = spec056Window(1, x: 100)
        let target = spec056Window(2, x: 999)
        let provider = PowerUserProvider(windows: [current, target])
        provider.focusedID = current.id
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("spec056-desktops"))
        let display = DisplayID(rawValue: "display-main")
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, desktopID: DesktopID(rawValue: 1), activeStageID: StageID(rawValue: "source"), stages: [
                PersistentStage(id: StageID(rawValue: "source"), members: [spec056Member(current)])]),
            PersistentStageScope(displayID: display, desktopID: DesktopID(rawValue: 2), activeStageID: StageID(rawValue: "other"), stages: [
                PersistentStage(id: StageID(rawValue: "other")),
                PersistentStage(id: StageID(rawValue: "destination"), members: [spec056Member(target)])])
        ]))
        let owner = try #require(store.state().stageScope(for: target.id))
        let oldOwner = store.state().stageScope(for: current.id)
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store)
        let result = WindowSwitcherService(service: service).activate(WindowSwitcherEntry(window: target, scope: owner))
        #expect(result.changed)
        #expect(store.state().currentDesktopID(for: display) == DesktopID(rawValue: 2))
        #expect(store.state().scopes.first { $0.displayID == display && $0.desktopID == DesktopID(rawValue: 2) }?.activeStageID == owner.stageID)
        #expect(store.state().stageScope(for: target.id) == owner)
        #expect(store.state().stageScope(for: current.id) == oldOwner)
        #expect(writer.focused.last == target.id)
    }

    @Test func staleOwnershipIsRejectedInsideTheTransaction() throws {
        let target = spec056Window(2, x: 100)
        let provider = PowerUserProvider(windows: [target])
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("spec056-stale-owner"))
        store.save(PersistentStageState(scopes: [PersistentStageScope(displayID: DisplayID(rawValue: "display-main"),
            stages: [PersistentStage(id: StageID(rawValue: "new"), members: [spec056Member(target)])])]))
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store,
                                      persistStateChanges: false)
        let snapshot = service.snapshot(followFocus: false)
        let before = store.state()
        let stale = StageScope(displayID: DisplayID(rawValue: "display-main"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "old"))
        let result = WindowBookmarkCommandService(service: service, store: store).focusWindow(target, in: stale,
            snapshot: snapshot, generation: PlacementGeneration.shared.next(), label: "switcher", cause: "switcher.activate",
            eventPrefix: "window.switcher", requireOwnership: true, details: [:])
        #expect(!result.changed)
        #expect(writer.focused.isEmpty)
        #expect(store.state() == before)
    }

    @Test(arguments: [false, true])
    func minimizedMemberRestoresBeforeLayoutWithoutWritingStaleObservation(becomesReadable: Bool) throws {
        let current = spec056Window(1, x: 100)
        let target = spec056Window(2, x: 500)
        let provider = PowerUserProvider(windows: [current])
        let writer = Spec056RestoringWriter(provider: provider, target: target, becomesReadable: becomesReadable)
        let store = StageStore(path: tempPath("spec056-minimized"))
        let display = DisplayID(rawValue: "display-main")
        store.save(PersistentStageState(scopes: [PersistentStageScope(displayID: display,
            activeStageID: StageID(rawValue: "source"), stages: [
                PersistentStage(id: StageID(rawValue: "source"), members: [spec056Member(current)]),
                PersistentStage(id: StageID(rawValue: "destination"), mode: .float, members: [spec056Member(target)])])]))
        let owner = try #require(store.state().stageScope(for: target.id))
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store,
                                      persistStateChanges: false)
        var stale = target
        stale.title = "Ancien titre de la carte"
        stale.frame = Rect(x: -2000, y: -2000, width: 100, height: 100)
        let result = WindowBookmarkCommandService(service: service, store: store).focusWindow(stale, in: owner,
            snapshot: service.snapshot(followFocus: false), generation: PlacementGeneration.shared.next(),
            label: "switcher", cause: "switcher.activate", eventPrefix: "window.switcher", requireOwnership: true, details: [:])
        #expect(result.changed)
        #expect(writer.calls.first == "focus")
        #expect(writer.restoredFrame == target.frame)
        #expect(store.state().stageScope(for: target.id) == owner)
        #expect(store.state().scopes.first?.stages.first(where: { $0.id == owner.stageID })?.members.first?.title == target.title)
    }

    @Test(arguments: [false, true])
    func failedRestoreRollsBackOnlyItsOwnState(concurrentChange: Bool) throws {
        let target = spec056Window(2, x: 500)
        let provider = PowerUserProvider(windows: [])
        let writer = Spec056RestoringWriter(provider: provider, target: target, becomesReadable: false)
        writer.focusSucceeds = false
        let store = StageStore(path: tempPath("spec056-restore-failed"))
        let display = DisplayID(rawValue: "display-main")
        store.save(PersistentStageState(scopes: [PersistentStageScope(displayID: display,
            activeStageID: StageID(rawValue: "source"), stages: [
                PersistentStage(id: StageID(rawValue: "source")),
                PersistentStage(id: StageID(rawValue: "destination"), members: [spec056Member(target)])])]))
        let owner = try #require(store.state().stageScope(for: target.id))
        let before = store.state()
        if concurrentChange { writer.onFocus = { store.mutate { $0.focusDisplay(DisplayID(rawValue: "concurrent")) } } }
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store,
                                      persistStateChanges: false)
        let result = WindowBookmarkCommandService(service: service, store: store).focusWindow(target, in: owner,
            snapshot: service.snapshot(followFocus: false), generation: PlacementGeneration.shared.next(),
            label: "switcher", cause: "switcher.activate", eventPrefix: "window.switcher", requireOwnership: true, details: [:])
        #expect(result.outcome == .failed)
        #expect(writer.restoredFrame == nil)
        if concurrentChange { #expect(store.state().activeDisplayID == DisplayID(rawValue: "concurrent")) }
        else { #expect(store.state() == before) }
    }

    /// Session 106 : depuis un plein écran natif, la fenêtre visée est sur un autre espace et AX ne la voit
    /// pas. Le repli ouvre l'application et change d'espace ; sans lui, l'activation échoue comme avant et revient en arrière.
    @Test(arguments: [false, true])
    func windowOnAnotherSpaceIsReachedByOpeningItsApplication(spaceSwitchWorks: Bool) throws {
        let target = spec056Window(2, x: 500)
        let provider = PowerUserProvider(windows: [])
        let writer = Spec056RestoringWriter(provider: provider, target: target, becomesReadable: true)
        writer.focusSucceeds = false
        writer.otherSpaceSucceeds = spaceSwitchWorks
        let store = StageStore(path: tempPath("spec106-other-space-\(spaceSwitchWorks)"))
        store.save(PersistentStageState(scopes: [PersistentStageScope(displayID: DisplayID(rawValue: "display-main"),
            activeStageID: StageID(rawValue: "source"), stages: [
                PersistentStage(id: StageID(rawValue: "source")),
                PersistentStage(id: StageID(rawValue: "destination"), members: [spec056Member(target)])])]))
        let owner = try #require(store.state().stageScope(for: target.id))
        let before = store.state()
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store,
                                      persistStateChanges: false)
        let result = WindowBookmarkCommandService(service: service, store: store).focusWindow(target, in: owner,
            snapshot: service.snapshot(followFocus: false), generation: PlacementGeneration.shared.next(),
            label: "switcher", cause: "switcher.activate", eventPrefix: "window.switcher", requireOwnership: true, details: [:])
        #expect(writer.calls.prefix(2) == ["focus", "space"])
        if spaceSwitchWorks {
            #expect(result.outcome != .failed)
            #expect(store.state().scopes.first?.activeStageID == owner.stageID)
        } else {
            #expect(result.outcome == .failed)
            #expect(store.state() == before)
        }
    }

    @Test func refusedFrameDoesNotClaimThatFocusFailed() throws {
        let target = spec056Window(2, x: 500)
        let provider = PowerUserProvider(windows: [])
        let writer = Spec056RestoringWriter(provider: provider, target: target, becomesReadable: false)
        writer.frameSucceeds = false
        let store = StageStore(path: tempPath("spec056-frame-failed"))
        store.save(PersistentStageState(scopes: [PersistentStageScope(displayID: DisplayID(rawValue: "display-main"),
            stages: [PersistentStage(id: StageID(rawValue: "destination"), members: [spec056Member(target)])])]))
        let owner = try #require(store.state().stageScope(for: target.id))
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store,
                                      persistStateChanges: false)
        let result = WindowBookmarkCommandService(service: service, store: store).focusWindow(target, in: owner,
            snapshot: service.snapshot(followFocus: false), generation: PlacementGeneration.shared.next(),
            label: "switcher", cause: "switcher.activate", eventPrefix: "window.switcher", requireOwnership: true, details: [:])
        #expect(result.changed)
        #expect(result.outcome == .failed)
        #expect(result.message.contains("placement incomplete"))
        #expect(writer.calls.last == "focus")
    }

    @Test
    func closedWindowIsRefusedWithoutAnyMutation() {
        let window = spec056Window(1, x: 100)
        let provider = PowerUserProvider(windows: [window])
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("spec056-closed"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: DisplayID(rawValue: "display-main"), activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [spec056Member(window)]),
            ]),
        ]))
        let before = store.state()
        let service = WindowSwitcherService(service: SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store))
        let closed = WindowSwitcherEntry(window: spec056Window(9, x: 100), scope: nil)

        let activated = service.activate(closed)
        let closedAction = service.perform(.close, on: closed)

        #expect(!activated.changed)
        #expect(!closedAction.changed)
        #expect(writer.focused.isEmpty)
        #expect(store.state() == before)
    }

    @Test
    func fullscreenTargetsTheSelectedWindowRatherThanTheCurrentFocus() throws {
        let current = spec056Window(1, x: 100)
        let target = spec056Window(2, x: 600)
        let provider = PowerUserProvider(windows: [current, target])
        provider.focusedID = current.id
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("spec056-fullscreen"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: DisplayID(rawValue: "display-main"), activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [spec056Member(current), spec056Member(target)])
            ])
        ]))
        let snapshotService = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store)
        let scope = try #require(store.state().stageScope(for: target.id))
        let result = WindowSwitcherService(service: snapshotService).perform(.fullscreen, on: WindowSwitcherEntry(window: target, scope: scope))
        #expect(result.changed)
        #expect(snapshotService.commandLayoutIntent(scope: scope)?.zoomedWindowID == target.id)
        #expect(snapshotService.commandLayoutIntent(scope: scope)?.zoomReservesRail == false)
        #expect(writer.nativeFullscreen.isEmpty)
    }

    @Test
    func persistenceFailureStopsTheFocusTransaction() throws {
        let window = spec056Window(1, x: 100)
        let provider = PowerUserProvider(windows: [window])
        let writer = PowerUserWriter(provider: provider)
        let good = StageStore(path: tempPath("spec056-good"))
        good.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: DisplayID(rawValue: "display-main"), activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [spec056Member(window)]),
            ]),
        ]))
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: good)
        let owner = try #require(good.state().stageScope(for: window.id))
        let corruptPath = tempPath("spec056-corrupt")
        try "{ json invalide".write(toFile: corruptPath, atomically: true, encoding: .utf8)

        let result = WindowBookmarkCommandService(service: service, store: StageStore(path: corruptPath)).focusWindow(
            window,
            in: owner,
            snapshot: service.snapshot(followFocus: false),
            generation: PlacementGeneration.shared.next(),
            label: "switcher activate",
            cause: "switcher.activate",
            eventPrefix: "window.switcher",
            details: [:]
        )

        #expect(!result.changed)
        #expect(writer.focused.isEmpty)
    }
}

private func spec056Window(_ id: UInt32, x: Double) -> WindowSnapshot {
    WindowSnapshot(
        id: WindowID(rawValue: id),
        pid: getpid(),
        appName: "App \(id)",
        bundleID: "app.\(id)",
        title: "Window \(id)",
        frame: Rect(x: x, y: 100, width: 300, height: 300),
        isOnScreen: true,
        isTileCandidate: true
    )
}

private func spec056Member(_ window: WindowSnapshot) -> PersistentStageMember {
    PersistentStageMember(
        windowID: window.id,
        bundleID: window.bundleID,
        title: window.title,
        frame: window.frame,
        pid: window.pid
    )
}

private final class Spec056RestoringWriter: WindowFrameWriting, @unchecked Sendable {
    let provider: PowerUserProvider
    let target: WindowSnapshot
    let becomesReadable: Bool
    var calls: [String] = []
    var restoredFrame: Rect?
    var focusSucceeds = true
    var frameSucceeds = true
    var onFocus: (() -> Void)?
    var otherSpaceSucceeds = false
    init(provider: PowerUserProvider, target: WindowSnapshot, becomesReadable: Bool) {
        self.provider = provider; self.target = target; self.becomesReadable = becomesReadable
    }
    func focus(_ window: WindowSnapshot) -> Bool {
        calls.append("focus")
        onFocus?()
        guard focusSucceeds else { return false }
        provider.focusedID = target.id
        if becomesReadable, !provider.snapshots.contains(where: { $0.id == target.id }) {
            var restored = target
            restored.frame = Rect(x: 0, y: 0, width: 100, height: 100)
            provider.snapshots.append(restored)
        }
        return true
    }
    func focusOnOtherSpace(_ window: WindowSnapshot, timeout: TimeInterval) -> SpaceFocusOutcome {
        calls.append("space")
        guard otherSpaceSucceeds else { return SpaceFocusOutcome(opened: true, focused: false, waitedMs: 0) }
        focusSucceeds = true
        return SpaceFocusOutcome(opened: true, focused: focus(window), waitedMs: 0)
    }
    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        calls.append("frame")
        guard frameSucceeds else { return nil }
        if window.id == target.id { restoredFrame = Rect(frame) }
        return frame
    }
}
