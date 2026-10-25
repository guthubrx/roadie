import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

struct Spec067StageNamesTests {
    private let a = DisplayID(rawValue: "display-main")
    private let b = DisplayID(rawValue: "display-other")
    private func d(_ raw: Int) -> DesktopID { DesktopID(rawValue: raw) }
    private func s(_ raw: String) -> StageID { StageID(rawValue: raw) }
    private func member(_ id: UInt32) -> PersistentStageMember {
        PersistentStageMember(windowID: WindowID(rawValue: id), bundleID: "app", title: "w\(id)", frame: Rect(x: 0, y: 0, width: 100, height: 100))
    }
    private func names(_ state: PersistentStageState, _ display: DisplayID, _ desktop: Int) -> [String] {
        state.scopes.first { $0.displayID == display && $0.desktopID == d(desktop) }?.stages.map(\.name) ?? []
    }

    @Test func duplicatesKeepTheOccupiedCopyAndNeverLoseWindows() {
        var state = PersistentStageState(scopes: [
            PersistentStageScope(displayID: a, desktopID: d(1), stages: [PersistentStage(id: s("2"), name: "Perso"), PersistentStage(id: s("1"), name: "Work")]),
            PersistentStageScope(displayID: a, desktopID: d(2), stages: [PersistentStage(id: s("2"), name: "Perso", members: [member(1), member(2)])]),
            PersistentStageScope(displayID: b, desktopID: d(1), stages: [PersistentStage(id: s("9"), name: "perso ", members: [member(3)]),
                                                                       PersistentStage(id: s("1"), name: "Work")]),
        ], activeDisplayID: b)

        let changed = state.makeStageNamesUnique()

        #expect(changed == 3)
        #expect(names(state, a, 2) == ["Perso"])
        #expect(names(state, b, 1) == ["Perso 2", "Work"])
        #expect(names(state, a, 1) == ["Stage 2", "Stage 1"])
        #expect(state.duplicateStageNameCount == 0)
        #expect(state.scopes.flatMap { $0.stages.flatMap(\.members) }.count == 3)
        #expect(state.makeStageNamesUnique() == 0)
    }

    @Test func configuredWorkspaceNamesOnlyOneStage() {
        let config = StageManagerConfig(workspaces: [StageDefinition(id: "1", displayName: "Work"), StageDefinition(id: "2", displayName: "Perso")])
        var scope = PersistentStageScope(displayID: a, desktopID: d(3), stages: [])
        scope.applyConfiguredStages(config, takenNames: [StageNameUniqueness.key("Work")])
        #expect(scope.stages.map(\.id) == [s("1"), s("2")])
        #expect(scope.stages.map(\.name) == ["Stage 1", "Perso"])
    }

    @Test func renameToANameUsedElsewhereIsRefused() {
        let store = StageStore(path: tempPath("spec067-rename"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: a, desktopID: d(1), stages: [PersistentStage(id: s("1"), name: "Work"), PersistentStage(id: s("2"))]),
            PersistentStageScope(displayID: b, desktopID: d(4), stages: [PersistentStage(id: s("1"), name: "Perso")]),
        ], desktopSelections: [PersistentDesktopSelection(displayID: a, currentDesktopID: d(1))]))
        let service = SnapshotService(provider: PowerUserProvider(windows: []), frameWriter: PowerUserWriter(provider: PowerUserProvider(windows: [])),
                                      config: RoadieConfig(), stageStore: store)
        let commands = StageCommandService(service: service, store: store, events: EventLog(path: tempPath("spec067-events")))

        #expect(commands.rename("2", to: " perso", displayID: a).outcome == .failed)
        #expect(commands.rename("1", to: "Work", displayID: a).changed)
        #expect(commands.rename("2", to: "Lecture", displayID: a).changed)
        #expect(names(store.state(), a, 1) == ["Work", "Lecture"])
    }

    @Test func stageMovesToAPlaceOfAnotherDesktopWithItsName() {
        let store = StageStore(path: tempPath("spec067-move"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: a, desktopID: d(1), activeStageID: s("1"), stages: [
                PersistentStage(id: s("1"), name: "Work"), PersistentStage(id: s("3"), name: "Com", members: [member(5)])]),
            PersistentStageScope(displayID: a, desktopID: d(2), activeStageID: s("1"), stages: [
                PersistentStage(id: s("1"), name: "Un"), PersistentStage(id: s("3"), name: "Trois"), PersistentStage(id: s("4"), name: "Quatre")]),
        ], desktopSelections: [PersistentDesktopSelection(displayID: a, currentDesktopID: d(1))],
           windowPins: [PersistentWindowPin(windowID: WindowID(rawValue: 5), homeScope: StageScope(displayID: a, desktopID: d(1), stageID: s("3")),
                                            pinScope: .stage, bundleID: "app", title: "w5", lastFrame: Rect(x: 0, y: 0, width: 10, height: 10))]))
        let service = SnapshotService(provider: PowerUserProvider(windows: []), frameWriter: PowerUserWriter(provider: PowerUserProvider(windows: [])),
                                      config: RoadieConfig(), stageStore: store)
        let commands = StageCommandService(service: service, store: store, events: EventLog(path: tempPath("spec067-move-events")))

        let result = commands.moveStage(s("3"), displayID: a, from: d(1), to: d(2), before: s("4"))

        #expect(result.changed)
        let state = store.state()
        #expect(names(state, a, 1) == ["Work"])
        // Identifiant 3 déjà pris par une stage nommée : la stage arrivante change d'identifiant, pas de nom.
        #expect(names(state, a, 2) == ["Un", "Trois", "Com", "Quatre"])
        let moved = state.scopes.first { $0.desktopID == d(2) }?.stages.first { $0.name == "Com" }
        #expect(moved?.members.map(\.windowID) == [WindowID(rawValue: 5)])
        #expect(state.windowPins.first?.homeScope == StageScope(displayID: a, desktopID: d(2), stageID: moved?.id ?? s("?")))
        #expect(state.scopes.first { $0.desktopID == d(2) }?.activeStageID == s("1"))

        // Même bureau : réordonnancement seul, puis dépôt sans effet à sa propre place.
        #expect(commands.moveStage(s("4"), displayID: a, from: d(2), to: d(2), before: s("1")).changed)
        #expect(names(store.state(), a, 2) == ["Quatre", "Un", "Trois", "Com"])
        #expect(commands.moveStage(s("4"), displayID: a, from: d(2), to: d(2), before: s("1")).outcome == .noOp)
    }
}
