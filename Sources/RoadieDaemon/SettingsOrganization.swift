import Foundation

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
            order.sort { ($0 == "Profils et raccourcis" ? 0 : 1) < ($1 == "Profils et raccourcis" ? 0 : 1) }
        }
        return order.map { SettingsGroup(id: $0, title: $0, descriptors: values[$0] ?? []) }
    }

    static func title(for d: SettingDescriptor) -> String {
        let key = d.key, id = d.id
        switch d.category {
        case .general: return "Texte et lisibilité"
        case .tuilage:
            if id.hasPrefix("window_placement.") { return "Nouvelles fenêtres" }
            if id.hasPrefix("width_adjustment.") || key == "resize_handles" { return "Redimensionnement" }
            if key.contains("gap") || key == "display_overrides" { return "Marges et espaces" }
            if key.contains("filter") || key.contains("subrole") { return "Fenêtres prises en charge" }
            return "Disposition des fenêtres"
        case .stages: return "Organisation des stages et bureaux"
        case .focus: return key.contains("mouse") ? "Souris et pointeur" : "Changements de focus"
        case .bordures: return key.contains("font") ? "Texte" : "Apparence des bordures"
        case .overview: return ["enabled", "hotkey"].contains(key) ? "Activation et raccourci" : "Disposition et loupe"
        case .selecteur:
            if key == "shortcuts" { return "Profils et raccourcis" }
            if key == "excluded_bundles" { return "Applications exclues" }
            if key == "enabled" { return "Activation" }
            return key.contains("font") ? "Texte" : "Apparence commune"
        case .recherche: return key.contains("font") ? "Texte et apparence" : "Raccourci et activation"
        case .lettres: return key.contains("font") ? "Texte des repères" : "Activation et repères"
        case .grille:
            if key.contains("font") || key.contains("color") || key.contains("opacity") || key.contains("overlay") || key == "label_placement" { return "Apparence et repères" }
            if key.contains("key") || key.contains("action") || key.contains("mouse") || key.contains("focus") || key.contains("arrow") { return "Navigation et actions" }
            return "Structure de la grille"
        case .rail:
            if id.contains("stage_labels") { return "Noms et numéros des stages" }
            if id.contains("labels.") { return "Texte et légendes" }
            if id.contains("parallax.") { return "Perspective" }
            if id.contains("stacked.") { return "Empilement" }
            if id.contains("preview.") { return "Aperçus des fenêtres" }
            if id.contains("stages.") { return "Cartes et glisser-déposer" }
            if id.contains("layout.") { return "Position et espacement" }
            return "Visibilité du rail"
        case .regles:
            if id == "rules" { return "Règles de placement" }
            if id.contains("hooks") { return "Automatisations" }
            return "Exceptions"
        case .avance:
            if id.contains("record") { return "Enregistrement et macros" }
            if id.contains("titlebar") { return "Menu de la barre de titre" }
            return "Compatibilité et éléments des applications"
        }
    }
}
