import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

@Suite
struct Spec056ModelTests {
    @Test
    func historyIgnoresNilAndDuplicatesAndKeepsMostRecentFirst() {
        let history = WindowSwitcherFocusHistory()
        history.observe(nil)
        history.observe(WindowID(rawValue: 1))
        history.observe(WindowID(rawValue: 2))
        history.observe(WindowID(rawValue: 1))

        #expect(history.recentIDs == [WindowID(rawValue: 1), WindowID(rawValue: 2)])
    }

    @Test
    func historyIsBoundedToCapacity() {
        let history = WindowSwitcherFocusHistory()
        for raw in 1...600 {
            history.observe(WindowID(rawValue: UInt32(raw)))
        }

        #expect(history.recentIDs.count == WindowSwitcherFocusHistory.capacity)
        #expect(history.recentIDs.first == WindowID(rawValue: 600))
        #expect(history.recentIDs.last == WindowID(rawValue: 89))
    }

    @Test
    func initialSelectionIsThePreviousWindowNotTheFocusedOne() {
        let entries = [spec056Entry(1), spec056Entry(2), spec056Entry(3)]
        let model = WindowSwitcherModel(
            entries: entries,
            profile: spec056Profile(),
            context: WindowSwitcherContext(focusedWindowID: WindowID(rawValue: 1)),
            recentIDs: [WindowID(rawValue: 1), WindowID(rawValue: 3), WindowID(rawValue: 2)]
        )

        #expect(model.selected?.id == WindowID(rawValue: 3))
    }

    @Test
    func singleWindowIsSelectedAlone() {
        let model = WindowSwitcherModel(
            entries: [spec056Entry(7)],
            profile: spec056Profile(),
            context: WindowSwitcherContext()
        )

        #expect(model.matches.count == 1)
        #expect(model.selected?.id == WindowID(rawValue: 7))
    }

