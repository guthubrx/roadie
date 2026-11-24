import Foundation
import TOMLKit

/// Recherche par mot-clé de la barre (SPEC-090) : `yt chat` cherche « chat » sur YouTube.
public struct WebSearch: Equatable, Codable, Sendable {
    public var keyword: String
    public var title: String
    /// Adresse avec `{query}`.
    public var url: String

    public init(keyword: String, title: String, url: String) {
        self.keyword = keyword
        self.title = title
        self.url = url
    }

    /// Recherches proposées quand `web_searches` est absent.
    public static let defaults = [
        WebSearch(keyword: "g", title: "Google", url: "https://www.google.com/search?q={query}"),
        WebSearch(keyword: "yt", title: "YouTube", url: "https://www.youtube.com/results?search_query={query}"),
        WebSearch(keyword: "wp", title: tr("Wikipédia", "Wikipedia"), url: "https://fr.wikipedia.org/w/index.php?search={query}"),
        WebSearch(keyword: "ddg", title: "DuckDuckGo", url: "https://duckduckgo.com/?q={query}"),
        WebSearch(keyword: "maps", title: tr("Plans", "Maps"), url: "maps://?q={query}"),
        // Session 119 : d'autres recherches intégrées d'Alfred.
        WebSearch(keyword: "gi", title: "Google Images", url: "https://www.google.com/search?tbm=isch&q={query}"),
        WebSearch(keyword: "gmaps", title: "Google Maps", url: "https://www.google.com/maps/search/{query}"),
        WebSearch(keyword: "tr", title: tr("Google Traduction", "Google Translate"), url: "https://translate.google.com/?sl=auto&text={query}"),
        WebSearch(keyword: "wpen", title: tr("Wikipedia (anglais)", "Wikipedia (English)"), url: "https://en.wikipedia.org/w/index.php?search={query}"),
        WebSearch(keyword: "amazon", title: "Amazon", url: "https://www.amazon.fr/s?k={query}"),
        WebSearch(keyword: "imdb", title: "IMDb", url: "https://www.imdb.com/find?q={query}"),
        WebSearch(keyword: "ebay", title: "eBay", url: "https://www.ebay.fr/sch/i.html?_nkw={query}"),
        WebSearch(keyword: "bing", title: "Bing", url: "https://www.bing.com/search?q={query}"),
        WebSearch(keyword: "linkedin", title: "LinkedIn", url: "https://www.linkedin.com/search/results/all/?keywords={query}"),
        WebSearch(keyword: "x", title: "X", url: "https://x.com/search?q={query}"),
        WebSearch(keyword: "gh", title: "GitHub", url: "https://github.com/search?q={query}"),
        WebSearch(keyword: "wa", title: "Wolfram|Alpha", url: "https://www.wolframalpha.com/input?i={query}"),
    ]
}

/// Actions de la barre qui ont une touche réglable (session 108). L'ordre est celui des paramètres.
public enum LauncherBarKeys {
    public struct Action: Sendable, Equatable {
        public let id: String
        public let label: String
        public let help: String
        public let defaultKey: String
        public var configKey: String { id + "_key" }
    }

    public static let actions: [Action] = [
        Action(id: "large_type", label: tr("Grand texte", "Large type"), help: tr("Montre la ligne choisie en très grands caractères, comme ⌘L dans Alfred.", "Shows the chosen row in very large type, like ⌘L in Alfred."), defaultKey: "command+l"),
        Action(id: "copy", label: tr("Copier la ligne", "Copy row"), help: tr("Copie le chemin, l'adresse ou le titre de la ligne choisie, quand aucun texte n'est sélectionné dans la saisie.", "Copies the path, address or title of the chosen row, when no text is selected in the field."), defaultKey: "command+c"),
        Action(id: "preview", label: tr("Aperçu", "Quick Look"), help: tr("Ouvre l'aperçu (Quick Look) du fichier choisi.", "Opens Quick Look for the chosen file."), defaultKey: "command+y"),
        Action(id: "save_action", label: tr("Garder l'action", "Save action"), help: tr("Enregistre l'action choisie sous une abréviation.", "Saves the chosen action under an abbreviation."), defaultKey: "command+s"),
        Action(id: "show_rules", label: tr("Règle proposée", "Suggested rule"), help: tr("Montre la règle proposée pour la fenêtre choisie.", "Shows the suggested rule for the chosen window."), defaultKey: "command+r"),
        Action(id: "close", label: tr("Fermer la barre", "Close bar"), help: tr("Ferme la barre.", "Closes the bar."), defaultKey: "command+w"),
        Action(id: "close_all", label: tr("Tout fermer", "Close all"), help: tr("Ferme la barre d'un coup, même dans un dossier ou un verbe.", "Closes the bar at once, even inside a folder or a verb."), defaultKey: "command+escape"),
        Action(id: "settings", label: tr("Paramètres de Roadie", "Roadie Settings"), help: tr("Ferme la barre et ouvre les Paramètres de Roadie, comme ⌘, dans Alfred.", "Closes the bar and opens Roadie Settings, like ⌘, in Alfred."), defaultKey: "command+,"),
        Action(id: "select_toggle", label: tr("Ajouter ou retirer de la sélection", "Add to or remove from selection"), help: tr("Sélection multiple : ajoute la ligne choisie, ou la retire.", "Multiple selection: adds the chosen row, or removes it."), defaultKey: "alt+up"),
        Action(id: "select_add_next", label: tr("Ajouter et passer à la suivante", "Add and go to next"), help: tr("Sélection multiple : ajoute la ligne choisie, puis descend d'une ligne.", "Multiple selection: adds the chosen row, then moves down one row."), defaultKey: "alt+down"),
        Action(id: "select_remove_last", label: tr("Retirer la dernière", "Remove last"), help: tr("Sélection multiple : retire le dernier élément ajouté.", "Multiple selection: removes the last item added."), defaultKey: "alt+left"),
        Action(id: "selection_verbs", label: tr("Actions de la sélection", "Selection actions"), help: tr("Sélection multiple : montre les actions qui s'appliquent à toute la sélection.", "Multiple selection: shows the actions that apply to the whole selection."), defaultKey: "alt+right"),
        Action(id: "select_clear", label: tr("Vider la sélection", "Clear selection"), help: tr("Sélection multiple : retire tous les éléments.", "Multiple selection: removes all items."), defaultKey: "alt+backspace"),
    ]

    /// Défauts, puis valeurs données, normalisées ; une action inconnue est ignorée. O(a).
    public static func resolved(_ given: [String: String]) -> [String: String] {
        var keys: [String: String] = [:]
        for action in actions {
            keys[action.id] = TargetGridConfig.normalizedKey(given[action.id] ?? action.defaultKey, fallback: "")
        }
        return keys
    }
}

/// Raccourci global géré par Roadie pour une commande `roadie …` (session 108), table `[[shortcuts]]`.
/// `bttUUID` : raccourci BTT d'origine, désactivé tant que Roadie prend la main.
public struct CommandShortcut: Equatable, Codable, Sendable {
    public var keys: String
    public var command: String
    public var enabled: Bool
    public var bttUUID: String

