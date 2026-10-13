/// Raisons de refus d'une édition de `roadies.toml`. `line` est numérotée à partir de 1.
public enum ConfigEditError: Error, Equatable {
    case multilineValue(line: Int)
    case dottedKey(line: Int)
    case inlineTable(line: Int)
    case duplicateKey(line: Int)
    case duplicateTable
    case unterminatedString(line: Int)
    case ambiguousInsertion
}

/// Édite une clé scalaire de `roadies.toml` sans ré-encoder le fichier (research R5) :
/// seule la ligne visée change ; commentaires, ordre, tables inconnues et fins de ligne restent intacts.
/// Un automate suit, ligne à ligne, les chaînes (`"…"`, `'…'`, `"""`, `'''`) et les tableaux ouverts.
public enum ConfigFileEditor {
    /// `table` : chemin TOML complet de la table (`experimental.target_grid`), `key` : clé simple.
    /// `value` : LITTÉRAL TOML déjà formaté (`4`, `0.55`, `true`, `"#7AA2F7"`) ; `nil` retire la ligne de la clé.
    /// Retourne le nouveau texte. Complexité : O(L) sur L = nombre de caractères du fichier.
    public static func edit(_ text: String, table: String, key: String, value: String?) -> Result<String, ConfigEditError> {
        let found: Located
        switch locate(text, table: table, key: key) {
        case .failure(let error): return .failure(error)
        case .success(let located): found = located
        }
        var lines = found.lines
        let eol = lines.first(where: { !$0.end.isEmpty })?.end ?? "\n"

        if let keyIndex = found.keyIndex {
            if let value {
                let scalars = Array(lines[keyIndex].text.unicodeScalars)
                var view = String.UnicodeScalarView()
                view.append(contentsOf: scalars[..<found.valueRange.lowerBound])
                view.append(contentsOf: value.unicodeScalars)
                view.append(contentsOf: scalars[found.valueRange.upperBound...])
                lines[keyIndex].text = String(view)
            } else {
                // Retrait de la dernière ligne sans saut final : le fichier reste sans saut final.
                if lines[keyIndex].end.isEmpty, keyIndex > 0 { lines[keyIndex - 1].end = "" }
                lines.remove(at: keyIndex)
            }
            return .success(join(lines))
        }
        guard let value else { return .success(text) }
        // Fichier terminé dans une valeur ouverte : aucune place sûre pour la nouvelle ligne.
        guard found.endsAtTopLevel else { return .failure(.ambiguousInsertion) }

        let newLine = "\(key) = \(value)"
        if let headerIndex = found.headerIndex {
            let after = found.lastUseful ?? headerIndex
            var inserted = Line(text: newLine, end: eol)
            if after >= 0, lines[after].end.isEmpty {
                lines[after].end = eol
                inserted.end = ""
            }
            lines.insert(inserted, at: after + 1)
        } else {
            if let last = lines.indices.last {
                if lines[last].end.isEmpty { lines[last].end = eol }
                if !lines[last].text.unicodeScalars.allSatisfy(isSpace) { lines.append(Line(text: "", end: eol)) }
            }
            lines.append(Line(text: "[\(table)]", end: eol))
            lines.append(Line(text: newLine, end: eol))
        }
        return .success(join(lines))
    }

