import CoreGraphics
import Darwin
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieStages
@testable import RoadieDaemon

/// Session 022, round 4, lot T3 : REL-001 (identifiants de stage et de fenêtre qui arrêtaient le
/// daemon), REL-021 (échec annoncé après un effet ou une première écriture) et REL-042 (code de
/// sortie déduit du texte). Aucun test ne touche à `~/.roadies`.
@MainActor
@Suite(.serialized)
struct Audit022R4LotT3Tests {
    // MARK: - REL-001 : génération d'identifiant de stage

    /// Avant la correction : `Int.max + 1` arrêtait le processus (erreur fatale Swift).
    @Test
    func assignEmptyAfterIntMaxStageCreatesFreeStageThroughCLI() throws {
        let fixture = try T3Fixture("t3-intmax", stages: [T3Fixture.stage("1", members: [0, 1])])
        defer { fixture.cleanUp() }
        let router = fixture.router()

        let create = router.run(["stage", "create", String(Int.max), "Limite"])
        #expect(create.exitCode == 0, "\(create)")
        let assign = router.run(["stage", "assign-empty"])

        #expect(assign.exitCode == 0, "\(assign)")
        let ids = fixture.stageIDs()
        #expect(ids.contains(String(Int.max)))
        let generated = ids.filter { $0.hasPrefix("stage-") }
        #expect(generated.count == 1, "\(ids)")
        #expect(fixture.stage(generated.first ?? "")?.members.map(\.windowID) == [fixture.left.id])
    }

    @Test
    func assignEmptyKeepsOrdinaryGenerationRules() throws {
        // Plus grand identifiant numérique + 1 ; la stage nommée n'est pas réutilisée.
        let named = try T3Fixture("t3-gen-max", stages: [
            T3Fixture.stage("1", members: [0, 1]),
            PersistentStage(id: StageID(rawValue: "5"), name: "Perso"),
        ])
        defer { named.cleanUp() }
        #expect(named.stages.assignEmpty().changed)
        #expect(named.stage("6")?.members.map(\.windowID) == [named.left.id])

        // Stage vide non nommée : réutilisée.
        let reusable = try T3Fixture("t3-gen-reuse")
        defer { reusable.cleanUp() }
        #expect(reusable.stages.assignEmpty().changed)
        #expect(reusable.stage("2")?.members.map(\.windowID) == [reusable.left.id])

        // Aucun identifiant numérique : nombre de stages + 1.
        let textual = try T3Fixture("t3-gen-text", stages: [T3Fixture.stage("main", members: [0, 1])])
        defer { textual.cleanUp() }
        #expect(textual.stages.assignEmpty().changed)
        #expect(textual.stage("2")?.members.map(\.windowID) == [textual.left.id])
    }

    /// Avant la correction : `WindowID(rawValue: 0)` arrêtait le processus (précondition).
    @Test
    func zeroWindowIDIsAUsageErrorForSummonAndGroupCommands() throws {
        let fixture = try T3Fixture("t3-summon-zero")
        defer { fixture.cleanUp() }
        let router = fixture.router()

        #expect(router.run(["stage", "summon", "0"]).exitCode == 64)
        for verb in ["add", "remove", "focus"] {
            #expect(router.run(["group", verb, "g", "0"]).exitCode == 64, "\(verb)")
        }
        #expect(CLICommandRouter.windowID("0") == nil)
        #expect(CLICommandRouter.windowID("-1") == nil)
        #expect(CLICommandRouter.windowID("7") == WindowID(rawValue: 7))
    }

    // MARK: - REL-021 : LayoutCommandService

    @Test
    func zoomParentMovesNothingWhenIntentCannotBeWritten() throws {
        let fixture = try T3Fixture("t3-zoom-intent")
        defer { fixture.cleanUp() }
        let garbage = try fixture.corruptIntents()

        let result = fixture.layout.zoomParent()

        fixture.expectRefused(result)
        #expect(try Data(contentsOf: fixture.intentURL) == garbage)
    }

