import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

/// Session 022, lot D : REL-001 (arguments stage invalides), PERF-005 (ordre inchangé), REL-023 (--no-follow).
@Suite
struct Audit022LotDTests {
    // MARK: REL-001

    @Test
    func reorderStageClampsExtremePositionsWithoutTrap() {
        func order(after position: Int) -> [String] {
            var scope = PersistentStageScope(
                displayID: DisplayID(rawValue: "display-main"),
                activeStageID: StageID(rawValue: "1"),
                stages: ["1", "2", "3"].map { PersistentStage(id: StageID(rawValue: $0)) }
            )
            let reordered = scope.reorderStage(StageID(rawValue: "2"), to: position)
            #expect(reordered)
            return scope.stages.map(\.id.rawValue)
        }

        #expect(order(after: Int.min) == ["2", "1", "3"])
        #expect(order(after: -5) == ["2", "1", "3"])
        #expect(order(after: 0) == ["2", "1", "3"])
        #expect(order(after: 1) == ["2", "1", "3"])
        #expect(order(after: 2) == ["1", "2", "3"])
        #expect(order(after: 3) == ["1", "3", "2"])
        #expect(order(after: Int.max) == ["1", "3", "2"])
    }

    @Test
    func stageCommandsRefuseEmptyStageIDAndExtremePosition() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let window = powerWindow(1, x: 100)
        let provider = PowerUserProvider(displays: [main], windows: [window])
        let writer = PowerUserWriter(provider: provider)
        let store = lotDStageStore("audit022-d-empty-id", scopes: [
            lotDScope(main.id, active: "1", stages: [lotDStage("1", window), lotDStage("2")])
        ], activeDisplayID: main.id)
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store)
        let commands = StageCommandService(service: service, store: store, config: RoadieConfig())

        let results = [
            commands.create(""),
            commands.rename("", to: "x"),
            commands.reorder("", to: 1),
            commands.delete(""),
            commands.switchTo(""),
            commands.switchTo("", displayID: main.id),
            commands.assign("")
        ]
        for result in results {
            #expect(!result.changed)
            #expect(result.message.contains("nonempty stage id"))
        }

        let extreme = commands.reorder("2", to: Int.min)
        #expect(extreme.changed)
        var state = store.state()
        #expect(state.scope(displayID: main.id).stages.map(\.id.rawValue) == ["2", "1"])
    }

    // MARK: PERF-005

    @Test
    func assignPositionKeepsVisibleThenEmptyOrderAndSkipsParked() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let first = powerWindow(1, x: 100)
        let other = powerWindow(2, x: 500)
        func run(position: Int, name: String) -> (message: String, owner: String?) {
            let provider = PowerUserProvider(displays: [main], windows: [first, other])
            let writer = PowerUserWriter(provider: provider)
            let store = lotDStageStore(name, scopes: [
                lotDScope(main.id, active: "1", stages: [
                    lotDStage("1", first),
                    lotDStage("2"),
                    lotDStage("3", other),
                    PersistentStage(id: StageID(rawValue: "4"), parkingState: .parked),
                    lotDStage("5")
                ])
            ], activeDisplayID: main.id)
            let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store)
            let result = StageCommandService(service: service, store: store, config: RoadieConfig())
                .assignPosition(position)
            var state = store.state()
            let owner = state.scope(displayID: main.id).stages.first { $0.members.contains { $0.windowID == first.id } }?.id.rawValue
            return (result.message, owner)
        }

        // Ordre attendu : visibles (1, 3), puis vides (2, 5) ; la stage parkée vide (4) est ignorée.
        #expect(run(position: 2, name: "audit022-d-pos2").owner == "3")
        #expect(run(position: 3, name: "audit022-d-pos3").owner == "2")
        #expect(run(position: 4, name: "audit022-d-pos4").owner == "5")
        let missing = run(position: 5, name: "audit022-d-pos5")
        #expect(missing.message.contains("not found"))
        #expect(missing.owner == "1")
    }

    // MARK: REL-023

    @Test
    func noFollowMoveKeepsMovedStageHiddenThenRestoresItOnTargetDisplay() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let side = powerDisplay("display-side", index: 2, x: 1000)
        let moved = powerWindow(1, x: 100)
        let targetResident = powerWindow(2, x: 1100)
        let provider = PowerUserProvider(displays: [main, side], windows: [moved, targetResident])
        let writer = PowerUserWriter(provider: provider)
        let store = lotDStageStore("audit022-d-no-follow", scopes: [
            lotDScope(main.id, active: "1", stages: [lotDStage("1", moved)]),
            lotDScope(side.id, active: "9", stages: [lotDStage("9", targetResident), lotDStage("1")])
        ], activeDisplayID: main.id)
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store)
        let commands = StageCommandService(service: service, store: store, config: RoadieConfig())

        let result = commands.moveActiveStageToDisplay(index: 2, followFocus: false)

        #expect(result.changed)
        // Stage inactive sur l'écran cible : fenêtre envoyée au point de masquage (bord droit), pas au centre.
        let hiddenFrame = provider.snapshots.first { $0.id == moved.id }?.frame.cgRect
        #expect(hiddenFrame.map { HiddenWindowPlacementProbe.isAtHiddenEdge($0, displays: [main, side]) } == true)
        // Frame de retour mémorisée : centrée sur l'écran cible.
        var state = store.state()
        let stored = state.scope(displayID: side.id).stages.first { $0.id == StageID(rawValue: "1") }?.members.first?.frame.cgRect
        #expect(stored == CGRect(x: 1350, y: 250, width: 300, height: 300))

        // L'activation de la stage la rend visible sur l'écran cible.
        _ = commands.switchTo("1", displayID: side.id)
        let restored = provider.snapshots.first { $0.id == moved.id }?.frame.cgRect
        #expect(restored.map { side.visibleFrame.cgRect.contains($0) } == true)
    }

    @Test
    func followMoveStillShowsMovedStageCenteredOnTargetDisplay() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let side = powerDisplay("display-side", index: 2, x: 1000)
        let moved = powerWindow(1, x: 100)
        let provider = PowerUserProvider(displays: [main, side], windows: [moved])
        let writer = PowerUserWriter(provider: provider)
        let store = lotDStageStore("audit022-d-follow", scopes: [
            lotDScope(main.id, active: "1", stages: [lotDStage("1", moved)]),
            lotDScope(side.id, active: "1", stages: [lotDStage("1")])
        ], activeDisplayID: main.id)
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store)

        let result = StageCommandService(service: service, store: store, config: RoadieConfig())
            .moveActiveStageToDisplay(index: 2, followFocus: true)

        #expect(result.changed)
        let frame = provider.snapshots.first { $0.id == moved.id }?.frame.cgRect
        #expect(frame.map { side.visibleFrame.cgRect.contains($0) } == true)
    }
}

