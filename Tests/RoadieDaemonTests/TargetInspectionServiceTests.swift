import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon
import RoadieStages

@Suite
struct TargetInspectionServiceTests {
    @Test
    func inspectWindowReportsPinnedFloatingAndScopeReasons() {
        let displayID = DisplayID(rawValue: "display-main")
        let stageID = StageID(rawValue: "1")
        let scope = StageScope(displayID: displayID, desktopID: DesktopID(rawValue: 1), stageID: stageID)
        var window = powerWindow(9, x: 100, app: "Settings")
        window.isTileCandidate = false
        let pin = PersistentWindowPin(
            windowID: window.id,
            homeScope: scope,
            pinScope: .desktop,
            bundleID: window.bundleID,
            title: window.title,
            lastFrame: window.frame
        )
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [powerDisplay(displayID.rawValue)],
            windows: [ScopedWindowSnapshot(window: window, scope: scope, pin: pin)],
            state: roadieState(displayID: displayID, activeStageID: stageID, windows: [scope: [window.id]]),
            focusedWindowID: window.id
        )
        let state = PersistentStageState(scopes: [
            PersistentStageScope(displayID: displayID, activeStageID: stageID, stages: [
                PersistentStage(id: stageID, members: [
                    PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
                ]),
            ]),
        ], windowPins: [pin], activeDisplayID: displayID)
        let target = RoadieTarget(
            id: "window:\(window.id.rawValue)",
            kind: .window,
            title: window.appName,
            subtitle: window.title,
            source: .roadie,
            scope: TargetScopeSnapshot(scope: scope, windowId: window.id),
            actions: [.focus, .inspect]
        )

        let inspection = TargetInspectionService.inspect(target: target, snapshot: snapshot, state: state)

        #expect(inspection.state.tileable == false)
        #expect(inspection.state.floating == true)
        #expect(inspection.state.pinned == true)
        #expect(inspection.state.focused == true)
        #expect(inspection.reasons.contains("excluded_from_tiling"))
        #expect(inspection.reasons.contains("pin_scope=desktop"))
    }

    @Test
    func inspectStaleWindowReturnsStaleReason() {
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [powerDisplay()],
            windows: [],
            state: RoadieState(),
            focusedWindowID: nil
        )
        let target = RoadieTarget(
            id: "window:99",
            kind: .window,
            title: "Gone",
            source: .roadie,
            scope: TargetScopeSnapshot(windowId: 99),
            actions: [.focus, .inspect]
        )

        let inspection = TargetInspectionService.inspect(target: target, snapshot: snapshot, state: PersistentStageState())

        #expect(inspection.state.focused == false)
        #expect(inspection.reasons.contains("stale_target"))
    }

    @Test
    func inspectionJSONKeepsTargetIdentityStateAndReasons() throws {
        let target = RoadieTarget(
            id: "stage:display-main/1/1",
            label: "A",
            kind: .stage,
            title: "Work",
            source: .roadie,
            scope: TargetScopeSnapshot(displayId: "display-main", desktopId: 1, stageId: "1"),
            actions: [.switch, .inspect]
        )
        let inspection = TargetInspection(
            target: target,
            summary: "Work - 2 fenêtre(s) live",
            identity: TargetInspectionIdentity(displayId: "display-main", desktopId: 1, stageId: "1"),
            state: TargetInspectionState(tileable: nil, floating: nil, pinned: nil, focused: nil, activeStage: true, source: "roadie"),
            reasons: ["mode=mutableBsp", "live_windows=2"]
        )

        let data = try JSONEncoder().encode(inspection)
        let decoded = try JSONDecoder().decode(TargetInspection.self, from: data)

        #expect(decoded.target.id == "stage:display-main/1/1")
        #expect(decoded.identity.stageId == "1")
        #expect(decoded.state.activeStage == true)
        #expect(decoded.reasons.contains("live_windows=2"))
    }
}
