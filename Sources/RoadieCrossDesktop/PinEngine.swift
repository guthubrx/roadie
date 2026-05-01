import Foundation

/// Résolution d'une PinRule en UUID de desktop cible.
/// L'`labelResolver` retourne l'UUID associé à un label (fourni par SPEC-003 multi-desktop).
/// L'`indexResolver` retourne l'UUID associé à un index 1-based.
public struct PinEngine: Sendable {
    public let rules: [PinRule]
    private let labelResolver: @Sendable (String) -> String?
    private let indexResolver: @Sendable (Int) -> String?

    public init(rules: [PinRule],
                labelResolver: @escaping @Sendable (String) -> String?,
                indexResolver: @escaping @Sendable (Int) -> String?) {
        self.rules = rules
        self.labelResolver = labelResolver
        self.indexResolver = indexResolver
    }

    /// Retourne l'UUID cible pour un bundleID si une rule match. Premier match gagne.
    /// Retourne nil si :
    /// - aucune rule ne match le bundleID
    /// - la rule a `desktop_label` mais le label est inconnu
    /// - la rule a `desktop_index` mais l'index est invalide
    public func target(forBundleID bundleID: String) -> String? {
        guard let rule = rules.first(where: { $0.bundleID == bundleID }) else { return nil }
        if let label = rule.desktopLabel { return labelResolver(label) }
        if let idx = rule.desktopIndex { return indexResolver(idx) }
        return nil
    }
}