    @Test
    func nextWrapsForwardAndBackward() {
        var model = WindowSwitcherModel(
            entries: [spec056Entry(1), spec056Entry(2), spec056Entry(3)],
            profile: spec056Profile(),
            context: WindowSwitcherContext(focusedWindowID: WindowID(rawValue: 1)),
            recentIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2), WindowID(rawValue: 3)]
        )
        #expect(model.selected?.id == WindowID(rawValue: 2))

        model.next()
        #expect(model.selected?.id == WindowID(rawValue: 3))
        model.next()
        #expect(model.selected?.id == WindowID(rawValue: 1))
        model.next(backwards: true)
        #expect(model.selected?.id == WindowID(rawValue: 3))
    }

    @Test
    func searchIgnoresCaseAndAccents() {
        var model = WindowSwitcherModel(
            entries: [spec056Entry(1, title: "Résumé"), spec056Entry(2, title: "Calendrier")],
            profile: spec056Profile(),
            context: WindowSwitcherContext()
        )

        model.search("resume")
        #expect(model.matches.map(\.id) == [WindowID(rawValue: 1)])

        model.search("")
        #expect(model.matches.count == 2)
    }

    @Test
    func stageScopeShowsOnlyTheFocusedStage() {
        let stageOne = spec056Scope(stage: "1")
        let stageTwo = spec056Scope(stage: "2")
        let model = WindowSwitcherModel(
            entries: [spec056Entry(1, scope: stageOne), spec056Entry(2, scope: stageTwo)],
            profile: spec056Profile(scope: "stage"),
            context: WindowSwitcherContext(
                displayID: stageOne.displayID,
                desktopID: stageOne.desktopID,
                stageID: stageOne.stageID
            )
        )

        #expect(model.matches.map(\.id) == [WindowID(rawValue: 1)])
    }

    @Test
    func excludedBundlesAreRemoved() {
        let model = WindowSwitcherModel(
            entries: [spec056Entry(1, bundle: "app.keep"), spec056Entry(2, bundle: "app.hide")],
            profile: spec056Profile(),
            context: WindowSwitcherContext(),
            excludedBundles: ["app.hide"]
        )

        #expect(model.matches.map(\.id) == [WindowID(rawValue: 1)])
    }

    @Test
    func minimizedWindowsAreRemovedWhenProfileExcludesThem() {
        let model = WindowSwitcherModel(
            entries: [spec056Entry(1), spec056Entry(2, minimized: true)],
            profile: spec056Profile(includeMinimized: false),
            context: WindowSwitcherContext()
        )

        #expect(model.matches.map(\.id) == [WindowID(rawValue: 1)])
    }

    @Test
    func onePerAppKeepsTheFirstWindowOfEachBundle() {
        let model = WindowSwitcherModel(
            entries: [spec056Entry(1, bundle: "app.same"), spec056Entry(2, bundle: "app.same")],
            profile: spec056Profile(onePerApp: true),
            context: WindowSwitcherContext()
        )

        #expect(model.matches.count == 1)
    }

    @Test
    func titleSortOrderIgnoresCaseAndAccents() {
        let model = WindowSwitcherModel(
            entries: [spec056Entry(1, title: "Zèbre"), spec056Entry(2, title: "alpha")],
            profile: spec056Profile(sortOrder: "title"),
            context: WindowSwitcherContext()
        )

        #expect(model.matches.map(\.id) == [WindowID(rawValue: 2), WindowID(rawValue: 1)])
    }

    @Test
    func removingTheSelectedWindowMovesSelectionToAnotherMatch() {
        var model = WindowSwitcherModel(
            entries: [spec056Entry(1), spec056Entry(2), spec056Entry(3)],
            profile: spec056Profile(),
            context: WindowSwitcherContext(),
            recentIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2), WindowID(rawValue: 3)]
        )
        #expect(model.selected?.id == WindowID(rawValue: 1))

        model.remove(id: WindowID(rawValue: 1))

        #expect(model.matches.map(\.id) == [WindowID(rawValue: 2), WindowID(rawValue: 3)])
        #expect(model.selected?.id == WindowID(rawValue: 2))
    }

    @Test
    func selectingAnUnknownWindowChangesNothing() {
        var model = WindowSwitcherModel(
            entries: [spec056Entry(1), spec056Entry(2)],
            profile: spec056Profile(),
            context: WindowSwitcherContext(),
            recentIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)]
        )
        let before = model.selected?.id

        model.select(id: WindowID(rawValue: 99))

        #expect(model.selected?.id == before)
    }
}

private func spec056Profile(
    scope: String = "all",
    sortOrder: String = "recent",
    includeMinimized: Bool = true,
    onePerApp: Bool = false
) -> WindowSwitcherShortcutConfig {
    WindowSwitcherShortcutConfig(
        id: "all",
        name: "Toutes les fenêtres",
        hotkey: "ctrl+alt+tab",
        scope: scope,
        releaseAction: "focus",
        sortOrder: sortOrder,
        includeMinimized: includeMinimized,
        includeHidden: true,
        includeFullscreen: true,
        onePerApp: onePerApp
    )
}

private func spec056Scope(stage: String) -> StageScope {
    StageScope(
        displayID: DisplayID(rawValue: "display-main"),
        desktopID: DesktopID(rawValue: 1),
        stageID: StageID(rawValue: stage)
    )
}

private func spec056Entry(
    _ id: UInt32,
    title: String = "Window",
    scope: StageScope? = nil,
    minimized: Bool = false,
    bundle: String? = nil
) -> WindowSwitcherEntry {
    WindowSwitcherEntry(
        window: WindowSnapshot(
            id: WindowID(rawValue: id),
            pid: Int32(id),
            appName: "App \(id)",
            bundleID: bundle ?? "app.\(id)",
            title: title,
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            isOnScreen: !minimized,
            isTileCandidate: true
        ),
        scope: scope ?? spec056Scope(stage: "1"),
        isMinimized: minimized
    )
}
