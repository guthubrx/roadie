import Foundation

/// Classement appris du lanceur (SPEC-073 F3), logique pure. Deux mémoires par objet :
/// - les abréviations tapées avant de le choisir, avec leur nombre (mnémoniques à la Quicksilver) ;
/// - une fréquence-récence à demi-vie de 10 jours : l'ancre est stockée, pas le score, pour qu'aucune
///   réécriture ne soit nécessaire avec le temps (`score = 2^((ancre - t) / 10 jours)`, au moins 1).
/// Les deux mémoires existent aussi par stage active au moment du choix (SPEC-076).
struct LauncherRanking: Codable, Equatable, Sendable {
    /// Mémoire d'un objet dans une stage : mêmes règles que la mémoire globale.
    struct Context: Codable, Equatable, Sendable {
        var anchor: Double
        var abbreviations: [String: Int]
    }

    struct Entry: Codable, Equatable, Sendable {
        /// Instant (secondes depuis 1970) auquel le score retombe à 1.
        var anchor: Double
        /// Requête repliée → nombre de choix de cet objet après l'avoir tapée.
        var abbreviations: [String: Int]
        /// Par stage (`stage:<nom>` ou `scope:<place>`) ; absent des fichiers 073, ignoré par leur décodeur.
        var contexts: [String: Context]?
    }

    static let halfLife: Double = 10 * 24 * 3600
    /// Abréviations gardées par objet ; les moins utilisées partent d'abord.
    static let maxAbbreviations = 8
    /// Stages retenues par objet ; les moins récentes partent d'abord.
    static let maxContexts = 6
    private static let lambda = log(2.0) / halfLife

    var entries: [String: Entry] = [:]

    func frecency(_ key: String, at now: Date) -> Double {
        guard let anchor = entries[key]?.anchor else { return 1 }
        return Self.score(anchor, at: now)
    }

    /// Fréquence-récence de l'objet dans cette stage ; 1 sans historique. O(1).
    func frecency(_ key: String, at now: Date, context: String?) -> Double {
        guard let context, let anchor = entries[key]?.contexts?[context]?.anchor else { return 1 }
        return Self.score(anchor, at: now)
    }

    private static func score(_ anchor: Double, at now: Date) -> Double {
        max(1, exp(lambda * (anchor - now.timeIntervalSince1970)))
    }

    /// Nombre de choix de cet objet après exactement cette requête. O(1).
    func exactUses(_ key: String, query: String) -> Int {
        entries[key]?.abbreviations[LauncherMatch.fold(query)] ?? 0
    }

    /// Même chose dans cette stage seulement. O(1).
    func exactUses(_ key: String, query: String, context: String?) -> Int {
        guard let context else { return 0 }
        return entries[key]?.contexts?[context]?.abbreviations[LauncherMatch.fold(query)] ?? 0
    }

    /// Nombre de choix après une requête plus longue qui commence par celle-ci (`fi` → `fire`). O(a).
    func prefixUses(_ key: String, query: String) -> Int {
        let folded = LauncherMatch.fold(query)
        guard !folded.isEmpty, let abbreviations = entries[key]?.abbreviations else { return 0 }
        return abbreviations.reduce(0) { $0 + ($1.key.hasPrefix(folded) ? $1.value : 0) }
    }

    /// Un choix : le score gagne 100 points et la requête est mémorisée, partout et dans la stage
    /// `context` si elle est donnée. O(a log a + c).
    mutating func recordVisit(_ key: String, query: String, at now: Date, context: String? = nil) {
        let t = now.timeIntervalSince1970
        var entry = entries[key] ?? Entry(anchor: t, abbreviations: [:])
        entry.anchor = t + log(frecency(key, at: now) + 100) / Self.lambda
        let folded = LauncherMatch.fold(query)
        Self.remember(folded, in: &entry.abbreviations)
        if let context {
            var contexts = entry.contexts ?? [:]
            var local = contexts[context] ?? Context(anchor: t, abbreviations: [:])
            local.anchor = t + log(frecency(key, at: now, context: context) + 100) / Self.lambda
            Self.remember(folded, in: &local.abbreviations)
            contexts[context] = local
            if contexts.count > Self.maxContexts, let oldest = contexts.min(by: { $0.value.anchor < $1.value.anchor }) {
                contexts[oldest.key] = nil
            }
            entry.contexts = contexts
        }
        entries[key] = entry
    }

    /// Ajoute la requête ; au-delà de la borne, la moins utilisée part. O(a).
    private static func remember(_ folded: String, in abbreviations: inout [String: Int]) {
        guard !folded.isEmpty else { return }
        abbreviations[folded, default: 0] += 1
        if abbreviations.count > maxAbbreviations,
           let rarest = abbreviations.min(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }) {
            abbreviations[rarest.key] = nil
        }
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

    func recordVisit(_ key: String, query: String, at now: Date = Date(), context: String? = nil) {
        var ranking = load(at: now)
        ranking.recordVisit(key, query: query, at: now, context: context)
        JSONPersistence.write(ranking, to: url, label: "launcher ranking")
    }
}
