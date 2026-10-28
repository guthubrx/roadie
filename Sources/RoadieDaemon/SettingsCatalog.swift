import Foundation
import RoadieCore

// Catalogue des réglages de `roadies.toml` (SPEC-023) : types purs, sans AppKit ni SwiftUI.
// Les libellés, descriptions, défauts et plages ne se déduisent pas du code : ils sont écrits ici
// et vérifiés par `SettingsCatalogTests` contre `RoadieConfig()` et `RailSettings.load(raw:)`.

/// Catégorie de la fenêtre de réglages. La valeur brute est l'identifiant utilisé par `/settings`.
public enum SettingCategory: String, CaseIterable, Sendable {
    case general
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
        case .general: return "Général"
        case .tuilage: return "Tuilage"
        case .stages: return "Stages et bureaux"
        case .lettres: return "Mode lettres"
        case .grille: return "Grille"
        case .recherche: return "Recherche"
        case .rail: return "Rail"
        case .bordures: return "Bordures"
        case .focus: return "Focus et souris"
        case .overview: return "Vue d’ensemble"
        case .selecteur: return "Sélecteur"
        case .regles: return "Règles"
        case .avance: return "Avancé"
        }
    }

    /// Nom de l'icône système (SF Symbols).
    public var symbolName: String {
        switch self {
        case .general: return "gearshape"
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
            if value.isEmpty { return "Comme le thème clair" }
            return LauncherThemeCatalog.all().first { $0.id == value }?.name ?? value
        }
        let label: String
        switch (id, value) {
        case ("target_mode.bar_screen", "mouse"): return "Écran de la souris"
        case ("target_mode.bar_screen", "active"): return "Écran de la fenêtre active"
        case ("target_mode.bar_screen", "main"): return "Écran principal"
        case ("target_mode.bar_position", "bottom"): return "En bas, liste au-dessus"
        case ("target_mode.bar_position", "center"): return "Au centre, liste dessous"
        case ("target_mode.bar_position", "top"): return "En haut, liste dessous (comme Alfred)"
        case ("target_mode.terminal_app", let app): return LauncherTerminal.appName(app)
        case ("target_mode.path_sort", "name"): return "Par nom"
        case ("target_mode.path_sort", "modified"): return "Modifiés récemment d'abord"
        case ("target_mode.path_sort", "created"): return "Créés récemment d'abord"
        case ("overview.presentation", "archipelago"): return "Archipel"
        case ("overview.presentation", "bays"): return "Baies"
        case ("window_placement.new_apps_target", "focused_display"): return "Écran actif (recommandé)"
        case ("window_placement.new_apps_target", "mouse"): return "Écran de la souris"
        case ("window_placement.new_apps_target", "macos"): return "Choix de macOS"
        case ("tiling.default_strategy", "bsp"): label = "Arbre automatique"
        case ("tiling.default_strategy", "spatialBsp"): label = "Arbre persistant"
        case ("tiling.default_strategy", "masterStack"): label = "Fenêtre principale et pile"
        case ("tiling.default_strategy", "float"): label = "Placement libre"
        case ("tiling.split_policy", "largest_dim"): label = "Répartition équilibrée par défaut"
        case ("tiling.split_policy", "balanced"): label = "Répartition équilibrée héritée"
        case ("tiling.split_policy", "dwindle"): label = "Découpage en spirale"
        case ("switcher.style", "thumbnails"): label = "Vignettes"
        case ("switcher.style", "icons"): label = "Icônes"
        case ("switcher.style", "list"): label = "Liste compacte"
        default: return value
        }
        return "\(label) (\(value))"
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
        let needle = TargetHintService.normalized(query)
        guard !needle.isEmpty else { return [] }
        return zip(all, searchTexts).filter { $0.1.contains(needle) }.map(\.0)
    }
}

// MARK: - Fabrique et textes communs

extension SettingsCatalog {
    static let interfaceDescriptors: [SettingDescriptor] = [
        entry(.general, "interface", "settings_text_font_size", "Texte des paramètres (points)",
              "Taille des libellés et des champs. Le changement s'applique immédiatement.", .double(8...32), .double(16)),
        entry(.general, "interface", "settings_help_font_size", "Descriptions des paramètres (points)",
              "Taille des aides et des messages dans les paramètres, indépendante des champs.", .double(8...32), .double(14)),
        entry(.general, "interface", "settings_title_font_size", "Titres des paramètres (points)",
              "Taille des titres de catégorie dans les paramètres.", .double(10...48), .double(22)),
    ]

