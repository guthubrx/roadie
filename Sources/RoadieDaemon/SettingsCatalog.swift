import Foundation
import RoadieCore

// Catalogue des réglages de `roadies.toml` (SPEC-023) : types purs, sans AppKit ni SwiftUI.
// Les libellés, descriptions, défauts et plages ne se déduisent pas du code : ils sont écrits ici
// et vérifiés par `SettingsCatalogTests` contre `RoadieConfig()` et `RailSettings.load(raw:)`.

/// Catégorie de la fenêtre de réglages. La valeur brute est l'identifiant utilisé par `/settings`.
public enum SettingCategory: String, CaseIterable, Sendable {
    case general
    case raccourcis
    case tuilage
    case stages
    case lettres
    case grille
    case recherche
    case rail
    case bordures
    case focus
    case selecteur
    case overview
    case regles
    case avance

    public var label: String {
        switch self {
        case .general: return tr("Général", "General")
        case .raccourcis: return tr("Raccourcis", "Shortcuts")
        case .tuilage: return tr("Tuilage", "Tiling")
        case .stages: return tr("Stages et bureaux", "Stages and desktops")
        case .lettres: return tr("Mode lettres", "Letter mode")
        case .grille: return tr("Grille", "Grid")
        case .recherche: return tr("Recherche", "Search")
        case .rail: return "Rail"
        case .bordures: return tr("Bordures", "Borders")
        case .focus: return tr("Focus et souris", "Focus and mouse")
        case .overview: return tr("Vue d’ensemble", "Overview")
        case .selecteur: return tr("Sélecteur", "Switcher")
        case .regles: return tr("Règles", "Rules")
        case .avance: return tr("Avancé", "Advanced")
        }
    }

    /// Nom de l'icône système (SF Symbols).
    public var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .raccourcis: return "keyboard"
        case .tuilage: return "rectangle.split.2x2"
        case .stages: return "square.stack.3d.up"
        case .lettres: return "textformat.abc"
        case .grille: return "square.grid.3x3"
        case .recherche: return "magnifyingglass"
        case .rail: return "sidebar.left"
        case .bordures: return "square.dashed"
        case .focus: return "cursorarrow.click"
        case .overview: return "rectangle.3.group"
        case .selecteur: return "rectangle.on.rectangle"
        case .regles: return "list.bullet.rectangle"
        case .avance: return "wrench.and.screwdriver"
        }
    }
}

public enum SettingValue: Equatable, Sendable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    /// Clé facultative sans valeur par défaut (absente du fichier), ou liste en lecture seule.
    case unset
}

public enum SettingKind: Equatable, Sendable {
    case bool
    case int(ClosedRange<Int>?)
    case double(ClosedRange<Double>?)
    case choice([String])
    case text
    /// Chaîne `#RRGGBB` ou `#RRGGBBAA`.
    case color
}

public struct SettingDescriptor: Equatable, Sendable {
    /// `table.clé` sans le préfixe `experimental.` ni `fx.` ; unique dans le catalogue.
    public let id: String
    public let category: SettingCategory
    /// Chemin TOML complet de la table (`experimental.target_grid`) ; vide pour une table racine.
    public let tablePath: String
    public let key: String
    public let label: String
    public let help: String
    public let kind: SettingKind
    public let defaultValue: SettingValue
    /// Présent pour les listes et les tableaux de tables : affichés, jamais modifiés.
    public let readOnlyReason: String?
    public let collection: CollectionSpec?

    /// Libellé de présentation seulement : le menu conserve la valeur brute comme tag. O(1).
    public func choiceLabel(_ value: String) -> String {
        if id == "switcher.presentation", let presentation = WindowSwitcherPresentation(rawValue: value) {
            return presentation.label
        }
        // Thèmes de la barre (session 101) : leur nom, comme dans Alfred.
        if id == "target_mode.theme" || id == "target_mode.theme_dark" {
            if value.isEmpty { return tr("Comme le thème clair", "Same as the light theme") }
            return LauncherThemeCatalog.all().first { $0.id == value }?.name ?? value
        }
        let label: String
        switch (id, value) {
        case ("interface.language", "auto"): return tr("Automatique (langue de macOS)", "Automatic (macOS language)")
        case ("interface.language", "fr"): return "Français"
        case ("interface.language", "en"): return "English"
        case ("target_mode.bar_screen", "mouse"): return tr("Écran de la souris", "Display with the mouse")
        case ("target_mode.bar_screen", "active"): return tr("Écran de la fenêtre active", "Display of the active window")
        case ("target_mode.bar_screen", "main"): return tr("Écran principal", "Main display")
        case ("target_mode.bar_position", "bottom"): return tr("En bas, liste au-dessus", "Bottom, list above")
        case ("target_mode.bar_position", "center"): return tr("Au centre, liste dessous", "Center, list below")
        case ("target_mode.bar_position", "top"): return tr("En haut, liste dessous (comme Alfred)", "Top, list below (like Alfred)")
        case ("target_mode.terminal_app", let app): return LauncherTerminal.appName(app)
        case ("target_mode.return_cmd", let effect), ("target_mode.return_alt", let effect), ("target_mode.return_ctrl", let effect):
            return Self.returnEffectLabel(effect)
        case ("target_mode.workflow_view_style", "system"): return tr("Comme macOS", "Like macOS")
        case ("target_mode.workflow_view_style", "theme"): return tr("Couleurs du thème de la barre", "Bar theme colors")
        case ("target_mode.workflow_view_style", "glassy-dark"): return "Glassy Dark"
        case ("target_mode.workflow_view_style", "flat-dark"): return "Flat Dark"
        case ("target_mode.workflow_view_style", "glassy-light"): return "Glassy Light"
        case ("target_mode.path_sort", "name"): return tr("Par nom", "By name")
        case ("target_mode.path_sort", "modified"): return tr("Modifiés récemment d'abord", "Recently modified first")
        case ("target_mode.path_sort", "created"): return tr("Créés récemment d'abord", "Recently created first")
        case ("overview.presentation", "archipelago"): return tr("Archipel", "Archipelago")
        case ("overview.presentation", "bays"): return tr("Baies", "Bays")
        case ("window_placement.new_apps_target", "focused_display"): return tr("Écran actif (recommandé)", "Active display (recommended)")
        case ("window_placement.new_apps_target", "mouse"): return tr("Écran de la souris", "Display with the mouse")
        case ("window_placement.new_apps_target", "macos"): return tr("Choix de macOS", "macOS choice")
        case ("tiling.default_strategy", "bsp"): label = tr("Arbre automatique", "Automatic tree")
        case ("tiling.default_strategy", "spatialBsp"): label = tr("Arbre persistant", "Persistent tree")
        case ("tiling.default_strategy", "masterStack"): label = tr("Fenêtre principale et pile", "Main window and stack")
        case ("tiling.default_strategy", "float"): label = tr("Placement libre", "Free placement")
        case ("tiling.split_policy", "largest_dim"): label = tr("Répartition équilibrée par défaut", "Balanced split (default)")
        case ("tiling.split_policy", "balanced"): label = tr("Répartition équilibrée héritée", "Balanced split (legacy)")
        case ("tiling.split_policy", "dwindle"): label = tr("Découpage en spirale", "Spiral split")
        case ("switcher.style", "thumbnails"): label = tr("Vignettes", "Thumbnails")
        case ("switcher.style", "icons"): label = tr("Icônes", "Icons")
        case ("switcher.style", "list"): label = tr("Liste compacte", "Compact list")
        default: return value
        }
        return "\(label) (\(value))"
    }

    /// Effet de ⌘, ⌥ ou ⌃ + Retour (session 131), dans la langue de l'interface. O(1).
    static func returnEffectLabel(_ value: String) -> String {
        switch value {
        case "new-stage": tr("Ouvrir ou envoyer dans une nouvelle stage", "Open or send to a new stage")
        case "here": tr("Amener dans la stage active", "Bring to the active stage")
        case "send": tr("Envoyer dans une nouvelle stage, sans y aller", "Send to a new stage, stay here")
        case "web": tr("Chercher le texte tapé sur le web", "Search the typed text on the web")
        case "copy": tr("Copier (chemin, adresse ou titre)", "Copy (path, address or title)")
        case "reveal": tr("Montrer dans le Finder", "Reveal in Finder")
        case "quicklook": tr("Aperçu (Quick Look)", "Quick Look")
        case "verbs": tr("Ouvrir les verbes", "Open the verbs")
        case "none": tr("Rien de plus que Retour", "Same as Return")
        default: value
        }
    }

    /// Une valeur déjà présente reste visible même si elle n'est pas proposée à l'écriture. O(c).
    public func choiceValues(includingCurrent value: String) -> [String] {
        guard case .choice(let choices) = kind else { return [] }
        return choices.contains(value) ? choices : choices + [value]
    }

