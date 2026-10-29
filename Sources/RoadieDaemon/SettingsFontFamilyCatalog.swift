import Foundation
import RoadieCore

extension SettingsCatalog {
    /// Valeurs texte : une famille absente reste enregistrée et utilise le secours système.
    public static let fontFamilyDescriptors: [SettingDescriptor] = [
        SettingDescriptor(
            category: .recherche, tablePath: "experimental.target_mode", key: "search_font_family",
            label: tr("Police de la recherche", "Search font"),
            help: tr("Famille de police de la saisie et du compteur. La taille se règle séparément. Une police absente utilise la police système.", "Font family of the typed text and the counter. Size is set separately. A missing font falls back to the system font."),
            kind: .text, defaultValue: .string("system")
        ),
        SettingDescriptor(
            category: .recherche, tablePath: "experimental.target_mode", key: "command_font_family",
            label: tr("Police des suggestions", "Suggestion font"),
            help: tr("Famille de police des suggestions et des messages. La taille se règle séparément. Une police absente utilise la police système.", "Font family of suggestions and messages. Size is set separately. A missing font falls back to the system font."),
            kind: .text, defaultValue: .string("system")
        ),
    ]
}
