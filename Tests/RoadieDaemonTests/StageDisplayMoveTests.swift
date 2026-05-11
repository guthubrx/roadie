import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

@Suite
struct StageDisplayMoveTests {
    @Test
    func moveActiveStageByDisplayIndexPreservesSourceAndMovesMembers() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let side = powerDisplay("display-side", index: 2, x: 1000)
        let moved = powerWindow(1, x: 100)
        let remaining = powerWindow(2, x: 500)
        let provider = PowerUserProvider(displays: [main, side], windows: [moved, remaining])
        let writer = PowerUserWriter(provider: provider)
        let store = stageStore("stage-display-move-index", scopes: [
            scope(main.id, active: "1", stages: [
                stage("1", moved),
                stage("2", remaining)
            ]),
            scope(side.id, active: "1", stages: [
                stage("1")
            ])
        ], activeDisplayID: main.id)
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store)

        let result = StageCommandService(service: service, store: store, config: RoadieConfig())
            .moveActiveStageToDisplay(index: 2)

        var state = store.state()
        #expect(result.changed)
        #expect(state.activeDisplayID == side.id)
        #expect(state.scope(displayID: main.id).activeStageID.rawValue == "2")
        #expect(state.scope(displayID: main.id).memberIDs(in: StageID(rawValue: "2")) == [remaining.id])
        #expect(state.scope(displayID: side.id).memberIDs(in: StageID(rawValue: "1")) == [moved.id])
        #expect(writer.frames[moved.id] != nil)
    }

    @Test
    func moveActiveStageByDirectionUsesDisplayTopology() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let right = powerDisplay("display-right", index: 2, x: 1000)
        let moved = powerWindow(1, x: 100)
        let provider = PowerUserProvider(displays: [main, right], windows: [moved])
        let writer = PowerUserWriter(provider: provider)
        let store = stageStore("stage-display-move-direction", scopes: [
            scope(main.id, active: "1", stages: [stage("1", moved)]),
            scope(right.id, active: "1", stages: [stage("1")])
        ], activeDisplayID: main.id)
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store)

        let result = StageCommandService(service: service, store: store, config: RoadieConfig())
            .moveActiveStageToDisplay(direction: .right)

        #expect(result.changed)
        var state = store.state()
        #expect(state.activeDisplayID == right.id)
        #expect(state.scope(displayID: right.id).memberIDs(in: StageID(rawValue: "1")) == [moved.id])
    }

    @Test
    func collisionWithNonEmptyTargetRenumbersMovedStageWithoutDroppingTarget() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let side = powerDisplay("display-side", index: 2, x: 1000)
        let moved = powerWindow(1, x: 100)
        let targetResident = powerWindow(2, x: 1100)
        let provider = PowerUserProvider(displays: [main, side], windows: [moved, targetResident])
        let writer = PowerUserWriter(provider: provider)
        let store = stageStore("stage-display-move-collision", scopes: [
            scope(main.id, active: "1", stages: [stage("1", moved)]),
            scope(side.id, active: "1", stages: [stage("1", targetResident)])
        ], activeDisplayID: main.id)
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store)

        let result = StageCommandService(service: service, store: store, config: RoadieConfig())
            .moveActiveStageToDisplay(index: 2)

        var state = store.state()
        let targetScope = state.scope(displayID: side.id)
        #expect(result.changed)
        #expect(targetScope.memberIDs(in: StageID(rawValue: "1")) == [targetResident.id])
        #expect(targetScope.memberIDs(in: StageID(rawValue: "2")) == [moved.id])
        #expect(targetScope.activeStageID.rawValue == "2")
    }

    @Test
    func noFollowKeepsFocusDisplayAndTargetActiveStage() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let side = powerDisplay("display-side", index: 2, x: 1000)
        let moved = powerWindow(1, x: 100)
        let targetResident = powerWindow(2, x: 1100)
        let provider = PowerUserProvider(displays: [main, side], windows: [moved, targetResident])
        let writer = PowerUserWriter(provider: provider)
        let store = stageStore("stage-display-move-no-follow", scopes: [
            scope(main.id, active: "1", stages: [stage("1", moved)]),
            scope(side.id, active: "9", stages: [
                stage("9", targetResident),
                stage("1")
            ])
        ], activeDisplayID: main.id)
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store)

        let result = StageCommandService(service: service, store: store, config: RoadieConfig())
            .moveActiveStageToDisplay(index: 2, followFocus: false)

        var state = store.state()
        #expect(result.changed)
        #expect(state.activeDisplayID == main.id)
        #expect(state.scope(displayID: side.id).activeStageID.rawValue == "9")
        #expect(state.scope(displayID: side.id).memberIDs(in: StageID(rawValue: "1")) == [moved.id])
    }

    @Test
    func configuredNoFollowAppliesWhenNoCliOverrideIsProvided() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let side = powerDisplay("display-side", index: 2, x: 1000)
        let moved = powerWindow(1, x: 100)
        let provider = PowerUserProvider(displays: [main, side], windows: [moved])
        let writer = PowerUserWriter(provider: provider)
        let store = stageStore("stage-display-move-config-no-follow", scopes: [
            scope(main.id, active: "1", stages: [stage("1", moved)]),
            scope(side.id, active: "1", stages: [stage("1")])
        ], activeDisplayID: main.id)
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store)
        let config = RoadieConfig(focus: FocusConfig(stageMoveFollowsFocus: false))

        let result = StageCommandService(service: service, store: store, config: config)
            .moveActiveStageToDisplay(index: 2)

        var state = store.state()
        #expect(result.changed)
        #expect(state.activeDisplayID == main.id)
        #expect(state.scope(displayID: side.id).activeStageID != StageID(rawValue: "1"))
        #expect(state.scope(displayID: side.id).memberIDs(in: StageID(rawValue: "1")) == [moved.id])
    }

    @Test
    func explicitFollowOverridesNoFollowConfig() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let side = powerDisplay("display-side", index: 2, x: 1000)
        let moved = powerWindow(1, x: 100)
        let provider = PowerUserProvider(displays: [main, side], windows: [moved])
        let writer = PowerUserWriter(provider: provider)
        let store = stageStore("stage-display-move-explicit-follow", scopes: [
            scope(main.id, active: "1", stages: [stage("1", moved)]),
            scope(side.id, active: "1", stages: [stage("1")])
        ], activeDisplayID: main.id)
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store)
        let config = RoadieConfig(focus: FocusConfig(stageMoveFollowsFocus: false))

        let result = StageCommandService(service: service, store: store, config: config)
            .moveActiveStageToDisplay(index: 2, followFocus: true)

        #expect(result.changed)
        #expect(store.state().activeDisplayID == side.id)
    }

    @Test
    func explicitStageMoveSupportsInactiveRailStageWithoutActivatingItFirst() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let side = powerDisplay("display-side", index: 2, x: 1000)
        let active = powerWindow(1, x: 100)
        let inactive = powerWindow(2, x: 500)
        let provider = PowerUserProvider(displays: [main, side], windows: [active, inactive])
        let writer = PowerUserWriter(provider: provider)
        let store = stageStore("stage-display-move-inactive-rail", scopes: [
            scope(main.id, active: "1", stages: [
                stage("1", active),
                stage("2", inactive)
            ]),
            scope(side.id, active: "1", stages: [stage("1")])
        ], activeDisplayID: main.id)
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store)

        let result = StageCommandService(service: service, store: store, config: RoadieConfig())
            .moveStageToDisplay(
                stageID: StageID(rawValue: "2"),
                sourceDisplayID: main.id,
                targetDisplayID: side.id,
                followFocus: false,
                source: "rail"
            )

        var state = store.state()
        #expect(result.changed)
        #expect(state.activeDisplayID == main.id)
        #expect(state.scope(displayID: main.id).activeStageID.rawValue == "1")
        #expect(state.scope(displayID: side.id).memberIDs(in: StageID(rawValue: "2")) == [inactive.id])
    }

    @Test
    func invalidOrCurrentTargetDoesNotMutateState() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let moved = powerWindow(1, x: 100)
        let provider = PowerUserProvider(displays: [main], windows: [moved])
        let store = stageStore("stage-display-move-invalid", scopes: [
            scope(main.id, active: "1", stages: [stage("1", moved)])
        ], activeDisplayID: main.id)
        let service = SnapshotService(provider: provider, config: RoadieConfig(), stageStore: store)
        var before = store.state()
        let commands = StageCommandService(service: service, store: store, config: RoadieConfig())

        let invalid = commands.moveActiveStageToDisplay(index: 99)
        let current = commands.moveActiveStageToDisplay(index: 1)

        var after = store.state()
        #expect(!invalid.changed)
        #expect(!current.changed)
        #expect(after.activeDisplayID == before.activeDisplayID)
        #expect(after.scope(displayID: main.id).activeStageID == before.scope(displayID: main.id).activeStageID)
        #expect(after.scope(displayID: main.id).memberIDs(in: StageID(rawValue: "1")) == [moved.id])
    }

    @Test
    func railStageMoveTargetsExcludeSourceDisplayAndSortByIndex() {
        let first = powerDisplay("display-first", index: 2, x: 1000)
        let second = powerDisplay("display-second", index: 1, x: 0)
        let third = powerDisplay("display-third", index: 3, x: 2000)
        let provider = PowerUserProvider(displays: [first, second, third], windows: [])
        let service = SnapshotService(provider: provider, config: RoadieConfig(), stageStore: StageStore(path: tempPath("rail-stage-targets")))
        let snapshot = service.snapshot()

        let targets = RailController.stageDisplayMoveTargets(sourceDisplayID: first.id, in: snapshot)

        #expect(targets.map(\.id) == [second.id, third.id])
    }

    @Test
    func railStageMoveTargetsAreEmptyOnSingleDisplay() {
        let display = powerDisplay("display-only", index: 1, x: 0)
        let provider = PowerUserProvider(displays: [display], windows: [])
        let service = SnapshotService(provider: provider, config: RoadieConfig(), stageStore: StageStore(path: tempPath("rail-stage-targets-single")))
        let snapshot = service.snapshot()

        let targets = RailController.stageDisplayMoveTargets(sourceDisplayID: display.id, in: snapshot)

        #expect(targets.isEmpty)
    }

    @Test
    func stageDisplayMoveUpdatesPinnedWindowHomeDisplay() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let side = powerDisplay("display-side", index: 2, x: 1000)
        let moved = powerWindow(1, x: 100)
        let home = StageScope(displayID: main.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let provider = PowerUserProvider(displays: [main, side], windows: [moved])
        let store = stageStore("stage-display-pinned-move", scopes: [
            scope(main.id, active: "1", stages: [stage("1", moved)]),
            scope(side.id, active: "1", stages: [stage("1")])
        ], activeDisplayID: main.id)
        var state = store.state()
        state.setPin(window: moved, homeScope: home, pinScope: .allDesktops)
        store.save(state)
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), config: RoadieConfig(), stageStore: store)

        let result = StageCommandService(service: service, store: store, config: RoadieConfig())
            .moveActiveStageToDisplay(index: 2)

        #expect(result.changed)
        #expect(store.state().pin(for: moved.id)?.homeScope.displayID == side.id)
        #expect(store.state().stageScope(for: moved.id)?.displayID == side.id)
    }
}

private func stageStore(
    _ name: String,
    scopes: [PersistentStageScope],
    activeDisplayID: DisplayID
) -> StageStore {
    let store = StageStore(path: tempPath(name))
    store.save(PersistentStageState(scopes: scopes, activeDisplayID: activeDisplayID))
    return store
}

private func scope(
    _ displayID: DisplayID,
    active rawActiveID: String,
    stages: [PersistentStage]
) -> PersistentStageScope {
    PersistentStageScope(
        displayID: displayID,
        activeStageID: StageID(rawValue: rawActiveID),
        stages: stages
    )
}

private func stage(_ rawID: String, _ windows: WindowSnapshot...) -> PersistentStage {
    PersistentStage(
        id: StageID(rawValue: rawID),
        members: windows.map(member)
    )
}

private func member(_ window: WindowSnapshot) -> PersistentStageMember {
    PersistentStageMember(
        windowID: window.id,
        bundleID: window.bundleID,
        title: window.title,
        frame: window.frame
    )
}
