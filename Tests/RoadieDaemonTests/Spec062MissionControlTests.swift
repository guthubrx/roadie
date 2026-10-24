import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

/// Interrupteur partagé avec la fermeture @Sendable de la sonde.
private final class Flag: @unchecked Sendable { var value: Bool; init(_ value: Bool) { self.value = value } }

/// Écrivain qui note l’intention « position seule » de chaque écriture, puis délègue.
private final class SizeIntentWriter: WindowFrameWriting, @unchecked Sendable {
    let inner: PowerUserWriter
    private(set) var preservesSize: [WindowID: [Bool]] = [:]
    init(_ inner: PowerUserWriter) { self.inner = inner }
    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        preservesSize[window.id, default: []].append(false)
        return inner.setFrame(frame, of: window)
    }
    func setFrames(_ updates: [WindowFrameUpdate], generation: UInt64) -> [WindowID: CGRect?] {
        var results: [WindowID: CGRect?] = [:]
        for update in updates {
            preservesSize[update.window.id, default: []].append(update.preservesSize)
            results.updateValue(inner.setFrame(update.frame, of: update.window), forKey: update.window.id)
        }
        return results
    }
}

@Suite("Spec062 Mission Control")
struct Spec062MissionControlTests {
    /// Changer de stage gare la fenêtre de la stage quittée en position seule : sa taille n’est jamais
    /// réécrite, même si le cadre observé était réduit par Mission Control.
    @Test func stageSwitchParksHiddenWindowWithoutSizeWrite() {
        let display = powerDisplay()
        let leaving = powerWindow(1, x: 100), arriving = powerWindow(2, x: 1500)
        let provider = PowerUserProvider(displays: [display], windows: [leaving, arriving])
        let writer = SizeIntentWriter(PowerUserWriter(provider: provider))
        let store = StageStore(path: tempPath("spec062-park"))
        func member(_ window: WindowSnapshot) -> PersistentStageMember {
            PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame)
        }
        store.save(PersistentStageState(scopes: [PersistentStageScope(displayID: display.id, activeStageID: StageID(rawValue: "1"), stages: [
            PersistentStage(id: StageID(rawValue: "1"), members: [member(leaving)]),
            PersistentStage(id: StageID(rawValue: "2"), members: [member(arriving)])])], activeDisplayID: display.id))
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store)

        _ = StageCommandService(service: service, store: store, config: RoadieConfig()).switchTo("2", displayID: display.id)

        #expect(writer.preservesSize[leaving.id]?.allSatisfy { $0 } == true)
        #expect(writer.preservesSize[leaving.id]?.isEmpty == false)
        #expect(provider.snapshots.first { $0.id == leaving.id }?.frame.width == leaving.frame.width)
    }

    /// Un relevé fait pendant Mission Control n’enregistre aucun cadre ; le suivant, si.
    @Test func snapshotDuringMissionControlDoesNotPersistFrames() {
        let display = powerDisplay()
        let window = powerWindow(1, x: 100)
        let provider = PowerUserProvider(displays: [display], windows: [window])
        let store = StageStore(path: tempPath("spec062-persist"))
        store.save(PersistentStageState(scopes: [PersistentStageScope(displayID: display.id, activeStageID: StageID(rawValue: "1"), stages: [
            PersistentStage(id: StageID(rawValue: "1"), members: [
                PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame)])])],
            activeDisplayID: display.id))
        let active = Flag(true)
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), config: RoadieConfig(),
                                      stageStore: store, persistStateChanges: true, missionControlActive: { active.value })
        // Cadre réduit et déplacé tel que Mission Control le rapporte.
        provider.snapshots[0].frame = Rect(x: 532, y: 640, width: 115, height: 66)
        _ = service.snapshot(followFocus: false)
        var state = store.state()
        let during = state.scopes.first?.stages.first?.members.first?.frame
        active.value = false
        _ = service.snapshot(followFocus: false)
        state = store.state()
        let after = state.scopes.first?.stages.first?.members.first?.frame

        #expect(during == window.frame)
        #expect(after == Rect(x: 532, y: 640, width: 115, height: 66))
    }

    /// Le fichier de restauration garde sa version précédente pendant Mission Control.
    @Test func restoreSnapshotIsNotRewrittenDuringMissionControl() throws {
        let display = powerDisplay()
        let window = powerWindow(1, x: 100)
        let provider = PowerUserProvider(displays: [display], windows: [window])
        let store = StageStore(path: tempPath("spec062-restore-state"))
        let active = Flag(false)
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), config: RoadieConfig(),
                                      stageStore: store, missionControlActive: { active.value })
        let restore = RestoreSafetyService(path: tempPath("spec062-restore.json"), markerPath: tempPath("spec062-marker.json"), service: service)
        let first = try restore.writeSnapshot()
        active.value = true
        provider.snapshots[0].frame = Rect(x: 532, y: 640, width: 115, height: 66)
        let during = try restore.writeSnapshot()

        #expect(during.windows == first.windows)
        #expect(during.windows.first?.frame == window.frame)
    }

    /// La vue d’ensemble et le sélecteur partent de la fenêtre au premier plan selon macOS, pas de celle
    /// retenue par la stage active du premier écran.
    @Test func switcherContextUsesTheSystemFocusedWindow() {
        let builtIn = powerDisplay("display-a", index: 1, x: 0), external = powerDisplay("display-b", index: 2, x: 1000)
        let retained = powerWindow(1, x: 100), working = powerWindow(2, x: 1100)
        let provider = PowerUserProvider(displays: [builtIn, external], windows: [retained, working])
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), config: RoadieConfig(),
                                      stageStore: StageStore(path: tempPath("spec062-focus")))
        let snapshot = service.snapshot(followFocus: false)
        let switcher = WindowSwitcherService(service: service)

        #expect(switcher.context(snapshot: snapshot, systemFocusedID: working.id).focusedWindowID == working.id)
        #expect(switcher.context(snapshot: snapshot, systemFocusedID: working.id).displayID == external.id)
        #expect(switcher.context(snapshot: snapshot, systemFocusedID: WindowID(rawValue: 999)).focusedWindowID == snapshot.focusedWindowID)
    }

    /// Les commandes encodées avant SPEC-062 restent lisibles, sans masquage implicite.
    @Test func applyCommandDecodesWithoutPreservesSize() throws {
        let command = ApplyCommand(window: powerWindow(3, x: 0), frame: Rect(x: 1, y: 2, width: 3, height: 4))
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as! [String: Any]
        json.removeValue(forKey: "preservesSize")
        let decoded = try JSONDecoder().decode(ApplyCommand.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded == command)
        #expect(!decoded.preservesSize)
    }
}
