import Foundation

// MARK: - Validation des labels de desktop (T041, US4, FR-023)
//
// Règles (contrat cli-desktop.md + spec FR-023) :
//   - regex ^[a-zA-Z0-9_-]{0,32}$
//   - labels réservés interdits (collision avec les sélecteurs de navigation)

/// Labels réservés par le sélecteur de navigation (Selector.swift).
/// Un desktop ne peut pas porter ces noms pour éviter toute ambiguïté.
private let reservedLabels: Set<String> = [
    "prev", "next", "recent", "first", "last", "current",
]

/// Ensemble des scalaires autorisés : ASCII alphanumérique + underscore + tiret.
/// Intentionnellement restreint à l'ASCII (pas d'Unicode étendu — spec FR-023).
private let allowedScalars: CharacterSet =
    CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")

/// Valide un label de desktop.
/// - Returns: `true` si le label est vide (= retrait du label) ou conforme.
/// - Note: chaîne vide = retrait du label, toujours valide.
public func isValidDesktopLabel(_ label: String) -> Bool {
    guard !label.isEmpty else { return true }   // vide = retrait
    guard label.count <= 32 else { return false }
    return label.unicodeScalars.allSatisfy { allowedScalars.contains($0) }
}

/// Vérifie si un label est réservé par le sélecteur de navigation.
/// Les labels réservés ne peuvent pas être attribués à un desktop.
public func isReservedDesktopLabel(_ label: String) -> Bool {
    reservedLabels.contains(label)
}
