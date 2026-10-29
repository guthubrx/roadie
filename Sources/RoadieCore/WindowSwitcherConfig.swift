import Foundation
import RoadieCore

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
    public var presentation: String
    /// Icône de l'application à côté du titre de chaque fenêtre (session 121).
    public var appIcon: Bool
    /// 0 : taille automatique, selon le texte. Sinon bornée à 12…64 points.
    public var appIconSize: Double
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
        shortcuts: [WindowSwitcherShortcutConfig] = [WindowSwitcherShortcutConfig()],
        presentation: String = "classic",
        appIcon: Bool = true,
        appIconSize: Double = 0
    ) {
        self.enabled = enabled
        self.style = Self.styles.contains(style) ? style : "thumbnails"
        self.autoSize = autoSize
        self.thumbnailWidth = min(400, max(120, thumbnailWidth))
        self.fontSize = min(32, max(10, fontSize))
        let family = fontFamily.trimmingCharacters(in: .whitespacesAndNewlines)
        self.fontFamily = family.isEmpty ? "system" : family
        self.preview = preview
        self.presentation = WindowSwitcherPresentation(rawValue: presentation)?.rawValue ?? "classic"
        self.appIcon = appIcon
        self.appIconSize = appIconSize <= 0 ? 0 : min(64, max(12, appIconSize))
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
        case presentation
        case appIcon = "app_icon"
        case appIconSize = "app_icon_size"
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
            shortcuts: try c.decodeIfPresent([WindowSwitcherShortcutConfig].self, forKey: .shortcuts) ?? defaults.shortcuts,
            presentation: try c.decodeIfPresent(String.self, forKey: .presentation) ?? defaults.presentation,
            appIcon: try c.decodeIfPresent(Bool.self, forKey: .appIcon) ?? defaults.appIcon,
            appIconSize: try c.decodeFlexibleDouble(forKey: .appIconSize) ?? defaults.appIconSize
        )
    }
}

/// Profil de raccourci du sélecteur (`[[switcher.shortcuts]]`). Un profil sans raccourci a `hotkey` vide.
public struct WindowSwitcherShortcutConfig: Equatable, Codable, Sendable {
    public static let scopes: Set<String> = ["stage", "desktop", "display", "application", "all"]
    public static let releaseActions: Set<String> = ["focus", "stay", "search"]
    public static let triggerSources: Set<String> = ["roadie", "btt", "external"]
    public static let visibilityChoices: Set<String> = ["auto", "always", "never"]
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
    public var enabled: Bool
    public var triggerSource: String
    public var searchVisibility: String
    public var actionsVisibility: String
    public var arrowNavigation: Bool
    public var mouseHover: Bool
    public var styleOverride: String?
    public var previewOverride: Bool?
    public var autoSizeOverride: Bool?
    public var thumbnailWidthOverride: Double?
    public var fontSizeOverride: Double?
    public var fontFamilyOverride: String?
    public var presentationOverride: String?

    public init(
        id: String = "all",
        name: String = tr("Toutes les fenêtres", "All windows"),
        hotkey: String = "",
        scope: String = "all",
        releaseAction: String = "focus",
        sortOrder: String = "recent",
        includeMinimized: Bool = true,
        includeHidden: Bool = true,
        includeFullscreen: Bool = true,
        onePerApp: Bool = false,
        enabled: Bool = true,
        triggerSource: String? = nil,
        searchVisibility: String = "auto",
        actionsVisibility: String = "auto",
        arrowNavigation: Bool = true,
        mouseHover: Bool = true,
        styleOverride: String? = nil,
        previewOverride: Bool? = nil,
        autoSizeOverride: Bool? = nil,
        thumbnailWidthOverride: Double? = nil,
        fontSizeOverride: Double? = nil,
        fontFamilyOverride: String? = nil,
        presentationOverride: String? = nil
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
        self.enabled = enabled
        let source = triggerSource ?? (self.hotkey.isEmpty ? "external" : "roadie")
        self.triggerSource = Self.triggerSources.contains(source) ? source : "external"
        self.searchVisibility = Self.visibilityChoices.contains(searchVisibility) ? searchVisibility : "auto"
        self.actionsVisibility = Self.visibilityChoices.contains(actionsVisibility) ? actionsVisibility : "auto"
        self.arrowNavigation = arrowNavigation
        self.mouseHover = mouseHover
        self.styleOverride = styleOverride.flatMap { WindowSwitcherConfig.styles.contains($0) ? $0 : nil }
        self.previewOverride = previewOverride
        self.autoSizeOverride = autoSizeOverride
        self.thumbnailWidthOverride = thumbnailWidthOverride.map { min(400, max(120, $0)) }
        self.fontSizeOverride = fontSizeOverride.map { min(32, max(10, $0)) }
        self.fontFamilyOverride = fontFamilyOverride.flatMap { $0.isEmpty ? nil : $0 }
        self.presentationOverride = presentationOverride.flatMap { WindowSwitcherPresentation(rawValue: $0)?.rawValue }

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
        case enabled
        case triggerSource = "trigger_source"
        case searchVisibility = "search_visibility"
        case actionsVisibility = "actions_visibility"
        case arrowNavigation = "arrow_navigation"
        case mouseHover = "mouse_hover"
        case styleOverride = "style"
        case previewOverride = "preview"
        case autoSizeOverride = "auto_size"
        case thumbnailWidthOverride = "thumbnail_width"
        case fontSizeOverride = "font_size"
        case fontFamilyOverride = "font_family"
        case presentationOverride = "presentation"
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
            onePerApp: try c.decodeIfPresent(Bool.self, forKey: .onePerApp) ?? defaults.onePerApp,
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            triggerSource: try c.decodeIfPresent(String.self, forKey: .triggerSource),
            searchVisibility: try c.decodeIfPresent(String.self, forKey: .searchVisibility) ?? "auto",
            actionsVisibility: try c.decodeIfPresent(String.self, forKey: .actionsVisibility) ?? "auto",
            arrowNavigation: try c.decodeIfPresent(Bool.self, forKey: .arrowNavigation) ?? true,
            mouseHover: try c.decodeIfPresent(Bool.self, forKey: .mouseHover) ?? true,
            styleOverride: try c.decodeIfPresent(String.self, forKey: .styleOverride),
            previewOverride: try c.decodeIfPresent(Bool.self, forKey: .previewOverride),
            autoSizeOverride: try c.decodeIfPresent(Bool.self, forKey: .autoSizeOverride),
            thumbnailWidthOverride: try c.decodeFlexibleDouble(forKey: .thumbnailWidthOverride),
            fontSizeOverride: try c.decodeFlexibleDouble(forKey: .fontSizeOverride),
            fontFamilyOverride: try c.decodeIfPresent(String.self, forKey: .fontFamilyOverride),
            presentationOverride: try c.decodeIfPresent(String.self, forKey: .presentationOverride)
        )
    }
}
