import Testing
import RoadieCore
import RoadieStages

@Suite
struct WindowGroupStateTests {
    @Test
    func windowGroupTracksMembersAndActiveWindow() {
        var group = WindowGroup(id: "terminals", windowIDs: [WindowID(rawValue: 1)])

        group.add(WindowID(rawValue: 2))
        let focused = group.focus(WindowID(rawValue: 2))
        group.remove(WindowID(rawValue: 1))

        #expect(focused)
        #expect(group.windowIDs == [WindowID(rawValue: 2)])
        #expect(group.activeWindowID == WindowID(rawValue: 2))
    }

    @Test
    func stageStatePrunesGroupsWhenWindowIsRemoved() {
        var stage = StageState(
            id: StageID(rawValue: "1"),
            name: "Stage 1",
            windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)],
            groups: [WindowGroup(id: "pair", windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)])]
        )

        stage.remove(WindowID(rawValue: 2))

        #expect(stage.groups.isEmpty)
    }
}
