import Foundation

/// Réglages du sélecteur de fenêtres (`[switcher]`, Spec056). Les bornes et les listes fermées
/// sont appliquées au décodage et à l'initialisation : une valeur hors contrat devient la valeur sûre.
public struct WindowSwitcherConfig: Equatable, Codable, Sendable {
    public static let styles: Set<String> = ["thumbnails", "icons", "list"]
    public static let maxShortcuts = 9

    public var enabled: Bool
    public var style: String
    public var autoSize: Bool
    /// Bornée à 120…400 points.
    public var thumbnailWidth: Double
    /// Bornée à 10…32 points.
    public var fontSize: Double
    public var fontFamily: String
    public var preview: Bool
    public var excludedBundles: [String]
    /// Au plus neuf profils. Un identifiant déjà vu est ignoré : le premier profil gagne.
    public var shortcuts: [WindowSwitcherShortcutConfig]

    public init(
        enabled: Bool = true,
        style: String = "thumbnails",
        autoSize: Bool = true,
        thumbnailWidth: Double = 220,
        fontSize: Double = 16,
        fontFamily: String = "system",
        preview: Bool = true,
        excludedBundles: [String] = [],
        shortcuts: [WindowSwitcherShortcutConfig] = [WindowSwitcherShortcutConfig()]
    ) {
        self.enabled = enabled
        self.style = Self.styles.contains(style) ? style : "thumbnails"
        self.autoSize = autoSize
        self.thumbnailWidth = min(400, max(120, thumbnailWidth))
        self.fontSize = min(32, max(10, fontSize))
        let family = fontFamily.trimmingCharacters(in: .whitespacesAndNewlines)
        self.fontFamily = family.isEmpty ? "system" : family
        self.preview = preview
        self.excludedBundles = excludedBundles
        self.shortcuts = Self.normalizedShortcuts(shortcuts)
    }

    private static func normalizedShortcuts(_ shortcuts: [WindowSwitcherShortcutConfig]) -> [WindowSwitcherShortcutConfig] {
        var seen: Set<String> = []
        var result: [WindowSwitcherShortcutConfig] = []
        for shortcut in shortcuts {
            guard seen.insert(shortcut.id).inserted else { continue }
            result.append(shortcut)
            if result.count == maxShortcuts { break }
        }
        return result
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case style
        case autoSize = "auto_size"
        case thumbnailWidth = "thumbnail_width"
        case fontSize = "font_size"
        case fontFamily = "font_family"
        case preview
        case excludedBundles = "excluded_bundles"
        case shortcuts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = WindowSwitcherConfig()
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled,
            style: try c.decodeIfPresent(String.self, forKey: .style) ?? defaults.style,
            autoSize: try c.decodeIfPresent(Bool.self, forKey: .autoSize) ?? defaults.autoSize,
            thumbnailWidth: try c.decodeFlexibleDouble(forKey: .thumbnailWidth) ?? defaults.thumbnailWidth,
            fontSize: try c.decodeFlexibleDouble(forKey: .fontSize) ?? defaults.fontSize,
            fontFamily: try c.decodeIfPresent(String.self, forKey: .fontFamily) ?? defaults.fontFamily,
            preview: try c.decodeIfPresent(Bool.self, forKey: .preview) ?? defaults.preview,
            excludedBundles: try c.decodeIfPresent([String].self, forKey: .excludedBundles) ?? defaults.excludedBundles,
            shortcuts: try c.decodeIfPresent([WindowSwitcherShortcutConfig].self, forKey: .shortcuts) ?? defaults.shortcuts
        )
    }
}

/// Profil de raccourci du sélecteur (`[[switcher.shortcuts]]`). Un profil sans raccourci a `hotkey` vide.
public struct WindowSwitcherShortcutConfig: Equatable, Codable, Sendable {
    public static let scopes: Set<String> = ["stage", "desktop", "display", "application", "all"]
    public static let releaseActions: Set<String> = ["focus", "stay"]
    public static let sortOrders: Set<String> = ["recent", "title", "stage"]

    public var id: String
    public var name: String
    /// Forme minuscule sans espaces, par exemple `ctrl+alt+tab`. Vide : aucun raccourci clavier.
    public var hotkey: String
    public var scope: String
    public var releaseAction: String
    public var sortOrder: String
    public var includeMinimized: Bool
    public var includeHidden: Bool
    public var includeFullscreen: Bool
    public var onePerApp: Bool

    public init(
        id: String = "all",
        name: String = "Toutes les fenêtres",
        hotkey: String = "",
        scope: String = "all",
        releaseAction: String = "focus",
        sortOrder: String = "recent",
        includeMinimized: Bool = true,
        includeHidden: Bool = true,
        includeFullscreen: Bool = true,
        onePerApp: Bool = false
    ) {
        self.id = id
        self.name = name
        self.hotkey = hotkey.lowercased().filter { !$0.isWhitespace }
        self.scope = Self.scopes.contains(scope) ? scope : "all"
        self.releaseAction = Self.releaseActions.contains(releaseAction) ? releaseAction : "focus"
        self.sortOrder = Self.sortOrders.contains(sortOrder) ? sortOrder : "recent"
        self.includeMinimized = includeMinimized
        self.includeHidden = includeHidden
        self.includeFullscreen = includeFullscreen
        self.onePerApp = onePerApp
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case hotkey
        case scope
        case releaseAction = "release_action"
        case sortOrder = "sort_order"
        case includeMinimized = "include_minimized"
        case includeHidden = "include_hidden"
        case includeFullscreen = "include_fullscreen"
        case onePerApp = "one_per_app"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = WindowSwitcherShortcutConfig()
        self.init(
            id: try c.decodeIfPresent(String.self, forKey: .id) ?? defaults.id,
            name: try c.decodeIfPresent(String.self, forKey: .name) ?? defaults.name,
            hotkey: try c.decodeIfPresent(String.self, forKey: .hotkey) ?? defaults.hotkey,
            scope: try c.decodeIfPresent(String.self, forKey: .scope) ?? defaults.scope,
            releaseAction: try c.decodeIfPresent(String.self, forKey: .releaseAction) ?? defaults.releaseAction,
            sortOrder: try c.decodeIfPresent(String.self, forKey: .sortOrder) ?? defaults.sortOrder,
            includeMinimized: try c.decodeIfPresent(Bool.self, forKey: .includeMinimized) ?? defaults.includeMinimized,
            includeHidden: try c.decodeIfPresent(Bool.self, forKey: .includeHidden) ?? defaults.includeHidden,
            includeFullscreen: try c.decodeIfPresent(Bool.self, forKey: .includeFullscreen) ?? defaults.includeFullscreen,
            onePerApp: try c.decodeIfPresent(Bool.self, forKey: .onePerApp) ?? defaults.onePerApp
        )
    }
}
