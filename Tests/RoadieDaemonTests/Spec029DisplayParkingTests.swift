import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

@Suite
struct Spec029DisplayParkingTests {
    private let service = DisplayParkingService()
    private let hostID = DisplayID(rawValue: "host")
    private let originID = DisplayID(rawValue: "external")

    private func display(_ id: DisplayID, main: Bool = false) -> DisplaySnapshot {
        let frame = Rect(x: main ? 0 : 1920, y: 0, width: 1920, height: 1080)
        return DisplaySnapshot(id: id, index: main ? 0 : 1, name: id.rawValue,
                               frame: frame, visibleFrame: frame, isMain: main)
    }

    private func member(_ value: UInt32) -> PersistentStageMember {
        PersistentStageMember(windowID: WindowID(rawValue: value), bundleID: "com.test",
                              title: "Fixture", frame: Rect(x: 0, y: 0, width: 100, height: 100))
    }

    private func fixture() -> PersistentStageState {
        PersistentStageState(scopes: [
            PersistentStageScope(displayID: hostID, activeStageID: StageID(rawValue: "host"), stages: [
                PersistentStage(id: StageID(rawValue: "host"), name: "Host"),
            ]),
            PersistentStageScope(displayID: originID, activeStageID: StageID(rawValue: "A"), stages: [
                PersistentStage(id: StageID(rawValue: "A"), name: "Alpha", focusedWindowID: WindowID(rawValue: 11),
                                previousFocusedWindowID: WindowID(rawValue: 12), members: [member(11), member(12)]),
                PersistentStage(id: StageID(rawValue: "B"), name: "Empty"),
                PersistentStage(id: StageID(rawValue: "C"), name: "Charlie", members: [member(33)]),
            ]),
        ], activeDisplayID: hostID)
    }

    private func park(_ state: inout PersistentStageState) {
        _ = service.transition(state: &state, liveDisplays: [display(hostID, main: true)], windows: [],
                               now: Date(timeIntervalSince1970: 100))
    }

    private func restore(_ state: inout PersistentStageState) {
        _ = service.transition(state: &state,
                               liveDisplays: [display(hostID, main: true), display(originID)], windows: [],
                               now: Date(timeIntervalSince1970: 110))
    }

    @Test
    func roundTripKeepsEmptyStagesOrderActiveStageAndFocus() throws {
        var state = fixture()
        park(&state)
        // A regular tick used to remove the source placeholders before reconnection.
        _ = service.transition(state: &state, liveDisplays: [display(hostID, main: true)], windows: [],
                               now: Date(timeIntervalSince1970: 101))
        restore(&state)
        let restored = try #require(state.scopes.first { $0.displayID == originID })
        #expect(restored.stages.map(\.id.rawValue) == ["A", "B", "C"])
        #expect(restored.activeStageID.rawValue == "A")
        #expect(restored.stages[0].focusedWindowID == WindowID(rawValue: 11))
        #expect(restored.stages[0].previousFocusedWindowID == WindowID(rawValue: 12))
        #expect(restored.stages[0].members.map(\.windowID.rawValue) == [11, 12])
        #expect(state.scopes.first { $0.displayID == hostID }?.stages.map(\.id.rawValue) == ["host"])
    }

    @Test
    func sourceReorderDuringParkingIsNotOverwritten() throws {
        var state = fixture()
        park(&state)
        let index = try #require(state.scopes.firstIndex { $0.displayID == originID })
        let reordered = state.scopes[index].reorderStage(StageID(rawValue: "C"), to: 1)
        #expect(reordered)
        state.scopes[index].activeStageID = StageID(rawValue: "B")
        restore(&state)
        let restored = try #require(state.scopes.first { $0.displayID == originID })
        #expect(restored.stages.map(\.id.rawValue) == ["C", "A", "B"])
        #expect(restored.activeStageID.rawValue == "B")
    }

    @Test
    func legacyStateWithoutSourcePlaceholdersUsesRecordedPositions() throws {
        var state = fixture()
        park(&state)
        let scopeIndex = try #require(state.scopes.firstIndex { $0.displayID == originID })
        state.scopes[scopeIndex].stages.removeAll { $0.parkingState == .parked }
        restore(&state)
        let restored = try #require(state.scopes.first { $0.displayID == originID })
        #expect(restored.stages.map(\.id.rawValue) == ["A", "B", "C"])
        #expect(restored.stages.flatMap(\.members).map(\.windowID.rawValue) == [11, 12, 33])
    }

