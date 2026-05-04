import Foundation

/// Résout un sélecteur textuel de desktop en identifiant entier 1..count.
/// Gère : numéros, labels, prev/next/recent/first/last (contrats/cli-desktop.md).
/// Retourne nil si le sélecteur ne résout pas.
public func resolveSelector(
    _ s: String,
    registry: DesktopRegistry,
    count: Int
) async -> Int? {
    let selector = s.trimmingCharacters(in: .whitespaces)
    guard !selector.isEmpty else { return nil }

    // 1. Numéro direct
    if let n = Int(selector), (1...count).contains(n) {
        return n
    }

    let currentID = await registry.currentID
    let recentID = await registry.recentID

    // 2. Mots-clés de navigation
    switch selector {
    case "prev":
        let prev = currentID > 1 ? currentID - 1 : count
        return prev
    case "next":
        let next = currentID < count ? currentID + 1 : 1
        return next
    case "recent":
        return recentID
    case "first":
        return 1
    case "last":
        return count
    default:
        break
    }

    // 3. Résolution par label (case-sensitive, cf. contrat)
    let all = await registry.allDesktops()
    for desktop in all {
        if let label = desktop.label, label == selector {
            return desktop.id
        }
    }

    return nil
}