    static let readOnlyMessage = "lecture seule : modifier le fichier de configuration"

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
        entry(.tuilage, "tiling", key, "Marge extérieure \(side)",
              "Remplace la marge extérieure générale sur ce côté. Sans valeur, la marge générale s'applique.",
              .double(nil), .unset)
    }
}

// MARK: - Tuilage

extension SettingsCatalog {
    static let tilingDescriptors: [SettingDescriptor] = [
        entry(.tuilage, "tiling", "default_strategy", "Méthode de tuilage",
              "Dispose les fenêtres automatiquement en arbre, conserve un arbre ajustable, privilégie une fenêtre principale ou laisse le placement libre.",
              .choice(["bsp", "spatialBsp", "masterStack", "float"]), .string("bsp")),
        entry(.tuilage, "tiling", "split_policy", "Découpage de l'espace",
              "En mode Arbre automatique (bsp), la répartition équilibrée partage le groupe en deux à chaque découpe. La spirale réserve la moitié à la première fenêtre, puis découpe le reste. Sans effet en mode Arbre persistant.",
              .choice(["largest_dim", "balanced", "dwindle"]), .string("largest_dim")),
        entry(.tuilage, "tiling", "resize_handles", "Poignées de redimensionnement",
              "Permet de tirer les séparations entre les fenêtres en mode Arbre persistant. Le redimensionnement par les bords des fenêtres reste disponible.",
              .bool, .bool(true)),
        entry(.tuilage, "tiling", "gaps_outer", "Marge extérieure (points)",
              "Espace entre les fenêtres et le bord de l'écran.", .double(nil), .double(8)),
        gap("gaps_outer_top", "en haut"),
        gap("gaps_outer_right", "à droite"),
        gap("gaps_outer_bottom", "en bas"),
        gap("gaps_outer_left", "à gauche"),
        entry(.tuilage, "tiling", "gaps_inner", "Espace entre les fenêtres (points)",
              "Espace laissé entre deux fenêtres voisines.", .double(nil), .double(4)),
        entry(.tuilage, "tiling", "master_ratio", "Part de la fenêtre principale",
              "Proportion de l'écran donnée à la fenêtre principale en mode maître et pile (0,6 = 60 %).",
              .double(nil), .double(0.6)),
        entry(.tuilage, "tiling", "smart_gaps_solo", "Marges en fenêtre unique",
              "Retire les marges quand une seule fenêtre est affichée.", .bool, .bool(false)),
        entry(.tuilage, "tiling", "popup_filter", "Ignorer les fenêtres temporaires",
              "Garde hors du tuilage les infobulles et les menus contextuels.", .bool, .bool(true)),
        readOnlyEntry(.tuilage, "tiling", "smart_gaps_solo_sides", "Côtés sans marge pour une fenêtre seule",
                      "Liste des côtés (top, right, bottom, left) où la marge disparaît."),
        readOnlyEntry(.tuilage, "tiling", "allowed_subroles", "Types de fenêtres tuilées",
                      "Liste des sous-rôles d'accessibilité acceptés par le tuilage."),
        readOnlyEntry(.tuilage, "tiling", "display_overrides", "Marges par écran",
                      "Tableau de marges extérieures propres à chaque écran."),
        entry(.tuilage, "window_placement", "new_apps_target", "Écran des nouvelles fenêtres",
              "Par défaut, les nouvelles fenêtres rejoignent le stage courant de l’écran actif, même si la souris est ailleurs. Utile avec ⌘N. Ce choix peut aussi améliorer la réactivité en limitant les déplacements et les réorganisations entre écrans. Les autres choix suivent la souris ou le placement de macOS.",
              .choice(["focused_display", "mouse", "macos"]), .string("focused_display")),
        entry(.tuilage, "window_placement", "new_window_side", "Insertion des nouvelles fenêtres",
              "Côté où apparaît une nouvelle fenêtre par rapport à la fenêtre active, en mode spatialBsp.",
              .choice(["right", "left"]), .string("right")),
        entry(.tuilage, "width_adjustment", "nudge_step", "Pas d'ajustement de largeur",
              "Variation de largeur à chaque pression d'un raccourci (0,05 = 5 %).", .double(nil), .double(0.05)),
        entry(.tuilage, "width_adjustment", "minimum_ratio", "Largeur minimale",
              "Plus petite largeur autorisée, en proportion de la largeur de base.", .double(nil), .double(0.25)),
        entry(.tuilage, "width_adjustment", "maximum_ratio", "Largeur maximale",
              "Plus grande largeur autorisée, en proportion de la largeur de base. Doit rester au moins égale à la largeur minimale.",
              .double(nil), .double(1.5)),
        readOnlyEntry(.tuilage, "width_adjustment", "presets", "Largeurs prédéfinies",
                      "Liste des proportions proposées par les raccourcis de largeur."),
    ]
}

