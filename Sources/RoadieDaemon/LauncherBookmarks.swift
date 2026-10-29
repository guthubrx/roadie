import AppKit
import Compression
import CryptoKit
import Foundation
import RoadieCore
import SQLite3

/// Signet d'un navigateur dans la barre (session 104). Lu dans les fichiers du navigateur, sans le lancer
/// ni l'automatiser ; rien n'est journalisé.
struct LauncherBookmark: Equatable, Hashable, Sendable {
    let title: String
    let url: String
    /// Dossiers depuis la racine, « Barre personnelle › Outils ».
    let folder: String
    /// `firefox`, `safari`, `chrome`, `brave` ou `edge`.
    let browser: String
    /// Profil du navigateur, vide s'il n'y en a qu'un.
    let profile: String
    /// Mot-clé Firefox du signet ; avec `%s`, il devient une recherche par mot-clé.
    var keyword: String?
    /// Étiquettes Firefox.
    var tags: [String] = []
    /// Icône du site en cache, si le navigateur en a une.
    var icon: String?
    /// Page de l'historique (session 114) et son nombre de visites.
    var isHistory = false
    var visits = 0

    var id: String { "\(isHistory ? "history" : "bookmark"):\(browser):\(url)" }

    /// Titre, puis étiquettes et mot-clé, puis adresse (3 lettres au moins). O(q × t).
    func score(_ query: String) -> Int? {
        LauncherBookmarkIndex.Entry(self).score(LauncherMatch.Query(query), needle: LauncherMatch.fold(query))
    }

    /// Navigateur, profil et dossier, pour le détail de la ligne.
    var detail: String {
        ([LauncherBookmarkBrowsers.name(browser)] + (profile.isEmpty ? [] : [profile]) + (folder.isEmpty ? [] : [folder]))
            .joined(separator: " · ")
    }

    /// Signets qui correspondent, meilleurs d'abord ; à score égal, le titre le plus court. O(b × q × t + k log k).
    static func matches(_ query: String, in bookmarks: [LauncherBookmark], limit: Int = 6) -> [LauncherBookmark] {
        matches(query, in: LauncherBookmarkIndex(bookmarks), limit: limit)
    }

    /// Même recherche dans un index déjà plié (session 123). O(b × t) pour écarter, O(k × q × t + k log k) sinon.
    static func matches(_ query: String, in index: LauncherBookmarkIndex, limit: Int = 6) -> [LauncherBookmark] {
        let needle = LauncherMatch.fold(query)
        guard needle.count >= 2 else { return [] }
        let prepared = LauncherMatch.Query(query)
        var scored: [(bookmark: LauncherBookmark, score: Int)] = []
        for entry in index.entries {
            if let score = entry.score(prepared, needle: needle) { scored.append((entry.bookmark, score)) }
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.bookmark.title.count < $1.bookmark.title.count }
        // Un même signet dans plusieurs profils ou navigateurs : une seule ligne (adresse ou titre déjà vus).
        var seen: Set<String> = []
        var result: [LauncherBookmark] = []
        for entry in scored where result.count < limit {
            let url = entry.bookmark.url.hasSuffix("/") ? String(entry.bookmark.url.dropLast()) : entry.bookmark.url
            guard !seen.contains(url), !seen.contains("title:" + LauncherMatch.fold(entry.bookmark.title)) else { continue }
            seen.insert(url)
            seen.insert("title:" + LauncherMatch.fold(entry.bookmark.title))
            result.append(entry.bookmark)
        }
        return result
    }

    /// Mots-clés Firefox avec `%s` : recherches tapées « mot-clé texte », comme dans Firefox. Les mots-clés
    /// déjà pris par `web_searches` restent à ceux-ci. O(b).
    static func keywordSearches(_ bookmarks: [LauncherBookmark], taken: Set<String>) -> [WebSearch] {
        var used = taken
        return bookmarks.compactMap { bookmark in
            guard let keyword = bookmark.keyword?.lowercased(), !keyword.isEmpty, bookmark.url.contains("%s"),
                  used.insert(keyword).inserted else { return nil }
            return WebSearch(keyword: keyword, title: bookmark.title.isEmpty ? keyword : bookmark.title,
                             url: bookmark.url.replacingOccurrences(of: "%s", with: "{query}"))
        }
    }
}

