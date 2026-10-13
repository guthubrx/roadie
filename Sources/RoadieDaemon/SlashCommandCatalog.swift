import Foundation
import RoadieCore

/// Noms connus du contexte courant, fournis par le lanceur pour la complétion (SPEC-023).
public struct SlashContext: Equatable, Sendable {
    public var stageNames: [String]
    public var bookmarkNames: [String]

    public init(stageNames: [String] = [], bookmarkNames: [String] = []) {
        self.stageNames = stageNames
        self.bookmarkNames = bookmarkNames
    }
}

/// Lecture, écriture ou remise à zéro d'un réglage depuis la boîte (`/set`).
public enum SettingRequest: Equatable, Sendable {
    case read(String)
    case write(String, String)
    case reset(String)
    case listCategories
}

/// Résultat de l'analyse d'une commande : ce que le lanceur doit exécuter. Aucun effet de bord ici.
public enum SlashInvocation: Equatable, Sendable {
    /// `CLICommandRouter.run`, résultat court puis fermeture de la boîte.
    case router(argv: [String])
    /// Idem, mais le résultat s'affiche dans la boîte (`/doctor`).
    case routerInfo(argv: [String])
    /// Exécutée après la fermeture de la boîte (`/grid`, `/letters`, `/restart`).
    case routerDeferred(argv: [String])
    /// Le lanceur résout l'identifiant et le nom à partir de l'état des stages.
    case stageSwitchByName(String)
    case stageCreate(name: String?)
    case stageRename(String)
    case openSettings(category: SettingCategory?)
    case setting(SettingRequest)
}

/// Commande refusée : cause courte, forme attendue et commande la plus proche si elle existe.
public struct SlashError: Error, Equatable, Sendable {
    public var message: String
    public var usage: String?
    public var suggestion: String?

    public init(message: String, usage: String? = nil, suggestion: String? = nil) {
        self.message = message
        self.usage = usage
        self.suggestion = suggestion
    }
}

public struct SlashCommand: Equatable, Sendable {
    public var name: String
    public var aliases: [String]
    public var summary: String
    public var usage: String

    public init(name: String, aliases: [String] = [], summary: String, usage: String) {
        self.name = name
        self.aliases = aliases
        self.summary = summary
        self.usage = usage
    }
}

/// Catalogue des commandes de la boîte (contrat `contracts/slash-commands.md`). Logique pure :
/// `parse` ne touche à aucun état de Roadie, `suggestions` ne lit que le contexte reçu.
public enum SlashCommandCatalog {
    private static let directionUsage = "gauche|droite|haut|bas"

    /// Les 19 commandes du contrat, puis `/settings` et `/set`, dans l'ordre du contrat.
    public static let commands: [SlashCommand] = [
        SlashCommand(name: "move", summary: "Déplacer le focus dans une direction", usage: "/move \(directionUsage)"),
        SlashCommand(name: "swap", summary: "Échanger la fenêtre avec sa voisine", usage: "/swap \(directionUsage)"),
        SlashCommand(name: "resize", summary: "Redimensionner la fenêtre", usage: "/resize \(directionUsage)"),
        SlashCommand(name: "full", summary: "Plein écran natif", usage: "/full"),
        SlashCommand(name: "max", summary: "Agrandir la fenêtre", usage: "/max"),
        SlashCommand(
            name: "stage", aliases: ["s"], summary: "Changer de stage, en créer un, le renommer ou y envoyer la fenêtre",
            usage: "/stage N|nom|new [nom]|rename nom|send N"),
        SlashCommand(name: "screen", summary: "Passer à un autre écran", usage: "/screen \(directionUsage)|N"),
        SlashCommand(name: "send", summary: "Envoyer la fenêtre sur un écran", usage: "/send N"),
        SlashCommand(name: "desktop", aliases: ["d"], summary: "Passer à un autre bureau", usage: "/desktop N"),
        SlashCommand(name: "layout", summary: "Changer la méthode de tuilage", usage: "/layout bsp|spatial|master|float"),
        SlashCommand(name: "balance", summary: "Équilibrer les fenêtres", usage: "/balance"),
        SlashCommand(name: "split", summary: "Choisir le sens de coupe", usage: "/split h|v"),
        SlashCommand(name: "bm", aliases: ["b"], summary: "Aller à un bookmark ou en poser un", usage: "/bm nom|set nom"),
        SlashCommand(name: "grid", summary: "Grille de clic", usage: "/grid [fenêtre]"),
        SlashCommand(name: "letters", summary: "Mode lettres", usage: "/letters"),
        SlashCommand(name: "doctor", summary: "Diagnostic de Roadie", usage: "/doctor"),
        SlashCommand(name: "heal", summary: "Réparer le daemon", usage: "/heal"),
        SlashCommand(name: "reload", summary: "Recharger la configuration", usage: "/reload"),
        SlashCommand(name: "restart", summary: "Redémarrer le daemon", usage: "/restart"),
        SlashCommand(name: "settings", summary: "Ouvrir la fenêtre de réglages", usage: "/settings [catégorie]"),
        SlashCommand(name: "set", summary: "Lire, écrire ou rétablir un réglage", usage: "/set nom [valeur|défaut]"),
    ]