// MARK: - Stages, focus

extension SettingsCatalog {
    static let stageDescriptors: [SettingDescriptor] = [
        entry(.stages, "stage_manager", "default_stage", "Stage par défaut",
              "Identifiant du stage actif sur un écran neuf.", .text, .string("1")),
        readOnlyEntry(.stages, "stage_manager", "workspaces", "Noms des stages",
                      "Noms des stages. Retirer une définition ne supprime ni le stage ni les fenêtres déjà conservés."),
    ]

    static let focusDescriptors: [SettingDescriptor] = [
        entry(.focus, "focus", "stage_follows_focus", "Le stage suit le focus",
              "Affiche le stage d'une fenêtre quand elle reçoit le focus.", .bool, .bool(true)),
        entry(.focus, "focus", "assign_follows_focus", "Le focus suit l'assignation",
              "Donne le focus à une fenêtre après son envoi vers un autre stage.", .bool, .bool(false)),
        entry(.focus, "focus", "stage_move_follows_focus", "Le déplacement de stage suit le focus",
              "Affiche le nouveau stage quand une fenêtre y est déplacée.", .bool, .bool(true)),
        entry(.focus, "focus", "focus_follows_mouse", "Le focus suit la souris",
              "Donne le focus à la fenêtre sous le pointeur.", .bool, .bool(false)),
        entry(.focus, "focus", "mouse_follows_focus", "La souris suit le focus",
              "Déplace le pointeur sur la fenêtre qui reçoit le focus.", .bool, .bool(false)),
    ]
}

// MARK: - Bordures

extension SettingsCatalog {
    // Les libellés « bordure » ne servent qu'ici : la recherche « bordure » ne doit trouver que ces réglages.
    static let borderDescriptors: [SettingDescriptor] = [
        entry(.bordures, "fx.borders", "enabled", "Afficher les bordures",
              "Dessine une bordure autour des fenêtres.", .bool, .bool(false)),
        entry(.bordures, "fx.borders", "thickness", "Épaisseur de la bordure (points)",
              "Épaisseur du trait de la bordure.", .double(nil), .double(2)),
        entry(.bordures, "fx.borders", "corner_radius", "Arrondi de la bordure (points)",
              "Rayon des angles de la bordure.", .double(nil), .double(10)),
        entry(.bordures, "fx.borders", "active_color", "Couleur de la bordure active",
              "Couleur de la bordure de la fenêtre qui a le focus.", .color, .string("#7AA2F7")),
        entry(.bordures, "fx.borders", "inactive_color", "Couleur de la bordure inactive",
              "Couleur de la bordure des autres fenêtres.", .color, .string("#414868")),
        entry(.bordures, "fx.borders", "pulse_on_focus", "Pulsation de la bordure au focus",
              "Fait pulser la bordure quand une fenêtre reçoit le focus.", .bool, .bool(false)),
        readOnlyEntry(.bordures, "fx.borders", "stage_overrides", "Couleur de contour par stage",
                      "Tableau de couleurs propres à certains stages."),
    ]
}

// MARK: - Mode lettres et recherche

