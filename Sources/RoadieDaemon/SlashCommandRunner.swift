import Foundation
import RoadieCore

/// Résultat d'une commande de la boîte (SPEC-023), interprété par la session de recherche.
public enum SlashOutcome: Equatable, Sendable {
    /// Succès : la boîte se ferme (message court éventuel).
    case done(message: [String])
    /// Résultat affiché dans la boîte, qui reste ouverte (`/doctor`, `/set nom`, `/set`).
    case info([String])
    /// Échec : la boîte reste ouverte, message et usage.
    case failed(SlashError)
    /// À exécuter par l'appelant après la fermeture de la boîte (`/grid`, `/letters`, `/restart`).
    case deferred(argv: [String])
    /// L'appelant ouvre la fenêtre de réglages après la fermeture de la boîte.
    case openSettings(category: SettingCategory?)
}

/// Historique persistant des commandes réussies (research R9) : la plus récente en dernier.
public struct CommandHistoryStore: Sendable {
    public static let maxEntries = 50
    private let url: URL

    public init(url: URL = URL(fileURLWithPath: NSString(string: "~/.local/state/roadies/command-history.json").expandingTildeInPath)) {
        self.url = url
    }

    public func load() -> [String] {
        JSONPersistence.load([String].self, from: url, default: [])
    }

    /// Doublon consécutif ignoré ; 50 entrées au plus. O(n), n <= 50.
    public func append(_ command: String) {
        guard !command.isEmpty else { return }
        JSONPersistence.mutate([String].self, at: url, default: [], label: "command history") { history in
            guard history.last != command else { return }
            history = Array((history + [command]).suffix(Self.maxEntries))
        }
    }
}

/// Lanceur des commandes de la boîte (research R1, R2, R10, R11). Analyse par `SlashCommandCatalog`,
/// exécution par une nouvelle instance de `CLICommandRouter` à chaque commande (aucun tampon partagé).
/// Le lanceur ne fige aucune fenêtre : le routeur lit le focus au moment de l'exécution (FR-004).
@MainActor
public final class SlashCommandRunner {
    /// Nombre de lignes d'un résultat affiché dans la boîte, ligne « lignes cachées » comprise.
    static let maxInfoLines = 12

    private let route: @MainActor ([String]) -> CLIResponse
    private let settings: SettingsService
    private let history: CommandHistoryStore
    private let stageStore: () -> StageStore
    private let eventLog: EventLog

    public convenience init(
        makeRouter: @escaping @MainActor () -> CLICommandRouter = { CLICommandRouter() },
        settings: SettingsService = .shared,
        history: CommandHistoryStore = CommandHistoryStore(),
        stageStore: @escaping () -> StageStore = { StageStore() },
        eventLog: EventLog? = nil
    ) {
        self.init(route: { makeRouter().run($0) }, settings: settings, history: history, stageStore: stageStore, eventLog: eventLog)
    }

    /// `route` : point d'injection des tests pour les commandes qui lisent l'état réel (`doctor`, `heal`, `config reload`).
    init(
        route: @escaping @MainActor ([String]) -> CLIResponse,
        settings: SettingsService,
        history: CommandHistoryStore,
        stageStore: @escaping () -> StageStore,
        eventLog: EventLog?
    ) {
        self.route = route
        self.settings = settings
        self.history = history
        self.stageStore = stageStore
        self.eventLog = eventLog ?? EventLog()
    }

    // MARK: - API

    /// Saisie sans le `/`. Analyse, exécute, journalise un refus et enregistre l'historique après un succès.
    public func execute(_ input: String) -> SlashOutcome {
        let command = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = Self.commandName(command)
        let outcome: SlashOutcome
        switch SlashCommandCatalog.parse(command) {
        case .failure(let error):
            outcome = reject(name ?? "unknown", name == nil ? "unknown_command" : "invalid_arguments", error)
        case .success(let invocation):
            outcome = run(invocation, command: name ?? "unknown")
        }
        if case .failed = outcome { return outcome }
        history.append(command)
        return outcome
    }

    /// Action différée, appelée par l'intégration après la fermeture de la boîte (la boîte est déjà
    /// fermée : aucun message ne peut y être affiché). Un échec est journalisé (R10) : nom de la
    /// commande (premier mot de l'argv) et code de sortie, jamais les arguments.
    @discardableResult
    public func runDeferred(_ argv: [String]) -> CLIResponse {
        let response = route(argv)
        if response.exitCode != 0 {
            eventLog.append(RoadieEvent(
                type: "command.deferred_failed",
                details: ["command": argv.first ?? "unknown", "code": String(response.exitCode)]))
        }
        return response
    }