    @Test
    func zoomParentRestoresPreviousIntentWhenFrameIsRefused() throws {
        let fixture = try T3Fixture("t3-zoom-refused", refuseFrames: true)
        defer { fixture.cleanUp() }
        let previous = fixture.commandIntent()
        try fixture.service.effectiveIntentStore.saveChecked(previous)

        let result = fixture.layout.zoomParent()

        #expect(!result.changed)
        #expect(result.outcome == .failed)
        #expect(fixture.service.effectiveIntentStore.intent(for: fixture.scope) == previous)
    }

    @Test
    func zoomParentReportsPartialResultWhenRollbackFails() throws {
        let fixture = try T3Fixture("t3-zoom-partial", refuseFrames: true)
        defer { fixture.cleanUp() }
        try fixture.service.effectiveIntentStore.saveChecked(fixture.commandIntent())
        fixture.writer.onFirstFrame = { _ = try? fixture.corruptIntents() }

        let result = fixture.layout.zoomParent()

        #expect(result.changed)
        #expect(result.outcome == .failed)
        #expect(result.message.contains("partial"), "\(result.message)")
        #expect(CLICommandRouter.actionExitCode(changed: result.changed, message: result.message, outcome: result.outcome) == 1)
    }

    @Test
    func zoomParentStillZoomsWhenWritable() throws {
        let fixture = try T3Fixture("t3-zoom-ok")
        defer { fixture.cleanUp() }

        let result = fixture.layout.zoomParent()

        #expect(result.changed, "\(result.message)")
        let intent = fixture.service.effectiveIntentStore.intent(for: fixture.scope)
        #expect(intent?.zoomedWindowID == fixture.left.id)
        #expect(intent?.placements[fixture.left.id] == fixture.main.visibleFrame)
        #expect(fixture.writer.frames[fixture.left.id] == fixture.main.visibleFrame)
    }

    @Test
    func insertAndSplitMoveNothingWhenIntentCannotBeWritten() throws {
        let insert = try T3Fixture("t3-insert")
        defer { insert.cleanUp() }
        _ = try insert.corruptIntents()
        insert.expectRefused(insert.layout.insert(.right))

        let split = try T3Fixture("t3-split")
        defer { split.cleanUp() }
        _ = try split.corruptIntents()
        split.expectRefused(split.layout.split("vertical"))
    }

    // MARK: - REL-021 : transferts (bureau, fenêtre, stage, menu contextuel)

    /// Avant la correction : affectation au bureau 2 et pin retiré déjà écrits, puis refus annoncé.
    @Test
    func desktopTransferKeepsMembershipAndPinWhenIntentCannotBeRemoved() throws {
        let fixture = try T3Fixture("t3-desktop")
        defer { fixture.cleanUp() }
        try fixture.pinLeftWindow()
        let before = fixture.normalizedState()
        _ = try fixture.corruptIntents()

        let result = fixture.desktops.assignActiveWindow(to: DesktopID(rawValue: 2))

        fixture.expectRefused(result)
        #expect(fixture.store.state() == before)
        #expect(fixture.store.state().pin(for: fixture.left.id) != nil)
    }

    @Test
    func windowTransferKeepsMembershipWhenIntentCannotBeRemoved() throws {
        let fixture = try T3Fixture("t3-window")
        defer { fixture.cleanUp() }
        let before = fixture.normalizedState()
        _ = try fixture.corruptIntents()

        let result = fixture.windows.sendToDisplay(2)

        fixture.expectRefused(result)
        #expect(fixture.store.state() == before)
    }

