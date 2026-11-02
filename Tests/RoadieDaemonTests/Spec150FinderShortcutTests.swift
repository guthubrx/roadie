import AppKit
import RoadieAX
import RoadieCore
import Testing
@testable import RoadieDaemon

@Suite struct Spec150FinderShortcutTests {
    private let left = DisplayID(rawValue: "left"), right = DisplayID(rawValue: "right")

    @Test func anEmptyScreenUnderThePointerWinsOverTheFocusedScreen() {
        let a = Rect(x: 0, y: 0, width: 1000, height: 800)
        let b = Rect(x: 1000, y: -400, width: 1600, height: 1200)
        let displays = [DisplaySnapshot(id: left, index: 1, name: "Left", frame: a, visibleFrame: a, isMain: true),
                        DisplaySnapshot(id: right, index: 2, name: "Right", frame: b, visibleFrame: b, isMain: false)]
        let state = PersistentStageState(scopes: [
            PersistentStageScope(displayID: left, activeStageID: StageID(rawValue: "1")),
            PersistentStageScope(displayID: right, activeStageID: StageID(rawValue: "hidden")),
            PersistentStageScope(displayID: right, desktopID: DesktopID(rawValue: 2), activeStageID: StageID(rawValue: "empty"))
        ], desktopSelections: [PersistentDesktopSelection(displayID: right, currentDesktopID: DesktopID(rawValue: 2))], activeDisplayID: left)

        #expect(LauncherPlacement.stageUnderPointer(CGPoint(x: 1400, y: -200), displays: displays, state: state)
                == StageScope(displayID: right, desktopID: DesktopID(rawValue: 2), stageID: StageID(rawValue: "empty")))
        #expect(LauncherPlacement.stageUnderPointer(CGPoint(x: 1000, y: 100), displays: displays, state: state)?.displayID == right)
        #expect(LauncherPlacement.stageUnderPointer(CGPoint(x: 999, y: 100), displays: displays, state: state)?.displayID == left)
        #expect(LauncherPlacement.stageUnderPointer(CGPoint(x: -10, y: -10), displays: displays, state: state) == nil)
        #expect(LauncherPlacement.stageUnderPointer(CGPoint(x: 1400, y: -200), displays: [], state: state) == nil)
        #expect(LauncherPlacement.stageUnderPointer(CGPoint(x: 1400, y: -200), displays: displays, state: PersistentStageState()) == nil)
    }

    @Test @MainActor func mouseDestinationRequiresHereWithoutAnotherDestination() {
        let router = CLICommandRouter()
        for tail in [["--mouse"], ["--here", "--mouse", "--stage", "Elsewhere"], ["--here", "--mouse", "--new-stage"]] {
            #expect(router.run(["launch", "/not-opened"] + tail).exitCode == 64)
        }
        #expect(router.run(["help", "launch"]).stdout.contains("--here [--mouse]"))
    }
}
