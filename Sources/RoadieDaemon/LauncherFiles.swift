import AppKit
import Foundation
import RoadieAX

/// Fichier ou dossier trouvé par Spotlight pour le lanceur (SPEC-077).
struct LauncherFile: Equatable, Hashable, Sendable {
    let path: String
    let name: String
    let isFolder: Bool
    let lastUsed: Date?

    var rankingKey: String { "file:\(path)" }
    /// Dossier qui le contient, abrégé en `~`.
    var location: String { LauncherList.shortPath((path as NSString).deletingLastPathComponent) }
    var folder: String { (path as NSString).deletingLastPathComponent }
}

/// Mots-clés de la recherche dans le contenu et par étiquette (session 113), comme `in` et `tags` d'Alfred ;
/// vide : désactivé.
struct LauncherFileKeywords: Equatable, Sendable {
    var content = "in"
    var tag = "tags"
    /// `open` et `find` d'Alfred (session 119) : fichiers seuls ; avec `find`, Retour les montre dans le Finder.
    var open = "open"
    var find = "find"
}

/// Saisie de la recherche de fichiers : par nom (SPEC-077), dans le contenu ou par étiquette Finder
/// (session 113). `filesOnly` : seuls les fichiers sont montrés.
struct LauncherFileQuery: Equatable, Sendable {
    enum Mode: Equatable, Sendable { case name, content, tag }
    var mode: Mode
    var needle: String
    var filesOnly: Bool
    /// `find` : Retour montre le fichier dans le Finder au lieu de l'ouvrir (session 119).
    var reveals = false

    /// Une espace ou une apostrophe en tête : nom seul. `in rapport`, `tags rouge` : contenu, étiquette ;
    /// le mot-clé doit être suivi d'une espace (`inbox` reste un nom). O(n).
    static func parse(_ query: String, keywords: LauncherFileKeywords = LauncherFileKeywords()) -> LauncherFileQuery {
        if query.hasPrefix(" ") || query.hasPrefix("'") {
            return LauncherFileQuery(mode: .name, needle: String(query.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines), filesOnly: true)
        }
        let lowered = query.lowercased()
        for (keyword, mode, reveals) in [(keywords.content, Mode.content, false), (keywords.tag, Mode.tag, false),
                                         (keywords.open, Mode.name, false), (keywords.find, Mode.name, true)] {
            let keyword = keyword.trimmingCharacters(in: .whitespaces).lowercased()
            guard !keyword.isEmpty, lowered.hasPrefix(keyword + " ") else { continue }
            return LauncherFileQuery(mode: mode, needle: String(query.dropFirst(keyword.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines),
                                     filesOnly: true, reveals: reveals)
        }
        return LauncherFileQuery(mode: .name, needle: query.trimmingCharacters(in: .whitespacesAndNewlines), filesOnly: false)
    }
}

/// Règles de la recherche de fichiers, pures et testables. O(1) par chemin.
enum LauncherFileRules {
    /// Familles montrées par défaut, comme les « Extras » d'Alfred : dossiers, documents, textes, images.
    static let contentTypes = ["public.folder", "public.text", "public.image", "com.adobe.pdf",
                               "public.composite-content", "public.spreadsheet", "public.presentation"]
    static let limit = 40

    /// Saisie qui ne cherche que des fichiers : une espace ou une apostrophe en tête (recherche rapide),
    /// ou un mot-clé de contenu ou d'étiquette (session 113).
    static func filesOnly(_ query: String, keywords: LauncherFileKeywords = LauncherFileKeywords()) -> Bool {
        LauncherFileQuery.parse(query, keywords: keywords).filesOnly
    }

    /// Texte cherché : sans le préfixe ni le mot-clé, ni les espaces autour.
    static func needle(_ query: String, keywords: LauncherFileKeywords = LauncherFileKeywords()) -> String {
        LauncherFileQuery.parse(query, keywords: keywords).needle
    }

    /// 3 caractères au moins, 2 en recherche rapide, de contenu ou d'étiquette : en deçà, trop de réponses.
    static func shouldSearch(_ query: String, keywords: LauncherFileKeywords = LauncherFileKeywords()) -> Bool {
        let parsed = LauncherFileQuery.parse(query, keywords: keywords)
        return parsed.needle.count >= (parsed.filesOnly ? 2 : 3)
    }

