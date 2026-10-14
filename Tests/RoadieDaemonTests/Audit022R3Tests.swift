import CoreGraphics
import Darwin
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieStages
@testable import RoadieDaemon

/// Session 022, round 3 : R1-02 / REL-021 généralisé (commandes de fenêtre, bureau, signet,
/// groupe, menu contextuel, écran et disposition), `isFloating` unique dans la sortie
/// d'automatisation et `events.gap` au catalogue. Aucun test ne touche à `~/.roadies`.
@Suite(.serialized)
struct Audit022R3Tests {
    // MARK: - R1-02 : WindowCommands

    @Test
    func windowMoveNeitherMovesNorFocusesWhenLayoutIntentCannotBeRemoved() throws {
        let fixture = try R3Fixture("r3-window-move")
        defer { fixture.cleanUp() }
        let garbage = try fixture.corruptIntents()

        let result = fixture.windows.move(.right)

        fixture.expectRefused(result)
        #expect(try Data(contentsOf: fixture.intentURL) == garbage)
    }

    @Test
    func windowSendToDisplayDoesNotMoveWhenStageStateCannotBeWritten() throws {
        let fixture = try R3Fixture("r3-window-display")
        defer { fixture.cleanUp() }
        let before = try fixture.lockStateDirectory()
        guard fixture.directoryIsReadOnly else { return } // administrateur : cas non reproductible

        let result = fixture.windows.sendToDisplay(2)

        fixture.expectRefused(result)
        #expect(try Data(contentsOf: fixture.store.fileURL) == before)
    }

    /// Sortie de plein écran (DaemonSnapshot.restoreZoomLayoutIntentChecked) : intent illisible,
    /// aucune restauration de cadre.
    @Test
    func toggleFullscreenOffDoesNotRestoreWhenLayoutIntentCannotBeRemoved() throws {
        let fixture = try R3Fixture("r3-fullscreen-off", leftFrame: Rect(x: 0, y: 0, width: 1000, height: 800))
        defer { fixture.cleanUp() }
        _ = try fixture.corruptIntents()

        let result = fixture.windows.toggleFullscreen()

        #expect(result.message.hasPrefix("toggle fullscreen off: failed"))
        fixture.expectRefused(result)
    }

    // MARK: - R1-02 : DesktopCommands

    @Test
    func desktopFocusNeitherHidesNorFocusesWhenStateCannotBeWritten() throws {
        let fixture = try R3Fixture("r3-desktop-focus")
        defer { fixture.cleanUp() }
        let before = try fixture.lockStateDirectory()
        guard fixture.directoryIsReadOnly else { return }

        let result = fixture.desktops.focus(DesktopID(rawValue: 2))

        fixture.expectRefused(result)
        #expect(try Data(contentsOf: fixture.store.fileURL) == before)
    }

    @Test
    func desktopLabelReportsFailureWhenStateIsUnreadable() throws {
        let fixture = try R3Fixture("r3-desktop-label")
        defer { fixture.cleanUp() }
        let garbage = try fixture.corruptStageState()

        let result = fixture.desktops.label(DesktopID(rawValue: 1), as: "Code")

        fixture.expectRefused(result)
        #expect(try Data(contentsOf: fixture.store.fileURL) == garbage)
    }

    // MARK: - R1-02 : WindowBookmarkCommands

    @Test
    func bookmarkSetReportsFailureWithoutEventWhenStateCannotBeWritten() throws {
        let fixture = try R3Fixture("r3-bookmark-set")
        defer { fixture.cleanUp() }
        let before = try fixture.lockStateDirectory()
        guard fixture.directoryIsReadOnly else { return }

        let result = fixture.bookmarks.set("code")

        fixture.expectRefused(result)
        #expect(try Data(contentsOf: fixture.store.fileURL) == before)
        #expect(!fixture.eventLogContains("window.bookmark_set"))
    }

