import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

@Suite
struct Spec029StageMoveIdentityTests {
    private let source = powerDisplay("identity-source", index: 1, x: 0)
    private let target = powerDisplay("identity-target", index: 2, x: 1000)
    private let window = powerWindow(7021, x: 100)

    private func movedState(stage: PersistentStage, targetStages: [PersistentStage]) throws -> PersistentStageState {
        let store = StageStore(path: tempPath("spec029-stage-move-identity"))
        defer { try? FileManager.default.removeItem(at: store.fileURL) }
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: source.id, activeStageID: stage.id, stages: [stage]),
            PersistentStageScope(displayID: target.id, activeStageID: targetStages[0].id, stages: targetStages),
        ], activeDisplayID: source.id))
        let provider = PowerUserProvider(displays: [source, target], windows: [window])
        let snapshots = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider),
                                         config: RoadieConfig(), stageStore: store)
        let result = StageCommandService(service: snapshots, store: store, config: RoadieConfig())
            .moveStageToDisplay(stageID: stage.id, sourceDisplayID: source.id, targetDisplayID: target.id,
                                followFocus: true)
        #expect(result.changed)
        return store.state()
    }

    private func movingStage(id: String = "2") -> PersistentStage {
        PersistentStage(id: StageID(rawValue: id), name: "Stage 2", members: [
            PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
        ])
    }

    @Test
    func collisionKeepsAnAutomaticNameAutomaticAfterItsIdentifierChanges() throws {
        let occupied = PersistentStage(id: StageID(rawValue: "2"), members: [
            PersistentStageMember(windowID: WindowID(rawValue: 7022), bundleID: "test", title: "Other", frame: window.frame),
        ])
        let state = try movedState(stage: movingStage(), targetStages: [
            PersistentStage(id: StageID(rawValue: "1")), occupied, PersistentStage(id: StageID(rawValue: "3")),
        ])
        var moved = try #require(state.scopes.first { $0.displayID == target.id }?.stages.first { $0.members.contains { $0.windowID == window.id } })
        #expect(moved.id.rawValue == "4")
        #expect(!StagePresentationOrder.isNamed(moved))
        moved.members = []
        let scope = PersistentStageScope(displayID: target.id, stages: [moved])
        #expect(StagePresentationOrder(scope: scope, liveWindowIDs: []).visibleStageIDs.isEmpty)
    }

    @Test
    func detachedRestoredIdentifierDoesNotTurnItsAutomaticNameIntoAPersonalName() throws {
        var stage = movingStage(id: "2-restored-2")
        stage.parkingState = .restored
        stage.origin = StageOrigin(logicalDisplayID: LogicalDisplayID(displayID: source.id), displayID: source.id,
                                   desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "2"), position: 2,
                                   nameAtParking: "Stage 2", parkedAt: Date(timeIntervalSince1970: 100))
        #expect(!StagePresentationOrder.isNamed(stage))
        let state = try movedState(stage: stage, targetStages: [PersistentStage(id: StageID(rawValue: "1"))])
        let moved = try #require(state.scopes.first { $0.displayID == target.id }?.stages.first { $0.id == stage.id })
        #expect(moved.origin == nil)
        #expect(!StagePresentationOrder.isNamed(moved))
    }

    @Test
    func anEmptyNamedDestinationSurvivesTheWholeStageTransfer() throws {
        let personal = PersistentStage(id: StageID(rawValue: "2"), name: "Personal destination", mode: .float)
        let state = try movedState(stage: movingStage(), targetStages: [
            PersistentStage(id: StageID(rawValue: "1")), personal,
        ])
        let scope = try #require(state.scopes.first { $0.displayID == target.id })
        #expect(scope.stages.first { $0.id == personal.id } == personal)
        #expect(scope.stages.contains { $0.id != personal.id && $0.members.contains { $0.windowID == window.id } })
    }

    @Test
    func aPersonalMovingNameSurvivesTheSameCollision() throws {
        var stage = movingStage()
        stage.name = "My workspace"
        let occupied = PersistentStage(id: StageID(rawValue: "2"), members: [
            PersistentStageMember(windowID: WindowID(rawValue: 7022), bundleID: "test", title: "Other", frame: window.frame),
        ])
        let state = try movedState(stage: stage, targetStages: [PersistentStage(id: StageID(rawValue: "1")), occupied])
        let moved = try #require(state.scopes.first { $0.displayID == target.id }?.stages.first { $0.members.contains { $0.windowID == window.id } })
        #expect(moved.id != stage.id)
        #expect(moved.name == "My workspace")
    }
}
