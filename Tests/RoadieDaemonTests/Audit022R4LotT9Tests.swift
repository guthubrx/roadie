import CoreGraphics
import Darwin
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieStages
@testable import RoadieDaemon

/// Session 022, round 4, lot T9 : REL-042 (code de sortie lu sur un statut explicite pour les
/// groupes, largeurs, écrans et signets), `daemon heal` en échec quand les réparations ne sont pas
/// écrites (REL-021) et store injecté pour `group`. Aucun test ne touche à `~/.roadies`.
@MainActor
@Suite(.serialized)
struct Audit022R4LotT9Tests {
    // MARK: - Fixture

    private struct Fixture {
        let directory: URL
        let store: StageStore
        let service: SnapshotService
        let provider: PowerUserProvider

        init(_ name: String, windows: [WindowSnapshot] = [powerWindow(1, x: 100), powerWindow(2, x: 500)], displays: [DisplaySnapshot] = [powerDisplay()]) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            provider = PowerUserProvider(displays: displays, windows: windows)
            store = StageStore(path: directory.appendingPathComponent("stages.json").path)
            service = SnapshotService(
                provider: provider,
                frameWriter: PowerUserWriter(provider: provider),
                config: RoadieConfig(),
                intentStore: LayoutIntentStore(path: directory.appendingPathComponent("intents.json").path),
                stageStore: store,
                events: EventLog(path: directory.appendingPathComponent("events.jsonl").path),
                persistStateChanges: false
            )
        }

        @MainActor func router() -> CLICommandRouter {
            let service = service
            return CLICommandRouter(makeService: { _ in service })
        }

        func cleanUp() {
            chmod(directory.path, 0o700)
            try? FileManager.default.removeItem(at: directory)
        }

