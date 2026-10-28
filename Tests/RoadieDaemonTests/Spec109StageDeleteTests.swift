import Foundation
import RoadieAX
import RoadieCore
import Testing
@testable import RoadieDaemon

/// Session 109 : supprimer depuis le rail une stage sans fenêtre, nommée ou non, sur l'écran cliqué.
@Suite
@MainActor
struct Spec109StageDeleteTests {
    private let active = DisplayID(rawValue: "display-a")
    private let clicked = DisplayID(rawValue: "display-b")
    private let live = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "vivante",
                                      frame: Rect(x: 1000, y: 0, width: 500, height: 500), isOnScreen: true, isTileCandidate: true)

    private func member(_ id: UInt32, closed: Bool = false) -> PersistentStageMember {
        PersistentStageMember(windowID: WindowID(rawValue: id), bundleID: "a", title: "f\(id)", frame: Rect(x: 0, y: 0, width: 10, height: 10),
                              confirmedClosedAt: closed ? Date() : nil)
    }

    private func fixture() -> (StageCommandService, StageStore, String) {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-109-\(UUID().uuidString).json").path
        let store = StageStore(path: path)
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: active, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1")), PersistentStage(id: StageID(rawValue: "2"), name: "Com"),
            ]),
            PersistentStageScope(displayID: clicked, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [member(1)]),
                PersistentStage(id: StageID(rawValue: "2"), name: "Com"),
                PersistentStage(id: StageID(rawValue: "7-restored-2"), name: "Stage 7", members: [member(5, closed: true), member(6)]),
                PersistentStage(id: StageID(rawValue: "3"), members: [member(1)]),
                PersistentStage(id: StageID(rawValue: "4"), parkingState: .parked),
            ]),
        ], activeDisplayID: active))
        let provider = PowerUserProvider(displays: [
                DisplaySnapshot(id: active, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500),
                                visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                DisplaySnapshot(id: clicked, index: 2, name: "B", frame: Rect(x: 1000, y: 0, width: 1000, height: 500),
                                visibleFrame: Rect(x: 1000, y: 0, width: 1000, height: 500), isMain: false),
            ], windows: [live])
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider),
                                      config: RoadieConfig(), stageStore: store)
        return (StageCommandService(service: service, store: store), store, path)
    }

    private func ids(_ store: StageStore, _ display: DisplayID) -> [String] {
        store.state().scopes.first { $0.displayID == display }?.stages.map(\.id.rawValue) ?? []
    }

    @Test func clickedDisplayLosesOnlyItsStagesWithoutWindows() {
        let (commands, store, path) = fixture()
        defer { try? FileManager.default.removeItem(atPath: path) }
        // Stage nommée vide, puis reste « Stage 7 » dont les fenêtres sont fermées ou disparues.
        #expect(commands.delete("2", displayID: clicked).changed)
        #expect(commands.delete("7-restored-2", displayID: clicked).changed)
        #expect(ids(store, clicked) == ["1", "3", "4"])
        #expect(ids(store, active) == ["1", "2"])
    }

    @Test func activeParkedAndOccupiedStagesStay() {
        let (commands, store, path) = fixture()
        defer { try? FileManager.default.removeItem(atPath: path) }
        for id in ["1", "3", "4", "absente"] {
            #expect(commands.delete(id, displayID: clicked).outcome == .failed, "\(id)")
        }
        #expect(ids(store, clicked) == ["1", "2", "7-restored-2", "3", "4"])
        // Sans écran donné, la CLI reste sur l'écran actif.
        #expect(commands.delete("2").changed)
        #expect(ids(store, active) == ["1"])
    }

    @Test func railMenuNamesTheReasonOfARefusal() {
        let (_, store, path) = fixture()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let liveIDs: Set<WindowID> = [live.id]
        let refusal = { (id: String) in
            RailController.deleteStageRefusal(stageID: StageID(rawValue: id), displayID: clicked, store: store, liveWindowIDs: liveIDs)
        }
        #expect(refusal("2") == nil)
        #expect(refusal("7-restored-2") == nil)
        #expect(refusal("1") == "stage active")
        #expect(refusal("3") == "contient des fenêtres")
        #expect(refusal("4") == "écran absent")
        // Une fenêtre absente depuis peu reste affichée pendant la grâce du rail : la stage n'est pas vide.
        var recent = member(9)
        recent.lastSeenAt = Date().addingTimeInterval(-2)
        recent.missingSince = Date().addingTimeInterval(-1)
        #expect(!StageCommandService.isDeletable(PersistentStage(id: StageID(rawValue: "8"), members: [recent]),
                                                 activeStageID: StageID(rawValue: "1"), liveWindowIDs: []))
    }
}