    /// Avant la correction : la fenêtre était déplacée, puis l'échec de l'intent final annonçait un refus.
    @Test
    func windowTransferSucceedsWhenFinalIntentCannotBeWrittenAfterMoving() throws {
        let fixture = try T3Fixture("t3-window-late")
        defer { fixture.cleanUp() }
        fixture.writer.onFirstFrame = { _ = try? fixture.corruptIntents() }

        let result = fixture.windows.sendToDisplay(2)

        #expect(result.changed, "\(result.message)")
        #expect(result.outcome == .changed)
        #expect(fixture.store.state().scopes.first { $0.displayID == fixture.side.id }?
            .stages.flatMap(\.members).map(\.windowID) == [fixture.left.id])
    }

    @Test
    func stageTransferKeepsStateWhenIntentCannotBeRemoved() throws {
        let fixture = try T3Fixture("t3-stage")
        defer { fixture.cleanUp() }
        let before = fixture.normalizedState()
        _ = try fixture.corruptIntents()

        let result = fixture.stages.moveActiveStageToDisplay(index: 2, followFocus: false)

        fixture.expectRefused(result)
        #expect(fixture.store.state() == before)
    }

    /// Stage déplacée et masquée, puis frames de retour non écrites : résultat partiel, pas un refus.
    @Test
    func stageTransferReportsPartialResultWhenReturnFramesCannotBeWritten() throws {
        let fixture = try T3Fixture("t3-stage-late")
        defer { fixture.cleanUp() }
        fixture.writer.onFirstFrame = { chmod(fixture.directory.path, 0o500) }

        let result = fixture.stages.moveActiveStageToDisplay(index: 2, followFocus: false)
        guard access(fixture.directory.path, W_OK) != 0 else { return } // administrateur

        #expect(result.changed)
        #expect(result.outcome == .failed)
        #expect(result.message.contains("partial"), "\(result.message)")
    }

    @Test
    func stagePlaceKeepsStateWhenIntentCannotBeRemoved() throws {
        // Stage cible sans arbre (placeWindow) puis à arbre (placeInTree).
        for mode in [WindowManagementMode.bsp, .spatialBsp] {
            let fixture = try T3Fixture("t3-place-\(mode.rawValue)", sideMode: mode)
            defer { fixture.cleanUp() }
            let before = fixture.normalizedState()
            _ = try fixture.corruptIntents()

            let result = fixture.stages.place(windowID: fixture.left.id, displayID: fixture.side.id, orderedWindowIDs: [fixture.left.id])

            fixture.expectRefused(result)
            #expect(fixture.store.state() == before, "\(mode)")
        }
    }

    @Test
    func contextMenuDesktopStageKeepsStateWhenIntentCannotBeRemoved() throws {
        let fixture = try T3Fixture("t3-context")
        defer { fixture.cleanUp() }
        let before = fixture.normalizedState()
        _ = try fixture.corruptIntents()

        let result = fixture.contextActions.execute(WindowContextAction(
            windowID: fixture.left.id, kind: .desktopStage, targetID: "1:2", sourceScope: fixture.scope
        ))

        fixture.expectRefused(result)
        #expect(fixture.store.state() == before)
    }

    /// Retour arrière impossible (état non inscriptible) : erreur partielle, résultat `changed`, code 1.
    @Test
    func stageTransferRollbackFailureIsReportedAsPartial() throws {
        let fixture = try T3Fixture("t3-rollback")
        defer { fixture.cleanUp() }
        _ = try fixture.corruptIntents()

        #expect(throws: PartialCommitError.self) {
            try fixture.service.commitStageTransfer(in: fixture.store, { state in
                state.activeDisplayID = fixture.side.id
            }, clearingIntentsOf: { _ in
                chmod(fixture.directory.path, 0o500)
                return [fixture.scope]
            })
        }
        guard access(fixture.directory.path, W_OK) != 0 else { return }
        let result = StageCommandResult.persistenceFailure("t3", PartialCommitError(cause: "c", rollback: CocoaError(.fileWriteNoPermission)))
        #expect(result.changed && result.outcome == .failed)
    }

    // MARK: - REL-021 : state heal

    /// Avant la correction : réparation comptée et code 0 alors que rien n'était écrit.
    @Test
    func stateHealReportsUnpersistedRepairsAsFailure() throws {
        let fixture = try T3Fixture("t3-heal", activeDisplay: false)
        defer { fixture.cleanUp() }
        chmod(fixture.directory.path, 0o500)
        guard access(fixture.directory.path, W_OK) != 0 else { return }

        let report = StateAuditService(service: fixture.service).heal()

        #expect(report.repaired == 0)
        #expect(report.persistenceError != nil)
        #expect(report.failed)
        let response = fixture.router().run(["state", "heal"])
        #expect(response.exitCode == 1)
        #expect(response.stderr.contains("state heal: failed"), "\(response.stderr)")
    }

    // MARK: - REL-042 : statut explicite

    /// Avant la correction : « stage create failed » répété donnait le code 1 (mot du nom).
    @Test
    func repeatedStageCreateIsANoOpWhateverTheStageName() throws {
        let fixture = try T3Fixture("t3-create-names")
        defer { fixture.cleanUp() }
        let router = fixture.router()

        for name in ["failed", "not found", "unknown", "requires", "unavailable", "must x", "demo"] {
            #expect(router.run(["stage", "create", name]).exitCode == 0, "\(name)")
            let again = router.run(["stage", "create", name])
            #expect(again.exitCode == 0, "\(name): \(again.stdout)")
            #expect(again.stdout.contains("already exists"))
        }
    }

    @Test
    func realPersistenceFailureStillExitsNonZero() throws {
        let fixture = try T3Fixture("t3-create-fail")
        defer { fixture.cleanUp() }
        chmod(fixture.directory.path, 0o500)
        guard access(fixture.directory.path, W_OK) != 0 else { return }

        #expect(fixture.router().run(["stage", "create", "demo"]).exitCode == 1)
    }

    @Test
    func exitCodeFollowsOutcomeAndKeepsTextFallbackWithoutOne() {
        #expect(CLICommandRouter.actionExitCode(changed: false, message: "stage create failed: already exists", outcome: .noOp) == 0)
        #expect(CLICommandRouter.actionExitCode(changed: false, message: "anything", outcome: .failed) == 1)
        #expect(CLICommandRouter.actionExitCode(changed: true, message: "x: partial", outcome: .failed) == 1)
        // Résultat construit hors du lot, sans statut : lecture du message conservée.
        let legacy = StageCommandResult(message: "display focus 9: unknown display", changed: false)
        #expect(legacy.outcome == nil)
        #expect(CLICommandRouter.actionExitCode(changed: legacy.changed, message: legacy.message, outcome: legacy.outcome) == 1)
        #expect(StageCommandResult(message: "done", changed: true).outcome == .changed)
    }
}

