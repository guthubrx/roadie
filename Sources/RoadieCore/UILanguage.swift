import Foundation

/// Langue de toute l'interface (sessions 126 et 127) : réglage `[interface] language`, sinon français si la
/// première langue de macOS est le français, anglais sinon. Les mots tapés restent acceptés dans les deux.
public enum UILanguage: String, Sendable {
    case fr, en

    /// Lue une fois au démarrage ; les rendus de la documentation la fixent pour leurs captures.
    nonisolated(unsafe) public static var current: UILanguage = detect()

    /// Ordre : `ROADIE_LANGUAGE` (`fr` ou `en`, fixé à `fr` par `scripts/test`), puis `[interface] language` du
    /// fichier de configuration, puis la première langue de macOS.
    public static func detect(_ languages: [String] = Locale.preferredLanguages,
                              environment: [String: String] = ProcessInfo.processInfo.environment,
                              configText: String? = configFileText()) -> UILanguage {
        if let forced = environment["ROADIE_LANGUAGE"].flatMap(UILanguage.init(rawValue:)) { return forced }
        if let chosen = configText.flatMap(configured) { return chosen }
        return languages.first?.lowercased().hasPrefix("fr") == true ? .fr : .en
    }

    /// `language = "fr"` ou `"en"` dans la table `[interface]` ; nil pour `auto` ou l'absence. Lecture directe du
    /// texte : le chargeur de configuration emploie déjà `tr`, il ne peut pas servir ici. O(n) lignes.
    public static func configured(_ text: String) -> UILanguage? {
        var inInterface = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            if line.hasPrefix("[") { inInterface = line == "[interface]"; continue }
            guard inInterface, line.hasPrefix("language") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == "language" else { continue }
            return UILanguage(rawValue: parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
        }
        return nil
    }

    /// Texte du fichier de configuration habituel, s'il existe.
    public static func configFileText() -> String? {
        try? String(contentsOfFile: NSString(string: "~/.config/roadies/roadies.toml").expandingTildeInPath, encoding: .utf8)
    }
}

/// Texte affiché dans la langue de l'interface. O(1).
public func tr(_ fr: String, _ en: String) -> String {
    UILanguage.current == .fr ? fr : en
}
