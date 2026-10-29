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
            "gaps_outer": "Marge générale (points)", "gaps_outer_top": "Marge en haut (points)",
            "gaps_outer_right": "Marge à droite (points)", "gaps_outer_bottom": "Marge en bas (points)",
            "gaps_outer_left": "Marge à gauche (points)", "app": "Application", "app_regex": "Application (expression régulière)",
            "title": "Titre", "title_regex": "Titre (expression régulière)", "role": "Rôle d'accessibilité",
            "subrole": "Sous-rôle d'accessibilité", "display": "Écran", "desktop": "Bureau", "stage": "Stage",
            "manage": "Gérer la fenêtre", "exclude": "Exclure du tuilage", "follow": "Suivre l'assignation",
            "floating": "Rendre flottante", "emit_event": "Émettre un événement", "assign_desktop": "Envoyer vers le bureau",
            "assign_display": "Envoyer vers l'écran", "assign_stage": "Envoyer vers le stage", "scratchpad": "Groupe temporaire"
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
            return rows("shortcuts", [field("keys", "Combinaison"), field("command", "Commande", required: true),
                                      field("enabled", "Active", .bool, value: .bool(true)), field("btt_uuid", "Raccourci BTT d'origine")])
        case "target_mode.app_search_paths":
            return list(.text, [], suggestions: ["~/Applications/Chrome Apps.localized", "/Applications/Utilities"], unique: true)
        case "switcher.shortcuts":
            let profile = WindowSwitcherShortcutConfig()
            var fields = [
                field("id", "Identifiant", required: true, value: .string(profile.id),
                      help: "Nom interne du profil. Chaque profil doit avoir un identifiant distinct."),
                field("name", "Nom affiché", required: true, value: .string(profile.name),
                      help: "Nom lisible du profil, affiché dans la liste des profils."),
                field("hotkey", "Raccourci interne (facultatif)", required: false, value: .string(profile.hotkey),
                      help: "Laissez vide avec BetterTouchTool ou Karabiner : ils exécutent roadie switcher cycle --hold cmd. Une combinaison ici active un raccourci géré par Roadie."),
                field("scope", "Fenêtres affichées", .choice(["stage", "desktop", "display", "application", "all"]),
                      required: true, value: .string(profile.scope),
                      help: "Fenêtres proposées : stage Roadie actif, bureau Roadie actif, écran actif, application active ou toutes les fenêtres gérées. Ces filtres suivent les stages et bureaux Roadie, pas les espaces natifs de macOS.",
                      choiceLabels: ["stage": "Stage actif", "desktop": "Bureau actif", "display": "Écran actif",
                                     "application": "Application active", "all": "Toutes les fenêtres"]),
                field("release_action", "Action au relâchement", .choice(["focus", "stay", "search"]),
                      required: true, value: .string(profile.releaseAction),
                      help: "Ce qui se passe au relâchement de la touche ou à la validation. « Activer » donne le focus à la fenêtre choisie. « Garder ouvert » permet de rechercher puis de valider par Retour.",
                      choiceLabels: ["focus": "Activer la fenêtre choisie", "stay": "Garder le sélecteur ouvert", "search": "Passer en recherche"]),
                field("sort_order", "Tri", .choice(["recent", "title", "stage"]),
                      required: true, value: .string(profile.sortOrder),
                      help: "Ordre des fenêtres dans le sélecteur. « Récentes d'abord » place en tête les fenêtres utilisées récemment.",
                      choiceLabels: ["recent": "Récentes d'abord", "title": "Titre (A à Z)", "stage": "Par stage"]),
                field("include_minimized", "Inclure les fenêtres réduites", .bool, value: .bool(profile.includeMinimized),
                      help: "Affiche aussi les fenêtres réduites."),
                field("include_hidden", "Inclure les applications masquées", .bool, value: .bool(profile.includeHidden),
                      help: "Affiche aussi les fenêtres des applications masquées (Cmd+H)."),
                field("include_fullscreen", "Inclure les fenêtres plein écran", .bool, value: .bool(profile.includeFullscreen),
                      help: "Affiche aussi les fenêtres en plein écran macOS."),
                field("one_per_app", "Une fenêtre par application", .bool, value: .bool(profile.onePerApp),
                      help: "Affiche seulement la fenêtre la plus récente de chaque application."),
            ]
            fields += [
                field("btt_forward_uuid", "Liaison BTT", value: .string("")),
                field("btt_reverse_uuid", "Liaison BTT inverse", value: .string("")),
                field("enabled", "Profil actif", .bool, value: .bool(true)),
                field("trigger_source", "Gestionnaire du raccourci", .choice(["external", "roadie", "btt"]), value: .string("external"),
                      choiceLabels: ["external": "Commande ou outil externe", "roadie": "Roadie", "btt": "BetterTouchTool"]),
                field("search_visibility", "Champ de recherche", .choice(["auto", "always", "never"]), value: .string("auto"),
                      choiceLabels: ["auto": "Selon le mode", "always": "Toujours visible", "never": "Masqué"]),
                field("actions_visibility", "Menu Actions", .choice(["auto", "always", "never"]), value: .string("auto"),
                      choiceLabels: ["auto": "Selon le mode", "always": "Toujours visible", "never": "Masqué"]),
                field("arrow_navigation", "Navigation aux quatre flèches", .bool, value: .bool(true)),
                field("mouse_hover", "Sélection au survol", .bool, value: .bool(true)),
                field("style", "Présentation du profil", .choice(["thumbnails", "icons", "list"]),
                      choiceLabels: ["thumbnails": "Vignettes", "icons": "Icônes", "list": "Liste compacte"]),
                field("presentation", "Organisation du profil", .choice(WindowSwitcherPresentation.allCases.map(\.rawValue)),
                      choiceLabels: Dictionary(uniqueKeysWithValues: WindowSwitcherPresentation.allCases.map { ($0.rawValue, $0.label) })),
                field("preview", "Grand aperçu du profil", .bool),
                field("auto_size", "Taille automatique du profil", .bool),
                field("thumbnail_width", "Largeur des vignettes du profil", .double(120...400)),
                field("font_size", "Taille du texte du profil", .double(10...32)),
                field("font_family", "Police du profil"),
            ]
            let defaultRow = Dictionary(uniqueKeysWithValues: fields.map { ($0.path.joined(separator: "."), $0.defaultValue) })
            return CollectionSpec(shape: .rows(table: id, fields: fields, uniqueKey: "id", oneOf: []),
                                  defaultValue: .rows([CollectionRow(fields: defaultRow)]))
        case "tiling.display_overrides":
            return rows(id, [field("display_id", "Identifiant de l'écran"), field("display_name", "Nom de l'écran")]
                        + ["gaps_outer", "gaps_outer_top", "gaps_outer_right", "gaps_outer_bottom", "gaps_outer_left"].map { field($0, labels[$0] ?? $0, .double(nil)) },
                        oneOf: [["display_id", "display_name"]])
        case "exclusions.floating_windows":
            return rows(id, [field("app", "Application", required: true, help: "Nom affiché (Thunderbird) ou identifiant (org.mozilla.thunderbird)."),
                             field("title", "Titre", required: true, help: "# : un nombre ; * : n'importe quel texte. Exemple : # Reminder.")])
        case "stage_manager.workspaces":
            return rows(id, [field("id", "Identifiant", required: true), field("display_name", "Nom du stage", required: true)], key: "id")
        case "borders.stage_overrides", "rail.preview.stage_overrides":
            return rows("fx." + id, [field("stage_id", "Identifiant du stage", required: true), field("active_color", "Couleur", .color)], key: "stage_id")
        case "rules":
            var fields = [field("id", "Identifiant", required: true), field("enabled", "Activée", .bool, value: .bool(true)),
                          field("priority", "Priorité", .int(nil), value: .int(0)),
                          field("stop_processing", "Arrêter après cette règle", .bool, value: .bool(false))]
            fields += ["app", "app_regex", "title", "title_regex", "role", "subrole", "display", "desktop", "stage"].map { field("match." + $0, "Critère : " + (labels[$0] ?? $0)) }
            fields.append(field("match.is_floating", "Fenêtre flottante", .bool))
            fields += ["manage", "exclude", "follow", "floating", "emit_event"].map { field("action." + $0, "Action : " + (labels[$0] ?? $0), .bool) }
            fields += ["assign_desktop", "assign_display", "assign_stage", "scratchpad"].map { field("action." + $0, "Action : " + (labels[$0] ?? $0)) }
            let storedActionHelp = "Enregistré dans la règle. Ce paramètre ne modifie pas encore le tuilage."
            fields += [field("action.layout", "Méthode de tuilage", .text, help: storedActionHelp),
                       field("action.gap_override", "Marge", .int(nil), help: storedActionHelp)]
            return rows("rules", fields, key: "id")
        default:
            return CollectionSpec(shape: .advanced(table: "signals.hooks"), defaultValue: .advanced(""))
        }
    }
}
