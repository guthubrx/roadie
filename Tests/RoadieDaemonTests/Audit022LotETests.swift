import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

/// Lot E (audit v14, REL-002) : `roadie state heal` ne retire un membre absent du relevé que sur
/// preuve de fermeture (pid mort). Une fenêtre réduite, sur un autre Space, d'une application qui
/// ne répond pas ou d'un écran débranché est absente du relevé mais toujours ouverte.
@Suite
struct Audit022LotETests {
    private struct Provider: SystemSnapshotProviding {
        var displaySnapshots: [DisplaySnapshot]
        var windowSnapshots: [WindowSnapshot]

        func permissions(prompt: Bool) -> PermissionSnapshot { PermissionSnapshot(accessibilityTrusted: true) }
        func displays() -> [DisplaySnapshot] { displaySnapshots }
        func windows() -> [WindowSnapshot] { windowSnapshots }
        func focusedWindowID() -> WindowID? { windowSnapshots.first?.id }
    }

    private final class Writer: WindowFrameWriting, @unchecked Sendable {
        func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? { frame }
        func focus(_ window: WindowSnapshot) -> Bool { true }
    }

    private let display = DisplayID(rawValue: "display-e")
    private let stage1 = StageID(rawValue: "1")
    private let stage2 = StageID(rawValue: "2")
    private let desktop = DesktopID(rawValue: 1)

    private func window(_ id: UInt32, pid: Int32, x: Double = 0) -> WindowSnapshot {
        WindowSnapshot(
            id: WindowID(rawValue: id), pid: pid, appName: "App\(id)", bundleID: "app.\(id)",
            title: "w\(id)", frame: Rect(x: x, y: 0, width: 500, height: 500),
            isOnScreen: true, isTileCandidate: true
        )
    }

    private func member(_ id: UInt32, pid: Int32?) -> PersistentStageMember {
        PersistentStageMember(
            windowID: WindowID(rawValue: id), bundleID: "app.\(id)", title: "w\(id)",
            frame: Rect(x: 0, y: 0, width: 500, height: 500), pid: pid
        )
    }

