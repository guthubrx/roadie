import Foundation
import TOMLKit

public enum RoadieConfigLoader {
    /// Clés qui sont des listes ou des tableaux de tables : hors du catalogue de réglages scalaires (SPEC-023).
    private static let nonScalarKeys: [String: Set<String>] = [
        "tiling": ["display_overrides", "smart_gaps_solo_sides", "allowed_subroles"],
        "stage_manager": ["workspaces"],
        "exclusions": ["floating_bundles", "floating_windows"],
        "fx.animations": ["move", "stage", "appearance", "rail", "launcher", "switcher", "overview"],
        "fx.borders": ["stage_overrides"],
        "width_adjustment": ["presets"],
        "experimental.app_targets": ["include_roles", "additional_boost_bundle_ids"],
        "experimental.target_mode": ["web_searches", "fallback_searches", "bookmark_browsers", "app_search_paths", "btt_pause_keys",
                                      "file_types", "file_excluded_folders"],
        "switcher": ["excluded_bundles", "zone_click_excluded_bundles", "zone_clicks_per_app", "shortcuts"]
    ]

    /// Tables qui sont elles-mêmes des tableaux de tables ou leurs sous-tables.
    private static let nonScalarTables: Set<String> = [
        "tiling.display_overrides", "stage_manager.workspaces", "fx.borders.stage_overrides", "exclusions.floating_windows",
        "fx.rail.preview.stage_overrides", "switcher.shortcuts", "switcher.zone_clicks_per_app", "experimental.target_mode.web_searches", "rules", "rules.match", "rules.action",
        "shortcuts"
    ]

    /// Clés scalaires reconnues par le validateur, par chemin de table TOML complet.
    /// Les tables sans clé scalaire sont omises. Complexité : O(k) — k nombre de clés connues.
    public static func knownScalarKeys() -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for (table, keys) in ConfigValidationRules.knownKeys where !nonScalarTables.contains(table) && table != "launcher" && !table.hasPrefix("launcher.") {
            let scalars = keys.subtracting(nonScalarKeys[table] ?? [])
            if !scalars.isEmpty { result[table] = scalars }
        }
        return result
    }

    /// Clés décodées mais lues nulle part dans le daemon, par chemin de table.
    public static func ineffectiveKeys() -> [String: Set<String>] {
        ConfigValidationRules.ineffectiveKeys
    }

    /// Clés acceptées par le validateur, par chemin de table (« » pour la racine).
    public static func knownKeys() -> [String: Set<String>] {
        ConfigValidationRules.knownKeys
    }

    /// Distance de Levenshtein, partagée avec le validateur (aucune seconde implémentation).
    public static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        ConfigValidationRules.editDistance(lhs, rhs)
    }

    public static func defaultConfigPath() -> String {
        (NSString(string: "~/.config/roadies/roadies.toml").expandingTildeInPath as String)
    }

    public static func generatedRulesPath(for path: String? = nil) -> String {
        let resolved = path ?? defaultConfigPath()
        let url = URL(fileURLWithPath: NSString(string: resolved).expandingTildeInPath)
        let filename = url.deletingPathExtension().lastPathComponent + ".generated.toml"
        return url.deletingLastPathComponent().appendingPathComponent(filename).path
    }

    public static func load(from path: String? = nil) throws -> RoadieConfig {
        let resolved = path ?? defaultConfigPath()
        var config = RoadieConfig()
        if FileManager.default.fileExists(atPath: resolved) {
            let raw = try String(contentsOfFile: resolved, encoding: .utf8)
            config = try TOMLDecoder().decode(RoadieConfig.self, from: raw)
        }
        config.rules.append(contentsOf: try generatedRules(from: generatedRulesPath(for: resolved)))
        config.rules.append(contentsOf: FloatingWindowTitles.rules(config.exclusions.floatingWindows))
        return config
    }

    public static func validate(path: String? = nil) -> ConfigValidationReport {
        let resolved = path ?? defaultConfigPath()
        let generatedPath = generatedRulesPath(for: resolved)
        var items: [ConfigValidationItem] = []
        guard FileManager.default.fileExists(atPath: resolved) else {
            items.append(
                ConfigValidationItem(level: .warning, path: resolved, message: tr("fichier de configuration introuvable ; les valeurs par défaut s'appliquent", "config file not found; defaults will be used"))
            )
            items.append(contentsOf: validateGeneratedRules(path: generatedPath))
            if items.isEmpty {
                items.append(ConfigValidationItem(level: .ok, path: resolved, message: tr("configuration valide", "config is valid")))
            }
            return ConfigValidationReport(items: items)
        }

        var raw = ""
        do {
            raw = try String(contentsOfFile: resolved, encoding: .utf8)
            _ = try TOMLDecoder().decode(RoadieConfig.self, from: raw)
            items.append(contentsOf: ConfigValidationRules.validate(rawToml: raw))
            items.append(contentsOf: validateGeneratedRules(path: generatedPath))
            if items.isEmpty {
                items.append(ConfigValidationItem(level: .ok, path: resolved, message: tr("configuration valide", "config is valid")))
            }
            return ConfigValidationReport(items: items)
        } catch {
            return ConfigValidationReport(items: [
                ConfigValidationItem(level: .error, path: resolved, message: ConfigValidationRules.describe(decodeError: error, rawToml: raw))
            ])
        }
    }

    public static func loadRulesFile(from path: String) throws -> [WindowRule] {
        try generatedRules(from: path)
    }

    private static func generatedRules(from path: String) throws -> [WindowRule] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        let raw = try String(contentsOfFile: path, encoding: .utf8)
        return try TOMLDecoder().decode(RoadieConfig.self, from: raw).rules
    }

    private static func validateGeneratedRules(path: String) -> [ConfigValidationItem] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        var raw = ""
        do {
            raw = try String(contentsOfFile: path, encoding: .utf8)
            _ = try TOMLDecoder().decode(RoadieConfig.self, from: raw)
            return ConfigValidationRules.validateGeneratedRules(rawToml: raw, path: path)
        } catch {
            return [
                ConfigValidationItem(level: .error, path: path, message: ConfigValidationRules.describe(decodeError: error, rawToml: raw))
            ]
        }
    }
}

