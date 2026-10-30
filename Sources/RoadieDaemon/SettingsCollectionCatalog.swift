import Foundation
import RoadieCore

extension SettingsCatalog {
    static func collectionSpec(id: String) -> CollectionSpec {
        func list(_ kind: SettingKind, _ values: [SettingValue], suggestions: [String] = [],
                  minCount: Int = 0, unique: Bool = false, sorted: Bool = false) -> CollectionSpec {
            CollectionSpec(shape: .list(element: kind, suggestions: suggestions, minCount: minCount,
                                        unique: unique, sorted: sorted), defaultValue: .list(values))
        }
        let labels: [String: String] = [
            "gaps_outer": tr("Marge générale (points)", "General gap (points)"), "gaps_outer_top": tr("Marge en haut (points)", "Top gap (points)"),
            "gaps_outer_right": tr("Marge à droite (points)", "Right gap (points)"), "gaps_outer_bottom": tr("Marge en bas (points)", "Bottom gap (points)"),
            "gaps_outer_left": tr("Marge à gauche (points)", "Left gap (points)"), "app": tr("Application", "App"), "app_regex": tr("Application (expression régulière)", "App (regular expression)"),
            "title": tr("Titre", "Title"), "title_regex": tr("Titre (expression régulière)", "Title (regular expression)"), "role": tr("Rôle d'accessibilité", "Accessibility role"),
            "subrole": tr("Sous-rôle d'accessibilité", "Accessibility subrole"), "display": tr("Écran", "Display"), "desktop": tr("Bureau", "Desktop"), "stage": "Stage",
            "manage": tr("Gérer la fenêtre", "Manage the window"), "exclude": tr("Exclure du tuilage", "Exclude from tiling"), "follow": tr("Suivre l'assignation", "Follow the assignment"),
            "floating": tr("Rendre flottante", "Make floating"), "emit_event": tr("Émettre un événement", "Emit an event"), "remember_frame": tr("Retenir la place", "Remember its place"), "assign_desktop": tr("Envoyer vers le bureau", "Send to desktop"),
            "assign_display": tr("Envoyer vers l'écran", "Send to display"), "assign_stage": tr("Envoyer vers le stage", "Send to stage"), "scratchpad": tr("Groupe temporaire", "Scratchpad")
        ]
        func field(_ key: String, _ label: String, _ kind: SettingKind = .text,
                   required: Bool = false, value: SettingValue = .unset, help: String = "",
                   choiceLabels: [String: String] = [:]) -> CollectionFieldSpec {
            CollectionFieldSpec(path: key.components(separatedBy: "."), label: label, help: help,
                                kind: kind, required: required, defaultValue: value, choiceLabels: choiceLabels)
        }
        func rows(_ table: String, _ fields: [CollectionFieldSpec], key: String? = nil,
                  oneOf: [[String]] = []) -> CollectionSpec {
            CollectionSpec(shape: .rows(table: table, fields: fields, uniqueKey: key, oneOf: oneOf), defaultValue: .rows([]))
        }
        switch id {
        case "tiling.smart_gaps_solo_sides":
            return list(.choice(GapSide.allCases.map(\.rawValue)), TilingConfig().smartGapsSoloSides.map { .string($0.rawValue) }, unique: true)
        case "tiling.allowed_subroles":
            return list(.text, TilingConfig().allowedSubroles.map(SettingValue.string), suggestions: ["AXStandardWindow", "AXDialog", "AXSystemDialog"])
        case "width_adjustment.presets":
            return list(.double(nil), WidthAdjustmentConfig().presets.map(SettingValue.double), minCount: 1, unique: true, sorted: true)
        case "app_targets.include_roles":
            return list(.text, AppTargetsConfig().includeRoles.map(SettingValue.string), suggestions: AppTargetsConfig().includeRoles, minCount: 1)
        case "app_targets.additional_boost_bundle_ids", "exclusions.floating_bundles":
            return list(.text, [])
        case "switcher.excluded_bundles":
            return list(.text, [], unique: true)
        case "target_mode.bookmark_browsers":
            return list(.choice(["firefox", "safari", "chrome", "brave", "edge"]),
                        TargetModeConfig().bookmarkBrowsers.map(SettingValue.string), unique: true)
        case "target_mode.btt_pause_keys":
            return list(.text, [], unique: true)
        case "shortcuts":
            return rows("shortcuts", [field("keys", tr("Combinaison", "Key combination")), field("command", tr("Commande", "Command"), required: true),
                                      field("enabled", tr("Active", "On"), .bool, value: .bool(true)), field("btt_uuid", tr("Raccourci BTT d'origine", "Original BTT shortcut"))])
        case "target_mode.app_search_paths":
            return list(.text, [], suggestions: ["~/Applications/Chrome Apps.localized", "/Applications/Utilities"], unique: true)
        case "switcher.shortcuts":
            let profile = WindowSwitcherShortcutConfig()
            var fields = [
                field("id", tr("Identifiant", "Identifier"), required: true, value: .string(profile.id),
                      help: tr("Nom interne du profil. Chaque profil doit avoir un identifiant distinct.", "Internal name of the profile. Each profile needs a distinct identifier.")),
                field("name", tr("Nom affiché", "Display name"), required: true, value: .string(profile.name),
                      help: tr("Nom lisible du profil, affiché dans la liste des profils.", "Readable name of the profile, shown in the profile list.")),
                field("hotkey", tr("Raccourci interne (facultatif)", "Built-in shortcut (optional)"), required: false, value: .string(profile.hotkey),
                      help: tr("Laissez vide avec BetterTouchTool ou Karabiner : ils exécutent roadie switcher cycle --hold cmd. Une combinaison ici active un raccourci géré par Roadie.", "Leave empty with BetterTouchTool or Karabiner: they run roadie switcher cycle --hold cmd. A combination here turns on a shortcut handled by Roadie.")),
                field("scope", tr("Fenêtres affichées", "Windows shown"), .choice(["stage", "desktop", "display", "application", "all"]),
                      required: true, value: .string(profile.scope),
                      help: tr("Fenêtres proposées : stage Roadie actif, bureau Roadie actif, écran actif, application active ou toutes les fenêtres gérées. Ces filtres suivent les stages et bureaux Roadie, pas les espaces natifs de macOS.", "Windows offered: active Roadie stage, active Roadie desktop, active display, active app or all managed windows. These filters follow Roadie stages and desktops, not native macOS Spaces."),
                      choiceLabels: ["stage": tr("Stage actif", "Active stage"), "desktop": tr("Bureau actif", "Active desktop"), "display": tr("Écran actif", "Active display"),
                                     "application": tr("Application active", "Active app"), "all": tr("Toutes les fenêtres", "All windows")]),
                field("release_action", tr("Action au relâchement", "Release action"), .choice(["focus", "stay", "search"]),
                      required: true, value: .string(profile.releaseAction),
                      help: tr("Ce qui se passe au relâchement de la touche ou à la validation. « Activer » donne le focus à la fenêtre choisie. « Garder ouvert » permet de rechercher puis de valider par Retour.", "What happens when the key is released or the choice is confirmed. “Activate” focuses the chosen window. “Keep open” lets you search, then confirm with Return."),
                      choiceLabels: ["focus": tr("Activer la fenêtre choisie", "Activate the chosen window"), "stay": tr("Garder le sélecteur ouvert", "Keep the switcher open"), "search": tr("Passer en recherche", "Switch to search")]),
                field("sort_order", tr("Tri", "Sort"), .choice(["recent", "title", "stage"]),
                      required: true, value: .string(profile.sortOrder),
                      help: tr("Ordre des fenêtres dans le sélecteur. « Récentes d'abord » place en tête les fenêtres utilisées récemment.", "Order of windows in the switcher. “Recent first” puts recently used windows at the top."),
                      choiceLabels: ["recent": tr("Récentes d'abord", "Recent first"), "title": tr("Titre (A à Z)", "Title (A to Z)"), "stage": tr("Par stage", "By stage")]),
                field("include_minimized", tr("Inclure les fenêtres réduites", "Include minimized windows"), .bool, value: .bool(profile.includeMinimized),
                      help: tr("Affiche aussi les fenêtres réduites.", "Also shows minimized windows.")),
                field("include_hidden", tr("Inclure les applications masquées", "Include hidden apps"), .bool, value: .bool(profile.includeHidden),
                      help: tr("Affiche aussi les fenêtres des applications masquées (Cmd+H).", "Also shows windows of hidden apps (Cmd+H).")),
                field("include_fullscreen", tr("Inclure les fenêtres plein écran", "Include full-screen windows"), .bool, value: .bool(profile.includeFullscreen),
                      help: tr("Affiche aussi les fenêtres en plein écran macOS.", "Also shows windows in macOS full screen.")),
                field("one_per_app", tr("Une fenêtre par application", "One window per app"), .bool, value: .bool(profile.onePerApp),
                      help: tr("Affiche seulement la fenêtre la plus récente de chaque application.", "Shows only the most recent window of each app.")),
            ]
            fields += [
                field("btt_forward_uuid", tr("Liaison BTT", "BTT binding"), value: .string("")),
                field("btt_reverse_uuid", tr("Liaison BTT inverse", "Reverse BTT binding"), value: .string("")),
                field("enabled", tr("Profil actif", "Profile on"), .bool, value: .bool(true)),
                field("trigger_source", tr("Gestionnaire du raccourci", "Shortcut handler"), .choice(["external", "roadie", "btt"]), value: .string("external"),
                      choiceLabels: ["external": tr("Commande ou outil externe", "Command or external tool"), "roadie": "Roadie", "btt": "BetterTouchTool"]),
                field("search_visibility", tr("Champ de recherche", "Search field"), .choice(["auto", "always", "never"]), value: .string("auto"),
                      choiceLabels: ["auto": tr("Selon le mode", "Depends on mode"), "always": tr("Toujours visible", "Always visible"), "never": tr("Masqué", "Hidden")]),
                field("actions_visibility", tr("Menu Actions", "Actions menu"), .choice(["auto", "always", "never"]), value: .string("auto"),
                      choiceLabels: ["auto": tr("Selon le mode", "Depends on mode"), "always": tr("Toujours visible", "Always visible"), "never": tr("Masqué", "Hidden")]),
                field("arrow_navigation", tr("Navigation aux quatre flèches", "Four-arrow navigation"), .bool, value: .bool(true)),
                field("mouse_hover", tr("Sélection au survol", "Select on hover"), .bool, value: .bool(true)),
                field("style", tr("Présentation du profil", "Profile style"), .choice(["thumbnails", "icons", "list"]),
                      choiceLabels: ["thumbnails": tr("Vignettes", "Thumbnails"), "icons": tr("Icônes", "Icons"), "list": tr("Liste compacte", "Compact list")]),
                field("presentation", tr("Organisation du profil", "Profile layout"), .choice(WindowSwitcherPresentation.allCases.map(\.rawValue)),
                      choiceLabels: Dictionary(uniqueKeysWithValues: WindowSwitcherPresentation.allCases.map { ($0.rawValue, $0.label) })),
                field("preview", tr("Grand aperçu du profil", "Profile large preview"), .bool),
                field("auto_size", tr("Taille automatique du profil", "Profile automatic size"), .bool),
                field("thumbnail_width", tr("Largeur des vignettes du profil", "Profile thumbnail width"), .double(120...400)),
                field("font_size", tr("Taille du texte du profil", "Profile text size"), .double(10...32)),
                field("font_family", tr("Police du profil", "Profile font")),
            ]
            let defaultRow = Dictionary(uniqueKeysWithValues: fields.map { ($0.path.joined(separator: "."), $0.defaultValue) })
            return CollectionSpec(shape: .rows(table: id, fields: fields, uniqueKey: "id", oneOf: []),
                                  defaultValue: .rows([CollectionRow(fields: defaultRow)]))
        case "tiling.display_overrides":
            return rows(id, [field("display_id", tr("Identifiant de l'écran", "Display identifier")), field("display_name", tr("Nom de l'écran", "Display name"))]
                        + ["gaps_outer", "gaps_outer_top", "gaps_outer_right", "gaps_outer_bottom", "gaps_outer_left"].map { field($0, labels[$0] ?? $0, .double(nil)) },
                        oneOf: [["display_id", "display_name"]])
        case "exclusions.floating_windows":
            return rows(id, [field("app", tr("Application", "App"), required: true, help: tr("Nom affiché (Thunderbird) ou identifiant (org.mozilla.thunderbird).", "Display name (Thunderbird) or identifier (org.mozilla.thunderbird).")),
                             field("title", tr("Titre", "Title"), required: true, help: tr("# : un nombre ; * : n'importe quel texte. Exemple : # Reminder.", "#: a number; *: any text. Example: # Reminder.")),
                             field("remember_frame", labels["remember_frame"] ?? "", .bool, value: .bool(false),
                                   help: tr("La fenêtre rouvre là où vous l'avez laissée, à la même taille.", "The window reopens where you left it, at the same size."))])
        case "stage_manager.workspaces":
            return rows(id, [field("id", tr("Identifiant", "Identifier"), required: true), field("display_name", tr("Nom du stage", "Stage name"), required: true)], key: "id")
        case "borders.stage_overrides", "rail.preview.stage_overrides":
            return rows("fx." + id, [field("stage_id", tr("Identifiant du stage", "Stage identifier"), required: true), field("active_color", tr("Couleur", "Color"), .color)], key: "stage_id")
        case "rules":
            var fields = [field("id", tr("Identifiant", "Identifier"), required: true), field("enabled", tr("Activée", "On"), .bool, value: .bool(true)),
                          field("priority", tr("Priorité", "Priority"), .int(nil), value: .int(0)),
                          field("stop_processing", tr("Arrêter après cette règle", "Stop after this rule"), .bool, value: .bool(false))]
            fields += ["app", "app_regex", "title", "title_regex", "role", "subrole", "display", "desktop", "stage"].map { field("match." + $0, tr("Critère : ", "Match: ") + (labels[$0] ?? $0)) }
            fields.append(field("match.is_floating", tr("Fenêtre flottante", "Floating window"), .bool))
            fields += ["manage", "exclude", "follow", "floating", "emit_event", "remember_frame"].map { field("action." + $0, tr("Action : ", "Action: ") + (labels[$0] ?? $0), .bool) }
            fields += ["assign_desktop", "assign_display", "assign_stage", "scratchpad"].map { field("action." + $0, tr("Action : ", "Action: ") + (labels[$0] ?? $0)) }
            let storedActionHelp = tr("Enregistré dans la règle. Ce paramètre ne modifie pas encore le tuilage.", "Saved in the rule. This setting does not change tiling yet.")
            fields += [field("action.layout", tr("Méthode de tuilage", "Tiling method"), .text, help: storedActionHelp),
                       field("action.gap_override", tr("Marge", "Gap"), .int(nil), help: storedActionHelp)]
            return rows("rules", fields, key: "id")
        default:
            return CollectionSpec(shape: .advanced(table: "signals.hooks"), defaultValue: .advanced(""))
        }
    }
}
