import Foundation

/// Historique des navigateurs dans la barre (session 114), à côté des signets : pages vues ces derniers jours,
/// lues dans les fichiers du navigateur sans le lancer. Une page est un `LauncherBookmark` rangé dans
/// « Historique », ouvert par le même chemin qu'un signet. Rien n'est journalisé ni gardé par Roadie.
enum LauncherWebHistory {
    /// Pages gardées par profil : les plus visitées, de quoi couvrir l'usage courant sans tout lire.
    static let perProfile = 2000
    static let folder = "Historique"

    /// Pages qui correspondent, hors adresses déjà proposées (signets) ; meilleur appariement, puis les plus
    /// visitées. O(h × q × t + k log k).
    static func matches(_ query: String, in pages: [LauncherBookmark], excluding shown: Set<String>, limit: Int = 4) -> [LauncherBookmark] {
        matches(query, in: LauncherBookmarkIndex(pages), excluding: shown, limit: limit)
    }

    /// Même recherche dans un index déjà plié (session 123) : 2 300 pages en quelques millisecondes.
    static func matches(_ query: String, in index: LauncherBookmarkIndex, excluding shown: Set<String>, limit: Int = 4) -> [LauncherBookmark] {
        let needle = LauncherMatch.fold(query)
        guard needle.count >= 2 else { return [] }
        let prepared = LauncherMatch.Query(query)
        var scored: [(page: LauncherBookmark, score: Int)] = []
        for entry in index.entries {
            guard let score = entry.score(prepared, needle: needle), !shown.contains(normalized(entry.bookmark.url)) else { continue }
            scored.append((entry.bookmark, score))
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.page.visits > $1.page.visits }
        var seen: Set<String> = []
        var result: [LauncherBookmark] = []
        for entry in scored where result.count < limit && seen.insert(normalized(entry.page.url)).inserted {
            result.append(entry.page)
        }
        return result
    }

    /// Adresse sans `/` final, pour reconnaître une même page. O(n).
    static func normalized(_ url: String) -> String { url.hasSuffix("/") ? String(url.dropLast()) : url }

    static func page(title: String?, url: String, browser: String, profile: String, visits: Int) -> LauncherBookmark? {
        guard url.hasPrefix("http://") || url.hasPrefix("https://") else { return nil }
        let title = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var page = LauncherBookmark(title: title.isEmpty ? url : title, url: url, folder: folder, browser: browser, profile: profile)
        page.isHistory = true
        page.visits = visits
        return page
    }

    /// Firefox : `moz_places`, dates en microsecondes depuis 1970, classées par la fréquence-récence de Firefox.
    static func firefox(_ profile: FirefoxProfiles.Profile, label: String, since: Date) -> [LauncherBookmark] {
        let sql = """
        SELECT url, title, visit_count FROM moz_places
        WHERE hidden = 0 AND visit_count > 0 AND last_visit_date > \(Int64(since.timeIntervalSince1970 * 1_000_000))
        ORDER BY frecency DESC LIMIT \(perProfile)
        """
        var pages: [LauncherBookmark] = []
        SQLiteSnapshot.read(profile.path.appendingPathComponent("places.sqlite"), sql: sql) { row in
            guard let url = SQLiteSnapshot.text(row, 0),
                  let page = page(title: SQLiteSnapshot.text(row, 1), url: url, browser: "firefox", profile: label,
                                  visits: SQLiteSnapshot.int(row, 2)) else { return }
            pages.append(page)
        }
        return pages
    }

