import Foundation

/// Fautes de frappe rattrapées (session 134), logique pure. Une faute est une lettre oubliée, en trop, remplacée,
/// ou deux lettres voisines inversées (distance de Damerau-Levenshtein restreinte). La saisie peut tomber
/// n'importe où dans le texte : « enregsitrer » trouve « Fichier Enregistrer sous ». Aucune faute admise sous
/// 4 lettres, une jusqu'à 7, deux à partir de 8, plafonnées par le réglage `typo_max_errors`.
enum TypoMatch {
    /// Fautes admises pour une saisie de `length` caractères. O(1).
    static func allowedErrors(forLength length: Int, max: Int) -> Int {
        guard max > 0 else { return 0 }
        return length < 4 ? 0 : length < 8 ? Swift.min(1, max) : Swift.min(2, max)
    }

    /// Plus petit nombre de fautes entre `query` et un passage de `text`, ou nil au-delà de `maxErrors`.
    /// `letters` : empreintes (`LauncherMatch.letters`) ; une saisie dont plus de `maxErrors` lettres manquent
    /// au texte est écartée sans calcul. O(q × t), arrêt dès qu'une ligne dépasse le plafond.
    static func distance(_ query: [Character], in text: [Character], maxErrors: Int,
                         queryLetters: UInt64? = nil, textLetters: UInt64? = nil) -> Int? {
        guard maxErrors > 0, !query.isEmpty, !text.isEmpty else { return nil }
        if let queryLetters, let textLetters, (queryLetters & ~textLetters).nonzeroBitCount > maxErrors { return nil }
        let width = text.count + 1
        // Ligne 0 à zéro : le passage peut commencer n'importe où dans le texte.
        var older = [Int](repeating: 0, count: width)
        var previous = [Int](repeating: 0, count: width)
        var current = [Int](repeating: 0, count: width)
        for i in 1...query.count {
            current[0] = i
            var rowMin = i
            for j in 1..<width {
                let cost = query[i - 1] == text[j - 1] ? 0 : 1
                var value = Swift.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, query[i - 1] == text[j - 2], query[i - 2] == text[j - 1] {
                    value = Swift.min(value, older[j - 2] + 1)
                }
                current[j] = value
                rowMin = Swift.min(rowMin, value)
            }
            if rowMin > maxErrors { return nil }
            (older, previous, current) = (previous, current, older)
        }
        // Le passage peut aussi finir n'importe où : meilleure valeur de la dernière ligne.
        let best = previous.dropFirst().min() ?? maxErrors + 1
        return best <= maxErrors ? best : nil
    }

    /// Même mesure sur deux textes pliés par `LauncherMatch.fold`, espaces retirés ; `setting` : plafond réglé.
    /// O(q × t).
    static func distance(_ query: String, in text: String, setting: Int) -> Int? {
        let wanted = Array(LauncherMatch.fold(query).filter { !$0.isWhitespace })
        let found = Array(LauncherMatch.fold(text).filter { !$0.isWhitespace })
        return distance(wanted, in: found, maxErrors: allowedErrors(forLength: wanted.count, max: setting),
                        queryLetters: LauncherMatch.letters(wanted), textLetters: LauncherMatch.letters(found))
    }
}