    @Test
    func editedSourcePlaceholderIsPreservedInsteadOfDeleted() throws {
        var state = fixture()
        park(&state)
        let index = try #require(state.scopes.firstIndex { $0.displayID == originID })
        let stageIndex = try #require(state.scopes[index].stages.firstIndex { $0.id.rawValue == "A" })
        state.scopes[index].stages[stageIndex].name = "Reserved by user"
        state.scopes[index].stages[stageIndex].mode = .float
        let hostIndex = try #require(state.scopes.firstIndex { $0.displayID == hostID })
        let copyIndex = try #require(state.scopes[hostIndex].stages.firstIndex { $0.origin?.stageID.rawValue == "A" })
        state.scopes[hostIndex].stages[copyIndex].name = "Current parked copy"
        state.scopes[hostIndex].stages[copyIndex].mode = .masterStack
        restore(&state)
        let restored = try #require(state.scopes.first { $0.displayID == originID })
        let reserved = try #require(restored.stages.first { $0.id.rawValue == "A" })
        #expect(reserved.name == "Reserved by user")
        #expect(reserved.mode == .float)
        #expect(reserved.members.isEmpty)
        #expect(restored.stages.contains { $0.name == "Current parked copy" && $0.mode == .masterStack && $0.members.map(\.windowID.rawValue) == [11, 12] })
        #expect(Set(restored.stages.map(\.id)).count == restored.stages.count)
    }

    @Test
    func editedSourceModeAloneIsPreserved() throws {
        var state = fixture()
        park(&state)
        let index = try #require(state.scopes.firstIndex { $0.displayID == originID })
        let stageIndex = try #require(state.scopes[index].stages.firstIndex { $0.id.rawValue == "A" })
        state.scopes[index].stages[stageIndex].mode = .float
        restore(&state)
        let restored = try #require(state.scopes.first { $0.displayID == originID })
        #expect(restored.stages.first { $0.id.rawValue == "A" }?.mode == .float)
        #expect(restored.stages.first { $0.id.rawValue == "A" }?.members.isEmpty == true)
        #expect(restored.stages.contains { $0.mode == .bsp && $0.members.map(\.windowID.rawValue) == [11, 12] })
    }

    @Test
    func materializationReusesAnEmptyHostSlotInPlace() throws {
        var state = fixture()
        let hostIndex = try #require(state.scopes.firstIndex { $0.displayID == hostID })
        state.scopes[hostIndex].stages.append(PersistentStage(id: StageID(rawValue: "A"), name: "Alpha"))
        state.scopes[hostIndex].stages.append(PersistentStage(id: StageID(rawValue: "later"), name: "Later"))
        park(&state)
        _ = service.transition(state: &state, liveDisplays: [display(hostID, main: true)], windows: [],
                               now: Date(timeIntervalSince1970: 161))
        let host = try #require(state.scopes.first { $0.displayID == hostID })
        #expect(host.stages.map(\.id.rawValue) == ["host", "A", "later", "C"])
        #expect(host.stages[1].members.map(\.windowID.rawValue) == [11, 12])
    }

    @Test
    func reportNamesTheOriginThatActuallyParkedStages() {
        var state = fixture()
        state.scopes.insert(PersistentStageScope(displayID: DisplayID(rawValue: "empty-disconnected")), at: 1)
        let report = service.transition(state: &state, liveDisplays: [display(hostID, main: true)], windows: [],
                                        now: Date(timeIntervalSince1970: 100))
        #expect(report.originDisplayID == originID)
        #expect(report.originLogicalDisplayID == LogicalDisplayID(displayID: originID))
        #expect(report.parkedStageCount == 2)
    }