    public init(
        category: SettingCategory,
        tablePath: String,
        key: String,
        label: String,
        help: String,
        kind: SettingKind,
        defaultValue: SettingValue,
        readOnlyReason: String? = nil,
        collection: CollectionSpec? = nil
    ) {
        self.id = SettingsCatalog.id(tablePath: tablePath, key: key)
        self.category = category
        self.tablePath = tablePath
        self.key = key
        self.label = label
        self.help = help
        self.kind = kind
        self.defaultValue = defaultValue
        self.readOnlyReason = readOnlyReason
        self.collection = collection
    }
}

public enum SettingsCatalog {
    /// Tous les réglages, dans l'ordre d'affichage : l'ordre de `all` fixe celui d'une catégorie.
    public static let all: [SettingDescriptor] =
        interfaceDescriptors + tilingDescriptors + stageDescriptors + focusDescriptors + borderDescriptors
        + targetModeDescriptors + appTargetDescriptors + targetGridDescriptors
        + advancedDescriptors + ruleDescriptors + railDescriptors + fontFamilyDescriptors + switcherDescriptors + overviewDescriptors
        + shortcutDescriptors

    /// Texte de recherche normalisé de chaque réglage, calculé une fois (même ordre que `all`) :
    /// nom, libellé, aide, catégorie et groupe affiché (session 107 : « raccourci » trouve tout un groupe).
    private static let searchTexts: [String] = all.map {
        TargetHintService.normalized("\($0.id) \($0.label) \($0.help) \($0.category.label) \(SettingsOrganization.title(for: $0))")
    }

    /// Préfixes de table retirés du nom d'un réglage.
    private static let hiddenPrefixes = ["experimental.", "fx."]

    /// Nom d'un réglage : chemin de la table sans `experimental.` ni `fx.`, puis la clé.
    public static func id(tablePath: String, key: String) -> String {
        var table = tablePath
        for prefix in hiddenPrefixes where table.hasPrefix(prefix) {
            table.removeFirst(prefix.count)
        }
        return table.isEmpty ? key : "\(table).\(key)"
    }

    /// O(n) - n = nombre de réglages (moins de 200).
    public static func find(id: String) -> SettingDescriptor? {
        all.first { $0.id == id }
    }

    /// Alias d'un choix, acceptés à la lecture du fichier et par `/set`, ramenés à la valeur du catalogue.
    /// `tiling.default_strategy` : les formes que le chargeur accepte (`WindowManagementMode(roadieValue:)`) ;
    /// `mutableBsp` et ses formes deviennent `spatialBsp`, comme au chargement (`Config.swift`, SPEC-017 A8).
    /// `SettingsCatalogTests` vérifie cette table contre `WindowManagementMode`.
    static let choiceAliases: [String: [String: String]] = [
        "tiling.default_strategy": [
            "spatial_bsp": "spatialBsp", "spatial-bsp": "spatialBsp", "spatial": "spatialBsp", "tree": "spatialBsp",
            "mutableBsp": "spatialBsp", "mutable_bsp": "spatialBsp", "mutable-bsp": "spatialBsp", "yabai": "spatialBsp",
            "master_stack": "masterStack", "master-stack": "masterStack",
            "floating": "float",
        ],
    ]

    /// Valeur du catalogue pour un alias connu du réglage `id` (casse ignorée, espaces autour retirés) ;
    /// sinon le texte tel quel. O(a) - a = nombre d'alias du réglage.
    public static func canonicalChoice(_ text: String, for id: String) -> String {
        guard let aliases = choiceAliases[id] else { return text }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return aliases.first { $0.key.caseInsensitiveCompare(trimmed) == .orderedSame }?.value ?? text
    }

    /// O(n)
    public static func descriptors(in category: SettingCategory) -> [SettingDescriptor] {
        all.filter { $0.category == category }
    }

    /// Réglages dont le nom, le libellé ou la description contient la saisie, sans tenir compte
    /// de la casse ni des accents. Saisie vide : aucun résultat. O(n * m) - n réglages, m longueur d'un texte.
    public static func search(_ query: String) -> [SettingDescriptor] {
        // Chaque mot doit apparaître, dans n'importe quel ordre (session 107).
        let words = TargetHintService.normalized(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        return zip(all, searchTexts).filter { text in words.allSatisfy { text.1.contains($0) } }.map(\.0)
    }
}

// MARK: - Fabrique et textes communs

extension SettingsCatalog {
    static let interfaceDescriptors: [SettingDescriptor] = [
        entry(.general, "interface", "settings_text_font_size", tr("Texte des paramètres (points)", "Settings text (points)"),
              tr("Taille des libellés et des champs. Le changement s'applique immédiatement.", "Size of labels and fields. The change applies immediately."), .double(8...32), .double(16)),
        entry(.general, "interface", "settings_help_font_size", tr("Descriptions des paramètres (points)", "Settings descriptions (points)"),
              tr("Taille des aides et des messages dans les paramètres, indépendante des champs.", "Size of help and messages in Settings, independent of the fields."), .double(8...32), .double(14)),
        entry(.general, "interface", "settings_title_font_size", tr("Titres des paramètres (points)", "Settings titles (points)"),
              tr("Taille des titres de catégorie dans les paramètres.", "Size of category titles in Settings."), .double(10...48), .double(22)),
        entry(.general, "interface", "language", tr("Langue de l'interface", "Interface language"),
              tr("Langue de la barre, du sélecteur, de la vue d'ensemble, du rail, des menus et des paramètres. Automatique suit la première langue de macOS. Roadie redémarre pour appliquer le changement.",
                 "Language of the bar, switcher, overview, rail, menus and settings. Automatic follows the first macOS language. Roadie restarts to apply the change."),
              .choice(["auto", "fr", "en"]), .string("auto")),
    ]

    static let readOnlyMessage = tr("lecture seule : modifier le fichier de configuration", "read-only: edit the configuration file")

    /// Réglage simple modifiable.
    static func entry(
        _ category: SettingCategory,
        _ tablePath: String,
        _ key: String,
        _ label: String,
        _ help: String,
        _ kind: SettingKind,
        _ defaultValue: SettingValue
    ) -> SettingDescriptor {
        SettingDescriptor(
            category: category, tablePath: tablePath, key: key, label: label, help: help,
            kind: kind, defaultValue: defaultValue
        )
    }

    /// Liste ou tableau de tables : éditeur structuré intégré.
    static func readOnlyEntry(
        _ category: SettingCategory,
        _ tablePath: String,
        _ key: String,
        _ label: String,
        _ help: String
    ) -> SettingDescriptor {
        let spec = collectionSpec(id: id(tablePath: tablePath, key: key))
        return SettingDescriptor(
            category: category, tablePath: tablePath, key: key, label: label, help: help,
            kind: .text, defaultValue: .string(SettingsCollectionCodec.summary(spec.defaultValue)), collection: spec
        )
    }