    // MARK: - Résolution de mots

    /// Identifiant sans accent ou libellé d'une catégorie, sans tenir compte de la casse ni des accents. O(k), k = 11.
    public static func resolveCategory(_ text: String) -> SettingCategory? {
        let needle = TargetHintService.normalized(text)
        return SettingCategory.allCases.first {
            TargetHintService.normalized($0.rawValue) == needle || TargetHintService.normalized($0.label) == needle
        }
    }

    /// `gauche|droite|haut|bas|left|right|up|down` vers `left|right|up|down`. O(1).
    public static func normalizeDirection(_ word: String) -> String? {
        switch TargetHintService.normalized(word) {
        case "gauche", "left": return "left"
        case "droite", "right": return "right"
        case "haut", "up": return "up"
        case "bas", "down": return "down"
        default: return nil
        }
    }

    /// Commande désignée par son nom ou un alias. O(c).
    private static func command(named word: String) -> SlashCommand? {
        let key = TargetHintService.normalized(word)
        return commands.first { $0.name == key || $0.aliases.contains(key) }
    }

    /// Entier ≥ 1, sinon nil.
    private static func positive(_ word: String) -> Int? {
        Int(word).flatMap { $0 >= 1 ? $0 : nil }
    }

    /// Découpe par espaces (plusieurs permises). Au plus `maxWords` mots ; le reste de la saisie, trimé,
    /// forme un dernier élément s'il n'est pas vide. O(l).
    private static func split(_ text: String, maxWords: Int = .max) -> [String] {
        var result: [String] = []
        var remainder = Substring(text)
        while result.count < maxWords {
            remainder = remainder.drop(while: \.isWhitespace)
            guard !remainder.isEmpty else { return result }
            let word = remainder.prefix { !$0.isWhitespace }
            result.append(String(word))
            remainder = remainder.dropFirst(word.count)
        }
        let tail = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { result.append(tail) }
        return result
    }

    // MARK: - Analyse

    /// Analyse la saisie (sans le `/` initial). O(l + c) - l longueur de la saisie, c nombre de commandes.
    public static func parse(_ input: String) -> Result<SlashInvocation, SlashError> {
        let words = split(input, maxWords: 1)
        guard let head = words.first else {
            return .failure(SlashError(message: "Saisissez une commande après « / »."))
        }
        guard let command = command(named: head) else { return .failure(unknown(head)) }
        return parseArguments(of: command, rest: words.count > 1 ? words[1] : "")
    }

    /// Commande inconnue : propose le nom le plus proche si la distance d'édition est d'au plus 2.
    private static func unknown(_ head: String) -> SlashError {
        let key = TargetHintService.normalized(head)
        let closest = commands
            .map { (name: $0.name, distance: RoadieConfigLoader.editDistance(key, $0.name)) }
            .filter { $0.distance <= 2 }
            .min { $0.distance < $1.distance }
        return SlashError(message: "Commande inconnue : /\(head)", suggestion: closest?.name)
    }

