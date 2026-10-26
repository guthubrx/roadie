import Foundation

/// Entrée tapée d'un workflow (SPEC-088) : mot-clé d'un Script Filter ou d'une entrée Keyword.
struct AlfredEntry: Equatable, Sendable {
    enum Kind: String, Sendable { case scriptFilter, keyword, listFilter, fileFilter }
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
                entries.append(AlfredEntry(
                    workflowID: workflow.id, workflowName: workflow.name, objectUID: object.uid, kind: kind, keyword: keyword,
                    withSpace: object.config["withspace"]?.bool ?? true,
                    argument: AlfredEntry.Argument(rawValue: object.int("argumenttype") ?? 0) ?? .required,
                    title: title.isEmpty ? workflow.name : title,
                    subtitle: AlfredPlaceholders.expand(object.string("subtext") ?? "", query: "", variables: variables),
                    icon: workflow.icon(for: object.uid)))
            }
        }
        return entries.sorted { ($0.keyword, $0.workflowName) < ($1.keyword, $1.workflowName) }
    }
}
