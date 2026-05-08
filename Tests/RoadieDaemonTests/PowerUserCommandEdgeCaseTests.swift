import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct PowerUserCommandEdgeCaseTests {
    @Test
    func commandsHandleEmptyWindowSets() {
        let provider = PowerUserProvider(windows: [])
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider))

        #expect(!WindowCommandService(service: service).focusBackAndForth().changed)
        #expect(!LayoutCommandService(service: service).zoomParent().changed)
    }

    @Test
    func commandsHandleUnknownDisplayAndStaleWindow() {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100)])
        let store = StageStore(path: tempPath("power-edge-stages"))
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)
        _ = service.snapshot()

        let stageMove = StageCommandService(service: service, store: store).moveActiveStageToDisplay(index: 99)
        let stageSummon = StageCommandService(service: service, store: store).summon(
            windowID: WindowID(rawValue: 999),
            displayID: DisplayID(rawValue: "display-main")
        )

        #expect(!stageMove.changed)
        #expect(stageSummon.changed)
        #expect(stageSummon.message.contains("stale window pruned"))
    }
}
