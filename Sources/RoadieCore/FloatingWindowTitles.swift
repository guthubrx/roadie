import Foundation

/// Fenêtres d'une application qui flottent toujours, reconnues par leur titre (session 125) :
/// `[[exclusions.floating_windows]]` avec `app` et `title`. Pour macOS, un rappel, une boîte de dialogue
/// ou une palette ressemble souvent à une fenêtre ordinaire ; seul son titre la distingue.
public struct FloatingWindowConfig: Equatable, Codable, Sendable {
    /// Nom de l'application (« Thunderbird ») ou son identifiant (`org.mozilla.thunderbird`), sans casse.
    public var app: String
    /// Titre, sans casse : `#` remplace un nombre, `*` n'importe quel texte (« # Reminder »).
    public var title: String

    public init(app: String, title: String) {
        self.app = app
        self.title = title
    }
}

public enum FloatingWindowTitles {
    /// Au-dessus des règles générées par application (9 000) : seule la première règle trouvée agit.
    public static let priority = 9_100
    public static let rulePrefix = "float-title"

    /// Titre d'une fenêtre écrit pour la liste : chaque nombre devient `#`, un `#` ou une `*` du titre
    /// devient `*`. nil pour un titre vide. « 1 Reminder » donne « # Reminder ». O(t).
    public static func text(fromTitle title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var text = ""
        var inNumber = false
        for character in trimmed {
            if character.isASCII, character.isNumber {
                if !inNumber { text.append("#") }
                inNumber = true
                continue
            }
            inNumber = false
            text.append(character == "#" || character == "*" ? "*" : character)
        }
        return text
    }

    /// Expression ancrée et sans casse d'un titre de la liste : `#` devient `\d+` et le mot qui suit
    /// accepte un « s » final (« # Reminder » couvre « 3 Reminders »), `*` devient `.*`. O(t).
    public static func regex(_ text: String) -> String {
        var regex = "(?i)^"
        var segment = ""
        var afterNumber = false
        func flush() {
            guard !segment.isEmpty else { return }
            var escaped = NSRegularExpression.escapedPattern(for: segment)
            if afterNumber, let start = segment.firstIndex(where: { !$0.isWhitespace }), start != segment.startIndex {
                let word = segment[start...].prefix { $0.isLetter }
                if !word.isEmpty {
                    let stem = word.hasSuffix("s") ? String(word.dropLast()) : String(word)
                    escaped = NSRegularExpression.escapedPattern(for: String(segment[..<start]))
                        + NSRegularExpression.escapedPattern(for: stem) + "s?"
                        + NSRegularExpression.escapedPattern(for: String(segment[start...].dropFirst(word.count)))
                }
            }
            regex += escaped
            segment = ""
            afterNumber = false
        }
        for character in text.trimmingCharacters(in: .whitespacesAndNewlines) {
            switch character {
            case "#":
                flush()
                regex += "\\d+"
                afterNumber = true
            case "*":
                flush()
                regex += ".*"
            default:
                segment.append(character)
            }
        }
        flush()
        return regex + "$"
    }

    /// Règles de flottement des lignes valides, une par couple application-titre. O(n).
    public static func rules(_ entries: [FloatingWindowConfig]) -> [WindowRule] {
        var seen = Set<String>()
        return entries.compactMap { entry in
            let app = entry.app.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !app.isEmpty, !title.isEmpty else { return nil }
            let id = "\(rulePrefix)-\(hash(app.lowercased()))-\(hash(title.lowercased()))"
            guard seen.insert(id).inserted else { return nil }
            var match = RuleMatch(appRegex: "(?i)^\(NSRegularExpression.escapedPattern(for: app))$")
            match.titleRegex = regex(title)
            return WindowRule(id: id, enabled: true, priority: priority, stopProcessing: true, match: match,
                              action: RuleAction(floating: true))
        }
    }

    /// Empreinte FNV-1a stable d'un texte, en hexadécimal. O(t).
    private static func hash(_ value: String) -> String {
        String(value.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }, radix: 16)
    }
}