extension SettingsCatalog {
    static let targetModeDescriptors: [SettingDescriptor] = [
        entry(.lettres, "experimental.target_mode", "enabled", "Activer le mode lettres",
              "Active les étiquettes à lettres pour atteindre fenêtres et stages au clavier.", .bool, .bool(true)),
        entry(.lettres, "experimental.target_mode", "picker_enabled", "Sélecteur de cibles",
              "Autorise la sélection d'une cible en tapant sa lettre.", .bool, .bool(true)),
        entry(.lettres, "experimental.target_mode", "overlay_enabled", "Afficher les étiquettes en continu",
              "Montre les étiquettes à l'écran pendant quelques secondes.", .bool, .bool(false)),
        entry(.lettres, "experimental.target_mode", "overlay_labels_only", "Étiquettes seules",
              "N'affiche que les étiquettes, sans cadre autour des cibles.", .bool, .bool(true)),
        entry(.lettres, "experimental.target_mode", "overlay_duration_seconds", "Durée d'affichage (secondes)",
              "Temps pendant lequel les étiquettes restent visibles.", .double(0.2...30), .double(3)),
        entry(.lettres, "experimental.target_mode", "app_mouse_actions_enabled", "Actions de souris",
              "Autorise le clic et le double-clic sur les éléments d'une application.", .bool, .bool(false)),
        entry(.lettres, "experimental.target_mode", "scroll_mode_enabled", "Mode défilement",
              "Autorise le défilement au clavier dans le mode lettres.", .bool, .bool(false)),
        entry(.lettres, "experimental.target_mode", "label_font_size", "Taille des étiquettes (points)",
              "Taille du texte des étiquettes du mode lettres, indépendante de la recherche.", .double(8...48), .double(13)),
        entry(.recherche, "experimental.target_mode", "search_label_font_size", "Étiquettes de recherche (points)",
              "Taille des lettres sur les résultats de recherche.", .double(8...48), .double(13)),
        entry(.recherche, "experimental.target_mode", "search_text_font_size", "Texte de la barre de recherche (points)",
              "Taille de la saisie et du nombre de correspondances. La barre suit cette taille.", .double(8...48), .double(15)),
        entry(.recherche, "experimental.target_mode", "command_text_font_size", "Texte des suggestions (points)",
              "Taille de la liste et des messages après la saisie de /, indépendante de la barre.", .double(8...48), .double(13)),
        entry(.recherche, "experimental.target_mode", "search_hotkey", "Raccourci de la recherche",
              "Raccourci global qui ouvre la recherche, par exemple command+control+alt+f. Vide : désactivé.",
              .text, .string("command+control+alt+f")),
        entry(.recherche, "experimental.target_mode", "actions_hotkey", "Raccourci des verbes de la fenêtre active",
              "Ouvre la barre directement sur les verbes de la fenêtre au premier plan : envoyer, flotter, plein écran. Vide : désactivé.",
              .text, .string("command+control+alt+shift+f")),
        entry(.recherche, "experimental.target_mode", "web_search_url", "Recherche web (⌃ Retour)",
              "Adresse ouverte par ⌃ Retour dans la barre ; {query} reçoit le texte tapé.",
              .text, .string("https://www.google.com/search?q={query}")),
        entry(.recherche, "experimental.target_mode", "pick_modifier", "Touche des raccourcis 1 à 9",
              "Touche tenue avec un chiffre pour ouvrir une ligne de la barre : command (⌘), shift (⇧), alt (⌥) ou control (⌃). Avec shift, les chiffres de la rangée du haut ne s'écrivent plus dans la recherche en AZERTY.",
              .choice(["command", "shift", "alt", "control"]), .string("command")),
        entry(.recherche, "experimental.target_mode", "view_cycle_hotkey", "Touche des présentations",
              "Dans la barre, fait passer les résultats d'un workflow, d'un dossier ou les fichiers de la liste à la grille, puis aux grandes tuiles. Le chip à droite de la saisie fait de même. Vide : désactivée.",
              .text, .string("command+g")),
        entry(.recherche, "experimental.target_mode", "workflows_enabled", "Workflows dans la barre",
              "Mots-clés et listes des workflows au format d'Alfred dans la barre. Un workflow tourne avec les droits de Roadie : n'installez que ceux que vous connaissez.",
              .bool, .bool(true)),
        entry(.recherche, "experimental.target_mode", "alfred_workflows", "Workflows installés dans Alfred",
              "Lit aussi, sans les modifier, les workflows installés dans Alfred. Ceux de ~/.config/roadies/workflows restent lus.",
              .bool, .bool(true)),
        entry(.recherche, "experimental.target_mode", "idle_frequent_enabled", "Barre vide : Souvent ici",
              "Avant la saisie, propose les applications que vous ouvrez le plus souvent depuis la stage active.",
              .bool, .bool(true)),
        entry(.recherche, "experimental.target_mode", "idle_frequent_count", "Souvent ici : nombre de lignes",
              "Nombre d'applications proposées dans « Souvent ici ».", .int(1...10), .int(3)),
        entry(.recherche, "experimental.target_mode", "idle_recent_searches_enabled", "Barre vide : Recherches récentes",
              "Avant la saisie, propose vos dernières recherches qui ont mené à une action.",
              .bool, .bool(true)),
        entry(.recherche, "experimental.target_mode", "idle_recent_searches_count", "Recherches récentes : nombre de lignes",
              "Nombre de recherches proposées. Roadie garde les 20 dernières.", .int(1...20), .int(3)),
        entry(.recherche, "experimental.target_mode", "theme", "Thème de la barre",
              "Aspect de la barre : Roadie, ou l'un des thèmes d'Alfred (couleurs, polices, flou, largeur). Un thème exporté d'Alfred (.alfredappearance) placé dans ~/.config/roadies/themes, ou créé dans Alfred, s'ajoute à la liste au prochain lancement. Un thème autre que Roadie apporte ses tailles de texte.",
              .choice(LauncherThemeCatalog.all().map(\.id)), .string("roadie")),
        entry(.recherche, "experimental.target_mode", "theme_dark", "Thème en mode sombre",
              "Thème utilisé quand macOS est en mode sombre, comme le réglage d'Alfred. « Comme le thème clair » garde le même thème.",
              .choice([""] + LauncherThemeCatalog.all().map(\.id)), .string("")),
        entry(.recherche, "experimental.target_mode", "visible_results", "Nombre de résultats montrés",
              "Lignes de résultats visibles sous la saisie ; les autres défilent. 0 : autant que la place de l'écran.",
              .int(0...20), .int(0)),
        entry(.recherche, "experimental.target_mode", "bar_screen", "Écran de la barre",
              "Écran où la barre s'ouvre : celui de la souris, celui de la fenêtre active, ou l'écran principal.",
              .choice(TargetModeConfig.barScreens), .string("mouse")),
        entry(.recherche, "experimental.target_mode", "bar_position", "Place de la barre",
              "Place par défaut : en bas avec la liste au-dessus, au centre, ou en haut avec la liste dessous comme Alfred.",
              .choice(TargetModeConfig.barPositions), .string("bottom")),
        entry(.recherche, "experimental.target_mode", "bar_save_position", "Retenir la place de la barre",
              "Glissez la barre par son bord ou le fond de la liste : elle garde cette place aux ouvertures suivantes. Un double-clic sur le bord la remet à sa place par défaut.",
              .bool, .bool(true)),
        entry(.recherche, "experimental.target_mode", "terminal_app", "Terminal de >",
              "Tapez > puis une commande dans la barre : Retour la lance dans une nouvelle fenêtre de ce terminal, depuis votre dossier personnel. Warp ne reçoit pas de commande : il s'ouvre et la commande est copiée.",
              .choice(TargetModeConfig.terminalApps), .string("terminal")),
        entry(.recherche, "experimental.target_mode", "bookmarks_enabled", "Signets des navigateurs",
              "Les signets de Firefox, Safari et Chrome apparaissent dans la barre dès deux lettres, avec l'icône du site. Les mots-clés de Firefox (« w » + texte) servent aussi de recherches. Safari demande l'accès complet au disque pour Roadie.",
              .bool, .bool(true)),
        readOnlyEntry(.recherche, "experimental.target_mode", "bookmark_browsers", "Navigateurs dont les signets sont lus",
                      "Firefox (tous les profils), Safari, Chrome, Brave ou Edge."),
        readOnlyEntry(.recherche, "experimental.target_mode", "app_search_paths", "Dossiers d'applications ajoutés",
                      "Dossiers parcourus en plus des dossiers d'applications de macOS (un niveau de sous-dossier), par exemple ~/Applications/Chrome Apps.localized. Pris en compte à la prochaine ouverture de la barre."),
        entry(.recherche, "experimental.target_mode", "path_sort", "Ordre des éléments d'un dossier tapé",
              "Quand vous tapez un chemin (~/ ou /) : par nom, ou les plus récents d'abord. Les dossiers restent en tête. ⌫ à la fin d'un chemin remonte d'un dossier.",
              .choice(TargetModeConfig.pathSorts), .string("name")),
        entry(.recherche, "experimental.target_mode", "learning_enabled", "Apprendre vos choix",
              "Les résultats que vous choisissez souvent passent en tête. Désactivé : ordre sans apprentissage et rien n'est enregistré. « roadie launcher reset » efface ce qui a été appris.",
              .bool, .bool(true)),
        entry(.recherche, "experimental.target_mode", "confirm_quit_all", "Confirmer « Tout quitter »",
              "La commande système « Tout quitter » demande un second Retour. Redémarrer, Éteindre, Fermer la session et Vider la corbeille le demandent toujours.",
              .bool, .bool(true)),
    ]