/// Navigateurs lus, leur nom et leur application.
enum LauncherBookmarkBrowsers {
    static func name(_ id: String) -> String {
        switch id {
        case "firefox": "Firefox"
        case "safari": "Safari"
        case "chrome": "Chrome"
        case "brave": "Brave"
        case "edge": "Edge"
        case "arc": "Arc"
        default: id
        }
    }

    static func bundleIDs(_ id: String) -> [String] {
        switch id {
        case "firefox": ["org.mozilla.firefox", "org.mozilla.nightly", "org.mozilla.firefoxdeveloperedition"]
        case "safari": ["com.apple.Safari"]
        case "chrome": ["com.google.Chrome"]
        case "brave": ["com.brave.Browser"]
        case "edge": ["com.microsoft.edgemac"]
        default: []
        }
    }

    /// Application installée du navigateur. O(1) par identifiant.
    @MainActor static func appURL(_ id: String) -> URL? {
        bundleIDs(id).lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }

    @MainActor static func appPath(_ id: String) -> String? { appURL(id)?.path }

    /// Application du navigateur du signet s'il n'est pas celui qui ouvre `url` par défaut ; nil sinon.
    @MainActor static func otherThanDefault(_ id: String, for url: URL) -> URL? {
        guard let app = appURL(id), let bundle = Bundle(url: app)?.bundleIdentifier else { return nil }
        let defaultBundle = NSWorkspace.shared.urlForApplication(toOpen: url).flatMap { Bundle(url: $0)?.bundleIdentifier }
        return defaultBundle == bundle ? nil : app
    }

    /// Dossier des données d'un navigateur Chromium.
    static func chromiumRoot(_ id: String, support: URL) -> URL? {
        switch id {
        case "chrome": support.appendingPathComponent("Google/Chrome")
        case "brave": support.appendingPathComponent("BraveSoftware/Brave-Browser")
        case "edge": support.appendingPathComponent("Microsoft Edge")
        default: nil
        }
    }
}

// MARK: - SQLite

/// Lecture d'une copie d'une base SQLite : Firefox et Chrome gardent leurs bases ouvertes et verrouillées.
/// La copie emporte le journal WAL, rejoué à l'ouverture : les derniers ajouts sont lus. La copie est
/// effacée après lecture.
enum SQLiteSnapshot {
    /// Appelle `row` pour chaque ligne ; faux si la base n'a pas pu être lue. O(copie + lignes).
    @discardableResult
    static func read(_ database: URL, sql: String, row: (OpaquePointer) -> Void) -> Bool {
        let files = FileManager.default
        let folder = files.temporaryDirectory.appendingPathComponent("roadie-sqlite-\(UUID().uuidString)", isDirectory: true)
        defer { try? files.removeItem(at: folder) }
        guard (try? files.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return false }
        let copy = folder.appendingPathComponent(database.lastPathComponent)
        guard (try? files.copyItem(at: database, to: copy)) != nil else { return false }
        let wal = URL(fileURLWithPath: database.path + "-wal")
        if files.fileExists(atPath: wal.path) { try? files.copyItem(at: wal, to: URL(fileURLWithPath: copy.path + "-wal")) }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let handle else {
            sqlite3_close(handle)
            return false
        }
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW { row(statement) }
        return true
    }

    static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }

    static func int(_ statement: OpaquePointer, _ column: Int32) -> Int { Int(sqlite3_column_int64(statement, column)) }

    static func blob(_ statement: OpaquePointer, _ column: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }
}

// MARK: - Firefox