    /// Marge facultative d'un côté : absente par défaut.
    private static func gap(_ key: String, _ side: String) -> SettingDescriptor {
        entry(.tuilage, "tiling", key, tr("Marge extérieure \(side)", "Outer gap, \(side)"),
              tr("Remplace la marge extérieure générale sur ce côté. Sans valeur, la marge générale s'applique.", "Overrides the general outer gap on this side. Without a value, the general gap applies."),
              .double(nil), .unset)
    }
}

// MARK: - Raccourcis (session 108)

extension SettingsCatalog {
    /// Touches de la barre, touches prioritaires sur BTT et commandes Roadie. Les raccourcis globaux, les
    /// touches de la grille et celles des présentations restent dans leur table d'origine, rangés ici.
    static let shortcutDescriptors: [SettingDescriptor] = LauncherBarKeys.actions.map { action in
        entry(.raccourcis, "experimental.target_mode", action.configKey, action.label,
              action.help + tr(" Vide : désactivée.", " Empty: off."), .text, .string(action.defaultKey))
    } + [
        readOnlyEntry(.raccourcis, "experimental.target_mode", "btt_pause_keys", tr("Touches de la barre prioritaires sur BetterTouchTool", "Bar keys that take priority over BetterTouchTool"),
                      tr("Tant que la barre est ouverte, Roadie met en pause les raccourcis BetterTouchTool de ces combinaisons, puis les réactive à la fermeture. Le bouton d'un conflit les ajoute ici.", "While the bar is open, Roadie pauses the BetterTouchTool shortcuts that use these combinations, then turns them back on when it closes. A conflict's button adds them here.")),
        readOnlyEntry(.raccourcis, "", "shortcuts", tr("Commandes Roadie", "Roadie commands"),
                      tr("Chaque commande roadie (focus, move, resize, warp, stage, desktop, display, window, toggle, rail…) avec sa combinaison et qui la prend en charge : Roadie, BetterTouchTool ou personne.", "Each roadie command (focus, move, resize, warp, stage, desktop, display, window, toggle, rail…) with its key combination and who handles it: Roadie, BetterTouchTool or nobody.")),
    ]
}

// MARK: - Tuilage

extension SettingsCatalog {
    static let tilingDescriptors: [SettingDescriptor] = [
        entry(.tuilage, "tiling", "default_strategy", tr("Méthode de tuilage", "Tiling method"),
              tr("Dispose les fenêtres automatiquement en arbre, conserve un arbre ajustable, privilégie une fenêtre principale ou laisse le placement libre.", "Arranges windows automatically in a tree, keeps an adjustable tree, favors a main window, or leaves placement free."),
              .choice(["bsp", "spatialBsp", "masterStack", "float"]), .string("bsp")),
        entry(.tuilage, "tiling", "split_policy", tr("Découpage de l'espace", "Space splitting"),
              tr("En mode Arbre automatique (bsp), la répartition équilibrée partage le groupe en deux à chaque découpe. La spirale réserve la moitié à la première fenêtre, puis découpe le reste. Sans effet en mode Arbre persistant.", "In Automatic tree mode (bsp), the balanced split halves the group at each cut. The spiral gives half to the first window, then splits the rest. No effect in Persistent tree mode."),
              .choice(["largest_dim", "balanced", "dwindle"]), .string("largest_dim")),
        entry(.tuilage, "tiling", "live_drag_preview", tr("Réorganiser les fenêtres pendant le glisser", "Rearrange windows while dragging"),
              tr("Les fenêtres voisines prennent leur future place avant le dépôt. Désactivez pour afficher seulement le fantôme. Annuler restaure les voisines. Sans effet sur le redimensionnement par les bords.", "Neighboring windows take their future positions before the drop. Turn off to show only the ghost. Canceling restores the neighbors. Does not affect resizing by window edges."),
              .bool, .bool(true)),
        entry(.tuilage, "tiling", "resize_handles", tr("Poignées de redimensionnement", "Resize handles"),
              tr("Permet de tirer les séparations entre les fenêtres en mode Arbre persistant. Le redimensionnement par les bords des fenêtres reste disponible.", "Lets you drag the dividers between windows in Persistent tree mode. Resizing by window edges stays available."),
              .bool, .bool(true)),
        entry(.tuilage, "tiling", "gaps_outer", tr("Marge extérieure (points)", "Outer gap (points)"),
              tr("Espace entre les fenêtres et le bord de l'écran.", "Space between the windows and the edge of the display."), .double(nil), .double(8)),
        gap("gaps_outer_top", tr("en haut", "top")),
        gap("gaps_outer_right", tr("à droite", "right")),
        gap("gaps_outer_bottom", tr("en bas", "bottom")),
        gap("gaps_outer_left", tr("à gauche", "left")),
        entry(.tuilage, "tiling", "gaps_inner", tr("Espace entre les fenêtres (points)", "Gap between windows (points)"),
              tr("Espace laissé entre deux fenêtres voisines.", "Space left between two neighboring windows."), .double(nil), .double(4)),
        entry(.tuilage, "tiling", "master_ratio", tr("Part de la fenêtre principale", "Main window share"),
              tr("Proportion de l'écran donnée à la fenêtre principale en mode maître et pile (0,6 = 60 %).", "Share of the display given to the main window in main-and-stack mode (0.6 = 60%)."),
              .double(nil), .double(0.6)),
        entry(.tuilage, "tiling", "smart_gaps_solo", tr("Marges en fenêtre unique", "Gaps with a single window"),
              tr("Retire les marges quand une seule fenêtre est affichée.", "Removes the gaps when only one window is shown."), .bool, .bool(false)),
        entry(.tuilage, "tiling", "popup_filter", tr("Ignorer les fenêtres temporaires", "Ignore transient windows"),
              tr("Garde hors du tuilage les infobulles et les menus contextuels.", "Keeps tooltips and context menus out of tiling."), .bool, .bool(true)),
        readOnlyEntry(.tuilage, "tiling", "smart_gaps_solo_sides", tr("Côtés sans marge pour une fenêtre seule", "Sides without a gap for a single window"),
                      tr("Liste des côtés (top, right, bottom, left) où la marge disparaît.", "List of sides (top, right, bottom, left) where the gap disappears.")),
        readOnlyEntry(.tuilage, "tiling", "allowed_subroles", tr("Types de fenêtres tuilées", "Tiled window types"),
                      tr("Liste des sous-rôles d'accessibilité acceptés par le tuilage.", "List of accessibility subroles accepted by tiling.")),
        readOnlyEntry(.tuilage, "tiling", "display_overrides", tr("Marges par écran", "Gaps per display"),
                      tr("Tableau de marges extérieures propres à chaque écran.", "Table of outer gaps specific to each display.")),
        entry(.tuilage, "window_placement", "new_apps_target", tr("Écran des nouvelles fenêtres", "Display for new windows"),
              tr("Par défaut, les nouvelles fenêtres rejoignent le stage courant de l’écran actif, même si la souris est ailleurs. Utile avec ⌘N. Ce choix peut aussi améliorer la réactivité en limitant les déplacements et les réorganisations entre écrans. Les autres choix suivent la souris ou le placement de macOS.", "By default, new windows join the current stage of the active display, even if the mouse is elsewhere. Useful with ⌘N. This choice can also improve responsiveness by limiting moves and rearrangements between displays. The other choices follow the mouse or macOS placement."),
              .choice(["focused_display", "mouse", "macos"]), .string("focused_display")),
        entry(.tuilage, "window_placement", "new_window_side", tr("Insertion des nouvelles fenêtres", "New window insertion"),
              tr("Côté où apparaît une nouvelle fenêtre par rapport à la fenêtre active, en mode spatialBsp.", "Side where a new window appears relative to the active window, in spatialBsp mode."),
              .choice(["right", "left"]), .string("right")),
        entry(.tuilage, "width_adjustment", "nudge_step", tr("Pas d'ajustement de largeur", "Width adjustment step"),
              tr("Variation de largeur à chaque pression d'un raccourci (0,05 = 5 %).", "Width change for each press of a shortcut (0.05 = 5%)."), .double(nil), .double(0.05)),
        entry(.tuilage, "width_adjustment", "minimum_ratio", tr("Largeur minimale", "Minimum width"),
              tr("Plus petite largeur autorisée, en proportion de la largeur de base.", "Smallest allowed width, as a share of the base width."), .double(nil), .double(0.25)),
        entry(.tuilage, "width_adjustment", "maximum_ratio", tr("Largeur maximale", "Maximum width"),
              tr("Plus grande largeur autorisée, en proportion de la largeur de base. Doit rester au moins égale à la largeur minimale.", "Largest allowed width, as a share of the base width. Must be at least the minimum width."),
              .double(nil), .double(1.5)),
        readOnlyEntry(.tuilage, "width_adjustment", "presets", tr("Largeurs prédéfinies", "Preset widths"),
                      tr("Liste des proportions proposées par les raccourcis de largeur.", "List of shares offered by the width shortcuts.")),
    ]
}

// MARK: - Stages, focus

extension SettingsCatalog {
    static let stageDescriptors: [SettingDescriptor] = [
        entry(.stages, "stage_manager", "default_stage", tr("Stage par défaut", "Default stage"),
              tr("Identifiant du stage actif sur un écran neuf.", "Identifier of the active stage on a new display."), .text, .string("1")),
        readOnlyEntry(.stages, "stage_manager", "workspaces", tr("Noms des stages", "Stage names"),
                      tr("Noms des stages. Retirer une définition ne supprime ni le stage ni les fenêtres déjà conservés.", "Stage names. Removing a definition deletes neither the stage nor the windows already kept.")),
    ]