    public init(keys: String, command: String, enabled: Bool = true, bttUUID: String = "") {
        self.keys = TargetGridConfig.normalizedKey(keys, fallback: "")
        self.command = command.trimmingCharacters(in: .whitespaces)
        self.enabled = enabled
        self.bttUUID = bttUUID
    }

    /// Arguments de la commande, sans le mot `roadie` du début ; guillemets simples et doubles respectés. O(n).
    public var arguments: [String] {
        var result: [String] = [], current = "", quote: Character?
        for character in command {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character == " " {
                if !current.isEmpty { result.append(current); current = "" }
            } else { current.append(character) }
        }
        if !current.isEmpty { result.append(current) }
        if result.first == "roadie" || result.first?.hasSuffix("/roadie") == true { result.removeFirst() }
        return result
    }

    enum CodingKeys: String, CodingKey {
        case keys, command, enabled
        case bttUUID = "btt_uuid"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(keys: try c.decodeIfPresent(String.self, forKey: .keys) ?? "",
                  command: try c.decodeIfPresent(String.self, forKey: .command) ?? "",
                  enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
                  bttUUID: try c.decodeIfPresent(String.self, forKey: .bttUUID) ?? "")
    }
}

public struct TargetModeConfig: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var pickerEnabled: Bool
    public var overlayEnabled: Bool
    public var overlayLabelsOnly: Bool
    public var overlayDurationSeconds: Double
    public var appMouseActionsEnabled: Bool
    public var scrollModeEnabled: Bool
    /// Raccourci global du mode recherche (SPEC-021), forme normalisée `command+control+alt+f` ;
    /// vide = désactivé. Défaut : la hyper key (Cmd+Option+Ctrl) + F, comme le conseille Homerow.
    public var searchHotkey: String
    /// Raccourci qui ouvre la barre aux verbes de la fenêtre active (SPEC-075) ; vide = désactivé.
    /// Défaut : hyper key + Maj + F (Capslock + Maj + F).
    public var actionsHotkey: String
    /// Raccourci de la recherche à l'écran, sans la liste du lanceur (session 133) ; vide = désactivé.
    public var screenSearchHotkey: String
    /// Le lanceur lit aussi les éléments à l'écran (section « À l'écran », SPEC-073) ; faux : seulement
    /// applications, fenêtres, stages et fichiers, la recherche à l'écran ayant son raccourci (session 134).
    public var launcherOnScreen: Bool
    /// Recherche web de ⌃ Retour (SPEC-075) ; `{query}` reçoit le texte tapé, encodé.
    public var webSearchURL: String
    /// Modificateur des raccourcis 1 à 9 du lanceur (SPEC-085) : `command`, `shift`, `alt` ou `control`.
    /// Une autre valeur revient à `command`.
    public var pickModifier: String
    /// Effet de ⌘, ⌥ et ⌃ + Retour dans la barre (session 131) : `new-stage`, `here`, `send`, `web`, `copy`, `reveal`,
    /// `quicklook`, `verbs` ou `none`.
    public var returnCommand: String
    public var returnOption: String
    public var returnControl: String
    /// Apparence des fenêtres de workflow (Texte, Image, PDF) et du navigateur SF Symbols (session 131, styles d'Alfred 6) :
    /// `system`, `theme`, `glassy-dark`, `flat-dark` ou `glassy-light`.
    public var workflowViewStyle: String
    /// Workflows dans la barre (SPEC-088) ; `alfredWorkflows` : lire aussi ceux installés dans Alfred.
    public var workflowsEnabled: Bool
    public var alfredWorkflows: Bool
    /// Recherches par mot-clé de la barre (SPEC-090) ; nil = défauts (`WebSearch.defaults`), vide = aucune.
    public var webSearches: [WebSearch]?
    /// Mots-clés de `webSearches` proposés en repli, après la recherche de `web_search_url`.
    public var fallbackSearches: [String]
    /// Barre vide (session 096) : « Souvent ici » et « Recherches récentes », activation et nombre de lignes.
    /// Le décodage ramène le nombre dans 1…10 et 1…20 (l'historique garde 20 saisies).
    public var idleFrequentEnabled: Bool
    public var idleFrequentCount: Int
    /// Fautes de frappe rattrapées au plus, 0 à 2 (session 134) : 0 coupe la fonction.
    public var typoMaxErrors: Int
    public var idleRecentSearchesEnabled: Bool
    public var idleRecentSearchesCount: Int
    /// Touche qui fait passer les résultats de la liste à la grille puis aux grandes tuiles (session 099) ;
    /// vide : désactivée.
    public var viewCycleHotkey: String
    /// Taille de police des étiquettes en points (SPEC-023). Le décodage ramène toute valeur dans 8…48 (clamp dans l'init) : aucune validation hors plage n'est nécessaire.
    public var labelFontSize: Double
    public var searchLabelFontSize: Double
    public var searchTextFontSize: Double
    public var commandTextFontSize: Double
    public var searchFontFamily: String
    public var commandFontFamily: String
    /// Thème de la barre (session 101) : identifiant d'un thème fourni (`roadie`, `alfred`, `alfred-dark`…)
    /// ou nom d'un fichier `.alfredappearance` importé. `themeDark` : thème quand macOS est en mode sombre ;
    /// vide = `theme`.
    public var theme: String
    public var themeDark: String
    /// Nombre de résultats montrés (session 101) ; 0 = autant que la place, sinon 3…20.
    public var visibleResults: Int
    /// Écran de la barre (session 102) : `mouse` (écran du pointeur), `active` (écran de la fenêtre
    /// active) ou `main` (écran principal). Une autre valeur revient à `mouse`.
    public var barScreen: String
    /// Place par défaut de la barre (session 102) : `bottom`, `center` ou `top`.
    public var barPosition: String
    /// La barre déplacée à la souris garde sa place d'une ouverture à l'autre (session 102).
    public var barSavePosition: Bool
    /// Terminal qui lance une commande tapée après `>` (session 103) : `terminal`, `iterm`, `ghostty`,
    /// `warp`, `kitty`, `wezterm` ou `alacritty`.
    public var terminalApp: String
    /// Signets des navigateurs dans la barre (session 104) et navigateurs lus (`firefox`, `safari`, `chrome`,
    /// `brave`, `edge`, `arc`).
    public var bookmarksEnabled: Bool
    public var bookmarkBrowsers: [String]
    /// Dossiers d'applications ajoutés à la portée par défaut (session 105), `~` accepté.
    public var appSearchPaths: [String]
    /// Classement appris des résultats (session 105) ; faux : ordre sans apprentissage, rien n'est enregistré.
    public var learningEnabled: Bool
    /// Ordre des éléments d'un chemin tapé (session 105) : `name`, `modified` ou `created` ; dossiers en tête.
    public var pathSort: String
    /// « Tout quitter » demande une confirmation (session 105).
    public var confirmQuitAll: Bool
    /// Retour sur un calcul ouvre aussi Calculette, en plus de copier le résultat (session 110).
    public var calcOpensCalculator: Bool
    /// Les verbes les plus choisis pour un type d'objet passent en tête (session 111).
    public var learnVerbOrder: Bool
    /// Mots-clés de la recherche dans le contenu et par étiquette Finder (session 113) ; vide : désactivé.
    public var contentSearchKeyword: String
    public var tagSearchKeyword: String
    /// Historique des navigateurs dans la barre (session 114) : jours couverts, 0 désactivé, au plus 365.
    public var webHistoryDays: Int
    /// Paramètres de Roadie et panneaux des Réglages Système dans la barre (session 115).
    public var settingsInSearch: Bool
    /// Session 119 : mots-clés `open` et `find`, types de fichiers ajoutés (UTI), dossiers écartés, séparateur
    /// décimal du calcul (`system`, `point`, `comma`) et groupement des milliers, barre de défilement.
    public var openKeyword: String
    public var findKeyword: String
    public var fileTypes: [String]
    public var fileExcludedFolders: [String]
    public var calcDecimal: String
    public var calcGrouping: Bool
    public var showScrollbar: Bool
    /// Touches de la barre (session 108), par action de `LauncherBarKeys.actions` ; forme normalisée,
    /// vide : touche désactivée. Clés TOML `<action>_key`.
    public var barKeys: [String: String]
    /// Touches de la barre qui passent avant BetterTouchTool (session 108) : tant que la barre est ouverte,
    /// Roadie met en pause les raccourcis BTT de ces combinaisons, puis les réactive.
    public var bttPauseKeys: [String]

    public static let defaultSearchHotkey = "command+control+alt+f"
    public static let defaultActionsHotkey = "command+control+alt+shift+f"
    public static let defaultWebSearchURL = "https://www.google.com/search?q={query}"
    public static let pickModifiers = ["command", "shift", "alt", "control"]
    public static let returnEffects = ["new-stage", "here", "send", "web", "copy", "reveal", "quicklook", "verbs", "none"]
    public static let workflowViewStyles = ["system", "theme", "glassy-dark", "flat-dark", "glassy-light"]
    public static let barScreens = ["mouse", "active", "main"]
    public static let barPositions = ["bottom", "center", "top"]
    /// Séparateur décimal du résultat d'un calcul (session 119) : réglages de macOS, point ou virgule.
    public static let calcDecimals = ["system", "point", "comma"]
    public static let terminalApps = ["terminal", "iterm", "ghostty", "warp", "kitty", "wezterm", "alacritty"]
    public static let bookmarkBrowserIDs = ["firefox", "safari", "chrome", "brave", "edge", "arc"]
    public static let pathSorts = ["name", "modified", "created"]

    public init(
        enabled: Bool = true,
        pickerEnabled: Bool = true,
        overlayEnabled: Bool = false,
        overlayLabelsOnly: Bool = true,
        overlayDurationSeconds: Double = 3,
        appMouseActionsEnabled: Bool = false,
        scrollModeEnabled: Bool = false,
        searchHotkey: String = TargetModeConfig.defaultSearchHotkey,
        actionsHotkey: String = TargetModeConfig.defaultActionsHotkey,
        screenSearchHotkey: String = "",
        launcherOnScreen: Bool = true,
        webSearchURL: String = TargetModeConfig.defaultWebSearchURL,
        pickModifier: String = "command",
        returnCommand: String = "new-stage",
        returnOption: String = "here",
        returnControl: String = "web",
        workflowViewStyle: String = "system",
        workflowsEnabled: Bool = true,
        alfredWorkflows: Bool = true,
        webSearches: [WebSearch]? = nil,
        fallbackSearches: [String] = [],
        idleFrequentEnabled: Bool = true,
        idleFrequentCount: Int = 3,
        typoMaxErrors: Int = 2,
        idleRecentSearchesEnabled: Bool = true,
        idleRecentSearchesCount: Int = 3,
        viewCycleHotkey: String = "command+g",
        labelFontSize: Double = 13,
        searchLabelFontSize: Double = 13,
        searchTextFontSize: Double = 15,
        commandTextFontSize: Double = 13,
        searchFontFamily: String = "system",
        commandFontFamily: String = "system",
        theme: String = "roadie",
        themeDark: String = "",
        visibleResults: Int = 0,
        barScreen: String = "mouse",
        barPosition: String = "bottom",
        barSavePosition: Bool = true,
        terminalApp: String = "terminal",
        bookmarksEnabled: Bool = true,
        bookmarkBrowsers: [String] = ["firefox", "safari", "chrome"],
        appSearchPaths: [String] = [],
        learningEnabled: Bool = true,
        pathSort: String = "name",
        confirmQuitAll: Bool = true,
        calcOpensCalculator: Bool = false,
        learnVerbOrder: Bool = true,
        contentSearchKeyword: String = "in",
        tagSearchKeyword: String = "tags",
        webHistoryDays: Int = 90,
        settingsInSearch: Bool = true,
        openKeyword: String = "open",
        findKeyword: String = "find",
        fileTypes: [String] = [],
        fileExcludedFolders: [String] = [],
        calcDecimal: String = "system",
        calcGrouping: Bool = false,
        showScrollbar: Bool = false,
        barKeys: [String: String] = [:],
        bttPauseKeys: [String] = []
    ) {
        self.enabled = enabled
        self.pickerEnabled = pickerEnabled
        self.overlayEnabled = overlayEnabled
        self.overlayLabelsOnly = overlayLabelsOnly
        self.overlayDurationSeconds = overlayDurationSeconds
        self.appMouseActionsEnabled = appMouseActionsEnabled
        self.scrollModeEnabled = scrollModeEnabled
        self.searchHotkey = TargetGridConfig.normalizedKey(searchHotkey, fallback: "")
        self.actionsHotkey = TargetGridConfig.normalizedKey(actionsHotkey, fallback: "")
        self.screenSearchHotkey = TargetGridConfig.normalizedKey(screenSearchHotkey, fallback: "")
        self.launcherOnScreen = launcherOnScreen
        self.webSearchURL = webSearchURL
        self.pickModifier = TargetModeConfig.pickModifiers.contains(pickModifier) ? pickModifier : "command"
        self.returnCommand = TargetModeConfig.returnEffects.contains(returnCommand) ? returnCommand : "new-stage"
        self.returnOption = TargetModeConfig.returnEffects.contains(returnOption) ? returnOption : "here"
        self.returnControl = TargetModeConfig.returnEffects.contains(returnControl) ? returnControl : "web"
        self.workflowViewStyle = TargetModeConfig.workflowViewStyles.contains(workflowViewStyle) ? workflowViewStyle : "system"
        self.workflowsEnabled = workflowsEnabled
        self.alfredWorkflows = alfredWorkflows
        self.webSearches = webSearches
        self.fallbackSearches = fallbackSearches
        self.idleFrequentEnabled = idleFrequentEnabled
        self.idleFrequentCount = min(10, max(1, idleFrequentCount))
        self.typoMaxErrors = min(2, max(0, typoMaxErrors))
        self.idleRecentSearchesEnabled = idleRecentSearchesEnabled
        self.idleRecentSearchesCount = min(20, max(1, idleRecentSearchesCount))
        self.viewCycleHotkey = TargetGridConfig.normalizedKey(viewCycleHotkey, fallback: "")
        self.labelFontSize = min(48, max(8, labelFontSize))
        self.searchLabelFontSize = min(48, max(8, searchLabelFontSize))
        self.searchTextFontSize = min(48, max(8, searchTextFontSize))
        self.commandTextFontSize = min(48, max(8, commandTextFontSize))
        self.searchFontFamily = searchFontFamily
        self.commandFontFamily = commandFontFamily
        self.theme = theme.isEmpty ? "roadie" : theme
        self.themeDark = themeDark
        self.visibleResults = visibleResults <= 0 ? 0 : min(20, max(3, visibleResults))
        self.barScreen = TargetModeConfig.barScreens.contains(barScreen) ? barScreen : "mouse"
        self.barPosition = TargetModeConfig.barPositions.contains(barPosition) ? barPosition : "bottom"
        self.barSavePosition = barSavePosition
        self.terminalApp = TargetModeConfig.terminalApps.contains(terminalApp) ? terminalApp : "terminal"
        self.bookmarksEnabled = bookmarksEnabled
        self.bookmarkBrowsers = bookmarkBrowsers.filter { TargetModeConfig.bookmarkBrowserIDs.contains($0) }
        self.appSearchPaths = appSearchPaths
        self.learningEnabled = learningEnabled
        self.pathSort = TargetModeConfig.pathSorts.contains(pathSort) ? pathSort : "name"
        self.confirmQuitAll = confirmQuitAll
        self.calcOpensCalculator = calcOpensCalculator
        self.learnVerbOrder = learnVerbOrder
        self.contentSearchKeyword = contentSearchKeyword.trimmingCharacters(in: .whitespaces)
        self.tagSearchKeyword = tagSearchKeyword.trimmingCharacters(in: .whitespaces)
        self.webHistoryDays = min(365, max(0, webHistoryDays))
        self.settingsInSearch = settingsInSearch
        self.openKeyword = openKeyword.trimmingCharacters(in: .whitespaces)
        self.findKeyword = findKeyword.trimmingCharacters(in: .whitespaces)
        self.fileTypes = fileTypes.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        self.fileExcludedFolders = fileExcludedFolders.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        self.calcDecimal = TargetModeConfig.calcDecimals.contains(calcDecimal) ? calcDecimal : "system"
        self.calcGrouping = calcGrouping
        self.showScrollbar = showScrollbar
        self.barKeys = LauncherBarKeys.resolved(barKeys)
        self.bttPauseKeys = bttPauseKeys.map { TargetGridConfig.normalizedKey($0, fallback: "") }.filter { !$0.isEmpty }
    }

    /// Modificateurs (`command`, `control`, `alt`, `shift`) et touche d'un raccourci normalisé ;
    /// nil si la chaîne n'a pas exactement une touche et au moins un modificateur.
    public static func hotkeyParts(_ normalized: String) -> (modifiers: Set<String>, key: String)? {
        let modifierNames: Set<String> = ["command", "control", "alt", "shift"]
        let parts = normalized.split(separator: "+").map(String.init)
        let modifiers = Set(parts.filter { modifierNames.contains($0) })
        let keys = parts.filter { !modifierNames.contains($0) }
        guard !modifiers.isEmpty, keys.count == 1, let key = keys.first, !key.isEmpty else { return nil }
        return (modifiers, key)
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case pickerEnabled = "picker_enabled"
        case overlayEnabled = "overlay_enabled"
        case overlayLabelsOnly = "overlay_labels_only"
        case overlayDurationSeconds = "overlay_duration_seconds"
        case appMouseActionsEnabled = "app_mouse_actions_enabled"
        case scrollModeEnabled = "scroll_mode_enabled"
        case searchHotkey = "search_hotkey"
        case actionsHotkey = "actions_hotkey"
        case screenSearchHotkey = "screen_search_hotkey"
        case launcherOnScreen = "launcher_on_screen"
        case webSearchURL = "web_search_url"
        case pickModifier = "pick_modifier"
        case returnCommand = "return_cmd"
        case returnOption = "return_alt"
        case returnControl = "return_ctrl"
        case workflowViewStyle = "workflow_view_style"
        case workflowsEnabled = "workflows_enabled"
        case alfredWorkflows = "alfred_workflows"
        case webSearches = "web_searches"
        case fallbackSearches = "fallback_searches"
        case idleFrequentEnabled = "idle_frequent_enabled"
        case idleFrequentCount = "idle_frequent_count"
        case typoMaxErrors = "typo_max_errors"
        case idleRecentSearchesEnabled = "idle_recent_searches_enabled"
        case idleRecentSearchesCount = "idle_recent_searches_count"
        case viewCycleHotkey = "view_cycle_hotkey"
        case labelFontSize = "label_font_size"
        case searchLabelFontSize = "search_label_font_size"
        case searchTextFontSize = "search_text_font_size"
        case commandTextFontSize = "command_text_font_size"
        case searchFontFamily = "search_font_family"
        case commandFontFamily = "command_font_family"
        case theme
        case themeDark = "theme_dark"
        case visibleResults = "visible_results"
        case barScreen = "bar_screen"
        case barPosition = "bar_position"
        case barSavePosition = "bar_save_position"
        case terminalApp = "terminal_app"
        case bookmarksEnabled = "bookmarks_enabled"
        case bookmarkBrowsers = "bookmark_browsers"
        case appSearchPaths = "app_search_paths"
        case learningEnabled = "learning_enabled"
        case pathSort = "path_sort"
        case confirmQuitAll = "confirm_quit_all"
        case calcOpensCalculator = "calc_opens_calculator"
        case learnVerbOrder = "learn_verb_order"
        case contentSearchKeyword = "content_search_keyword"
        case tagSearchKeyword = "tag_search_keyword"
        case webHistoryDays = "web_history_days"
        case settingsInSearch = "settings_in_search"
        case openKeyword = "open_keyword"
        case findKeyword = "find_keyword"
        case fileTypes = "file_types"
        case fileExcludedFolders = "file_excluded_folders"
        case calcDecimal = "calc_decimal"
        case calcGrouping = "calc_grouping"
        case showScrollbar = "show_scrollbar"
        case bttPauseKeys = "btt_pause_keys"
    }

    /// Clé TOML quelconque : les touches de la barre se lisent par leur nom (`large_type_key`…).
    struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        try self.init(
            container: decoder.container(keyedBy: CodingKeys.self),
            barKeys: Self.decodeBarKeys(decoder.container(keyedBy: AnyKey.self)), defaults: TargetModeConfig()
        )
    }

    /// O(k), k = clés du lanceur. Les clés absentes conservent leur valeur héritée.
    init(container c: KeyedDecodingContainer<CodingKeys>, barKeys: [String: String], defaults: TargetModeConfig) throws {
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled,
            pickerEnabled: try c.decodeIfPresent(Bool.self, forKey: .pickerEnabled) ?? defaults.pickerEnabled,
            overlayEnabled: try c.decodeIfPresent(Bool.self, forKey: .overlayEnabled) ?? defaults.overlayEnabled,
            overlayLabelsOnly: try c.decodeIfPresent(Bool.self, forKey: .overlayLabelsOnly) ?? defaults.overlayLabelsOnly,
            overlayDurationSeconds: try c.decodeFlexibleDouble(forKey: .overlayDurationSeconds) ?? defaults.overlayDurationSeconds,
            appMouseActionsEnabled: try c.decodeIfPresent(Bool.self, forKey: .appMouseActionsEnabled) ?? defaults.appMouseActionsEnabled,
            scrollModeEnabled: try c.decodeIfPresent(Bool.self, forKey: .scrollModeEnabled) ?? defaults.scrollModeEnabled,
            searchHotkey: try c.decodeIfPresent(String.self, forKey: .searchHotkey) ?? defaults.searchHotkey,
            actionsHotkey: try c.decodeIfPresent(String.self, forKey: .actionsHotkey) ?? defaults.actionsHotkey,
            screenSearchHotkey: try c.decodeIfPresent(String.self, forKey: .screenSearchHotkey) ?? defaults.screenSearchHotkey,
            launcherOnScreen: try c.decodeIfPresent(Bool.self, forKey: .launcherOnScreen) ?? defaults.launcherOnScreen,
            webSearchURL: try c.decodeIfPresent(String.self, forKey: .webSearchURL) ?? defaults.webSearchURL,
            pickModifier: try c.decodeIfPresent(String.self, forKey: .pickModifier) ?? defaults.pickModifier,
            returnCommand: try c.decodeIfPresent(String.self, forKey: .returnCommand) ?? defaults.returnCommand,
            returnOption: try c.decodeIfPresent(String.self, forKey: .returnOption) ?? defaults.returnOption,
            returnControl: try c.decodeIfPresent(String.self, forKey: .returnControl) ?? defaults.returnControl,
            workflowViewStyle: try c.decodeIfPresent(String.self, forKey: .workflowViewStyle) ?? defaults.workflowViewStyle,
            workflowsEnabled: try c.decodeIfPresent(Bool.self, forKey: .workflowsEnabled) ?? defaults.workflowsEnabled,
            alfredWorkflows: try c.decodeIfPresent(Bool.self, forKey: .alfredWorkflows) ?? defaults.alfredWorkflows,
            webSearches: try c.decodeIfPresent([WebSearch].self, forKey: .webSearches) ?? defaults.webSearches,
            fallbackSearches: try c.decodeIfPresent([String].self, forKey: .fallbackSearches) ?? defaults.fallbackSearches,
            idleFrequentEnabled: try c.decodeIfPresent(Bool.self, forKey: .idleFrequentEnabled) ?? defaults.idleFrequentEnabled,
            idleFrequentCount: try c.decodeIfPresent(Int.self, forKey: .idleFrequentCount) ?? defaults.idleFrequentCount,
            typoMaxErrors: try c.decodeIfPresent(Int.self, forKey: .typoMaxErrors) ?? defaults.typoMaxErrors,
            idleRecentSearchesEnabled: try c.decodeIfPresent(Bool.self, forKey: .idleRecentSearchesEnabled) ?? defaults.idleRecentSearchesEnabled,
            idleRecentSearchesCount: try c.decodeIfPresent(Int.self, forKey: .idleRecentSearchesCount) ?? defaults.idleRecentSearchesCount,
            viewCycleHotkey: try c.decodeIfPresent(String.self, forKey: .viewCycleHotkey) ?? defaults.viewCycleHotkey,
            labelFontSize: try c.decodeFlexibleDouble(forKey: .labelFontSize) ?? defaults.labelFontSize,
            searchLabelFontSize: try c.decodeFlexibleDouble(forKey: .searchLabelFontSize) ?? defaults.searchLabelFontSize,
            searchTextFontSize: try c.decodeFlexibleDouble(forKey: .searchTextFontSize) ?? defaults.searchTextFontSize,
            commandTextFontSize: try c.decodeFlexibleDouble(forKey: .commandTextFontSize) ?? defaults.commandTextFontSize,
            searchFontFamily: try c.decodeIfPresent(String.self, forKey: .searchFontFamily) ?? defaults.searchFontFamily,
            commandFontFamily: try c.decodeIfPresent(String.self, forKey: .commandFontFamily) ?? defaults.commandFontFamily,
            theme: try c.decodeIfPresent(String.self, forKey: .theme) ?? defaults.theme,
            themeDark: try c.decodeIfPresent(String.self, forKey: .themeDark) ?? defaults.themeDark,
            visibleResults: try c.decodeIfPresent(Int.self, forKey: .visibleResults) ?? defaults.visibleResults,
            barScreen: try c.decodeIfPresent(String.self, forKey: .barScreen) ?? defaults.barScreen,
            barPosition: try c.decodeIfPresent(String.self, forKey: .barPosition) ?? defaults.barPosition,
            barSavePosition: try c.decodeIfPresent(Bool.self, forKey: .barSavePosition) ?? defaults.barSavePosition,
            terminalApp: try c.decodeIfPresent(String.self, forKey: .terminalApp) ?? defaults.terminalApp,
            bookmarksEnabled: try c.decodeIfPresent(Bool.self, forKey: .bookmarksEnabled) ?? defaults.bookmarksEnabled,
            bookmarkBrowsers: try c.decodeIfPresent([String].self, forKey: .bookmarkBrowsers) ?? defaults.bookmarkBrowsers,
            appSearchPaths: try c.decodeIfPresent([String].self, forKey: .appSearchPaths) ?? defaults.appSearchPaths,
            learningEnabled: try c.decodeIfPresent(Bool.self, forKey: .learningEnabled) ?? defaults.learningEnabled,
            pathSort: try c.decodeIfPresent(String.self, forKey: .pathSort) ?? defaults.pathSort,
            confirmQuitAll: try c.decodeIfPresent(Bool.self, forKey: .confirmQuitAll) ?? defaults.confirmQuitAll,
            calcOpensCalculator: try c.decodeIfPresent(Bool.self, forKey: .calcOpensCalculator) ?? defaults.calcOpensCalculator,
            learnVerbOrder: try c.decodeIfPresent(Bool.self, forKey: .learnVerbOrder) ?? defaults.learnVerbOrder,
            contentSearchKeyword: try c.decodeIfPresent(String.self, forKey: .contentSearchKeyword) ?? defaults.contentSearchKeyword,
            tagSearchKeyword: try c.decodeIfPresent(String.self, forKey: .tagSearchKeyword) ?? defaults.tagSearchKeyword,
            webHistoryDays: try c.decodeIfPresent(Int.self, forKey: .webHistoryDays) ?? defaults.webHistoryDays,
            settingsInSearch: try c.decodeIfPresent(Bool.self, forKey: .settingsInSearch) ?? defaults.settingsInSearch,
            openKeyword: try c.decodeIfPresent(String.self, forKey: .openKeyword) ?? defaults.openKeyword,
            findKeyword: try c.decodeIfPresent(String.self, forKey: .findKeyword) ?? defaults.findKeyword,
            fileTypes: try c.decodeIfPresent([String].self, forKey: .fileTypes) ?? defaults.fileTypes,
            fileExcludedFolders: try c.decodeIfPresent([String].self, forKey: .fileExcludedFolders) ?? defaults.fileExcludedFolders,
            calcDecimal: try c.decodeIfPresent(String.self, forKey: .calcDecimal) ?? defaults.calcDecimal,
            calcGrouping: try c.decodeIfPresent(Bool.self, forKey: .calcGrouping) ?? defaults.calcGrouping,
            showScrollbar: try c.decodeIfPresent(Bool.self, forKey: .showScrollbar) ?? defaults.showScrollbar,
            barKeys: defaults.barKeys.merging(barKeys) { _, new in new },
            bttPauseKeys: try c.decodeIfPresent([String].self, forKey: .bttPauseKeys) ?? defaults.bttPauseKeys
        )
    }

    /// O(a), a = nombre d'actions de la barre.
    static func decodeBarKeys(_ any: KeyedDecodingContainer<AnyKey>) throws -> [String: String] {
        var keys: [String: String] = [:]
        for action in LauncherBarKeys.actions {
            if let value = try any.decodeIfPresent(String.self, forKey: AnyKey(stringValue: action.configKey)) {
                keys[action.id] = value
            }
        }
        return keys
    }
}

