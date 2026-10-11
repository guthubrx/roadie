import CoreGraphics
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon
import RoadieStages

@Suite
struct ResizeHandlePickerTests {
    private func snapshot() -> DaemonSnapshot {
        let display = DisplayID(rawValue: "external")
        let scope = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        var state = RoadieState()
        state.ensureDisplay(display)
        try? state.createStage(id: scope.stageID, name: "Active", in: display, desktopID: scope.desktopID)
        try? state.switchStage(scope.stageID, in: display, desktopID: scope.desktopID)
        let windows = [
            WindowSnapshot(id: WindowID(rawValue: 1), pid: 1, appName: "A", bundleID: "a", title: "", frame: Rect(x: 1662, y: -926, width: 2016, height: 2114), isOnScreen: true, isTileCandidate: true),
            WindowSnapshot(id: WindowID(rawValue: 2), pid: 2, appName: "B", bundleID: "b", title: "", frame: Rect(x: 3688, y: -926, width: 1656, height: 2114), isOnScreen: true, isTileCandidate: true),
            WindowSnapshot(id: WindowID(rawValue: 3), pid: 3, appName: "Overlay", bundleID: "overlay", title: "", frame: Rect(x: 3680, y: -400, width: 2, height: 100), isOnScreen: true, isTileCandidate: false),
        ]
        return DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true), displays: [],
            windows: windows.map { ScopedWindowSnapshot(window: $0, scope: scope) }, state: state
        )
    }

    @Test(arguments: [
        CGPoint(x: 3678, y: -300), CGPoint(x: 3680, y: -300),
        CGPoint(x: 1660, y: -300), CGPoint(x: 2000, y: -928),
        CGPoint(x: 2000, y: 1190), CGPoint(x: 3680, y: 1190),
    ])
    func resizeHandleOutsideFrameKeepsWindow(point: CGPoint) {
        let snapshot = snapshot()
        #expect(FocusFollowsMousePicker.targetWindow(at: point, in: snapshot) == nil)
        #expect(FocusFollowsMousePicker.gestureTargetWindow(at: point, in: snapshot)?.window.id.rawValue == 1)
    }

    @Test
    func nearestEdgeWinsInGapAndInteriorWinsOverExpandedNeighbor() {
        let snapshot = snapshot()
        #expect(FocusFollowsMousePicker.gestureTargetWindow(at: CGPoint(x: 3681, y: -300), in: snapshot)?.window.id.rawValue == 1)
        #expect(FocusFollowsMousePicker.gestureTargetWindow(at: CGPoint(x: 3685, y: -300), in: snapshot)?.window.id.rawValue == 2)
        #expect(FocusFollowsMousePicker.gestureTargetWindow(at: CGPoint(x: 3689, y: -300), in: snapshot)?.window.id.rawValue == 2)
        #expect(FocusFollowsMousePicker.gestureTargetWindow(at: CGPoint(x: 1650, y: -300), in: snapshot) == nil)
    }

    @Test
    func equalDistanceUsesFocusedWindow() {
        var snapshot = snapshot()
        snapshot.focusedWindowID = WindowID(rawValue: 2)
        #expect(FocusFollowsMousePicker.gestureTargetWindow(at: CGPoint(x: 3683, y: -300), in: snapshot)?.window.id.rawValue == 2)
    }

    @Test
    func inactiveStageIsExcludedFromResizeHandles() {
        var snapshot = snapshot()
        snapshot.windows[0].scope = StageScope(displayID: DisplayID(rawValue: "external"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "2"))
        #expect(FocusFollowsMousePicker.gestureTargetWindow(at: CGPoint(x: 1660, y: -300), in: snapshot) == nil)
    }
}