    /// Noms de stages de l'espace courant (tous si l'espace courant est inconnu) et de bookmarks.
    public func context() -> SlashContext {
        let state = stageStore().state()
        let stages = Self.currentStages(in: state).stages
        var seen = Set<String>()
        let names = stages.map(\.name).filter { seen.insert($0).inserted }
        let numbers = Set(stages.compactMap { Int($0.id.rawValue) }).sorted().map(String.init)
        return SlashContext(stageNames: names, bookmarkNames: state.windowBookmarks.map(\.name), stageNumbers: numbers)
    }

    public func loadHistory() -> [String] {
        history.load()
    }

    // MARK: - Exécution

    private func run(_ invocation: SlashInvocation, command: String) -> SlashOutcome {
        switch invocation {
        case .router(let argv):
            return routed(argv, command: command)
        case .routerInfo(let argv):
            return routedInfo(argv, command: command)
        case .routerDeferred(let argv):
            return .deferred(argv: argv)
        case .stageSwitchByName(let name):
            switch resolveStage(named: name) {
            case .success(let id): return routed(["stage", "switch", id], command: command)
            case .failure(let error): return reject(command, error.code, error.error)
            }
        case .stageCreate(let name):
            let id = Self.smallestFreeID(Self.currentStages(in: stageStore().state()).stages)
            return routed(["stage", "create", id] + (name.map { [$0] } ?? []), command: command)
        case .stageRename(let name):
            guard let id = Self.currentStages(in: stageStore().state()).active else {
                return reject(command, "no_current_stage", SlashError(message: "Stage courant inconnu.", usage: Self.usage("stage")))
            }
            return routed(["stage", "rename", id, name], command: command)
        case .openSettings(let category):
            return .openSettings(category: category)
        case .setting(let request):
            return setting(request, command: command)
        }
    }

    /// Exécution par le routeur. Certains échecs sortent avec le code 0 (« no active window »,
    /// « display focus right: no display ») : ils sont reconnus à leur texte. Tout échec porte la
    /// forme attendue de la commande (`usage`). O(l), l = taille de la réponse.
    private func routed(_ argv: [String], command: String) -> SlashOutcome {
        let response = route(argv)
        let stdout = response.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = response.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = "\(stdout)\n\(stderr)"
        let usage = Self.usage(command)
        if text.contains("no active window") || text.contains("no active tiled window") {
            return reject(command, "no_active_window", SlashError(message: "Aucune fenêtre active.", usage: usage))
        }
        if argv.starts(with: ["display", "focus"]), text.contains(": no display") || text.contains(": unknown display") {
            return reject(command, "no_other_display", SlashError(message: "Il n'y a pas d'autre écran.", usage: usage))
        }
        guard response.exitCode == 0 else {
            return reject(command, "router_failed", SlashError(message: Self.translated(stderr.isEmpty ? stdout : stderr), usage: usage))
        }
        // Exit 0 avec un message connu (« aucune fenêtre voisine », « déjà sur cet écran »…) : rien n'a été fait,
        // l'échec doit rester visible dans la boîte.
        let message = Self.translated(stdout)
        if message != stdout {
            return reject(command, "no_effect", SlashError(message: message, usage: usage))
        }
        return .done(message: stdout.isEmpty ? [] : [message])
    }

    /// `/doctor` (sortie = diagnostic), `/heal` et `/reload` : le résultat s'affiche dans la boîte, lignes
    /// connues traduites. Pour `/heal` et `/reload`, une sortie non nulle ou un `status=` autre que `applied`
    /// est un échec (message du routeur, ou `error=` de `config reload`). O(l), l = taille de la réponse.
    private func routedInfo(_ argv: [String], command: String) -> SlashOutcome {
        let response = route(argv)
        let text = response.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? response.stderr : response.stdout
        let isReload = argv.starts(with: ["config", "reload"])
        // `status=`/`error=` ne se traduisent que pour `config reload` : `doctor` et `daemon heal` écrivent aussi `status=ok`.
        let lines = Self.lines(text).map { isReload ? Self.translated($0) : $0 }
        // Seul `config reload` dit `status=applied` en cas de succès ; `daemon heal` écrit `status=ok`.
        let reloadRefused = isReload && text.contains("status=") && !text.contains("status=applied")
        if argv.first != "doctor", response.exitCode != 0 || reloadRefused {
            let message = lines.first { $0.hasPrefix("Rechargement refusé :") } ?? lines.first ?? "La commande a échoué."
            return reject(command, "router_failed", SlashError(message: message, usage: Self.usage(command)))
        }
        return .info(Self.truncated(lines))
    }