public struct AppTargetsConfig: Equatable, Codable, Sendable {
    /// `frontmost_window` : fenêtre active ; `visible_windows` : toutes les fenêtres à l'écran (SPEC-021).
    public static let scopes: Set<String> = ["frontmost_window", "visible_windows"]

    public var enabled: Bool
    public var scope: String
    public var maxTargets: Int
    public var timeoutMs: Int
    public var hintCharacters: String
    public var includeRoles: [String]
    public var axBoostEnabled: Bool
    public var maxDepth: Int
    public var additionalBoostBundleIDs: [String]

    public init(
        enabled: Bool = false,
        scope: String = "frontmost_window",
        maxTargets: Int = 150,
        timeoutMs: Int = 120,
        hintCharacters: String = "asdfghjkl",
        includeRoles: [String] = ["AXButton", "AXLink", "AXTextField", "AXMenuItem", "AXRow", "AXCheckBox", "AXRadioButton", "AXPopUpButton"],
        axBoostEnabled: Bool = false,
        maxDepth: Int = 12,
        additionalBoostBundleIDs: [String] = []
    ) {
        self.enabled = enabled
        self.scope = scope
        self.maxTargets = min(500, max(1, maxTargets))
        self.timeoutMs = min(2_000, max(10, timeoutMs))
        self.hintCharacters = hintCharacters.isEmpty ? "asdfghjkl" : hintCharacters
        self.includeRoles = includeRoles
        self.axBoostEnabled = axBoostEnabled
        self.maxDepth = min(40, max(1, maxDepth))
        self.additionalBoostBundleIDs = additionalBoostBundleIDs
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case scope
        case maxTargets = "max_targets"
        case timeoutMs = "timeout_ms"
        case hintCharacters = "hint_characters"
        case includeRoles = "include_roles"
        case axBoostEnabled = "ax_boost_enabled"
        case maxDepth = "max_depth"
        case additionalBoostBundleIDs = "additional_boost_bundle_ids"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            scope: try c.decodeIfPresent(String.self, forKey: .scope) ?? "frontmost_window",
            maxTargets: try c.decodeIfPresent(Int.self, forKey: .maxTargets) ?? 150,
            timeoutMs: try c.decodeIfPresent(Int.self, forKey: .timeoutMs) ?? 120,
            hintCharacters: try c.decodeIfPresent(String.self, forKey: .hintCharacters) ?? "asdfghjkl",
            includeRoles: try c.decodeIfPresent([String].self, forKey: .includeRoles) ?? ["AXButton", "AXLink", "AXTextField", "AXMenuItem", "AXRow", "AXCheckBox", "AXRadioButton", "AXPopUpButton"],
            axBoostEnabled: try c.decodeIfPresent(Bool.self, forKey: .axBoostEnabled) ?? false,
            maxDepth: try c.decodeIfPresent(Int.self, forKey: .maxDepth) ?? 12,
            additionalBoostBundleIDs: try c.decodeIfPresent([String].self, forKey: .additionalBoostBundleIDs) ?? []
        )
    }
}

