import CoreGraphics
import Testing
import RoadieAX
import RoadieCore
import RoadieStages
@testable import RoadieDaemon

@Suite
struct TargetModeRuntimeControllerTests {
    @Test
    func commandRoundTripsThroughDistributedNotificationPayload() throws {
        let command = TargetModeRuntimeCommand(name: "targets.interactive", arguments: [
            "source": "all",
            "includeAppTargets": "true",
            "duration": "10"
        ])

        let parsed = try #require(TargetModeRuntimeCommand(userInfo: command.userInfo))

        #expect(parsed.name == "targets.interactive")
        #expect(parsed.string("source") == "all")
        #expect(parsed.bool("includeAppTargets"))
        #expect(parsed.double("duration") == 10)
    }

    @Test
    func commandRejectsMissingCommandName() {
        #expect(TargetModeRuntimeCommand(userInfo: ["source": "all"]) == nil)
    }

    @Test
    func gridFocusPickerPrefersTopmostWindowContainingCellCenter() {
        let large = ScopedWindowSnapshot(window: WindowSnapshot(
            id: WindowID(rawValue: 10),
            pid: 100,
            appName: "Large",
            bundleID: "large",
            title: "Large",
            frame: Rect(x: 100, y: 100, width: 500, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        ), scope: nil)
        let small = ScopedWindowSnapshot(window: WindowSnapshot(
            id: WindowID(rawValue: 20),
            pid: 200,
            appName: "Small",
            bundleID: "small",
            title: "Small",
            frame: Rect(x: 140, y: 140, width: 80, height: 80),
            isOnScreen: true,
            isTileCandidate: true
        ), scope: nil)
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [],
            windows: [large, small],
            state: RoadieState()
        )

        let target = GridFocusPicker.targetWindow(intersectingAXFrame: CGRect(x: 120, y: 120, width: 140, height: 140), in: snapshot)

        #expect(target?.window.id == large.window.id)
    }

    @Test
    func gridFocusPickerFallsBackToTopmostIntersectingWindowWhenCenterIsEmpty() {
        let top = ScopedWindowSnapshot(window: WindowSnapshot(
            id: WindowID(rawValue: 30),
            pid: 300,
            appName: "Top",
            bundleID: "top",
            title: "Top",
            frame: Rect(x: 100, y: 100, width: 100, height: 100),
            isOnScreen: true,
            isTileCandidate: true
        ), scope: nil)
        let bottom = ScopedWindowSnapshot(window: WindowSnapshot(
            id: WindowID(rawValue: 40),
            pid: 400,
            appName: "Bottom",
            bundleID: "bottom",
            title: "Bottom",
            frame: Rect(x: 110, y: 110, width: 500, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        ), scope: nil)
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [],
            windows: [top, bottom],
            state: RoadieState()
        )

        let target = GridFocusPicker.targetWindow(intersectingAXFrame: CGRect(x: 90, y: 90, width: 130, height: 60), in: snapshot)

        #expect(target?.window.id == top.window.id)
    }
}
