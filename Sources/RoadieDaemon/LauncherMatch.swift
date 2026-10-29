import Foundation

/// Appariement approximatif du lanceur (SPEC-073 F2), logique pure.
/// Les lettres de la requête doivent apparaître dans l'ordre. Une lettre vaut 4 points au début du
/// texte, 3 sur un début de mot, 2 ailleurs ; un saut depuis la lettre précédente coûte 2 points.
/// Le résultat est retenu s'il atteint 2 points par lettre moins 1, et au moins 3 : une sous-chaîne
/// passe, des initiales aussi (`vsc` pour Visual Studio Code, `ps` pour Adobe Photoshop), une lettre
/// seule seulement sur un début de mot, un éparpillement (`feox` pour Firefox) non.
/// Casse, accents et largeur ignorés.
enum LauncherMatch {
    private static let textStart = 4, wordStart = 3, inside = 2, jumpCost = 2

    /// Clé de comparaison : minuscules, sans accents ni largeur, espaces de bord retirés.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Empreinte d'un texte plié (session 123) : un bit par lettre a-z ou chiffre présent. Un texte dont
    /// l'empreinte ne couvre pas celle de la saisie ne peut pas lui correspondre ; les autres caractères
    /// n'entrent pas dans l'empreinte, qui n'écarte donc jamais à tort. O(t).
    static func letters<S: Sequence>(_ characters: S) -> UInt64 where S.Element == Character {
        var mask: UInt64 = 0
        for character in characters {
            guard let ascii = character.asciiValue else { continue }
            switch ascii {
            case 97...122: mask |= 1 << UInt64(ascii - 97)
            case 48...57: mask |= 1 << UInt64(ascii - 48 + 26)
            default: break
            }
        }
        return mask
    }

    /// Saisie pliée une fois par frappe (session 123) : lettres sans espaces.
    struct Query: Sendable {
        let wanted: [Character]
        let compact: String
        let letters: UInt64

        init?(_ query: String) {
            wanted = Array(LauncherMatch.fold(query).filter { !$0.isWhitespace })
            guard !wanted.isEmpty else { return nil }
            compact = String(wanted)
            letters = LauncherMatch.letters(wanted)
        }
    }

    /// Texte plié une fois (session 123) : caractère par caractère pour garder les positions, débuts de mot,
    /// et forme compacte pour l'égalité complète. Un caractère ASCII se plie en minuscule sans appel
    /// Foundation : même résultat, cent fois moins cher. O(t).
    struct Prepared: Sendable {
        let folded: [Character]
        let starts: [Bool]
        let compact: String
        let letters: UInt64

        init(_ text: String) {
            let original = Array(text)
            folded = original.map { $0.isASCII ? Character($0.lowercased()) : (LauncherMatch.fold(String($0)).first ?? $0) }
            starts = original.indices.map { LauncherMatch.isWordStart(original, at: $0) }
            // Pliage du texte entier, qui peut changer la longueur (« ß » → « ss ») ; en ASCII, le pliage par lettre.
            compact = original.allSatisfy(\.isASCII)
                ? String(folded.filter { !$0.isWhitespace })
                : String(LauncherMatch.fold(text).filter { !$0.isWhitespace })
            letters = LauncherMatch.letters(folded)
        }
    }

    /// Meilleur score de la requête dans le texte, ou nil sous le seuil. Égalité complète, espaces
    /// ignorés : `Int.max`. O(q × t), q et t bornés par la taille d'un nom.
    static func score(_ query: String, in text: String) -> Int? {
        guard let query = Query(query) else { return nil }
        return score(query, in: Prepared(text))
    }

    /// Même score sur une saisie et un texte déjà pliés. Un texte qui ne contient pas les lettres dans l'ordre
    /// est écarté en une lecture : le calcul complet n'y trouverait rien. O(t) écarté, O(q × t) sinon.
    static func score(_ query: Query, in text: Prepared) -> Int? {
        if text.compact == query.compact { return Int.max }
        guard query.letters & ~text.letters == 0 else { return nil }
        let wanted = query.wanted, folded = text.folded, starts = text.starts
        var matched = 0
        for character in folded where character == wanted[matched] {
            matched += 1
            if matched == wanted.count { break }
        }
        guard matched == wanted.count else { return nil }
        let none = Int.min
        // best[j] : meilleur score avec la lettre courante de la requête posée sur le caractère j.
        var best = [Int](repeating: none, count: folded.count)
        for (i, letter) in wanted.enumerated() {
            var next = [Int](repeating: none, count: folded.count)
            var farthest = none // meilleur score de la lettre précédente posée avant j - 1
            for j in folded.indices {
                if j >= 2 { farthest = max(farthest, best[j - 2]) }
                guard folded[j] == letter else { continue }
                let points = j == 0 ? textStart : starts[j] ? wordStart : inside
                if i == 0 { next[j] = points; continue }
                if j > 0, best[j - 1] != none { next[j] = best[j - 1] + points }
                if farthest != none { next[j] = max(next[j], farthest + points - jumpCost) }
            }
            best = next
        }
        guard let found = best.max(), found != none, found >= max(wordStart, inside * wanted.count - 1) else { return nil }
        return found
    }

    /// Début de mot : premier caractère, après un séparateur, majuscule après une minuscule
    /// (`OrbStack`), lettre après un chiffre (`1Password`). O(1).
    fileprivate static func isWordStart(_ characters: [Character], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = characters[index - 1], current = characters[index]
        if previous.isWhitespace || "-._/()[]".contains(previous) { return current.isLetter || current.isNumber }
        if current.isUppercase, previous.isLowercase { return true }
        return current.isLetter && previous.isNumber
    }
}