    static let focusDescriptors: [SettingDescriptor] = [
        entry(.focus, "focus", "stage_follows_focus", tr("Le stage suit le focus", "Stage follows focus"),
              tr("Affiche le stage d'une fenêtre quand elle reçoit le focus.", "Shows a window's stage when the window gets focus."), .bool, .bool(true)),
        entry(.focus, "focus", "assign_follows_focus", tr("Le focus suit l'assignation", "Focus follows assignment"),
              tr("Donne le focus à une fenêtre après son envoi vers un autre stage.", "Focuses a window after it is sent to another stage."), .bool, .bool(false)),
        entry(.focus, "focus", "stage_move_follows_focus", tr("Le déplacement de stage suit le focus", "Stage move follows focus"),
              tr("Affiche le nouveau stage quand une fenêtre y est déplacée.", "Shows the new stage when a window is moved to it."), .bool, .bool(true)),
        entry(.focus, "focus", "focus_follows_mouse", tr("Le focus suit la souris", "Focus follows mouse"),
              tr("Donne le focus à la fenêtre sous le pointeur.", "Focuses the window under the pointer."), .bool, .bool(false)),
        entry(.focus, "focus", "mouse_follows_focus", tr("La souris suit le focus", "Mouse follows focus"),
              tr("Déplace le pointeur sur la fenêtre qui reçoit le focus.", "Moves the pointer to the window that gets focus."), .bool, .bool(false)),
    ]
}

// MARK: - Bordures

extension SettingsCatalog {
    // Les libellés « bordure » ne servent qu'ici : la recherche « bordure » ne doit trouver que ces réglages.
    static let borderDescriptors: [SettingDescriptor] = [
        entry(.bordures, "fx.borders", "enabled", tr("Afficher les bordures", "Show borders"),
              tr("Dessine une bordure autour des fenêtres.", "Draws a border around windows."), .bool, .bool(false)),
        entry(.bordures, "fx.borders", "thickness", tr("Épaisseur de la bordure (points)", "Border width (points)"),
              tr("Épaisseur du trait de la bordure.", "Thickness of the border line."), .double(nil), .double(2)),
        entry(.bordures, "fx.borders", "corner_radius", tr("Arrondi de la bordure (points)", "Border corner radius (points)"),
              tr("Rayon des angles de la bordure.", "Radius of the border corners."), .double(nil), .double(10)),
        entry(.bordures, "fx.borders", "active_color", tr("Couleur de la bordure active", "Active border color"),
              tr("Couleur de la bordure de la fenêtre qui a le focus.", "Border color of the focused window."), .color, .string("#7AA2F7")),
        entry(.bordures, "fx.borders", "inactive_color", tr("Couleur de la bordure inactive", "Inactive border color"),
              tr("Couleur de la bordure des autres fenêtres.", "Border color of the other windows."), .color, .string("#414868")),
        entry(.bordures, "fx.borders", "pulse_on_focus", tr("Pulsation de la bordure au focus", "Border pulse on focus"),
              tr("Fait pulser la bordure quand une fenêtre reçoit le focus.", "Pulses the border when a window gets focus."), .bool, .bool(false)),
        readOnlyEntry(.bordures, "fx.borders", "stage_overrides", tr("Couleur de contour par stage", "Outline color per stage"),
                      tr("Tableau de couleurs propres à certains stages.", "Table of colors specific to some stages.")),
    ]
}

// MARK: - Mode lettres et recherche

extension SettingsCatalog {
    static let targetModeDescriptors: [SettingDescriptor] = [
        entry(.lettres, "experimental.target_mode", "enabled", tr("Activer le mode lettres", "Turn on letter mode"),
              tr("Active les étiquettes à lettres pour atteindre fenêtres et stages au clavier.", "Turns on letter labels to reach windows and stages from the keyboard."), .bool, .bool(true)),
        entry(.lettres, "experimental.target_mode", "picker_enabled", tr("Sélecteur de cibles", "Target picker"),
              tr("Autorise la sélection d'une cible en tapant sa lettre.", "Lets you pick a target by typing its letter."), .bool, .bool(true)),
        entry(.lettres, "experimental.target_mode", "overlay_enabled", tr("Afficher les étiquettes en continu", "Keep labels shown"),
              tr("Montre les étiquettes à l'écran pendant quelques secondes.", "Shows the labels on screen for a few seconds."), .bool, .bool(false)),
        entry(.lettres, "experimental.target_mode", "overlay_labels_only", tr("Étiquettes seules", "Labels only"),
              tr("N'affiche que les étiquettes, sans cadre autour des cibles.", "Shows only the labels, without a frame around targets."), .bool, .bool(true)),
        entry(.lettres, "experimental.target_mode", "overlay_duration_seconds", tr("Durée d'affichage (secondes)", "Display time (seconds)"),
              tr("Temps pendant lequel les étiquettes restent visibles.", "How long the labels stay visible."), .double(0.2...30), .double(3)),
        entry(.lettres, "experimental.target_mode", "app_mouse_actions_enabled", tr("Actions de souris", "Mouse actions"),
              tr("Autorise le clic et le double-clic sur les éléments d'une application.", "Allows click and double-click on an app's elements."), .bool, .bool(false)),
        entry(.lettres, "experimental.target_mode", "scroll_mode_enabled", tr("Mode défilement", "Scroll mode"),
              tr("Autorise le défilement au clavier dans le mode lettres.", "Allows keyboard scrolling in letter mode."), .bool, .bool(false)),
        entry(.lettres, "experimental.target_mode", "label_font_size", tr("Taille des étiquettes (points)", "Label size (points)"),
              tr("Taille du texte des étiquettes du mode lettres, indépendante de la recherche.", "Text size of letter-mode labels, independent of search."), .double(8...48), .double(13)),
        entry(.recherche, "experimental.target_mode", "search_label_font_size", tr("Étiquettes de recherche (points)", "Search labels (points)"),
              tr("Taille des lettres sur les résultats de recherche.", "Size of the letters on search results."), .double(8...48), .double(13)),
        entry(.recherche, "experimental.target_mode", "search_text_font_size", tr("Texte de la barre de recherche (points)", "Search bar text (points)"),
              tr("Taille de la saisie et du nombre de correspondances. La barre suit cette taille.", "Size of the typed text and the match count. The bar follows this size."), .double(8...48), .double(15)),
        entry(.recherche, "experimental.target_mode", "command_text_font_size", tr("Texte des suggestions (points)", "Suggestion text (points)"),
              tr("Taille de la liste et des messages après la saisie de /, indépendante de la barre.", "Size of the list and messages after typing /, independent of the bar."), .double(8...48), .double(13)),
        entry(.raccourcis, "experimental.target_mode", "search_hotkey", tr("Raccourci de la recherche", "Search shortcut"),
              tr("Raccourci global qui ouvre la recherche, par exemple command+control+alt+f. Vide : désactivé.", "Global shortcut that opens search, for example command+control+alt+f. Empty: off."),
              .text, .string("command+control+alt+f")),
        entry(.raccourcis, "experimental.target_mode", "actions_hotkey", tr("Raccourci des verbes de la fenêtre active", "Active window verbs shortcut"),
              tr("Ouvre la barre directement sur les verbes de la fenêtre au premier plan : envoyer, flotter, plein écran. Vide : désactivé.", "Opens the bar directly on the verbs of the frontmost window: send, float, full screen. Empty: off."),
              .text, .string("command+control+alt+shift+f")),
        entry(.raccourcis, "experimental.target_mode", "screen_search_hotkey", tr("Raccourci de la recherche à l'écran", "On-screen search shortcut"),
              tr("Ouvre la barre sans la liste du lanceur : les éléments visibles qui correspondent reçoivent une étiquette, Retour clique. ", "Opens the bar without the launcher list: matching visible elements get a label, Return clicks. ")
              + tr("Par exemple command+control+alt+f (Capslock + F). Vide : désactivé.", "For example command+control+alt+f (Capslock + F). Empty: off."),
              .text, .string("")),
        entry(.recherche, "experimental.target_mode", "web_search_url", tr("Recherche web (⌃ Retour)", "Web search (⌃ Return)"),
              tr("Adresse ouverte par ⌃ Retour dans la barre ; {query} reçoit le texte tapé.", "Address opened by ⌃ Return in the bar; {query} receives the typed text."),
              .text, .string("https://www.google.com/search?q={query}")),
        entry(.raccourcis, "experimental.target_mode", "pick_modifier", tr("Touche des raccourcis 1 à 9", "Key for shortcuts 1 to 9"),
              tr("Touche tenue avec un chiffre pour ouvrir une ligne de la barre : command (⌘), shift (⇧), alt (⌥) ou control (⌃). Avec shift, les chiffres de la rangée du haut ne s'écrivent plus dans la recherche en AZERTY.", "Key held with a digit to open a row of the bar: command (⌘), shift (⇧), alt (⌥) or control (⌃). With shift, top-row digits no longer type into search on AZERTY keyboards."),
              .choice(["command", "shift", "alt", "control"]), .string("command")),
        // Session 131 : listes « Action Modifiers » d'Alfred.
        entry(.recherche, "experimental.target_mode", "return_cmd", tr("⌘ Retour", "⌘ Return"),
              tr("Ce que fait Retour avec la touche Commande tenue dans la barre ; la ligne choisie l'annonce.",
                 "What Return does with Command held in the bar; the selected row announces it."),
              .choice(TargetModeConfig.returnEffects), .string("new-stage")),
        entry(.recherche, "experimental.target_mode", "return_alt", tr("⌥ Retour", "⌥ Return"),
              tr("Ce que fait Retour avec la touche Option tenue dans la barre ; la ligne choisie l'annonce.",
                 "What Return does with Option held in the bar; the selected row announces it."),
              .choice(TargetModeConfig.returnEffects), .string("here")),
        entry(.recherche, "experimental.target_mode", "return_ctrl", tr("⌃ Retour", "⌃ Return"),
              tr("Ce que fait Retour avec la touche Contrôle tenue dans la barre ; la ligne choisie l'annonce.",
                 "What Return does with Control held in the bar; the selected row announces it."),
              .choice(TargetModeConfig.returnEffects), .string("web")),
        entry(.recherche, "experimental.target_mode", "workflow_view_style", tr("Style des fenêtres de workflow", "Workflow window style"),
              tr("Apparence des vues Texte, Image et PDF des workflows et du navigateur SF Symbols, comme les styles d'Alfred 6 : verre sombre, aplat sombre ou verre clair.",
                 "Look of the Text, Image and PDF workflow views and of the SF Symbols browser, like Alfred 6 styles: dark glass, flat dark or light glass."),
              .choice(TargetModeConfig.workflowViewStyles), .string("system")),
        entry(.raccourcis, "experimental.target_mode", "view_cycle_hotkey", tr("Touche des présentations", "View key"),
              tr("Dans la barre, fait passer les résultats d'un workflow, d'un dossier ou les fichiers de la liste à la grille, puis aux grandes tuiles. Le chip à droite de la saisie fait de même. Vide : désactivée.", "In the bar, switches the results of a workflow, a folder or files from list to grid, then to large tiles. The chip on the right of the field does the same. Empty: off."),
              .text, .string("command+g")),
        entry(.recherche, "experimental.target_mode", "workflows_enabled", tr("Workflows dans la barre", "Workflows in the bar"),
              tr("Mots-clés et listes des workflows au format d'Alfred dans la barre. Un workflow tourne avec les droits de Roadie : n'installez que ceux que vous connaissez.", "Keywords and lists of Alfred-format workflows in the bar. A workflow runs with Roadie's permissions: only install workflows you trust."),
              .bool, .bool(true)),
        entry(.recherche, "experimental.target_mode", "alfred_workflows", tr("Workflows installés dans Alfred", "Workflows installed in Alfred"),
              tr("Lit aussi, sans les modifier, les workflows installés dans Alfred. Ceux de ~/.config/roadies/workflows restent lus.", "Also reads the workflows installed in Alfred, without changing them. Those in ~/.config/roadies/workflows are still read."),
              .bool, .bool(true)),
        entry(.recherche, "experimental.target_mode", "idle_frequent_enabled", tr("Barre vide : Souvent ici", "Empty bar: Often here"),
              tr("Avant la saisie, propose les applications que vous ouvrez le plus souvent depuis la stage active.", "Before you type, suggests the apps you open most often from the active stage."),
              .bool, .bool(true)),
        entry(.recherche, "experimental.target_mode", "launcher_on_screen", tr("Éléments à l'écran dans le lanceur", "On-screen elements in the launcher"),
              tr("Le lanceur lit aussi les boutons et textes visibles (section « À l'écran »). Coupé, il ne cherche que ", "The launcher also reads visible buttons and text (“On screen” section). Off, it only searches ")
              + tr("applications, fenêtres, stages et fichiers ; la recherche à l'écran garde son propre raccourci.", "apps, windows, stages and files; on-screen search keeps its own shortcut."),
              .bool, .bool(true)),
        entry(.recherche, "experimental.target_mode", "typo_max_errors", tr("Fautes de frappe rattrapées", "Typos forgiven"),
              tr("Sans correspondance exacte, la recherche à l'écran et la section « Vouliez-vous dire » du lanceur admettent ", "Without an exact match, on-screen search and the launcher's “Did you mean” section allow ")
              + tr("des fautes : une à partir de 4 lettres, deux à partir de 8, au plus ce nombre. 0 : coupé.", "typos: one from 4 letters, two from 8, at most this number. 0: off."),
              .int(0...2), .int(2)),
        entry(.recherche, "experimental.target_mode", "idle_frequent_count", tr("Souvent ici : nombre de lignes", "Often here: number of rows"),
              tr("Nombre d'applications proposées dans « Souvent ici ».", "Number of apps suggested in “Often here”."), .int(1...10), .int(3)),
        entry(.recherche, "experimental.target_mode", "idle_recent_searches_enabled", tr("Barre vide : Recherches récentes", "Empty bar: Recent searches"),
              tr("Avant la saisie, propose vos dernières recherches qui ont mené à une action.", "Before you type, suggests your latest searches that led to an action."),
              .bool, .bool(true)),
        entry(.recherche, "experimental.target_mode", "idle_recent_searches_count", tr("Recherches récentes : nombre de lignes", "Recent searches: number of rows"),
              tr("Nombre de recherches proposées. Roadie garde les 20 dernières.", "Number of searches suggested. Roadie keeps the last 20."), .int(1...20), .int(3)),
        entry(.recherche, "experimental.target_mode", "theme", tr("Thème de la barre", "Bar theme"),
              tr("Aspect de la barre : Roadie, ou l'un des thèmes d'Alfred (couleurs, polices, flou, largeur). Un thème exporté d'Alfred (.alfredappearance) placé dans ~/.config/roadies/themes, ou créé dans Alfred, s'ajoute à la liste au prochain lancement. Un thème autre que Roadie apporte ses tailles de texte.", "Look of the bar: Roadie, or one of Alfred's themes (colors, fonts, blur, width). A theme exported from Alfred (.alfredappearance) placed in ~/.config/roadies/themes, or created in Alfred, joins the list at the next launch. A theme other than Roadie brings its own text sizes."),
              .choice(LauncherThemeCatalog.all().map(\.id)), .string("roadie")),
        entry(.recherche, "experimental.target_mode", "theme_dark", tr("Thème en mode sombre", "Dark mode theme"),
              tr("Thème utilisé quand macOS est en mode sombre, comme le réglage d'Alfred. « Comme le thème clair » garde le même thème.", "Theme used when macOS is in dark mode, like Alfred's setting. “Same as the light theme” keeps the same theme."),
              .choice([""] + LauncherThemeCatalog.all().map(\.id)), .string("")),
        entry(.recherche, "experimental.target_mode", "visible_results", tr("Nombre de résultats montrés", "Number of results shown"),
              tr("Lignes de résultats visibles sous la saisie ; les autres défilent. 0 : autant que la place de l'écran.", "Result rows visible under the field; the others scroll. 0: as many as the display allows."),
              .int(0...20), .int(0)),
        entry(.recherche, "experimental.target_mode", "bar_screen", tr("Écran de la barre", "Bar display"),
              tr("Écran où la barre s'ouvre : celui de la souris, celui de la fenêtre active, ou l'écran principal.", "Display where the bar opens: the one with the mouse, the one with the active window, or the main display."),
              .choice(TargetModeConfig.barScreens), .string("mouse")),
        entry(.recherche, "experimental.target_mode", "bar_position", tr("Place de la barre", "Bar position"),
              tr("Place par défaut : en bas avec la liste au-dessus, au centre, ou en haut avec la liste dessous comme Alfred.", "Default position: bottom with the list above, center, or top with the list below like Alfred."),
              .choice(TargetModeConfig.barPositions), .string("bottom")),
        entry(.recherche, "experimental.target_mode", "bar_save_position", tr("Retenir la place de la barre", "Remember the bar position"),
              tr("Glissez la barre par son bord ou le fond de la liste : elle garde cette place aux ouvertures suivantes. Un double-clic sur le bord la remet à sa place par défaut.", "Drag the bar by its edge or the list background: it keeps that place next time. A double-click on the edge puts it back in its default place."),
              .bool, .bool(true)),
        entry(.recherche, "experimental.target_mode", "terminal_app", tr("Terminal de >", "Terminal for >"),
              tr("Tapez > puis une commande dans la barre : Retour la lance dans une nouvelle fenêtre de ce terminal, depuis votre dossier personnel. Warp ne reçoit pas de commande : il s'ouvre et la commande est copiée.", "Type > then a command in the bar: Return runs it in a new window of this terminal, from your home folder. Warp does not accept commands: it opens and the command is copied."),
              .choice(TargetModeConfig.terminalApps), .string("terminal")),
        entry(.recherche, "experimental.target_mode", "bookmarks_enabled", tr("Signets des navigateurs", "Browser bookmarks"),
              tr("Les signets de Firefox, Safari et Chrome apparaissent dans la barre dès deux lettres, avec l'icône du site. Les mots-clés de Firefox (« w » + texte) servent aussi de recherches. Safari demande l'accès complet au disque pour Roadie.", "Firefox, Safari and Chrome bookmarks appear in the bar from two letters, with the site icon. Firefox keywords (“w” + text) also work as searches. Safari requires Full Disk Access for Roadie."),
              .bool, .bool(true)),
        readOnlyEntry(.recherche, "experimental.target_mode", "bookmark_browsers", tr("Navigateurs dont les signets sont lus", "Browsers whose bookmarks are read"),
                      tr("Firefox (tous les profils), Safari, Chrome, Brave ou Edge.", "Firefox (all profiles), Safari, Chrome, Brave or Edge.")),
        readOnlyEntry(.recherche, "experimental.target_mode", "app_search_paths", tr("Dossiers d'applications ajoutés", "Extra app folders"),
                      tr("Dossiers parcourus en plus des dossiers d'applications de macOS (un niveau de sous-dossier), par exemple ~/Applications/Chrome Apps.localized. Pris en compte à la prochaine ouverture de la barre.", "Folders scanned in addition to the macOS app folders (one level of subfolders), for example ~/Applications/Chrome Apps.localized. Applied the next time the bar opens.")),
        entry(.recherche, "experimental.target_mode", "path_sort", tr("Ordre des éléments d'un dossier tapé", "Order of items in a typed folder"),
              tr("Quand vous tapez un chemin (~/ ou /) : par nom, ou les plus récents d'abord. Les dossiers restent en tête. ⌫ à la fin d'un chemin remonte d'un dossier.", "When you type a path (~/ or /): by name, or most recent first. Folders stay on top. ⌫ at the end of a path goes up one folder."),
              .choice(TargetModeConfig.pathSorts), .string("name")),
        entry(.recherche, "experimental.target_mode", "learning_enabled", tr("Apprendre vos choix", "Learn your choices"),
              tr("Les résultats que vous choisissez souvent passent en tête. Désactivé : ordre sans apprentissage et rien n'est enregistré. « roadie launcher reset » efface ce qui a été appris.", "Results you often choose move to the top. Off: order without learning, and nothing is recorded. “roadie launcher reset” erases what was learned."),
              .bool, .bool(true)),
        entry(.recherche, "experimental.target_mode", "confirm_quit_all", tr("Confirmer « Tout quitter »", "Confirm “Quit all”"),
              tr("La commande système « Tout quitter » demande un second Retour. Redémarrer, Éteindre, Fermer la session et Vider la corbeille le demandent toujours.", "The “Quit all” system command asks for a second Return. Restart, Shut down, Log out and Empty trash always ask."),
              .bool, .bool(true)),
        entry(.recherche, "experimental.target_mode", "calc_opens_calculator", tr("Calcul : ouvrir aussi Calculette", "Calculation: also open Calculator"),
              tr("Retour sur un calcul copie toujours le résultat. Activé : il ouvre aussi Calculette, ou va à sa fenêtre déjà ouverte ; ⌘V y colle le résultat. ⌘C copie sans ouvrir.", "Return on a calculation always copies the result. On: it also opens Calculator, or goes to its open window; ⌘V pastes the result there. ⌘C copies without opening."),
              .bool, .bool(false)),
        entry(.recherche, "experimental.target_mode", "learn_verb_order", tr("Verbes : ordre appris", "Verbs: learned order"),
              tr("Après Tab, les verbes que vous choisissez le plus pour un type d'objet (application, fichier, fenêtre, stage…) passent en tête. Désactivé : ordre fixe. Suit aussi « Apprendre vos choix ».", "After Tab, the verbs you choose most for a type of item (app, file, window, stage…) move to the top. Off: fixed order. Also follows “Learn your choices”."),
              .bool, .bool(true)),
        entry(.recherche, "experimental.target_mode", "content_search_keyword", tr("Mot-clé : chercher dans le contenu", "Keyword: search file contents"),
              tr("Mot-clé suivi d'une espace puis de mots (« in facture ») : fichiers dont le texte contient ces mots, par Spotlight. Vide : désactivé.", "Keyword followed by a space and words (“in invoice”): files whose text contains these words, through Spotlight. Empty: off."),
              .text, .string("in")),
        entry(.recherche, "experimental.target_mode", "tag_search_keyword", tr("Mot-clé : chercher par étiquette", "Keyword: search by tag"),
              tr("Mot-clé suivi d'une espace puis d'une étiquette du Finder (« tags rouge », « tags projet ») : fichiers et dossiers qui la portent. Les couleurs se tapent en français ou en anglais. Vide : désactivé.", "Keyword followed by a space and a Finder tag (“tags red”, “tags project”): files and folders that have it. Colors can be typed in English or French. Empty: off."),
              .text, .string("tags")),
        entry(.recherche, "experimental.target_mode", "web_history_days", tr("Historique des navigateurs : jours", "Browser history: days"),
              tr("Pages déjà vues dans les navigateurs des signets, proposées sous « Historique » dès deux lettres (titre ou adresse). Nombre de jours couverts ; 0 : désactivé. Safari demande l'accès complet au disque pour Roadie.", "Pages already visited in the bookmark browsers, suggested under “History” from two letters (title or address). Number of days covered; 0: off. Safari requires Full Disk Access for Roadie."),
              .int(0...365), .int(90)),
        entry(.recherche, "experimental.target_mode", "settings_in_search", tr("Réglages dans la barre", "Settings in the bar"),
              tr("Les pages et réglages des Paramètres de Roadie (« rail », « thème ») et les panneaux des Réglages Système (« clavier », « Wi-Fi ») apparaissent sous « Réglages » dès deux lettres. Retour les ouvre.", "Pages and settings of Roadie Settings (“rail”, “theme”) and System Settings panes (“keyboard”, “Wi-Fi”) appear under “Settings” from two letters. Return opens them."),
              .bool, .bool(true)),
        entry(.recherche, "experimental.target_mode", "open_keyword", tr("Mot-clé : ouvrir un fichier", "Keyword: open a file"),
              tr("Mot-clé suivi d'une espace puis d'un nom (« open devis ») : seuls les fichiers sont montrés ; Retour ouvre. Vide : désactivé.", "Keyword followed by a space and a name (“open quote”): only files are shown; Return opens. Empty: off."),
              .text, .string("open")),
        entry(.recherche, "experimental.target_mode", "find_keyword", tr("Mot-clé : montrer dans le Finder", "Keyword: reveal in Finder"),
              tr("Mot-clé suivi d'une espace puis d'un nom (« find devis ») : seuls les fichiers sont montrés ; Retour les montre dans le Finder. Vide : désactivé.", "Keyword followed by a space and a name (“find quote”): only files are shown; Return reveals them in Finder. Empty: off."),
              .text, .string("find")),
        readOnlyEntry(.recherche, "experimental.target_mode", "file_types", tr("Types de fichiers ajoutés", "Extra file types"),
                      tr("Types de macOS (UTI) cherchés en plus des dossiers, documents, textes, images, PDF, tableurs et présentations : par exemple public.archive (archives) ou com.apple.applescript.script (AppleScripts). Un type couvre aussi ses sous-types.", "macOS types (UTI) searched in addition to folders, documents, text, images, PDF, spreadsheets and presentations: for example public.archive (archives) or com.apple.applescript.script (AppleScripts). A type also covers its subtypes.")),
        readOnlyEntry(.recherche, "experimental.target_mode", "file_excluded_folders", tr("Dossiers écartés de la recherche", "Folders excluded from search"),
                      tr("Dossiers dont les fichiers ne sortent jamais dans la barre, par exemple ~/Downloads/Archives. Le reste de ~/Library, les éléments cachés et node_modules restent toujours écartés.", "Folders whose files never show in the bar, for example ~/Downloads/Archives. The rest of ~/Library, hidden items and node_modules are always excluded.")),
        entry(.recherche, "experimental.target_mode", "calc_decimal", tr("Calcul : séparateur décimal", "Calculation: decimal separator"),
              tr("Séparateur du résultat d'un calcul : celui des réglages de macOS, le point ou la virgule. La saisie accepte toujours les deux.", "Separator of a calculation result: the one in macOS settings, the period or the comma. Input always accepts both."),
              .choice(TargetModeConfig.calcDecimals), .string("system")),
        entry(.recherche, "experimental.target_mode", "calc_grouping", tr("Calcul : séparer les milliers", "Calculation: group thousands"),
              tr("Le résultat d'un calcul sépare les milliers (12 345,6), aussi dans ce qui est copié.", "A calculation result groups thousands (12,345.6), also in what is copied."),
              .bool, .bool(false)),
        entry(.recherche, "experimental.target_mode", "show_scrollbar", tr("Barre de défilement", "Scroll bar"),
              tr("Montre à droite de la liste une barre qui indique la place des lignes visibles quand il y a plus de résultats que de place.", "Shows a bar on the right of the list that marks the position of the visible rows when there are more results than room."),
              .bool, .bool(false)),
    ]