    /// Écran vivant, stage 1 active avec la fenêtre visible 1, stage 2 inactive avec `members`.
    private func heal(
        stage2Members: [PersistentStageMember],
        stage2Focus: UInt32?,
        extraScopes: [PersistentStageScope] = [],
        liveWindows extra: [WindowSnapshot] = [],
        isProcessAlive: (Int32) -> Bool
    ) -> (PersistentStageState, StateHealReport) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-022-e-\(UUID().uuidString).json").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = StageStore(path: path)
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: display, activeStageID: stage1, stages: [
                    PersistentStage(id: stage1, focusedWindowID: WindowID(rawValue: 1), members: [member(1, pid: 100)]),
                    PersistentStage(id: stage2, focusedWindowID: stage2Focus.map { WindowID(rawValue: $0) }, members: stage2Members),
                ]),
            ] + extraScopes,
            desktopSelections: [PersistentDesktopSelection(displayID: display)],
            activeDisplayID: display
        ))
        let screen = Rect(x: 0, y: 0, width: 1000, height: 800)
        let service = SnapshotService(
            provider: Provider(
                displaySnapshots: [DisplaySnapshot(id: display, index: 1, name: "E", frame: screen, visibleFrame: screen, isMain: true)],
                windowSnapshots: [window(1, pid: 100)] + extra
            ),
            frameWriter: Writer(),
            config: RoadieConfig(),
            stageStore: store
        )
        let report = StateAuditService(service: service, stageStore: store).heal(isProcessAlive: isProcessAlive)
        return (store.state(), report)
    }

    private func ids(_ raw: [UInt32]) -> [WindowID] { raw.map { WindowID(rawValue: $0) } }

    /// Fenêtre réduite, sur un autre Space ou d'une application qui ne répond pas : absente du
    /// relevé, pid vivant. Appartenance, ordre et focus de la stage restent intacts.
    @Test
    func absentMemberWithLiveProcessKeepsMembershipOrderAndFocus() {
        var (state, _) = heal(
            stage2Members: [member(2, pid: 200), member(3, pid: 300)],
            stage2Focus: 2,
            isProcessAlive: { _ in true }
        )
        let scope = state.scope(displayID: display, desktopID: desktop)
        #expect(scope.memberIDs(in: stage2) == ids([2, 3]))
        #expect(scope.stages.first { $0.id == stage2 }?.focusedWindowID == WindowID(rawValue: 2))
        #expect(scope.memberIDs(in: stage1) == ids([1]))
    }

    /// Fenêtre masquée par Roadie dans une stage inactive : elle reste dans le relevé, hors écran.
    @Test
    func memberHiddenByRoadieOffscreenIsKept() {
        var (state, _) = heal(
            stage2Members: [member(2, pid: 200)],
            stage2Focus: 2,
            liveWindows: [window(2, pid: 200, x: 20_000)],
            isProcessAlive: { _ in false }
        )
        let scope = state.scope(displayID: display, desktopID: desktop)
        #expect(scope.memberIDs(in: stage2) == ids([2]))
    }

    /// Membre d'un écran débranché : absent du relevé, pid vivant, conservé pour le retour de l'écran.
    @Test
    func memberOfDisconnectedDisplayWithLiveProcessIsKept() {
        let gone = DisplayID(rawValue: "display-gone")
        let (state, _) = heal(
            stage2Members: [],
            stage2Focus: nil,
            extraScopes: [PersistentStageScope(displayID: gone, activeStageID: stage1, stages: [
                PersistentStage(id: stage1, focusedWindowID: WindowID(rawValue: 4), members: [member(4, pid: 400)]),
            ])],
            isProcessAlive: { _ in true }
        )
        let scope = state.scopes.first { $0.displayID == gone }
        #expect(scope?.memberIDs(in: stage1) == ids([4]))
    }

    /// Pid prouvé mort : la fenêtre est fermée, le membre part et le focus se replie.
    @Test
    func absentMemberWithDeadProcessIsRemoved() {
        var (state, report) = heal(
            stage2Members: [member(2, pid: 200), member(3, pid: 300)],
            stage2Focus: 3,
            isProcessAlive: { $0 != 300 }
        )
        let scope = state.scope(displayID: display, desktopID: desktop)
        #expect(scope.memberIDs(in: stage2) == ids([2]))
        #expect(scope.stages.first { $0.id == stage2 }?.focusedWindowID == WindowID(rawValue: 2))
        #expect(report.repaired >= 2)
    }

    /// Pid inconnu (ancien fichier d'état) : aucune preuve de fermeture, le membre reste. La grâce
    /// de 30 min du snapshot le retire plus tard s'il ne revient pas.
    @Test
    func absentMemberWithoutKnownPidIsKept() {
        var (state, _) = heal(
            stage2Members: [member(2, pid: nil)],
            stage2Focus: 2,
            isProcessAlive: { _ in false }
        )
        let scope = state.scope(displayID: display, desktopID: desktop)
        #expect(scope.memberIDs(in: stage2) == ids([2]))
    }

    /// La déduplication ne dépend pas de la visibilité : un membre absent en double est réduit à
    /// sa première occurrence.
    @Test
    func duplicateAbsentMemberIsDeduplicated() {
        var (state, report) = heal(
            stage2Members: [member(2, pid: 200), member(2, pid: 200), member(1, pid: 100)],
            stage2Focus: 2,
            isProcessAlive: { _ in true }
        )
        let scope = state.scope(displayID: display, desktopID: desktop)
        #expect(scope.memberIDs(in: stage1) == ids([1]))
        #expect(scope.memberIDs(in: stage2) == ids([2]))
        #expect(!report.audit.failed)
    }
}
