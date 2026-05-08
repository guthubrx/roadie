import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon
import RoadieStages

@Suite
struct WindowGroupIndicatorTests {
    @MainActor
    @Test
    func borderControllerExposesGroupIndicatorState() {
        var state = RoadieState()
        let displayID = DisplayID(rawValue: "display-main")
        let desktopID = DesktopID(rawValue: 1)
        let stageID = StageID(rawValue: "1")
        try? state.createStage(id: stageID, name: "Stage 1", in: displayID, desktopID: desktopID)
        try? state.setGroups([
            WindowGroup(id: "docs", windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)], activeWindowID: WindowID(rawValue: 2))
        ], for: StageScope(displayID: displayID, desktopID: desktopID, stageID: stageID))
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [powerDisplay()],
            windows: [],
            state: state
        )

        let indicator = BorderController().groupIndicator(for: WindowID(rawValue: 1), snapshot: snapshot)

        #expect(indicator == "docs:2/2")
    }
}
