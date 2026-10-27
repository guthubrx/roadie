import Foundation

/// Résultat d'un calcul tapé dans la barre (SPEC-087).
struct LauncherCalculation: Equatable, Sendable {
    /// Saisie relue, sans espaces autour.
    let expression: String
    let value: Double
    /// Résultat mis en forme : 12 chiffres significatifs, séparateur décimal de la langue, sans groupement.
    let text: String
}

/// Calculatrice du lanceur : analyseur à descente récursive, sans `NSExpression` qui lève une exception
/// Objective-C, impossible à rattraper, sur une saisie incomplète (research R1). Pur et testable.
enum LauncherCalculator {
    /// Fonctions permises après `=` (comme le calcul avancé d'Alfred).
    static let functions: [String: @Sendable (Double) -> Double] = [
        "sqrt": { $0.squareRoot() }, "abs": { Swift.abs($0) }, "round": { $0.rounded() },
        "floor": { $0.rounded(.down) }, "ceil": { $0.rounded(.up) }, "exp": { Foundation.exp($0) },
        "ln": { Foundation.log($0) }, "log": { Foundation.log10($0) }, "log2": { Foundation.log2($0) },
        "sin": { Foundation.sin($0) }, "cos": { Foundation.cos($0) }, "tan": { Foundation.tan($0) },
        "asin": { Foundation.asin($0) }, "acos": { Foundation.acos($0) }, "atan": { Foundation.atan($0) },
        // Session 105 : le reste du calcul avancé d'Alfred.
        "sinh": { Foundation.sinh($0) }, "cosh": { Foundation.cosh($0) }, "tanh": { Foundation.tanh($0) },
        "asinh": { Foundation.asinh($0) }, "acosh": { Foundation.acosh($0) }, "atanh": { Foundation.atanh($0) },
        "trunc": { $0.rounded(.towardZero) }, "rint": { $0.rounded(.toNearestOrEven) }, "near": { $0.rounded(.toNearestOrEven) },
        "dtor": { $0 * .pi / 180 }, "rtod": { $0 * 180 / .pi },
    ]
    static let constants: [String: Double] = ["pi": .pi, "e": M_E]

    /// Caractères d'un calcul en cours de frappe (FR-009 : Maj + chiffre y écrit le chiffre).
    static let typingCharacters = Set("0123456789 +-*/^%,.()=×÷")

    /// Calcul en cours de frappe : saisie vide, faite de caractères de calcul, ou calcul avancé
    /// commencé par `=` (fonctions et constantes en lettres, `=sqrt(2)`). O(n).
    static func isTyping(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).hasPrefix("=") || text.allSatisfy(typingCharacters.contains)
    }

    /// Calcul complet et fini, sinon nil (texte ordinaire, saisie incomplète, division par zéro). O(n).
    static func evaluate(_ raw: String, locale: Locale = .current) -> LauncherCalculation? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        let advanced = text.hasPrefix("=")
        let body = advanced ? String(text.dropFirst()) : text
        guard var parser = Parser(body, advanced: advanced) else { return nil }
        // Un nombre seul n'est pas un calcul : il faut un opérateur, ou le préfixe `=`.
        guard advanced || parser.hasOperator, let value = parser.parse(), value.isFinite else { return nil }
        return LauncherCalculation(expression: text, value: value, text: format(value, locale: locale))
    }

    static func format(_ value: Double, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.usesSignificantDigits = true
        formatter.maximumSignificantDigits = 12
        let clean = value == 0 ? 0 : value // -0 rendu 0
        return formatter.string(from: NSNumber(value: clean)) ?? String(clean)
    }

    /// Jetons puis grammaire : somme → produit → unaire → puissance (à droite) → primaire.
    private struct Parser {
        enum Token: Equatable { case number(Double), name(String), op(Character), open, close }

        private let tokens: [Token]
        private var index = 0

        var hasOperator: Bool {
            tokens.enumerated().contains { offset, token in
                // Un `-` en tête est un signe, pas une opération.
                if case .op = token { return offset > 0 }
                return false
            }
        }

        init?(_ text: String, advanced: Bool) {
            var tokens: [Token] = []
            var chars = Array(text)[...]
            while let c = chars.first {
                if c == " " { chars.removeFirst(); continue }
                if c.isNumber || c == "." || c == "," {
                    var digits = ""
                    var separators = 0
                    while let d = chars.first, d.isNumber || d == "." || d == "," {
                        if !d.isNumber { separators += 1; digits.append(".") } else { digits.append(d) }
                        chars.removeFirst()
                    }
                    guard separators <= 1, digits != ".", let value = Double(digits) else { return nil }
                    tokens.append(.number(value))
                } else if c.isLetter {
                    guard advanced else { return nil }
                    var name = ""
                    while let d = chars.first, d.isLetter || d.isNumber { name.append(d); chars.removeFirst() }
                    tokens.append(.name(name.lowercased()))
                } else if "+-*/^%".contains(c) || c == "×" || c == "÷" {
                    tokens.append(.op(c == "×" ? "*" : c == "÷" ? "/" : c))
                    chars.removeFirst()
                } else if c == "(" {
                    tokens.append(.open); chars.removeFirst()
                } else if c == ")" {
                    tokens.append(.close); chars.removeFirst()
                } else {
                    return nil
                }
            }
            guard !tokens.isEmpty else { return nil }
            self.tokens = tokens
        }

        mutating func parse() -> Double? {
            guard let value = sum(), index == tokens.count else { return nil }
            return value
        }

        private var current: Token? { index < tokens.count ? tokens[index] : nil }

        private mutating func sum() -> Double? {
            guard var value = product() else { return nil }
            while case .op(let op)? = current, op == "+" || op == "-" {
                index += 1
                guard let right = product() else { return nil }
                value = op == "+" ? value + right : value - right
            }
            return value
        }

        private mutating func product() -> Double? {
            guard var value = unary() else { return nil }
            while case .op(let op)? = current, op == "*" || op == "/" || op == "%" {
                index += 1
                guard let right = unary() else { return nil }
                switch op {
                case "*": value *= right
                case "/": value /= right
                default: value = value.truncatingRemainder(dividingBy: right)
                }
            }
            return value
        }

        /// Moins unaire plus faible que `^` : `-2^2` = -4.
        private mutating func unary() -> Double? {
            if case .op(let op)? = current, op == "-" || op == "+" {
                index += 1
                guard let value = unary() else { return nil }
                return op == "-" ? -value : value
            }
            return power()
        }

        private mutating func power() -> Double? {
            guard let base = primary() else { return nil }
            if case .op("^")? = current {
                index += 1
                guard let exponent = unary() else { return nil }
                return pow(base, exponent)
            }
            return base
        }

        private mutating func primary() -> Double? {
            switch current {
            case .number(let value)?:
                index += 1
                return value
            case .open?:
                index += 1
                guard let value = sum(), current == .close else { return nil }
                index += 1
                return value
            case .name(let name)?:
                index += 1
                if let constant = LauncherCalculator.constants[name] { return constant }
                guard let function = LauncherCalculator.functions[name], current == .open else { return nil }
                index += 1
                guard let argument = sum(), current == .close else { return nil }
                index += 1
                return function(argument)
            default:
                return nil
            }
        }
    }
}