    private func setting(_ request: SettingRequest, command: String) -> SlashOutcome {
        switch request {
        case .listCategories:
            return .info(SettingCategory.allCases.map { "\($0.rawValue) - \($0.label)" })
        case .read(let id):
            guard let line = settings.describe(id) else { return unknownSetting(id, command: command) }
            return .info([line])
        case .write(let id, let raw):
            guard SettingsCatalog.find(id: id) != nil else { return unknownSetting(id, command: command) }
            return changed(id, settings.set(id, to: raw), command: command)
        case .reset(let id):
            guard SettingsCatalog.find(id: id) != nil else { return unknownSetting(id, command: command) }
            return changed(id, settings.reset(id), command: command)
        }
    }

    private func changed(_ id: String, _ result: SettingChangeResult, command: String) -> SlashOutcome {
        switch result {
        case .applied(_, let new):
            return .info(["\(id) = \(SettingsService.display(new))"])
        case .rejected(let reason):
            return reject(command, "setting_rejected", SlashError(message: reason, usage: Self.usage("set")))
        }
    }

    /// Nom inconnu : propose le réglage le plus proche (distance d'édition <= 2). O(n * m), n < 200 réglages.
    private func unknownSetting(_ id: String, command: String) -> SlashOutcome {
        let closest = SettingsCatalog.all
            .filter { $0.readOnlyReason == nil }
            .map { (id: $0.id, distance: RoadieConfigLoader.editDistance(id, $0.id)) }
            .filter { $0.distance <= 2 }
            .min { $0.distance < $1.distance }
        return reject(command, "unknown_setting", SlashError(message: "Réglage inconnu : \(id).", usage: Self.usage("set"), suggestion: closest?.id))
    }

    /// Journal (R10) : nom de la commande et code de la raison, jamais la saisie ni les arguments.
    private func reject(_ command: String, _ reason: String, _ error: SlashError) -> SlashOutcome {
        eventLog.append(RoadieEvent(type: "command.rejected", details: ["command": command, "reason": reason]))
        return .failed(error)
    }

    // MARK: - Stages

    private struct StageFailure: Error {
        let code: String
        let error: SlashError
    }

    /// Nom insensible à la casse et aux accents. Plusieurs stages du même nom : erreur avec la liste. O(s).
    private func resolveStage(named name: String) -> Result<String, StageFailure> {
        let needle = TargetHintService.normalized(name)
        let matches = Self.currentStages(in: stageStore().state()).stages.filter { TargetHintService.normalized($0.name) == needle }
        let ids = Array(Set(matches.map(\.id.rawValue))).sorted()
        switch ids.count {
        case 1:
            return .success(ids[0])
        case 0:
            return .failure(StageFailure(code: "stage_not_found", error: SlashError(message: "Stage inconnu : \(name).", usage: Self.usage("stage"))))
        default:
            let list = matches.map { "\($0.id.rawValue) (\($0.name))" }.joined(separator: ", ")
            return .failure(StageFailure(code: "stage_ambiguous", error: SlashError(
                message: "Plusieurs stages portent ce nom : \(list). Utilisez le numéro.", usage: Self.usage("stage"))))
        }
    }

    /// Stages de l'espace courant (écran actif, bureau courant) et stage actif, comme `StageCommandService`.
    /// Écran actif inconnu et plusieurs écrans : tous les stages, sans stage actif. O(s), s = nombre de stages.
    private static func currentStages(in state: PersistentStageState) -> (stages: [PersistentStage], active: String?) {
        let displays = Set(state.scopes.map(\.displayID))
        if let displayID = state.activeDisplayID ?? (displays.count == 1 ? displays.first : nil) {
            let desktopID = state.currentDesktopID(for: displayID)
            if let scope = state.scopes.first(where: { $0.displayID == displayID && $0.desktopID == desktopID }) {
                return (scope.stages, scope.activeStageID.rawValue)
            }
        }
        return (state.scopes.flatMap(\.stages), nil)
    }

