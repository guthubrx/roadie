import Foundation

/// Classement appris du lanceur (SPEC-073 F3), logique pure. Deux mémoires par objet :
/// - les abréviations tapées avant de le choisir, avec leur nombre (mnémoniques à la Quicksilver) ;
/// - une fréquence-récence à demi-vie de 10 jours : l'ancre est stockée, pas le score, pour qu'aucune
///   réécriture ne soit nécessaire avec le temps (`score = 2^((ancre - t) / 10 jours)`, au moins 1).
struct LauncherRanking: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        /// Instant (secondes depuis 1970) auquel le score retombe à 1.
        var anchor: Double
        /// Requête repliée → nombre de choix de cet objet après l'avoir tapée.
        var abbreviations: [String: Int]
    }

    static let halfLife: Double = 10 * 24 * 3600
    /// Abréviations gardées par objet ; les moins utilisées partent d'abord.
    static let maxAbbreviations = 8
    private static let lambda = log(2.0) / halfLife

    var entries: [String: Entry] = [:]

    func frecency(_ key: String, at now: Date) -> Double {
        guard let anchor = entries[key]?.anchor else { return 1 }
        return max(1, exp(Self.lambda * (anchor - now.timeIntervalSince1970)))
    }

    /// Nombre de choix de cet objet après exactement cette requête. O(1).
    func exactUses(_ key: String, query: String) -> Int {
        entries[key]?.abbreviations[LauncherMatch.fold(query)] ?? 0
    }

    /// Nombre de choix après une requête plus longue qui commence par celle-ci (`fi` → `fire`). O(a).
    func prefixUses(_ key: String, query: String) -> Int {
        let folded = LauncherMatch.fold(query)
        guard !folded.isEmpty, let abbreviations = entries[key]?.abbreviations else { return 0 }
        return abbreviations.reduce(0) { $0 + ($1.key.hasPrefix(folded) ? $1.value : 0) }
    }

    /// Un choix : le score gagne 100 points et la requête est mémorisée. O(a log a).
    mutating func recordVisit(_ key: String, query: String, at now: Date) {
        let t = now.timeIntervalSince1970
        var entry = entries[key] ?? Entry(anchor: t, abbreviations: [:])
        entry.anchor = t + log(frecency(key, at: now) + 100) / Self.lambda
        let folded = LauncherMatch.fold(query)
        if !folded.isEmpty {
            entry.abbreviations[folded, default: 0] += 1
            if entry.abbreviations.count > Self.maxAbbreviations,
               let rarest = entry.abbreviations.min(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }) {
                entry.abbreviations[rarest.key] = nil
            }
        }
        entries[key] = entry
    }

    /// Objets dont le score est retombé à 1 : oubliés. O(n).
    mutating func prune(at now: Date) {
        entries = entries.filter { $0.value.anchor > now.timeIntervalSince1970 }
    }
}

/// Fichier `~/.roadies/launcher-ranking.json` : local, jamais transmis, effaçable sans dommage.
struct LauncherRankingStore: Sendable {
    let url: URL

    init(path: String = "~/.roadies/launcher-ranking.json") {
        url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    func load(at now: Date = Date()) -> LauncherRanking {
        var ranking = JSONPersistence.load(LauncherRanking.self, from: url, default: LauncherRanking())
        ranking.prune(at: now)
        return ranking
    }

    func recordVisit(_ key: String, query: String, at now: Date = Date()) {
        var ranking = load(at: now)
        ranking.recordVisit(key, query: query, at: now)
        JSONPersistence.write(ranking, to: url, label: "launcher ranking")
    }
}
