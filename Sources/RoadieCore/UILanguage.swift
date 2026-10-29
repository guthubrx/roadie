import Foundation

/// Langue des textes de la barre, du sélecteur et de la vue d'ensemble (session 126) : français si la
/// première langue de macOS est le français, anglais sinon. Les mots tapés restent acceptés dans les deux.
public enum UILanguage: String, Sendable {
    case fr, en

    /// Lue une fois au démarrage ; les rendus de la documentation la fixent pour leurs captures.
    nonisolated(unsafe) public static var current: UILanguage = detect()

    /// `ROADIE_LANGUAGE` (`fr` ou `en`) l'emporte : `scripts/test` fixe le français, attendu par les tests.
    public static func detect(_ languages: [String] = Locale.preferredLanguages,
                              environment: [String: String] = ProcessInfo.processInfo.environment) -> UILanguage {
        if let forced = environment["ROADIE_LANGUAGE"].flatMap(UILanguage.init(rawValue:)) { return forced }
        return languages.first?.lowercased().hasPrefix("fr") == true ? .fr : .en
    }
}

/// Texte affiché dans la langue de l'interface. O(1).
public func tr(_ fr: String, _ en: String) -> String {
    UILanguage.current == .fr ? fr : en
}
