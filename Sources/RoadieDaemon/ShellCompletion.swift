import Foundation

/// Script de complétion zsh de `roadie`, produit depuis la table des commandes (spec 155).
/// Deux niveaux seulement : la commande, puis le premier mot qui suit.
enum ShellCompletion {
    // O(n), n = lignes de la table (< 100). La recherche d'un doublon parcourt les
    // sous-commandes d'une seule commande : borne constatée < 15.
    static func zsh(specs: [CLICommandSpec]) -> String {
        var order: [String] = []
        var subcommands: [String: [String]] = [:]
        for spec in specs where spec.implemented {
            let tokens = spec.usage.split(separator: " ")
            guard let head = tokens.first else { continue }
            let seconds = tokens.count > 1 ? words(tokens[1]) : []
            for name in words(head) {
                if subcommands[name] == nil {
                    order.append(name)
                    subcommands[name] = []
                }
                for second in seconds where subcommands[name]?.contains(second) != true {
                    subcommands[name, default: []].append(second)
                }
            }
        }

        var lines = [
            "#compdef roadie",
            "",
            "_roadie() {",
            "  local -a commands",
            "  commands=(\(order.joined(separator: " ")))",
            "  if (( CURRENT == 2 )); then",
            "    compadd -a commands",
            "    return",
            "  fi",
            "  if (( CURRENT == 3 )); then",
            "    case \"$words[2]\" in",
        ]
        for name in order {
            guard let seconds = subcommands[name], !seconds.isEmpty else { continue }
            lines.append("      \(name)) compadd \(seconds.joined(separator: " ")) ;;")
        }
        lines += [
            "    esac",
            "  fi",
            "}",
            "",
            "if (( $+functions[compdef] )); then compdef _roadie roadie; fi",
        ]
        return lines.joined(separator: "\n")
    }

    /// Mots proposables d'un élément d'usage : `list|current` donne deux mots ; `[--json]`,
    /// `ID` et `--version` n'en donnent aucun.
    private static func words(_ token: Substring) -> [String] {
        token.split(separator: "|").map(String.init).filter { word in
            guard let first = word.unicodeScalars.first, CharacterSet.lowercaseLetters.contains(first) else { return false }
            return word.unicodeScalars.allSatisfy {
                CharacterSet.lowercaseLetters.contains($0) || CharacterSet.decimalDigits.contains($0) || $0 == "-"
            }
        }
    }
}