    /// Littéral TOML brut de la valeur (`4`, `"#7AA2F7"`), sans commentaire de fin de ligne ni espaces.
    /// `nil` si la clé est absente, vide, ou si l'édition serait refusée (valeur multi-lignes, clé en double…).
    /// Complexité : O(L) sur L = nombre de caractères du fichier.
    public static func readLiteral(_ text: String, table: String, key: String) -> String? {
        guard case .success(let found) = locate(text, table: table, key: key),
              let keyIndex = found.keyIndex, !found.valueRange.isEmpty else { return nil }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: Array(found.lines[keyIndex].text.unicodeScalars)[found.valueRange])
        return String(view)
    }

    /// Résultat du parcours d'un fichier pour une clé : lignes, position de la clé et de sa table.
    private struct Located {
        var lines: [Line]
        /// Index de l'en-tête de la table ; -1 pour la table racine ; `nil` si la table est absente.
        var headerIndex: Int?
        var lastUseful: Int?
        var keyIndex: Int?
        /// Position de la valeur dans la ligne de la clé (en scalaires Unicode).
        var valueRange: Range<Int>
        var endsAtTopLevel: Bool
    }

    /// Parcourt tout le fichier avec l'automate et applique les règles de refus. O(L).
    private static func locate(_ text: String, table: String, key: String) -> Result<Located, ConfigEditError> {
        let lines = splitLines(text)
        let tablePath = table.isEmpty ? [] : segments(Array(table.unicodeScalars)[...])
        let target = tablePath + [key]

        var state = ScanState()
        var context: [String] = []
        var contextIsArray = false
        var headerIndex: Int? = tablePath.isEmpty ? -1 : nil
        var lastUseful: Int?
        var keyIndex: Int?
        var valueRange = 0..<0
        var failure: ConfigEditError?
        func fail(_ error: ConfigEditError) { if failure == nil { failure = error } }

        for (index, line) in lines.enumerated() {
            let scalars = Array(line.text.unicodeScalars)
            let inTarget = !contextIsArray && context == tablePath
            // Intérieur d'une valeur multi-lignes : seule la ligne qui la referme compte comme utile.
            guard state.isTopLevel else {
                state = scan(scalars, from: 0, state).state
                if inTarget, state.isTopLevel { lastUseful = index }
                continue
            }
            guard let first = scalars.firstIndex(where: { !isSpace($0) }), scalars[first] != "#" else { continue }
            if scalars[first] == "[" {
                let isArray = first + 1 < scalars.count && scalars[first + 1] == "["
                let start = first + (isArray ? 2 : 1)
                let end = scalars[start...].firstIndex(of: "]") ?? scalars.count
                context = segments(scalars[start..<end])
                contextIsArray = isArray
                if !isArray, context == tablePath {
                    if headerIndex != nil { fail(.duplicateTable) } else { headerIndex = index }
                }
                continue
            }
            guard let equals = equalsIndex(scalars, from: first) else {
                if inTarget { lastUseful = index }
                continue
            }
            let names = segments(scalars[first..<equals])
            let result = scan(scalars, from: equals + 1, ScanState())
            state = result.state
            if inTarget, state.isTopLevel { lastUseful = index }
            guard !contextIsArray else { continue }

            let path = context + names
            let start = scalars[(equals + 1)...].firstIndex(where: { !isSpace($0) }) ?? scalars.count
            let opening = start < scalars.count ? scalars[start] : " "
            if inTarget, names == [key] {
                if keyIndex != nil { fail(.duplicateKey(line: index + 1)); continue }
                keyIndex = index
                if opening == "{" { fail(.inlineTable(line: index + 1)) }
                else if opening == "[" || !state.isTopLevel { fail(.multilineValue(line: index + 1)) }
                else if result.unterminated { fail(.unterminatedString(line: index + 1)) }
                var end = result.comment ?? scalars.count
                while end > start, isSpace(scalars[end - 1]) { end -= 1 }
                valueRange = start..<max(start, end)
            } else if names.count > 1, path.starts(with: target)
                        || (context.count < tablePath.count && path.count > tablePath.count && path.starts(with: tablePath)) {
                // La clé visée, ou la table visée, est définie par une clé pointée.
                fail(.dottedKey(line: index + 1))
            } else if path == tablePath, opening == "{" {
                fail(.inlineTable(line: index + 1))
            }
        }
        if let failure { return .failure(failure) }
        return .success(Located(
            lines: lines, headerIndex: headerIndex, lastUseful: lastUseful, keyIndex: keyIndex,
            valueRange: valueRange, endsAtTopLevel: state.isTopLevel
        ))
    }

    private struct Line {
        var text: String
        /// `"\n"`, `"\r\n"`, ou `""` pour une dernière ligne sans saut final.
        var end: String
    }

    private struct ScanState {
        var depth = 0
        /// Guillemet de la chaîne multi-lignes ouverte (`"` ou `'`).
        var multiline: Unicode.Scalar?
        var isTopLevel: Bool { depth == 0 && multiline == nil }
    }

    // O(L)
    private static func splitLines(_ text: String) -> [Line] {
        var lines: [Line] = []
        var current = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            guard scalar == "\n" else { current.append(scalar); continue }
            if current.last == "\r" {
                current.removeLast()
                lines.append(Line(text: String(current), end: "\r\n"))
            } else {
                lines.append(Line(text: String(current), end: "\n"))
            }
            current = String.UnicodeScalarView()
        }
        if !current.isEmpty { lines.append(Line(text: String(current), end: "")) }
        return lines
    }

    private static func join(_ lines: [Line]) -> String {
        lines.map { $0.text + $0.end }.joined()
    }

    private static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t"
    }

    private static func isTriple(_ s: [Unicode.Scalar], _ i: Int, _ quote: Unicode.Scalar) -> Bool {
        i + 2 < s.count && s[i] == quote && s[i + 1] == quote && s[i + 2] == quote
    }

    /// Parcourt une ligne depuis `start` avec l'état reçu. Retourne l'état en fin de ligne, la position du
    /// commentaire (premier `#` hors chaîne) et si une chaîne d'une ligne reste ouverte. O(n) sur la ligne.
    private static func scan(_ s: [Unicode.Scalar], from start: Int, _ initial: ScanState) -> (state: ScanState, comment: Int?, unterminated: Bool) {
        var state = initial
        var i = start
        while i < s.count {
            let c = s[i]
            if let quote = state.multiline {
                if quote == "\"", c == "\\" { i += 2; continue }
                if isTriple(s, i, quote) { state.multiline = nil; i += 3 } else { i += 1 }
                continue
            }
            switch c {
            case "#":
                return (state, i, false)
            case "\"", "'":
                if isTriple(s, i, c) { state.multiline = c; i += 3; continue }
                i += 1
                var closed = false
                while i < s.count {
                    if c == "\"", s[i] == "\\" { i += 2; continue }
                    i += 1
                    if s[i - 1] == c { closed = true; break }
                }
                if !closed { return (state, nil, true) }
            case "[", "{":
                state.depth += 1
                i += 1
            case "]", "}":
                state.depth = max(0, state.depth - 1)
                i += 1
            default:
                i += 1
            }
        }
        return (state, nil, false)
    }

    /// Position du `=` qui sépare la clé de la valeur (hors clé entre guillemets). O(n).
    private static func equalsIndex(_ s: [Unicode.Scalar], from start: Int) -> Int? {
        var quote: Unicode.Scalar?
        var i = start
        while i < s.count {
            let c = s[i]
            if let open = quote {
                if open == "\"", c == "\\" { i += 2; continue }
                if c == open { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "=" {
                return i
            } else if c == "#" {
                return nil
            }
            i += 1
        }
        return nil
    }

    /// Segments d'une clé ou d'un nom de table (`a . "b"` → `["a", "b"]`). O(n).
    private static func segments(_ s: ArraySlice<Unicode.Scalar>) -> [String] {
        var parts: [String] = []
        var current = String.UnicodeScalarView()
        var quote: Unicode.Scalar?
        for c in s {
            if let open = quote {
                if c == open { quote = nil } else { current.append(c) }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "." {
                parts.append(String(current))
                current = String.UnicodeScalarView()
            } else if !isSpace(c) {
                current.append(c)
            }
        }
        parts.append(String(current))
        return parts
    }
}