public enum TargetGridInteractionMode: String, Codable, Equatable, Sendable {
    case autoClick = "auto_click"
    case recursive
}

public enum TargetGridArrowEdgeBehavior: String, Codable, Equatable, Sendable {
    case clamp
    case wrap
}

public enum TargetGridLabelPlacement: String, Codable, Equatable, Sendable {
    case callout
    case center
}

public enum TargetGridScope: String, Codable, Equatable, Sendable {
    case display
    case focusedWindow = "focused_window"
}

public struct TargetGridConfig: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var mode: TargetGridInteractionMode
    public var overlayEnabled: Bool
    public var overlayDrawGrid: Bool
    public var overlayFillColor: String
    public var overlayFillOpacity: Double
    public var overlayBorderColor: String
    public var overlayBorderOpacity: Double
    public var overlayLabelColor: String
    public var overlayLabelBackgroundOpacity: Double
    public var rows: Int
    public var columns: Int
    public var maxDepth: Int
    public var hintCharacters: String
    public var confirmActionKey: String
    public var resetKey: String
    public var backKey: String
    public var exitKey: String
    public var arrowNavigationEnabled: Bool
    public var arrowEdgeBehavior: TargetGridArrowEdgeBehavior
    public var actionDelayMs: Int
    public var wakeMousePixels: Int
    public var mouseFollowGrid: Bool
    public var focusFollowGrid: Bool
    public var labelPlacement: TargetGridLabelPlacement
    public var defaultScope: TargetGridScope
    /// Taille de police des étiquettes en points (SPEC-023). Le décodage ramène toute valeur dans 8…48 (clamp dans l'init) : aucune validation hors plage n'est nécessaire.
    public var labelFontSize: Double

    public init(
        enabled: Bool = false,
        mode: TargetGridInteractionMode = .recursive,
        overlayEnabled: Bool = true,
        overlayDrawGrid: Bool = true,
        overlayFillColor: String = "#4DABF7",
        overlayFillOpacity: Double = 0.10,
        overlayBorderColor: String = "#4DABF7",
        overlayBorderOpacity: Double = 0.55,
        overlayLabelColor: String = "#FFFFFF",
        overlayLabelBackgroundOpacity: Double = 0.84,
        rows: Int = 3,
        columns: Int = 3,
        maxDepth: Int = 3,
        hintCharacters: String = "azeqsdwxc",
        confirmActionKey: String = "space",
        resetKey: String = "r",
        backKey: String = "backspace",
        exitKey: String = "escape",
        arrowNavigationEnabled: Bool = true,
        arrowEdgeBehavior: TargetGridArrowEdgeBehavior = .clamp,
        actionDelayMs: Int = 30,
        wakeMousePixels: Int = 1,
        mouseFollowGrid: Bool = false,
        focusFollowGrid: Bool = false,
        labelPlacement: TargetGridLabelPlacement = .callout,
        defaultScope: TargetGridScope = .display,
        labelFontSize: Double = 13
    ) {
        self.enabled = enabled
        self.mode = mode
        self.overlayEnabled = overlayEnabled
        self.overlayDrawGrid = overlayDrawGrid
        self.overlayFillColor = overlayFillColor.isEmpty ? "#4DABF7" : overlayFillColor
        self.overlayFillOpacity = min(1, max(0, overlayFillOpacity))
        self.overlayBorderColor = overlayBorderColor.isEmpty ? "#4DABF7" : overlayBorderColor
        self.overlayBorderOpacity = min(1, max(0, overlayBorderOpacity))
        self.overlayLabelColor = overlayLabelColor.isEmpty ? "#FFFFFF" : overlayLabelColor
        self.overlayLabelBackgroundOpacity = min(1, max(0, overlayLabelBackgroundOpacity))
        self.rows = min(12, max(2, rows))
        self.columns = min(12, max(2, columns))
        self.maxDepth = min(20, max(1, maxDepth))
        self.hintCharacters = hintCharacters.isEmpty ? "azeqsdwxc" : hintCharacters
        self.confirmActionKey = Self.normalizedKey(confirmActionKey, fallback: "space")
        self.resetKey = Self.normalizedKey(resetKey, fallback: "r")
        self.backKey = Self.normalizedKey(backKey, fallback: "backspace")
        self.exitKey = Self.normalizedKey(exitKey, fallback: "escape")
        self.arrowNavigationEnabled = arrowNavigationEnabled
        self.arrowEdgeBehavior = arrowEdgeBehavior
        self.actionDelayMs = min(1_000, max(0, actionDelayMs))
        self.wakeMousePixels = min(20, max(0, wakeMousePixels))
        self.mouseFollowGrid = mouseFollowGrid
        self.focusFollowGrid = focusFollowGrid
        self.labelPlacement = labelPlacement
        self.defaultScope = defaultScope
        self.labelFontSize = min(48, max(8, labelFontSize))
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case overlayEnabled = "overlay_enabled"
        case overlayDrawGrid = "overlay_draw_grid"
        case overlayFillColor = "overlay_fill_color"
        case overlayFillOpacity = "overlay_fill_opacity"
        case overlayBorderColor = "overlay_border_color"
        case overlayBorderOpacity = "overlay_border_opacity"
        case overlayLabelColor = "overlay_label_color"
        case overlayLabelBackgroundOpacity = "overlay_label_background_opacity"
        case rows
        case columns
        case maxDepth = "max_depth"
        case hintCharacters = "hint_characters"
        case mode
        case confirmActionKey = "confirm_action_key"
        case resetKey = "reset_key"
        case backKey = "back_key"
        case exitKey = "exit_key"
        case arrowNavigationEnabled = "arrow_navigation_enabled"
        case arrowEdgeBehavior = "arrow_edge_behavior"
        case actionDelayMs = "action_delay_ms"
        case wakeMousePixels = "wake_mouse_pixels"
        case mouseFollowGrid = "mouse_follow_grid"
        case focusFollowGrid = "focus_follow_grid"
        case labelPlacement = "label_placement"
        case defaultScope = "default_scope"
        case labelFontSize = "label_font_size"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            mode: try c.decodeIfPresent(TargetGridInteractionMode.self, forKey: .mode) ?? .recursive,
            overlayEnabled: try c.decodeIfPresent(Bool.self, forKey: .overlayEnabled) ?? true,
            overlayDrawGrid: try c.decodeIfPresent(Bool.self, forKey: .overlayDrawGrid) ?? true,
            overlayFillColor: try c.decodeIfPresent(String.self, forKey: .overlayFillColor) ?? "#4DABF7",
            overlayFillOpacity: try c.decodeFlexibleDouble(forKey: .overlayFillOpacity) ?? 0.10,
            overlayBorderColor: try c.decodeIfPresent(String.self, forKey: .overlayBorderColor) ?? "#4DABF7",
            overlayBorderOpacity: try c.decodeFlexibleDouble(forKey: .overlayBorderOpacity) ?? 0.55,
            overlayLabelColor: try c.decodeIfPresent(String.self, forKey: .overlayLabelColor) ?? "#FFFFFF",
            overlayLabelBackgroundOpacity: try c.decodeFlexibleDouble(forKey: .overlayLabelBackgroundOpacity) ?? 0.84,
            rows: try c.decodeIfPresent(Int.self, forKey: .rows) ?? 3,
            columns: try c.decodeIfPresent(Int.self, forKey: .columns) ?? 3,
            maxDepth: try c.decodeIfPresent(Int.self, forKey: .maxDepth) ?? 3,
            hintCharacters: try c.decodeIfPresent(String.self, forKey: .hintCharacters) ?? "azeqsdwxc",
            confirmActionKey: try c.decodeIfPresent(String.self, forKey: .confirmActionKey) ?? "space",
            resetKey: try c.decodeIfPresent(String.self, forKey: .resetKey) ?? "r",
            backKey: try c.decodeIfPresent(String.self, forKey: .backKey) ?? "backspace",
            exitKey: try c.decodeIfPresent(String.self, forKey: .exitKey) ?? "escape",
            arrowNavigationEnabled: try c.decodeIfPresent(Bool.self, forKey: .arrowNavigationEnabled) ?? true,
            arrowEdgeBehavior: try c.decodeIfPresent(TargetGridArrowEdgeBehavior.self, forKey: .arrowEdgeBehavior) ?? .clamp,
            actionDelayMs: try c.decodeIfPresent(Int.self, forKey: .actionDelayMs) ?? 30,
            wakeMousePixels: try c.decodeIfPresent(Int.self, forKey: .wakeMousePixels) ?? 1,
            mouseFollowGrid: try c.decodeIfPresent(Bool.self, forKey: .mouseFollowGrid) ?? false,
            focusFollowGrid: try c.decodeIfPresent(Bool.self, forKey: .focusFollowGrid) ?? false,
            labelPlacement: try c.decodeIfPresent(TargetGridLabelPlacement.self, forKey: .labelPlacement) ?? .callout,
            defaultScope: try c.decodeIfPresent(TargetGridScope.self, forKey: .defaultScope) ?? .display,
            labelFontSize: try c.decodeFlexibleDouble(forKey: .labelFontSize) ?? 13
        )
    }

    /// Partagé avec `TargetModeConfig.searchHotkey` (SPEC-021).
    static func normalizedKey(_ value: String, fallback: String) -> String {
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return fallback }
        let parts = cleaned.split(separator: "+").map(String.init).map { part in
            switch part {
            case "option":
                return "alt"
            case "cmd":
                return "command"
            case "ctrl":
                return "control"
            case "hyper":
                return "command+control+alt"
            case "esc":
                return "escape"
            case "delete":
                return "backspace"
            case "enter":
                return "return"
            default:
                return part
            }
        }
        return parts.joined(separator: "+")
    }
}