    /// Chrome, Brave, Edge : table `urls` de `History`, dates en microsecondes depuis 1601.
    static func chromium(_ profile: URL, browser: String, label: String, since: Date) -> [LauncherBookmark] {
        let webkit = Int64((since.timeIntervalSince1970 + 11_644_473_600) * 1_000_000)
        let sql = """
        SELECT url, title, visit_count FROM urls WHERE hidden = 0 AND last_visit_time > \(webkit)
        ORDER BY visit_count DESC LIMIT \(perProfile)
        """
        var pages: [LauncherBookmark] = []
        SQLiteSnapshot.read(profile.appendingPathComponent("History"), sql: sql) { row in
            guard let url = SQLiteSnapshot.text(row, 0),
                  let page = page(title: SQLiteSnapshot.text(row, 1), url: url, browser: browser, profile: label,
                                  visits: SQLiteSnapshot.int(row, 2)) else { return }
            pages.append(page)
        }
        return pages
    }

    /// Safari : `History.db` (accès complet au disque requis), dates en secondes depuis 2001 ; le titre de la
    /// dernière visite.
    static func safari(since: Date) -> [LauncherBookmark] {
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari/History.db")
        let sql = """
        SELECT i.url, (SELECT v.title FROM history_visits v WHERE v.history_item = i.id ORDER BY v.visit_time DESC LIMIT 1),
               i.visit_count
        FROM history_items i
        WHERE (SELECT MAX(v.visit_time) FROM history_visits v WHERE v.history_item = i.id) > \(since.timeIntervalSinceReferenceDate)
        ORDER BY i.visit_count DESC LIMIT \(perProfile)
        """
        var pages: [LauncherBookmark] = []
        SQLiteSnapshot.read(file, sql: sql) { row in
            guard let url = SQLiteSnapshot.text(row, 0),
                  let page = page(title: SQLiteSnapshot.text(row, 1), url: url, browser: "safari", profile: "",
                                  visits: SQLiteSnapshot.int(row, 2)) else { return }
            pages.append(page)
        }
        return pages
    }
}

/// Lecture de l'historique hors du fil principal, gardée 5 minutes : copier `places.sqlite` (jusqu'à 15 Mo
/// ici) à chaque ouverture de la barre serait inutile.
final class LauncherWebHistoryStore: @unchecked Sendable {
    static let shared = LauncherWebHistoryStore()

    private let lock = NSLock()
    private var cached: (key: String, at: Date, index: LauncherBookmarkIndex)?

    /// `days` : fenêtre de l'historique. O(fichiers + pages).
    func load(browsers: [String], days: Int, now: Date = Date()) -> [LauncherBookmark] {
        loadIndex(browsers: browsers, days: days, now: now).entries.map(\.bookmark)
    }

    /// Pages pliées pour la recherche (session 123), gardées avec la lecture : préparées une fois, en fond. O(p × t).
    func loadIndex(browsers: [String], days: Int, now: Date = Date()) -> LauncherBookmarkIndex {
        let key = "\(browsers.joined(separator: ","))/\(days)"
        lock.lock()
        if let cached, cached.key == key, now.timeIntervalSince(cached.at) < 300 {
            defer { lock.unlock() }
            return cached.index
        }
        lock.unlock()
        let index = LauncherBookmarkIndex(read(browsers: browsers, since: now.addingTimeInterval(-Double(days) * 86_400)))
        lock.lock()
        cached = (key, now, index)
        lock.unlock()
        return index
    }

    private func read(browsers: [String], since: Date) -> [LauncherBookmark] {
        var all: [LauncherBookmark] = []
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        for browser in browsers {
            switch browser {
            case "firefox":
                let profiles = FirefoxProfiles.all()
                for profile in profiles {
                    all += LauncherWebHistory.firefox(profile, label: profiles.count > 1 ? profile.name : "", since: since)
                }
            case "safari":
                all += LauncherWebHistory.safari(since: since)
            default:
                guard let root = LauncherBookmarkBrowsers.chromiumRoot(browser, support: support) else { continue }
                let profiles = ChromiumBookmarks.profiles(root)
                for profile in profiles {
                    all += LauncherWebHistory.chromium(profile.path, browser: browser, label: profiles.count > 1 ? profile.name : "", since: since)
                }
            }
        }
        return all
    }
}