    static let appTargetDescriptors: [SettingDescriptor] = [
        entry(.lettres, "experimental.app_targets", "enabled", "Cibles dans les applications",
              "Étiquette aussi les boutons et les liens des applications.", .bool, .bool(false)),
        entry(.lettres, "experimental.app_targets", "scope", "Étendue des cibles",
              "« frontmost_window » : fenêtre active ; « visible_windows » : toutes les fenêtres visibles.",
              .choice(["frontmost_window", "visible_windows"]), .string("frontmost_window")),
        entry(.lettres, "experimental.app_targets", "max_targets", "Nombre maximal de cibles",
              "Au-delà, les cibles en trop sont ignorées.", .int(1...500), .int(150)),
        entry(.lettres, "experimental.app_targets", "timeout_ms", "Délai de lecture (ms)",
              "Temps maximal accordé à la lecture des éléments d'une application.", .int(10...2000), .int(120)),
        entry(.lettres, "experimental.app_targets", "hint_characters", "Lettres des étiquettes",
              "Caractères utilisés pour les étiquettes. Au moins deux.", .text, .string("asdfghjkl")),
        entry(.lettres, "experimental.app_targets", "ax_boost_enabled", "Accessibilité renforcée",
              "Demande à certaines applications d'exposer plus d'éléments.", .bool, .bool(false)),
        entry(.lettres, "experimental.app_targets", "max_depth", "Profondeur de lecture",
              "Nombre de niveaux d'éléments explorés dans une fenêtre.", .int(1...40), .int(12)),
        readOnlyEntry(.avance, "experimental.app_targets", "include_roles", "Rôles d'éléments retenus",
                      "Liste des rôles d'accessibilité transformés en cibles."),
        readOnlyEntry(.avance, "experimental.app_targets", "additional_boost_bundle_ids", "Applications à renforcer en plus",
                      "Liste d'identifiants d'applications pour l'accessibilité renforcée."),
    ]
}

