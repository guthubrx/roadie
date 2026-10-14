import Testing
import RoadieCore
@testable import RoadieStages

@Suite
struct Spec024MembershipTests {
    private func scope(_ stage: String, display: String = "main", desktop: Int = 1) -> StageScope {
        StageScope(displayID: DisplayID(rawValue: display), desktopID: DesktopID(rawValue: desktop), stageID: StageID(rawValue: stage))
    }

    @Test
    func groupedMembershipMatchesSequentialAssignmentIncludingDuplicates() throws {
        let scopes = [scope("1"), scope("2"), scope("3", display: "other", desktop: 2)]
        var initial = RoadieState()
        for scope in scopes {
            try? initial.createStage(id: scope.stageID, name: scope.stageID.rawValue, in: scope.displayID, desktopID: scope.desktopID)
        }
        let assignments = [
            (WindowID(rawValue: 1), scopes[0]), (WindowID(rawValue: 2), scopes[0]),
            (WindowID(rawValue: 3), scopes[1]), (WindowID(rawValue: 1), scopes[1]),
            (WindowID(rawValue: 4), scopes[2]), (WindowID(rawValue: 3), scopes[1]),
            (WindowID(rawValue: 5), scopes[2]), (WindowID(rawValue: 4), scopes[0])
        ]
        var sequential = initial
        for (id, scope) in assignments { try sequential.assignWindow(id, to: scope) }
        var grouped = initial
        try grouped.initializeWindowMemberships(assignments)
        #expect(grouped == sequential)
    }

    @Test
    func invalidScopeLeavesFreshStateUntouched() throws {
        var state = RoadieState()
        state.ensureDisplay(DisplayID(rawValue: "main"))
        let before = state
        #expect(throws: RoadieStateError.self) {
            try state.initializeWindowMemberships([(WindowID(rawValue: 1), scope("missing")), (WindowID(rawValue: 2), scope("1"))])
        }
        #expect(state == before)
    }

    @Test
    func initializationKeepsMetadataAndAllowsRealFocusRestoration() throws {
        var state = RoadieState()
        let target = scope("1")
        state.ensureDisplay(target.displayID)
        try state.setMode(.masterStack, for: target)
        let group = WindowGroup(id: "pair", windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)])
        try state.setGroups([group], for: target)
        try state.initializeWindowMemberships([(WindowID(rawValue: 1), target), (WindowID(rawValue: 2), target)])
        #expect(state.stage(scope: target)?.focusedWindowID == WindowID(rawValue: 2))
        try state.setFocusedWindow(WindowID(rawValue: 1), for: target)
        #expect(state.stage(scope: target)?.focusedWindowID == WindowID(rawValue: 1))
        #expect(state.stage(scope: target)?.mode == .masterStack)
        #expect(state.stage(scope: target)?.groups == [group])
    }
}