/// Profils de Firefox : ceux de la gestion des profils (`Profile Groups`, avec leur nom choisi) et ceux de
/// `profiles.ini`. Seuls ceux qui ont une base de signets comptent.
enum FirefoxProfiles {
    struct Profile: Equatable, Sendable {
        let path: URL
        let name: String
    }

    static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Firefox", isDirectory: true)
    }

    /// O(p).
    static func all(root: URL = root) -> [Profile] {
        var found: [String: String] = [:]
        var order: [String] = []
        func add(_ relative: String, _ name: String) {
            let path = relative.hasPrefix("/") ? relative : root.appendingPathComponent(relative).path
            if found[path] == nil { order.append(path) }
            if found[path]?.isEmpty ?? true { found[path] = name }
        }
        let groups = root.appendingPathComponent("Profile Groups")
        for database in (try? FileManager.default.contentsOfDirectory(at: groups, includingPropertiesForKeys: nil)) ?? []
        where database.pathExtension == "sqlite" {
            SQLiteSnapshot.read(database, sql: "SELECT path, name FROM Profiles") { row in
                if let path = SQLiteSnapshot.text(row, 0) { add(path, SQLiteSnapshot.text(row, 1) ?? "") }
            }
        }
        for (path, name) in iniProfiles((try? String(contentsOf: root.appendingPathComponent("profiles.ini"), encoding: .utf8)) ?? "") {
            add(path, name)
        }
        return order.compactMap { path in
            FileManager.default.fileExists(atPath: path + "/places.sqlite") ? Profile(path: URL(fileURLWithPath: path), name: found[path] ?? "") : nil
        }
    }

    /// `[ProfileN]` de `profiles.ini` : chemin et nom. O(l).
    static func iniProfiles(_ text: String) -> [(path: String, name: String)] {
        var result: [(String, String)] = []
        var section = "", path: String?, name = ""
        func flush() { if section.hasPrefix("Profile"), let path { result.append((path, name)) } }
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                flush()
                section = String(line.dropFirst().dropLast())
                path = nil
                name = ""
            } else if let equal = line.firstIndex(of: "=") {
                let key = line[..<equal], value = String(line[line.index(after: equal)...])
                if key == "Path" { path = value }
                if key == "Name" { name = value }
            }
        }
        flush()
        return result
    }
}

enum FirefoxBookmarks {
    /// Racines de Firefox et leur nom affiché.
    static var roots: [String: String] {
        ["menu________": tr("Menu des marque-pages", "Bookmarks Menu"), "toolbar_____": tr("Barre personnelle", "Bookmarks Toolbar"),
         "unfiled_____": tr("Autres marque-pages", "Other Bookmarks"), "mobile______": "Mobile"]
    }

