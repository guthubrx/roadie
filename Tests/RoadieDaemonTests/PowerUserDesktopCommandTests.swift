import Testing
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
}
