import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

/// SPEC-023 T013, T016, T020, T021 (lanceur) : exécution des commandes de la boîte. Routeur réel sur
/// un fournisseur factice ; état des stages, historique, journal et configuration en dossiers temporaires.
@MainActor
@Suite(.serialized)
struct SlashCommandRunnerTests {
    private static let display = DisplayID(rawValue: "display-main")

    /// Environnement d'un test : les routeurs créés partagent fournisseur, écrivain et état des stages.
    @MainActor
    private final class Fixture {
        let provider: PowerUserProvider
        let writer: PowerUserWriter
        let stageStore = StageStore(path: tempPath("slash-stages"))
        let eventsPath = tempPath("slash-events")
        let historyURL = URL(fileURLWithPath: tempPath("slash-history"))
        let configPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("slash-config-\(UUID().uuidString)/roadies.toml").path
        private(set) var routersMade = 0

        init(windows: [WindowSnapshot] = [powerWindow(1, x: 0)], stages: [PersistentStage]? = nil, active: String = "1") {
            provider = PowerUserProvider(windows: windows)
            writer = PowerUserWriter(provider: provider)
            if let stages {
                stageStore.save(PersistentStageState(
                    scopes: [PersistentStageScope(displayID: SlashCommandRunnerTests.display, activeStageID: StageID(rawValue: active), stages: stages)],
                    activeDisplayID: SlashCommandRunnerTests.display
                ))
            }
        }

        lazy var settings = SettingsService(configPath: configPath, eventLog: EventLog(path: eventsPath), afterWrite: {})

        func runner() -> SlashCommandRunner {
            SlashCommandRunner(
                makeRouter: { [unowned self] in
                    routersMade += 1
                    return CLICommandRouter(makeService: { [provider, writer, stageStore, eventsPath] _ in
                        SnapshotService(
                            provider: provider,
                            frameWriter: writer,
                            config: RoadieConfig(),
                            intentStore: LayoutIntentStore(path: tempPath("slash-intents")),
                            stageStore: stageStore,
                            events: EventLog(path: eventsPath),
                            persistStateChanges: false
                        )
                    })
                },
                settings: settings,
                history: CommandHistoryStore(url: historyURL),
                stageStore: { [stageStore] in stageStore },
                eventLog: EventLog(path: eventsPath)
            )
        }

        /// Lanceur dont le routeur est remplacé par une réponse fixe (commandes qui lisent l'état réel).
        func runner(route: @escaping @MainActor ([String]) -> CLIResponse) -> SlashCommandRunner {
            SlashCommandRunner(
                route: route, settings: settings, history: CommandHistoryStore(url: historyURL),
                stageStore: { [stageStore] in stageStore }, eventLog: EventLog(path: eventsPath))
        }

        var events: String { (try? String(contentsOfFile: eventsPath, encoding: .utf8)) ?? "" }
        var configText: String { (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? "" }
        var scope: PersistentStageScope? { stageStore.state().scopes.first { $0.displayID == SlashCommandRunnerTests.display } }
    }

    private static func stage(_ id: String, _ name: String) -> PersistentStage {
        PersistentStage(id: StageID(rawValue: id), name: name)
    }

    private static func isDone(_ outcome: SlashOutcome) -> Bool {
        if case .done = outcome { return true }
        return false
    }

    private static func failure(_ outcome: SlashOutcome) -> SlashError? {
        if case .failed(let error) = outcome { return error }
        return nil
    }

    // MARK: - Commandes du routeur (T013)

    @Test
    func fullAndMaxReachTheRouter() {
        let fixture = Fixture()
        let runner = fixture.runner()
        #expect(Self.isDone(runner.execute("full")))
        #expect(fixture.writer.nativeFullscreen == [WindowID(rawValue: 1)])
        let max = runner.execute("max")
        #expect(Self.isDone(max), "\(max)")
        #expect(fixture.routersMade == 2)
    }