    /// Signets, mots-clés et étiquettes d'un profil. O(n) lignes de `moz_bookmarks`.
    static func read(_ profile: FirefoxProfiles.Profile, profileLabel: String) -> [LauncherBookmark] {
        struct Node { let parent: Int; let title: String; let guid: String }
        var folders: [Int: Node] = [:]
        var leaves: [(parent: Int, title: String, url: String, keyword: String?)] = []
        let sql = """
        SELECT b.id, b.parent, b.type, IFNULL(b.title, ''), IFNULL(b.guid, ''), p.url, k.keyword
        FROM moz_bookmarks b LEFT JOIN moz_places p ON p.id = b.fk LEFT JOIN moz_keywords k ON k.place_id = b.fk
        """
        SQLiteSnapshot.read(profile.path.appendingPathComponent("places.sqlite"), sql: sql) { row in
            let id = SQLiteSnapshot.int(row, 0), parent = SQLiteSnapshot.int(row, 1), type = SQLiteSnapshot.int(row, 2)
            let title = SQLiteSnapshot.text(row, 3) ?? ""
            if type == 2 { folders[id] = Node(parent: parent, title: title, guid: SQLiteSnapshot.text(row, 4) ?? "") }
            if type == 1, let url = SQLiteSnapshot.text(row, 5), !url.hasPrefix("place:") {
                leaves.append((parent, title, url, SQLiteSnapshot.text(row, 6)))
            }
        }
        let tagsRoot = folders.first { $0.value.guid == "tags________" }?.key
        var tags: [String: [String]] = [:]
        var bookmarks: [LauncherBookmark] = []
        for leaf in leaves {
            // Une étiquette est un signet sans titre rangé dans un dossier de la racine des étiquettes.
            if let tagsRoot, let folder = folders[leaf.parent], folder.parent == tagsRoot {
                tags[leaf.url, default: []].append(folder.title)
                continue
            }
            var path: [String] = []
            var current = leaf.parent
            var guard_ = 0
            while let folder = folders[current], guard_ < 32 {
                if let root = roots[folder.guid] { path.append(root); break }
                if !folder.title.isEmpty { path.append(folder.title) }
                current = folder.parent
                guard_ += 1
            }
            bookmarks.append(LauncherBookmark(title: leaf.title.isEmpty ? leaf.url : leaf.title, url: leaf.url,
                                              folder: path.reversed().joined(separator: " › "), browser: "firefox",
                                              profile: profileLabel, keyword: leaf.keyword))
        }
        return bookmarks.map { bookmark in
            var bookmark = bookmark
            bookmark.tags = tags[bookmark.url] ?? []
            return bookmark
        }
    }

    /// Icônes des pages dans `favicons.sqlite` : la plus proche de 32 pixels. O(n).
    static func favicons(_ profile: FirefoxProfiles.Profile, for urls: Set<String>) -> [String: Data] {
        var best: [String: (data: Data, width: Int)] = [:]
        let sql = """
        SELECT p.page_url, i.data, i.width FROM moz_pages_w_icons p
        JOIN moz_icons_to_pages ip ON ip.page_id = p.id JOIN moz_icons i ON i.id = ip.icon_id
        """
        SQLiteSnapshot.read(profile.path.appendingPathComponent("favicons.sqlite"), sql: sql) { row in
            guard let url = SQLiteSnapshot.text(row, 0), urls.contains(url), let data = SQLiteSnapshot.blob(row, 1) else { return }
            let width = SQLiteSnapshot.int(row, 2)
            if let current = best[url], abs(current.width - 32) <= abs(width - 32) { return }
            best[url] = (data, width)
        }
        return best.mapValues(\.data)
    }
}

/// Onglets ouverts de Firefox (session 104, complément de SPEC-082) : Firefox n'a pas de dictionnaire
/// AppleScript, mais il enregistre sa session toutes les 15 secondes dans
/// `sessionstore-backups/recovery.jsonlz4` (JSON compressé en LZ4, en-tête `mozLz40`).
enum FirefoxSession {
    struct Tab: Equatable, Sendable {
        /// Rang de la fenêtre dans la session et de l'onglet dans sa fenêtre, à partir de 1.
        let window: Int
        let index: Int
        /// Cadre de la fenêtre, origine en haut à gauche comme l'accessibilité.
        let bounds: CGRect
        let isActive: Bool
        let title: String
        let url: String
        let profile: String
    }

