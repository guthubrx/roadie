import Foundation
import RoadieCore

/// Dernières saisies qui ont mené à une action (SPEC-090 FR-004) : 20 au plus, la plus récente à la
/// fin, sans doublon. Ne quitte pas le Mac.
struct LauncherHistoryBook: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let query: String
        let at: Date
    }

    static let maxEntries = 20
    /// Barre rouverte dans ce délai : la dernière saisie revient.
    static let resumeWindow: TimeInterval = 5 * 60

    var entries: [Entry] = []

    mutating func record(_ query: String, at now: Date) {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        entries.removeAll { $0.query == text }
        entries.append(Entry(query: text, at: now))
        if entries.count > Self.maxEntries { entries.removeFirst(entries.count - Self.maxEntries) }
    }

    /// Saisie à reprendre : la dernière, si elle a moins de 5 minutes. O(1).
    func resumable(at now: Date) -> String? {
        guard let last = entries.last, now.timeIntervalSince(last.at) < Self.resumeWindow else { return nil }
        return last.query
    }

    /// Recherches récentes de la barre vide, la plus récente d'abord. O(n).
    func recent(_ count: Int) -> [String] { Array(entries.reversed().prefix(count).map(\.query)) }
}

struct LauncherHistoryStore: Sendable {
    let url: URL

    init(path: String = TestEnvironment.launcherFile("launcher-history.json")) {
        url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    func load() -> LauncherHistoryBook { JSONPersistence.load(LauncherHistoryBook.self, from: url, default: LauncherHistoryBook()) }

    func record(_ query: String, at now: Date = Date()) {
        JSONPersistence.mutate(LauncherHistoryBook.self, at: url, default: LauncherHistoryBook(), label: "launcher history") { book in
            book.record(query, at: now)
        }
    }

    func clear() throws {
        try JSONPersistence.mutateChecked(LauncherHistoryBook.self, at: url, default: LauncherHistoryBook(), label: "launcher history") { book in
            book = LauncherHistoryBook()
        }
    }
}

/// Machine à états pure pour remonter/redescendre dans l'historique des saisies du lanceur
/// avec les flèches ↑ / ↓ depuis le haut de la liste.
struct LauncherHistoryNavigator: Equatable, Sendable {
    /// Entrées triées de la plus récente (`0`) à la plus ancienne.
    let entries: [String]
    private(set) var cursor: Int? = nil
    private(set) var draft: String? = nil

    init(entries: [String]) {
        self.entries = entries
    }

    var isActive: Bool { cursor != nil }

    mutating func reset() {
        cursor = nil
        draft = nil
    }

    /// Flèche ↑ : remonte vers une saisie plus ancienne. Retourne `nil` si vide ou déjà au bout.
    mutating func stepOlder(currentQuery: String) -> String? {
        guard !entries.isEmpty else { return nil }
        if let current = cursor {
            let next = min(current + 1, entries.count - 1)
            guard next != current else { return nil }
            cursor = next
            return entries[next]
        }
        draft = currentQuery
        let trimmed = currentQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = (entries.first == trimmed && entries.count > 1) ? 1 : 0
        cursor = start
        return entries[start]
    }

    /// Flèche ↓ (en mode historique) : redescend vers plus récent, puis restaure le brouillon initial.
    mutating func stepNewer() -> String? {
        guard let current = cursor else { return nil }
        if current > 0 {
            let next = current - 1
            if next == 0, let draft, entries[0] == draft.trimmingCharacters(in: .whitespacesAndNewlines) {
                let restored = draft
                reset()
                return restored
            }
            cursor = next
            return entries[next]
        }
        let restored = draft ?? ""
        reset()
        return restored
    }
}
