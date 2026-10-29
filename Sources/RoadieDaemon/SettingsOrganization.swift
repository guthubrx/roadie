import Foundation
import RoadieCore

struct SettingsGroup: Identifiable {
    let id: String
    let title: String
    let descriptors: [SettingDescriptor]
}

/// Partition de présentation seulement : aucun réglage n'est filtré ou réécrit. O(n).
enum SettingsOrganization {
    static func groups(_ descriptors: [SettingDescriptor]) -> [SettingsGroup] {
        var order: [String] = []
        var values: [String: [SettingDescriptor]] = [:]
        for descriptor in descriptors {
            let title = title(for: descriptor)
            if values[title] == nil { order.append(title) }
            values[title, default: []].append(descriptor)
        }
        if descriptors.first?.category == .selecteur {
            order.sort { ($0 == tr("Profils et raccourcis", "Profiles and shortcuts") ? 0 : 1) < ($1 == tr("Profils et raccourcis", "Profiles and shortcuts") ? 0 : 1) }
        }
        return order.map { SettingsGroup(id: $0, title: $0, descriptors: values[$0] ?? []) }
    }

    static func title(for d: SettingDescriptor) -> String {
        let key = d.key, id = d.id
        switch d.category {
        case .general: return tr("Texte et lisibilité", "Text and readability")
        case .raccourcis:
            if ["search_hotkey", "actions_hotkey"].contains(key) || id == "overview.hotkey" { return tr("Raccourcis globaux de Roadie", "Roadie global shortcuts") }
            if id.hasPrefix("target_grid.") { return tr("Dans la grille", "In the grid") }
            if id == "shortcuts" { return tr("Commandes Roadie", "Roadie commands") }
            return tr("Dans la barre de recherche", "In the search bar")
        case .tuilage:
            if id.hasPrefix("window_placement.") { return tr("Nouvelles fenêtres", "New windows") }
            if id.hasPrefix("width_adjustment.") || key == "resize_handles" { return tr("Redimensionnement", "Resizing") }
            if key.contains("gap") || key == "display_overrides" { return tr("Marges et espaces", "Gaps and spacing") }
            if key.contains("filter") || key.contains("subrole") { return tr("Fenêtres prises en charge", "Supported windows") }
            return tr("Disposition des fenêtres", "Window layout")
        case .stages: return tr("Organisation des stages et bureaux", "Stages and desktops")
        case .focus: return key.contains("mouse") ? tr("Souris et pointeur", "Mouse and pointer") : tr("Changements de focus", "Focus changes")
        case .bordures: return key.contains("font") ? tr("Texte", "Text") : tr("Apparence des bordures", "Border appearance")
        case .overview: return key == "enabled" ? tr("Activation", "Activation") : tr("Disposition et loupe", "Layout and magnifier")
        case .selecteur:
            if key == "shortcuts" { return tr("Profils et raccourcis", "Profiles and shortcuts") }
            if key == "excluded_bundles" { return tr("Applications exclues", "Excluded apps") }
            if key == "enabled" { return tr("Activation", "Activation") }
            return key.contains("font") ? tr("Texte", "Text") : tr("Apparence commune", "Shared appearance")
        case .recherche: return key.contains("font") ? tr("Texte et apparence", "Text and appearance") : tr("Activation et contenu", "Activation and content")
        case .lettres: return key.contains("font") ? tr("Texte des repères", "Label text") : tr("Activation et repères", "Activation and labels")
        case .grille:
            if key.contains("font") || key.contains("color") || key.contains("opacity") || key.contains("overlay") || key == "label_placement" { return tr("Apparence et repères", "Appearance and labels") }
            if key.contains("key") || key.contains("action") || key.contains("mouse") || key.contains("focus") || key.contains("arrow") { return tr("Navigation et actions", "Navigation and actions") }
            return tr("Structure de la grille", "Grid structure")
        case .rail:
            if id.contains("stage_labels") { return tr("Noms et numéros des stages", "Stage names and numbers") }
            if id.contains("labels.") { return tr("Texte et légendes", "Text and captions") }
            if id.contains("parallax.") { return tr("Perspective", "Perspective") }
            if id.contains("stacked.") { return tr("Empilement", "Stacking") }
            if id.contains("preview.") { return tr("Aperçus des fenêtres", "Window previews") }
            if id.contains("stages.") { return tr("Cartes et glisser-déposer", "Cards and drag and drop") }
            if id.contains("layout.") { return tr("Position et espacement", "Position and spacing") }
            return tr("Visibilité du rail", "Rail visibility")
        case .regles:
            if id == "rules" { return tr("Règles de placement", "Placement rules") }
            if id.contains("hooks") { return tr("Automatisations", "Automations") }
            return tr("Exceptions", "Exceptions")
        case .avance:
            if id.contains("record") { return tr("Enregistrement et macros", "Recording and macros") }
            if id.contains("titlebar") { return tr("Menu de la barre de titre", "Title bar menu") }
            return tr("Compatibilité et éléments des applications", "Compatibility and app elements")
        }
    }
}
