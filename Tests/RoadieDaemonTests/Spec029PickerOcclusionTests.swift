import CoreGraphics
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon
import RoadieStages

@Suite
struct Spec029PickerOcclusionTests {
    private func snapshot(popupInFront: Bool = false, borderInFront: Bool = false) -> DaemonSnapshot {
        let display = DisplayID(rawValue: "display-main")
        let scope = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        var state = RoadieState()
        state.ensureDisplay(display)
        func window(_ id: UInt32, frame: Rect, managed: Bool) -> ScopedWindowSnapshot {
            ScopedWindowSnapshot(window: WindowSnapshot(id: WindowID(rawValue: id), pid: Int32(id), appName: "Fixture",
                bundleID: "fixture.\(id)", title: "", frame: frame, isOnScreen: true, isTileCandidate: managed),
                scope: managed ? scope : nil)
        }
        let parent = window(1, frame: Rect(x: 1542, y: 45, width: 500, height: 1220), managed: true)
        let border = window(2, frame: Rect(x: 1530, y: 33, width: 524, height: 1244), managed: false)
        let left = window(3, frame: Rect(x: 150, y: 38, width: 1382, height: 1234), managed: true)
        var windows = borderInFront ? [border, parent, left] : [parent, border, left]
        if popupInFront {
            windows.insert(window(4, frame: Rect(x: 1530, y: 510, width: 30, height: 40), managed: false), at: 0)
        }
        return DaemonSnapshot(permissions: PermissionSnapshot(accessibilityTrusted: true), displays: [],
                              windows: windows, state: state, focusedWindowID: WindowID(rawValue: 1))
    }

    @Test(arguments: [CGPoint(x: 1541.1640625, y: 524.59765625), CGPoint(x: 1537.8125, y: 532.55078125)])
    func behindWindowDoesNotBlockItsFrontParentsHandle(point: CGPoint) {
        let snapshot = snapshot()
        #expect(FocusFollowsMousePicker.frontWindow(at: point, in: snapshot)?.window.id.rawValue == 2)
        #expect(FocusFollowsMousePicker.targetWindow(at: point, in: snapshot) == nil)
        #expect(FocusFollowsMousePicker.gestureTargetWindow(at: point, in: snapshot)?.window.id.rawValue == 1)
    }

    @Test(arguments: [true, false])
    func genuinelyFrontIneligibleWindowStillBlocks(popup: Bool) {
        let snapshot = snapshot(popupInFront: popup, borderInFront: !popup)
        #expect(FocusFollowsMousePicker.gestureTargetWindow(at: CGPoint(x: 1537.8125, y: 532.55078125), in: snapshot) == nil)
    }

    @Test
    func directEligibleInteriorKeepsItsPriority() {
        let snapshot = snapshot()
        #expect(FocusFollowsMousePicker.gestureTargetWindow(at: CGPoint(x: 1543, y: 532), in: snapshot)?.window.id.rawValue == 1)
    }

    @Test
    func handleBehindTheFirstIneligibleInteriorIsNotConsidered() {
        // À 1533, la poignée gauche (id3) est plus proche mais derrière le premier intérieur.
        // Le parent id1, devant, est à 9 points : hors de sa bande de 8 points.
        let snapshot = snapshot()
        #expect(FocusFollowsMousePicker.gestureTargetWindow(at: CGPoint(x: 1533, y: 532), in: snapshot) == nil)
    }
}
