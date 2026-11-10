import Foundation
import Testing
import TOMLKit
import RoadieCore

/// Garde-fous des réglages (spec 155, US3) : un réglage ajouté à moitié fait échouer un test.
@Suite struct Spec155ConfigGuardTests {
    // O(n), n = valeurs de la configuration encodée.
    private func walk(
        _ table: [String: Any], path: String, known: [String: Set<String>],
        unknown: inout [String], unchecked: inout [String]
    ) {
        for (key, value) in table {
            let childPath = path.isEmpty ? key : "\(path).\(key)"
            if let child = value as? [String: Any] {
                if known[childPath] == nil {
                    unchecked.append(childPath)
                } else {
                    walk(child, path: childPath, known: known, unknown: &unknown, unchecked: &unchecked)
                }
            } else if let rows = value as? [[String: Any]], known[childPath] != nil {
                for row in rows { walk(row, path: childPath, known: known, unknown: &unknown, unchecked: &unchecked) }
            } else if known[path]?.contains(key) != true {
                unknown.append(childPath)
            }
        }
    }

    @Test func everyDefaultSettingIsKnownByTheValidator() throws {
        let data = try JSONEncoder().encode(RoadieConfig())
        let tree = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var unknown: [String] = []
        var unchecked: [String] = []
        walk(tree, path: "", known: RoadieConfigLoader.knownKeys(), unknown: &unknown, unchecked: &unchecked)

        // Les tableaux de tables sont parcourus avec leur propre chemin de validation.
        #expect(unknown.isEmpty, "réglages encodés mais absents de knownKeys : \(unknown.sorted())")
        #expect(unchecked.isEmpty, "tables encodées mais absentes de knownKeys : \(unchecked.sorted())")
    }

    @Test func anEmptyFileGivesTheDefaultConfiguration() throws {
        let decoded = try TOMLDecoder().decode(RoadieConfig.self, from: "")
        #expect(decoded == RoadieConfig())
    }
    @Test func optionalSettingsAndTableRowsAreAlsoKnown() throws {
        var config = RoadieConfig()
        config.tiling.gapsOuterTop = 1; config.tiling.gapsOuterRight = 2
        config.tiling.gapsOuterBottom = 3; config.tiling.gapsOuterLeft = 4
        config.tiling.displayOverrides = [DisplayTilingOverride(displayID: "id", displayName: "Screen", gapsOuter: 8,
            gapsOuterTop: 1, gapsOuterRight: 2, gapsOuterBottom: 3, gapsOuterLeft: 4)]
        config.stageManager.workspaces = [StageDefinition(id: "1", displayName: "Work")]
        config.exclusions.floatingWindows = [FloatingWindowConfig(app: "Test", title: "Help", rememberFrame: true)]
        config.fx.borders.stageOverrides = [BorderStageOverride(stageID: "1", activeColor: "#FFFFFF")]
        config.fx.animations.durationMS = 100; config.fx.animations.intensity = 0.5
        config.fx.animations.stiffness = 200; config.fx.animations.damping = 1
        var motion = AnimationOverrides()
        motion.durationMS = 100; motion.intensity = 0.5; motion.stiffness = 200; motion.damping = 1
        config.fx.animations.move = motion; config.fx.animations.stage = motion
        config.fx.animations.appearance = motion; config.fx.animations.rail = motion
        config.fx.animations.launcher = motion; config.fx.animations.switcher = motion; config.fx.animations.overview = motion
        config.experimental.targetMode.webSearches = [WebSearch(keyword: "test", title: "Test", url: "https://example.invalid/?q={query}")]
        config.switcher.shortcuts = [WindowSwitcherShortcutConfig(styleOverride: "thumbnails", previewOverride: true,
            autoSizeOverride: true, thumbnailWidthOverride: 200, fontSizeOverride: 14, fontFamilyOverride: "system", presentationOverride: "classic")]
        config.switcher.zoneClicksPerApp = [ZoneClicksAppConfig(app: "Test", count: 2)]
        config.shortcuts = [CommandShortcut(keys: "command+f", command: "targets search")]
        config.rules = [WindowRule(id: "test", match: RuleMatch(app: "Test", appRegex: "Test", title: "Title", titleRegex: "Title",
            role: "AXWindow", subrole: "AXStandardWindow", display: "1", desktop: "1", stage: "1", isFloating: false),
            action: RuleAction(manage: true, exclude: false, assignDesktop: "1", assignDisplay: "1", assignStage: "1",
                follow: false, floating: false, layout: "bsp", gapOverride: 8, scratchpad: "test", emitEvent: false, rememberFrame: true))]

        // La réflexion exige une valeur pour chaque optionnel et chaque tableau de structures.
        // Un nouveau nil/[] structurel oblige à compléter cette fixture : il ne passe pas en silence.
        func missingValues(_ value: Any, path: String = "") -> [String] {
            let mirror = Mirror(reflecting: value)
            if mirror.displayStyle == .optional, mirror.children.isEmpty { return [path] }
            if mirror.displayStyle == .collection, mirror.children.isEmpty,
               !(value is [String]), !(value is [Double]), !(value is [Int]) { return [path] }
            return mirror.children.flatMap { missingValues($0.value, path: path + "." + ($0.label ?? "[]")) }
        }
        #expect(missingValues(config).isEmpty, "Valeurs non représentées : \(missingValues(config))")
        let data = try JSONEncoder().encode(config)
        let tree = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var unknown: [String] = [], unchecked: [String] = []
        walk(tree, path: "", known: RoadieConfigLoader.knownKeys(), unknown: &unknown, unchecked: &unchecked)
        #expect(unknown.isEmpty, "Clés inconnues : \(unknown)")
        #expect(unchecked.isEmpty, "Tables non contrôlées : \(unchecked)")
    }

}