public struct TargetRecordConfig: Equatable, Codable, Sendable {
    public enum IndicatorMode: String, Codable, Equatable, Sendable {
        case notification
        case navrail
        case both
        case none

        public var showsNotification: Bool {
            self == .notification || self == .both
        }

        public var showsNavrail: Bool {
            self == .navrail || self == .both
        }
    }

    public var enabled: Bool
    public var replayEnabled: Bool
    public var directory: String
    public var defaultDurationSeconds: Double
    public var maxDurationSeconds: Double
    public var maxEvents: Int
    public var includeMouseMoves: Bool
    public var includeKeyEvents: Bool
    public var includeAXContext: Bool
    public var recordTextInput: Bool
    public var indicator: IndicatorMode
    public var navrailBottomOffset: Double

    public init(
        enabled: Bool = false,
        replayEnabled: Bool = false,
        directory: String = "~/.local/state/roadies/records",
        defaultDurationSeconds: Double = 10,
        maxDurationSeconds: Double = 120,
        maxEvents: Int = 2_000,
        includeMouseMoves: Bool = false,
        includeKeyEvents: Bool = true,
        includeAXContext: Bool = true,
        recordTextInput: Bool = false,
        indicator: IndicatorMode = .notification,
        navrailBottomOffset: Double = 50
    ) {
        self.enabled = enabled
        self.replayEnabled = replayEnabled
        self.directory = directory
        self.defaultDurationSeconds = min(maxDurationSeconds, max(0.5, defaultDurationSeconds))
        self.maxDurationSeconds = min(3_600, max(1, maxDurationSeconds))
        self.maxEvents = min(20_000, max(1, maxEvents))
        self.includeMouseMoves = includeMouseMoves
        self.includeKeyEvents = includeKeyEvents
        self.includeAXContext = includeAXContext
        self.recordTextInput = recordTextInput
        self.indicator = indicator
        self.navrailBottomOffset = min(400, max(0, navrailBottomOffset))
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case replayEnabled = "replay_enabled"
        case directory
        case defaultDurationSeconds = "default_duration_seconds"
        case maxDurationSeconds = "max_duration_seconds"
        case maxEvents = "max_events"
        case includeMouseMoves = "include_mouse_moves"
        case includeKeyEvents = "include_key_events"
        case includeAXContext = "include_ax_context"
        case recordTextInput = "record_text_input"
        case indicator
        case navrailBottomOffset = "navrail_bottom_offset"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            replayEnabled: try c.decodeIfPresent(Bool.self, forKey: .replayEnabled) ?? false,
            directory: try c.decodeIfPresent(String.self, forKey: .directory) ?? "~/.local/state/roadies/records",
            defaultDurationSeconds: try c.decodeFlexibleDouble(forKey: .defaultDurationSeconds) ?? 10,
            maxDurationSeconds: try c.decodeFlexibleDouble(forKey: .maxDurationSeconds) ?? 120,
            maxEvents: try c.decodeIfPresent(Int.self, forKey: .maxEvents) ?? 2_000,
            includeMouseMoves: try c.decodeIfPresent(Bool.self, forKey: .includeMouseMoves) ?? false,
            includeKeyEvents: try c.decodeIfPresent(Bool.self, forKey: .includeKeyEvents) ?? true,
            includeAXContext: try c.decodeIfPresent(Bool.self, forKey: .includeAXContext) ?? true,
            recordTextInput: try c.decodeIfPresent(Bool.self, forKey: .recordTextInput) ?? false,
            indicator: try c.decodeIfPresent(IndicatorMode.self, forKey: .indicator) ?? .notification,
            navrailBottomOffset: try c.decodeFlexibleDouble(forKey: .navrailBottomOffset) ?? 50
        )
    }
}