public enum ConfigValidationLevel: String, Codable, Sendable {
    case ok
    case warning
    case error
}

public struct ConfigValidationItem: Equatable, Codable, Sendable {
    public var level: ConfigValidationLevel
    public var path: String
    public var message: String

    public init(level: ConfigValidationLevel, path: String, message: String) {
        self.level = level
        self.path = path
        self.message = message
    }
}

public struct ConfigValidationReport: Equatable, Codable, Sendable {
    public var items: [ConfigValidationItem]

    public init(items: [ConfigValidationItem]) {
        self.items = items
    }

    public var hasErrors: Bool {
        items.contains { $0.level == .error }
    }
}

private enum ConfigValidationRules {
    private static let supportedTables: Set<String> = [
        "launcher", "launcher.web_searches",
        "interface",
        "tiling",
        "desktops",
        "stage_manager",
        "stage_manager.workspaces",
        "tiling.display_overrides",
        "exclusions",
        "exclusions.floating_windows",
        "fx",
        "fx.animations",
        "fx.animations.move",
        "fx.animations.stage",
        "fx.animations.appearance",
        "fx.animations.rail",
        "fx.animations.launcher",
        "fx.animations.switcher",
        "fx.animations.overview",
        "fx.borders",
        "fx.borders.stage_overrides",
        // Tables lues par RailSettings (Sources/RoadieDaemon/RailSettings.swift).
        "fx.rail",
        "fx.rail.layout",
        "fx.rail.header",
        "fx.rail.header.display",
        "fx.rail.header.desktop",
        "fx.rail.stages",
        "fx.rail.preview",
        "fx.rail.preview.stage_overrides",
        "fx.rail.stacked",
        "fx.rail.stage_labels",
        "fx.rail.parallax",
        "focus",
        "window_placement",
        "width_adjustment",
        "overview",
        "switcher",
        "switcher.shortcuts",
        "experimental",
        "experimental.titlebar_context_menu",
        "experimental.target_mode",
        "experimental.target_mode.web_searches",
        "experimental.app_targets",
        "experimental.target_grid",
        "experimental.target_record",
        "rules",
        "rules.match",
        "rules.action",
        "shortcuts"
    ]

    private static let knownUnsupportedTables: Set<String> = [
        "daemon",
        "mouse",
        "scratchpads",
        "sticky",
        "signals",
        "signals.hooks",
        "fx.opacity",
        "fx.opacity.stage_hide"
    ]