// MARK: - Grille

extension SettingsCatalog {
    static let targetGridDescriptors: [SettingDescriptor] = {
        let t = "experimental.target_grid"
        return [
            entry(.grille, t, "enabled", "Activer la grille",
                  "Active la grille qui sert à cliquer n'importe où avec le clavier.", .bool, .bool(false)),
            entry(.grille, t, "mode", "Mode de la grille",
                  "« recursive » affine la zone à chaque touche et attend votre confirmation ; « auto_click » clique seul à la profondeur maximale.",
                  .choice(["auto_click", "recursive"]), .string("recursive")),
            entry(.grille, t, "overlay_enabled", "Afficher la grille",
                  "Dessine la grille sur l'écran.", .bool, .bool(true)),
            entry(.grille, t, "overlay_draw_grid", "Tracer les lignes",
                  "Dessine les lignes entre les cellules.", .bool, .bool(true)),
            entry(.grille, t, "overlay_fill_color", "Couleur de remplissage",
                  "Couleur de fond des cellules.", .color, .string("#4DABF7")),
            entry(.grille, t, "overlay_fill_opacity", "Opacité du remplissage",
                  "0 : transparent, 1 : opaque.", .double(0...1), .double(0.10)),
            entry(.grille, t, "overlay_border_color", "Couleur des lignes",
                  "Couleur du contour des cellules.", .color, .string("#4DABF7")),
            entry(.grille, t, "overlay_border_opacity", "Opacité des lignes",
                  "0 : transparent, 1 : opaque.", .double(0...1), .double(0.55)),
            entry(.grille, t, "overlay_label_color", "Couleur du texte des étiquettes",
                  "Couleur des lettres affichées dans la grille.", .color, .string("#FFFFFF")),
            entry(.grille, t, "overlay_label_background_opacity", "Opacité du fond des étiquettes",
                  "0 : transparent, 1 : opaque.", .double(0...1), .double(0.84)),
            entry(.grille, t, "rows", "Nombre de lignes",
                  "Lignes de la grille. Les lettres doivent suffire pour toutes les cellules.", .int(2...12), .int(3)),
            entry(.grille, t, "columns", "Nombre de colonnes",
                  "Colonnes de la grille. Les lettres doivent suffire pour toutes les cellules.", .int(2...12), .int(3)),
            entry(.grille, t, "max_depth", "Profondeur maximale",
                  "Nombre de subdivisions successives d'une zone.", .int(1...20), .int(3)),
            entry(.grille, t, "hint_characters", "Lettres des étiquettes",
                  "Caractères des cellules. Au moins lignes × colonnes caractères.", .text, .string("azeqsdwxc")),
            entry(.grille, t, "confirm_action_key", "Touche de confirmation",
                  "Touche qui valide l'action dans la zone choisie.", .text, .string("space")),
            entry(.grille, t, "reset_key", "Touche de remise à zéro",
                  "Touche qui revient à la grille entière.", .text, .string("r")),
            entry(.grille, t, "back_key", "Touche de retour",
                  "Touche qui revient à la zone précédente.", .text, .string("backspace")),
            entry(.grille, t, "exit_key", "Touche de sortie",
                  "Touche qui quitte la grille.", .text, .string("escape")),
            entry(.grille, t, "arrow_navigation_enabled", "Navigation aux flèches",
                  "Déplace la zone choisie avec les flèches.", .bool, .bool(true)),
            entry(.grille, t, "arrow_edge_behavior", "Flèches au bord",
                  "« clamp » s'arrête au bord ; « wrap » repart du côté opposé.",
                  .choice(["clamp", "wrap"]), .string("clamp")),
            entry(.grille, t, "action_delay_ms", "Délai avant l'action (ms)",
                  "Pause entre la dernière touche et l'action.", .int(0...1000), .int(30)),
            entry(.grille, t, "wake_mouse_pixels", "Réveil de la souris (pixels)",
                  "Petit déplacement du pointeur avant l'action, pour réveiller certaines applications.", .int(0...20), .int(1)),
            entry(.grille, t, "mouse_follow_grid", "La souris suit la grille",
                  "Déplace le pointeur au centre de la zone choisie.", .bool, .bool(false)),
            entry(.grille, t, "focus_follow_grid", "Le focus suit la grille",
                  "Donne le focus à la fenêtre située sous la zone choisie.", .bool, .bool(false)),
            entry(.grille, t, "label_placement", "Position des étiquettes",
                  "« callout » : étiquette en coin de cellule ; « center » : au centre.",
                  .choice(["callout", "center"]), .string("callout")),
            entry(.grille, t, "default_scope", "Étendue par défaut",
                  "« display » : tout l'écran ; « focused_window » : la fenêtre active.",
                  .choice(["display", "focused_window"]), .string("display")),
            entry(.grille, t, "label_font_size", "Taille des étiquettes (points)",
                  "Taille du texte des étiquettes de la grille.", .double(8...48), .double(13)),
        ]
    }()
}

