import Foundation

/// Chemin tapé dans la barre (SPEC-087) : dossier à lire et suite qui filtre ses éléments.
struct LauncherPathQuery: Equatable, Sendable {
    /// Dossier lu, chemin absolu.
    let directory: String
    /// Suite tapée après le dernier `/` : filtre des éléments.
    let prefix: String
    /// Début tapé du dossier, `~` gardé : sert à la complétion (`~/Doc` → `~/`).
    let typedBase: String
    /// Chemin complet désigné par la saisie, s'il existe : en premier.
    var exact: String { (directory as NSString).appendingPathComponent(prefix) }
}

/// Règles des chemins tapés, pures et testables.
enum LauncherPathRules {
    /// `/` : chemin si un second `/` est tapé, ou si le premier nom commence un élément de `/` sans
    /// commencer une commande ni un alias du mode commande (research R3) ; sinon mode commande.
    /// `~` : toujours un chemin. O(c + r).
    static func isPath(_ query: String, commands: [String], rootEntries: [String]) -> Bool {
        if query == "~" || query.hasPrefix("~/") { return true }
        guard query.hasPrefix("/") else { return false }
        let rest = query.dropFirst()
        if rest.contains("/") { return true }
        let first = rest.lowercased()
        guard !first.isEmpty, !commands.contains(where: { $0.lowercased().hasPrefix(first) }) else { return false }
        return rootEntries.contains { $0.lowercased().hasPrefix(first) }
    }

    /// Noms et alias du mode commande.
    static var commandNames: [String] { SlashCommandCatalog.commands.flatMap { [$0.name] + $0.aliases } }

    /// Éléments visibles de `/`, lus une fois.
    static let rootEntries: [String] = ((try? FileManager.default.contentsOfDirectory(atPath: "/")) ?? []).filter { !$0.hasPrefix(".") }

    /// Dossier et suite d'un chemin tapé. O(n).
    static func parts(_ query: String, home: String = NSHomeDirectory()) -> LauncherPathQuery {
        let slash = query.lastIndex(of: "/")
        let typedBase = slash.map { String(query[...$0]) } ?? (query == "~" ? "~/" : "/")
        let prefix = slash.map { String(query[query.index(after: $0)...]) } ?? (query == "~" ? "" : query)
        let base = typedBase.hasPrefix("~") ? home + typedBase.dropFirst() : typedBase
        return LauncherPathQuery(directory: base.count > 1 && base.hasSuffix("/") ? String(base.dropLast()) : base,
                                 prefix: prefix, typedBase: typedBase)
    }

    /// ⌫ sur un chemin qui finit par `/` (session 105) : le dossier parent, `/` final gardé ; nil à la racine
    /// (`/`, `~/`) ou hors d'un chemin de dossier. O(n).
    static func parent(_ query: String) -> String? {
        guard query.hasSuffix("/"), query != "/", query != "~/" else { return nil }
        let trimmed = query.dropLast()
        guard let slash = trimmed.lastIndex(of: "/") else { return nil }
        return String(trimmed[...slash])
    }

    /// Saisie après Tab sur un élément : début tapé du dossier, nom, `/` pour un dossier. O(n).
    static func completion(_ file: LauncherFile, in query: LauncherPathQuery) -> String {
        query.typedBase + file.name + (file.isFolder ? "/" : "")
    }

    /// Éléments d'un dossier qui correspondent à la suite : l'élément exact d'abord, puis dossiers et
    /// fichiers par nom ; cachés seulement si la suite commence par `.`. O(e + k log k), e éléments lus.
    /// `dates` : date de tri par nom d'élément (session 105, `path_sort` = modified ou created), plus récent
    /// d'abord ; vide : ordre des noms.
    static func filter(_ names: [(name: String, isFolder: Bool)], query: LauncherPathQuery, keep: Int = 200,
                       dates: [String: Date] = [:]) -> [LauncherFile] {
        let hidden = query.prefix.hasPrefix(".")
        let folded = LauncherMatch.fold(query.prefix)
        var found: [(file: LauncherFile, score: Int)] = []
        for entry in names where hidden || !entry.name.hasPrefix(".") {
            let score: Int
            if folded.isEmpty {
                score = 0
            } else if let matched = LauncherMatch.score(query.prefix, in: entry.name) {
                score = matched
            } else { continue }
            let path = (query.directory as NSString).appendingPathComponent(entry.name)
            found.append((LauncherFile(path: path, name: entry.name, isFolder: entry.isFolder, lastUsed: nil), score))
        }
        let exact = LauncherMatch.fold(query.prefix)
        return found.sorted { a, b in
            let ea = LauncherMatch.fold(a.file.name) == exact, eb = LauncherMatch.fold(b.file.name) == exact
            if ea != eb { return ea }
            if a.score != b.score { return a.score > b.score }
            if a.file.isFolder != b.file.isFolder { return a.file.isFolder }
            if !dates.isEmpty {
                let da = dates[a.file.name] ?? .distantPast, db = dates[b.file.name] ?? .distantPast
                if da != db { return da > db }
            }
            return a.file.name.localizedStandardCompare(b.file.name) == .orderedAscending
        }.prefix(keep).map(\.file)
    }
}

/// Lecture d'un dossier hors du fil principal ; seule la dernière demande est rendue (research R4).
@MainActor
final class LauncherPathListing {
    private var generation = 0
    /// Éléments parcourus au plus : un dossier énorme ne retient pas la barre.
    nonisolated static let scanLimit = 5_000

    func list(_ query: LauncherPathQuery, sort: String = "name", done: @escaping @MainActor ([LauncherFile]) -> Void) {
        generation += 1
        let current = generation
        DispatchQueue.global(qos: .userInitiated).async {
            let names = Self.read(query.directory)
            let key: URLResourceKey? = sort == "modified" ? .contentModificationDateKey : sort == "created" ? .creationDateKey : nil
            let dates = key.map { Self.dates(query.directory, names: names, key: $0) } ?? [:]
            let files = LauncherPathRules.filter(names, query: query, dates: dates)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard self.generation == current else { return }
                    done(files)
                }
            }
        }
    }

    func cancel() { generation += 1 }

    /// Dates d'un dossier pour le tri (session 105). O(e).
    nonisolated static func dates(_ directory: String, names: [(name: String, isFolder: Bool)], key: URLResourceKey) -> [String: Date] {
        var dates: [String: Date] = [:]
        for entry in names {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(entry.name)
            if let values = try? url.resourceValues(forKeys: [key]) {
                dates[entry.name] = key == .creationDateKey ? values.creationDate : values.contentModificationDate
            }
        }
        return dates
    }

    nonisolated static func read(_ directory: String) -> [(name: String, isFolder: Bool)] {
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey],
                                                               options: [.skipsSubdirectoryDescendants, .skipsPackageDescendants]) else { return [] }
        var names: [(name: String, isFolder: Bool)] = []
        for case let item as URL in enumerator {
            let isFolder = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            // Une application est un paquet : elle s'ouvre, on n'y entre pas.
            names.append((item.lastPathComponent, isFolder && item.pathExtension != "app"))
            if names.count >= scanLimit { break }
        }
        return names
    }
}