    /// `mozLz40\0`, taille décompressée sur 4 octets, puis un bloc LZ4. nil si le format ne correspond pas.
    static func decompress(_ data: Data) -> Data? {
        let magic = Data("mozLz40\0".utf8)
        guard data.count > 12, data.prefix(8) == magic else { return nil }
        let size = data.subdata(in: 8..<12).withUnsafeBytes { Int($0.loadUnaligned(as: UInt32.self).littleEndian) }
        guard size > 0, size < 512 * 1024 * 1024 else { return nil }
        var output = Data(count: size)
        let payload = data.subdata(in: 12..<data.count)
        let written = output.withUnsafeMutableBytes { destination in
            payload.withUnsafeBytes { source in
                compression_decode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, size,
                                          source.bindMemory(to: UInt8.self).baseAddress!, payload.count, nil, COMPRESSION_LZ4_RAW)
            }
        }
        return written == size ? output : nil
    }

    /// Onglets d'une session : entrée courante de chaque onglet visible. O(t).
    static func tabs(_ json: Data, profile: String) -> [Tab] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let windows = root["windows"] as? [[String: Any]] else { return [] }
        var result: [Tab] = []
        for (w, window) in windows.enumerated() {
            let selected = (window["selected"] as? NSNumber)?.intValue ?? 1
            let bounds = CGRect(x: (window["screenX"] as? NSNumber)?.doubleValue ?? 0, y: (window["screenY"] as? NSNumber)?.doubleValue ?? 0,
                                width: (window["width"] as? NSNumber)?.doubleValue ?? 0, height: (window["height"] as? NSNumber)?.doubleValue ?? 0)
            for (t, tab) in ((window["tabs"] as? [[String: Any]]) ?? []).enumerated() {
                guard (tab["hidden"] as? Bool) != true, let entries = tab["entries"] as? [[String: Any]], !entries.isEmpty else { continue }
                let current = entries[min(entries.count, max(1, (tab["index"] as? NSNumber)?.intValue ?? entries.count)) - 1]
                guard let url = current["url"] as? String, !url.hasPrefix("about:") || url == "about:home" else { continue }
                result.append(Tab(window: w + 1, index: t + 1, bounds: bounds, isActive: t + 1 == selected,
                                  title: (current["title"] as? String) ?? url, url: url, profile: profile))
            }
        }
        return result
    }

    /// Onglets des profils dont la session a été écrite depuis `since` (lancement de Firefox) : seuls les
    /// profils ouverts. O(p + t).
    static func openTabs(root: URL = FirefoxProfiles.root, since: Date) -> [Tab] {
        let profiles = FirefoxProfiles.all(root: root)
        return profiles.flatMap { profile -> [Tab] in
            let file = profile.path.appendingPathComponent("sessionstore-backups/recovery.jsonlz4")
            guard let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  modified >= since, let data = try? Data(contentsOf: file), let json = decompress(data) else { return [] }
            return tabs(json, profile: profiles.count > 1 ? profile.name : "")
        }
    }
}

// MARK: - Chromium et Safari

enum ChromiumBookmarks {
    static var rootNames: [String: String] {
        ["bookmark_bar": tr("Barre de favoris", "Bookmarks bar"), "other": tr("Autres favoris", "Other bookmarks"),
         "synced": tr("Favoris sur mobile", "Mobile bookmarks")]
    }

    /// Profils (`Default`, `Profile N`) et leur nom dans `Local State`. O(p).
    static func profiles(_ root: URL) -> [(path: URL, name: String)] {
        var names: [String: String] = [:]
        if let data = try? Data(contentsOf: root.appendingPathComponent("Local State")),
           let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let cache = (state["profile"] as? [String: Any])?["info_cache"] as? [String: Any] {
            for (folder, info) in cache { names[folder] = (info as? [String: Any])?["name"] as? String }
        }
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return folders.filter { ($0 == "Default" || $0.hasPrefix("Profile "))
            && FileManager.default.fileExists(atPath: root.appendingPathComponent("\($0)/Bookmarks").path) }
            .sorted().map { (root.appendingPathComponent($0), names[$0] ?? $0) }
    }