    /// Couleurs du Finder : macOS les enregistre sous leur nom anglais, même affichées en français.
    static let tagColors = ["rouge": "Red", "orange": "Orange", "jaune": "Yellow", "vert": "Green", "bleu": "Blue",
                            "violet": "Purple", "gris": "Gray"]

    /// Texte placé entre guillemets dans une requête Spotlight : `\`, `"` et `*` neutralisés. O(n).
    static func quoted(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "*", with: "\\*")
    }

    /// Requête Spotlight : par nom (familles d'`contentTypes`) ; contenu : chaque mot comme début de mot du
    /// texte (0,1 s contre 3 s pour un texte partiel sur ce poste) ; étiquette : début d'un nom d'étiquette,
    /// ou sa couleur en anglais. O(m) mots.
    /// `extraTypes` : types ajoutés par `file_types` (session 119), comme les Extras et l'Avancé d'Alfred.
    static func predicate(_ query: LauncherFileQuery, extraTypes: [String] = []) -> NSPredicate {
        switch query.mode {
        case .name:
            return predicate(query.needle, extraTypes: extraTypes)
        case .content:
            let words = query.needle.split(whereSeparator: \.isWhitespace).map { "kMDItemTextContent == \"\(quoted(String($0)))*\"cdw" }
            let content = NSPredicate(fromMetadataQueryString: words.joined(separator: " && ")) ?? NSPredicate(value: false)
            return NSCompoundPredicate(andPredicateWithSubpredicates: [content, types(extraTypes)])
        case .tag:
            let names = [query.needle] + (tagColors[LauncherMatch.fold(query.needle)].map { [$0] } ?? [])
            let text = names.map { "kMDItemUserTags == \"\(quoted($0))*\"cd" }.joined(separator: " || ")
            return NSPredicate(fromMetadataQueryString: text) ?? NSPredicate(value: false)
        }
    }

    /// Familles cherchées : celles d'`contentTypes` et les types ajoutés (un type couvre aussi ses sous-types). O(t).
    private static func types(_ extra: [String]) -> NSPredicate {
        NSCompoundPredicate(orPredicateWithSubpredicates: (contentTypes + extra).map { NSPredicate(format: "kMDItemContentTypeTree == %@", $0) })
    }

    /// Dossiers de `~/Library` gardés, comme la portée d'Alfred (session 113) : OneDrive, Dropbox, Google Drive
    /// (`CloudStorage`) et iCloud Drive (`Mobile Documents`).
    static let libraryFolders = ["/Library/CloudStorage/", "/Library/Mobile Documents/"]