    @Test
    func bookmarkFocusNeitherMovesNorFocusesWhenStateCannotBeWritten() throws {
        let fixture = try R3Fixture("r3-bookmark-focus")
        defer { fixture.cleanUp() }
        #expect(fixture.bookmarks.set("code").changed)
        // Stage 2 active : le focus du signet doit rendre la stage 1 active, donc écrire l'état.
        fixture.store.mutate { state in
            var scope = state.scope(displayID: fixture.main.id, desktopID: DesktopID(rawValue: 1))
            scope.activeStageID = StageID(rawValue: "2")
            state.update(scope)
        }
        let before = try fixture.lockStateDirectory()
        guard fixture.directoryIsReadOnly else { return }

        let result = fixture.bookmarks.focus("code")

        fixture.expectRefused(result)
        #expect(try Data(contentsOf: fixture.store.fileURL) == before)
    }

    // MARK: - R1-02 : WindowGroupCommands

    @Test
    func groupCreateReportsFailureWithoutEventWhenStateCannotBeWritten() throws {
        let fixture = try R3Fixture("r3-group-create")
        defer { fixture.cleanUp() }
        let before = try fixture.lockStateDirectory()
        guard fixture.directoryIsReadOnly else { return }

        let result = fixture.groups.create(id: "pair", windowIDs: [fixture.left.id, fixture.right.id])

        fixture.expectRefused(result)
        #expect(try Data(contentsOf: fixture.store.fileURL) == before)
        #expect(!fixture.eventLogContains("window.grouped"))
    }

    // MARK: - R1-02 : WindowContextActions

    @Test
    func contextPinReportsFailureWithoutEventWhenStateCannotBeWritten() throws {
        let fixture = try R3Fixture("r3-context-pin")
        defer { fixture.cleanUp() }
        let before = try fixture.lockStateDirectory()
        guard fixture.directoryIsReadOnly else { return }

        let result = fixture.contextActions.execute(WindowContextAction(
            windowID: fixture.left.id,
            kind: .pinDesktop,
            targetID: "",
            sourceScope: nil
        ))

        fixture.expectRefused(result)
        #expect(try Data(contentsOf: fixture.store.fileURL) == before)
        #expect(!fixture.eventLogContains("window.pin_added"))
    }

    // MARK: - R1-02 : DisplayCommands

    @Test
    func displayFocusDoesNotFocusWhenStateCannotBeWritten() throws {
        let fixture = try R3Fixture("r3-display-focus")
        defer { fixture.cleanUp() }
        let before = try fixture.lockStateDirectory()
        guard fixture.directoryIsReadOnly else { return }

        let result = fixture.displays.focus(index: 2)

        fixture.expectRefused(result)
        #expect(try Data(contentsOf: fixture.store.fileURL) == before)
    }

    // MARK: - R1-02 : LayoutCommandService

    @Test
    func layoutFlattenDoesNotLayOutWhenLayoutIntentCannotBeRemoved() throws {
        let fixture = try R3Fixture("r3-layout-flatten")
        defer { fixture.cleanUp() }
        let garbage = try fixture.corruptIntents()

        let result = fixture.layout.flatten()

        fixture.expectRefused(result)
        #expect(try Data(contentsOf: fixture.intentURL) == garbage)
    }

    @Test
    func layoutBalanceDoesNotLayOutWhenLayoutIntentCannotBeRemoved() throws {
        let fixture = try R3Fixture("r3-layout-balance")
        defer { fixture.cleanUp() }
        _ = try fixture.corruptIntents()

        let result = fixture.layout.balance()

        fixture.expectRefused(result)
    }

    // MARK: - R1-02 : chemin nominal inchangé

