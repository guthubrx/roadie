import Foundation
import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct SettingsCatalogTests {
    private var simple: [SettingDescriptor] { SettingsCatalog.all.filter { $0.readOnlyReason == nil && $0.collection == nil } }
    private var railSimple: [SettingDescriptor] { simple.filter { $0.tablePath.hasPrefix("fx.rail") } }

    // MARK: - Structure

    @Test
    func identifiersAreUnique() {
        let ids = SettingsCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test
    func catalogHas195SimpleSettings() {
        // Spec056 : 7 réglages du sélecteur ; les listes du sélecteur sont des collections.
        // Spec075 : raccourci des verbes et recherche web. Spec088 : deux réglages des workflows.
        #expect(simple.count == 203)
        #expect(railSimple.count == 80)
        #expect(simple.count - railSimple.count == 123)
    }

    @Test
    func tilingChoiceLabelsAreReadableAndRetainTheirTechnicalNames() throws {
        for id in ["tiling.default_strategy", "tiling.split_policy"] {
            let descriptor = try #require(SettingsCatalog.find(id: id))
            guard case .choice(let choices) = descriptor.kind else { Issue.record("choix attendu"); return }
            let labels = choices.map { descriptor.choiceLabel($0) }
            #expect(Set(labels).count == choices.count)
            for value in choices {
                #expect(descriptor.choiceLabel(value) != value)
                #expect(descriptor.choiceLabel(value).hasSuffix("(\(value))"))
            }
        }
        let other = try #require(SettingsCatalog.find(id: "window_placement.new_window_side"))
        #expect(other.choiceLabel("left") == "left")
    }

    @Test
    func placementChoicesUseReadableLabelsAndMatchTheConfigDefault() throws {
        let setting = try #require(SettingsCatalog.find(id: "window_placement.new_apps_target"))
        #expect(setting.defaultValue == .string(WindowPlacementConfig().newAppsTarget))
        guard case .choice(let values) = setting.kind else { Issue.record("choix attendu"); return }
        #expect(values == ["focused_display", "mouse", "macos"])
        #expect(setting.choiceLabel("focused_display") == "Écran actif (recommandé)")
        #expect(setting.choiceLabel("mouse") == "Écran de la souris")
        #expect(setting.choiceLabel("macos") == "Choix de macOS")
        #expect(setting.choiceLabel("future") == "future")
    }

    @Test
    func strategyAliasesMatchTheLoader() throws {
        let strategy = try #require(SettingsCatalog.find(id: "tiling.default_strategy"))
        guard case .choice(let choices) = strategy.kind else { Issue.record("choix attendu"); return }
        for alias in ["spatial_bsp", "master_stack", "mutable_bsp", "bsp", "float", "SPATIAL_BSP", " tree "] {
            let canonical = SettingsCatalog.canonicalChoice(alias, for: strategy.id)
            #expect(choices.contains(canonical), "\(alias) → \(canonical)")
            // Même résultat que le chargeur : `mutableBsp` y devient `spatialBsp`.
            let loaded = try #require(WindowManagementMode(roadieValue: canonical))
            let expected = try #require(WindowManagementMode(roadieValue: alias.trimmingCharacters(in: .whitespaces).lowercased() == "spatial_bsp" ? "spatial_bsp" : alias.trimmingCharacters(in: .whitespaces)))
            #expect(loaded == (expected == .mutableBsp ? .spatialBsp : expected), "\(alias)")
        }
        #expect(SettingsCatalog.canonicalChoice("spirale", for: strategy.id) == "spirale")
        #expect(SettingsCatalog.canonicalChoice("spatial_bsp", for: "tiling.split_policy") == "spatial_bsp")
    }

    @Test
    func collectionsAreEditableListsAndTableArrays() {
        let readOnly = Set(SettingsCatalog.all.filter { $0.collection != nil }.map(\.id))
        #expect(readOnly == [
            "tiling.smart_gaps_solo_sides", "tiling.allowed_subroles", "exclusions.floating_bundles",
            "width_adjustment.presets", "app_targets.include_roles", "app_targets.additional_boost_bundle_ids",
            "tiling.display_overrides", "stage_manager.workspaces", "borders.stage_overrides",
            "rail.preview.stage_overrides", "rules", "signals.hooks",
            "switcher.excluded_bundles", "switcher.shortcuts",
        ])
        for descriptor in SettingsCatalog.all where descriptor.collection != nil {
            #expect(descriptor.readOnlyReason == nil)
            #expect(descriptor.defaultValue != .unset)
        }
    }

    @Test
    func categoriesAreFilled() {
        for category in SettingCategory.allCases {
            #expect(!SettingsCatalog.descriptors(in: category).isEmpty, "catégorie vide : \(category.rawValue)")
            #expect(!category.label.isEmpty && !category.symbolName.isEmpty)
        }
        #expect(SettingCategory.rail.label == "Rail")
        #expect(SettingCategory.stages.label == "Stages et bureaux")
        #expect(SettingsCatalog.find(id: "target_mode.search_hotkey")?.category == .recherche)
        #expect(SettingsCatalog.find(id: "stage_manager.default_stage")?.category == .stages)
        #expect(SettingsCatalog.find(id: "stage_manager.workspaces")?.category == .stages)
        #expect(SettingsCatalog.find(id: "borders.stage_overrides")?.category == .bordures)
        #expect(SettingsCatalog.find(id: "rail.preview.stage_overrides")?.category == .rail)
        #expect(SettingsCatalog.find(id: "target_record.enabled")?.category == .avance)
    }

    @Test
    func idsFollowTheTablePathAndKey() {
        #expect(SettingsCatalog.id(tablePath: "experimental.target_grid", key: "rows") == "target_grid.rows")
        #expect(SettingsCatalog.id(tablePath: "fx.rail.header.display", key: "font_size") == "rail.header.display.font_size")
        #expect(SettingsCatalog.id(tablePath: "fx.borders", key: "active_color") == "borders.active_color")
        #expect(SettingsCatalog.id(tablePath: "tiling", key: "gaps_outer") == "tiling.gaps_outer")
        #expect(SettingsCatalog.id(tablePath: "", key: "rules") == "rules")
        for descriptor in SettingsCatalog.all {
            #expect(descriptor.id == SettingsCatalog.id(tablePath: descriptor.tablePath, key: descriptor.key))
            #expect(!descriptor.id.hasPrefix("experimental.") && !descriptor.id.hasPrefix("fx."))
        }
    }

    @Test
    func descriptorsAreCoherent() {
        for descriptor in simple {
            let id = descriptor.id
            #expect(!descriptor.label.isEmpty && !descriptor.help.isEmpty, "texte vide : \(id)")
            switch (descriptor.kind, descriptor.defaultValue) {
            case (.bool, .bool):
                break
            case (.int(let range), .int(let value)):
                #expect(range?.contains(value) ?? true, "défaut hors plage : \(id)")
            case (.double(let range), .double(let value)):
                #expect(range?.contains(value) ?? true, "défaut hors plage : \(id)")
            case (.choice(let choices), .string(let value)):
                #expect(choices.contains(value), "défaut hors choix : \(id)")
            case (.text, .string):
                break
            case (.color, .string(let value)):
                #expect(isHexColor(value), "couleur invalide : \(id)")
            case (.double, .unset):
                // Marges facultatives : absentes du fichier par défaut.
                #expect(id.hasPrefix("tiling.gaps_outer_"), "défaut absent inattendu : \(id)")
            default:
                Issue.record("type et défaut incohérents : \(id)")
            }
        }
    }

    // MARK: - Dérive par rapport au validateur

    @Test
    func catalogMatchesTheScalarKeysKnownByTheValidator() {
        // Exclusions voulues : les clés sans effet (`desktops.*`, `stage_manager.enabled|hide_strategy`)
        // et la table héritée `fx.rail.header` (16 clés remplacées par `header.display` et `header.desktop`).
        // `knownScalarKeys()` omet déjà les listes et les tableaux de tables.
        let ineffective = RoadieConfigLoader.ineffectiveKeys()
        var expected: Set<String> = []
        for (table, keys) in RoadieConfigLoader.knownScalarKeys() where table != "fx.rail.header" {
            for key in keys where ineffective[table]?.contains(key) != true {
                expected.insert("\(table).\(key)")
            }
        }
        let described = Set(simple.map { "\($0.tablePath).\($0.key)" })

        let missing = expected.subtracting(described).sorted()
        let extra = described.subtracting(expected).sorted()
        #expect(missing.isEmpty, "clés du validateur sans descripteur : \(missing.joined(separator: ", "))")
        #expect(extra.isEmpty, "descripteurs sans clé connue du validateur : \(extra.joined(separator: ", "))")
        #expect(expected.count == 203)
    }

    // MARK: - Défauts

    @Test
    func configDefaultsMatchRoadieConfig() throws {
        let tree = try jsonTree(RoadieConfig())
        for descriptor in simple where !descriptor.tablePath.hasPrefix("fx.rail") {
            let json = jsonValue(tree, tablePath: descriptor.tablePath, key: descriptor.key)
            switch descriptor.defaultValue {
            case .unset:
                #expect(json == nil, "défaut attendu absent : \(descriptor.id)")
            case .bool(let expected):
                #expect(isBool(json) && (json as? Bool) == expected, "défaut différent : \(descriptor.id)")
            case .int(let expected):
                #expect(numeric(json) == Double(expected), "défaut différent : \(descriptor.id)")
            case .double(let expected):
                #expect(numeric(json).map { abs($0 - expected) < 1e-9 } == true, "défaut différent : \(descriptor.id)")
            case .string(let expected):
                #expect((json as? String) == expected, "défaut différent : \(descriptor.id)")
            }
        }
    }

    @Test
    func railDefaultsMatchRailSettings() {
        let status = statusDictionary(RailSettings.load(raw: ""))
        // Les 80 clés du rail ont un descripteur, et inversement.
        #expect(Set(railSimple.map { String($0.id.dropFirst("rail.".count)) }) == Set(status.keys))
        for descriptor in railSimple {
            let name = String(descriptor.id.dropFirst("rail.".count))
            let actual = status[name]
            switch descriptor.defaultValue {
            case .bool(let expected): #expect(actual == "\(expected)", "défaut différent : \(descriptor.id)")
            case .double(let expected): #expect(actual.flatMap(Double.init) == expected, "défaut différent : \(descriptor.id)")
            case .string(let expected): #expect(actual == expected, "défaut différent : \(descriptor.id)")
            default: Issue.record("type de défaut inattendu pour le rail : \(descriptor.id)")
            }
        }
    }

    // MARK: - Plages

    @Test
    func railRangesAreTheClampsOfRailSettings() {
        var checked = 0
        for descriptor in railSimple {
            guard case .double(let range?) = descriptor.kind else { continue }
            let name = String(descriptor.id.dropFirst("rail.".count))
            let low = statusDictionary(RailSettings.load(raw: rail(descriptor, range.lowerBound - 1000)))[name]
            let high = statusDictionary(RailSettings.load(raw: rail(descriptor, range.upperBound + 1000)))[name]
            #expect(low.flatMap(Double.init) == range.lowerBound, "borne basse : \(descriptor.id)")
            #expect(high.flatMap(Double.init) == range.upperBound, "borne haute : \(descriptor.id)")
            checked += 1
        }
        // 80 clés du rail, dont 49 numériques.
        #expect(checked == 49)
    }

    @Test
    func configRangesAreTheCodeLimits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("settings-catalog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("roadies.toml").path

        var checked = 0
        for descriptor in simple where !descriptor.tablePath.hasPrefix("fx.rail") {
            let bounds: (low: Double, high: Double)
            switch descriptor.kind {
            case .int(let range?): bounds = (Double(range.lowerBound), Double(range.upperBound))
            case .double(let range?): bounds = (range.lowerBound, range.upperBound)
            default: continue
            }
            // La durée par défaut est bornée par la durée maximale : sa borne haute n'est pas fixe.
            let checkHigh = descriptor.id != "target_record.default_duration_seconds"
            let sides: [(value: Double, expected: Double, side: String)] =
                [(bounds.low - 1, bounds.low, "basse")] + (checkHigh ? [(bounds.high + 1, bounds.high, "haute")] : [])
            for (value, expected, side) in sides {
                let outcome = try loadWithValue(descriptor, value, path: path)
                // Hors plage : le code borne la valeur, ou la validation signale une erreur sur ce réglage.
                #expect(outcome.loaded == expected || outcome.errorOnKey, "borne \(side) non respectée : \(descriptor.id)")
            }
            if checkHigh {
                // Les bornes elles-mêmes sont acceptées telles quelles.
                for expected in [bounds.low, bounds.high] {
                    let outcome = try loadWithValue(descriptor, expected, path: path)
                    #expect(outcome.loaded == expected && !outcome.errorOnKey, "borne refusée : \(descriptor.id)")
                }
            }
            checked += 1
        }
        // 32 réglages hors rail ont une plage.
        #expect(checked == 32)
    }

    // MARK: - Recherche

    @Test
    func searchForBordureFindsExactlyTheBorderSettings() {
        let found = SettingsCatalog.search("bordure")
        #expect(Set(found.map(\.id)) == Set(simple.filter { $0.id.hasPrefix("borders.") }.map(\.id)))
        #expect(found.count == 6)
    }

    @Test
    func searchIgnoresCaseAndAccents() {
        let withAccent = SettingsCatalog.search("règles").map(\.id)
        #expect(!withAccent.isEmpty)
        #expect(SettingsCatalog.search("regles").map(\.id) == withAccent)
        #expect(SettingsCatalog.search("REGLES").map(\.id) == withAccent)
        #expect(SettingsCatalog.search("  Épaisseur ").map(\.id) == SettingsCatalog.search("epaisseur").map(\.id))
        #expect(withAccent.contains("rules"))
    }

    @Test
    func searchMatchesNameLabelAndHelp() {
        #expect(SettingsCatalog.search("target_grid.rows").map(\.id) == ["target_grid.rows"])
        #expect(SettingsCatalog.search("Nombre de colonnes").map(\.id) == ["target_grid.columns"])
        #expect(SettingsCatalog.search("sous le pointeur").map(\.id) == ["focus.focus_follows_mouse"])
        #expect(SettingsCatalog.search("").isEmpty)
        #expect(SettingsCatalog.search("zzzzzz").isEmpty)
    }

    @Test
    func findReturnsTheGridRowsDescriptor() throws {
        let rows = try #require(SettingsCatalog.find(id: "target_grid.rows"))
        #expect(rows.kind == .int(2...12))
        #expect(rows.defaultValue == .int(3))
        #expect(rows.tablePath == "experimental.target_grid")
        #expect(SettingsCatalog.find(id: "target_grid.nope") == nil)
    }

    @Test
    func labelFontSizeKeysExistForLettersAndGrid() throws {
        for id in ["target_mode.label_font_size", "target_grid.label_font_size"] {
            let size = try #require(SettingsCatalog.find(id: id))
            #expect(size.kind == .double(8...48))
            #expect(size.defaultValue == .double(13))
            #expect(size.label == "Taille des étiquettes (points)")
        }
    }

    // MARK: - Aides

    private func isHexColor(_ value: String) -> Bool {
        value.range(of: "^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$", options: .regularExpression) != nil
    }

    private func jsonTree(_ config: RoadieConfig) throws -> [String: Any] {
        let data = try JSONEncoder().encode(config)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Suit le chemin TOML (`experimental.target_grid`) dans l'arbre JSON de la configuration.
    private func jsonValue(_ tree: [String: Any], tablePath: String, key: String) -> Any? {
        var node: Any? = tree
        for part in tablePath.split(separator: ".") {
            node = (node as? [String: Any])?[String(part)]
        }
        return (node as? [String: Any])?[key]
    }

    private func isBool(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private func numeric(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, !isBool(value) else { return nil }
        return number.doubleValue
    }

    /// `clé=valeur` de `statusLines`, sans le préfixe `rail.` des identifiants.
    private func statusDictionary(_ settings: RailSettings) -> [String: String] {
        var result: [String: String] = [:]
        for line in settings.statusLines {
            guard let equals = line.firstIndex(of: "=") else { continue }
            result[String(line[..<equals])] = String(line[line.index(after: equals)...])
        }
        return result
    }

    private func rail(_ descriptor: SettingDescriptor, _ value: Double) -> String {
        "[\(descriptor.tablePath)]\n\(descriptor.key) = \(value)\n"
    }

    /// Écrit `[table]\nclé = valeur`, charge la configuration et valide le fichier.
    private func loadWithValue(
        _ descriptor: SettingDescriptor, _ value: Double, path: String
    ) throws -> (loaded: Double?, errorOnKey: Bool) {
        let literal: String
        if case .int = descriptor.kind { literal = "\(Int(value))" } else { literal = "\(value)" }
        try "[\(descriptor.tablePath)]\n\(descriptor.key) = \(literal)\n".write(toFile: path, atomically: true, encoding: .utf8)
        let tree = try jsonTree(RoadieConfigLoader.load(from: path))
        let loaded = numeric(jsonValue(tree, tablePath: descriptor.tablePath, key: descriptor.key))
        let fullPath = "\(descriptor.tablePath).\(descriptor.key)"
        let errorOnKey = RoadieConfigLoader.validate(path: path).items.contains { $0.level == .error && $0.path == fullPath }
        return (loaded, errorOnKey)
    }
}