    /// Plus petit identifiant numérique libre à partir de 1. O(s).
    private static func smallestFreeID(_ stages: [PersistentStage]) -> String {
        let used = Set(stages.compactMap { Int($0.id.rawValue) })
        var id = 1
        while used.contains(id) { id += 1 }
        return String(id)
    }

    // MARK: - Textes

    /// Premier mot reconnu comme nom ou alias d'une commande ; nil sinon. O(c).
    private static func commandName(_ input: String) -> String? {
        SlashCommandCatalog.command(named: String(input.prefix { !$0.isWhitespace }))?.name
    }

    private static func usage(_ name: String) -> String? {
        SlashCommandCatalog.commands.first { $0.name == name }?.usage
    }

    /// Messages bruts connus du routeur (`WindowCommands`, `WindowBookmarkCommands`, `StageCommands`,
    /// `DesktopCommands`) en français. Message inconnu : renvoyé tel quel. Les messages techniques
    /// qui contiennent des compteurs (`applied=2 failed=0`) ne sont pas traduits. O(r), r = nombre de règles (borné, une vingtaine).
    static func translated(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name = between(text, "bookmark focus ", ": not found") { return "Bookmark introuvable : \(name)." }
        if let name = between(text, "bookmark focus ", ": display unavailable") { return "Bookmark \(name) : écran indisponible." }
        if let name = between(text, "bookmark focus ", ": focus failed") { return "Bookmark \(name) : le focus a échoué." }
        if text == "status=applied" { return "Configuration rechargée." }
        if text.hasPrefix("status=") { return "Rechargement refusé." }
        if text.hasPrefix("error=") { return "Rechargement refusé : \(text.dropFirst("error=".count))" }
        if text.hasPrefix("no neighbor ") {
            let directions = ["left": "à gauche", "right": "à droite", "up": "au-dessus", "down": "en dessous"]
            return "Aucune fenêtre voisine \(directions[String(text.dropFirst("no neighbor ".count))] ?? "dans cette direction")."
        }
        if text.hasPrefix("unknown display ") { return "Écran inconnu : \(text.dropFirst("unknown display ".count))." }
        if text.hasSuffix(": unknown display") { return "Écran inconnu." }
        if text.hasSuffix(": no display") { return "Aucun écran disponible." }
        if text.hasSuffix(": no active display") { return "Aucun écran actif." }
        if text.hasSuffix("window unavailable") || text.hasSuffix("display unavailable") {
            return "Fenêtre ou écran indisponible."
        }
        if text.hasSuffix("failed, window unavailable for tiling") { return "Cette fenêtre ne peut pas être tuilée." }
        if text.hasSuffix("failed, refused native-fullscreen or non-resizable window") {
            return "Fenêtre en plein écran natif ou non redimensionnable."
        }
        if text.hasSuffix("failed, refused incompatible application minimum size") {
            return "La taille minimale de l'application est incompatible."
        }
        if text.hasSuffix("failed, refused frame") { return "La fenêtre a refusé le nouveau cadre." }
        if text.hasSuffix(": window not in tree") { return "Cette fenêtre n'est pas dans le tuilage." }
        if text.hasSuffix("already on target display") { return "La fenêtre est déjà sur cet écran." }
        if text.hasSuffix("already on target desktop") { return "La fenêtre est déjà sur ce bureau." }
        return text
    }

    /// Texte entre `prefix` (début) et `suffix` (fin) ; nil si le texte n'a pas cette forme.
    private static func between(_ text: String, _ prefix: String, _ suffix: String) -> String? {
        guard text.hasPrefix(prefix), text.hasSuffix(suffix), text.count > prefix.count + suffix.count else { return nil }
        return String(text.dropFirst(prefix.count).dropLast(suffix.count))
    }

    private static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Au plus 12 lignes ; au-delà, la 12e indique le nombre de lignes cachées. O(n).
    static func truncated(_ lines: [String]) -> [String] {
        guard lines.count > maxInfoLines else { return lines }
        let hidden = lines.count - (maxInfoLines - 1)
        return Array(lines.prefix(maxInfoLines - 1)) + ["… \(hidden) lignes cachées"]
    }
}
