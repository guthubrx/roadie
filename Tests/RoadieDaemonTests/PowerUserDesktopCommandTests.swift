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
}