        func groups() -> [WindowGroup] {
            store.state().scopes.flatMap(\.stages).flatMap(\.groups)
        }
    }

    // MARK: - Groupes

    /// Avant la correction : `group` écrivait dans le store par défaut (`~/.roadies`), pas dans celui du service.
    @Test
    func groupCommandsUseTheServiceStore() throws {
        let fixture = try Fixture("t9-group-store")
        defer { fixture.cleanUp() }
        let router = fixture.router()

        #expect(router.run(["group", "create", "demo", "1", "2"]).exitCode == 0)
        #expect(fixture.groups().map(\.id) == ["demo"])
        #expect(router.run(["group", "list"]).stdout.contains("demo"))
        #expect(router.run(["group", "dissolve", "demo"]).exitCode == 0)
        #expect(fixture.groups().isEmpty)
    }

    /// Sans écran, `group` n'a pas de scope actif : action sans objet (0), même si l'identifiant porte un mot d'échec.
    @Test
    func groupNoOpWithFailureWordsInIdentifierExitsZero() throws {
        let fixture = try Fixture("t9-group-noop", windows: [], displays: [])
        defer { fixture.cleanUp() }
        let router = fixture.router()

        for id in ["failed", "not found", "unknown", "requires", "unavailable", "must x", "demo"] {
            let response = router.run(["group", "create", id, "1"])
            #expect(response.exitCode == 0, "\(id): \(response)")
            #expect(response.stdout.contains("no active scope"), "\(id)")
        }
    }

    @Test
    func groupRealFailuresKeepExitCodeOne() throws {
        let fixture = try Fixture("t9-group-fail")
        defer { fixture.cleanUp() }
        let router = fixture.router()

        // Groupe introuvable : échec, quel que soit l'identifiant.
        for id in ["ghost", "failed"] {
            #expect(router.run(["group", "dissolve", id]).exitCode == 1, "dissolve \(id)")
            #expect(router.run(["group", "remove", id, "1"]).exitCode == 1, "remove \(id)")
            #expect(router.run(["group", "focus", id, "1"]).exitCode == 1, "focus \(id)")
        }
        // Écriture d'état refusée : échec.
        try Data("{ pas du json".utf8).write(to: fixture.store.fileURL)
        #expect(router.run(["group", "create", "demo", "1"]).exitCode == 1)
        #expect(router.run(["group", "dissolve", "demo"]).exitCode == 1)
    }

    @Test
    func groupResultsCarryExplicitOutcome() throws {
        let fixture = try Fixture("t9-group-outcome")
        defer { fixture.cleanUp() }
        let groups = WindowGroupCommandService(service: fixture.service, store: fixture.store, events: EventLog(path: tempPath("t9-group-events")))

        #expect(groups.list().outcome == .noOp)
        #expect(groups.create(id: "failed", windowIDs: [WindowID(rawValue: 1)]).outcome == .changed)
        // Création répétée : l'identifiant « failed » ne change rien au statut.
        #expect(groups.create(id: "failed", windowIDs: [WindowID(rawValue: 1)]).outcome == .changed)
        #expect(groups.dissolve(id: "failed").outcome == .changed)
        #expect(groups.dissolve(id: "failed").outcome == .failed)
    }

    // MARK: - Largeur

    @Test
    func widthResultsCarryExplicitOutcome() throws {
        let fixture = try Fixture("t9-width", windows: [])
        defer { fixture.cleanUp() }
        let width = WidthAdjustmentService(service: fixture.service, config: RoadieConfig(), events: EventLog(path: tempPath("t9-width-events")))

        let empty = width.apply(WidthAdjustmentIntent(scope: .activeWindow, mode: .presetNext))
        #expect(empty.message == "width: no active tiled window")
        #expect(empty.outcome == .noOp)

        let applied = try Fixture("t9-width-ok", windows: [powerWindow(1, x: 0, y: 0, width: 300, height: 300)])
        defer { applied.cleanUp() }
        let result = WidthAdjustmentService(service: applied.service, config: RoadieConfig(), events: EventLog(path: tempPath("t9-width-ok-events")))
            .apply(WidthAdjustmentIntent(scope: .activeWindow, mode: .explicitRatio, targetRatio: 0.5))
        #expect(result.changed)
        #expect(result.outcome == .changed)
    }

    @Test
    func widthRouterUsageErrorsExitOne() throws {
        let fixture = try Fixture("t9-width-usage", windows: [])
        defer { fixture.cleanUp() }
        let router = fixture.router()

        #expect(router.run(["layout", "width"]).exitCode == 1)
        #expect(router.run(["layout", "width", "bogus"]).exitCode == 1)
        #expect(router.run(["layout", "width", "ratio", "abc"]).exitCode == 1)
        // Sans fenêtre : action sans objet.
        #expect(router.run(["layout", "width", "next"]).exitCode == 0)
    }

    // MARK: - Écran

    @Test
    func displayFocusExitCodes() throws {
        let fixture = try Fixture("t9-display")
        defer { fixture.cleanUp() }
        let router = fixture.router()

        #expect(router.run(["display", "focus", "9"]).exitCode == 1)
        // Un seul écran : aucun voisin, action sans objet.
        let none = router.run(["display", "focus", "right"])
        #expect(none.exitCode == 0, "\(none)")
        #expect(none.stdout.contains("no display"))
        #expect(router.run(["display", "focus", "1"]).exitCode == 0)
    }

    // MARK: - Signets

    @Test
    func bookmarkUserNamesWithFailureWordsNeverDecideTheExitCode() throws {
        let fixture = try Fixture("t9-bookmark-noop", windows: [], displays: [])
        defer { fixture.cleanUp() }
        let router = fixture.router()

        // Aucune fenêtre active : action sans objet (0) pour tout nom.
        for name in ["failed", "not-found", "unknown", "demo"] {
            let response = router.run(["bookmark", "set", name])
            #expect(response.exitCode == 0, "\(name): \(response)")
        }
        #expect(router.run(["bookmark", "list"]).exitCode == 0)
    }

    @Test
    func bookmarkRealFailuresKeepExitCodeOne() throws {
        let fixture = try Fixture("t9-bookmark-fail")
        defer { fixture.cleanUp() }
        let router = fixture.router()

        for name in ["demo", "failed"] {
            #expect(router.run(["bookmark", "focus", name]).exitCode == 1, "focus \(name)")
            #expect(router.run(["bookmark", "clear", name]).exitCode == 1, "clear \(name)")
        }
        #expect(router.run(["bookmark", "set", "work"]).exitCode == 0)
        #expect(router.run(["bookmark", "clear", "work"]).exitCode == 0)
    }

    // MARK: - Code de sortie

    @Test
    func exitCodeIsReadFromOutcomeOnly() {
        #expect(CLICommandRouter.actionExitCode(outcome: .failed) == 1)
        #expect(CLICommandRouter.actionExitCode(outcome: .noOp) == 0)
        #expect(CLICommandRouter.actionExitCode(outcome: .changed) == 0)
        #expect(CLICommandRouter.actionExitCode(outcome: nil) == 0)
        // Un succès sans effet dont le texte porte des mots d'échec (valeur utilisateur).
        let result = WindowGroupCommandResult.noChange("group failed not found unknown: no active scope")
        #expect(CLICommandRouter.actionExitCode(outcome: result.outcome) == 0)
    }

    // MARK: - daemon heal

    private func okAudit() -> StateAuditReport {
        StateAuditReport(checks: [StateAuditCheck(level: .ok, name: "active-display", message: "ok")])
    }

    @Test
    func healReportFailsWhenRepairsWereNotWritten() {
        let notWritten = StateHealReport(repaired: 0, audit: okAudit(), persistenceError: "state heal: failed, disk")
        #expect(!notWritten.audit.failed)
        let report = DaemonHealReport(state: notWritten, layout: .empty, health: DaemonHealthReport(checks: []))
        #expect(report.failed)

        let written = StateHealReport(repaired: 1, audit: okAudit())
        #expect(!DaemonHealReport(state: written, layout: .empty, health: DaemonHealthReport(checks: [])).failed)
    }

    /// Bout en bout : état sans écran actif et dossier non inscriptible, la réparation n'est pas écrite.
    @Test
    func daemonHealExitsOneWhenRepairCannotBeWritten() throws {
        let fixture = try Fixture("t9-heal-unwritable")
        defer { fixture.cleanUp() }
        fixture.store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: DisplayID(rawValue: "display-main"), activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1")),
            ]),
        ], activeDisplayID: nil))
        chmod(fixture.directory.path, 0o500)
        guard access(fixture.directory.path, W_OK) != 0 else { return }

        let heal = DaemonHealthService(
            service: fixture.service,
            stageStore: fixture.store,
            events: EventLog(path: tempPath("t9-heal-events")),
            pidFilePath: tempPath("t9-heal-pid"),
            statusPath: tempPath("t9-heal-status"),
            componentRegistry: { [] }
        ).heal()

        #expect(heal.state.persistenceError != nil, "\(heal.state)")
        #expect(!heal.state.audit.failed)
        #expect(heal.failed)
    }
}