    /// Fichier `Bookmarks` (JSON). O(n).
    static func read(_ data: Data, browser: String, profile: String) -> [LauncherBookmark] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = root["roots"] as? [String: Any] else { return [] }
        var result: [LauncherBookmark] = []
        func walk(_ node: [String: Any], path: [String]) {
            if node["type"] as? String == "url", let url = node["url"] as? String {
                let name = node["name"] as? String ?? ""
                result.append(LauncherBookmark(title: name.isEmpty ? url : name, url: url, folder: path.joined(separator: " › "),
                                               browser: browser, profile: profile))
                return
            }
            for child in node["children"] as? [[String: Any]] ?? [] {
                walk(child, path: child["type"] as? String == "folder" ? path + [child["name"] as? String ?? ""] : path)
            }
        }
        for key in ["bookmark_bar", "other", "synced"] {
            if let node = roots[key] as? [String: Any] { walk(node, path: [rootNames[key] ?? key]) }
        }
        return result
    }

    static func favicons(_ profile: URL, for urls: Set<String>) -> [String: Data] {
        var best: [String: (data: Data, width: Int)] = [:]
        let sql = "SELECT m.page_url, b.image_data, b.width FROM icon_mapping m JOIN favicon_bitmaps b ON b.icon_id = m.icon_id"
        SQLiteSnapshot.read(profile.appendingPathComponent("Favicons"), sql: sql) { row in
            guard let url = SQLiteSnapshot.text(row, 0), urls.contains(url), let data = SQLiteSnapshot.blob(row, 1) else { return }
            let width = SQLiteSnapshot.int(row, 2)
            if let current = best[url], abs(current.width - 32) <= abs(width - 32) { return }
            best[url] = (data, width)
        }
        return best.mapValues(\.data)
    }
}

enum SafariBookmarks {
    static var file: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari/Bookmarks.plist")
    }

    /// `Bookmarks.plist` ; la liste de lecture compte aussi. Lecture refusée sans accès complet au disque :
    /// liste vide. O(n).
    static func read(_ data: Data) -> [LauncherBookmark] {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return [] }
        var result: [LauncherBookmark] = []
        func walk(_ node: [String: Any], path: [String]) {
            if node["WebBookmarkType"] as? String == "WebBookmarkTypeLeaf", let url = node["URLString"] as? String {
                let title = (node["URIDictionary"] as? [String: Any])?["title"] as? String ?? url
                result.append(LauncherBookmark(title: title, url: url, folder: path.joined(separator: " › "), browser: "safari", profile: ""))
                return
            }
            let name: String? = switch node["Title"] as? String {
            case "BookmarksBar": tr("Barre des favoris", "Favorites Bar")
            case "BookmarksMenu": tr("Menu des signets", "Bookmarks Menu")
            case "com.apple.ReadingList": tr("Liste de lecture", "Reading List")
            case "History", "", nil: nil
            case let title?: title
            }
            if node["Title"] as? String == "History" { return }
            for child in node["Children"] as? [[String: Any]] ?? [] { walk(child, path: path + (name.map { [$0] } ?? [])) }
        }
        walk(root, path: [])
        return result
    }
}

// MARK: - Cache

/// Signets de tous les navigateurs choisis, relus au plus toutes les 60 secondes ; les icônes des sites
/// sont copiées une fois dans `~/.roadies/favicons`. Appelé hors du fil principal.
final class LauncherBookmarkStore: @unchecked Sendable {
    static let shared = LauncherBookmarkStore()

    private let lock = NSLock()
    private var cached: (browsers: [String], at: Date, index: LauncherBookmarkIndex)?
    let iconFolder: URL

    init(iconFolder: URL = URL(fileURLWithPath: NSString(string: TestEnvironment.launcherFile("favicons")).expandingTildeInPath, isDirectory: true)) {
        self.iconFolder = iconFolder
    }

    /// Signets pliés pour la recherche (session 123), gardés avec la lecture : préparés une fois, en fond. O(b × t).
    func loadIndex(browsers: [String], now: Date = Date()) -> LauncherBookmarkIndex {
        lock.lock()
        if let cached, cached.browsers == browsers, now.timeIntervalSince(cached.at) < 60 {
            defer { lock.unlock() }
            return cached.index
        }
        lock.unlock()
        let index = LauncherBookmarkIndex(read(browsers: browsers))
        lock.lock()
        cached = (browsers, now, index)
        lock.unlock()
        return index
    }

