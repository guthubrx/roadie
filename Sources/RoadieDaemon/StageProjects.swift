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

/// Plan de lancement calculé pour rouvrir une scène de travail (Spec 162) : pur et testable.
struct StageProjectLaunchPlan: Equatable, Sendable {
    let missingApps: [String]
    let urlsToOpen: [String]
    let windowCount: Int
    let hasTree: Bool
}

/// Stage nommée gardée comme projet/scène : ses fenêtres dans l'ordre, la forme de sa disposition
/// (feuilles = rangs à partir de 1) et ses métadonnées enrichies optionnelles (Spec 162 : URLs/dossiers
/// supplémentaires, applications à lancer si absentes, nombre d'écrans, note).
struct StageProject: Codable, Equatable, Sendable {
    let name: String
    let savedAt: Date
    let windows: [ProjectWindow]
    let tree: BSPTree?
    var extraURLs: [String]
    var launchApps: [String]
    var displayCount: Int
    var notes: String?

    init(
        name: String,
        savedAt: Date,
        windows: [ProjectWindow],
        tree: BSPTree?,
        extraURLs: [String] = [],
        launchApps: [String] = [],
        displayCount: Int = 1,
        notes: String? = nil
    ) {
        self.name = name
        self.savedAt = savedAt
        self.windows = windows
        self.tree = tree
        self.extraURLs = extraURLs
        self.launchApps = launchApps
        self.displayCount = max(1, displayCount)
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case name, savedAt, windows, tree
        case extraURLs, launchApps, displayCount, notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.savedAt = try c.decode(Date.self, forKey: .savedAt)
        self.windows = try c.decode([ProjectWindow].self, forKey: .windows)
        self.tree = try c.decodeIfPresent(BSPTree.self, forKey: .tree)
        self.extraURLs = try c.decodeIfPresent([String].self, forKey: .extraURLs) ?? []
        self.launchApps = try c.decodeIfPresent([String].self, forKey: .launchApps) ?? []
        self.displayCount = max(1, try c.decodeIfPresent(Int.self, forKey: .displayCount) ?? 1)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }

    /// Fenêtres vivantes d'une stage, dans l'ordre de ses membres ; l'arbre ne garde que leurs feuilles,
    /// remplacées par leur rang. O(m + f).
    static func capture(
        name: String,
        members: [WindowID],
        windows: [WindowID: ProjectWindow],
        tree: BSPTree?,
        at now: Date,
        extraURLs: [String] = [],
        launchApps: [String] = [],
        displayCount: Int = 1,
        notes: String? = nil
    ) -> StageProject {
        let kept = members.filter { windows[$0] != nil }
        let rank = Dictionary(uniqueKeysWithValues: kept.enumerated().map { ($1, $0 + 1) })
        let ranked = tree.map { tree in
            let absent = Set(tree.windowIDs).subtracting(kept)
            return renamed(tree.projected(excluding: absent)) { rank[$0].map { WindowID(rawValue: UInt32($0)) } }
        }
        return StageProject(
            name: name,
            savedAt: now,
            windows: kept.compactMap { windows[$0] },
            tree: ranked.flatMap { $0.isEmpty ? nil : $0 },
            extraURLs: extraURLs,
            launchApps: launchApps,
            displayCount: displayCount,
            notes: notes
        )
    }

    /// Calcule les applications absentes à lancer et les URLs/dossiers supplémentaires à ouvrir (Spec 162).
    /// Résout l'identité d'une application fournie par chemin `.app` afin d'éviter un double lancement.
    func launchPlan(
        runningBundleIDs: Set<String>,
        runningAppPaths: Set<String> = [],
        bundleIDResolver: (String) -> String? = { Bundle(path: $0)?.bundleIdentifier }
    ) -> StageProjectLaunchPlan {
        let normalizedRunningPaths = Set(runningAppPaths.map {
            URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath).standardizedFileURL.path
        })
        var missing: [String] = []
        var seenKeys = Set<String>()
        for app in launchApps {
            let trimmed = app.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let looksLikePath = trimmed.hasPrefix("/") || trimmed.hasPrefix("~") || trimmed.hasSuffix(".app")
            let standardizedPath: String? = looksLikePath
                ? URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath).standardizedFileURL.path
                : nil
            let resolvedBundleID = standardizedPath.flatMap(bundleIDResolver)
            if runningBundleIDs.contains(trimmed) { continue }
            if let resolvedBundleID, runningBundleIDs.contains(resolvedBundleID) { continue }
            if let standardizedPath, normalizedRunningPaths.contains(standardizedPath) { continue }
            let dedupKey = resolvedBundleID ?? standardizedPath ?? trimmed
            guard seenKeys.insert(dedupKey).inserted else { continue }
            missing.append(trimmed)
        }
        let urls = extraURLs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return StageProjectLaunchPlan(
            missingApps: missing,
            urlsToOpen: urls,
            windowCount: windows.count,
            hasTree: tree != nil
        )
    }

    /// Encode une liste de chaînes sans ambiguïté (JSON array) pour le transport de commandes runtime.
    static func encodeStringList(_ values: [String]) -> String? {
        guard !values.isEmpty, let data = try? JSONEncoder().encode(values) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Décode une liste encodée en tableau JSON (avec repli sur une chaîne simple non vide).
    static func decodeStringList(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        if let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return decoded.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? [] : [trimmed]
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
        case .tabGroup(let ids, let active):
            let renamedIDs = ids.compactMap(name)
            return BSPTree.normalizedTabGroup(renamedIDs, active: name(active))
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

    func save(_ project: StageProject) throws {
        try JSONPersistence.mutateChecked(StageProjectBook.self, at: url, default: StageProjectBook(), label: "stage projects") { book in
            book.projects[LauncherMatch.fold(project.name)] = project
        }
    }

    @discardableResult
    func delete(_ name: String) throws -> Bool {
        try JSONPersistence.mutateChecked(StageProjectBook.self, at: url, default: StageProjectBook(), label: "stage projects") { book in
            book.projects.removeValue(forKey: LauncherMatch.fold(name)) != nil
        }
    }
}