    /// Dossier personnel hors `~/Library` (sauf les stockages en ligne), sans élément caché ni dépendances de projet,
    /// ni dossier écarté par `file_excluded_folders` (session 119, chemins absolus ou en `~`). O(e + p).
    static func isShown(_ path: String, home: String = NSHomeDirectory(), excluded: [String] = []) -> Bool {
        guard path.hasPrefix(home + "/") else { return false }
        if excluded.contains(where: { folder in
            let root = folder.hasPrefix("~/") ? home + folder.dropFirst() : folder
            return !root.isEmpty && (path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/"))
        }) { return false }
        if path.hasPrefix(home + "/Library/"), !libraryFolders.contains(where: { path.hasPrefix(home + $0) }) { return false }
        let relative = path.dropFirst(home.count + 1)
        return !relative.split(separator: "/").contains { $0.hasPrefix(".") || $0 == "node_modules" }
    }

    /// Même requête que `predicate`, dans la syntaxe de Spotlight, pour `MDQuery` hors du fil principal
    /// (session 123). O(t + mots).
    static func queryString(_ query: LauncherFileQuery, extraTypes: [String] = []) -> String {
        let kinds = "(" + (contentTypes + extraTypes).map { "kMDItemContentTypeTree == \"\(quoted($0))\"" }.joined(separator: " || ") + ")"
        switch query.mode {
        case .name:
            return "kMDItemDisplayName == \"*\(quoted(query.needle))*\"cd && \(kinds)"
        case .content:
            let words = query.needle.split(whereSeparator: \.isWhitespace).map { "kMDItemTextContent == \"\(quoted(String($0)))*\"cdw" }
            return (words + [kinds]).joined(separator: " && ")
        case .tag:
            let names = [query.needle] + (tagColors[LauncherMatch.fold(query.needle)].map { [$0] } ?? [])
            return names.map { "kMDItemUserTags == \"\(quoted($0))*\"cd" }.joined(separator: " || ")
        }
    }

    /// Fichiers utilisés ces `days` derniers jours, des familles cherchées : la liste locale instantanée.
    static func recentQueryString(days: Int, extraTypes: [String] = []) -> String {
        let kinds = "(" + (contentTypes + extraTypes).map { "kMDItemContentTypeTree == \"\(quoted($0))\"" }.joined(separator: " || ") + ")"
        return "kMDItemLastUsedDate >= $time.today(-\(days)) && \(kinds)"
    }

    static func predicate(_ needle: String, extraTypes: [String] = []) -> NSPredicate {
        let name = NSPredicate(format: "kMDItemDisplayName LIKE[cd] %@", "*\(needle)*")
        return NSCompoundPredicate(andPredicateWithSubpredicates: [name, types(extraTypes)])
    }

    /// Les plus récemment utilisés d'abord, puis par nom. O(f log f).
    static func ordered(_ files: [LauncherFile]) -> [LauncherFile] {
        files.sorted { a, b in
            if a.lastUsed != b.lastUsed { return (a.lastUsed ?? .distantPast) > (b.lastUsed ?? .distantPast) }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}

/// Requête Spotlight synchrone, à lancer hors du fil principal (session 123) : dossier personnel, les plus
/// récemment utilisés d'abord, chemins montrés seulement. `limit` nil : tous. O(r) attributs lus au plus.
enum LauncherSpotlight {
    nonisolated static func files(_ queryString: String, excluded: [String], limit: Int?) -> [LauncherFile] {
        guard let query = MDQueryCreate(kCFAllocatorDefault, queryString as CFString, nil, [kMDItemLastUsedDate] as CFArray) else { return [] }
        MDQuerySetSearchScope(query, [kMDQueryScopeHome] as CFArray, 0)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        // Comme `NSMetadataQuery` trié par date décroissante : les fichiers datés du plus récent au plus ancien,
        // puis ceux jamais ouverts. Date lue dans le tri de la requête, sans relire l'élément. O(r).
        let count = MDQueryGetResultCount(query)
        var dated: [CFIndex] = [], undated: [CFIndex] = []
        for index in 0..<count {
            let value = MDQueryGetAttributeValueOfResultAtIndex(query, kMDItemLastUsedDate, index)
                .map { Unmanaged<CFTypeRef>.fromOpaque($0).takeUnretainedValue() }
            if value is Date { dated.append(index) } else { undated.append(index) }
        }
        var files: [LauncherFile] = []
        for index in dated.reversed() + undated {
            if let limit, files.count >= limit { break }
            guard let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String,
                  LauncherFileRules.isShown(path, excluded: excluded) else { continue }
            let types = MDItemCopyAttribute(item, kMDItemContentTypeTree) as? [String] ?? []
            files.append(LauncherFile(path: path,
                                      name: MDItemCopyAttribute(item, kMDItemDisplayName) as? String ?? (path as NSString).lastPathComponent,
                                      isFolder: types.contains("public.folder"),
                                      lastUsed: MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date))
        }
        return LauncherFileRules.ordered(files)
    }
}

/// Fichiers déjà ouverts (dix ans : un millier de fichiers ici), lus en fond et gardés 5 minutes (session 123) : la barre y cherche
/// à chaque frappe, avec la règle de Spotlight (nom qui contient la saisie, casse et accents ignorés), avant
/// que Spotlight ne réponde pour tous les fichiers.
final class LauncherRecentFiles: @unchecked Sendable {
    static let shared = LauncherRecentFiles()
    static let days = 3650

    private struct Entry { let file: LauncherFile; let name: String }
    private let lock = NSLock()
    private var cached: (key: String, at: Date, entries: [Entry])?
    private var loading = false

    /// Relit la liste en fond si elle a plus de 5 minutes ou d'autres réglages. O(1) sur l'appelant.
    func refresh(extraTypes: [String], excluded: [String], now: Date = Date()) {
        let key = "\(extraTypes)|\(excluded)"
        let start = lock.withLock { () -> Bool in
            if loading { return false }
            if let cached, cached.key == key, now.timeIntervalSince(cached.at) < 300 { return false }
            loading = true
            return true
        }
        guard start else { return }
        DispatchQueue.global(qos: .utility).async { [self] in
            let files = LauncherSpotlight.files(LauncherFileRules.recentQueryString(days: Self.days, extraTypes: extraTypes),
                                                excluded: excluded, limit: nil)
            let entries = files.map { Entry(file: $0, name: LauncherMatch.fold($0.name)) }
            lock.withLock {
                cached = (key, Date(), entries)
                loading = false
            }
        }
    }

    /// Fichiers récents dont le nom contient la saisie, les plus récents d'abord. O(n).
    func matches(_ needle: String, limit: Int = LauncherFileRules.limit) -> [LauncherFile] {
        let folded = LauncherMatch.fold(needle)
        guard !folded.isEmpty else { return [] }
        let entries = lock.withLock { cached?.entries ?? [] }
        var found: [LauncherFile] = []
        for entry in entries where entry.name.contains(folded) {
            found.append(entry.file)
            if found.count == limit { break }
        }
        return found
    }
}

/// Recherche Spotlight du lanceur, hors du fil principal (session 123) : une requête à la fois, une requête
/// dépassée par une frappe suivante n'est pas lancée ou son résultat est ignoré. 120 ms d'attente après la
/// dernière frappe.
@MainActor
final class LauncherFileSearch {
    private static let queue = DispatchQueue(label: "roadie.launcher.spotlight", qos: .userInitiated)
    /// Dernière requête voulue, lue par la file de fond.
    private final class Latest: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func next() -> Int { lock.withLock { value += 1; return value } }
        func isCurrent(_ token: Int) -> Bool { lock.withLock { value == token } }
    }
    private let latest = Latest()
    private var pending: DispatchWorkItem?
    /// Mots-clés `in` et `tags` réglés (session 113).
    var keywords = LauncherFileKeywords()
    /// Types ajoutés et dossiers écartés (session 119).
    var extraTypes: [String] = []
    var excluded: [String] = []

    func search(_ text: String, done: @escaping @MainActor ([LauncherFile]) -> Void) {
        cancel()
        guard LauncherFileRules.shouldSearch(text, keywords: keywords) else { done([]); return }
        let string = LauncherFileRules.queryString(LauncherFileQuery.parse(text, keywords: keywords), extraTypes: extraTypes)
        let excluded = excluded, latest = latest, token = latest.next()
        let work = DispatchWorkItem {
            Self.queue.async {
                guard latest.isCurrent(token) else { return }
                let files = LauncherSpotlight.files(string, excluded: excluded, limit: LauncherFileRules.limit)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { if latest.isCurrent(token) { done(files) } }
                }
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    func cancel() {
        pending?.cancel()
        pending = nil
        _ = latest.next()
    }
}

/// Fenêtre qui affiche déjà un fichier (SPEC-077 C). Lecture AX hors du fil principal, l'application par
/// défaut du fichier d'abord ; arrêt à la première trouvée. `exposing` : applications dont au moins une
/// fenêtre a donné un document, sans aucun chemin (relevé de compatibilité). O(w) lectures AX.
enum LauncherDocuments {
    static func window(showing path: String, in entries: [WindowSwitcherEntry],
                       preferredBundle: String?) async -> (window: WindowSwitcherEntry?, exposing: [String], scanned: String) {
        let target = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        let groups = Dictionary(grouping: entries, by: \.window.pid)
            .sorted { ($0.value.first?.window.bundleID == preferredBundle ? 0 : 1) < ($1.value.first?.window.bundleID == preferredBundle ? 0 : 1) }
            .map(\.value)
        return await Task.detached(priority: .userInitiated) {
            var exposing: [String] = []
            // Fenêtres, éléments AX retrouvés, documents lus : de quoi voir où la chaîne s'arrête.
            var windows = 0, elementsFound = 0, documents = 0
            var statuses: [String: Int] = [:]
            for group in groups {
                guard let pid = group.first?.window.pid else { continue }
                let elements = axWindowElements(pid: pid)
                var exposes = false
                for entry in group {
                    windows += 1
                    guard let element = elements[CGWindowID(entry.id.rawValue)] else { continue }
                    elementsFound += 1
                    let read = axDocumentRead(element)
                    statuses["\(entry.window.bundleID):\(read.status)", default: 0] += 1
                    guard let document = read.path else { continue }
                    documents += 1
                    exposes = true
                    if document == target { return (entry, exposing, "\(windows)/\(elementsFound)/\(documents)") }
                }
                if exposes, let bundle = group.first?.window.bundleID { exposing.append(bundle) }
            }
            return (nil, exposing, "\(windows)/\(elementsFound)/\(documents) " + statuses.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " "))
        }.value
    }
}
