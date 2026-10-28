import Foundation
import RoadieCore
import RoadieTiler

/// Fenêtre d'un projet : de quoi la rouvrir (SPEC-080). Document ou adresse quand l'application les
/// expose ; sinon une nouvelle fenêtre de l'application.
struct ProjectWindow: Codable, Equatable, Sendable {
    let bundleID: String
    let appPath: String
    let document: String?
    let url: String?
    let title: String
}

/// Stage nommée gardée comme projet : ses fenêtres dans l'ordre et la forme de sa disposition, dont les
/// feuilles sont les rangs des fenêtres à partir de 1 (`WindowID(rang)`, un identifiant est positif).
struct StageProject: Codable, Equatable, Sendable {
    let name: String
    let savedAt: Date
    let windows: [ProjectWindow]
    let tree: BSPTree?

    /// Fenêtres vivantes d'une stage, dans l'ordre de ses membres ; l'arbre ne garde que leurs feuilles,
    /// remplacées par leur rang. O(m + f).
    static func capture(name: String, members: [WindowID], windows: [WindowID: ProjectWindow], tree: BSPTree?, at now: Date) -> StageProject {
        let kept = members.filter { windows[$0] != nil }
        let rank = Dictionary(uniqueKeysWithValues: kept.enumerated().map { ($1, $0 + 1) })
        let ranked = tree.map { tree in
            let absent = Set(tree.windowIDs).subtracting(kept)
            return renamed(tree.projected(excluding: absent)) { rank[$0].map { WindowID(rawValue: UInt32($0)) } }
        }
        return StageProject(name: name, savedAt: now, windows: kept.compactMap { windows[$0] },
                            tree: ranked.flatMap { $0.isEmpty ? nil : $0 })
    }

    /// Arbre remis sur les fenêtres rouvertes, rang pour rang ; nil s'il en manque une. O(f).
    func tree(for reopened: [WindowID]) -> BSPTree? {
        guard let tree, reopened.count == windows.count else { return nil }
        return Self.renamed(tree) { id in Int(exactly: id.rawValue).flatMap { $0 >= 1 && $0 <= reopened.count ? reopened[$0 - 1] : nil } }
    }

    /// Feuilles renommées ; une feuille sans nouveau nom disparaît (son frère remonte). O(f).
    private static func renamed(_ tree: BSPTree, _ name: (WindowID) -> WindowID?) -> BSPTree {
        switch tree {
        case .empty: return .empty
        case .leaf(let id): return name(id).map(BSPTree.leaf) ?? .empty
        case .split(let orientation, let ratio, let first, let second):
            let a = renamed(first, name), b = renamed(second, name)
            if a.isEmpty { return b }
            if b.isEmpty { return a }
            return .split(orientation: orientation, ratio: ratio, first: a, second: b)
        }
    }
}

/// Projets de l'utilisateur, `~/.roadies/projects.json` : local. Un même nom remplace le projet.
struct StageProjectBook: Codable, Equatable, Sendable {
    var projects: [String: StageProject] = [:]

    func project(named name: String) -> StageProject? { projects[LauncherMatch.fold(name)] }
}

struct StageProjectStore: Sendable {
    let url: URL

    init(path: String = TestEnvironment.launcherFile("projects.json")) {
        url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    func load() -> StageProjectBook { JSONPersistence.load(StageProjectBook.self, from: url, default: StageProjectBook()) }

    func save(_ project: StageProject) {
        var book = load()
        book.projects[LauncherMatch.fold(project.name)] = project
        JSONPersistence.write(book, to: url, label: "stage projects")
    }

    @discardableResult
    func delete(_ name: String) -> Bool {
        var book = load()
        guard book.projects.removeValue(forKey: LauncherMatch.fold(name)) != nil else { return false }
        JSONPersistence.write(book, to: url, label: "stage projects")
        return true
    }
}