    @Test
    func commandsStillSucceedWhenStateIsWritable() throws {
        let fixture = try R3Fixture("r3-ok")
        defer { fixture.cleanUp() }

        #expect(fixture.bookmarks.set("code").changed)
        #expect(fixture.groups.create(id: "pair", windowIDs: [fixture.left.id, fixture.right.id]).changed)
        #expect(fixture.desktops.label(DesktopID(rawValue: 1), as: "Code").changed)
        #expect(fixture.windows.move(.right).changed)
        #expect(!fixture.writer.frames.isEmpty)
        let state = fixture.store.state()
        #expect(state.bookmark(named: "code")?.windowID == fixture.left.id)
        #expect(state.label(displayID: fixture.main.id, desktopID: DesktopID(rawValue: 1)) == "Code")
    }

    // MARK: - isFloating unique (R1-07 / REL-007)

    /// La sortie d'automatisation suit `LayoutMaintainer.ruleFloatingState` : stage `float`,
    /// fenêtre hors mosaïque et fenêtre épinglée flottent ; une candidate sans scope (en attente
    /// d'un écran débranché) n'est plus annoncée flottante (inconnu rendu `false`).
    @Test
    func automationIsFloatingFollowsRuleClassification() throws {
        let display = powerDisplay()
        let desktop = DesktopID(rawValue: 1)
        var state = RoadieState()
        state.ensureDisplay(display.id) // bureau 1 et stage « 1 » en mode bsp
        try state.createStage(id: StageID(rawValue: "2"), name: "Float", mode: .float, in: display.id, desktopID: desktop)
        let tiled = StageScope(displayID: display.id, desktopID: desktop, stageID: StageID(rawValue: "1"))
        let floating = StageScope(displayID: display.id, desktopID: desktop, stageID: StageID(rawValue: "2"))
        var popup = powerWindow(4, x: 700)
        popup.isTileCandidate = false
        let pinned = powerWindow(5, x: 800)
        let pin = PersistentWindowPin(
            windowID: pinned.id,
            homeScope: tiled,
            pinScope: .desktop,
            bundleID: pinned.bundleID,
            title: pinned.title,
            lastFrame: pinned.frame
        )
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [display],
            windows: [
                ScopedWindowSnapshot(window: powerWindow(1, x: 0), scope: tiled),
                ScopedWindowSnapshot(window: powerWindow(2, x: 300), scope: floating),
                ScopedWindowSnapshot(window: powerWindow(3, x: 500), scope: nil),
                ScopedWindowSnapshot(window: popup, scope: nil),
                ScopedWindowSnapshot(window: pinned, scope: tiled, pin: pin),
            ],
            state: state,
            focusedWindowID: nil
        )

        let automation = AutomationSnapshotService(rules: [], stageStore: StageStore(path: tempPath("r3-floating")))
            .snapshot(from: snapshot)
        let floatingByID = Dictionary(uniqueKeysWithValues: automation.windows.map { ($0.id, $0.isFloating) })

        #expect(floatingByID == ["1": false, "2": true, "3": false, "4": true, "5": true])
        for entry in snapshot.windows {
            let expected = LayoutMaintainer.ruleFloatingState(of: entry, in: snapshot.state) ?? false
            #expect(floatingByID[String(entry.window.id.rawValue)] == expected)
        }
    }

    // MARK: - Catalogue d'événements

    @Test
    func eventCatalogListsEventStreamGap() {
        let catalog = AutomationEventCatalog()
        #expect(catalog.contains(EventSubscriptionService.gapEventType))
        #expect(!catalog.isObsolete(EventSubscriptionService.gapEventType))
    }
}

// MARK: - Outils

/// Écran principal (stage 1 : deux fenêtres côte à côte, stage 2 vide) et écran secondaire. État
/// et intents dans un dossier dédié ; journal d'événements à part, pour vérifier qu'aucun
/// événement n'annonce une commande refusée.
private struct R3Fixture {
    let directory: URL
    let main = powerDisplay("display-main", index: 1, x: 0)
    let side = powerDisplay("display-side", index: 2, x: 1000)
    let left: WindowSnapshot
    let right: WindowSnapshot
    let provider: PowerUserProvider
    let writer: PowerUserWriter
    let store: StageStore
    let intentURL: URL
    let eventURL: URL
    let service: SnapshotService
    let events: EventLog