    private static func fail(_ command: SlashCommand, _ message: String) -> Result<SlashInvocation, SlashError> {
        .failure(SlashError(message: message, usage: command.usage))
    }

    private static func parseArguments(of command: SlashCommand, rest: String) -> Result<SlashInvocation, SlashError> {
        let args = split(rest)
        switch command.name {
        case "move": return direction(command, args) { .router(argv: ["move", $0]) }
        case "swap": return direction(command, args) { .router(argv: ["window", "swap", $0]) }
        case "resize": return direction(command, args) { .router(argv: ["resize", $0]) }
        case "full": return fixed(command, args, .router(argv: ["toggle", "native-fullscreen"]))
        case "max": return fixed(command, args, .router(argv: ["toggle", "maximize"]))
        case "stage": return parseStage(command, rest: rest)
        case "screen":
            guard args.count == 1 else { return fail(command, "Indiquez une direction ou un numéro d'écran.") }
            if let dir = normalizeDirection(args[0]) { return .success(.router(argv: ["display", "focus", dir])) }
            if let number = positive(args[0]) { return .success(.router(argv: ["display", "focus", String(number)])) }
            return fail(command, "Direction ou numéro d'écran invalide : \(args[0]).")
        case "send": return number(command, args, "un numéro d'écran") { .router(argv: ["window", "display", $0]) }
        case "desktop": return number(command, args, "un numéro de bureau") { .router(argv: ["desktop", "focus", $0]) }
        case "layout": return parseLayout(command, args)
        case "balance": return fixed(command, args, .router(argv: ["balance"]))
        case "split": return parseSplit(command, args)
        case "bm": return parseBookmark(command, rest: rest)
        case "grid": return parseGrid(command, args)
        case "letters":
            return fixed(command, args, .routerDeferred(argv: ["targets", "interactive", "--source", "all", "--include-app-targets"]))
        case "doctor": return fixed(command, args, .routerInfo(argv: ["doctor"]))
        case "heal": return fixed(command, args, .router(argv: ["daemon", "heal"]))
        case "reload": return fixed(command, args, .router(argv: ["config", "reload"]))
        case "restart": return fixed(command, args, .routerDeferred(argv: ["daemon", "restart"]))
        case "settings": return parseSettings(command, rest: rest)
        default: return parseSet(rest: rest) // "set"
        }
    }

    /// Commande sans argument.
    private static func fixed(
        _ command: SlashCommand, _ args: [String], _ invocation: SlashInvocation
    ) -> Result<SlashInvocation, SlashError> {
        args.isEmpty ? .success(invocation) : fail(command, "Cette commande n'accepte pas d'argument.")
    }

    private static func direction(
        _ command: SlashCommand, _ args: [String], _ build: (String) -> SlashInvocation
    ) -> Result<SlashInvocation, SlashError> {
        guard args.count == 1 else { return fail(command, "Indiquez une direction.") }
        guard let dir = normalizeDirection(args[0]) else { return fail(command, "Direction invalide : \(args[0]).") }
        return .success(build(dir))
    }

    private static func number(
        _ command: SlashCommand, _ args: [String], _ what: String, _ build: (String) -> SlashInvocation
    ) -> Result<SlashInvocation, SlashError> {
        guard args.count == 1, let value = positive(args[0]) else {
            return fail(command, "Indiquez \(what) (entier à partir de 1).")
        }
        return .success(build(String(value)))
    }

    private static func parseStage(_ command: SlashCommand, rest: String) -> Result<SlashInvocation, SlashError> {
        let parts = split(rest, maxWords: 1)
        guard let first = parts.first else { return fail(command, "Indiquez un numéro, un nom ou une action.") }
        let tail = parts.count > 1 ? parts[1] : nil
        switch TargetHintService.normalized(first) {
        case "new":
            return .success(.stageCreate(name: tail))
        case "rename":
            guard let tail else { return fail(command, "Indiquez le nouveau nom du stage.") }
            return .success(.stageRename(tail))
        case "send":
            guard let tail, let id = positive(tail) else { return fail(command, "Indiquez le numéro du stage cible.") }
            return .success(.router(argv: ["stage", "assign", String(id)]))
        default:
            // Un mot numérique est toujours un identifiant ; sinon toute la saisie est le nom du stage.
            guard Int(first) != nil else { return .success(.stageSwitchByName(rest.trimmingCharacters(in: .whitespacesAndNewlines))) }
            guard tail == nil, let id = positive(first) else { return fail(command, "Numéro de stage invalide : \(rest).") }
            return .success(.router(argv: ["stage", "switch", String(id)]))
        }
    }

