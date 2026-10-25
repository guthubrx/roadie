import Foundation

/// Ligne proposée sous la boîte de commandes (SPEC-023).
public struct SlashSuggestion: Equatable, Sendable {
    /// `header` : titre de section du lanceur, non choisissable ; `result` : ligne du lanceur (SPEC-073).
    public enum Kind: Equatable, Sendable { case command, argument, setting, header, result }
    /// Icône d'une ligne du lanceur : celle d'un fichier (application) ou un symbole système.
    public enum Icon: Hashable, Sendable { case file(String), symbol(String) }

    /// Texte à insérer à la place du mot courant (`stage `, `target_grid.rows`).
    public var text: String
    /// Description courte affichée à côté du texte.
    public var detail: String
    public var kind: Kind
    public var icon: Icon?

    public init(text: String, detail: String = "", kind: Kind, icon: Icon? = nil) {
        self.text = text
        self.detail = detail
        self.kind = kind
        self.icon = icon
    }
}

/// Message affiché dans la boîte jusqu'à la frappe suivante.
public enum SlashMessage: Equatable, Sendable {
    case info([String])
    case error(String, usage: String?)
}

/// Mode commande de la boîte (SPEC-023) : logique pure, sans écran, à la manière de `TargetSearchModel`.
/// La saisie ne contient pas le `/` initial. Le fournisseur de suggestions est injecté : le modèle
/// ne connaît ni le catalogue des commandes ni l'état des stages.
public struct SlashCommandModel: Equatable, Sendable {
    /// Taille maximale de l'historique : la plus ancienne commande est perdue au-delà.
    public static let maxHistory = CommandHistoryStore.maxEntries

    /// Texte saisi, sans le `/` initial.
    public private(set) var input: String
    /// Suggestions pour `input`, non tronquées : l'affichage choisit combien en montrer.
    public private(set) var suggestions: [SlashSuggestion]
    public private(set) var selected: Int?
    /// Ancienne vers récente ; doublon consécutif ignoré.
    public private(set) var history: [String]
    /// Position dans `history` pendant le parcours (nil hors parcours).
    public private(set) var historyCursor: Int?
    public private(set) var message: SlashMessage?
    /// Faux dès que le `/` initial est effacé : la main revient à la recherche.
    public private(set) var isActive = true

    /// Début de saisie (tout sauf le mot courant) figé pendant un cycle de Tab. Sans lui, un mot
    /// complété qui finit par une espace (`stage `) deviendrait un nouveau mot vide au Tab suivant.
    private var completionPrefix: String?
    /// Une navigation explicite doit être acceptée par Tab, même si elle revient au choix inséré.
    private var completionCanAdvance = false
    private let suggestionProvider: @Sendable (String) -> [SlashSuggestion]

    public init(
        input: String = "",
        history: [String] = [],
        suggestionProvider: @escaping @Sendable (String) -> [SlashSuggestion]
    ) {
        self.input = input
        self.history = Array(history.suffix(Self.maxHistory))
        self.suggestionProvider = suggestionProvider
        suggestions = suggestionProvider(input)
    }