// MARK: - Avancé et règles

extension SettingsCatalog {
    static let advancedDescriptors: [SettingDescriptor] = {
        let record = "experimental.target_record"
        let menu = "experimental.titlebar_context_menu"
        return [
            entry(.avance, record, "enabled", "Activer l'enregistrement",
                  "Autorise l'enregistrement des actions au clavier et à la souris.", .bool, .bool(false)),
            entry(.avance, record, "replay_enabled", "Activer la relecture",
                  "Autorise la relecture d'un enregistrement.", .bool, .bool(false)),
            entry(.avance, record, "directory", "Dossier des enregistrements",
                  "Dossier où sont rangés les enregistrements.", .text, .string("~/.local/state/roadies/records")),
            entry(.avance, record, "default_duration_seconds", "Durée par défaut (secondes)",
                  "Durée d'un enregistrement sans durée précisée. Au plus la durée maximale.", .double(0.5...3600), .double(10)),
            entry(.avance, record, "max_duration_seconds", "Durée maximale (secondes)",
                  "Durée la plus longue d'un enregistrement.", .double(1...3600), .double(120)),
            entry(.avance, record, "max_events", "Nombre maximal d'événements",
                  "Au-delà, l'enregistrement s'arrête.", .int(1...20000), .int(2000)),
            entry(.avance, record, "include_mouse_moves", "Enregistrer les mouvements de souris",
                  "Ajoute chaque déplacement du pointeur.", .bool, .bool(false)),
            entry(.avance, record, "include_key_events", "Enregistrer les touches",
                  "Ajoute les touches pressées.", .bool, .bool(true)),
            entry(.avance, record, "include_ax_context", "Enregistrer le contexte d'accessibilité",
                  "Ajoute l'élément visé par chaque action.", .bool, .bool(true)),
            entry(.avance, record, "record_text_input", "Enregistrer le texte saisi",
                  "Ajoute le texte tapé. Peut contenir des informations personnelles.", .bool, .bool(false)),
            entry(.avance, record, "indicator", "Indicateur d'enregistrement",
                  "Où signaler qu'un enregistrement est en cours : notification, rail (navrail), les deux ou aucun.",
                  .choice(["notification", "navrail", "both", "none"]), .string("notification")),
            entry(.avance, record, "navrail_bottom_offset", "Décalage de l'indicateur du rail (points)",
                  "Distance entre l'indicateur et le bas du rail.", .double(0...400), .double(50)),
            entry(.avance, menu, "enabled", "Activer le menu de la barre de titre",
                  "Ouvre un menu d'actions par clic droit sur la barre de titre d'une fenêtre.", .bool, .bool(false)),
            entry(.avance, menu, "double_click_maximize", "Double-clic sur la barre de titre",
                  "Affiche la fenêtre seule, en gardant le rail libre, puis rend la disposition au double-clic suivant. "
                  + "N'agit que si macOS ne fait rien de ce double-clic (Bureau et Dock > « Ne rien faire »).",
                  .bool, .bool(false)),
            entry(.avance, menu, "height", "Hauteur de la zone (points)",
                  "Hauteur de la barre de titre qui réagit au clic droit.", .double(12...96), .double(36)),
            entry(.avance, menu, "leading_exclusion", "Zone exclue à gauche (points)",
                  "Largeur ignorée à gauche, pour garder les boutons de la fenêtre.", .double(0...240), .double(84)),
            entry(.avance, menu, "trailing_exclusion", "Zone exclue à droite (points)",
                  "Largeur ignorée à droite de la barre de titre.", .double(0...240), .double(16)),
            entry(.avance, menu, "managed_windows_only", "Fenêtres gérées seulement",
                  "Limite le menu aux fenêtres gérées par Roadie.", .bool, .bool(true)),
            entry(.avance, menu, "tile_candidates_only", "Fenêtres tuilables seulement",
                  "Limite le menu aux fenêtres que le tuilage peut placer.", .bool, .bool(true)),
            entry(.avance, menu, "include_stage_destinations", "Proposer les stages",
                  "Ajoute au menu les stages de destination.", .bool, .bool(true)),
            entry(.avance, menu, "include_desktop_destinations", "Proposer les bureaux",
                  "Ajoute au menu les bureaux de destination.", .bool, .bool(true)),
            entry(.avance, menu, "include_display_destinations", "Proposer les écrans",
                  "Ajoute au menu les écrans de destination.", .bool, .bool(true)),
        ]
    }()

    static let ruleDescriptors: [SettingDescriptor] = [
        readOnlyEntry(.regles, "exclusions", "floating_bundles", "Applications toujours flottantes",
                      "Liste d'identifiants d'applications gardées hors du tuilage."),
        readOnlyEntry(.regles, "", "rules", "Règles de fenêtres",
                      "Tableau de règles qui placent ou excluent des fenêtres selon l'application ou le titre."),
        readOnlyEntry(.regles, "signals", "hooks", "Commandes déclenchées par événement",
                      "Structure avancée connue. Roadie ne l'exécute pas actuellement ; cet éditeur permet de la conserver et de la préparer."),
    ]
}
