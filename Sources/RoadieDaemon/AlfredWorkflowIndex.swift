import Foundation
import UniformTypeIdentifiers

/// Entrée tapée d'un workflow (SPEC-088) : mot-clé d'un Script Filter ou d'une entrée Keyword.
struct AlfredEntry: Equatable, Sendable {
    enum Kind: String, Sendable {
        case scriptFilter, keyword, listFilter, fileFilter
        /// Déclencheurs (SPEC-089) : pas de mot-clé tapé.
        case hotkey, external, fileAction, universalAction, fallback
        /// Grille ouverte par un schéma (SPEC-092) : jamais indexée par mot-clé.
        case grid
    }
    enum Argument: Int, Sendable { case required = 0, optional = 1, none = 2 }

    let workflowID: String
    let workflowName: String
    let objectUID: String
    let kind: Kind
    let keyword: String
    /// Une espace sépare le mot-clé de l'argument.
    let withSpace: Bool
    let argument: Argument
    let title: String
    let subtitle: String
    let icon: String?
    /// Dossier du workflow : base des icônes relatives.
    var folder = ""
    /// « Alfred filtre les résultats » : le script tourne une fois, la barre filtre (mode d'Alfred).
    var filtersResults = false
    var filterMode = 0
    /// Sous-titre pendant que le script tourne.
    var runningSubtitle = ""
    /// Déclencheurs (SPEC-089) : identifiant externe, ce qu'accepte une action, touches d'un raccourci
    /// (« ⌥⌘G », vide si non attribuées) et son argument (0 sélection, 1 presse-papiers, 3 texte, 4 aucun).
    var triggerID = ""
    var acceptsFiles = false
    var acceptsText = false
    var acceptsURLs = false
    var fileTypes: [String] = []
    var keys = ""
    var hotkeyArgument = 0
    var hotkeyText = ""
    /// Filtre de liste (SPEC-089 FR-005) : ses éléments fixes, sans script.
    var listItems: [AlfredItem] = []

    var id: String { "wf:\(workflowID):\(objectUID)" }

    /// Ce que la saisie fait de cette entrée : rien, la proposer (mot-clé en cours, argument manquant),
    /// ou la lancer avec l'argument tapé. Casse ignorée sur le mot-clé. O(k).
    enum Match: Equatable { case none, suggest, run(String) }

    func match(_ query: String) -> Match {
        let lower = query.lowercased(), key = keyword.lowercased()
        guard !key.isEmpty else { return .none }
        var rest: String?
        if lower == key {
            rest = ""
        } else if withSpace, lower.hasPrefix(key + " ") {
            rest = String(query.dropFirst(key.count + 1))
        } else if !withSpace, lower.hasPrefix(key) {
            rest = String(query.dropFirst(key.count))
        }
        guard let rest else {
            // Mot-clé en cours de frappe (2 lettres au moins) ou titre qui correspond.
            if query.count >= 2, key.hasPrefix(lower) || LauncherMatch.score(query, in: title) != nil { return .suggest }
            return .none
        }
        let argument = rest.trimmingCharacters(in: .whitespaces)
        switch self.argument {
        case .required: return argument.isEmpty ? .suggest : .run(argument)
        case .optional: return .run(argument)
        case .none: return argument.isEmpty ? .run("") : .none
        }
    }
}

/// Workflows lus pour la barre et la commande (SPEC-088 FR-001) : dossier d'Alfred (lecture seule) et
/// dossier de Roadie. Un workflow n'est relu que si son `info.plist` ou son `prefs.plist` a changé.
final class AlfredWorkflowIndex: @unchecked Sendable {
    static let shared = AlfredWorkflowIndex()

    /// Dossier des workflows de Roadie.
    static var roadieFolder: URL {
        URL(fileURLWithPath: NSString(string: "~/.config/roadies/workflows").expandingTildeInPath, isDirectory: true)
    }

    /// Dossier de préférences d'Alfred : clé `current` de `prefs.json` (dossier synchronisé compris),
    /// sinon l'emplacement par défaut ; nil s'il n'existe pas. O(1).
    static func alfredPreferences(home: String = NSHomeDirectory()) -> URL? {
        let support = URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/Alfred")
        if let data = try? Data(contentsOf: support.appendingPathComponent("prefs.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let current = json["current"] as? String, FileManager.default.fileExists(atPath: current) {
            return URL(fileURLWithPath: current, isDirectory: true)
        }
        let fallback = support.appendingPathComponent("Alfred.alfredpreferences", isDirectory: true)
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }

    private struct Cached { let stamp: [Date?]; let workflow: AlfredWorkflow }
    private let lock = NSLock()
    private var cache: [String: Cached] = [:]

    /// Workflows actifs des sources demandées, triés par nom. O(W) dates lues, O(W × o) au rechargement.
    func workflows(alfred: Bool, roadie: Bool = true) -> [AlfredWorkflow] {
        var folders: [(URL, AlfredWorkflow.Source)] = []
        if alfred, let preferences = Self.alfredPreferences() {
            folders += Self.children(of: preferences.appendingPathComponent("workflows")).map { ($0, .alfred) }
        }
        if roadie { folders += Self.children(of: Self.roadieFolder).map { ($0, .roadie) } }
        return workflows(in: folders)
    }

    /// Workflows de ces dossiers, relus seulement s'ils ont changé.
    func workflows(in folders: [(URL, AlfredWorkflow.Source)]) -> [AlfredWorkflow] {
        lock.withLock {
            folders.compactMap { folder, source in
                let key = "\(source.rawValue):\(folder.path)"
                let stamp = ["info.plist", "prefs.plist"].map {
                    (try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent($0).path))?[.modificationDate] as? Date
                }
                if let cached = cache[key], cached.stamp == stamp { return cached.workflow }
                guard let workflow = AlfredWorkflow.load(folder: folder, source: source) else { return nil }
                cache[key] = Cached(stamp: stamp, workflow: workflow)
                return workflow
            }
            .filter { !$0.disabled }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    static func children(of folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("info.plist").path) }
    }