    static let appTargetDescriptors: [SettingDescriptor] = [
        entry(.lettres, "experimental.app_targets", "enabled", tr("Cibles dans les applications", "Targets in apps"),
              tr("Étiquette aussi les boutons et les liens des applications.", "Also labels the buttons and links of apps."), .bool, .bool(false)),
        entry(.lettres, "experimental.app_targets", "scope", tr("Étendue des cibles", "Target scope"),
              tr("« frontmost_window » : fenêtre active ; « visible_windows » : toutes les fenêtres visibles.", "“frontmost_window”: active window; “visible_windows”: all visible windows."),
              .choice(["frontmost_window", "visible_windows"]), .string("frontmost_window")),
        entry(.lettres, "experimental.app_targets", "max_targets", tr("Nombre maximal de cibles", "Maximum number of targets"),
              tr("Au-delà, les cibles en trop sont ignorées.", "Beyond this, extra targets are ignored."), .int(1...500), .int(150)),
        entry(.lettres, "experimental.app_targets", "timeout_ms", tr("Délai de lecture (ms)", "Read timeout (ms)"),
              tr("Temps maximal accordé à la lecture des éléments d'une application.", "Maximum time allowed to read an app's elements."), .int(10...2000), .int(120)),
        entry(.lettres, "experimental.app_targets", "hint_characters", tr("Lettres des étiquettes", "Label letters"),
              tr("Caractères utilisés pour les étiquettes. Au moins deux.", "Characters used for labels. At least two."), .text, .string("asdfghjkl")),
        entry(.lettres, "experimental.app_targets", "ax_boost_enabled", tr("Accessibilité renforcée", "Enhanced accessibility"),
              tr("Demande à certaines applications d'exposer plus d'éléments.", "Asks some apps to expose more elements."), .bool, .bool(false)),
        entry(.lettres, "experimental.app_targets", "max_depth", tr("Profondeur de lecture", "Read depth"),
              tr("Nombre de niveaux d'éléments explorés dans une fenêtre.", "Number of element levels explored in a window."), .int(1...40), .int(12)),
        readOnlyEntry(.avance, "experimental.app_targets", "include_roles", tr("Rôles d'éléments retenus", "Element roles kept"),
                      tr("Liste des rôles d'accessibilité transformés en cibles.", "List of accessibility roles turned into targets.")),
        readOnlyEntry(.avance, "experimental.app_targets", "additional_boost_bundle_ids", tr("Applications à renforcer en plus", "Extra apps to enhance"),
                      tr("Liste d'identifiants d'applications pour l'accessibilité renforcée.", "List of app identifiers for enhanced accessibility.")),
    ]
}

// MARK: - Grille

extension SettingsCatalog {
    static let targetGridDescriptors: [SettingDescriptor] = {
        let t = "experimental.target_grid"
        return [
            entry(.grille, t, "enabled", tr("Activer la grille", "Turn on the grid"),
                  tr("Active la grille qui sert à cliquer n'importe où avec le clavier.", "Turns on the grid used to click anywhere with the keyboard."), .bool, .bool(false)),
            entry(.grille, t, "mode", tr("Mode de la grille", "Grid mode"),
                  tr("« recursive » affine la zone à chaque touche et attend votre confirmation ; « auto_click » clique seul à la profondeur maximale.", "“recursive” narrows the area with each key and waits for your confirmation; “auto_click” clicks by itself at maximum depth."),
                  .choice(["auto_click", "recursive"]), .string("recursive")),
            entry(.grille, t, "overlay_enabled", tr("Afficher la grille", "Show the grid"),
                  tr("Dessine la grille sur l'écran.", "Draws the grid on the display."), .bool, .bool(true)),
            entry(.grille, t, "overlay_draw_grid", tr("Tracer les lignes", "Draw lines"),
                  tr("Dessine les lignes entre les cellules.", "Draws the lines between cells."), .bool, .bool(true)),
            entry(.grille, t, "overlay_fill_color", tr("Couleur de remplissage", "Fill color"),
                  tr("Couleur de fond des cellules.", "Background color of the cells."), .color, .string("#4DABF7")),
            entry(.grille, t, "overlay_fill_opacity", tr("Opacité du remplissage", "Fill opacity"),
                  tr("0 : transparent, 1 : opaque.", "0: transparent, 1: opaque."), .double(0...1), .double(0.10)),
            entry(.grille, t, "overlay_border_color", tr("Couleur des lignes", "Line color"),
                  tr("Couleur du contour des cellules.", "Outline color of the cells."), .color, .string("#4DABF7")),
            entry(.grille, t, "overlay_border_opacity", tr("Opacité des lignes", "Line opacity"),
                  tr("0 : transparent, 1 : opaque.", "0: transparent, 1: opaque."), .double(0...1), .double(0.55)),
            entry(.grille, t, "overlay_label_color", tr("Couleur du texte des étiquettes", "Label text color"),
                  tr("Couleur des lettres affichées dans la grille.", "Color of the letters shown in the grid."), .color, .string("#FFFFFF")),
            entry(.grille, t, "overlay_label_background_opacity", tr("Opacité du fond des étiquettes", "Label background opacity"),
                  tr("0 : transparent, 1 : opaque.", "0: transparent, 1: opaque."), .double(0...1), .double(0.84)),
            entry(.grille, t, "rows", tr("Nombre de lignes", "Number of rows"),
                  tr("Lignes de la grille. Les lettres doivent suffire pour toutes les cellules.", "Rows of the grid. There must be enough letters for all cells."), .int(2...12), .int(3)),
            entry(.grille, t, "columns", tr("Nombre de colonnes", "Number of columns"),
                  tr("Colonnes de la grille. Les lettres doivent suffire pour toutes les cellules.", "Columns of the grid. There must be enough letters for all cells."), .int(2...12), .int(3)),
            entry(.grille, t, "max_depth", tr("Profondeur maximale", "Maximum depth"),
                  tr("Nombre de subdivisions successives d'une zone.", "Number of successive subdivisions of an area."), .int(1...20), .int(3)),
            entry(.grille, t, "hint_characters", tr("Lettres des étiquettes", "Label letters"),
                  tr("Caractères des cellules. Au moins lignes × colonnes caractères.", "Cell characters. At least rows × columns characters."), .text, .string("azeqsdwxc")),
            entry(.raccourcis, t, "confirm_action_key", tr("Touche de confirmation", "Confirm key"),
                  tr("Touche qui valide l'action dans la zone choisie.", "Key that confirms the action in the chosen area."), .text, .string("space")),
            entry(.raccourcis, t, "reset_key", tr("Touche de remise à zéro", "Reset key"),
                  tr("Touche qui revient à la grille entière.", "Key that goes back to the whole grid."), .text, .string("r")),
            entry(.raccourcis, t, "back_key", tr("Touche de retour", "Back key"),
                  tr("Touche qui revient à la zone précédente.", "Key that goes back to the previous area."), .text, .string("backspace")),
            entry(.raccourcis, t, "exit_key", tr("Touche de sortie", "Exit key"),
                  tr("Touche qui quitte la grille.", "Key that leaves the grid."), .text, .string("escape")),
            entry(.grille, t, "arrow_navigation_enabled", tr("Navigation aux flèches", "Arrow navigation"),
                  tr("Déplace la zone choisie avec les flèches.", "Moves the chosen area with the arrow keys."), .bool, .bool(true)),
            entry(.grille, t, "arrow_edge_behavior", tr("Flèches au bord", "Arrows at the edge"),
                  tr("« clamp » s'arrête au bord ; « wrap » repart du côté opposé.", "“clamp” stops at the edge; “wrap” continues from the opposite side."),
                  .choice(["clamp", "wrap"]), .string("clamp")),
            entry(.grille, t, "action_delay_ms", tr("Délai avant l'action (ms)", "Delay before action (ms)"),
                  tr("Pause entre la dernière touche et l'action.", "Pause between the last key and the action."), .int(0...1000), .int(30)),
            entry(.grille, t, "wake_mouse_pixels", tr("Réveil de la souris (pixels)", "Mouse wake-up (pixels)"),
                  tr("Petit déplacement du pointeur avant l'action, pour réveiller certaines applications.", "Small pointer move before the action, to wake up some apps."), .int(0...20), .int(1)),
            entry(.grille, t, "mouse_follow_grid", tr("La souris suit la grille", "Mouse follows the grid"),
                  tr("Déplace le pointeur au centre de la zone choisie.", "Moves the pointer to the center of the chosen area."), .bool, .bool(false)),
            entry(.grille, t, "focus_follow_grid", tr("Le focus suit la grille", "Focus follows the grid"),
                  tr("Donne le focus à la fenêtre située sous la zone choisie.", "Focuses the window under the chosen area."), .bool, .bool(false)),
            entry(.grille, t, "label_placement", tr("Position des étiquettes", "Label position"),
                  tr("« callout » : étiquette en coin de cellule ; « center » : au centre.", "“callout”: label in the cell corner; “center”: in the center."),
                  .choice(["callout", "center"]), .string("callout")),
            entry(.grille, t, "default_scope", tr("Étendue par défaut", "Default scope"),
                  tr("« display » : tout l'écran ; « focused_window » : la fenêtre active.", "“display”: the whole display; “focused_window”: the active window."),
                  .choice(["display", "focused_window"]), .string("display")),
            entry(.grille, t, "label_font_size", tr("Taille des étiquettes (points)", "Label size (points)"),
                  tr("Taille du texte des étiquettes de la grille.", "Text size of the grid labels."), .double(8...48), .double(13)),
        ]
    }()
}

// MARK: - Avancé et règles

extension SettingsCatalog {
    static let advancedDescriptors: [SettingDescriptor] = {
        let record = "experimental.target_record"
        let menu = "experimental.titlebar_context_menu"
        return [
            entry(.avance, record, "enabled", tr("Activer l'enregistrement", "Turn on recording"),
                  tr("Autorise l'enregistrement des actions au clavier et à la souris.", "Allows recording keyboard and mouse actions."), .bool, .bool(false)),
            entry(.avance, record, "replay_enabled", tr("Activer la relecture", "Turn on replay"),
                  tr("Autorise la relecture d'un enregistrement.", "Allows replaying a recording."), .bool, .bool(false)),
            entry(.avance, record, "directory", tr("Dossier des enregistrements", "Recordings folder"),
                  tr("Dossier où sont rangés les enregistrements.", "Folder where recordings are stored."), .text, .string("~/.local/state/roadies/records")),
            entry(.avance, record, "default_duration_seconds", tr("Durée par défaut (secondes)", "Default duration (seconds)"),
                  tr("Durée d'un enregistrement sans durée précisée. Au plus la durée maximale.", "Duration of a recording with no duration given. At most the maximum duration."), .double(0.5...3600), .double(10)),
            entry(.avance, record, "max_duration_seconds", tr("Durée maximale (secondes)", "Maximum duration (seconds)"),
                  tr("Durée la plus longue d'un enregistrement.", "Longest duration of a recording."), .double(1...3600), .double(120)),
            entry(.avance, record, "max_events", tr("Nombre maximal d'événements", "Maximum number of events"),
                  tr("Au-delà, l'enregistrement s'arrête.", "Beyond this, recording stops."), .int(1...20000), .int(2000)),
            entry(.avance, record, "include_mouse_moves", tr("Enregistrer les mouvements de souris", "Record mouse movements"),
                  tr("Ajoute chaque déplacement du pointeur.", "Adds every pointer move."), .bool, .bool(false)),
            entry(.avance, record, "include_key_events", tr("Enregistrer les touches", "Record keys"),
                  tr("Ajoute les touches pressées.", "Adds the keys pressed."), .bool, .bool(true)),
            entry(.avance, record, "include_ax_context", tr("Enregistrer le contexte d'accessibilité", "Record accessibility context"),
                  tr("Ajoute l'élément visé par chaque action.", "Adds the element targeted by each action."), .bool, .bool(true)),
            entry(.avance, record, "record_text_input", tr("Enregistrer le texte saisi", "Record typed text"),
                  tr("Ajoute le texte tapé. Peut contenir des informations personnelles.", "Adds the typed text. May contain personal information."), .bool, .bool(false)),
            entry(.avance, record, "indicator", tr("Indicateur d'enregistrement", "Recording indicator"),
                  tr("Où signaler qu'un enregistrement est en cours : notification, rail (navrail), les deux ou aucun.", "Where to show that a recording is in progress: notification, rail (navrail), both or none."),
                  .choice(["notification", "navrail", "both", "none"]), .string("notification")),
            entry(.avance, record, "navrail_bottom_offset", tr("Décalage de l'indicateur du rail (points)", "Rail indicator offset (points)"),
                  tr("Distance entre l'indicateur et le bas du rail.", "Distance between the indicator and the bottom of the rail."), .double(0...400), .double(50)),
            entry(.avance, menu, "enabled", tr("Activer le menu de la barre de titre", "Turn on the title bar menu"),
                  tr("Ouvre un menu d'actions par clic droit sur la barre de titre d'une fenêtre.", "Opens an action menu on right-click in a window's title bar."), .bool, .bool(false)),
            entry(.avance, menu, "double_click_maximize", tr("Double-clic sur la barre de titre", "Double-click on the title bar"),
                  tr("Affiche la fenêtre seule, en gardant le rail libre, puis rend la disposition au double-clic suivant. ", "Shows the window alone, keeping the rail free, then restores the layout on the next double-click. ")
                  + tr("N'agit que si macOS ne fait rien de ce double-clic (Bureau et Dock > « Ne rien faire »).", "Only works if macOS does nothing with this double-click (Desktop & Dock > “Do Nothing”)."),
                  .bool, .bool(false)),
            entry(.avance, menu, "height", tr("Hauteur de la zone (points)", "Area height (points)"),
                  tr("Hauteur de la barre de titre qui réagit au clic droit.", "Height of the title bar area that responds to right-click."), .double(12...96), .double(36)),
            entry(.avance, menu, "leading_exclusion", tr("Zone exclue à gauche (points)", "Excluded area on the left (points)"),
                  tr("Largeur ignorée à gauche, pour garder les boutons de la fenêtre.", "Width ignored on the left, to keep the window buttons."), .double(0...240), .double(84)),
            entry(.avance, menu, "trailing_exclusion", tr("Zone exclue à droite (points)", "Excluded area on the right (points)"),
                  tr("Largeur ignorée à droite de la barre de titre.", "Width ignored on the right of the title bar."), .double(0...240), .double(16)),
            entry(.avance, menu, "managed_windows_only", tr("Fenêtres gérées seulement", "Managed windows only"),
                  tr("Limite le menu aux fenêtres gérées par Roadie.", "Limits the menu to windows managed by Roadie."), .bool, .bool(true)),
            entry(.avance, menu, "tile_candidates_only", tr("Fenêtres tuilables seulement", "Tileable windows only"),
                  tr("Limite le menu aux fenêtres que le tuilage peut placer.", "Limits the menu to windows that tiling can place."), .bool, .bool(true)),
            entry(.avance, menu, "include_stage_destinations", tr("Proposer les stages", "Offer stages"),
                  tr("Ajoute au menu les stages de destination.", "Adds destination stages to the menu."), .bool, .bool(true)),
            entry(.avance, menu, "include_desktop_destinations", tr("Proposer les bureaux", "Offer desktops"),
                  tr("Ajoute au menu les bureaux de destination.", "Adds destination desktops to the menu."), .bool, .bool(true)),
            entry(.avance, menu, "include_display_destinations", tr("Proposer les écrans", "Offer displays"),
                  tr("Ajoute au menu les écrans de destination.", "Adds destination displays to the menu."), .bool, .bool(true)),
        ]
    }()

