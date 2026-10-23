import Foundation

extension SettingsCatalog {
    /// Valeurs texte : une famille absente reste enregistrée et utilise le secours système.
    public static let fontFamilyDescriptors: [SettingDescriptor] = [
        SettingDescriptor(
            category: .recherche, tablePath: "experimental.target_mode", key: "search_font_family",
            label: "Police de la recherche",
            help: "Famille de police de la saisie et du compteur. La taille se règle séparément. Une police absente utilise la police système.",
            kind: .text, defaultValue: .string("system")
        ),
        SettingDescriptor(
            category: .recherche, tablePath: "experimental.target_mode", key: "command_font_family",
            label: "Police des suggestions",
            help: "Famille de police des suggestions et des messages. La taille se règle séparément. Une police absente utilise la police système.",
            kind: .text, defaultValue: .string("system")
        ),
    ]
}
