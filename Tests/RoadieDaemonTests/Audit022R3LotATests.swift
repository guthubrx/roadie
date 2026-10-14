import CoreGraphics
import Darwin
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieStages
import RoadieTiler
@testable import RoadieDaemon

/// Session 022, round 3, lot A : R2-01. Une commande qui annonce un échec n'a produit aucun effet
/// AX et laisse un état que la maintenance ne transforme pas en effet après coup : entrée en
/// zoom, `mode` et `balance`. Aucun test ne touche à `~/.roadies`.
@Suite(.serialized)
struct Audit022R3LotATests {
    // MARK: - Entrée en zoom (WindowCommands)

    @Test
    func zoomOnNeitherMovesNorHidesWhenLayoutIntentCannotBeWritten() throws {
        let fixture = try R3AFixture("r3a-zoom-intent")
        defer { fixture.cleanUp() }
        let garbage = try fixture.corruptIntents()

        let result = fixture.windows.toggleFullscreen()

        fixture.expectRefused(result)
        #expect(try Data(contentsOf: fixture.intentURL) == garbage)
        // Cadre mémorisé écrit avant l'intent, puis rendu : la stage ne retient pas le zoom.
        #expect(fixture.rememberedFrame(of: fixture.left.id) == fixture.left.frame)
    }

    @Test
    func zoomOnNeitherMovesNorWritesIntentWhenStageStateCannotBeWritten() throws {
        let fixture = try R3AFixture("r3a-zoom-stage")
        defer { fixture.cleanUp() }
        let before = try fixture.lockStageDirectory()
        guard fixture.stageDirectoryIsReadOnly else { return } // administrateur : cas non reproductible

        let result = fixture.windows.toggleFullscreen()

        fixture.expectRefused(result)
        #expect(try Data(contentsOf: fixture.store.fileURL) == before)
        #expect(fixture.service.effectiveIntentStore.intent(for: fixture.scope) == nil)
    }

    /// Cadre refusé par l'application après les écritures : intent précédent et cadre mémorisé
    /// reviennent, aucune voisine n'est cachée.
    @Test
    func zoomOnRefusedByApplicationRestoresPreviousIntentAndRememberedFrame() throws {
        let fixture = try R3AFixture("r3a-zoom-refused", writer: RefusingFrameWriter())
        defer { fixture.cleanUp() }
        let previous = fixture.commandIntent()
        try fixture.service.effectiveIntentStore.saveChecked(previous)

        let result = fixture.windows.toggleFullscreen()

        #expect(!result.changed)
        #expect(result.message == "toggle fullscreen on: failed, refused frame")
        #expect(fixture.service.effectiveIntentStore.intent(for: fixture.scope) == previous)
        #expect(fixture.rememberedFrame(of: fixture.left.id) == fixture.left.frame)
        #expect(fixture.refusingWriter?.requested == [fixture.left.id])
    }

    @Test
    func zoomOnStillRecordsIntentAndRememberedFrameWhenWritable() throws {
        let fixture = try R3AFixture("r3a-zoom-ok")
        defer { fixture.cleanUp() }

        let result = fixture.windows.toggleFullscreen()

        #expect(result.changed)
        let intent = fixture.service.effectiveIntentStore.intent(for: fixture.scope)
        #expect(intent?.zoomedWindowID == fixture.left.id)
        #expect(intent?.placements[fixture.left.id] == fixture.powerWriter?.frames[fixture.left.id])
        #expect(intent?.placements[fixture.right.id] == fixture.powerWriter?.frames[fixture.right.id])
        #expect(fixture.rememberedFrame(of: fixture.left.id) == fixture.powerWriter?.frames[fixture.left.id])
    }

    // MARK: - mode (StageCommands)

    /// Avant R2-01, le mode était écrit puis le retrait de l'intent échouait : la maintenance
    /// appliquait le nouveau mode après l'échec annoncé.
    @Test
    func modeWritesNothingWhenLayoutIntentCannotBeRemoved() throws {
        let fixture = try R3AFixture("r3a-mode-intent")
        defer { fixture.cleanUp() }
        let garbage = try fixture.corruptIntents()

        let result = fixture.stages.setMode(.float)

        fixture.expectRefused(result)
        // Le snapshot peut normaliser le fichier : seul le mode compte.
        #expect(fixture.stageMode() == .bsp)
        #expect(try Data(contentsOf: fixture.intentURL) == garbage)
    }