// MARK: - Outils

/// Écrivain de test : applique ou refuse les cadres, et appelle `onFirstFrame` à la première
/// écriture (panne injectée entre l'effet AX et une écriture d'état suivante).
private final class T3Writer: WindowFrameWriting, @unchecked Sendable {
    let provider: PowerUserProvider
    let refuse: Bool
    var onFirstFrame: (() -> Void)?
    private(set) var frames: [WindowID: Rect] = [:]
    private(set) var focused: [WindowID] = []

    init(provider: PowerUserProvider, refuse: Bool) {
        self.provider = provider
        self.refuse = refuse
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        if let hook = onFirstFrame {
            onFirstFrame = nil
            hook()
        }
        guard !refuse else { return nil }
        frames[window.id] = Rect(frame)
        provider.snapshots = provider.snapshots.map {
            guard $0.id == window.id else { return $0 }
            var updated = $0
            updated.frame = Rect(frame)
            return updated
        }
        return frame
    }

    func focus(_ window: WindowSnapshot) -> Bool {
        focused.append(window.id)
        provider.focusedID = window.id
        return true
    }
}

/// Deux écrans ; écran principal : stage 1 avec deux fenêtres, stage 2 vide (par défaut).
/// État des stages et intents dans un dossier temporaire.
@MainActor
private struct T3Fixture {
    let directory: URL
    let main = powerDisplay("display-main", index: 1, x: 0)
    let side = powerDisplay("display-side", index: 2, x: 1000)
    let left = powerWindow(1, x: 0, y: 0, width: 500, height: 800)
    let right = powerWindow(2, x: 500, y: 0, width: 500, height: 800)
    let provider: PowerUserProvider
    let writer: T3Writer
    let store: StageStore
    let intentURL: URL
    let service: SnapshotService
    let events: EventLog