    /// Clés réellement lues, par table. Une table absente de ce dictionnaire n'est pas vérifiée.
    /// Source : les `CodingKeys` de ce fichier, `WindowRule.swift` et `RailSettings.swift`.
    static let knownKeys: [String: Set<String>] = {
        let labelKeys: Set<String> = ["enabled", "template", "color", "font_size", "font_family", "weight", "alignment", "opacity", "offset_x", "offset_y"]
        let gapKeys: Set<String> = ["gaps_outer", "gaps_outer_top", "gaps_outer_right", "gaps_outer_bottom", "gaps_outer_left"]
        var keys: [String: Set<String>] = [
            "": [],
            "fx": ["drop_preview", "drag_preview", "drag_preview_opacity_percent", "drag_preview_scale_percent"],
            "fx.animations": ["enabled", "profile", "curve", "duration_ms", "intensity", "stiffness", "damping", "move", "stage", "appearance", "rail", "launcher", "switcher", "overview"],
            "fx.animations.move": ["enabled", "curve", "duration_ms", "intensity", "stiffness", "damping"],
            "fx.animations.stage": ["enabled", "curve", "duration_ms", "intensity", "stiffness", "damping"],
            "fx.animations.appearance": ["enabled", "curve", "duration_ms", "intensity", "stiffness", "damping"],
            "fx.animations.rail": ["enabled", "curve", "duration_ms", "intensity", "stiffness", "damping"],
            "fx.animations.launcher": ["enabled", "curve", "duration_ms", "intensity", "stiffness", "damping"],
            "fx.animations.switcher": ["enabled", "curve", "duration_ms", "intensity", "stiffness", "damping"],
            "fx.animations.overview": ["enabled", "curve", "duration_ms", "intensity", "stiffness", "damping"],

            "interface": ["settings_text_font_size", "settings_help_font_size", "settings_title_font_size", "language"],
            "tiling": gapKeys.union(["default_strategy", "split_policy", "resize_handles", "live_drag_preview", "drag_move_modifier", "drag_resize_modifier", "display_overrides", "gaps_inner", "master_ratio", "smart_gaps_solo", "smart_gaps_solo_sides", "allowed_subroles", "popup_filter", "float_picture_in_picture"]),
            "tiling.display_overrides": gapKeys.union(["display_id", "display_name"]),
            "desktops": ["enabled", "count", "back_and_forth", "mode"],
            "stage_manager": ["enabled", "hide_strategy", "default_stage", "workspaces"],
            "stage_manager.workspaces": ["id", "display_name"],
            "exclusions": ["floating_bundles", "floating_windows", "floating_avoid_rail"],
            "exclusions.floating_windows": ["app", "title", "remember_frame"],
            "fx.borders": ["enabled", "thickness", "corner_radius", "active_color", "inactive_color", "pulse_on_focus", "stage_overrides"],
            "fx.borders.stage_overrides": ["stage_id", "active_color"],
            "fx.rail": ["renderer", "width", "background_color", "background_opacity", "auto_hide", "edge_hit_width", "edge_magnetism_width", "animation_ms", "hide_delay_ms", "layout_mode", "dynamic_left_gap", "empty_click_hide_active", "empty_click_safety_margin", "hide_on_maximized", "show_app_icons_row", "app_icons_row_size"],
            "fx.rail.layout": ["header_position", "stages_position", "spacing", "top_padding", "bottom_padding"],
            "fx.rail.header": ["enabled", "placement", "alignment", "top_padding", "bottom_padding", "height", "width", "title_color", "subtitle_color", "title_font_size", "subtitle_font_size", "font_family", "title_weight", "subtitle_weight", "title_template", "subtitle_template"],
            "fx.rail.header.display": labelKeys,
            "fx.rail.header.desktop": labelKeys,
            "fx.rail.stage_labels": ["enabled", "color", "font_size", "font_family", "weight", "alignment", "opacity", "offset_x", "offset_y", "placement", "z_order", "visibility_seconds", "fade_seconds", "caption_font_size", "gap", "follows_perspective"],
            "fx.rail.stages": ["position", "alignment", "gap", "slot_height", "reorder_magnetism"],
            "fx.rail.preview": ["width", "height", "leading_padding", "trailing_padding", "vertical_padding"],
            "fx.rail.preview.stage_overrides": ["stage_id", "active_color"],
            "fx.rail.stacked": ["offset_x", "offset_y", "scale_per_layer", "opacity_per_layer"],
            "fx.rail.parallax": ["rotation", "offset_x", "offset_y", "scale_per_layer", "opacity_per_layer", "darken_per_layer", "width", "height", "leading_padding", "trailing_padding", "vertical_padding"],
            "focus": ["stage_follows_focus", "assign_follows_focus", "stage_move_follows_focus", "focus_follows_mouse", "mouse_follows_focus"],
            "window_placement": ["new_apps_target", "new_window_side"],
            "width_adjustment": ["presets", "nudge_step", "minimum_ratio", "maximum_ratio"],
            "overview": ["enabled", "presentation", "loupe", "magnification", "hotkey", "background_blur", "selection_color", "selection_width"],
            "switcher": ["enabled", "presentation", "style", "auto_size", "thumbnail_width", "font_size", "font_family", "preview", "app_icon", "app_icon_size", "zone_history_size", "zone_history_hours", "zone_clicks_per_window", "excluded_bundles", "zone_click_excluded_bundles", "zone_clicks_per_app", "shortcuts"],
            "switcher.zone_clicks_per_app": ["app", "count"],
            "experimental.target_mode.web_searches": ["keyword", "title", "url"],
            "switcher.shortcuts": ["id", "name", "hotkey", "scope", "release_action", "sort_order", "include_minimized", "include_hidden", "include_fullscreen", "one_per_app", "enabled", "trigger_source", "search_visibility", "actions_visibility", "arrow_navigation", "mouse_hover", "btt_forward_uuid", "btt_reverse_uuid", "presentation", "style", "preview", "auto_size", "thumbnail_width", "font_size", "font_family", "source"],
            "experimental": [],
            "experimental.titlebar_context_menu": ["enabled", "height", "leading_exclusion", "trailing_exclusion", "managed_windows_only", "tile_candidates_only", "include_stage_destinations", "include_desktop_destinations", "include_display_destinations", "double_click_maximize"],
            "experimental.target_mode": Set<String>(["enabled", "picker_enabled", "overlay_enabled", "overlay_labels_only", "overlay_duration_seconds", "app_mouse_actions_enabled", "scroll_mode_enabled", "search_hotkey", "actions_hotkey", "screen_search_hotkey", "launcher_on_screen", "typo_max_errors", "web_search_url", "pick_modifier", "return_cmd", "return_alt", "return_ctrl", "workflow_view_style", "workflows_enabled", "alfred_workflows", "web_searches", "fallback_searches", "idle_frequent_enabled", "idle_frequent_count", "idle_recent_searches_enabled", "idle_recent_searches_count", "view_cycle_hotkey", "label_font_size", "search_label_font_size", "search_text_font_size", "command_text_font_size", "search_font_family", "command_font_family", "theme", "theme_dark", "visible_results", "bar_screen", "bar_position", "bar_save_position", "terminal_app", "bookmarks_enabled", "bookmark_browsers", "app_search_paths", "learning_enabled", "path_sort", "confirm_quit_all", "calc_opens_calculator", "learn_verb_order", "content_search_keyword", "tag_search_keyword", "web_history_days", "settings_in_search", "open_keyword", "find_keyword", "file_types", "file_excluded_folders", "calc_decimal", "calc_grouping", "show_scrollbar", "btt_pause_keys"]).union(LauncherBarKeys.actions.map(\.configKey)),
            "experimental.app_targets": ["enabled", "scope", "max_targets", "timeout_ms", "hint_characters", "include_roles", "ax_boost_enabled", "max_depth", "additional_boost_bundle_ids"],
            "experimental.target_grid": ["enabled", "mode", "overlay_enabled", "overlay_draw_grid", "overlay_fill_color", "overlay_fill_opacity", "overlay_border_color", "overlay_border_opacity", "overlay_label_color", "overlay_label_background_opacity", "rows", "columns", "max_depth", "hint_characters", "confirm_action_key", "reset_key", "back_key", "exit_key", "arrow_navigation_enabled", "arrow_edge_behavior", "action_delay_ms", "wake_mouse_pixels", "mouse_follow_grid", "focus_follow_grid", "label_placement", "default_scope", "label_font_size"],
            "experimental.target_record": ["enabled", "replay_enabled", "directory", "default_duration_seconds", "max_duration_seconds", "max_events", "include_mouse_moves", "include_key_events", "include_ax_context", "record_text_input", "indicator", "navrail_bottom_offset"],
            "rules": ["id", "enabled", "priority", "stop_processing", "match", "action"],
            "shortcuts": ["keys", "command", "enabled", "btt_uuid"],
            "rules.match": ["app", "app_regex", "title", "title_regex", "role", "subrole", "display", "desktop", "stage", "is_floating"],
            "rules.action": ["manage", "exclude", "assign_desktop", "assign_display", "assign_stage", "follow", "floating", "layout", "gap_override", "scratchpad", "emit_event", "remember_frame"]
        ]
        keys["launcher"] = keys["experimental.target_mode"]
        keys["launcher.web_searches"] = keys["experimental.target_mode.web_searches"]
        return keys
    }()