    @Test
    func modeRestoresLayoutIntentWhenModeCannotBeWritten() throws {
        let fixture = try R3AFixture("r3a-mode-stage")
        defer { fixture.cleanUp() }
        let intent = fixture.commandIntent()
        try fixture.service.effectiveIntentStore.saveChecked(intent)
        let before = try fixture.lockStageDirectory()
        guard fixture.stageDirectoryIsReadOnly else { return }

        let result = fixture.stages.setMode(.float)

        fixture.expectRefused(result)
        #expect(try Data(contentsOf: fixture.store.fileURL) == before)
        #expect(fixture.service.effectiveIntentStore.intent(for: fixture.scope) == intent)
    }

    // MARK: - balance (LayoutCommandService)

    /// Avant R2-01, les intents étaient retirés puis l'arbre refusé : la maintenance redisposait
    /// l'écran sans intent après l'échec annoncé.
    @Test
    func balanceRestoresLayoutIntentsWhenTreesCannotBeWritten() throws {
        let fixture = try R3AFixture("r3a-balance-stage", mode: .spatialBsp, tree: .split(
            orientation: .vertical, ratio: 0.7, first: .leaf(WindowID(rawValue: 1)), second: .leaf(WindowID(rawValue: 2))
        ))
        defer { fixture.cleanUp() }
        let intent = fixture.commandIntent()
        try fixture.service.effectiveIntentStore.saveChecked(intent)
        let before = try fixture.lockStageDirectory()
        guard fixture.stageDirectoryIsReadOnly else { return }

        let result = fixture.layout.balance()

        fixture.expectRefused(result)
        #expect(try Data(contentsOf: fixture.store.fileURL) == before)
        #expect(fixture.service.effectiveIntentStore.intent(for: fixture.scope) == intent)
    }

    @Test
    func balanceStillBalancesTreeWhenWritable() throws {
        let fixture = try R3AFixture("r3a-balance-ok", mode: .spatialBsp, tree: .split(
            orientation: .vertical, ratio: 0.7, first: .leaf(WindowID(rawValue: 1)), second: .leaf(WindowID(rawValue: 2))
        ))
        defer { fixture.cleanUp() }
        try fixture.service.effectiveIntentStore.saveChecked(fixture.commandIntent())

        let result = fixture.layout.balance()

        #expect(result.changed, "\(result.message)")
        #expect(fixture.store.state().bspTree(for: fixture.scope) == .split(
            orientation: .vertical, ratio: 0.5, first: .leaf(fixture.left.id), second: .leaf(fixture.right.id)
        ))
        #expect(fixture.service.effectiveIntentStore.intent(for: fixture.scope) == nil)
        #expect(fixture.powerWriter?.frames.isEmpty == false)
    }
}

// MARK: - Outils

/// Refuse tout cadre (application qui ne répond pas) et note les fenêtres visées.
private final class RefusingFrameWriter: WindowFrameWriting, @unchecked Sendable {
    private(set) var requested: [WindowID] = []

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        requested.append(window.id)
        return nil
    }
}

/// Un écran, stage 1 avec deux fenêtres côte à côte. État des stages et intents dans deux
/// dossiers distincts : l'un peut être en lecture seule sans bloquer l'autre.
private struct R3AFixture {
    let stageDirectory: URL
    let intentDirectory: URL
    let main = powerDisplay()
    let left = powerWindow(1, x: 0, y: 0, width: 500, height: 800)
    let right = powerWindow(2, x: 500, y: 0, width: 500, height: 800)
    let provider: PowerUserProvider
    let writer: any WindowFrameWriting
    let store: StageStore
    let intentURL: URL
    let eventURL: URL
    let service: SnapshotService
    let events: EventLog