public struct TitlebarContextMenuConfig: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var height: Double
    public var leadingExclusion: Double
    public var trailingExclusion: Double
    public var managedWindowsOnly: Bool
    public var tileCandidatesOnly: Bool
    public var includeStageDestinations: Bool
    public var includeDesktopDestinations: Bool
    public var includeDisplayDestinations: Bool
    /// Double-clic sur la barre de titre : maximisation Roadie (SPEC-050). Actif seulement si
    /// l'action macOS de ce double-clic vaut « Ne rien faire ». Indépendant du menu par clic droit.
    public var doubleClickMaximize: Bool

    public init(
        enabled: Bool = false,
        height: Double = 36,
        leadingExclusion: Double = 84,
        trailingExclusion: Double = 16,
        managedWindowsOnly: Bool = true,
        tileCandidatesOnly: Bool = true,
        includeStageDestinations: Bool = true,
        includeDesktopDestinations: Bool = true,
        includeDisplayDestinations: Bool = true,
        doubleClickMaximize: Bool = false
    ) {
        self.doubleClickMaximize = doubleClickMaximize
        self.enabled = enabled
        self.height = height
        self.leadingExclusion = leadingExclusion
        self.trailingExclusion = trailingExclusion
        self.managedWindowsOnly = managedWindowsOnly
        self.tileCandidatesOnly = tileCandidatesOnly
        self.includeStageDestinations = includeStageDestinations
        self.includeDesktopDestinations = includeDesktopDestinations
        self.includeDisplayDestinations = includeDisplayDestinations
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case height
        case leadingExclusion = "leading_exclusion"
        case trailingExclusion = "trailing_exclusion"
        case managedWindowsOnly = "managed_windows_only"
        case tileCandidatesOnly = "tile_candidates_only"
        case includeStageDestinations = "include_stage_destinations"
        case includeDesktopDestinations = "include_desktop_destinations"
        case includeDisplayDestinations = "include_display_destinations"
        case doubleClickMaximize = "double_click_maximize"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            height: try c.decodeFlexibleDouble(forKey: .height) ?? 36,
            leadingExclusion: try c.decodeFlexibleDouble(forKey: .leadingExclusion) ?? 84,
            trailingExclusion: try c.decodeFlexibleDouble(forKey: .trailingExclusion) ?? 16,
            managedWindowsOnly: try c.decodeIfPresent(Bool.self, forKey: .managedWindowsOnly) ?? true,
            tileCandidatesOnly: try c.decodeIfPresent(Bool.self, forKey: .tileCandidatesOnly) ?? true,
            includeStageDestinations: try c.decodeIfPresent(Bool.self, forKey: .includeStageDestinations) ?? true,
            includeDesktopDestinations: try c.decodeIfPresent(Bool.self, forKey: .includeDesktopDestinations) ?? true,
            includeDisplayDestinations: try c.decodeIfPresent(Bool.self, forKey: .includeDisplayDestinations) ?? true,
            doubleClickMaximize: try c.decodeIfPresent(Bool.self, forKey: .doubleClickMaximize) ?? false
        )
    }
}
