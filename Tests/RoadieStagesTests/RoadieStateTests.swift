import Testing
import RoadieCore
import RoadieStages

@Suite
struct RoadieStateTests {
    private let display = DisplayID(rawValue: "display-a")
    private let desktop1 = DesktopID(rawValue: 1)
    private let desktop2 = DesktopID(rawValue: 2)
    private let stage1 = StageID(rawValue: "1")
    private let stage2 = StageID(rawValue: "2")

    @Test
    func activeStageIsRememberedPerDesktop() throws {
        var state = RoadieState()
        try state.createStage(id: stage2, name: "Code", in: display, desktopID: desktop1)
        try state.createDesktop(desktop2, on: display)
        try state.createStage(id: stage2, name: "Docs", in: display, desktopID: desktop2)

        try state.switchStage(stage2, in: display, desktopID: desktop1)
        try state.switchDesktop(desktop2, on: display)

        #expect(state.activeScope(on: display)?.desktopID == desktop2)
        #expect(state.activeScope(on: display)?.stageID == stage1)

        try state.switchStage(stage2, in: display, desktopID: desktop2)
        try state.switchDesktop(desktop1, on: display)

        #expect(state.activeScope(on: display)?.desktopID == desktop1)
        #expect(state.activeScope(on: display)?.stageID == stage2)
    }

    @Test
    func assigningWindowMovesItBetweenStages() throws {
        let window = WindowID(rawValue: 42)
        var state = RoadieState()
        try state.createStage(id: stage2, name: "Secondary", in: display, desktopID: desktop1)

        try state.assignWindow(window, to: StageScope(displayID: display, desktopID: desktop1, stageID: stage1))
        try state.assignWindow(window, to: StageScope(displayID: display, desktopID: desktop1, stageID: stage2))

        #expect(state.stage(scope: StageScope(displayID: display, desktopID: desktop1, stageID: stage1))?.windowIDs == [])
        #expect(state.stage(scope: StageScope(displayID: display, desktopID: desktop1, stageID: stage2))?.windowIDs == [window])
    }

    @Test
    func modeChangesDoNotChangeMembership() throws {
        let window = WindowID(rawValue: 7)
        let scope = StageScope(displayID: display, desktopID: desktop1, stageID: stage1)
        var state = RoadieState()
        state.ensureDisplay(display)
        try state.assignWindow(window, to: scope)

        try state.setMode(.masterStack, for: scope)

        #expect(state.stage(scope: scope)?.mode == .masterStack)
        #expect(state.stage(scope: scope)?.windowIDs == [window])
    }
}