    /// Le fournisseur de suggestions (une fermeture) n'entre pas dans la comparaison.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.input == rhs.input && lhs.suggestions == rhs.suggestions && lhs.selected == rhs.selected
            && lhs.history == rhs.history && lhs.historyCursor == rhs.historyCursor
            && lhs.message == rhs.message && lhs.isActive == rhs.isActive
            && lhs.completionPrefix == rhs.completionPrefix
            && lhs.completionCanAdvance == rhs.completionCanAdvance
    }

    /// Complexité : O(c) par frappe, c = nombre de suggestions rendues par le fournisseur.
    public mutating func type(_ text: String) {
        input += text
        inputEdited()
    }

    /// Le champ natif peut remplacer une sélection ou éditer au milieu de la ligne. O(c + l).
    public mutating func replaceInput(_ text: String) {
        guard input != text else { return }
        input = text
        inputEdited()
    }

    public mutating func selectSuggestion(at index: Int) {
        guard suggestions.indices.contains(index) else { return }
        selected = index
        completionCanAdvance = false
    }

    /// Accepter le choix explicite, sans avancer dans le cycle de Tab. O(c + l).
    public mutating func acceptSelectedSuggestion() {
        guard selected != nil else { return }
        completionCanAdvance = false
        complete()
    }

    /// Effacer quand la saisie est vide retire le `/` initial : `isActive` devient faux.
    public mutating func deleteBackward() {
        message = nil
        guard !input.isEmpty else {
            isActive = false
            return
        }
        input.removeLast()
        inputEdited()
    }

    /// Tab accepte d'abord la sélection courante, ou la première proposition. Les Tab suivants
    /// parcourent les alternatives. Une seule suggestion remplace le mot et recharge les suivantes.
    /// Complexité : O(c + l), l = longueur de la saisie.
    public mutating func complete() {
        guard !suggestions.isEmpty else { return }
        let prefix = completionPrefix ?? currentPrefix
        if suggestions.count == 1 {
            input = prefix + suggestions[0].text
            inputEdited()
            return
        }
        completionPrefix = prefix
        if completionCanAdvance { move(by: 1) }
        else if selected == nil { selected = 0 }
        if let selected { input = prefix + suggestions[selected].text }
        completionCanAdvance = true
    }

    /// Ctrl-N : déplace la surbrillance sans toucher à la saisie.
    public mutating func nextSuggestion() {
        completionCanAdvance = false
        move(by: 1)
    }

    /// Ctrl-P et Maj-Tab.
    public mutating func previousSuggestion() {
        completionCanAdvance = false
        move(by: -1)
    }

    /// Flèche haut : commande précédente (la plus récente d'abord). Reste sur la plus ancienne.
    public mutating func historyUp() {
        message = nil
        guard !history.isEmpty else { return }
        showHistory(at: historyCursor.map { max(0, $0 - 1) } ?? history.count - 1)
    }

    /// Flèche bas : commande suivante ; après la plus récente, la saisie redevient vide.
    public mutating func historyDown() {
        message = nil
        guard let cursor = historyCursor else { return }
        showHistory(at: cursor + 1 < history.count ? cursor + 1 : nil)
    }

    public mutating func setMessage(_ message: SlashMessage?) { self.message = message }

    /// Retour : renvoie la commande sans `/` ni espace de bord et l'ajoute à l'historique (sauf si vide ou
    /// identique à la dernière). Le message reste affiché : l'exécuteur le remplace par le résultat.
    /// Complexité : O(l + h), h = taille de l'historique (50 au plus).
    public mutating func submit() -> String {
        let command = input.trimmingCharacters(in: .whitespacesAndNewlines)
        historyCursor = nil
        guard !command.isEmpty else { return command }
        if history.last != command { history.append(command) }
        history = Array(history.suffix(Self.maxHistory))
        return command
    }

    /// Saisie sans son dernier mot : le mot courant est le dernier, ou vide après une espace.
    private var currentPrefix: String {
        guard let space = input.lastIndex(of: " ") else { return "" }
        return String(input[...space])
    }

    /// Toute modification de la saisie efface le message, le cycle de Tab et le parcours d'historique.
    private mutating func inputEdited() {
        message = nil
        historyCursor = nil
        completionPrefix = nil
        completionCanAdvance = false
        selected = nil
        suggestions = suggestionProvider(input)
    }

    private mutating func move(by delta: Int) {
        guard !suggestions.isEmpty else { return }
        let count = suggestions.count
        selected = selected.map { ($0 + delta + count) % count } ?? (delta > 0 ? 0 : count - 1)
    }

    /// `index` nil : retour à la saisie vide, hors parcours.
    private mutating func showHistory(at index: Int?) {
        input = index.map { history[$0] } ?? ""
        inputEdited()
        historyCursor = index
    }
}
