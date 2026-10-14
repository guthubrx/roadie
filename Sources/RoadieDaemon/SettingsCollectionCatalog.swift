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
                   required: Bool = false, value: SettingValue = .unset, help: String = "") -> CollectionFieldSpec {
            CollectionFieldSpec(path: key.components(separatedBy: "."), label: label, help: help,
                                kind: kind, required: required, defaultValue: value)
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
        case "tiling.display_overrides":
            return rows(id, [field("display_id", "Identifiant de l'écran"), field("display_name", "Nom de l'écran")]
                        + ["gaps_outer", "gaps_outer_top", "gaps_outer_right", "gaps_outer_bottom", "gaps_outer_left"].map { field($0, labels[$0] ?? $0, .double(nil)) },
                        oneOf: [["display_id", "display_name"]])
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
