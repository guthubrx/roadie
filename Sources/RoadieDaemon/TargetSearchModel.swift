import Foundation

/// Mode recherche du mode lettres (SPEC-021), à la manière de Homerow : logique pure, sans écran.
/// La session interactive transmet les touches et dessine `matches`, `highlighted` et `properties`.
public struct TargetSearchModel: Equatable, Sendable {
    /// Délai pour reconnaître deux Retour comme un double-clic : le premier est différé d'autant.
    public static let doubleReturnInterval: TimeInterval = 0.35

    public private(set) var targets: [RoadieTarget]
    public private(set) var query = ""
    public private(set) var matches: [RoadieTarget]
    public private(set) var highlightedIndex: Int?
    /// Propriétés de la cible mise en avant, affichées après `?` jusqu'à la frappe suivante.
    public private(set) var properties: String?
    private var labelBuffer = ""
    private var pendingReturnAt: Date?

    public init(targets: [RoadieTarget]) {
        self.targets = targets
        self.matches = targets
        self.highlightedIndex = targets.isEmpty ? nil : 0
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
        matches = Self.matches(targets, query: query)
        highlightedIndex = matches.isEmpty ? nil : 0
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