    /// Entrées tapées des workflows ; mot-clé `{var:…}` résolu par les réglages. O(W × o).
    static func entries(_ workflows: [AlfredWorkflow]) -> [AlfredEntry] {
        var entries: [AlfredEntry] = []
        for workflow in workflows {
            let variables = workflow.configuredVariables
            for object in workflow.objects.values {
                let kind: AlfredEntry.Kind? = switch object.type {
                case "input.scriptfilter": .scriptFilter
                case "input.keyword": .keyword
                case "input.listfilter": .listFilter
                case "input.filefilter": .fileFilter
                default: nil
                }
                guard let kind, object.config["disabled"]?.bool != true else { continue }
                let keyword = AlfredPlaceholders.expand(object.string("keyword") ?? "", query: "", variables: variables)
                    .trimmingCharacters(in: .whitespaces)
                guard !keyword.isEmpty else { continue }
                let title = AlfredPlaceholders.expand(object.string("title") ?? object.string("text") ?? "", query: "", variables: variables)
                var entry = AlfredEntry(
                    workflowID: workflow.id, workflowName: workflow.name, objectUID: object.uid, kind: kind, keyword: keyword,
                    withSpace: object.config["withspace"]?.bool ?? true,
                    argument: AlfredEntry.Argument(rawValue: object.int("argumenttype") ?? 0) ?? .required,
                    title: title.isEmpty ? workflow.name : title,
                    subtitle: AlfredPlaceholders.expand(object.string("subtext") ?? "", query: "", variables: variables),
                    icon: workflow.icon(for: object.uid))
                entry.folder = workflow.folder.path
                entry.filtersResults = object.bool("alfredfiltersresults")
                entry.filterMode = object.int("alfredfiltersresultsmatchmode") ?? 0
                entry.runningSubtitle = object.string("runningsubtext") ?? ""
                if kind == .listFilter {
                    entry.filtersResults = true
                    entry.filterMode = object.int("matchmode") ?? 0
                    if let data = (object.string("items") ?? "").data(using: .utf8),
                       let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                        entry.listItems = AlfredScriptFilterResponse.parse(json: ["items": items]).items
                    }
                }
                entries.append(entry)
            }
        }
        return entries.sorted { ($0.keyword, $0.workflowName) < ($1.keyword, $1.workflowName) }
    }

    /// Déclencheurs des workflows : raccourcis, appels externes, actions sur fichier, actions
    /// universelles, recherches de repli (SPEC-089). O(W × o).
    static func triggers(_ workflows: [AlfredWorkflow]) -> [AlfredEntry] {
        var found: [AlfredEntry] = []
        for workflow in workflows {
            let variables = workflow.configuredVariables
            for object in workflow.objects.values {
                let kind: AlfredEntry.Kind? = switch object.type {
                case "trigger.hotkey": .hotkey
                case "trigger.external": .external
                case "trigger.action": .fileAction
                case "trigger.universalaction": .universalAction
                case "trigger.fallback": .fallback
                default: nil
                }
                guard let kind else { continue }
                let name = AlfredPlaceholders.expand(object.string("name") ?? object.string("text") ?? "", query: "{query}", variables: variables)
                var entry = AlfredEntry(workflowID: workflow.id, workflowName: workflow.name, objectUID: object.uid, kind: kind, keyword: "",
                                        withSpace: false, argument: .optional, title: name.isEmpty ? workflow.name : name, subtitle: workflow.name,
                                        icon: workflow.icon(for: object.uid))
                entry.folder = workflow.folder.path
                entry.triggerID = object.string("triggerid") ?? ""
                entry.acceptsFiles = kind == .fileAction || object.bool("acceptsfiles")
                entry.acceptsText = object.bool("acceptstext")
                entry.acceptsURLs = object.bool("acceptsurls")
                entry.fileTypes = (object.config["filetypes"]?.array ?? []).compactMap(\.string)
                entry.hotkeyArgument = object.int("argument") ?? 0
                entry.hotkeyText = object.string("argumenttext") ?? ""
                entry.keys = keys(modifiers: object.int("hotmod") ?? 0, key: object.string("hotstring") ?? "")
                found.append(entry)
            }
        }
        return found.sorted { ($0.workflowName, $0.title) < ($1.workflowName, $1.title) }
    }

    /// Touches d'un raccourci d'Alfred, dans l'ordre de macOS (⌃⌥⇧⌘). Vide sans touche. O(1).
    static func keys(modifiers: Int, key: String) -> String {
        guard !key.isEmpty else { return "" }
        let symbols = [(262_144, "⌃"), (524_288, "⌥"), (131_072, "⇧"), (1_048_576, "⌘")].filter { modifiers & $0.0 != 0 }.map(\.1)
        return symbols.joined() + key.uppercased()
    }

    /// Un fichier convient-il à une action ? Types vides : tous ; sinon le type du fichier doit
    /// se conformer à l'un d'eux (UTI). O(t).
    static func accepts(_ entry: AlfredEntry, path: String) -> Bool {
        guard entry.acceptsFiles else { return false }
        guard !entry.fileTypes.isEmpty else { return true }
        guard let type = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
        return entry.fileTypes.contains { identifier in UTType(identifier).map { type.conforms(to: $0) } ?? false }
    }
}