    private static func parseLayout(_ command: SlashCommand, _ args: [String]) -> Result<SlashInvocation, SlashError> {
        let modes = ["bsp": "bsp", "spatial": "spatialBsp", "master": "masterStack", "float": "float"]
        guard args.count == 1 else { return fail(command, "Indiquez une méthode de tuilage.") }
        guard let mode = modes[TargetHintService.normalized(args[0])] else {
            return fail(command, "Méthode invalide : \(args[0]). Valeurs permises : bsp, spatial, master, float.")
        }
        return .success(.router(argv: ["mode", mode]))
    }

    private static func parseSplit(_ command: SlashCommand, _ args: [String]) -> Result<SlashInvocation, SlashError> {
        guard args.count == 1 else { return fail(command, "Indiquez h (horizontal) ou v (vertical).") }
        switch TargetHintService.normalized(args[0]) {
        case "h", "horizontal": return .success(.router(argv: ["layout", "split", "horizontal"]))
        case "v", "vertical": return .success(.router(argv: ["layout", "split", "vertical"]))
        default: return fail(command, "Sens invalide : \(args[0]). Valeurs permises : h, v.")
        }
    }

    private static func parseBookmark(_ command: SlashCommand, rest: String) -> Result<SlashInvocation, SlashError> {
        let parts = split(rest, maxWords: 1)
        guard let first = parts.first else { return fail(command, "Indiquez le nom du bookmark.") }
        guard TargetHintService.normalized(first) == "set" else {
            return .success(.router(argv: ["bookmark", "jump", rest.trimmingCharacters(in: .whitespacesAndNewlines)]))
        }
        guard parts.count > 1 else { return fail(command, "Indiquez le nom du bookmark à poser.") }
        return .success(.router(argv: ["bookmark", "set", parts[1]]))
    }

    private static func parseGrid(_ command: SlashCommand, _ args: [String]) -> Result<SlashInvocation, SlashError> {
        let scope: String
        switch args.map(TargetHintService.normalized) {
        case []: scope = "display"
        case ["fenetre"], ["window"]: scope = "focused_window"
        default: return fail(command, "Argument invalide. Valeur permise : fenêtre.")
        }
        return .success(.routerDeferred(argv: ["grid", "interactive", "--scope", scope]))
    }