    /// O(fichiers + signets).
    private func read(browsers: [String]) -> [LauncherBookmark] {
        var all: [LauncherBookmark] = []
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        for browser in browsers {
            switch browser {
            case "firefox":
                let profiles = FirefoxProfiles.all()
                for profile in profiles {
                    var found = FirefoxBookmarks.read(profile, profileLabel: profiles.count > 1 ? profile.name : "")
                    attachIcons(&found) { FirefoxBookmarks.favicons(profile, for: $0) }
                    all += found
                }
            case "safari":
                if let data = try? Data(contentsOf: SafariBookmarks.file) { all += SafariBookmarks.read(data) }
            default:
                guard let root = LauncherBookmarkBrowsers.chromiumRoot(browser, support: support) else { continue }
                let profiles = ChromiumBookmarks.profiles(root)
                for profile in profiles {
                    guard let data = try? Data(contentsOf: profile.path.appendingPathComponent("Bookmarks")) else { continue }
                    var found = ChromiumBookmarks.read(data, browser: browser, profile: profiles.count > 1 ? profile.name : "")
                    attachIcons(&found) { ChromiumBookmarks.favicons(profile.path, for: $0) }
                    all += found
                }
            }
        }
        return all
    }

    /// Icône déjà en cache, sinon lue dans la base du navigateur (une seule lecture pour toutes les
    /// manquantes) et écrite en PNG, ICO ou autre format d'image ; SVG ignoré. O(s).
    private func attachIcons(_ bookmarks: inout [LauncherBookmark], read: (Set<String>) -> [String: Data]) {
        try? FileManager.default.createDirectory(at: iconFolder, withIntermediateDirectories: true)
        func path(_ url: String) -> String {
            let digest = Insecure.SHA1.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined()
            return iconFolder.appendingPathComponent(digest + ".icon").path
        }
        let missing = Set(bookmarks.map(\.url).filter { !FileManager.default.fileExists(atPath: path($0)) })
        if !missing.isEmpty {
            let found = read(missing)
            // Un fichier vide note « pas d'icône » : la base n'est pas relue pour ce signet.
            for url in missing {
                let data = found[url].flatMap { Self.isSVG($0) ? nil : $0 } ?? Data()
                FileManager.default.createFile(atPath: path(url), contents: data)
            }
        }
        for index in bookmarks.indices {
            let file = path(bookmarks[index].url)
            if let size = (try? FileManager.default.attributesOfItem(atPath: file))?[.size] as? Int, size > 0 { bookmarks[index].icon = file }
        }
    }

    static func isSVG(_ data: Data) -> Bool {
        String(decoding: data.prefix(256), as: UTF8.self).lowercased().contains("<svg")
    }
}

/// Signets ou pages pliés une fois pour la recherche (session 123) : à chaque frappe, seule la saisie est pliée.
/// Préparé quand la liste arrive, hors frappe. O(n × t) à la construction.
struct LauncherBookmarkIndex: Sendable {
    struct Entry: Sendable {
        let bookmark: LauncherBookmark
        let title: LauncherMatch.Prepared
        let tags: [String]
        let url: String
        let urlLetters: UInt64

        init(_ bookmark: LauncherBookmark) {
            self.bookmark = bookmark
            title = LauncherMatch.Prepared(bookmark.title)
            tags = bookmark.tags.map(LauncherMatch.fold)
            url = LauncherMatch.fold(bookmark.url)
            urlLetters = LauncherMatch.letters(url)
        }

        /// Titre, puis étiquettes et mot-clé, puis adresse (3 lettres au moins). O(q × t).
        func score(_ query: LauncherMatch.Query?, needle: String) -> Int? {
            if let query, let score = LauncherMatch.score(query, in: title) { return score }
            if tags.contains(where: { $0.hasPrefix(needle) }) { return 3 }
            guard needle.count >= 3, LauncherMatch.letters(needle) & ~urlLetters == 0, url.contains(needle) else { return nil }
            return 1
        }
    }

    let entries: [Entry]

    init(_ bookmarks: [LauncherBookmark]) { entries = bookmarks.map(Entry.init) }
}
