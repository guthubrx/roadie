import CoreGraphics
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

@Suite
struct PowerUserDesktopCommandTests {
    @Test
    func desktopBackAndForthReturnsToPreviousDesktop() {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100)])
        let store = StageStore(path: tempPath("power-desktop-stages"))
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)
        _ = service.snapshot()
        let commands = DesktopCommandService(service: service, store: store)

        let focusTwo = commands.focus(DesktopID(rawValue: 2))
        let back = commands.backAndForth()

        #expect(focusTwo.changed)
        #expect(back.changed)
        #expect(store.state().currentDesktopID(for: DisplayID(rawValue: "display-main")) == DesktopID(rawValue: 1))
    }

    @Test
    func desktopSummonSwitchesRequestedDesktopToActiveDisplay() {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100)])
        let store = StageStore(path: tempPath("power-desktop-summon"))
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)
        _ = service.snapshot()

        let result = DesktopCommandService(service: service, store: store).summon(DesktopID(rawValue: 3))

        #expect(result.changed)
        #expect(store.state().currentDesktopID(for: DisplayID(rawValue: "display-main")) == DesktopID(rawValue: 3))
    }

    @Test
    func stageMoveToDisplayMovesActiveStageMembership() {
        let displays = [
            powerDisplay("display-main", index: 1, x: 0),
            powerDisplay("display-side", index: 2, x: 1000)
        ]
        let provider = PowerUserProvider(displays: displays, windows: [powerWindow(1, x: 100)])
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("power-stage-move"))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)
        _ = service.snapshot()

        let result = StageCommandService(service: service, store: store).moveActiveStageToDisplay(index: 2)

        var state = store.state()
        #expect(result.changed)
        #expect(state.activeDisplayID == DisplayID(rawValue: "display-side"))
        #expect(state.scope(displayID: DisplayID(rawValue: "display-side")).stages.contains { $0.members.contains { $0.windowID == WindowID(rawValue: 1) } })
    }

    @Test
    func stagePositionCommandsFollowVisibleRailOrder() {
        let display = DisplayID(rawValue: "display-main")
        let windows = [
            powerWindow(1, x: 100),
            powerWindow(2, x: 1200),
            powerWindow(3, x: 1400)
        ]
        let provider = PowerUserProvider(windows: windows)
        provider.focusedID = windows[0].id
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("power-stage-position"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [
                    PersistentStageMember(windowID: windows[0].id, bundleID: windows[0].bundleID, title: windows[0].title, frame: windows[0].frame),
                ]),
                PersistentStage(id: StageID(rawValue: "3"), members: [
                    PersistentStageMember(windowID: windows[1].id, bundleID: windows[1].bundleID, title: windows[1].title, frame: Rect(x: 350, y: 100, width: 300, height: 300)),
                ]),
                PersistentStage(id: StageID(rawValue: "4"), members: [
                    PersistentStageMember(windowID: windows[2].id, bundleID: windows[2].bundleID, title: windows[2].title, frame: Rect(x: 650, y: 100, width: 300, height: 300)),
                ]),
            ]),
        ]))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)
        let commands = StageCommandService(service: service, store: store)

        let switchSecond = commands.switchToPosition(2)
        let reorder = commands.reorder("4", to: 1)
        let switchFirstAfterReorder = commands.switchToPosition(1)

        var state = store.state()
        #expect(switchSecond.changed)
        #expect(reorder.changed)
        #expect(switchFirstAfterReorder.changed)
        #expect(state.scope(displayID: display).activeStageID == StageID(rawValue: "4"))
        #expect(writer.focused.map(\.rawValue).contains(2))
        #expect(writer.focused.map(\.rawValue).contains(3))
    }

    @Test
    func stageSwitchPersistsTargetStageBeforeRestoringWindows() {
        let display = DisplayID(rawValue: "display-main")
        let visible = powerWindow(1, x: 100)
        var hidden = powerWindow(2, x: 999)
        hidden.frame = Rect(x: 999, y: 499, width: 400, height: 300)
        let provider = PowerUserProvider(windows: [visible, hidden])
        provider.focusedID = visible.id
        let store = StageStore(path: tempPath("power-stage-switch-order"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [
                    PersistentStageMember(windowID: visible.id, bundleID: visible.bundleID, title: visible.title, frame: visible.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "2"), focusedWindowID: hidden.id, members: [
                    PersistentStageMember(windowID: hidden.id, bundleID: hidden.bundleID, title: hidden.title, frame: Rect(x: 250, y: 50, width: 500, height: 350)),
                ]),
            ]),
        ]))
        let writer = StageSwitchOrderWriter(provider: provider, store: store, observedWindowID: hidden.id)
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)

        let result = StageCommandService(service: service, store: store).switchToPosition(2)

        #expect(result.changed)
        #expect(!writer.activeStagesObservedForTargetFrame.isEmpty)
        #expect(writer.activeStagesObservedForTargetFrame.allSatisfy { $0 == StageID(rawValue: "2") })
    }

    @Test
    func stageAssignPositionUsesVisibleRailOrder() {
        let display = DisplayID(rawValue: "display-main")
        let left = powerWindow(1, x: 100)
        let right = powerWindow(2, x: 1200)
        let provider = PowerUserProvider(windows: [left, right])
        provider.focusedID = left.id
        let store = StageStore(path: tempPath("power-stage-assign-position"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [
                    PersistentStageMember(windowID: left.id, bundleID: left.bundleID, title: left.title, frame: left.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "2")),
                PersistentStage(id: StageID(rawValue: "7"), members: [
                    PersistentStageMember(windowID: right.id, bundleID: right.bundleID, title: right.title, frame: Rect(x: 350, y: 100, width: 300, height: 300)),
                ]),
            ]),
        ]))
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)

        let result = StageCommandService(service: service, store: store).assignPosition(2)
        var state = store.state()
        let scope = state.scope(displayID: display)

        #expect(result.changed)
        #expect(scope.memberIDs(in: StageID(rawValue: "1")).isEmpty)
        #expect(scope.memberIDs(in: StageID(rawValue: "7")).contains(left.id))
    }

    @Test
    func stageAssignPositionCanTargetHiddenEmptyStageSlots() {
        let display = DisplayID(rawValue: "display-main")
        let window = powerWindow(1, x: 100)
        let provider = PowerUserProvider(windows: [window])
        provider.focusedID = window.id
        let store = StageStore(path: tempPath("power-stage-assign-hidden-empty-position"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [
                    PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "2")),
                PersistentStage(id: StageID(rawValue: "3")),
            ]),
        ]))
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)

        let result = StageCommandService(service: service, store: store).assignPosition(2)
        var state = store.state()
        let scope = state.scope(displayID: display)

        #expect(result.changed)
        #expect(scope.memberIDs(in: StageID(rawValue: "1")).isEmpty)
        #expect(scope.memberIDs(in: StageID(rawValue: "2")).contains(window.id))
    }

    @Test
    func desktopAssignUpdatesPinnedWindowHomeScope() {
        let display = DisplayID(rawValue: "display-main")
        let window = powerWindow(1, x: 100)
        let provider = PowerUserProvider(windows: [window])
        let store = StageStore(path: tempPath("power-desktop-pinned-assign"))
        let home = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), members: [PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame)])
                ]),
                PersistentStageScope(displayID: display, desktopID: DesktopID(rawValue: 2), activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"))
                ])
            ],
            windowPins: [
                PersistentWindowPin(windowID: window.id, homeScope: home, pinScope: .allDesktops, bundleID: window.bundleID, title: window.title, lastFrame: window.frame)
            ],
            activeDisplayID: display
        ))
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)

        let result = DesktopCommandService(service: service, store: store).assign(windowID: window.id, to: DesktopID(rawValue: 2), displayID: display)

        #expect(result.changed)
        #expect(store.state().pin(for: window.id)?.homeScope.desktopID == DesktopID(rawValue: 2))
        #expect(store.state().stageScope(for: window.id)?.desktopID == DesktopID(rawValue: 2))
    }
}

private final class StageSwitchOrderWriter: WindowFrameWriting, @unchecked Sendable {
    let provider: PowerUserProvider
    let store: StageStore
    let observedWindowID: WindowID
    private(set) var activeStagesObservedForTargetFrame: [StageID] = []

    init(provider: PowerUserProvider, store: StageStore, observedWindowID: WindowID) {
        self.provider = provider
        self.store = store
        self.observedWindowID = observedWindowID
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        if window.id == observedWindowID {
            let activeStageID = store.state().scopes
                .first { $0.displayID == DisplayID(rawValue: "display-main") }?
                .activeStageID
            if let activeStageID {
                activeStagesObservedForTargetFrame.append(activeStageID)
            }
        }
        let rect = Rect(frame)
        provider.snapshots = provider.snapshots.map {
            guard $0.id == window.id else { return $0 }
            var updated = $0
            updated.frame = rect
            return updated
        }
        return frame
    }

    func focus(_ window: WindowSnapshot) -> Bool {
        provider.focusedID = window.id
        return true
    }

    func reset(_ window: WindowSnapshot) -> Bool { true }
    func toggleZoom(_ window: WindowSnapshot) -> Bool { true }
    func toggleNativeFullscreen(_ window: WindowSnapshot) -> Bool { true }
}
