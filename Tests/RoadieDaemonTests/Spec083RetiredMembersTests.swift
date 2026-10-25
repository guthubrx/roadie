import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

private struct InventoryProvider: SystemSnapshotProviding {
    var display: DisplaySnapshot
    var inventory: [WindowID: Int32]
    func permissions(prompt: Bool) -> PermissionSnapshot { .init(accessibilityTrusted: true) }
    func displays() -> [DisplaySnapshot] { [display] }
    func windows() -> [WindowSnapshot] { [] }
    func existingWindowPIDs() -> [WindowID: Int32]? { inventory }
}

/// SPEC-083 : la fenêtre de réglages d'AlDente (781), fermée mais gardée en mémoire, restait
/// membre de sa stage grâce à l'inventaire CoreGraphics. Bascules et restaurations l'attendaient.
@Suite
struct Spec083RetiredMembersTests {
    private let id = WindowID(rawValue: 781)

    private func fixture(probe: @escaping ([WindowID: Int32]) -> Set<WindowID>) -> (LayoutMaintainer, StageStore, () -> Void) {
        let display = powerDisplay("retired-display", index: 1, x: 0)
        let member = PersistentStageMember(windowID: id, bundleID: "com.apphousekitchen.aldente-pro", title: "AlDente",
            frame: Rect(CGRect(x: 150, y: 30, width: 1400, height: 1087)), pid: 61329)
        let path = tempPath("retired-083")
        let store = StageStore(path: path)
        store.save(PersistentStageState(scopes: [PersistentStageScope(displayID: display.id,
            activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1")),
                PersistentStage(id: StageID(rawValue: "2"), name: "Perso", members: [member])
            ])], activeDisplayID: display.id))
        let service = SnapshotService(provider: InventoryProvider(display: display, inventory: [id: 61329]),
            config: RoadieConfig(), stageStore: store)
        let maintainer = LayoutMaintainer(service: service, store: store, retiredWindowProbe: probe)
        return (maintainer, store, { try? FileManager.default.removeItem(atPath: path) })
    }

    private func member(in store: StageStore) -> PersistentStageMember? {
        store.state().scopes.flatMap(\.stages).flatMap(\.members).first { $0.windowID == id }
    }

    @Test
    func retiredMemberIsMarkedClosed() {
        var asked: [WindowID: Int32] = [:]
        let (maintainer, store, cleanup) = fixture { asked = $0; return Set($0.keys) }
        defer { cleanup() }

        _ = maintainer.tick()

        #expect(asked == [id: 61329])
        #expect(member(in: store)?.confirmedClosedAt != nil)
    }

    @Test
    func memberOnAnotherDesktopStaysOpenAndIsCheckedAtMostEvery30Seconds() {
        var calls = 0
        let (maintainer, store, cleanup) = fixture { _ in calls += 1; return [] }
        defer { cleanup() }

        _ = maintainer.tick()
        _ = maintainer.tick()

        #expect(calls == 1)
        #expect(member(in: store)?.confirmedClosedAt == nil)
    }
}