    init(
        _ name: String,
        mode: WindowManagementMode = .bsp,
        tree: BSPTree? = nil,
        writer customWriter: (any WindowFrameWriting)? = nil
    ) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
        stageDirectory = root.appendingPathComponent("stages")
        intentDirectory = root.appendingPathComponent("intents")
        try FileManager.default.createDirectory(at: stageDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: intentDirectory, withIntermediateDirectories: true)
        provider = PowerUserProvider(displays: [main], windows: [left, right])
        provider.focusedID = left.id
        writer = customWriter ?? PowerUserWriter(provider: provider)
        store = StageStore(path: stageDirectory.appendingPathComponent("stages.json").path)
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: main.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(
                    id: StageID(rawValue: "1"),
                    mode: mode,
                    focusedWindowID: left.id,
                    members: [r3aMember(left), r3aMember(right)],
                    bspTree: tree
                ),
            ]),
        ], activeDisplayID: main.id))
        intentURL = intentDirectory.appendingPathComponent("intents.json")
        eventURL = root.appendingPathComponent("events.jsonl")
        events = EventLog(path: eventURL.path)
        service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(),
            intentStore: LayoutIntentStore(path: intentURL.path),
            stageStore: store
        )
    }

    var scope: StageScope {
        StageScope(displayID: main.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
    }

    var windows: WindowCommandService { WindowCommandService(service: service, stageStore: store, events: events) }
    var stages: StageCommandService { StageCommandService(service: service, store: store, events: events) }
    var layout: LayoutCommandService { LayoutCommandService(service: service, events: events) }
    var powerWriter: PowerUserWriter? { writer as? PowerUserWriter }
    var refusingWriter: RefusingFrameWriter? { writer as? RefusingFrameWriter }

    /// Intent de commande (disposition choisie par l'utilisateur) sur la stage active.
    func commandIntent() -> LayoutIntent {
        LayoutIntent(
            scope: scope,
            windowIDs: [left.id, right.id],
            placements: [left.id: Rect(x: 0, y: 0, width: 300, height: 800), right.id: Rect(x: 300, y: 0, width: 700, height: 800)],
            source: .command
        )
    }

    func stageMode() -> WindowManagementMode? {
        store.state().scopes.first { $0.displayID == main.id }?.stages.first { $0.id == scope.stageID }?.mode
    }

    func rememberedFrame(of windowID: WindowID) -> Rect? {
        store.state().scopes.flatMap(\.stages).flatMap(\.members).first { $0.windowID == windowID }?.frame
    }

    /// Octets de l'état avant la commande, puis dossier des stages en lecture seule.
    func lockStageDirectory() throws -> Data {
        let data = try Data(contentsOf: store.fileURL)
        chmod(stageDirectory.path, 0o500)
        return data
    }

    var stageDirectoryIsReadOnly: Bool { access(stageDirectory.path, W_OK) != 0 }

    /// Intents illisibles : toute écriture d'intent est refusée.
    func corruptIntents() throws -> Data {
        let garbage = Data("{ pas du json".utf8)
        try garbage.write(to: intentURL)
        return garbage
    }

    /// Contrat REL-021 : échec annoncé, code CLI non nul, aucun cadre ni focus AX.
    func expectRefused(_ result: some CommandResult, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(!result.changed, sourceLocation: sourceLocation)
        #expect(result.message.contains("failed"), "\(result.message)", sourceLocation: sourceLocation)
        #expect(result.outcome == .failed, sourceLocation: sourceLocation)
        #expect(CLICommandRouter.actionExitCode(outcome: result.outcome) == 1, sourceLocation: sourceLocation)
        #expect(powerWriter?.frames.isEmpty == true, "\(String(describing: powerWriter?.frames))", sourceLocation: sourceLocation)
        #expect(powerWriter?.focused.isEmpty == true, sourceLocation: sourceLocation)
    }

    func cleanUp() {
        chmod(stageDirectory.path, 0o700)
        try? FileManager.default.removeItem(at: stageDirectory.deletingLastPathComponent())
    }
}

private func r3aMember(_ window: WindowSnapshot) -> PersistentStageMember {
    PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame)
}
