import Foundation
import CoreGraphics
import Darwin
import RoadieAX
import RoadieCore

/// Résultat d'une commande CLI : sorties en tampon et code de retour (pas d'`exit`).
/// Même forme que la réponse du socket daemon (contrat `cli-daemon-socket.md`).
public struct CLIResponse: Codable, Equatable, Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(exitCode: Int32, stdout: String = "", stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Statut d'une commande d'action (REL-042) : le code de sortie CLI en découle.
public enum CommandOutcome: String, Codable, Equatable, Sendable {
    case changed
    case noOp
    case failed
}

/// Résultat d'une commande d'action portant son statut (REL-042). Le code de sortie CLI se lit sur
/// `outcome`, jamais sur `message`, qui peut contenir une valeur utilisateur. `outcome` nil (aucun
/// résultat du code livré n'en laisse) : code 0.
protocol CommandResult {
    var message: String { get }
    var changed: Bool { get }
    var outcome: CommandOutcome? { get }
    init(message: String, changed: Bool, outcome: CommandOutcome?)
}

extension CommandResult {
    /// Échec : rien n'a changé, code de sortie 1.
    static func failure(_ message: String) -> Self {
        Self(message: message, changed: false, outcome: .failed)
    }

    /// Action sans objet : rien à faire, code de sortie 0.
    static func noChange(_ message: String) -> Self {
        Self(message: message, changed: false, outcome: .noOp)
    }

    /// Résultat partiel (REL-021) : une écriture reste alors que la commande a échoué et que son
    /// retour arrière aussi. `changed` vrai, code de sortie 1.
    static func partial(_ message: String) -> Self {
        Self(message: message, changed: true, outcome: .failed)
    }

    /// Changement si `changed`, sinon échec : commandes dont toutes les écritures AX ont échoué.
    static func changedOrFailed(_ message: String, changed: Bool) -> Self {
        Self(message: message, changed: changed, outcome: changed ? .changed : .failed)
    }

    /// Changement si `changed`, sinon action sans objet.
    static func changedOrNoOp(_ message: String, changed: Bool) -> Self {
        Self(message: message, changed: changed, outcome: changed ? .changed : .noOp)
    }

    /// Échec de persistance (REL-021). Un retour arrière lui-même en échec (`PartialCommitError`)
    /// est signalé comme résultat partiel. « failed » reste dans le message pour les journaux.
    static func persistenceFailure(_ command: String, _ error: Error) -> Self {
        let message = JSONPersistence.commandFailureMessage(command, error)
        return error is PartialCommitError ? .partial(message) : .failure(message)
    }
}

/// Arrêt anticipé d'une commande depuis un helper profond (remplace `exit()`).
struct CLIExit: Error {
    let code: Int32
}

/// Entrée de la table des commandes : source unique de l'aide.
struct CLICommandSpec {
    let usage: String
    var implemented = true

    /// Noms de commande couverts par la ligne (`move|warp|resize ...` -> 3 noms).
    var names: [String] {
        usage.split(separator: " ").first.map { $0.split(separator: "|").map(String.init) } ?? []
    }
}

/// Dispatch des commandes `roadie`. Exécuté en local par le binaire `roadie`
/// ou par le daemon via `CommandSocketServer`. N'appelle jamais `exit` ni `print`.
@MainActor
public final class CLICommandRouter {
    private let makeService: (_ readOnly: Bool) -> SnapshotService
    private let streamSink: ((String) -> Void)?
    /// Service de configuration du processus : `config reload` doit agir sur celui que lisent
    /// les composants (REL-014), donc l'instance partagée par défaut.
    private let configReload: ConfigReloadService
    private let railRuntimeStore: RailRuntimeStateStore
    private var cachedService: SnapshotService?
    private var stdoutBuffer = ""
    private var stderrBuffer = ""
    /// Commande en cours, pour limiter l'aide d'une erreur d'usage à cette commande.
    private var currentCommand: String?

    /// Commande en cours de lecture seule (`isReadOnly`).
    private var currentIsReadOnly = false

    /// `makeService(readOnly)` : `readOnly` vaut `true` pour une commande de lecture (`isReadOnly`).
    /// `streamSink` : sortie directe des commandes en flux continu (`events subscribe`),
    /// fourni seulement en exécution locale.
    public init(
        makeService: @escaping (_ readOnly: Bool) -> SnapshotService = CLICommandRouter.defaultService,
        streamSink: ((String) -> Void)? = nil,
        configReload: ConfigReloadService = .shared,
        railRuntimeStore: RailRuntimeStateStore = RailRuntimeStateStore()
    ) {
        self.makeService = makeService
        self.streamSink = streamSink
        self.configReload = configReload
        self.railRuntimeStore = railRuntimeStore
    }

    /// Service par défaut. Une lecture n'écrit pas l'état et ne fait pas suivre le focus par la
    /// stage (FR-009) : `UserInputActivity` sans moniteur refuse ce suivi.
    nonisolated public static func defaultService(readOnly: Bool) -> SnapshotService {
        let config = ConfigReloadService.shared.currentConfig()
        guard readOnly else { return SnapshotService(config: config) }
        return SnapshotService(config: config, persistStateChanges: false, userInput: UserInputActivity())
    }

    /// Commandes de lecture : leur snapshot n'écrit rien et ne change pas la stage active (T211).
    // O(1).
    nonisolated public static func isReadOnly(_ args: [String]) -> Bool {
        let verb = args.dropFirst().first ?? ""
        switch args.first {
        case "windows", "tree", "query", "metrics", "doctor":
            return true
        case "display", "desktop":
            return verb == "list" || verb == "current"
        case "state":
            return verb == "dump" || verb == "audit"
        case "layout":
            return verb == "plan"
        case "focus":
            return verb == "status"
        case "stage", "bookmark", "targets":
            return verb == "list"
        case "daemon":
            return verb == "health"
        default:
            return false
        }
    }

    /// Service créé à la demande, une fois par commande (config à jour, pas de scan inutile).
    private var service: SnapshotService {
        if let cachedService { return cachedService }
        let created = makeService(currentIsReadOnly)
        cachedService = created
        return created
    }

    public func run(_ args: [String]) -> CLIResponse {
        stdoutBuffer = ""
        stderrBuffer = ""
        cachedService = nil
        currentCommand = args.first
        currentIsReadOnly = Self.isReadOnly(args)
        let code: Int32
        do {
            if let help = helpRequest(args) {
                code = help
            } else {
                code = try dispatch(args)
            }
        } catch let early as CLIExit {
            code = early.code
        } catch {
            err("roadie: \(error)")
            code = 1
        }
        cachedService = nil
        return CLIResponse(exitCode: code, stdout: stdoutBuffer, stderr: stderrBuffer)
    }

    private func out(_ text: String) {
        stdoutBuffer += text + "\n"
    }

    private func err(_ text: String) {
        stderrBuffer += text + "\n"
    }

    /// Vide le tampon stdout vers `streamSink` (commandes en flux continu).
    private func flushStream() {
        streamSink?(stdoutBuffer)
        stdoutBuffer = ""
    }

    static let launchdLabel = "com.roadie.roadied"

    /// Table des commandes : source unique de l'aide (`help`, `help COMMANDE`, erreurs d'usage).
    static let commandTable: [CLICommandSpec] = [
        CLICommandSpec(usage: "help [COMMAND]"),
        CLICommandSpec(usage: "--version"),
        CLICommandSpec(usage: "windows list [--json]"),
        CLICommandSpec(usage: "display list|current [--json]"),
        CLICommandSpec(usage: "display focus N|left|right|up|down"),
        CLICommandSpec(usage: "state dump|audit|heal [--json]"),
        CLICommandSpec(usage: "tree dump [--json]"),
        CLICommandSpec(usage: "layout plan [--json]"),
        CLICommandSpec(usage: "layout apply [--yes] [--json]"),
        CLICommandSpec(usage: "layout split horizontal|vertical"),
        CLICommandSpec(usage: "layout toggle-split [left|right|up|down]"),
        CLICommandSpec(usage: "layout join-with|insert left|right|up|down"),
        CLICommandSpec(usage: "layout flatten|zoom-parent"),
        CLICommandSpec(usage: "layout width next|prev|nudge [DELTA]|ratio RATIO [--all]"),
        CLICommandSpec(usage: "config show|validate|reload [--json] [--config PATH]"),
        CLICommandSpec(usage: "rules validate|list|explain [--json] [--config PATH]"),
        CLICommandSpec(usage: "group create|add|remove|focus|dissolve|list ..."),
        CLICommandSpec(usage: "query state|windows|displays|desktops|stages|groups|rules|health|events|event_catalog|performance|restore|targets|components"),
        CLICommandSpec(usage: "targets list|pick|inspect|activate|show|interactive|search|actions|hide ..."),
        CLICommandSpec(usage: "overview show|toggle|hide|status [--json]"),
        CLICommandSpec(usage: "project save [NAME] | open NAME | list [--json] | delete NAME"),
        CLICommandSpec(usage: "undo"),
        CLICommandSpec(usage: "launcher history [--clear] [--json]"),
        CLICommandSpec(usage: "launcher reset"),
        CLICommandSpec(usage: "workflow list [--json] [--hotkeys] | check FOLDER [--json] | install FILE.alfredworkflow [--replace] | remove ID"),
        CLICommandSpec(usage: "workflow run ID OBJECT [ARGUMENT] [--var NAME=VALUE] | trigger ID TRIGGER [ARGUMENT] [--var NAME=VALUE] | tasks update"),
        CLICommandSpec(usage: "workflow alfred search TEXT | trigger WORKFLOW NAME [ARGUMENT] | set WORKFLOW KEY VALUE | remove WORKFLOW KEY | reload WORKFLOW | reveal WORKFLOW"),
        CLICommandSpec(usage: "launch --open-items [--tabs]"),
        CLICommandSpec(usage: "launch PATH [--stage NAME | --here | --new-stage] [--position left|right|full|float] [--preview-only]"),
        CLICommandSpec(usage: "switcher show [--profile ID] | cycle [--profile ID] [--hold cmd] [--backwards] | next | previous | accept | cancel [--json]"),
        CLICommandSpec(usage: "grid show|interactive|click|double-click|right-click|move|scroll-up|scroll-down|drag [--scope display|focused_window] ..."),
        CLICommandSpec(usage: "record start NAME [--duration S] [--stop-file PATH]"),
        CLICommandSpec(usage: "record replay|list|inspect|delete ..."),
        CLICommandSpec(usage: "rail status|pin|unpin|toggle"),
        CLICommandSpec(usage: "rail labels show|hide|status"),
        CLICommandSpec(usage: "doctor"),
        CLICommandSpec(usage: "self-test"),
        CLICommandSpec(usage: "events tail [N]"),
        CLICommandSpec(usage: "events subscribe [--from-now] [--initial-state] [--type TYPE] [--scope SCOPE]"),
        CLICommandSpec(usage: "performance summary|recent|thresholds [--json] [--limit N]"),
        CLICommandSpec(usage: "restore snapshot|status|apply|unhide-all [--yes] [--json]"),
        CLICommandSpec(usage: "cleanup [--dry-run|--apply] [--json]"),
        CLICommandSpec(usage: "metrics [--json]"),
        CLICommandSpec(usage: "permissions [--prompt]"),
        CLICommandSpec(usage: "focus status"),
        CLICommandSpec(usage: "focus back-and-forth|left|right|up|down"),
        CLICommandSpec(usage: "bookmark set|focus|jump|clear|list NAME"),
        CLICommandSpec(usage: "move|warp|resize left|right|up|down"),
        CLICommandSpec(usage: "mode bsp|spatialBsp|masterStack|float"),
        CLICommandSpec(usage: "toggle maximize|fullscreen|native-fullscreen"),
        CLICommandSpec(usage: "toggle floating"),
        CLICommandSpec(usage: "window display N"),
        CLICommandSpec(usage: "window desktop N [--follow]"),
        CLICommandSpec(usage: "window swap left|right|up|down"),
        CLICommandSpec(usage: "window bookmark set|focus|jump|clear|list NAME"),
        CLICommandSpec(usage: "window reset"),
        CLICommandSpec(usage: "window close", implemented: false),
        CLICommandSpec(usage: "desktop list|current"),
        CLICommandSpec(usage: "desktop focus N|prev|next|last|back|back-and-forth"),
        CLICommandSpec(usage: "desktop next|prev|last|back|back-and-forth"),
        CLICommandSpec(usage: "desktop summon N"),
        CLICommandSpec(usage: "desktop label N NAME"),
        CLICommandSpec(usage: "desktop move N POSITION"),
        CLICommandSpec(usage: "stage list"),
        CLICommandSpec(usage: "stage create|delete N"),
        CLICommandSpec(usage: "stage rename N NAME"),
        CLICommandSpec(usage: "stage reorder N POSITION"),
        CLICommandSpec(usage: "stage switch|assign N"),
        CLICommandSpec(usage: "stage switch-position|assign-position N"),
        CLICommandSpec(usage: "stage switch-visible prev|next"),
        CLICommandSpec(usage: "stage assign-empty"),
        CLICommandSpec(usage: "stage summon WINDOW_ID"),
        CLICommandSpec(usage: "stage move-to-display N|left|right|up|down [--follow|--no-follow]"),
        CLICommandSpec(usage: "stage mode bsp|spatialBsp|masterStack|float"),
        CLICommandSpec(usage: "stage prev|next"),
        CLICommandSpec(usage: "balance"),
        CLICommandSpec(usage: "daemon health|heal [--json]"),
        CLICommandSpec(usage: "daemon restart"),
    ]

    /// Texte d'aide, complet ou limité à une commande. `nil` si la commande est inconnue.
    // O(n), n = lignes de la table (< 100).
    static func usage(for command: String?) -> String? {
        let specs = command.map { name in commandTable.filter { $0.names.contains(name) } } ?? commandTable
        guard !specs.isEmpty else { return nil }
        let lines = specs.map { "  roadie \($0.usage)" + ($0.implemented ? "" : "  (not implemented)") }
        return (["usage:"] + lines).joined(separator: "\n")
    }

    static func usage() -> String {
        usage(for: nil) ?? ""
    }

    /// `help`, `-h`, `--help` (seuls ou après une commande) : aide sur stdout, code 0.
    private func helpRequest(_ args: [String]) -> Int32? {
        let isHelpVerb = ["help", "-h", "--help"].contains(args.first ?? "")
        guard isHelpVerb || args.contains("--help") || args.contains("-h") else { return nil }
        let command = isHelpVerb ? args.dropFirst().first : args.first
        guard let text = Self.usage(for: command) else {
            err("roadie: unknown command \(command ?? "")")
            err(Self.usage())
            return 64
        }
        out(text)
        return 0
    }

    /// Erreur d'usage : aide de la commande sur stderr, code 64.
    private func usageError() -> Int32 {
        err(Self.usage(for: currentCommand) ?? Self.usage())
        return 64
    }

    /// Fin d'une commande d'action : message sur stdout, code 0 si changement ou action
    /// sans objet, 1 si la commande a échoué (FR-039).
    /// `RailRuntimeStateStore` rend nil si l'état n'a pas été écrit (REL-021) : code 1, pas de succès perdu.
    private func railNotPersisted() -> Int32 {
        err("roadie: rail state not persisted (rail.json unreadable or not writable); see roadied stderr")
        return 1
    }

    /// Fin d'une commande dont le résultat porte son statut (REL-042) : code calculé sur ce statut.
    private func finish(_ result: some CommandResult) -> Int32 {
        out(result.message)
        return Self.actionExitCode(outcome: result.outcome)
    }

    /// Statut explicite (REL-042) : 1 pour un échec, 0 sinon, sans lire le message, qui peut
    /// contenir une valeur utilisateur (stage nommée « failed »). O(1).
    nonisolated static func actionExitCode(outcome: CommandOutcome?) -> Int32 {
        outcome == .failed ? 1 : 0
    }

    /// Identifiant de fenêtre d'un argument : entier positif. `WindowID(rawValue: 0)` arrête le
    /// processus (précondition), donc zéro est refusé ici (REL-001). O(1).
    nonisolated static func windowID(_ raw: String) -> WindowID? {
        guard let value = UInt32(raw), value > 0 else { return nil }
        return WindowID(rawValue: value)
    }

    /// Commandes que le binaire `roadie` envoie au daemon (liste explicite, contrat
    /// `cli-daemon-socket.md`) : actions finies sans boucle AppKit ni flux continu.
    /// Tout le reste s'exécute toujours dans le processus `roadie`.
    // O(1).
    nonisolated public static func isDaemonRouted(_ args: [String]) -> Bool {
        guard let command = args.first, !args.contains("--help"), !args.contains("-h") else { return false }
        switch command {
        // `bookmark` : `set` lit la fenêtre active, donc l'Accessibilité du daemon. En local, un
        // raccourci Karabiner ne voyait aucune fenêtre (« no active tiled window »).
        case "focus", "move", "warp", "wrap", "resize", "balance", "stage", "desktop", "display", "window", "layout", "rules", "query", "bookmark":
            return true
        // `floating` lit la fenêtre active : il faut l'Accessibilité du daemon (SPEC-047).
        case "toggle":
            return ["maximize", "floating"].contains(args.dropFirst().first ?? "")
        case "restore":
            return args.dropFirst().first == "unhide-all"
        case "state":
            return ["dump", "audit"].contains(args.dropFirst().first ?? "")
        // Le diagnostic utilise les permissions du daemon, pas celles du terminal appelant.
        case "daemon":
            return args.dropFirst().first == "health"
        // `config reload` : l'instance partagée à recharger est celle du daemon (REL-014).
        case "config":
            return args.dropFirst().first == "reload"
        default:
            return false
        }
    }

    private func dispatch(_ args: [String]) throws -> Int32 {
        switch args.first {
        case "windows":
            guard args.dropFirst().first == "list" else {
                return usageError()
            }
            let snapshot = service.snapshot()
            if args.contains("--json") {
                try printJSON(snapshot.windows, label: "windows")
            } else {
                out(TextFormatter.windows(snapshot.windows))
            }
        case "display":
            let verb = args.dropFirst().first
            guard verb == "list" || verb == "current" || verb == "focus" else {
                return usageError()
            }
            if verb == "focus" {
                guard let target = args.dropFirst(2).first else {
                    err("roadie: display focus requires N|left|right|up|down")
                    return 64
                }
                let commandService = DisplayCommandService(service: service)
                let result: StageCommandResult
                if let index = Int(target), index > 0 {
                    result = commandService.focus(index: index)
                } else if let direction = Direction(rawValue: target) {
                    result = commandService.focus(direction)
                } else {
                    err("roadie: display focus requires N|left|right|up|down")
                    return 64
                }
                return finish(result)
            }
            let snapshot = service.snapshot()
            if args.contains("--json"), verb == "current" {
                guard let display = TextFormatter.currentDisplaySnapshot(snapshot, state: service.effectiveStageStore.state()) else {
                    err("roadie: no displays found")
                    return 1
                }
                try printJSON(display, label: "display")
            } else if args.contains("--json") {
                try printJSON(snapshot.displays, label: "displays")
            } else if verb == "current" {
                out(TextFormatter.currentDisplay(snapshot, state: service.effectiveStageStore.state()))
            } else {
                out(TextFormatter.displays(snapshot.displays, state: service.effectiveStageStore.state()))
            }
        case "state":
            let verb = args.dropFirst().first
            guard verb == "dump" || verb == "audit" || verb == "heal" else {
                return usageError()
            }
            if verb == "dump" {
                try printJSON(service.snapshot())
            } else if verb == "audit" {
                let report = StateAuditService(service: service).run()
                if args.contains("--json") {
                    try printJSON(report, label: "state audit")
                } else {
                    out(TextFormatter.stateAudit(report))
                }
                return report.failed ? 1 : 0
            } else {
                let report = StateAuditService(service: service).heal()
                if args.contains("--json") {
                    try printJSON(report, label: "state heal")
                } else {
                    out(TextFormatter.stateHeal(report))
                }
                // Réparations non écrites (REL-021) : signalées et code non nul.
                if let persistenceError = report.persistenceError {
                    err("roadie: \(persistenceError)")
                }
                return report.failed ? 1 : 0
            }
        case "layout":
            let verb = args.dropFirst().first
            // Relevé et plan seulement pour `plan` et `apply` : les autres verbes relèvent eux-mêmes ;
            // un relevé de plus doublerait l'énumération AX du raccourci (audit QUAL-101).
            switch verb {
            case "plan":
                let plan = service.applyPlan(from: service.snapshot())
                if args.contains("--json") {
                    try printJSON(plan, label: "layout plan")
                } else {
                    out(TextFormatter.applyPlan(plan))
                }
            case "apply":
                let snapshot = service.snapshot()
                guard args.contains("--yes") else {
                    err("roadie: refusing to move windows without --yes")
                    out(TextFormatter.applyPlan(service.applyPlan(from: snapshot)))
                    return 2
                }
                // Génération ouverte à l'entrée de la commande (A13, T223) : le plan est recalculé
                // dedans, pour que les frames acceptées d'une autre génération ne le filtrent pas.
                let generation = PlacementGeneration.shared.next()
                let result = service.apply(service.applyPlan(from: snapshot, generation: generation), generation: generation)
                if args.contains("--json") {
                    try printJSON(result, label: "apply result")
                } else {
                    out(TextFormatter.applyResult(result))
                }
            case "flatten":
                let result = LayoutCommandService(service: service).flatten()
                return finish(result)
            case "split":
                let result = LayoutCommandService(service: service).split(args.dropFirst(2).first ?? "")
                return finish(result)
            case "toggle-split":
                let rawDirection = args.dropFirst(2).first
                let direction = rawDirection.flatMap(Direction.init(rawValue:))
                if rawDirection != nil && direction == nil {
                    err("roadie: layout toggle-split expects optional left|right|up|down")
                    return 64
                }
                let result = LayoutCommandService(service: service).toggleSplit(direction)
                return finish(result)
            case "insert":
                guard let rawDirection = args.dropFirst(2).first, let direction = Direction(rawValue: rawDirection) else {
                    err("roadie: layout insert requires left|right|up|down")
                    return 64
                }
                let result = LayoutCommandService(service: service).insert(direction)
                return finish(result)
            case "join-with":
                guard let rawDirection = args.dropFirst(2).first, let direction = Direction(rawValue: rawDirection) else {
                    err("roadie: layout join-with requires left|right|up|down")
                    return 64
                }
                let result = LayoutCommandService(service: service).join(with: direction)
                return finish(result)
            case "zoom-parent":
                let result = LayoutCommandService(service: service).zoomParent()
                return finish(result)
            case "width":
                let result = runWidthLayoutCommand(Array(args.dropFirst(2)))
                return finish(result)
            default:
                return usageError()
            }
        case "tree":
            guard args.dropFirst().first == "dump" else {
                return usageError()
            }
            let dump = TreeDumpService(service: service).dump()
            if args.contains("--json") {
                try printJSON(dump, label: "tree dump")
            } else {
                out(TextFormatter.treeDump(dump))
            }
        case "permissions":
            // Permissions du daemon (statut publié) ; à défaut celles de ce processus.
            let local = AXPermissions.snapshot(prompt: args.contains("--prompt"))
            out(TextFormatter.permissions(
                daemon: DaemonStatusReading.read(),
                localAccessibility: local.accessibilityTrusted,
                localScreenRecording: CGPreflightScreenCaptureAccess()
            ))
        case "doctor":
            let snapshot = service.snapshot()
            out(TextFormatter.doctor(
                daemon: DaemonStatusReading.read(),
                config: RoadieConfigLoader.validate(path: nil),
                snapshot: snapshot,
                plan: service.applyPlan(from: snapshot),
                persistentState: service.effectiveStageStore.state()
            ))
        case "self-test":
            let report = SelfTestService(service: service).run()
            out(TextFormatter.selfTest(report))
            return report.failed ? 1 : 0
        case "events":
            let verb = args.dropFirst().first
            guard verb == "tail" || verb == "subscribe" else {
                return usageError()
            }
            if verb == "tail" {
                let limit = args.dropFirst(2).first.flatMap(Int.init) ?? 20
                out(EventLog().tail(limit: limit).joined(separator: "\n"))
            } else {
                return try runEventSubscription(Array(args.dropFirst(2)))
            }
        case "performance":
            return try runPerformanceCommand(Array(args.dropFirst()))
        case "restore":
            return try runRestoreCommand(Array(args.dropFirst()))
        case "cleanup":
            // Simulation par défaut ; `--apply` seul applique, `--dry-run` l'interdit.
            if args.contains("--dry-run"), args.contains("--apply") {
                err("roadie: cleanup accepts only one of --dry-run or --apply")
                return 64
            }
            let dryRun = !args.contains("--apply")
            let report = FileAdministrationService().run(dryRun: dryRun)
            if args.contains("--json") {
                try printCodableJSON(report)
            } else {
                out(TextFormatter.fileAdmin(report))
            }
        case "metrics":
            let metrics = MetricsService(service: service).collect()
            if args.contains("--json") {
                try printJSON(metrics, label: "metrics")
            } else {
                out(TextFormatter.metrics(metrics))
            }
        case "config":
            let verb = args.dropFirst().first
            guard verb == "show" || verb == "validate" || verb == "reload" else {
                return usageError()
            }
            let configPath = value(after: "--config", in: Array(args.dropFirst(2)))
            if verb == "validate" {
                let report = RoadieConfigLoader.validate(path: configPath)
                if args.contains("--json") {
                    try printCodableJSON(report)
                } else {
                    out(TextFormatter.configValidation(report))
                }
                return report.hasErrors ? 1 : 0
            } else if verb == "reload" {
                let result = configReload.reload(path: configPath ?? RoadieConfigLoader.defaultConfigPath())
                if args.contains("--json") {
                    try printCodableJSON(result)
                } else {
                    out("status=\(result.status.rawValue)")
                    if let error = result.error {
                        out("error=\(error)")
                    }
                }
                return result.status == .applied ? 0 : 1
            }
            do {
                let config = try RoadieConfigLoader.load(from: configPath)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                out(String(decoding: try encoder.encode(config), as: UTF8.self))
            } catch {
                err("roadie: config load failed: \(error)")
                return 1
            }
        case "rules":
            return try runRulesCommand(Array(args.dropFirst()))
        case "group":
            return try runGroupCommand(Array(args.dropFirst()))
        case "query":
            return try runQueryCommand(Array(args.dropFirst()))
        case "targets":
            return try runTargetsCommand(Array(args.dropFirst()))
        case "undo":
            // SPEC-081 : remettre la fenêtre du dernier déplacement dans sa stage d'origine.
            return try queueTargetModeRuntimeCommand(TargetModeRuntimeCommand(name: "launcher.undo"), json: args.contains("--json"))
        case "project":
            // SPEC-080 : enregistrer et rouvrir passent par le démon (lecture AX) ; la liste se lit ici.
            let sub = args.count >= 2 ? args[1] : ""
            let name = args.count >= 3 && !args[2].hasPrefix("--") ? args[2] : nil
            switch sub {
            case "list":
                let projects = StageProjectStore().load().projects.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                if args.contains("--json") {
                    let rows = projects.map { ["name": $0.name, "windows": String($0.windows.count), "savedAt": ISO8601DateFormatter().string(from: $0.savedAt)] }
                    out(String(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys, .prettyPrinted]), encoding: .utf8) ?? "[]")
                } else {
                    out(projects.isEmpty ? "aucun projet" : projects.map { "\($0.name)\t\($0.windows.count) fenêtre(s)" }.joined(separator: "\n"))
                }
                return 0
            case "save":
                return try queueTargetModeRuntimeCommand(TargetModeRuntimeCommand(name: "project.save", arguments: name.map { ["name": $0] } ?? [:]),
                                                         json: args.contains("--json"))
            case "open", "delete":
                guard let name else { return usageError() }
                return try queueTargetModeRuntimeCommand(TargetModeRuntimeCommand(name: "project.\(sub)", arguments: ["name": name]),
                                                         json: args.contains("--json"))
            default:
                return usageError()
            }
        case "workflow":
            return try runWorkflowCommand(Array(args.dropFirst()))
        case "launcher":
            // Session 105 : effacer la connaissance (classement appris), comme le bouton d'Alfred.
            if args.count >= 2, args[1] == "reset" {
                let url = LauncherRankingStore().url
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                out("classement appris effacé")
                return 0
            }
            // SPEC-090 : historique des saisies de la barre, gardé sur ce Mac.
            guard args.count >= 2, args[1] == "history" else { return usageError() }
            let store = LauncherHistoryStore()
            if args.contains("--clear") {
                store.clear()
                out("historique effacé")
                return 0
            }
            let entries = store.load().entries.reversed()
            if args.contains("--json") {
                let rows = entries.map { ["query": $0.query, "at": ISO8601DateFormatter().string(from: $0.at)] }
                out(String(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys, .prettyPrinted]), encoding: .utf8) ?? "[]")
            } else {
                out(entries.isEmpty ? "historique vide" : entries.map(\.query).joined(separator: "\n"))
            }
            return 0
        case "launch":
            // SPEC-082 : diagnostic des documents (et onglets avec --tabs) que la barre trouverait.
            if args.count >= 2, args[1] == "--open-items" {
                return try queueTargetModeRuntimeCommand(TargetModeRuntimeCommand(name: "launcher.open_items",
                                                                                  arguments: args.contains("--tabs") ? ["tabs": "true"] : [:]),
                                                         json: args.contains("--json"))
            }
            // SPEC-077 : fichier, dossier ou application ouvert comme Retour dans la barre.
            guard args.count >= 2, !args[1].hasPrefix("--") else { return usageError() }
            let expanded = NSString(string: args[1]).expandingTildeInPath
            let path = URL(fileURLWithPath: expanded, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
                .standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: path) else {
                err("launch: introuvable : \(args[1])")
                return 2
            }
            var payload = ["path": path]
            if let stage = value(after: "--stage", in: args) { payload["stage"] = stage }
            if args.contains("--new-stage") { payload["newStage"] = "true" }
            if args.contains("--here") { payload["here"] = "true" }
            if let position = value(after: "--position", in: args) {
                guard ["left", "right", "full", "float"].contains(position) else { return usageError() }
                payload["position"] = position
            }
            // SPEC-078 : aperçu actif seul, 2 s, puis restauration ; rien n'est ouvert (diagnostic).
            if args.contains("--preview-only") { payload["previewOnly"] = "true" }
            return try queueTargetModeRuntimeCommand(TargetModeRuntimeCommand(name: "launcher.launch", arguments: payload), json: args.contains("--json"))
        case "overview":
            guard let command = OverviewController.command(Array(args.dropFirst())) else { return usageError() }
            if command.name == "overview.status" {
                let c = configReload.currentConfig().overview
                let status: [String: String] = ["enabled": String(c.enabled), "presentation": c.presentation, "loupe": String(c.loupe), "magnification": String(c.magnification), "receiver_available": String(OverviewController.receiverAvailable)]
                out(String(data: try JSONSerialization.data(withJSONObject: status, options: [.sortedKeys]), encoding: .utf8) ?? "{}")
                return 0
            }
            guard OverviewController.receiverAvailable else {
                err("roadie: overview receiver unavailable; restart Roadie with this version"); return 1
            }
            guard configReload.currentConfig().overview.enabled || command.name == "overview.hide" else {
                err("roadie: overview disabled"); return 1
            }
            return try queueTargetModeRuntimeCommand(command, json: args.contains("--json"), notificationName: OverviewController.notificationName)
        case "switcher":
            let arguments = Array(args.dropFirst())
            guard let command = WindowSwitcherRuntimeBridge.command(arguments) else { return usageError() }
            return try queueTargetModeRuntimeCommand(command, json: args.contains("--json"),
                                                      notificationName: WindowSwitcherRuntimeBridge.notificationName)
        case "grid":
            return try runGridCommand(Array(args.dropFirst()))
        case "record":
            return try runRecordCommand(Array(args.dropFirst()))
        case "rail":
            guard let verb = args.dropFirst().first,
                  ["status", "pin", "unpin", "toggle", "labels"].contains(verb)
            else {
                return usageError()
            }
            let runtimeStore = railRuntimeStore
            switch verb {
            case "status":
                let pinned = runtimeStore.load().isPinned
                out((RailSettings.load().statusLines + ["runtime.pinned=\(pinned)"]).joined(separator: "\n"))
            case "pin":
                guard let state = runtimeStore.setPinned(true) else { return railNotPersisted() }
                out("rail pinned=\(state.isPinned)")
            case "unpin":
                guard let state = runtimeStore.setPinned(false) else { return railNotPersisted() }
                out("rail pinned=\(state.isPinned)")
            case "toggle":
                guard let state = runtimeStore.togglePinned() else { return railNotPersisted() }
                out("rail pinned=\(state.isPinned)")
            case "labels":
                let subcommand = args.dropFirst(2).first ?? "show"
                let settings = RailSettings.load().stageLabel
                switch subcommand {
                case "show":
                    guard let state = runtimeStore.showStageLabels(for: settings.visibilitySeconds) else { return railNotPersisted() }
                    if settings.visibilitySeconds <= 0 {
                        out("rail labels visible=always")
                    } else {
                        out("rail labels visible_until=\(state.stageLabelsVisibleUntil ?? 0)")
                    }
                case "hide":
                    guard let state = runtimeStore.hideStageLabels() else { return railNotPersisted() }
                    out("rail labels visible_until=\(state.stageLabelsVisibleUntil ?? 0)")
                case "status":
                    let state = runtimeStore.load()
                    let until = state.stageLabelsVisibleUntil.map { String($0) } ?? "-"
                    out("rail labels visibility_seconds=\(settings.visibilitySeconds) fade_seconds=\(settings.fadeSeconds) visible_until=\(until)")
                default:
                    return usageError()
                }
            default:
                return usageError()
            }
        case "focus":
            if args.dropFirst().first == "status" {
                out(TextFormatter.focusStatus(service.snapshot()))
                return 0
            } else if args.dropFirst().first == "back-and-forth" {
                let result = WindowCommandService(service: service).focusBackAndForth()
                return finish(result)
            } else {
                return runDirectionalCommand(args.dropFirst().first, verb: "focus") {
                    WindowCommandService(service: service).focus($0)
                }
            }
        case "move":
            return runDirectionalCommand(args.dropFirst().first, verb: "move") {
                WindowCommandService(service: service).move($0)
            }
        case "warp", "wrap":
            return runDirectionalCommand(args.dropFirst().first, verb: "warp") {
                WindowCommandService(service: service).warp($0)
            }
        case "resize":
            return runDirectionalCommand(args.dropFirst().first, verb: "resize") {
                WindowCommandService(service: service).resize($0)
            }
        case "mode":
            return try runModeCommand(args.dropFirst().first)
        case "window":
            return try runWindowCommand(Array(args.dropFirst()))
        case "bookmark":
            return try runBookmarkCommand(Array(args.dropFirst()))
        case "desktop":
            return try runDesktopCommand(Array(args.dropFirst()))
        case "stage":
            return try runStageCommand(Array(args.dropFirst()))
        case "balance":
            let result = LayoutCommandService(service: service).balance()
            return finish(result)
        case "daemon":
            if args.dropFirst().first == "health" {
                let report = DaemonHealthService(service: service, stageStore: service.effectiveStageStore).run()
                if args.contains("--json") {
                    try printJSON(report, label: "daemon health")
                } else {
                    out(TextFormatter.daemonHealth(report))
                }
                return report.failed ? 1 : 0
            } else if args.dropFirst().first == "heal" {
                let report = DaemonHealthService(service: service, stageStore: service.effectiveStageStore).heal()
                if args.contains("--json") {
                    try printJSON(report, label: "daemon heal")
                } else {
                    out(TextFormatter.daemonHeal(report))
                }
                if let persistenceError = report.state.persistenceError {
                    err("roadie: \(persistenceError)")
                }
                return report.failed ? 1 : 0
            } else if args.dropFirst().first == "restart" {
                return restartDaemon()
            } else {
                return usageError()
            }
        case "toggle":
            let subject = args.dropFirst().first ?? ""
            let windowCommands = WindowCommandService(service: service)
            let result: WindowCommandResult
            switch subject {
            case "maximize":
                result = windowCommands.toggleMaximize()
            case "fullscreen":
                result = windowCommands.toggleFullscreen()
            case "native-fullscreen":
                result = windowCommands.toggleNativeFullscreen()
            case "floating":
                let actions = WindowContextActions(
                    snapshotService: service,
                    stageStore: service.effectiveStageStore,
                    eventLog: service.effectiveEvents
                )
                return finish(actions.toggleFloating(windowID: nil))
            default:
                return usageError()
            }
            return finish(result)
        case "--version", "version":
            out("roadie \(RoadieVersion.current)")
        case nil:
            out(Self.usage())
        case .some(let unknown):
            err("roadie: unknown command \(unknown)")
            err(Self.usage())
            return 64
        }
        return 0
    }

    /// Même encodage que `SnapshotEncoding.json` (indenté, clés triées, dates par défaut).
    private func printJSON<T: Encodable>(_ value: T, label: String = "snapshot") throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            out(String(decoding: try encoder.encode(value), as: UTF8.self))
        } catch {
            err("roadie: failed to encode \(label): \(error)")
            throw CLIExit(code: 1)
        }
    }

    private func printCodableJSON<T: Encodable>(_ value: T) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            out(String(decoding: try encoder.encode(value), as: UTF8.self))
        } catch {
            err("roadie: failed to encode JSON: \(error)")
            throw CLIExit(code: 1)
        }
    }

    /// Workflows au format d'Alfred (SPEC-088 FR-010) : lus et installés ici, sans le démon.
    /// Ordre donné à Alfred par un script de workflow (SPEC-093 FR-004) : barre et déclencheur par le
    /// démon ; réglages gardés et dossier sur place. Journal sans texte de l'utilisateur (FR-007).
    private func runAlfredOrder(_ args: [String], json: Bool) throws -> Int32 {
        guard let order = args.first else { return usageError() }
        let rest = Array(args.dropFirst())
        func log(_ workflow: String) {
            EventLog().append(RoadieEvent(type: "launcher.alfred_call", details: ["order": order, "workflow": workflow]))
        }
        switch order {
        case "search":
            return try queueTargetModeRuntimeCommand(TargetModeRuntimeCommand(name: "workflow.alfred", arguments: ["order": "search", "text": rest.first ?? ""]), json: json)
        case "trigger":
            guard rest.count >= 2 else { return usageError() }
            var payload = ["order": "trigger", "id": rest[0], "trigger": rest[1]]
            if rest.count >= 3 { payload["argument"] = rest[2] }
            return try queueTargetModeRuntimeCommand(TargetModeRuntimeCommand(name: "workflow.alfred", arguments: payload), json: json)
        case "set":
            guard rest.count >= 3 else { return usageError() }
            try AlfredKeptSettings.shared.set(rest[1], to: rest[2], workflow: rest[0])
            log(rest[0])
            return 0
        case "remove":
            guard rest.count >= 2 else { return usageError() }
            try AlfredKeptSettings.shared.remove(rest[1], workflow: rest[0])
            log(rest[0])
            return 0
        case "reload":
            // L'index compare les dates à chaque lecture : rien à écrire (research R4).
            log(rest.first ?? "")
            return 0
        case "reveal":
            let config = configReload.currentConfig().experimental.targetMode
            guard let id = rest.first, let workflow = AlfredWorkflowIndex.shared.workflows(alfred: config.alfredWorkflows)
                .first(where: { $0.bundleID == id || $0.id == id }) else { err("workflow: introuvable : \(rest.first ?? "")"); return 2 }
            let reveal = Process()
            reveal.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            reveal.arguments = ["-R", workflow.folder.path]
            try reveal.run()
            log(id)
            return 0
        default:
            return usageError()
        }
    }

    private func runWorkflowCommand(_ args: [String]) throws -> Int32 {
        let json = args.contains("--json")
        func show(_ reports: [AlfredCompatibilityReport], totals: Bool) throws {
            if json {
                let rows: [[String: Any]] = reports.map { report in
                    ["id": report.id, "name": report.name, "bundleID": report.bundleID, "source": report.source.rawValue,
                     "keywords": report.keywords, "state": report.state.rawValue, "missing": report.missing,
                     "mentionsAlfred": report.mentionsAlfred, "alfredOrders": report.orders, "untranslated": report.untranslated]
                }
                out(String(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys, .prettyPrinted]), encoding: .utf8) ?? "[]")
                return
            }
            let state = ["complete": "complet", "partial": "partiel", "unusable": "inutilisable"]
            for report in reports {
                let keywords = report.keywords.isEmpty ? "" : " [\(report.keywords.joined(separator: ", "))]"
                let missing = report.missing.isEmpty ? "" : " · manque : \(report.missing.joined(separator: ", "))"
                // Ordres à Alfred (SPEC-093 FR-006) : traduits par Roadie, puis ceux qui ne le sont pas.
                let alfred = (report.orders.isEmpty ? "" : " · ordres à Alfred : \(report.orders.joined(separator: ", "))")
                    + (report.untranslated.isEmpty ? "" : " · non traduits : \(report.untranslated.joined(separator: ", "))")
                out("\(state[report.state.rawValue] ?? report.state.rawValue)\t\(report.name)\(keywords) (\(report.source.rawValue))\(missing)\(alfred)")
            }
            if totals {
                let total = max(1, reports.count)
                let complete = reports.filter { $0.state == .complete }.count, partial = reports.filter { $0.state == .partial }.count
                out("total \(reports.count) · complets \(complete) (\(100 * complete / total) %) · avec une entrée complète \(complete + partial) (\(100 * (complete + partial) / total) %) · complets sans ordre non traduit \(reports.filter { $0.state == .complete && $0.untranslated.isEmpty }.count) · avec ordres à Alfred \(reports.filter(\.mentionsAlfred).count)")
            }
            if reports.isEmpty { out("aucun workflow") }
        }
        switch args.first ?? "" {
        case "list" where args.contains("--hotkeys"):
            // Raccourcis déclarés (SPEC-089 FR-002) : Roadie ne les capture pas ; la commande se lie dans BetterTouchTool.
            let config = configReload.currentConfig().experimental.targetMode
            let workflows = AlfredWorkflowIndex.shared.workflows(alfred: config.alfredWorkflows)
            let arguments = [0: "sélection", 1: "presse-papiers", 2: "presse-papiers de recherche", 3: "texte"]
            let hotkeys = AlfredWorkflowIndex.triggers(workflows).filter { $0.kind == .hotkey }
            for entry in hotkeys {
                let id = workflows.first { $0.id == entry.workflowID }.map { $0.bundleID.isEmpty ? $0.id : $0.bundleID } ?? entry.workflowID
                let argument = entry.hotkeyArgument == 3 ? "texte « \(entry.hotkeyText) »" : arguments[entry.hotkeyArgument] ?? "aucun"
                out("\(entry.workflowName)\t\(entry.keys.isEmpty ? "touches non attribuées" : entry.keys)\targument : \(argument)\troadie workflow run \(id) \(entry.objectUID)")
            }
            if hotkeys.isEmpty { out("aucun raccourci") }
            return 0
        case "run", "trigger":
            guard args.count >= 3 else { return usageError() }
            var payload = ["id": args[1], args[0] == "run" ? "object" : "trigger": args[2]]
            if args.count >= 4, !args[3].hasPrefix("--") { payload["argument"] = args[3] }
            var variables: [String: String] = [:]
            for (index, arg) in args.enumerated() where arg == "--var" && index + 1 < args.count {
                let parts = args[index + 1].split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 { variables[parts[0]] = parts[1] }
            }
            if !variables.isEmpty {
                payload["variables"] = String(data: try JSONSerialization.data(withJSONObject: variables), encoding: .utf8)
            }
            return try queueTargetModeRuntimeCommand(TargetModeRuntimeCommand(name: "workflow.\(args[0])", arguments: payload), json: json)
        case "alfred":
            return try runAlfredOrder(Array(args.dropFirst()), json: json)
        case "osascript":
            // `osascript` de Roadie (SPEC-093 FR-003) : ordres à Alfred traduits, puis le vrai osascript.
            AlfredBridge.execOsascript(Array(args.dropFirst()), cli: BTTShortcutBindingService().executable)
        case "tasks":
            guard args.count >= 2, args[1] == "update" else { return usageError() }
            let count = try AlfredAutomationTasks.update()
            out("tâches d'automatisation : \(count) dans \(AlfredAutomationTasks.root.path) (dépôt public alfredapp/automation-tasks, licence BSD-3 gardée à côté)")
            return 0
        case "list":
            let config = configReload.currentConfig().experimental.targetMode
            let workflows = AlfredWorkflowIndex.shared.workflows(alfred: config.alfredWorkflows)
            try show(workflows.map { AlfredCompatibility.report($0) }, totals: false)
            return 0
        case "check":
            guard args.count >= 2 else { return usageError() }
            let folder = URL(fileURLWithPath: NSString(string: args[1]).expandingTildeInPath, isDirectory: true)
            try show(AlfredCompatibility.check(folder: folder), totals: true)
            return 0
        case "install":
            guard args.count >= 2, !args[1].hasPrefix("--") else { return usageError() }
            let file = URL(fileURLWithPath: NSString(string: args[1]).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: file.path) else { err("workflow: introuvable : \(args[1])"); return 2 }
            // Décompression dans un dossier temporaire, puis rangement sous le nom de son identifiant.
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-workflow-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: staging) }
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-x", "-k", file.path, staging.path]
            try unzip.run()
            unzip.waitUntilExit()
            let root = FileManager.default.fileExists(atPath: staging.appendingPathComponent("info.plist").path) ? staging
                : AlfredWorkflowIndex.children(of: staging).first
            guard unzip.terminationStatus == 0, let root, let workflow = AlfredWorkflow.load(folder: root, source: .roadie) else {
                err("workflow: archive illisible (info.plist absent)")
                return 1
            }
            let name = (workflow.bundleID.isEmpty ? file.deletingPathExtension().lastPathComponent : workflow.bundleID)
                .replacingOccurrences(of: "/", with: "-")
            let target = AlfredWorkflowIndex.roadieFolder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: target.path) {
                guard args.contains("--replace") else { err("workflow: déjà installé : \(name) (--replace pour remplacer)"); return 1 }
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.createDirectory(at: AlfredWorkflowIndex.roadieFolder, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: root, to: target)
            let report = AlfredCompatibility.report(AlfredWorkflow.load(folder: target, source: .roadie) ?? workflow)
            out("installé : \(workflow.name) → \(target.path) (\(report.state.rawValue))")
            return 0
        case "remove":
            guard args.count >= 2 else { return usageError() }
            let target = AlfredWorkflowIndex.roadieFolder.appendingPathComponent(args[1].replacingOccurrences(of: "/", with: "-"))
            guard FileManager.default.fileExists(atPath: target.appendingPathComponent("info.plist").path) else {
                err("workflow: absent du dossier de Roadie : \(args[1]) (les workflows d'Alfred se retirent dans Alfred)")
                return 2
            }
            try FileManager.default.removeItem(at: target)
            out("retiré : \(args[1])")
            return 0
        default:
            return usageError()
        }
    }

    private func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag) else { return nil }
        let valueIndex = args.index(after: index)
        guard valueIndex < args.endIndex else { return nil }
        return args[valueIndex]
    }

    private func intValue(after flag: String, in args: [String], default defaultValue: Int) -> Int {
        value(after: flag, in: args).flatMap(Int.init) ?? defaultValue
    }

    private func queueTargetModeRuntimeCommand(_ command: TargetModeRuntimeCommand, json: Bool,
                                               notificationName: Notification.Name = TargetModeRuntimeNotification.name) throws -> Int32 {
        guard isTargetModeReceiverRunning() else {
            let result = TargetActionResult(
                changed: false,
                message: "roadied_not_running",
                error: "roadied_not_running"
            )
            if json {
                try printCodableJSON(result)
            } else {
                err("roadie: roadied_not_running; start it with roadie daemon restart")
            }
            return 1
        }
        DistributedNotificationCenter.default().postNotificationName(
            notificationName,
            object: "roadie",
            userInfo: command.userInfo,
            deliverImmediately: true
        )
        let result = TargetActionResult(changed: true, message: "queued_to_roadied: \(command.name)")
        if json {
            try printCodableJSON(result)
        } else {
            out(result.message)
        }
        return 0
    }

    /// Le récepteur du mode cible tourne : `roadied run` (qui le démarre sauf `--no-target-mode`)
    /// ou le composant modulaire `target-mode`. Un tiler modulaire seul ne suffit pas.
    private func isTargetModeReceiverRunning() -> Bool {
        let daemon = DaemonStatusReading.read()
        if daemon.isRunning, daemon.status?.mode == "run" {
            return true
        }
        return ComponentLockFile.registry().contains { $0.component == "target-mode" }
    }

    private func runPerformanceCommand(_ args: [String]) throws -> Int32 {
        guard let verb = args.first else {
            return usageError()
        }
        let performance = PerformanceLogService()
        let json = args.contains("--json")
        switch verb {
        case "summary":
            let report = performance.summary(limit: intValue(after: "--limit", in: args, default: 500))
            if json { try printCodableJSON(report) } else { out(TextFormatter.performanceSummary(report)) }
            return 0
        case "recent":
            let events = performance.recent(limit: intValue(after: "--limit", in: args, default: 20))
            if json { try printCodableJSON(events) } else { out(TextFormatter.performanceRecent(events)) }
            return 0
        case "thresholds":
            let thresholds = performance.thresholds()
            if json { try printCodableJSON(thresholds) } else { out(TextFormatter.performanceThresholds(thresholds)) }
            return 0
        default:
            return usageError()
        }
    }

    private func runRestoreCommand(_ args: [String]) throws -> Int32 {
        guard let verb = args.first else {
            return usageError()
        }
        let restore = RestoreSafetyService(service: service)
        let json = args.contains("--json")
        do {
            switch verb {
            case "snapshot":
                let snapshot = try restore.writeSnapshot()
                if json { try printCodableJSON(snapshot) } else { out("restore snapshot written windows=\(snapshot.windows.count)") }
                return 0
            case "status":
                let status = restore.status()
                if json { try printCodableJSON(status) } else { out(TextFormatter.restoreStatus(status)) }
                return status.exists ? 0 : 1
            case "unhide-all":
                let result = restore.unhideAll()
                if json { try printCodableJSON(result) } else { out(TextFormatter.restoreApply(result)) }
                return result.failed == 0 ? 0 : 1
            case "apply":
                guard args.contains("--yes") else {
                    err("roadie: restore apply requires --yes")
                    return 2
                }
                let result = try restore.apply()
                if json { try printCodableJSON(result) } else { out(TextFormatter.restoreApply(result)) }
                return result.failed == 0 ? 0 : 1
            default:
                return usageError()
            }
        } catch {
            err("roadie: restore \(verb) failed: \(error)")
            return 1
        }
    }

    private func runWidthLayoutCommand(_ args: [String]) -> WidthAdjustmentResult {
        guard let verb = args.first else {
            return .failure("layout width: requires next|prev|nudge|ratio")
        }
        let scope: WidthAdjustmentScope = args.contains("--all") ? .allWindows : .activeWindow
        let widthService = WidthAdjustmentService(service: service)
        let result: WidthAdjustmentResult
        switch verb {
        case "next":
            result = widthService.apply(WidthAdjustmentIntent(scope: scope, mode: .presetNext))
        case "prev", "previous":
            result = widthService.apply(WidthAdjustmentIntent(scope: scope, mode: .presetPrevious))
        case "nudge":
            result = widthService.apply(WidthAdjustmentIntent(
                scope: scope,
                mode: .nudge,
                delta: args.dropFirst().first.flatMap(Double.init)
            ))
        case "ratio":
            guard let raw = args.dropFirst().first, let ratio = Double(raw) else {
                return .failure("layout width ratio: requires numeric ratio")
            }
            result = widthService.apply(WidthAdjustmentIntent(scope: scope, mode: .explicitRatio, targetRatio: ratio))
        default:
            return .failure("layout width: requires next|prev|nudge|ratio")
        }
        return result
    }

    private func runDirectionalCommand(
        _ rawDirection: String?,
        verb: String,
        action: (Direction) -> WindowCommandResult
    ) -> Int32 {
        guard let rawDirection, let direction = Direction(rawValue: rawDirection) else {
            err("roadie: \(verb) requires left|right|up|down")
            return 64
        }
        let result = action(direction)
        return finish(result)
    }

    private func runWindowCommand(_ args: [String]) throws -> Int32 {
        switch args.first {
        case "bookmark":
            return try runBookmarkCommand(Array(args.dropFirst()))
        case "display":
            guard args.indices.contains(1), let index = Int(args[1]) else {
                err("roadie: window display requires an index")
                return 64
            }
            let result = WindowCommandService(service: service).sendToDisplay(index)
            return finish(result)
        case "reset":
            let result = WindowCommandService(service: service).reset()
            return finish(result)
        case "desktop":
            guard args.indices.contains(1), let id = Int(args[1]), id > 0 else {
                err("roadie: window desktop requires a positive id")
                return 64
            }
            let result = DesktopCommandService(service: service).assignActiveWindow(
                to: DesktopID(rawValue: id),
                follow: args.contains("--follow")
            )
            return finish(result)
        case "swap":
            return runDirectionalCommand(args.dropFirst().first, verb: "window swap") {
                WindowCommandService(service: service).move($0)
            }
        case "close":
            out("roadie: window close is not implemented in this build")
            return 1
        default:
            return usageError()
        }
    }

    private func runBookmarkCommand(_ args: [String]) throws -> Int32 {
        let command = WindowBookmarkCommandService(service: service, store: service.effectiveStageStore)
        switch args.first {
        case "set":
            guard let name = args.dropFirst().first else {
                err("roadie: bookmark set requires a name")
                return 64
            }
            let result = command.set(name)
            return finish(result)
        case "focus", "jump":
            guard let name = args.dropFirst().first else {
                err("roadie: bookmark focus requires a name")
                return 64
            }
            let result = command.focus(name)
            return finish(result)
        case "clear", "remove":
            guard let name = args.dropFirst().first else {
                err("roadie: bookmark clear requires a name")
                return 64
            }
            let result = command.clear(name)
            return finish(result)
        case "list":
            let result = command.list()
            out(result.message)
            return 0
        default:
            return usageError()
        }
    }

    private func runDesktopCommand(_ args: [String]) throws -> Int32 {
        switch args.first {
        case "list":
            let result = DesktopCommandService(service: service).list()
            out(result.message)
            return 0
        case "current":
            let result = DesktopCommandService(service: service).current()
            out(result.message)
            return 0
        case "label":
            guard let rawID = args.dropFirst().first, let id = Int(rawID), id > 0, !args.dropFirst(2).isEmpty else {
                err("roadie: desktop label requires a positive id and label")
                return 64
            }
            let result = DesktopCommandService(service: service).label(
                DesktopID(rawValue: id),
                as: args.dropFirst(2).joined(separator: " ")
            )
            return finish(result)
        case "focus":
            // Forme documentée « desktop focus N|prev|next|last|back|back-and-forth » : les mots-clés
            // reprennent les sous-commandes courtes (desktop next, desktop prev…).
            if let keyword = args.dropFirst().first, ["prev", "previous", "next", "last", "back", "back-and-forth"].contains(keyword) {
                return try runDesktopCommand([keyword == "previous" ? "prev" : keyword])
            }
            guard let rawID = args.dropFirst().first, let id = Int(rawID), id > 0 else {
                err("roadie: desktop focus requires N|prev|next|last|back|back-and-forth")
                return 64
            }
            let result = DesktopCommandService(service: service).focus(DesktopID(rawValue: id))
            return finish(result)
        case "prev", "previous":
            let result = DesktopCommandService(service: service).cycle(.prev)
            return finish(result)
        case "next":
            let result = DesktopCommandService(service: service).cycle(.next)
            return finish(result)
        case "last", "back":
            let result = DesktopCommandService(service: service).last()
            return finish(result)
        case "back-and-forth":
            let result = DesktopCommandService(service: service).backAndForth()
            return finish(result)
        case "summon":
            guard let rawID = args.dropFirst().first, let id = Int(rawID), id > 0 else {
                err("roadie: desktop summon requires a positive id")
                return 64
            }
            let result = DesktopCommandService(service: service).summon(DesktopID(rawValue: id))
            return finish(result)
        case "move":
            guard args.count == 3, let source = Int(args[1]), let target = Int(args[2]), source > 0, target > 0 else {
                err("roadie: desktop move requires N POSITION (positive numbers)")
                return 64
            }
            let result = DesktopCommandService(service: service).move(DesktopID(rawValue: source), to: DesktopID(rawValue: target))
            return finish(result)
        default:
            return usageError()
        }
    }

    private func runStageCommand(_ args: [String]) throws -> Int32 {
        switch args.first {
        case "list":
            let result = StageCommandService(service: service).list()
            out(result.message)
            return 0
        case "create":
            guard let stageID = args.dropFirst().first, !stageID.isEmpty else {
                err("roadie: stage create requires a stage id")
                return 64
            }
            let name = args.dropFirst(2).isEmpty ? nil : args.dropFirst(2).joined(separator: " ")
            let result = StageCommandService(service: service).create(stageID, name: name)
            return finish(result)
        case "rename":
            guard let stageID = args.dropFirst().first, !args.dropFirst(2).isEmpty else {
                err("roadie: stage rename requires a stage id and name")
                return 64
            }
            let result = StageCommandService(service: service).rename(stageID, to: args.dropFirst(2).joined(separator: " "))
            return finish(result)
        case "reorder":
            guard let stageID = args.dropFirst().first,
                  let rawPosition = args.dropFirst(2).first,
                  let position = Int(rawPosition), position > 0
            else {
                err("roadie: stage reorder requires a stage id and a positive numeric position")
                return 64
            }
            let result = StageCommandService(service: service).reorder(stageID, to: position)
            return finish(result)
        case "delete":
            guard let stageID = args.dropFirst().first else {
                err("roadie: stage delete requires a stage id")
                return 64
            }
            let result = StageCommandService(service: service).delete(stageID)
            return finish(result)
        case "mode":
            return try runModeCommand(args.dropFirst().first)
        case "switch":
            guard let stageID = args.dropFirst().first else {
                err("roadie: stage switch requires a stage id")
                return 64
            }
            let result = StageCommandService(service: service).switchTo(stageID)
            return finish(result)
        case "switch-position", "switch-pos":
            guard let rawPosition = args.dropFirst().first, let position = Int(rawPosition), position > 0 else {
                err("roadie: stage switch-position requires a positive position")
                return 64
            }
            let result = StageCommandService(service: service).switchToPosition(position)
            return finish(result)
        case "switch-visible":
            guard let rawDirection = args.dropFirst().first,
                  let direction = StageCycleDirection(rawValue: rawDirection)
            else {
                err("roadie: stage switch-visible requires prev|next")
                return 64
            }
            let result = StageCommandService(service: service).switchVisible(direction)
            return finish(result)
        case "assign":
            guard let stageID = args.dropFirst().first else {
                err("roadie: stage assign requires a stage id")
                return 64
            }
            let result = StageCommandService(service: service).assign(stageID)
            return finish(result)
        case "assign-position", "assign-pos":
            guard let rawPosition = args.dropFirst().first, let position = Int(rawPosition), position > 0 else {
                err("roadie: stage assign-position requires a positive position")
                return 64
            }
            let result = StageCommandService(service: service).assignPosition(position)
            return finish(result)
        case "assign-empty":
            let result = StageCommandService(service: service).assignEmpty()
            return finish(result)
        case "summon":
            guard let rawWindowID = args.dropFirst().first, let windowID = Self.windowID(rawWindowID) else {
                err("roadie: stage summon requires a positive window id")
                return 64
            }
            let snapshot = service.snapshot()
            let state = service.effectiveStageStore.state()
            guard let activeDisplayID = state.activeDisplayID ?? snapshot.focusedWindowID.flatMap({ focusedID in
                snapshot.windows.first { $0.window.id == focusedID }?.scope?.displayID
            }) ?? snapshot.displays.first?.id else {
                err("roadie: stage summon: no active display")
                return 1
            }
            let result = StageCommandService(service: service).summon(windowID: windowID, displayID: activeDisplayID)
            return finish(result)
        case "move-to-display":
            guard let rawTarget = args.dropFirst().first else {
                err("roadie: stage move-to-display requires a display index or direction")
                return 64
            }
            let flags = Array(args.dropFirst(2))
            let allowedFlags: Set<String> = ["--follow", "--no-follow"]
            if let unknown = flags.first(where: { !allowedFlags.contains($0) }) {
                err("roadie: unknown stage move-to-display option \(unknown)")
                return 64
            }
            if flags.contains("--follow"), flags.contains("--no-follow") {
                err("roadie: stage move-to-display accepts only one of --follow or --no-follow")
                return 64
            }
            let followFocus: Bool? = flags.contains("--follow") ? true : (flags.contains("--no-follow") ? false : nil)
            let commandService = StageCommandService(service: service)
            let result: StageCommandResult
            if let index = Int(rawTarget), index > 0 {
                result = commandService.moveActiveStageToDisplay(index: index, followFocus: followFocus)
            } else if let direction = Direction(rawValue: rawTarget) {
                result = commandService.moveActiveStageToDisplay(direction: direction, followFocus: followFocus)
            } else {
                err("roadie: stage move-to-display requires a display index or left|right|up|down")
                return 64
            }
            return finish(result)
        case "prev":
            let result = StageCommandService(service: service).cycle(.prev)
            return finish(result)
        case "next":
            let result = StageCommandService(service: service).cycle(.next)
            return finish(result)
        case .some(let rawStageID):
            let result = StageCommandService(service: service).switchTo(rawStageID)
            return finish(result)
        case nil:
            return usageError()
        }
    }

    private func runEventSubscription(_ args: [String]) throws -> Int32 {
        guard streamSink != nil else {
            err("roadie: events subscribe runs only in a local terminal")
            return 64
        }
        let options = try parseEventSubscriptionOptions(args)
        let subscription = EventSubscriptionService()
        var cursor = subscription.start(options: options)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let correlationId = emitCommandEvent(
            type: "command.received",
            command: "events.subscribe",
            result: "received"
        )
        for event in subscription.initialEvents(snapshot: service.snapshot().automationSnapshot(), options: options) {
            if let data = try? encoder.encode(event),
               let line = String(data: data, encoding: .utf8) {
                out(line)
            }
        }
        emitCommandEvent(
            type: "command.applied",
            command: "events.subscribe",
            result: "streaming",
            correlationId: correlationId
        )
        flushStream()
        while true {
            let result = subscription.readAvailable(from: cursor, options: options)
            cursor = result.cursor
            for event in result.events {
                if let data = try? encoder.encode(event),
                   let line = String(data: data, encoding: .utf8) {
                    out(line)
                }
            }
            flushStream()
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    @discardableResult
    private func emitCommandEvent(type: String, command: String, result: String, correlationId: String = UUID().uuidString) -> String {
        EventLog().append(RoadieEventEnvelope(
            id: "cmd_\(UUID().uuidString)",
            type: type,
            scope: .command,
            subject: AutomationSubject(kind: "command", id: command),
            correlationId: correlationId,
            cause: .command,
            payload: [
                "command": .string(command),
                "result": .string(result)
            ]
        ))
        return correlationId
    }

    private func parseEventSubscriptionOptions(_ args: [String]) throws -> EventSubscriptionOptions {
        var fromNow = false
        var initialState = false
        var types = Set<String>()
        var scopes = Set<AutomationScope>()
        var index = 0
        while index < args.count {
            switch args[index] {
            case "--from-now":
                fromNow = true
                index += 1
            case "--initial-state":
                initialState = true
                index += 1
            case "--type":
                guard args.indices.contains(index + 1) else {
                    err("roadie: events subscribe --type requires a value")
                    throw CLIExit(code: 64)
                }
                types.insert(args[index + 1])
                index += 2
            case "--scope":
                guard args.indices.contains(index + 1) else {
                    err("roadie: events subscribe --scope requires a value")
                    throw CLIExit(code: 64)
                }
                scopes.insert(AutomationScope(rawValue: args[index + 1]))
                index += 2
            case let unknown:
                err("roadie: unknown events subscribe option \(unknown)")
                throw CLIExit(code: 64)
            }
        }
        return EventSubscriptionOptions(fromNow: fromNow, initialState: initialState, types: types, scopes: scopes)
    }

    private func runRulesCommand(_ args: [String]) throws -> Int32 {
        guard let verb = args.first, ["validate", "list", "explain"].contains(verb) else {
            return usageError()
        }
        let options = try parseRulesOptions(Array(args.dropFirst()))
        let service = RulesCommandService(configPath: options.configPath)

        switch verb {
        case "validate":
            let report = service.validate()
            if options.json {
                try printCodableJSON(report)
            } else {
                out(TextFormatter.configValidation(report))
            }
            return report.hasErrors ? 1 : 0
        case "list":
            do {
                let rules = try service.list()
                if options.json {
                    try printCodableJSON(rules)
                } else {
                    out(TextFormatter.rules(rules))
                }
                return 0
            } catch {
                err("roadie: rules list failed: \(error)")
                return 1
            }
        case "explain":
            guard let app = options.app else {
                err("roadie: rules explain requires --app APP")
                return 64
            }
            let window = WindowSnapshot(
                id: WindowID(rawValue: 1),
                pid: 0,
                appName: app,
                bundleID: options.bundleID ?? "",
                title: options.title ?? "",
                frame: Rect(x: 0, y: 0, width: 1, height: 1),
                isOnScreen: true,
                isTileCandidate: true
            )
            let context = WindowRuleMatchContext(
                role: options.role,
                subrole: options.subrole,
                display: options.display,
                desktop: options.desktop,
                stage: options.stage,
                isFloating: options.isFloating
            )
            do {
                let explanation = try service.explain(window: window, context: context)
                if options.json {
                    try printCodableJSON(explanation)
                } else {
                    out(TextFormatter.ruleExplanation(explanation))
                }
                return explanation.matchedRuleID == nil ? 1 : 0
            } catch {
                err("roadie: rules explain failed: \(error)")
                return 1
            }
        default:
            return usageError()
        }
    }

    private func runGroupCommand(_ args: [String]) throws -> Int32 {
        let service = WindowGroupCommandService(service: self.service, store: self.service.effectiveStageStore)
        switch args.first {
        case "list":
            let result = service.list()
            out(result.message)
            return 0
        case "create":
            guard let id = args.dropFirst().first else {
                err("roadie: group create requires an id")
                return 64
            }
            let ids = args.dropFirst(2).compactMap(Self.windowID)
            let result = service.create(id: id, windowIDs: ids)
            return finish(result)
        case "add":
            guard let id = args.dropFirst().first,
                  let rawWindowID = args.dropFirst(2).first,
                  let windowID = Self.windowID(rawWindowID)
            else {
                err("roadie: group add requires GROUP_ID WINDOW_ID")
                return 64
            }
            let result = service.add(windowID: windowID, to: id)
            return finish(result)
        case "remove":
            guard let id = args.dropFirst().first,
                  let rawWindowID = args.dropFirst(2).first,
                  let windowID = Self.windowID(rawWindowID)
            else {
                err("roadie: group remove requires GROUP_ID WINDOW_ID")
                return 64
            }
            let result = service.remove(windowID: windowID, from: id)
            return finish(result)
        case "focus":
            guard let id = args.dropFirst().first,
                  let rawWindowID = args.dropFirst(2).first,
                  let windowID = Self.windowID(rawWindowID)
            else {
                err("roadie: group focus requires GROUP_ID WINDOW_ID")
                return 64
            }
            let result = service.focus(windowID: windowID, in: id)
            return finish(result)
        case "dissolve":
            guard let id = args.dropFirst().first else {
                err("roadie: group dissolve requires GROUP_ID")
                return 64
            }
            let result = service.dissolve(id: id)
            return finish(result)
        default:
            return usageError()
        }
    }

    private func runTargetsCommand(_ args: [String]) throws -> Int32 {
        guard let verb = args.first else {
            return usageError()
        }
        let json = args.contains("--json")
        let options = parseTargetOptions(Array(args.dropFirst()))
        let targets = TargetHintService(service: service)

        switch verb {
        case "list":
            let report = targets.list(options)
            if json {
                try printCodableJSON(report)
            } else {
                out(TextFormatter.targets(report))
            }
            return report.error == nil || !report.targets.isEmpty ? 0 : 1
        case "pick":
            guard let query = positionalTargetArgument(Array(args.dropFirst())) else {
                err("roadie: targets pick requires QUERY_OR_LABEL")
                return 64
            }
            let action = value(after: "--action", in: args).flatMap(TargetActionVerb.init(rawValue:))
            let result = targets.pick(query, action: action, options: options)
            if json {
                try printCodableJSON(result)
            } else {
                out(TextFormatter.targetPick(result))
            }
            return result.error == nil ? 0 : 1
        case "inspect":
            guard service.effectiveConfig.experimental.targetMode.enabled else {
                let result = TargetActionResult(changed: false, message: "target_mode_disabled", error: "target_mode_disabled")
                if json {
                    try printCodableJSON(result)
                } else {
                    err("roadie: target_mode_disabled")
                }
                return 1
            }
            guard let targetValue = positionalTargetArgument(Array(args.dropFirst())) else {
                err("roadie: targets inspect requires TARGET_ID_OR_LABEL")
                return 64
            }
            switch TargetInspectionService(service: service).inspect(targetValue) {
            case .success(let inspection):
                if json {
                    try printCodableJSON(inspection)
                } else {
                    out(TextFormatter.targetInspection(inspection))
                }
                return 0
            case .failure(let error):
                let result = TargetActionResult(changed: false, message: error.description, error: error.description)
                if json {
                    try printCodableJSON(result)
                } else {
                    err("roadie: \(error.description)")
                }
                return 1
            }
        case "activate":
            guard let targetValue = positionalTargetArgument(Array(args.dropFirst())) else {
                err("roadie: targets activate requires TARGET_ID_OR_LABEL")
                return 64
            }
            let action = value(after: "--action", in: args).flatMap(TargetActionVerb.init(rawValue:))
            let result = targets.activate(targetValue, action: action)
            if json {
                try printCodableJSON(result)
            } else {
                out(result.message)
            }
            return result.error == nil ? 0 : 1
        case "show":
            let overlay = targets.overlayState(options: options, labelsOnly: args.contains("--labels-only"), visible: true)
            if args.contains("--visual") {
                let config = service.effectiveConfig.experimental.targetMode
                guard config.overlayEnabled else {
                    let result = TargetActionResult(changed: false, message: "target_overlay_disabled", error: "target_overlay_disabled")
                    if json {
                        try printCodableJSON(result)
                    } else {
                        err("roadie: target_overlay_disabled; set experimental.target_mode.overlay_enabled = true")
                    }
                    return 1
                }
                let duration = value(after: "--duration", in: args).flatMap(Double.init) ?? config.overlayDurationSeconds
                TargetOverlayPresenter.present(overlay, duration: duration, style: .labels(config))
                return 0
            }
            if json {
                try printCodableJSON(overlay)
            } else {
                out(TextFormatter.targetOverlay(overlay))
            }
            return 0
        case "interactive":
            var payload: [String: String] = [
                "source": options.source.rawValue,
                "max": String(options.maxResults),
                "includeHidden": String(options.includeHidden),
                "includeAppTargets": String(options.includeAppTargets)
            ]
            if let filter = options.filter {
                payload["filter"] = filter
            }
            if let duration = value(after: "--duration", in: args) {
                payload["duration"] = duration
            }
            if let action = value(after: "--action", in: args) {
                payload["action"] = action
            }
            return try queueTargetModeRuntimeCommand(TargetModeRuntimeCommand(name: "targets.interactive", arguments: payload), json: json)
        case "search":
            // SPEC-021 : même session que le raccourci global `search_hotkey`.
            return try queueTargetModeRuntimeCommand(TargetModeRuntimeCommand(name: "targets.search"), json: json)
        case "actions":
            // SPEC-075 : la barre ouverte aux verbes de la fenêtre active.
            return try queueTargetModeRuntimeCommand(TargetModeRuntimeCommand(name: "targets.actions"), json: json)
        case "hide":
            let result = targets.overlayState(options: options, labelsOnly: true, visible: false)
            if json {
                try printCodableJSON(result)
            } else {
                out(TextFormatter.targetOverlay(result))
            }
            return 0
        default:
            return usageError()
        }
    }

    private func parseTargetOptions(_ args: [String]) -> TargetQueryOptions {
        let source = value(after: "--source", in: args).flatMap(TargetSource.init(rawValue:)) ?? .roadie
        return TargetQueryOptions(
            source: source,
            filter: value(after: "--filter", in: args),
            maxResults: intValue(after: "--max", in: args, default: 120),
            includeHidden: args.contains("--include-hidden"),
            includeAppTargets: args.contains("--include-app-targets")
        )
    }

    private func positionalTargetArgument(_ args: [String]) -> String? {
        var index = 0
        while index < args.count {
            let item = args[index]
            if ["--json", "--include-hidden", "--include-app-targets", "--labels-only", "--visual"].contains(item) {
                index += 1
                continue
            }
            if ["--source", "--filter", "--max", "--action", "--duration"].contains(item) {
                index += 2
                continue
            }
            return item
        }
        return nil
    }

    private func runGridCommand(_ args: [String]) throws -> Int32 {
        guard let verb = args.first else {
            return usageError()
        }
        let json = args.contains("--json")
        let grid = TargetGridService(service: service)
        let displayIndex = intValue(after: "--display", in: args, default: -1)
        let effectiveDisplay = displayIndex >= 0 ? displayIndex : nil
        let scope = value(after: "--scope", in: args).flatMap(TargetGridScope.init(rawValue:))
        let path = positionalGridArgument(Array(args.dropFirst()))

        switch verb {
        case "interactive":
            var payload: [String: String] = [:]
            if let path {
                payload["path"] = path
            }
            if let effectiveDisplay {
                payload["display"] = String(effectiveDisplay)
            }
            if let scope {
                payload["scope"] = scope.rawValue
            }
            if let duration = value(after: "--duration", in: args) {
                payload["duration"] = duration
            }
            return try queueTargetModeRuntimeCommand(TargetModeRuntimeCommand(name: "grid.interactive", arguments: payload), json: json)
        case "show":
            let parentPath = path ?? ""
            let report = grid.report(displayIndex: effectiveDisplay, parentPath: parentPath, scope: scope)
            if args.contains("--visual") {
                guard service.effectiveConfig.experimental.targetGrid.overlayEnabled else {
                    let result = TargetActionResult(changed: false, message: "target_grid_overlay_disabled", error: "target_grid_overlay_disabled")
                    if json { try printCodableJSON(result) } else { err("roadie: target_grid_overlay_disabled") }
                    return 1
                }
                let targetsReport = grid.targets(displayIndex: effectiveDisplay, parentPath: parentPath, scope: scope)
                let overlay = TargetOverlayState(visible: true, labelsOnly: true, report: targetsReport)
                let duration = value(after: "--duration", in: args).flatMap(Double.init) ?? service.effectiveConfig.experimental.targetMode.overlayDurationSeconds
                TargetOverlayPresenter.present(overlay, duration: duration, style: TargetOverlayStyle.grid(service.effectiveConfig.experimental.targetGrid))
                return 0
            }
            if json {
                try printCodableJSON(report)
            } else {
                out(TextFormatter.targetGrid(report))
            }
            return report.error == nil ? 0 : 1
        case "click", "double-click", "right-click", "move", "scroll-up", "scroll-down":
            guard let path else {
                err("roadie: grid \(verb) requires PATH")
                return 64
            }
            let action = TargetGridAction(rawValue: verb)!
            let result = grid.perform(action, path: path, displayIndex: effectiveDisplay, scope: scope)
            if json { try printCodableJSON(result) } else { out(result.message) }
            return result.error == nil ? 0 : 1
        case "drag":
            guard let from = path,
                  let to = value(after: "--to", in: args) ?? secondGridArgument(Array(args.dropFirst())) else {
                err("roadie: grid drag requires FROM TO")
                return 64
            }
            let result = grid.perform(.drag, path: from, to: to, displayIndex: effectiveDisplay, scope: scope)
            if json { try printCodableJSON(result) } else { out(result.message) }
            return result.error == nil ? 0 : 1
        default:
            return usageError()
        }
    }

    private func runRecordCommand(_ args: [String]) throws -> Int32 {
        guard let verb = args.first else {
            return usageError()
        }
        let json = args.contains("--json")
        let recorder = TargetMacroService(service: service)
        switch verb {
        case "start":
            guard let name = positionalGridArgument(Array(args.dropFirst())) else {
                err("roadie: record start requires NAME")
                return 64
            }
            let duration = value(after: "--duration", in: args).flatMap(Double.init)
            let stopFilePath = value(after: "--stop-file", in: args)
            let result = recorder.record(name: name, duration: duration, stopFilePath: stopFilePath)
            if json { try printCodableJSON(result) } else { out(result.message) }
            return result.error == nil ? 0 : 1
        case "replay":
            guard let name = positionalGridArgument(Array(args.dropFirst())) else {
                err("roadie: record replay requires NAME")
                return 64
            }
            let result = recorder.replay(name)
            if json { try printCodableJSON(result) } else { out(result.message) }
            return result.error == nil ? 0 : 1
        case "list":
            let report = recorder.list()
            if json { try printCodableJSON(report) } else { out(TextFormatter.targetMacroList(report)) }
            return 0
        case "inspect":
            guard let name = positionalGridArgument(Array(args.dropFirst())) else {
                err("roadie: record inspect requires NAME")
                return 64
            }
            do {
                let recording = try recorder.inspect(name)
                if json { try printCodableJSON(recording) } else { out(TextFormatter.targetMacro(recording)) }
                return 0
            } catch {
                if json {
                    try printCodableJSON(TargetActionResult(changed: false, message: error.localizedDescription, error: "record_not_found"))
                } else {
                    err("roadie: record inspect failed: \(error.localizedDescription)")
                }
                return 1
            }
        case "delete":
            guard let name = positionalGridArgument(Array(args.dropFirst())) else {
                err("roadie: record delete requires NAME")
                return 64
            }
            do {
                let result = try recorder.delete(name)
                if json { try printCodableJSON(result) } else { out(result.message) }
                return 0
            } catch {
                if json {
                    try printCodableJSON(TargetActionResult(changed: false, message: error.localizedDescription, error: "record_delete_failed"))
                } else {
                    err("roadie: record delete failed: \(error.localizedDescription)")
                }
                return 1
            }
        default:
            return usageError()
        }
    }

    private func positionalGridArgument(_ args: [String]) -> String? {
        var index = 0
        while index < args.count {
            let item = args[index]
            if ["--json", "--visual"].contains(item) {
                index += 1
                continue
            }
            if ["--display", "--duration", "--to", "--stop-file", "--scope"].contains(item) {
                index += 2
                continue
            }
            return item
        }
        return nil
    }

    private func secondGridArgument(_ args: [String]) -> String? {
        var values: [String] = []
        var index = 0
        while index < args.count {
            let item = args[index]
            if ["--json", "--visual"].contains(item) {
                index += 1
                continue
            }
            if ["--display", "--duration", "--to", "--scope"].contains(item) {
                index += 2
                continue
            }
            values.append(item)
            index += 1
        }
        return values.dropFirst().first
    }

    private func runQueryCommand(_ args: [String]) throws -> Int32 {
        guard let name = args.first else {
            return usageError()
        }
        let result = AutomationQueryService(service: service).query(name)
        if case .object(let object) = result.data,
           object["error"] != nil {
            try printCodableJSON(result)
            return 64
        }
        try printCodableJSON(result)
        return 0
    }

    struct RulesOptions {
        var json = false
        var configPath: String?
        var app: String?
        var bundleID: String?
        var title: String?
        var role: String?
        var subrole: String?
        var display: String?
        var desktop: String?
        var stage: String?
        var isFloating: Bool?
    }

    private func parseRulesOptions(_ args: [String]) throws -> RulesOptions {
        var options = RulesOptions()
        var index = 0
        while index < args.count {
            switch args[index] {
            case "--json":
                options.json = true
                index += 1
            case "--config":
                options.configPath = try requiredRulesOption(args, index: index, name: "--config")
                index += 2
            case "--app":
                options.app = try requiredRulesOption(args, index: index, name: "--app")
                index += 2
            case "--bundle-id":
                options.bundleID = try requiredRulesOption(args, index: index, name: "--bundle-id")
                index += 2
            case "--title":
                options.title = try requiredRulesOption(args, index: index, name: "--title")
                index += 2
            case "--role":
                options.role = try requiredRulesOption(args, index: index, name: "--role")
                index += 2
            case "--subrole":
                options.subrole = try requiredRulesOption(args, index: index, name: "--subrole")
                index += 2
            case "--display":
                options.display = try requiredRulesOption(args, index: index, name: "--display")
                index += 2
            case "--desktop":
                options.desktop = try requiredRulesOption(args, index: index, name: "--desktop")
                index += 2
            case "--stage":
                options.stage = try requiredRulesOption(args, index: index, name: "--stage")
                index += 2
            case "--floating":
                options.isFloating = true
                index += 1
            case "--tiled":
                options.isFloating = false
                index += 1
            case let unknown:
                err("roadie: unknown rules option \(unknown)")
                throw CLIExit(code: 64)
            }
        }
        return options
    }

    private func requiredRulesOption(_ args: [String], index: Int, name: String) throws -> String {
        guard args.indices.contains(index + 1) else {
            err("roadie: rules \(name) requires a value")
            throw CLIExit(code: 64)
        }
        return args[index + 1]
    }

    private func runModeCommand(_ rawMode: String?) throws -> Int32 {
        guard let rawMode, let parsed = WindowManagementMode(roadieValue: rawMode) else {
            err("roadie: mode requires bsp|spatialBsp|masterStack|float")
            return 64
        }
        // `mutableBsp` (et `yabai`) reste accepté comme alias de l'arbre (SPEC-017 A8).
        let mode: WindowManagementMode = parsed == .mutableBsp ? .spatialBsp : parsed
        let result = StageCommandService(service: service).setMode(mode)
        return finish(result)
    }

    /// `daemon restart` : relance le service launchd installé (T092, aucun chemin utilisateur).
    private func restartDaemon() -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "-k", "gui/\(getuid())/\(Self.launchdLabel)"]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            err("roadie: failed to run launchctl: \(error)")
            return 1
        }
        if process.terminationStatus != 0 {
            err("roadie: launchctl kickstart failed (status \(process.terminationStatus)); is the \(Self.launchdLabel) LaunchAgent installed? see roadie doctor")
        }
        return process.terminationStatus
    }
}

/// Lecture du statut daemon : vivant si le pid existe et si le statut a moins de 90 s.
public struct DaemonStatusReading: Equatable, Sendable {
    public var status: DaemonStatus?
    /// `running`, `no_status`, `pid_not_alive` ou `status_stale`.
    public var state: String

    public var isRunning: Bool { state == "running" }

    public init(status: DaemonStatus?, state: String) {
        self.status = status
        self.state = state
    }

    public static func read(
        path: String = DaemonStatus.defaultPath,
        now: Date = Date(),
        isAlive: (Int32) -> Bool = ProcessLiveness.isAlive
    ) -> DaemonStatusReading {
        guard let status = DaemonStatus.load(from: path) else {
            return DaemonStatusReading(status: nil, state: "no_status")
        }
        guard isAlive(status.pid) else {
            return DaemonStatusReading(status: status, state: "pid_not_alive")
        }
        guard now.timeIntervalSince(status.updatedAt) <= DaemonStatus.staleAfter else {
            return DaemonStatusReading(status: status, state: "status_stale")
        }
        return DaemonStatusReading(status: status, state: "running")
    }
}