    @Test
    func noActiveWindowIsTranslated() {
        let fixture = Fixture(windows: [])
        let outcome = fixture.runner().execute("full")
        // L'échec porte la forme attendue de la commande (T031 c).
        #expect(outcome == .failed(SlashError(message: "Aucune fenêtre active.", usage: "/full")))
        #expect(fixture.events.contains("no_active_window"))
    }

    @Test
    func stageSwitchesByNumberAndByName() {
        let fixture = Fixture(stages: [Self.stage("1", "Main"), Self.stage("2", "Dev"), Self.stage("3", "Café")])
        let runner = fixture.runner()

        #expect(Self.isDone(runner.execute("stage 2")))
        #expect(fixture.scope?.activeStageID.rawValue == "2")
        // Nom insensible à la casse et aux accents, alias `s`.
        #expect(Self.isDone(runner.execute("s CAFE")))
        #expect(fixture.scope?.activeStageID.rawValue == "3")
        #expect(Self.isDone(runner.execute("stage main")))
        #expect(fixture.scope?.activeStageID.rawValue == "1")
    }

    @Test
    func unknownOrAmbiguousStageNameIsRefusedWithoutRouter() throws {
        let fixture = Fixture(stages: [Self.stage("1", "Main"), Self.stage("2", "Web"), Self.stage("4", "web")])
        let runner = fixture.runner()

        let unknown = try #require(Self.failure(runner.execute("stage inconnu")))
        #expect(unknown.message == "Stage inconnu : inconnu.")
        let ambiguous = try #require(Self.failure(runner.execute("stage web")))
        #expect(ambiguous.message.contains("2 (Web)"))
        #expect(ambiguous.message.contains("4 (web)"))
        #expect(fixture.routersMade == 0)
        #expect(fixture.scope?.activeStageID.rawValue == "1")
        #expect(fixture.events.contains("stage_not_found"))
        #expect(fixture.events.contains("stage_ambiguous"))
        #expect(!fixture.events.contains("inconnu"))
    }

    @Test
    func stageNewTakesSmallestFreeIdentifier() {
        let fixture = Fixture(stages: [Self.stage("1", "Main"), Self.stage("2", "Dev"), Self.stage("4", "Mail")])
        #expect(Self.isDone(fixture.runner().execute("stage new Notes")))
        #expect(fixture.scope?.stages.first { $0.id.rawValue == "3" }?.name == "Notes")
    }

    @Test
    func stageRenameTargetsCurrentStage() {
        let fixture = Fixture(stages: [Self.stage("1", "Main"), Self.stage("2", "Dev")], active: "2")
        #expect(Self.isDone(fixture.runner().execute("stage rename Perso")))
        #expect(fixture.scope?.stages.map(\.name) == ["Main", "Perso"])
    }

    /// T038 : effet réel des commandes de direction (vrai routeur, faux fournisseur), pas seulement l'argv.
    @Test
    func moveAndSwapExchangeNeighborFrames() {
        let move = Fixture(windows: [powerWindow(1, x: 0), powerWindow(2, x: 500)])
        let first = move.runner().execute("move droite")
        #expect(Self.isDone(first), "\(first)")
        let one = WindowID(rawValue: 1)
        let two = WindowID(rawValue: 2)
        // Les deux fenêtres ont changé d'emplacement : la fenêtre 1 n'est plus à gauche de la fenêtre 2.
        let movedOne = move.writer.frames[one]
        let movedTwo = move.writer.frames[two]
        #expect(movedOne != nil && movedTwo != nil)
        #expect((movedOne?.x ?? 0) > (movedTwo?.x ?? 0))

        let swap = Fixture(windows: [powerWindow(1, x: 0), powerWindow(2, x: 500)])
        let second = swap.runner().execute("swap right")
        #expect(Self.isDone(second), "\(second)")
        #expect((swap.writer.frames[one]?.x ?? 0) > (swap.writer.frames[two]?.x ?? 0))
    }