    static let ruleDescriptors: [SettingDescriptor] = [
        readOnlyEntry(.regles, "exclusions", "floating_bundles", tr("Applications toujours flottantes", "Always-floating apps"),
                      tr("Liste d'identifiants d'applications gardées hors du tuilage.", "List of app identifiers kept out of tiling.")),
        readOnlyEntry(.regles, "exclusions", "floating_windows", tr("Fenêtres toujours flottantes", "Always-floating windows"),
                      tr("Fenêtres d'une application gardées hors du tuilage selon leur titre : rappels, boîtes de dialogue, ", "Windows of an app kept out of tiling by their title: reminders, dialogs, ")
                      + tr("palettes. Dans le titre, # remplace un nombre et * n'importe quel texte ; les majuscules ne comptent ", "palettes. In the title, # stands for a number and * for any text; case does not ")
                      + tr("pas. « # Reminder » couvre « 1 Reminder » et « 3 Reminders ». Le menu Fenêtre de la barre de titre ", "matter. “# Reminder” covers “1 Reminder” and “3 Reminders”. The title bar's Window menu ")
                      + tr("ajoute ou retire la fenêtre choisie. `roadie window explain` dit pourquoi une fenêtre est tuilée.", "adds or removes the chosen window. `roadie window explain` tells why a window is tiled.")),
        entry(.regles, "exclusions", "floating_avoid_rail", tr("Fenêtres flottantes hors du rail", "Floating windows clear of the rail"),
              tr("Une fenêtre flottante qui s'ouvre sur le rail est décalée juste à sa droite, sans changer de taille. ", "A floating window that opens over the rail is moved just to its right, without resizing. ")
              + tr("Pour qu'une fenêtre revienne là où vous l'avez laissée, cochez « Retenir la place » sur sa ligne ou sa règle.", "To have a window come back where you left it, tick “Remember its place” on its row or rule."),
              .bool, .bool(true)),
        readOnlyEntry(.regles, "", "rules", tr("Règles de fenêtres", "Window rules"),
                      tr("Tableau de règles qui placent ou excluent des fenêtres selon l'application ou le titre.", "Table of rules that place or exclude windows by app or title.")),
        readOnlyEntry(.regles, "signals", "hooks", tr("Commandes déclenchées par événement", "Event-triggered commands"),
                      tr("Structure avancée connue. Roadie ne l'exécute pas actuellement ; cet éditeur permet de la conserver et de la préparer.", "Known advanced structure. Roadie does not run it yet; this editor lets you keep and prepare it.")),
    ]
}