    @Test
    func reconnectionAfterMaterializationRestoresOrderAndCurrentHostEdits() throws {
        var state = fixture()
        park(&state)
        _ = service.transition(state: &state, liveDisplays: [display(hostID, main: true)], windows: [],
                               now: Date(timeIntervalSince1970: 161))
        let hostIndex = try #require(state.scopes.firstIndex { $0.displayID == hostID })
        let materializedIndex = try #require(state.scopes[hostIndex].stages.firstIndex { $0.id.rawValue == "A" })
        state.scopes[hostIndex].stages[materializedIndex].name = "Edited overnight"
        state.scopes[hostIndex].stages[materializedIndex].mode = .masterStack
        state.scopes[hostIndex].stages[materializedIndex].members.append(member(99))
        let report = service.transition(state: &state,
                                        liveDisplays: [display(hostID, main: true), display(originID)], windows: [],
                                        now: Date(timeIntervalSince1970: 43_200))
        let restored = try #require(state.scopes.first { $0.displayID == originID })
        #expect(report.kind == .restore)
        #expect(restored.stages.map(\.id.rawValue) == ["A", "B", "C"])
        #expect(restored.stages[0].name == "Edited overnight")
        #expect(restored.stages[0].mode == .masterStack)
        #expect(restored.stages[0].members.map(\.windowID.rawValue) == [11, 12, 99])
        #expect(state.scopes.first { $0.displayID == hostID }?.stages.map(\.id.rawValue) == ["host"])
        let second = service.transition(state: &state,
                                        liveDisplays: [display(hostID, main: true), display(originID)], windows: [],
                                        now: Date(timeIntervalSince1970: 43_201))
        #expect(second.kind == .noop)
    }

    @Test
    func detachedMaterializedStageStaysOnHostWhenDisplayReturns() throws {
        var state = fixture()
        park(&state)
        _ = service.transition(state: &state, liveDisplays: [display(hostID, main: true)], windows: [],
                               now: Date(timeIntervalSince1970: 161))
        let hostIndex = try #require(state.scopes.firstIndex { $0.displayID == hostID })
        let stageIndex = try #require(state.scopes[hostIndex].stages.firstIndex { $0.id.rawValue == "A" })
        state.scopes[hostIndex].stages[stageIndex].origin = nil
        restore(&state)
        #expect(state.scopes.first { $0.displayID == hostID }?.stages.first { $0.id.rawValue == "A" }?.members.map(\.windowID.rawValue) == [11, 12])
        #expect(state.scopes.first { $0.displayID == originID }?.stages.flatMap(\.members).contains { $0.windowID.rawValue == 11 } == false)
    }

    @Test
    func explicitlyNativeMaterializedStageKeepsItsOriginWithoutReturning() throws {
        var state = fixture()
        park(&state)
        _ = service.transition(state: &state, liveDisplays: [display(hostID, main: true)], windows: [],
                               now: Date(timeIntervalSince1970: 161))
        let hostIndex = try #require(state.scopes.firstIndex { $0.displayID == hostID })
        let stageIndex = try #require(state.scopes[hostIndex].stages.firstIndex { $0.id.rawValue == "A" })
        state.scopes[hostIndex].stages[stageIndex].parkingState = .native
        restore(&state)
        #expect(state.scopes.first { $0.displayID == hostID }?.stages.first { $0.id.rawValue == "A" }?.members.map(\.windowID.rawValue) == [11, 12])
        #expect(state.scopes.first { $0.displayID == originID }?.stages.flatMap(\.members).contains { $0.windowID.rawValue == 11 } == false)
    }

    @Test
    func parkedCopyRenameAndModeOverrideOnlyItsUnchangedSourcePlaceholder() throws {
        var state = fixture()
        park(&state)
        let hostIndex = try #require(state.scopes.firstIndex { $0.displayID == hostID })
        let stageIndex = try #require(state.scopes[hostIndex].stages.firstIndex { $0.origin?.stageID.rawValue == "A" })
        state.scopes[hostIndex].stages[stageIndex].name = "Current parked name"
        state.scopes[hostIndex].stages[stageIndex].mode = .float
        restore(&state)
        let restored = try #require(state.scopes.first { $0.displayID == originID })
        #expect(restored.stages.map(\.id.rawValue) == ["A", "B", "C"])
        #expect(restored.stages[0].name == "Current parked name")
        #expect(restored.stages[0].mode == .float)
    }

