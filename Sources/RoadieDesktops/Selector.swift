import Foundation
import RoadieCore

/// Résout un sélecteur textuel de desktop en identifiant entier 1..count.
/// Gère : numéros, labels, prev/next/recent/first/last (contrats/cli-desktop.md).
/// Retourne nil si le sélecteur ne résout pas.
///
/// SPEC-025 amend — paramètre `inhabited` (set des desktop IDs avec ≥1 fenêtre) :
/// si fourni, `prev`/`next` ne naviguent QUE dans cet ensemble (cohérent avec
/// i3, Hyprland, AeroSpace : les desktops vides ne sont jamais "atteints" par
/// la nav relative). Tap explicite par numéro reste autorisé. Si l'ensemble
/// est vide ou non fourni, fallback sur le wrap arithmétique 1..count.
public func resolveSelector(
    _ s: String,
    registry: DesktopRegistry,
    count: Int,
    inhabited: Set<Int>? = nil
) async -> Int? {
    let selector = s.trimmingCharacters(in: .whitespaces)
    guard !selector.isEmpty else { return nil }

    // 1. Numéro direct (autorisé même sur desktop vide).
    if let n = Int(selector), (1...count).contains(n) {
        logInfo("desktop_selector_resolved", [
            "input": selector, "method": "explicit_id", "target": String(n),
        ])
        return n
    }

    let currentID = await registry.currentID
    let recentID = await registry.recentID

    // 2. Mots-clés de navigation
    switch selector {
    case "prev":
        let target = navigateRelative(currentID: currentID, count: count,
                                       inhabited: inhabited, direction: -1)
        logInfo("desktop_selector_resolved", [
            "input": selector, "method": "prev",
            "current": String(currentID), "target": String(target ?? -1),
            "inhabited_count": String(inhabited?.count ?? -1),
        ])
        return target
    case "next":
        let target = navigateRelative(currentID: currentID, count: count,
                                       inhabited: inhabited, direction: +1)
        logInfo("desktop_selector_resolved", [
            "input": selector, "method": "next",
            "current": String(currentID), "target": String(target ?? -1),
            "inhabited_count": String(inhabited?.count ?? -1),
        ])
        return target
    case "recent":
        logInfo("desktop_selector_resolved", [
            "input": selector, "method": "recent",
            "target": recentID.map(String.init) ?? "nil",
        ])
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
            logInfo("desktop_selector_resolved", [
                "input": selector, "method": "label", "target": String(desktop.id),
            ])
            return desktop.id
        }
    }

    return nil
}

/// Navigation relative prev/next.
/// - Si `inhabited` est fourni et non vide : navigue uniquement dans cet ensemble
///   (skip les desktops vides). Wrap-around dans l'ensemble habité.
/// - Sinon : wrap arithmétique 1..count (compat backward).
private func navigateRelative(currentID: Int, count: Int,
                              inhabited: Set<Int>?, direction: Int) -> Int? {
    if let inh = inhabited, !inh.isEmpty {
        let sorted = inh.sorted()
        // Si le current est habité, on part de sa position dans la liste.
        // Sinon, on choisit l'élément le plus proche dans la direction.
        if let idx = sorted.firstIndex(of: currentID) {
            let next = (idx + direction + sorted.count) % sorted.count
            return sorted[next]
        }
        // current pas dans inhabited (ex: desktop vide où on est arrivé) :
        // chercher le voisin habité dans la direction.
        if direction > 0 {
            return sorted.first(where: { $0 > currentID }) ?? sorted.first
        } else {
            return sorted.last(where: { $0 < currentID }) ?? sorted.last
        }
    }
    // Fallback : wrap arithmétique 1..count.
    if direction > 0 {
        return currentID < count ? currentID + 1 : 1
    } else {
        return currentID > 1 ? currentID - 1 : count
    }
}
