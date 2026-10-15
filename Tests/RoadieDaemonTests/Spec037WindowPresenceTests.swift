import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieStages
@testable import RoadieDaemon

private struct Presence037Provider: SystemSnapshotProviding {
    var display: DisplaySnapshot
    var observed: [WindowSnapshot] = []
    var inventory: [WindowID: Int32]?
    func permissions(prompt: Bool) -> PermissionSnapshot { .init(accessibilityTrusted: true) }
    func displays() -> [DisplaySnapshot] { [display] }
    func windows() -> [WindowSnapshot] { observed }
    func existingWindowPIDs() -> [WindowID: Int32]? { inventory }
}

private final class Replay037Inventory: SystemSnapshotProviding, @unchecked Sendable {
    var inventory: [WindowID: Int32]?
    var reads = 0
    func permissions(prompt: Bool) -> PermissionSnapshot { .init(accessibilityTrusted: true) }
    func displays() -> [DisplaySnapshot] { [] }
    func windows() -> [WindowSnapshot] { [] }
    func existingWindowPIDs() -> [WindowID: Int32]? { reads += 1; return inventory }
}

@Suite
struct Spec037WindowPresenceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let id = WindowID(rawValue: 54856)

    @Test(arguments: [false, true])
    func inventoryIsReplayedExactlyOnceIncludingUnavailable(unavailable: Bool) {
        let base = Replay037Inventory()
        base.inventory = unavailable ? nil : [id: 706]
        let replay = ReplayableSnapshotProvider(base: base)
        let first = replay.existingWindowPIDs()
        #expect(first == base.inventory)
        base.inventory = [id: 707]
        replay.replayLastScan()
        #expect(replay.existingWindowPIDs() == first)
        #expect(base.reads == 1)
        #expect(replay.existingWindowPIDs() == [id: 707])
        #expect(base.reads == 2)
    }

    private func fixture(wrapped: Bool = false, inventory: [WindowID: Int32]?, closed: Bool = false, pid: Int32? = 706,
                         observed: [WindowSnapshot] = []) -> (SnapshotService, StageStore, DisplaySnapshot) {
        let display = powerDisplay("presence-display", index: 1, x: 0)
        let member = PersistentStageMember(windowID: id, bundleID: "test.word", title: "Document",
            frame: Rect(CGRect(x: 150, y: 40, width: 700, height: 600)),
            lastSeenAt: now.addingTimeInterval(-3601), missingSince: now.addingTimeInterval(-3600),
            confirmedClosedAt: closed ? now.addingTimeInterval(-1) : nil, pid: pid)
        let store = StageStore(path: tempPath("presence-036"))
        store.save(PersistentStageState(scopes: [PersistentStageScope(displayID: display.id,
            activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1")),
                PersistentStage(id: StageID(rawValue: "7"), name: "Stage 7", members: [member])
            ])], activeDisplayID: display.id))
        let provider = Presence037Provider(display: display, observed: observed, inventory: inventory)
        let actual: any SystemSnapshotProviding = wrapped ? ReplayableSnapshotProvider(base: provider) : provider
        let service = SnapshotService(provider: actual, config: RoadieConfig(), stageStore: store,
            clock: { now })
        return (service, store, display)
    }

    @Test(arguments: [false, true])
    func inactiveSpaceWindowKeepsItsStageAfterOneHourWithoutEnteringPlacement(wrapped: Bool) {
        let (service, store, display) = fixture(wrapped: wrapped, inventory: [id: 706])
        let before = store.state()
        let snapshot = service.snapshot(followFocus: false)
        let state = store.state()
        let scope = state.scopes.first { $0.displayID == display.id }!
        let represented = service.railWindowIDs(in: snapshot, state: state)

        #expect(snapshot.windows.isEmpty)
        #expect(represented.contains(id))
        #expect(scope.stages.first { $0.id.rawValue == "7" }?.members.map(\.windowID) == [id])
        #expect(RailController.railVisibleStageIDs(in: scope, liveWindowIDs: represented, now: now).contains(StageID(rawValue: "7")))
        #expect(state.scopes.map { $0.stages.map(\.id) } == before.scopes.map { $0.stages.map(\.id) })
        #expect(service.applyPlan(from: snapshot).commands.isEmpty)
    }

    @Test(arguments: ["closed", "other-pid", "unknown-pid", "absent", "unavailable"])
    func uncertainOrClosedIdentityDoesNotResurrectAStage(reason: String) {
        let inventory: [WindowID: Int32]? = reason == "unavailable" ? nil :
            reason == "absent" ? [:] : [id: reason == "other-pid" ? 707 : 706]
        let (service, store, _) = fixture(inventory: inventory, closed: reason == "closed",
            pid: reason == "unknown-pid" ? nil : 706)
        let state = store.state()
        let snapshot = DaemonSnapshot(permissions: .init(accessibilityTrusted: true), displays: [], windows: [], state: RoadieState())
        #expect(!service.railWindowIDs(in: snapshot, state: state).contains(id))
        #expect(store.state() == state)
    }

    @Test
    func observedNonTileWindowIsNotReintroducedByTheInventory() {
        var window = powerWindow(id.rawValue, x: 100)
        window.pid = 706
        window.isTileCandidate = false
        let (service, store, _) = fixture(inventory: [id: 706], observed: [window])
        let snapshot = DaemonSnapshot(permissions: .init(accessibilityTrusted: true), displays: [],
            windows: [.init(window: window, scope: nil)], state: RoadieState())
        #expect(!service.railWindowIDs(in: snapshot, state: store.state()).contains(id))
    }

    @Test
    func confirmedAXClosureWinsOverAnOffSpaceCGEntry() {
        let (service, store, _) = fixture(inventory: [id: 706])
        store.mutate { state in
            state.scopes[0].stages[1].members[0].missingSince = nil
            state.scopes[0].stages[1].members[0].lastSeenAt = now
        }
        service.noteWindowDestroyed(id)
        let snapshot = service.snapshot(followFocus: false)
        let state = store.state()
        #expect(state.scopes[0].stages[1].members[0].confirmedClosedAt != nil)
        #expect(!service.railWindowIDs(in: snapshot, state: state).contains(id))
    }

    @Test
    func offSpaceGroupKeepsItsOrderAndFocusedMember() {
        let second = WindowID(rawValue: 54857)
        let (service, store, _) = fixture(inventory: [id: 706, second: 706])
        store.mutate { state in
            var member = state.scopes[0].stages[1].members[0]
            member.windowID = second
            state.scopes[0].stages[1].members.append(member)
            state.scopes[0].stages[1].focusedWindowID = second
            state.scopes[0].stages[1].groups = [WindowGroup(id: "documents", windowIDs: [id, second], activeWindowID: second)]
        }
        let before = store.state().scopes[0].stages[1]
        let snapshot = service.snapshot(followFocus: false)
        let state = store.state()
        let projected = RailController.railDisplayStage(state.scopes[0].stages[1],
            liveWindowIDs: service.railWindowIDs(in: snapshot, state: state), now: now)
        #expect(projected.members.map(\.windowID) == [id, second])
        #expect(projected.groups == before.groups)
        #expect(projected.focusedWindowID == second)
        #expect(snapshot.windows.isEmpty)
    }

    @Test
    func unknownOffSpaceWindowIsNeverAdopted() {
        let other = WindowID(rawValue: 999)
        let (service, store, _) = fixture(inventory: [other: 1234])
        let snapshot = service.snapshot(followFocus: false)
        #expect(snapshot.windows.isEmpty)
        #expect(!service.railWindowIDs(in: snapshot, state: store.state()).contains(other))
        #expect(!store.state().scopes.flatMap(\.stages).flatMap(\.members).contains { $0.windowID == other })
    }
}