    /// Clés décodées mais lues nulle part dans le daemon (vérifié par recherche dans `Sources/`).
    static let ineffectiveKeys: [String: Set<String>] = [
        "desktops": ["enabled", "count", "back_and_forth", "mode"],
        "stage_manager": ["enabled", "hide_strategy"],
        // Anciennes clés d'en-tête du rail : sans effet, la hauteur dépend des tailles de police.
        "fx.rail.header": ["height", "width"]
    ]

    static func validate(rawToml: String) -> [ConfigValidationItem] {
        var items: [ConfigValidationItem] = []
        let tables = tableNames(in: rawToml)
        for table in tables.sorted() {
            if supportedTables.contains(table) {
                continue
            }
            if knownUnsupportedTables.contains(table) {
                items.append(ConfigValidationItem(
                    level: .warning,
                    path: table,
                    message: tr("connue mais pas encore entièrement prise en charge", "known but not fully supported yet")
                ))
            } else {
                items.append(ConfigValidationItem(
                    level: .warning,
                    path: table,
                    message: tr("table inconnue, ignorée", "unknown table, ignored") + suggestionSuffix(for: table, among: supportedTables.union(knownUnsupportedTables))
                ))
            }
        }
        if let root = try? TOMLTable(string: rawToml) {
            items.append(contentsOf: keyChecks(in: root, path: ""))
        }
        if let config = try? TOMLDecoder().decode(RoadieConfig.self, from: rawToml) {
            if config.widthAdjustment.presets.isEmpty {
                items.append(ConfigValidationItem(level: .error, path: "width_adjustment.presets", message: tr("doit contenir au moins une proportion", "must contain at least one ratio")))
            }
            if config.widthAdjustment.minimumRatio > config.widthAdjustment.maximumRatio {
                items.append(ConfigValidationItem(level: .error, path: "width_adjustment.minimum_ratio", message: tr("doit être inférieur ou égal à maximum_ratio", "must be lower than or equal to maximum_ratio")))
            }
            items.append(contentsOf: validateTitlebarContextMenu(config.experimental.titlebarContextMenu))
            items.append(contentsOf: validateTargetMode(config.experimental.targetMode))
            if !config.overview.hotkey.isEmpty, TargetModeConfig.hotkeyParts(config.overview.hotkey) == nil {
                items.append(ConfigValidationItem(level: .error, path: "overview.hotkey", message: tr("modificateurs et une touche attendus ; vide : désactivé", "expected modifiers and one key; empty disables")))
            }
            items.append(contentsOf: validateAppTargets(config.experimental.appTargets))
            items.append(contentsOf: validateTargetGrid(config.experimental.targetGrid))
            items.append(contentsOf: validateTargetRecord(config.experimental.targetRecord))
        }
        return items
    }

