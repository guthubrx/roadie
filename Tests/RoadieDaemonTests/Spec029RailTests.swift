import AppKit
import Foundation
import RoadieAX
import RoadieCore
import Testing
@testable import RoadieDaemon

@Suite
@MainActor
struct Spec029RailTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func member(_ id: UInt32, missingAge: TimeInterval? = nil, now: Date) -> PersistentStageMember {
        PersistentStageMember(windowID: WindowID(rawValue: id), bundleID: "app.\(id)", title: "Window \(id)",
                              frame: Rect(x: 100, y: 100, width: 300, height: 300),
                              lastSeenAt: missingAge.map { now.addingTimeInterval(-$0 - 1) },
                              missingSince: missingAge.map { now.addingTimeInterval(-$0) })
    }

    private func scope(now: Date) -> PersistentStageScope {
        PersistentStageScope(displayID: DisplayID(rawValue: "display-main"), stages: [
            PersistentStage(id: StageID(rawValue: "1"), name: "Work", members: [member(1, now: now)]),
            PersistentStage(id: StageID(rawValue: "7"), members: [member(77, missingAge: 60, now: now)]),
            PersistentStage(id: StageID(rawValue: "9"), members: [member(2, now: now)]),
            PersistentStage(id: StageID(rawValue: "2"), name: "Perso"),
            PersistentStage(id: StageID(rawValue: "4")),
            PersistentStage(id: StageID(rawValue: "parked-old-3"), name: "Com", parkingState: .parked)
        ])
    }

    @Test
    func projectionKeepsNamedEmptyStagesAndExcludesStaleMembersWithoutReorderingIDs() {
        let persisted = scope(now: now)
        let order = StagePresentationOrder(scope: persisted, liveWindowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)], now: now)
        #expect(order.visibleStageIDs.map(\.rawValue) == ["1", "9", "2"])
        #expect(order.emptyStageIDs.map(\.rawValue) == ["4"])
        #expect(order.stageID(at: 2)?.rawValue == "9")
        #expect(order.stageID(at: 3)?.rawValue == "2")
        #expect(order.stageID(at: 4) == nil)
        #expect(order.stageID(at: 4, allowingEmptySlots: true)?.rawValue == "4")
        #expect(order.stageID(at: 0) == nil)
        #expect(persisted.stages.map(\.id.rawValue) == ["1", "7", "9", "2", "4", "parked-old-3"])
        #expect(persisted.stages[3].name == "Perso")
        #expect(persisted.stages[1].members.map(\.windowID.rawValue) == [77])
    }

    @Test
    func gracePeriodIsSharedByCardsAndPositionSelection() {
        var persisted = scope(now: now)
        persisted.stages.insert(PersistentStage(id: StageID(rawValue: "8"), members: [member(88, missingAge: 14, now: now)]), at: 1)
        let live: Set<WindowID> = [WindowID(rawValue: 1), WindowID(rawValue: 2)]
        let order = StagePresentationOrder(scope: persisted, liveWindowIDs: live, now: now)
        #expect(order.visibleStageIDs.map(\.rawValue) == ["1", "8", "9", "2"])
        #expect(order.stageID(at: 2)?.rawValue == "8")
        #expect(RailController.railVisibleStageIDs(in: persisted, liveWindowIDs: live, now: now) == order.visibleStageIDs)
        let expired = StagePresentationOrder(scope: persisted, liveWindowIDs: live, now: now.addingTimeInterval(2))
        #expect(expired.visibleStageIDs.map(\.rawValue) == ["1", "9", "2"])
        #expect(!expired.emptyStageIDs.contains(StageID(rawValue: "8")))
    }

    @Test
    func namedStageSurvivesItsLastMissingMemberAndLaterPruning() throws {
        var persisted = scope(now: now)
        persisted.stages[3].members = [member(22, missingAge: 120, now: now)]
        let live: Set<WindowID> = [WindowID(rawValue: 1), WindowID(rawValue: 2)]
        let missing = StagePresentationOrder(scope: persisted, liveWindowIDs: live, now: now)
        #expect(missing.visibleStageIDs.map(\.rawValue) == ["1", "9", "2"])
        #expect(missing.visibleStages.last?.members.isEmpty == true)
        #expect(missing.stageID(at: 3)?.rawValue == "2")
        #expect(!missing.emptyStageIDs.contains(StageID(rawValue: "2")))
        persisted.stages[3].members = []
        let pruned = StagePresentationOrder(scope: persisted, liveWindowIDs: live, now: now)
        #expect(pruned.visibleStageIDs == missing.visibleStageIDs)
        try #require(pruned.visibleStages.count == 3)
        #expect(StagePresentationOrder.menuLabel(pruned.visibleStages[2], position: 3) == "3 · Perso")
    }

    @Test
    func reorderingPreservesNamedStageAndUsesOneNewPositionEverywhere() throws {
        var persisted = scope(now: now)
        let reordered = persisted.reorderStage(StageID(rawValue: "2"), to: 1)
        #expect(reordered)
        let order = StagePresentationOrder(scope: persisted, liveWindowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)], now: now)
        #expect(order.visibleStageIDs.map(\.rawValue) == ["2", "1", "9"])
        #expect(order.stageID(at: 1)?.rawValue == "2")
        #expect(StagePresentationOrder.menuLabel(order.visibleStages[0], position: 1) == "1 · Perso")
        #expect(StagePresentationOrder.name(order.visibleStages[0], position: 1) == "Perso")
        try #require(order.visibleStages.count == 3)
        #expect(StagePresentationOrder.menuLabel(order.visibleStages[2], position: 3) == "Stage 3")
    }

    private func fixture() -> (StageStore, SnapshotService, WindowSnapshot) {
        let windows = [powerWindow(1, x: 100), powerWindow(2, x: 700)]
        let provider = PowerUserProvider(windows: windows)
        let store = StageStore(path: tempPath("spec029-rail"))
        store.save(PersistentStageState(scopes: [scope(now: Date())], activeDisplayID: DisplayID(rawValue: "display-main")))
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), config: RoadieConfig(), stageStore: store)
        return (store, service, windows[0])
    }

    @Test(arguments: [false, true])
    func switchAndAssignUseTheSameNamedEmptyPosition(assign: Bool) {
        let (store, service, moved) = fixture()
        defer { try? FileManager.default.removeItem(at: store.fileURL) }
        let command = StageCommandService(service: service, store: store, config: RoadieConfig())
        let result = assign ? command.assignPosition(3) : command.switchToPosition(3)
        #expect(result.changed)
        let persisted = store.state().scopes.first { $0.displayID.rawValue == "display-main" }!
        #expect(persisted.activeStageID.rawValue == "2")
        #expect(persisted.stages.first { $0.id.rawValue == "2" }?.name == "Perso")
        if assign { #expect(store.state().stageScope(for: moved.id)?.stageID.rawValue == "2") }
    }

    @Test
    func assigningSecondPositionSkipsStaleNonemptyStage() {
        let (store, service, moved) = fixture()
        defer { try? FileManager.default.removeItem(at: store.fileURL) }
        #expect(StageCommandService(service: service, store: store).assignPosition(2).changed)
        #expect(store.state().stageScope(for: moved.id)?.stageID.rawValue == "9")
        #expect(store.state().scopes.first?.stages.first { $0.id.rawValue == "7" }?.members.map(\.windowID.rawValue) == [77])
    }

    @Test
    func switchVisibleSkipsNamedEmptyCardsButPositionStillTargetsThem() {
        let (store, service, _) = fixture()
        defer { try? FileManager.default.removeItem(at: store.fileURL) }
        let command = StageCommandService(service: service, store: store, config: RoadieConfig())
        #expect(command.switchVisible(.next).changed)
        #expect(store.state().scopes.first?.activeStageID.rawValue == "9")
        #expect(command.switchVisible(.next).changed)
        #expect(store.state().scopes.first?.activeStageID.rawValue == "1")
        #expect(command.switchToPosition(3).changed)
        #expect(store.state().scopes.first?.activeStageID.rawValue == "2")
        #expect(store.state().scopes.first?.stages.first { $0.id.rawValue == "2" }?.members.isEmpty == true)
    }

    @Test
    func explicitIdentifierStillTargetsThatIdentifierInsteadOfItsVisiblePosition() {
        let (store, service, moved) = fixture()
        defer { try? FileManager.default.removeItem(at: store.fileURL) }
        #expect(StageCommandService(service: service, store: store).assign("7").changed)
        #expect(store.state().stageScope(for: moved.id)?.stageID.rawValue == "7")
        #expect(store.state().scopes.first?.stages.first { $0.id.rawValue == "7" }?.members.map(\.windowID.rawValue).contains(77) == true)
    }

    @Test
    func assignEmptyReusesAnAutomaticStageWhoseIdentifierWasRemapped() throws {
        let (store, service, moved) = fixture()
        defer { try? FileManager.default.removeItem(at: store.fileURL) }
        let sourceDisplay = DisplayID(rawValue: "removed-display")
        let origin = StageOrigin(logicalDisplayID: LogicalDisplayID(displayID: sourceDisplay), displayID: sourceDisplay,
                                 desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "5"), position: 2,
                                 nameAtParking: "Stage 5", parkedAt: Date())
        let restored = PersistentStage(id: StageID(rawValue: "5-restored-2"), name: "Stage 5", parkingState: .restored, origin: origin)
        try store.mutateChecked { state in
            state.scopes[0].stages = [state.scopes[0].stages[0], restored]
        }
        #expect(!StagePresentationOrder.isNamed(restored))
        #expect(StageCommandService(service: service, store: store).assignEmpty().changed)
        #expect(store.state().stageScope(for: moved.id)?.stageID == restored.id)
        #expect(store.state().scopes.first?.stages.first { $0.id == restored.id }?.name == "Stage 5")
    }

    @Test
    func emptyRailDropReservesIdentifiersOfAbsentPersistentMembers() throws {
        let (store, service, moved) = fixture()
        defer { try? FileManager.default.removeItem(at: store.fileURL) }
        let stale = PersistentStage(id: StageID(rawValue: "2"), members: [member(77, missingAge: 60, now: Date())])
        try store.mutateChecked { state in
            state.scopes[0].stages = [state.scopes[0].stages[0], stale, PersistentStage(id: StageID(rawValue: "3"), name: "Perso")]
        }
        let persisted = try #require(store.state().scopes.first)
        let live: Set<WindowID> = [moved.id, WindowID(rawValue: 2)]
        let order = StagePresentationOrder(scope: persisted, liveWindowIDs: live)
        #expect(order.visibleStageIDs.map(\.rawValue) == ["1", "3"])
        #expect(order.emptyStageIDs.isEmpty)
        let target = RailPanel.nextGeneratedStageID(in: persisted.stages.map(\.id))
        #expect(target.rawValue == "4")
        #expect(StageCommandService(service: service, store: store)
            .assign(windowID: moved.id, to: target.rawValue, displayID: persisted.displayID).changed)
        #expect(store.state().stageScope(for: moved.id)?.stageID == target)
        #expect(store.state().stageScope(for: WindowID(rawValue: 77))?.stageID == stale.id)
    }

    @Test
    func menusAgreeWithCardsAndIgnoreTheFadeState() throws {
        let (store, service, moved) = fixture()
        defer { try? FileManager.default.removeItem(at: store.fileURL) }
        let snapshot = service.snapshot(followFocus: false)
        let persisted = try #require(store.state().scopes.first { $0.displayID.rawValue == "display-main" })
        let live = Set(snapshot.windows.compactMap { $0.window.isTileCandidate ? $0.window.id : nil })
        let cards = RailDisplayContent(scope: persisted, presentationStates: [:], liveWindowIDs: live)
        let order = StagePresentationOrder(scope: persisted, liveWindowIDs: live)
        let faded = WindowContextActions(snapshotService: service, stageStore: store, stageLabelsVisible: { false })
            .destinations(for: moved.id, in: snapshot, settings: TitlebarContextMenuSettings(enabled: true))
        let shown = WindowContextActions(snapshotService: service, stageStore: store, stageLabelsVisible: { true })
            .destinations(for: moved.id, in: snapshot, settings: TitlebarContextMenuSettings(enabled: true))
        #expect(faded == shown)
        let stageDestinations = faded.filter { $0.kind == .stage && $0.label != "Prochaine stage vide" }
        #expect(stageDestinations.map(\.id) == cards.stages.map(\.id.rawValue))
        #expect(stageDestinations.map(\.label) == order.visibleStages.enumerated().map { StagePresentationOrder.menuLabel($0.element, position: $0.offset + 1) })
        #expect(stageDestinations.map(\.label) == ["1 · Work", "Stage 2", "3 · Perso"])
        #expect(faded.contains { $0.kind == .desktopStage && $0.id == "1:2" && $0.label == "3 · Perso" })
    }

}
