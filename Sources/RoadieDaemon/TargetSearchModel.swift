import Foundation

/// Mode recherche du mode lettres (SPEC-021), à la manière de Homerow : logique pure, sans écran.
/// La session interactive transmet les touches et dessine `matches`, `highlighted` et `properties`.
public struct TargetSearchModel: Equatable, Sendable {
    /// Délai pour reconnaître deux Retour comme un double-clic : le premier est différé d'autant.
    public static let doubleReturnInterval: TimeInterval = 0.35
    /// Cibles gardées au plus ; les étiquettes de cette réserve sont données dans l'ordre d'arrivée.
    public static let maxTargets = 500

    /// Triées par rang ; à rang égal, par ordre d'arrivée.
    public private(set) var targets: [RoadieTarget] = []
    private var ranks: [Int] = []
    private let labelPool: [String]
    /// Étiquettes d'une lettre (A, S, D…) : données aux résultats quand il y en a au plus autant.
    private let shortLabels: [String]
    private var labelsUsed = 0
    public private(set) var query = ""
    public private(set) var matches: [RoadieTarget]
    public private(set) var highlightedIndex: Int?
    /// Propriétés de la cible mise en avant, affichées après `?` jusqu'à la frappe suivante.
    public private(set) var properties: String?
    private var labelBuffer = ""
    private var pendingReturnAt: Date?

    public init(targets: [RoadieTarget], alphabet: String = "asdfghjkl", rank: (RoadieTarget) -> Int = { _ in 0 }) {
        labelPool = TargetHintService.labels(count: Self.maxTargets, alphabet: alphabet)
        shortLabels = labelPool.filter { $0.count == 1 }
        matches = []
        append(targets, rank: rank)
    }

    /// Cibles d'une fenêtre lue pendant la saisie (SPEC-021, barre immédiate). Chaque cible reçoit
    /// une étiquette à son arrivée et la garde : rien ne bouge sous les yeux. Rang plus petit d'abord,
    /// ordre d'arrivée à rang égal. La cible mise en avant le reste si elle correspond encore.
    /// Complexité : O(n + b log b), n cibles présentes, b cibles reçues.
    public mutating func append(_ batch: [RoadieTarget], rank: (RoadieTarget) -> Int) {
        let room = Self.maxTargets - targets.count
        guard room > 0, !batch.isEmpty else { return }
        let incoming = batch.prefix(room).enumerated()
            .map { offset, target -> (rank: Int, offset: Int, target: RoadieTarget) in
                var labeled = target
                labeled.label = labelPool[labelsUsed + offset]
                return (rank(target), offset, labeled)
            }
            .sorted { ($0.rank, $0.offset) < ($1.rank, $1.offset) }
        labelsUsed += incoming.count
        // Fusion de deux suites triées ; à rang égal, la cible déjà présente reste devant.
        var mergedTargets: [RoadieTarget] = []
        var mergedRanks: [Int] = []
        mergedTargets.reserveCapacity(targets.count + incoming.count)
        var old = 0
        for item in incoming {
            while old < targets.count, ranks[old] <= item.rank {
                mergedTargets.append(targets[old])
                mergedRanks.append(ranks[old])
                old += 1
            }
            mergedTargets.append(item.target)
            mergedRanks.append(item.rank)
        }
        mergedTargets.append(contentsOf: targets[old...])
        mergedRanks.append(contentsOf: ranks[old...])
        targets = mergedTargets
        ranks = mergedRanks

        let highlightedID = highlighted?.id
        matches = shortened(Self.matches(targets, query: query))
        highlightedIndex = matches.firstIndex { $0.id == highlightedID } ?? (query.isEmpty || matches.isEmpty ? nil : 0)
    }

    /// Retour seul en attente d'un éventuel second Retour : les autres touches sont ignorées.
    public var isAwaitingSecondReturn: Bool { pendingReturnAt != nil }

    /// Échap ou fermeture : l'action différée est abandonnée.
    public mutating func cancelPendingReturn() { pendingReturnAt = nil }

    public var highlighted: RoadieTarget? {
        highlightedIndex.map { matches[$0] }
    }

    public mutating func type(_ text: String) {
        properties = nil
        if text == "?" {
            properties = highlighted.map(Self.describe)
            return
        }
        query += text
        refresh()
    }

    public mutating func deleteBackward() {
        properties = nil
        guard !query.isEmpty else { return }
        query.removeLast()
        refresh()
    }