    @Test
    func sourcePlaceholderWithNewMembersRemainsDistinctFromItsParkedCopy() throws {
        var state = fixture()
        park(&state)
        let scopeIndex = try #require(state.scopes.firstIndex { $0.displayID == originID })
        let stageIndex = try #require(state.scopes[scopeIndex].stages.firstIndex { $0.id.rawValue == "A" })
        state.scopes[scopeIndex].stages[stageIndex].members = [member(77)]
        restore(&state)
        let restored = try #require(state.scopes.first { $0.displayID == originID })
        #expect(restored.stages.first { $0.id.rawValue == "A" }?.members.map(\.windowID.rawValue) == [77])
        #expect(restored.stages.contains { $0.members.map(\.windowID.rawValue) == [11, 12] })
        #expect(restored.stages.flatMap(\.members).map(\.windowID.rawValue).sorted() == [11, 12, 33, 77])
    }

    @Test
    func materializationPreservesHostPlaceholderCustomNameAndMode() throws {
        var state = fixture()
        let hostIndex = try #require(state.scopes.firstIndex { $0.displayID == hostID })
        state.scopes[hostIndex].stages.append(PersistentStage(id: StageID(rawValue: "A"), name: "My host stage", mode: .float))
        state.scopes[hostIndex].stages.append(PersistentStage(id: StageID(rawValue: "later"), name: "Later"))
        park(&state)
        _ = service.transition(state: &state, liveDisplays: [display(hostID, main: true)], windows: [],
                               now: Date(timeIntervalSince1970: 161))
        let host = try #require(state.scopes.first { $0.displayID == hostID })
        #expect(host.stages.prefix(3).map(\.id.rawValue) == ["host", "A", "later"])
        #expect(host.stages[1].name == "My host stage")
        #expect(host.stages[1].mode == .float)
        #expect(host.stages[1].members.isEmpty)
        #expect(host.stages.contains { $0.id != StageID(rawValue: "A") && $0.members.map(\.windowID.rawValue) == [11, 12] })
    }

    @Test
    func originalScopeOrderSurvivesAChangedPhysicalDisplayID() throws {
        var state = fixture()
        let scopeIndex = try #require(state.scopes.firstIndex { $0.displayID == originID })
        state.scopes[scopeIndex].lastKnownDisplayFingerprint = DisplayFingerprint(display: display(originID))
        park(&state)
        let originalDisplay = display(originID)
        let newID = DisplayID(rawValue: "external-new-id")
        let replacement = DisplaySnapshot(id: newID, index: originalDisplay.index, name: originalDisplay.name,
                                          frame: originalDisplay.frame, visibleFrame: originalDisplay.visibleFrame,
                                          isMain: false)
        _ = service.transition(state: &state, liveDisplays: [display(hostID, main: true), replacement], windows: [],
                               now: Date(timeIntervalSince1970: 110))
        let restored = try #require(state.scopes.first { $0.displayID == newID })
        #expect(restored.stages.map(\.id.rawValue) == ["A", "B", "C"])
        #expect(restored.activeStageID.rawValue == "A")
        #expect(state.scopes.contains { $0.displayID == originID } == false)
    }

    @Test
    func legacyOriginDecodesWithoutOptionalModeAndNewModeRoundTrips() throws {
        let origin = StageOrigin(logicalDisplayID: LogicalDisplayID(displayID: originID), displayID: originID,
                                 desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "A"), position: 1,
                                 nameAtParking: "Alpha", parkedAt: Date(timeIntervalSince1970: 100))
        let data = try JSONEncoder().encode(origin)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["modeAtParking"] == nil)
        let legacy = try JSONDecoder().decode(StageOrigin.self, from: data)
        #expect(legacy == origin)
        #expect(legacy.modeAtParking == nil)
        var updated = legacy
        updated.modeAtParking = .float
        let decoded = try JSONDecoder().decode(StageOrigin.self, from: JSONEncoder().encode(updated))
        #expect(decoded == updated)
    }
}

@Suite
struct Spec029ParkingTransferRegressionTests {
    private let host = powerDisplay("parking-host", index: 1, x: 0)
    private let origin = powerDisplay("parking-origin", index: 2, x: 1000)
    private let other = powerDisplay("parking-other", index: 3, x: 2000)
    private let window = powerWindow(7011, x: 1100)
    private let service = DisplayParkingService()