    static func validateGeneratedRules(rawToml: String, path: String) -> [ConfigValidationItem] {
        tableNames(in: rawToml).sorted().compactMap { table in
            guard ["rules", "rules.match", "rules.action"].contains(table) else {
                return ConfigValidationItem(
                    level: .warning,
                    path: "\(path):\(table)",
                    message: tr("le fichier des règles générées ne doit contenir que des tables [[rules]]", "generated rules file should only contain [[rules]] tables")
                )
            }
            return nil
        }
    }

    /// Signale les clés inconnues (avec suggestion) et les clés sans effet.
    /// Complexité : O(k * c * l²) — k clés du fichier, c candidats de la table (≤ 30), l longueur d'un nom (≤ 40).
    private static func keyChecks(in table: TOMLTable, path: String) -> [ConfigValidationItem] {
        var items: [ConfigValidationItem] = []
        let known = knownKeys[path]
        for key in table.keys.sorted() {
            guard let value = table[key] else { continue }
            let childPath = path.isEmpty ? key : "\(path).\(key)"
            if let child = value.table {
                items.append(contentsOf: keyChecks(in: child, path: childPath))
            } else if let array = value.array, array.count > 0, array.allSatisfy({ $0.table != nil }) {
                for element in array {
                    if let child = element.table {
                        items.append(contentsOf: keyChecks(in: child, path: childPath))
                    }
                }
            } else if let known {
                if ineffectiveKeys[path]?.contains(key) == true {
                    items.append(ConfigValidationItem(
                        level: .warning,
                        path: childPath,
                        message: tr("clé sans effet : roadie ne la lit pas", "key has no effect: roadie does not read it")
                    ))
                } else if !known.contains(key) {
                    items.append(ConfigValidationItem(
                        level: .warning,
                        path: childPath,
                        message: tr("clé inconnue, ignorée", "unknown key, ignored") + suggestionSuffix(for: key, among: known)
                    ))
                }
            }
        }
        return items
    }