/// Le masquage place la fenêtre sur le bord droit de l'écran le plus à droite (x = maxX - 1).
private enum HiddenWindowPlacementProbe {
    static func isAtHiddenEdge(_ frame: CGRect, displays: [DisplaySnapshot]) -> Bool {
        guard let maxX = displays.map({ $0.visibleFrame.cgRect.maxX }).max() else { return false }
        return abs(frame.minX - (maxX - 1)) <= 8
    }
}

private func lotDStageStore(_ name: String, scopes: [PersistentStageScope], activeDisplayID: DisplayID) -> StageStore {
    let store = StageStore(path: tempPath(name))
    store.save(PersistentStageState(scopes: scopes, activeDisplayID: activeDisplayID))
    return store
}

private func lotDScope(_ displayID: DisplayID, active rawActiveID: String, stages: [PersistentStage]) -> PersistentStageScope {
    PersistentStageScope(displayID: displayID, activeStageID: StageID(rawValue: rawActiveID), stages: stages)
}

private func lotDStage(_ rawID: String, _ windows: WindowSnapshot...) -> PersistentStage {
    PersistentStage(
        id: StageID(rawValue: rawID),
        members: windows.map {
            PersistentStageMember(windowID: $0.id, bundleID: $0.bundleID, title: $0.title, frame: $0.frame)
        }
    )
}
