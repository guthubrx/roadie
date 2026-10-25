import Foundation
import RoadieCore

/// Action gardée par ⌘S (SPEC-079) : une application ou un fichier, par son chemin, et où l'ouvrir. La
/// stage est gardée par son nom réel et retrouvée à l'usage ; une fenêtre ou une stage ne survivent
/// pas à leur fermeture, elles ne se gardent pas.
struct LauncherAlias: Codable, Equatable, Sendable {
    static let maxLength = 12

    let path: String
    let isApp: Bool
    let bundleID: String?
    let name: String
    let stage: String?
    let here: Bool
    let newStage: Bool
    let position: LauncherPosition?

    /// Abréviation acceptable : un mot de 1 à 12 caractères. O(n).
    static func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed.count <= maxLength && !trimmed.contains(" ")
    }

    /// nil avec la raison si l'action ne se garde pas. `stageName` : nom réel d'une stage, nil si anonyme.
    static func from(_ action: LauncherAction, stageName: (StageScope) -> String?) -> Result<LauncherAlias, Refusal> {
        let path: String, isApp: Bool, bundleID: String?, name: String
        switch action.subject {
        case .app(let app): (path, isApp, bundleID, name) = (app.path, true, app.bundleID, app.name)
        case .file(let file): (path, isApp, bundleID, name) = (file.path, false, nil, file.name)
        case .target: return .failure(.notDurable)
        case .project: return .failure(.unsupportedVerb)
        }
        var stage: String?, here = false, newStage = false
        switch (action.verb, action.destination?.kind) {
        case (.open, nil): break
        case (.bringHere, _): here = true
        case (.openIn, .newStage?): newStage = true
        case (.openIn, .stage(let scope)?):
            guard let named = stageName(scope) else { return .failure(.anonymousStage) }
            stage = named
        default: return .failure(.unsupportedVerb)
        }
        return .success(LauncherAlias(path: path, isApp: isApp, bundleID: bundleID, name: name, stage: stage,
                                      here: here, newStage: newStage, position: action.position))
    }

    enum Refusal: Error, Equatable {
        case notDurable, anonymousStage, unsupportedVerb

        var message: String {
            switch self {
            case .notDurable: "Seules les applications et les fichiers se gardent : une fenêtre ou une stage peut disparaître."
            case .anonymousStage: "Nommez d'abord cette stage : une stage anonyme ne se retrouve pas."
            case .unsupportedVerb: "Ce verbe ne se garde pas ; gardez Ouvrir, Ouvrir dans ou Amener ici."
            }
        }
    }

    /// L'action d'aujourd'hui : la stage retrouvée par son nom ; nil si elle n'existe plus. O(S).
    func action(state: PersistentStageState, activeStage: StageScope?, home: (DisplayID, DesktopID)) -> LauncherAction? {
        let subject: LauncherSubject = if isApp {
            .app(LauncherApp(bundleID: bundleID ?? "", path: path, name: name, alternateNames: []))
        } else {
            .file(LauncherFile(path: path, name: name, isFolder: false, lastUsed: nil))
        }
        var action: LauncherAction
        if let stage {
            guard let scope = LauncherSearchContext.stage(for: "stage:\(LauncherMatch.fold(stage))", in: state) else { return nil }
            action = LauncherAction(subject: subject, verb: .openIn, destination: LauncherDestination(kind: .stage(scope), title: stage, detail: ""))
        } else if newStage {
            action = LauncherAction(subject: subject, verb: .openIn,
                                    destination: LauncherDestination(kind: .newStage(name: nil, home.0, home.1), title: "Nouvelle stage", detail: ""))
        } else if here {
            guard let activeStage else { return nil }
            action = LauncherAction(subject: subject, verb: .bringHere, destination: LauncherDestination(kind: .stage(activeStage), title: "ici", detail: ""))
        } else {
            action = LauncherAction(subject: subject, verb: .open, destination: nil)
        }
        action.position = position
        return action
    }

    /// Même action hors de la barre, à coller dans BetterTouchTool ou un terminal.
    var command: String {
        var parts = ["roadie", "launch", Self.quoted(path)]
        if let stage { parts += ["--stage", Self.quoted(stage)] }
        if here { parts.append("--here") }
        if newStage { parts.append("--new-stage") }
        if let position { parts += ["--position", position.rawValue] }
        return parts.joined(separator: " ")
    }

    private static func quoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

/// Abréviations de l'utilisateur, `~/.roadies/launcher-aliases.json` : local, jamais transmis.
struct LauncherAliasBook: Codable, Equatable, Sendable {
    var aliases: [String: LauncherAlias] = [:]

    func alias(for query: String) -> (String, LauncherAlias)? {
        let key = LauncherMatch.fold(query)
        return aliases[key].map { (key, $0) }
    }
}

struct LauncherAliasStore: Sendable {
    let url: URL

    init(path: String = TestEnvironment.launcherFile("launcher-aliases.json")) {
        url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    func load() -> LauncherAliasBook { JSONPersistence.load(LauncherAliasBook.self, from: url, default: LauncherAliasBook()) }

    /// Une abréviation déjà prise est remplacée. Renvoie l'ancienne action remplacée, s'il y en avait une.
    @discardableResult
    func save(_ alias: LauncherAlias, as name: String) -> LauncherAlias? {
        var book = load()
        let key = LauncherMatch.fold(name)
        let previous = book.aliases[key]
        book.aliases[key] = alias
        JSONPersistence.write(book, to: url, label: "launcher aliases")
        return previous
    }
}