    static func stage(_ id: String, members: [Int] = []) -> PersistentStage {
        let windows = [powerWindow(1, x: 0, y: 0, width: 500, height: 800), powerWindow(2, x: 500, y: 0, width: 500, height: 800)]
        return PersistentStage(
            id: StageID(rawValue: id),
            focusedWindowID: members.first.map { windows[$0].id },
            members: members.map { index in
                let window = windows[index]
                return PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame)
            }
        )
    }

    init(
        _ name: String,
        stages: [PersistentStage] = [T3Fixture.stage("1", members: [0, 1]), T3Fixture.stage("2")],
        refuseFrames: Bool = false,
        activeDisplay: Bool = true,
        sideMode: WindowManagementMode = .bsp
    ) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        provider = PowerUserProvider(displays: [main, side], windows: [left, right])
        provider.focusedID = left.id
        writer = T3Writer(provider: provider, refuse: refuseFrames)
        store = StageStore(path: directory.appendingPathComponent("stages.json").path)
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: main.id, activeStageID: stages[0].id, stages: stages),
            PersistentStageScope(displayID: side.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), mode: sideMode),
            ]),
        ], activeDisplayID: activeDisplay ? main.id : nil))
        intentURL = directory.appendingPathComponent("intents.json")
        events = EventLog(path: directory.appendingPathComponent("events.jsonl").path)
        service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(),
            intentStore: LayoutIntentStore(path: intentURL.path),
            stageStore: store,
            events: events
        )
    }

    var scope: StageScope {
        StageScope(displayID: main.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
    }

    var windows: WindowCommandService { WindowCommandService(service: service, stageStore: store, events: events) }
    var desktops: DesktopCommandService { DesktopCommandService(service: service, store: store, events: events) }
    var stages: StageCommandService { StageCommandService(service: service, store: store, events: events) }
    var layout: LayoutCommandService { LayoutCommandService(service: service, events: events) }
    var contextActions: WindowContextActions {
        WindowContextActions(snapshotService: service, stageStore: store, eventLog: events, stageLabelsVisible: { false })
    }

    func router() -> CLICommandRouter {
        let service = service
        return CLICommandRouter(makeService: { _ in service })
    }

    /// État après un relevé : le relevé normalise l'état (pid, présentation, sélection de bureau).
    func normalizedState() -> PersistentStageState {
        _ = service.snapshot()
        return store.state()
    }

    func stageIDs() -> [String] {
        store.state().scopes.first { $0.displayID == main.id }?.stages.map(\.id.rawValue) ?? []
    }

    func stage(_ id: String) -> PersistentStage? {
        store.state().scopes.first { $0.displayID == main.id }?.stages.first { $0.id.rawValue == id }
    }

    func commandIntent() -> LayoutIntent {
        LayoutIntent(
            scope: scope,
            windowIDs: [left.id, right.id],
            placements: [left.id: Rect(x: 0, y: 0, width: 300, height: 800), right.id: Rect(x: 300, y: 0, width: 700, height: 800)],
            source: .command
        )
    }

    func pinLeftWindow() throws {
        try store.mutateChecked { state in
            _ = state.setPin(window: left, homeScope: scope, pinScope: .desktop)
        }
    }

    /// Intents illisibles : toute écriture d'intent est refusée, quel que soit l'utilisateur.
    @discardableResult
    func corruptIntents() throws -> Data {
        let garbage = Data("{ pas du json".utf8)
        try garbage.write(to: intentURL)
        return garbage
    }

    /// Contrat REL-021 : échec annoncé (statut et code CLI), aucun cadre ni focus AX.
    func expectRefused(_ result: some CommandResult, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(!result.changed, "\(result.message)", sourceLocation: sourceLocation)
        #expect(result.outcome == .failed, "\(result.message)", sourceLocation: sourceLocation)
        #expect(result.message.contains("failed"), "\(result.message)", sourceLocation: sourceLocation)
        #expect(writer.frames.isEmpty, "\(writer.frames)", sourceLocation: sourceLocation)
        #expect(writer.focused.isEmpty, "\(writer.focused)", sourceLocation: sourceLocation)
    }

    func cleanUp() {
        chmod(directory.path, 0o700)
        try? FileManager.default.removeItem(at: directory)
    }
}
