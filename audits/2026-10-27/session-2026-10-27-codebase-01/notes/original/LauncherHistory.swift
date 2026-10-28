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
        var book = load()
        let before = book
        book.record(query, at: now)
        guard book != before else { return }
        JSONPersistence.write(book, to: url, label: "launcher history")
    }

    func clear() { JSONPersistence.write(LauncherHistoryBook(), to: url, label: "launcher history") }
}