    private static func parseSettings(_ command: SlashCommand, rest: String) -> Result<SlashInvocation, SlashError> {
        let text = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .success(.openSettings(category: nil)) }
        guard let category = resolveCategory(text) else {
            let valid = SettingCategory.allCases.map(\.rawValue).joined(separator: ", ")
            return fail(command, "Catégorie inconnue : \(text). Catégories valides : \(valid).")
        }
        return .success(.openSettings(category: category))
    }

    private static func parseSet(rest: String) -> Result<SlashInvocation, SlashError> {
        let parts = split(rest, maxWords: 1)
        guard let name = parts.first else { return .success(.setting(.listCategories)) }
        guard parts.count > 1 else { return .success(.setting(.read(name))) }
        let value = parts[1]
        switch TargetHintService.normalized(value) {
        case "defaut", "default": return .success(.setting(.reset(name)))
        default: return .success(.setting(.write(name, value)))
        }
    }

    // MARK: - Suggestions

    /// Suggestion et clés de recherche normalisées : le préfixe d'une clé classe en premier, puis la
    /// présence du mot dans l'ensemble des clés et du texte annexe.
    private struct Candidate: Sendable {
        let suggestion: SlashSuggestion
        let keys: [String]
        let haystack: String

        init(_ suggestion: SlashSuggestion, keys: [String], extra: String = "") {
            self.suggestion = suggestion
            self.keys = keys.map(TargetHintService.normalized)
            self.haystack = TargetHintService.normalized((keys + [extra]).joined(separator: " "))
        }
    }

    private static let commandCandidates: [Candidate] = commands.map {
        Candidate(
            SlashSuggestion(text: "\($0.name) ", detail: $0.summary, kind: .command),
            keys: [$0.name] + $0.aliases)
    }

    /// Réglages modifiables : l'identifiant classe, l'identifiant et le libellé servent à la recherche.
    private static let settingCandidates: [Candidate] = SettingsCatalog.all
        .filter { $0.readOnlyReason == nil }
        .map { Candidate(SlashSuggestion(text: $0.id, detail: $0.label, kind: .setting), keys: [$0.id], extra: $0.label) }

    /// Candidats dont une clé commence par le mot, puis ceux qui le contiennent. Mot vide : tous. O(n * m).
    private static func rank(_ candidates: [Candidate], word: String) -> [SlashSuggestion] {
        guard !word.isEmpty else { return candidates.map(\.suggestion) }
        let starts = candidates.filter { $0.keys.contains { $0.hasPrefix(word) } }
        let contains = candidates.filter { candidate in
            !candidate.keys.contains { $0.hasPrefix(word) } && candidate.haystack.contains(word)
        }
        return (starts + contains).map(\.suggestion)
    }

    private static func arguments(_ values: [(String, String)]) -> [Candidate] {
        values.map { Candidate(SlashSuggestion(text: $0.0, detail: $0.1, kind: .argument), keys: [$0.0]) }
    }

    private static let directionCandidates = arguments([
        ("gauche", "left"), ("droite", "right"), ("haut", "up"), ("bas", "down"),
        ("left", "gauche"), ("right", "droite"), ("up", "haut"), ("down", "bas"),
    ])

    /// Suggestions pour la saisie (sans le `/`). Avant le premier espace : commandes, O(c). Ensuite : valeurs
    /// du premier argument seulement ; réglages en O(n * m), n <= 179 réglages, m longueur du texte comparé.
    public static func suggestions(for input: String, context: SlashContext) -> [SlashSuggestion] {
        guard let space = input.firstIndex(where: \.isWhitespace) else {
            return rank(commandCandidates, word: TargetHintService.normalized(input))
        }
        guard let command = command(named: String(input[..<space])) else { return [] }
        let afterHead = input[input.index(after: space)...]
        // Mot courant = après la dernière espace ; un mot déjà terminé avant lui ferme la complétion.
        var current = afterHead
        if let last = afterHead.lastIndex(where: \.isWhitespace) {
            guard split(String(afterHead[...last])).isEmpty else { return [] }
            current = afterHead[afterHead.index(after: last)...]
        }
        let word = TargetHintService.normalized(String(current))

        switch command.name {
        case "move", "swap", "resize", "screen":
            return rank(directionCandidates, word: word)
        case "layout":
            return rank(arguments([("bsp", "Partition binaire"), ("spatial", "Partition spatiale"),
                                   ("master", "Maître et pile"), ("float", "Flottant")]), word: word)
        case "split":
            return rank(arguments([("h", "horizontal"), ("v", "vertical")]), word: word)
        case "stage":
            let names = context.stageNames.map { Candidate(SlashSuggestion(text: $0, detail: "stage", kind: .argument), keys: [$0]) }
            let actions = arguments([("new", "Nouveau stage"), ("rename", "Renommer le stage courant"),
                                     ("send", "Envoyer la fenêtre vers un stage")])
            return rank(names + actions, word: word)
        case "bm":
            let names = context.bookmarkNames.map { Candidate(SlashSuggestion(text: $0, detail: "bookmark", kind: .argument), keys: [$0]) }
            return rank(names + arguments([("set", "Poser un bookmark")]), word: word)
        case "set":
            return rank(settingCandidates, word: word)
        case "settings":
            let categories = SettingCategory.allCases.map {
                Candidate(SlashSuggestion(text: $0.rawValue, detail: $0.label, kind: .argument), keys: [$0.rawValue], extra: $0.label)
            }
            return rank(categories, word: word)
        default:
            return []
        }
    }
}