    @Test
    func moveWithoutNeighborKeepsTranslatedMessage() {
        let fixture = Fixture()
        // Le routeur sort avec 0 : sans cela, la boîte se fermerait sans rien dire (échec silencieux).
        #expect(fixture.runner().execute("move gauche") == .failed(SlashError(
            message: "Aucune fenêtre voisine à gauche.", usage: "/move gauche|droite|haut|bas")))
        #expect(fixture.writer.frames.isEmpty)
        #expect(fixture.runner().loadHistory().isEmpty)
    }

    @Test
    func resizeWritesANewFrame() {
        let fixture = Fixture(windows: [powerWindow(1, x: 0), powerWindow(2, x: 500)])
        let before = fixture.provider.snapshots.first { $0.id == WindowID(rawValue: 1) }?.frame
        let outcome = fixture.runner().execute("resize droite")
        #expect(Self.isDone(outcome), "\(outcome)")
        let after = fixture.writer.frames[WindowID(rawValue: 1)]
        #expect(after != nil)
        #expect(after != before)
    }

    @Test
    func translatedKnownRouterMessagesOnly() {
        #expect(SlashCommandRunner.translated("unknown display 4") == "Écran inconnu : 4.")
        #expect(SlashCommandRunner.translated("no neighbor up") == "Aucune fenêtre voisine au-dessus.")
        #expect(SlashCommandRunner.translated("toggle maximize: failed, window unavailable for tiling") == "Cette fenêtre ne peut pas être tuilée.")
        #expect(SlashCommandRunner.translated("stage switch: unknown display") == "Écran inconnu.")
        #expect(SlashCommandRunner.translated("bookmark set a: window=1") == "bookmark set a: window=1")
    }

    @Test
    func screenWithoutOtherDisplayIsTranslated() {
        let fixture = Fixture()
        let outcome = fixture.runner().execute("screen droite")
        #expect(outcome == .failed(SlashError(message: "Il n'y a pas d'autre écran.", usage: "/screen gauche|droite|haut|bas|N")))
    }

    @Test
    func layoutAndBalanceReachTheRouter() {
        let fixture = Fixture(stages: [Self.stage("1", "Main")])
        let runner = fixture.runner()
        #expect(Self.isDone(runner.execute("layout float")))
        #expect(fixture.scope?.stages.first?.mode == .float)
        #expect(Self.isDone(runner.execute("balance")))
    }

    @Test
    func bookmarkCommandsKeepRouterMessages() throws {
        let fixture = Fixture()
        let runner = fixture.runner()
        let set = runner.execute("bm set a")
        guard case .done(let message) = set else {
            Issue.record("expected done, got \(set)")
            return
        }
        #expect(message.first?.hasPrefix("bookmark set a") == true)
        // Bookmark absent : message du routeur traduit, avec la forme attendue.
        let jump = try #require(Self.failure(runner.execute("b zz")))
        #expect(jump.message == "Bookmark introuvable : zz.")
        #expect(jump.usage == "/bm nom|set nom")
    }

    @Test
    func twoCommandsShareNoBuffer() {
        let fixture = Fixture()
        let runner = fixture.runner()
        #expect(Self.failure(runner.execute("bm zz")) != nil)
        let balance = runner.execute("balance")
        guard case .done(let message) = balance else {
            Issue.record("expected done, got \(balance)")
            return
        }
        #expect(!message.joined().contains("not found"))
        #expect(fixture.routersMade == 2)
    }

    /// `heal` et `config reload` lisent l'état réel : routeur remplacé, argv vérifiés. Comme `doctor`,
    /// leur résultat s'affiche dans la boîte ; un échec du routeur reste un échec (T040).
    @Test
    func healAndReloadAreShownInTheBox() {
        let fixture = Fixture()
        var seen: [[String]] = []
        let runner = fixture.runner { argv in
            seen.append(argv)
            return argv == ["daemon", "heal"]
                // Forme réelle de `daemon heal` (Formatters.daemonHeal) : `status=ok` n'est pas un refus de rechargement.
                ? CLIResponse(exitCode: 0, stdout: "status=ok\nstateRepaired=0\nhealthFailed=false\n")
                : CLIResponse(exitCode: 0, stdout: "status=applied\n")
        }
        #expect(runner.execute("heal") == .info(["status=ok", "stateRepaired=0", "healthFailed=false"]))
        #expect(runner.execute("reload") == .info(["Configuration rechargée."]))
        #expect(seen == [["daemon", "heal"], ["config", "reload"]])
        #expect(runner.loadHistory() == ["heal", "reload"])
    }

    @Test
    func doctorStatusLineIsNotTranslatedAsAReloadRefusal() {
        let fixture = Fixture()
        let runner = fixture.runner { _ in CLIResponse(exitCode: 0, stdout: "status=needs-attention\nwarn\tcheck\tmessage\n") }
        #expect(runner.execute("doctor") == .info(["status=needs-attention", "warn\tcheck\tmessage"]))
    }

    @Test
    func failedHealIsAFailureWithUsageAndNoHistory() {
        let fixture = Fixture()
        let runner = fixture.runner { _ in CLIResponse(exitCode: 1, stderr: "roadie: daemon injoignable\n") }
        #expect(runner.execute("heal") == .failed(SlashError(message: "roadie: daemon injoignable", usage: "/heal")))
        #expect(runner.loadHistory().isEmpty)
        #expect(fixture.events.contains("command.rejected"))
        #expect(fixture.events.contains("router_failed"))
        #expect(!fixture.events.contains("injoignable"))
    }

    @Test
    func refusedReloadIsAFailureWithTheConfigError() {
        let fixture = Fixture()
        let runner = fixture.runner { _ in
            CLIResponse(exitCode: 1, stdout: "status=failed_keeping_previous\nerror=ligne 3 invalide\n")
        }
        #expect(runner.execute("reload") == .failed(SlashError(message: "Rechargement refusé : ligne 3 invalide", usage: "/reload")))
        #expect(runner.loadHistory().isEmpty)
        // Même avec le code 0, un `status=` autre que `applied` n'est pas un succès.
        let zero = fixture.runner { _ in CLIResponse(exitCode: 0, stdout: "status=failed\nerror=refus\n") }
        #expect(zero.execute("reload") == .failed(SlashError(message: "Rechargement refusé : refus", usage: "/reload")))
    }

    @Test
    func failedDoctorStaysInfo() {
        let fixture = Fixture()
        let runner = fixture.runner { _ in CLIResponse(exitCode: 1, stdout: "daemon: KO\n") }
        #expect(runner.execute("doctor") == .info(["daemon: KO"]))
    }

    @Test
    func unknownCommandChangesNothingAndLogsNoInput() {
        let fixture = Fixture(stages: [Self.stage("1", "Main")])
        let before = fixture.stageStore.state()
        let runner = fixture.runner()

        let outcome = runner.execute("frobnicate secret")
        #expect(Self.failure(outcome) != nil)
        #expect(fixture.routersMade == 0)
        #expect(fixture.stageStore.state() == before)
        #expect(fixture.events.contains("command.rejected"))
        #expect(fixture.events.contains("unknown_command"))
        #expect(!fixture.events.contains("frobnicate"))
        #expect(!fixture.events.contains("secret"))
        #expect(runner.loadHistory().isEmpty)

        // Commande connue, arguments faux : le nom est journalisé, pas les arguments.
        #expect(Self.failure(runner.execute("move nulle-part")) != nil)
        #expect(fixture.events.contains("\"command\":\"move\""))
        #expect(fixture.events.contains("invalid_arguments"))
        #expect(!fixture.events.contains("nulle-part"))
    }

    // MARK: - Commandes différées et d'information (T016)

    @Test
    func deferredCommandsAreReturnedWithoutRunning() {
        let fixture = Fixture()
        let runner = fixture.runner()
        #expect(runner.execute("grid") == .deferred(argv: ["grid", "interactive", "--scope", "display"]))
        #expect(runner.execute("grid fenêtre") == .deferred(argv: ["grid", "interactive", "--scope", "focused_window"]))
        #expect(runner.execute("letters") == .deferred(argv: ["targets", "interactive", "--source", "all", "--include-app-targets"]))
        #expect(runner.execute("restart") == .deferred(argv: ["daemon", "restart"]))
        #expect(fixture.routersMade == 0)

        // L'appelant exécute ensuite l'action, sur une nouvelle instance du routeur.
        #expect(runner.runDeferred(["balance"]).exitCode == 0)
        #expect(fixture.routersMade == 1)
        #expect(!fixture.events.contains("command.deferred_failed"))
    }

    /// T037 : l'échec d'une action différée est journalisé avec le nom de la commande et le code,
    /// jamais les arguments.
    @Test
    func failedDeferredActionIsLoggedWithoutArguments() {
        let fixture = Fixture()
        let runner = fixture.runner { _ in CLIResponse(exitCode: 3, stderr: "roadie: échec secret-detail\n") }

        let response = runner.runDeferred(["grid", "interactive", "--scope", "secret-scope"])

        #expect(response.exitCode == 3)
        #expect(fixture.events.contains("command.deferred_failed"))
        #expect(fixture.events.contains("\"command\":\"grid\""))
        #expect(fixture.events.contains("\"code\":\"3\""))
        #expect(!fixture.events.contains("secret"))
        #expect(!fixture.events.contains("interactive"))
    }

    @Test
    func doctorIsShownInTheBoxAndTruncated() {
        let fixture = Fixture()
        let lines = (1...20).map { "ligne \($0)" }
        let runner = fixture.runner { _ in CLIResponse(exitCode: 0, stdout: lines.joined(separator: "\n") + "\n") }

        guard case .info(let long) = runner.execute("doctor") else {
            Issue.record("expected info")
            return
        }
        #expect(long.count == 12)
        #expect(long[10] == "ligne 11")
        #expect(long[11] == "… 9 lignes cachées")

        let short = fixture.runner { _ in CLIResponse(exitCode: 0, stdout: "ligne 1\nligne 2\n") }
        #expect(short.execute("doctor") == .info(["ligne 1", "ligne 2"]))
    }

    @Test
    func settingsOpensRequestedCategory() {
        let runner = Fixture().runner()
        #expect(runner.execute("settings grille") == .openSettings(category: .grille))
        #expect(runner.execute("settings") == .openSettings(category: nil))
    }

    // MARK: - Réglages (T020)

    @Test
    func setWritesReadsRefusesAndResets() throws {
        let fixture = Fixture()
        let runner = fixture.runner()

        // Les 9 caractères par défaut ne couvrent pas 4 × 3 cases : le validateur refuse, fichier intact.
        let tooFewHints = try #require(Self.failure(runner.execute("set target_grid.rows 4")))
        #expect(tooFewHints.message.contains("hint_characters"))
        #expect(fixture.configText.isEmpty)
        #expect(runner.execute("set target_grid.hint_characters azertyuiopqsdfgh") == .info(["target_grid.hint_characters = azertyuiopqsdfgh"]))
        #expect(runner.execute("set target_grid.rows 4") == .info(["target_grid.rows = 4"]))
        #expect(fixture.configText.contains("rows = 4"))

        guard case .info(let read) = runner.execute("set target_grid.rows") else {
            Issue.record("expected info")
            return
        }
        #expect(read == ["target_grid.rows = 4 (défaut 3, de 2 à 12)"])

        let before = fixture.configText
        let refused = try #require(Self.failure(runner.execute("set target_grid.rows 99")))
        #expect(refused.message.contains("de 2 à 12"))
        #expect(fixture.configText == before)

        #expect(runner.execute("set target_grid.rows défaut") == .info(["target_grid.rows = 3"]))
        let descriptor = try #require(SettingsCatalog.find(id: "target_grid.rows"))
        #expect(fixture.settings.value(of: descriptor).isDefault)
        #expect(!fixture.events.contains("\"99\""))
    }

    @Test
    func homonymSettingsStayIndependent() throws {
        let fixture = Fixture()
        let runner = fixture.runner()
        #expect(runner.execute("set target_mode.enabled non") == .info(["target_mode.enabled = false"]))
        #expect(runner.execute("set app_targets.enabled oui") == .info(["app_targets.enabled = true"]))
        let targetMode = try #require(SettingsCatalog.find(id: "target_mode.enabled"))
        let appTargets = try #require(SettingsCatalog.find(id: "app_targets.enabled"))
        #expect(fixture.settings.value(of: targetMode).value == .bool(false))
        #expect(fixture.settings.value(of: appTargets).value == .bool(true))
        #expect(runner.execute("set target_mode.label_font_size 20") == .info(["target_mode.label_font_size = 20"]))
    }

    @Test
    func setWithoutNameListsCategoriesAndUnknownNameSuggests() throws {
        let fixture = Fixture()
        let runner = fixture.runner()
        guard case .info(let categories) = runner.execute("set") else {
            Issue.record("expected info")
            return
        }
        #expect(categories.count == SettingCategory.allCases.count)
        #expect(categories.contains("grille - Grille"))

        let unknown = try #require(Self.failure(runner.execute("set target_grid.rowz 4")))
        #expect(unknown.message == "Réglage inconnu : target_grid.rowz.")
        #expect(unknown.suggestion == "target_grid.rows")
        #expect(fixture.configText.isEmpty)
        #expect(Self.failure(runner.execute("set target_grid.rowz"))?.suggestion == "target_grid.rows")
    }

    // MARK: - Historique et contexte (T021, partie lanceur)

    @Test
    func historyKeepsSuccessfulCommandsOnly() {
        let fixture = Fixture(stages: [Self.stage("1", "Main")])
        let runner = fixture.runner()
        _ = runner.execute("balance")
        _ = runner.execute("frobnicate")
        _ = runner.execute(" balance ")
        _ = runner.execute("grid")
        #expect(runner.loadHistory() == ["balance", "grid"])
        // Relu par une nouvelle instance (redémarrage).
        #expect(CommandHistoryStore(url: fixture.historyURL).load() == ["balance", "grid"])
    }

    @Test
    func historyKeepsFiftyEntries() {
        let store = CommandHistoryStore(url: URL(fileURLWithPath: tempPath("slash-history-max")))
        for index in 1...51 { store.append("stage \(index)") }
        store.append("stage 51")
        let history = store.load()
        #expect(history.count == 50)
        #expect(history.first == "stage 2")
        #expect(history.last == "stage 51")
    }

    @Test
    func contextListsCurrentStagesAndBookmarks() {
        let fixture = Fixture(stages: [Self.stage("1", "Main"), Self.stage("2", "Dev")])
        fixture.stageStore.mutate { state in
            state.windowBookmarks = [PersistentWindowBookmark(
                name: "mail", windowID: WindowID(rawValue: 1),
                scope: StageScope(displayID: Self.display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1")),
                bundleID: "app.1", title: "Window 1", frame: Rect(x: 0, y: 0, width: 10, height: 10))]
        }
        #expect(fixture.runner().context() == SlashContext(stageNames: ["Main", "Dev"], bookmarkNames: ["mail"], stageNumbers: ["1", "2"]))
    }
}