    private func fixture() -> PersistentStageState {
        PersistentStageState(scopes: [
            PersistentStageScope(displayID: host.id, activeStageID: StageID(rawValue: "host"), stages: [
                PersistentStage(id: StageID(rawValue: "host"), name: "Host"),
            ]),
            PersistentStageScope(displayID: origin.id, activeStageID: StageID(rawValue: "A"), stages: [
                PersistentStage(id: StageID(rawValue: "A"), name: "Alpha", members: [
                    PersistentStageMember(windowID: window.id, bundleID: window.bundleID,
                                          title: window.title, frame: window.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "B"), name: "Empty"),
            ]),
            PersistentStageScope(displayID: other.id, activeStageID: StageID(rawValue: "other"), stages: [
                PersistentStage(id: StageID(rawValue: "other"), name: "Other"),
            ]),
        ], activeDisplayID: host.id)
    }

    private func park(_ state: inout PersistentStageState) {
        _ = service.transition(state: &state, liveDisplays: [host, other], windows: [],
                               now: Date(timeIntervalSince1970: 100))
    }

    @Test
    func explicitDisplayMoveAfterACompletedReturnSurvivesTheNextTransition() throws {
        var state = fixture()
        park(&state)
        _ = service.transition(state: &state, liveDisplays: [host, origin, other], windows: [],
                               now: Date(timeIntervalSince1970: 110))
        let store = StageStore(path: tempPath("spec029-return-then-explicit-move"))
        store.save(state)
        let provider = PowerUserProvider(displays: [host, origin, other], windows: [window])
        let snapshotService = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider),
                                              config: RoadieConfig(), stageStore: store)
        let moved = StageCommandService(service: snapshotService, store: store, config: RoadieConfig())
            .moveStageToDisplay(stageID: StageID(rawValue: "A"), sourceDisplayID: origin.id,
                                targetDisplayID: other.id, followFocus: true)
        state = store.state()
        #expect(moved.changed)
        #expect(state.stageScope(for: window.id)?.displayID == other.id)
        let report = service.transition(state: &state, liveDisplays: [host, origin, other], windows: [],
                                        now: Date(timeIntervalSince1970: 111))
        #expect(report.kind == .noop)
        #expect(state.stageScope(for: window.id)?.displayID == other.id)
    }

    @Test
    func explicitDisplayMoveOfAMaterializedStageDetachesItsPendingReturn() throws {
        var state = fixture()
        park(&state)
        _ = service.transition(state: &state, liveDisplays: [host, other], windows: [],
                               now: Date(timeIntervalSince1970: 161))
        let store = StageStore(path: tempPath("spec029-materialized-explicit-move"))
        store.save(state)
        let provider = PowerUserProvider(displays: [host, other], windows: [window])
        let snapshotService = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider),
                                              config: RoadieConfig(), stageStore: store)
        let moved = StageCommandService(service: snapshotService, store: store, config: RoadieConfig())
            .moveStageToDisplay(stageID: StageID(rawValue: "A"), sourceDisplayID: host.id,
                                targetDisplayID: other.id, followFocus: true)
        state = store.state()
        #expect(moved.changed)
        #expect(state.stageScope(for: window.id)?.displayID == other.id)
        let report = service.transition(state: &state, liveDisplays: [host, origin, other], windows: [],
                                        now: Date(timeIntervalSince1970: 43_200))
        #expect(report.kind == .noop)
        #expect(state.stageScope(for: window.id)?.displayID == other.id)
    }

    @Test
    func legacyRestoredStageWithoutPendingPlaceholderIsNotCaptured() throws {
        var state = fixture()
        let oldOrigin = StageOrigin(logicalDisplayID: LogicalDisplayID(displayID: origin.id), displayID: origin.id,
                                    desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "A"), position: 1,
                                    nameAtParking: "Alpha", parkedAt: Date(timeIntervalSince1970: 100))
        var relocated = try #require(state.scopes.first { $0.displayID == origin.id }?.stages.first)
        relocated.parkingState = .restored
        relocated.origin = oldOrigin
        relocated.restoredAt = Date(timeIntervalSince1970: 110)
        state.scopes[1].stages.removeFirst()
        state.scopes[2].stages.append(relocated)
        state = try JSONDecoder().decode(PersistentStageState.self, from: JSONEncoder().encode(state))
        let report = service.transition(state: &state, liveDisplays: [host, origin, other], windows: [],
                                        now: Date(timeIntervalSince1970: 43_200))
        #expect(report.kind == .noop)
        #expect(state.stageScope(for: window.id)?.displayID == other.id)
    }
}