    init(_ name: String, leftFrame: Rect = Rect(x: 0, y: 0, width: 500, height: 800)) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        left = powerWindow(1, x: leftFrame.x, y: leftFrame.y, width: leftFrame.width, height: leftFrame.height)
        right = powerWindow(2, x: 500, y: 0, width: 500, height: 800)
        provider = PowerUserProvider(displays: [main, side], windows: [left, right])
        writer = PowerUserWriter(provider: provider)
        store = StageStore(path: directory.appendingPathComponent("stages.json").path)
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: main.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: left.id, members: [r3Member(left), r3Member(right)]),
                PersistentStage(id: StageID(rawValue: "2")),
            ]),
            PersistentStageScope(displayID: side.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1")),
            ]),
        ], activeDisplayID: main.id))
        intentURL = directory.appendingPathComponent("intents.json")
        eventURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-events-\(UUID().uuidString).jsonl")
        events = EventLog(path: eventURL.path)
        service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(),
            intentStore: LayoutIntentStore(path: intentURL.path),
            stageStore: store
        )
    }

    var windows: WindowCommandService { WindowCommandService(service: service, stageStore: store, events: events) }
    var desktops: DesktopCommandService { DesktopCommandService(service: service, store: store, events: events) }
    var bookmarks: WindowBookmarkCommandService { WindowBookmarkCommandService(service: service, store: store, events: events) }
    var groups: WindowGroupCommandService { WindowGroupCommandService(service: service, store: store, events: events) }
    var displays: DisplayCommandService { DisplayCommandService(service: service, store: store, events: events) }
    var layout: LayoutCommandService { LayoutCommandService(service: service, events: events) }
    var contextActions: WindowContextActions {
        WindowContextActions(snapshotService: service, stageStore: store, eventLog: events, stageLabelsVisible: { false })
    }

    /// Octets de l'état avant la commande, puis dossier en lecture seule : le verrou de l'état
    /// existe déjà, seule l'écriture échoue.
    func lockStateDirectory() throws -> Data {
        let data = try Data(contentsOf: store.fileURL)
        chmod(directory.path, 0o500)
        return data
    }

    var directoryIsReadOnly: Bool { access(directory.path, W_OK) != 0 }

    /// Intents illisibles : toute écriture d'intent est refusée, quel que soit l'utilisateur.
    func corruptIntents() throws -> Data {
        let garbage = Data("{ pas du json".utf8)
        try garbage.write(to: intentURL)
        return garbage
    }

    /// État des stages illisible : toute transaction vérifiée est refusée.
    func corruptStageState() throws -> Data {
        let garbage = Data("{ pas du json".utf8)
        try garbage.write(to: store.fileURL)
        return garbage
    }

    /// Contrat REL-021 : échec annoncé (« failed », code CLI non nul), aucun cadre ni focus AX.
    func expectRefused(_ result: some CommandResult, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(!result.changed, sourceLocation: sourceLocation)
        #expect(result.message.contains("failed"), "\(result.message)", sourceLocation: sourceLocation)
        #expect(result.outcome == .failed, sourceLocation: sourceLocation)
        #expect(CLICommandRouter.actionExitCode(outcome: result.outcome) == 1, sourceLocation: sourceLocation)
        #expect(writer.frames.isEmpty, "\(writer.frames)", sourceLocation: sourceLocation)
        #expect(writer.focused.isEmpty, "\(writer.focused)", sourceLocation: sourceLocation)
    }

    func eventLogContains(_ type: String) -> Bool {
        let text = (try? String(contentsOf: eventURL, encoding: .utf8)) ?? ""
        return text.contains("\"\(type)\"")
    }

    func cleanUp() {
        chmod(directory.path, 0o700)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: eventURL)
    }
}

private func r3Member(_ window: WindowSnapshot) -> PersistentStageMember {
    PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame)
}