    public mutating func next() {
        guard let index = highlightedIndex else { return }
        highlightedIndex = (index + 1) % matches.count
    }

    public mutating func previous() {
        guard let index = highlightedIndex else { return }
        highlightedIndex = (index - 1 + matches.count) % matches.count
    }

    /// Maj + label : met en avant la correspondance dont le label vaut les caractères tapés.
    /// Faux si aucun label ne commence ainsi (la saisie du label repart de zéro).
    public mutating func typeLabel(_ character: String) -> Bool {
        // Barre vide : aucune étiquette n'est affichée.
        guard !query.isEmpty else { return false }
        let candidate = labelBuffer + character.uppercased()
        let labels = matches.map { $0.label.uppercased() }
        guard labels.contains(where: { $0.hasPrefix(candidate) }) else {
            labelBuffer = ""
            return false
        }
        labelBuffer = candidate
        if let index = labels.firstIndex(of: candidate) {
            highlightedIndex = index
        }
        return true
    }

    /// Retour : Maj = clic droit, Cmd = Cmd-clic, immédiats. Retour seul est différé de
    /// `doubleReturnInterval` : un second Retour dans ce délai donne un double-clic (nil sinon,
    /// la session appelle `pendingReturn` à l'échéance). Cible Roadie : son action par défaut.
    public mutating func pressReturn(shift: Bool, command: Bool, at now: Date) -> TargetActionVerb? {
        guard let target = highlighted else { return nil }
        if shift || command {
            pendingReturnAt = nil
            return Self.verb(shift ? .rightClick : .commandClick, for: target)
        }
        if let first = pendingReturnAt, now.timeIntervalSince(first) < Self.doubleReturnInterval {
            pendingReturnAt = nil
            return Self.verb(.doubleClick, for: target)
        }
        pendingReturnAt = now
        return nil
    }

    /// Retour seul arrivé à échéance sans second Retour : clic simple.
    public mutating func pendingReturn(at now: Date) -> TargetActionVerb? {
        guard let first = pendingReturnAt, now.timeIntervalSince(first) >= Self.doubleReturnInterval,
              let target = highlighted
        else { return nil }
        pendingReturnAt = nil
        return Self.verb(.click, for: target)
    }

    /// Complexité : O(n) par frappe, n cibles de la session (≤ max_targets + cibles Roadie).
    public static func matches(_ targets: [RoadieTarget], query: String) -> [RoadieTarget] {
        let needle = compact(query)
        guard !needle.isEmpty, needle != "*", needle != ";" else { return targets }
        let found = targets.filter { compact($0.matchText + " " + ($0.searchText ?? "")).contains(needle) }
        let leading = found.filter { startsWith($0, needle) }
        return leading + found.filter { !startsWith($0, needle) }
    }

    /// Casse, accents et espaces ignorés (« watchlater » trouve « Watch Later »).
    static func compact(_ value: String) -> String {
        TargetHintService.normalized(value).replacingOccurrences(of: " ", with: "")
    }

    /// Titre, ou texte des enfants d'une cible web dont le titre n'est que son rôle.
    private static func startsWith(_ target: RoadieTarget, _ needle: String) -> Bool {
        compact(target.title).hasPrefix(needle) || compact(target.searchText ?? "").hasPrefix(needle)
    }

    private mutating func refresh() {
        labelBuffer = ""
        pendingReturnAt = nil
        matches = shortened(Self.matches(targets, query: query))
        // Barre vide : aucune étiquette affichée, donc rien à valider.
        highlightedIndex = query.isEmpty || matches.isEmpty ? nil : 0
    }

    /// Peu de résultats (au plus un par lettre de l'alphabet) : étiquettes A, S, D… dans l'ordre
    /// affiché, pour choisir par Maj + une seule lettre. Les cibles gardent leur étiquette d'origine.
    private func shortened(_ found: [RoadieTarget]) -> [RoadieTarget] {
        guard !query.isEmpty, found.count <= shortLabels.count else { return found }
        return found.enumerated().map { index, target in
            var short = target
            short.label = shortLabels[index]
            return short
        }
    }

    private static func verb(_ wanted: TargetActionVerb, for target: RoadieTarget) -> TargetActionVerb? {
        if target.source == .app { return wanted }
        return target.actions.first
    }

    private static func describe(_ target: RoadieTarget) -> String {
        [target.label, target.kind.rawValue, target.title, target.subtitle, target.searchText ?? "", target.id]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