    private static func suggestionSuffix(for name: String, among candidates: Set<String>) -> String {
        guard let best = closest(to: name, among: candidates) else { return "" }
        return tr(" ; vouliez-vous dire « \(best) » ?", "; did you mean “\(best)”?")
    }

    /// Candidat le plus proche par distance d'édition, à 2 modifications au plus (1 pour un nom court).
    private static func closest(to name: String, among candidates: Set<String>) -> String? {
        let limit = name.count <= 4 ? 1 : 2
        return candidates
            .map { (candidate: $0, distance: editDistance(name, $0)) }
            .filter { $0.distance <= limit }
            .min { ($0.distance, $0.candidate) < ($1.distance, $1.candidate) }?
            .candidate
    }

    /// Distance de Levenshtein. Complexité : O(a * b) en temps, O(b) en mémoire.
    static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            previous = current
        }
        return previous[b.count]
    }

    /// Traduit une erreur de décodage en message lisible : `table.clé : attendu X, reçu Y`.
    static func describe(decodeError error: Error, rawToml: String) -> String {
        if let parseError = error as? TOMLParseError {
            let begin = parseError.source.begin
            return tr("syntaxe TOML invalide (ligne \(begin.line), colonne \(begin.column)) : \(parseError.description)", "invalid TOML syntax (line \(begin.line), column \(begin.column)): \(parseError.description)")
        }
        guard let decodingError = error as? DecodingError else { return "\(error)" }
        let context: DecodingError.Context
        var expected: String?
        switch decodingError {
        case .typeMismatch(let type, let ctx), .valueNotFound(let type, let ctx):
            context = ctx
            expected = expectedName("\(type)")
        case .keyNotFound(_, let ctx):
            context = ctx
            // TOMLKit : `A "String" does not exist at ...`
            let parts = ctx.debugDescription.split(separator: "\"", omittingEmptySubsequences: false)
            expected = parts.count > 1 ? expectedName(String(parts[1])) : nil
        case .dataCorrupted(let ctx):
            context = ctx
        @unknown default:
            return "\(error)"
        }
        let path = displayPath(context.codingPath)
        let received = (try? TOMLTable(string: rawToml)).flatMap { rawValue(at: context.codingPath, in: $0) }
        var message = path.isEmpty ? "" : tr("\(path) : ", "\(path): ")
        switch (expected, received) {
        case (let expected?, let received?):
            message += tr("attendu \(expected), reçu \(receivedName(received.type))", "expected \(expected), got \(receivedName(received.type))")
        case (let expected?, nil):
            message += tr("clé obligatoire absente (attendu \(expected))", "required key missing (expected \(expected))")
        default:
            message += context.debugDescription
        }
        return message
    }

    private static func displayPath(_ codingPath: [CodingKey]) -> String {
        codingPath.reduce(into: "") { result, key in
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
    }

    private static func rawValue(at codingPath: [CodingKey], in root: TOMLTable) -> TOMLValueConvertible? {
        var current: TOMLValueConvertible = root
        for key in codingPath {
            if let index = key.intValue {
                guard let array = current.array, index >= 0, index < array.count else { return nil }
                current = array[index]
            } else {
                guard let next = current.table?[key.stringValue] else { return nil }
                current = next
            }
        }
        return current
    }

    private static func expectedName(_ swiftType: String) -> String {
        switch swiftType {
        case "String": return tr("texte", "text")
        case "Bool": return tr("booléen", "boolean")
        case "Double": return tr("nombre", "number")
        case "Int": return tr("entier", "integer")
        default: return swiftType
        }
    }

    private static func receivedName(_ type: TOMLType) -> String {
        switch type {
        case .string: return tr("texte", "text")
        case .bool: return tr("booléen", "boolean")
        case .double: return tr("nombre", "number")
        case .int: return tr("entier", "integer")
        case .table: return "table"
        case .array: return tr("tableau", "array")
        case .date, .time, .dateTime: return "date"
        }
    }

    private static func tableNames(in rawToml: String) -> Set<String> {
        var result: Set<String> = []
        for line in rawToml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("[") else { continue }
            let withoutComment = trimmed.split(separator: "#", maxSplits: 1).first.map(String.init) ?? trimmed
            let table = withoutComment
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]").union(.whitespaces))
            guard !table.isEmpty else { continue }
            result.insert(table)
        }
        return result
    }

    private static func validateTitlebarContextMenu(_ config: TitlebarContextMenuConfig) -> [ConfigValidationItem] {
        var items: [ConfigValidationItem] = []
        if config.height < 12 || config.height > 96 {
            items.append(ConfigValidationItem(
                level: .error,
                path: "experimental.titlebar_context_menu.height",
                message: tr("doit être entre 12 et 96", "must be between 12 and 96")
            ))
        }
        if config.leadingExclusion < 0 || config.leadingExclusion > 240 {
            items.append(ConfigValidationItem(
                level: .error,
                path: "experimental.titlebar_context_menu.leading_exclusion",
                message: tr("doit être entre 0 et 240", "must be between 0 and 240")
            ))
        }
        if config.trailingExclusion < 0 || config.trailingExclusion > 240 {
            items.append(ConfigValidationItem(
                level: .error,
                path: "experimental.titlebar_context_menu.trailing_exclusion",
                message: tr("doit être entre 0 et 240", "must be between 0 and 240")
            ))
        }
        if config.enabled &&
            !config.includeStageDestinations &&
            !config.includeDesktopDestinations &&
            !config.includeDisplayDestinations {
            items.append(ConfigValidationItem(
                level: .warning,
                path: "experimental.titlebar_context_menu",
                message: tr("toutes les familles de destinations sont désactivées ; le menu ne s'affichera pas", "all destination families are disabled; menu will not be shown")
            ))
        }
        return items
    }

    private static func validateTargetMode(_ config: TargetModeConfig) -> [ConfigValidationItem] {
        var items: [ConfigValidationItem] = []
        if config.overlayDurationSeconds < 0.2 || config.overlayDurationSeconds > 30 {
            items.append(ConfigValidationItem(
                level: .error,
                path: "experimental.target_mode.overlay_duration_seconds",
                message: tr("doit être entre 0,2 et 30", "must be between 0.2 and 30")
            ))
        }
        if !config.enabled &&
            (config.pickerEnabled || config.overlayEnabled || config.appMouseActionsEnabled || config.scrollModeEnabled) {
            items.append(ConfigValidationItem(
                level: .warning,
                path: "experimental.target_mode",
                message: tr("le mode cible est désactivé ; ses fonctions seront ignorées", "target mode is disabled; sub-features will be ignored")
            ))
        }
        if !config.searchHotkey.isEmpty, TargetModeConfig.hotkeyParts(config.searchHotkey) == nil {
            items.append(ConfigValidationItem(
                level: .error,
                path: "experimental.target_mode.search_hotkey",
                message: tr("modificateurs et une touche attendus, par exemple \"cmd+alt+ctrl+f\" ou \"hyper+f\" ; vide : désactivé", "expected modifiers and one key, e.g. \"cmd+alt+ctrl+f\" or \"hyper+f\"; empty disables")
            ))
        }
        if !config.actionsHotkey.isEmpty, TargetModeConfig.hotkeyParts(config.actionsHotkey) == nil {
            items.append(ConfigValidationItem(
                level: .error,
                path: "experimental.target_mode.actions_hotkey",
                message: tr("modificateurs et une touche attendus, par exemple \"hyper+shift+f\" ; vide : désactivé", "expected modifiers and one key, e.g. \"hyper+shift+f\"; empty disables")
            ))
        }
        if !config.screenSearchHotkey.isEmpty, TargetModeConfig.hotkeyParts(config.screenSearchHotkey) == nil {
            items.append(ConfigValidationItem(
                level: .error,
                path: "experimental.target_mode.screen_search_hotkey",
                message: tr("modificateurs et une touche attendus, par exemple \"hyper+f\" ; vide : désactivé", "expected modifiers and one key, e.g. \"hyper+f\"; empty disables")
            ))
        }
        if !config.webSearchURL.contains("{query}") || URL(string: config.webSearchURL.replacingOccurrences(of: "{query}", with: "q")) == nil {
            items.append(ConfigValidationItem(
                level: .warning,
                path: "experimental.target_mode.web_search_url",
                message: tr("adresse attendue contenant {query}", "expected an address containing {query}")
            ))
        }
        return items
    }

    private static func validateAppTargets(_ config: AppTargetsConfig) -> [ConfigValidationItem] {
        var items: [ConfigValidationItem] = []
        if !AppTargetsConfig.scopes.contains(config.scope) {
            items.append(ConfigValidationItem(
                level: .warning,
                path: "experimental.app_targets.scope",
                message: tr("étendues possibles : frontmost_window, visible_windows", "supported scopes: frontmost_window, visible_windows")
            ))
        }
        if config.hintCharacters.count < 2 {
            items.append(ConfigValidationItem(
                level: .error,
                path: "experimental.app_targets.hint_characters",
                message: tr("doit contenir au moins deux caractères", "must contain at least two characters")
            ))
        }
        if config.includeRoles.isEmpty {
            items.append(ConfigValidationItem(
                level: .error,
                path: "experimental.app_targets.include_roles",
                message: tr("doit contenir au moins un rôle AX", "must contain at least one AX role")
            ))
        }
        return items
    }

    private static func validateTargetGrid(_ config: TargetGridConfig) -> [ConfigValidationItem] {
        var items: [ConfigValidationItem] = []
        if config.hintCharacters.count < config.rows * config.columns {
            items.append(ConfigValidationItem(
                level: .error,
                path: "experimental.target_grid.hint_characters",
                message: tr("doit contenir au moins rows*columns caractères", "must contain at least rows*columns characters")
            ))
        }
        return items
    }

    private static func validateTargetRecord(_ config: TargetRecordConfig) -> [ConfigValidationItem] {
        var items: [ConfigValidationItem] = []
        if config.defaultDurationSeconds > config.maxDurationSeconds {
            items.append(ConfigValidationItem(
                level: .error,
                path: "experimental.target_record.default_duration_seconds",
                message: tr("doit être inférieur ou égal à max_duration_seconds", "must be lower than or equal to max_duration_seconds")
            ))
        }
        if config.replayEnabled && !config.enabled {
            items.append(ConfigValidationItem(
                level: .warning,
                path: "experimental.target_record.replay_enabled",
                message: tr("la relecture est activée mais l'enregistrement est désactivé", "replay is enabled but recording capability is disabled")
            ))
        }
        return items
    }
}

extension WindowManagementMode {
    /// La config n'a pas d'état : `mutableBsp` et `yabai` y désignent directement l'unique
    /// moteur à arbre `spatialBsp` (SPEC-017 R1, A8).
    init?(tomlValue: String) {
        guard let mode = WindowManagementMode(roadieValue: tomlValue) else {
            return nil
        }
        self = mode == .mutableBsp ? .spatialBsp : mode
    }
}

extension KeyedDecodingContainer {
    /// Accepte un nombre décimal ou un entier TOML. Clé absente : `nil` (le défaut s'applique).
    /// Autre type (booléen, texte, tableau) : l'erreur de décodage est propagée, jamais remplacée
    /// par le défaut (REL-011).
    func decodeFlexibleDouble(forKey key: Key) throws -> Double? {
        let value: Double?
        do {
            value = try decodeIfPresent(Double.self, forKey: key)
        } catch {
            guard let integer = try? decodeIfPresent(Int.self, forKey: key) else { throw error }
            value = Double(integer)
        }
        // TOML autorise nan/inf, mais les cadres AX et les exports JSON exigent un nombre fini.
        guard value?.isFinite != false else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected a finite number")
        }
        return value
    }
}
