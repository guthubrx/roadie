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

    /// Meilleur score de la requête dans le texte, ou nil sous le seuil. Égalité complète, espaces
    /// ignorés : `Int.max`. O(q × t), q et t bornés par la taille d'un nom.
    static func score(_ query: String, in text: String) -> Int? {
        let wanted = Array(fold(query).filter { !$0.isWhitespace })
        guard !wanted.isEmpty else { return nil }
        if String(fold(text).filter { !$0.isWhitespace }) == String(wanted) { return Int.max }
        let original = Array(text)
        let folded = original.map { fold(String($0)).first ?? $0 }
        let starts = original.indices.map { isWordStart(original, at: $0) }
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
    private static func isWordStart(_ characters: [Character], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = characters[index - 1], current = characters[index]
        if previous.isWhitespace || "-._/()[]".contains(previous) { return current.isLetter || current.isNumber }
        if current.isUppercase, previous.isLowercase { return true }
        return current.isLetter && previous.isNumber
    }
}
