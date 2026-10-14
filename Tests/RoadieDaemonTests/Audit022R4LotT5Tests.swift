import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

private func writeToml(_ name: String, _ content: String) throws -> String {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("roadie-r4t5-\(name)-\(UUID().uuidString).toml")
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url.path
}

/// REL-034 et MIN-005 : validation de la configuration.
@Suite
struct Audit022R4LotT5ConfigTests {
    @Test(arguments: ["spatial_bspp", "", "BSP", "grid"])
    func unknownDefaultStrategyFailsValidateAndLoad(value: String) throws {
        let path = try writeToml("badstrategy", "[tiling]\ndefault_strategy = \"\(value)\"\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let report = RoadieConfigLoader.validate(path: path)

        #expect(report.hasErrors, "validate doit refuser default_strategy = \"\(value)\"")
        #expect(report.items.contains { $0.level == .error && $0.message.contains("default_strategy") })
        #expect(throws: (any Error).self) { try RoadieConfigLoader.load(from: path) }
    }

    @Test
    func absentDefaultStrategyKeepsBsp() throws {
        let path = try writeToml("nostrategy", "[tiling]\nsplit_policy = \"largest_dim\"\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        #expect(!RoadieConfigLoader.validate(path: path).hasErrors)
        #expect(try RoadieConfigLoader.load(from: path).tiling.defaultStrategy == .bsp)
    }

    @Test(arguments: [
        ("bsp", WindowManagementMode.bsp),
        ("mutableBsp", .spatialBsp), ("mutable_bsp", .spatialBsp), ("mutable-bsp", .spatialBsp), ("yabai", .spatialBsp),
        ("masterStack", .masterStack), ("master_stack", .masterStack), ("master-stack", .masterStack),
        ("float", .float), ("floating", .float),
        ("spatialBsp", .spatialBsp), ("spatial_bsp", .spatialBsp), ("spatial-bsp", .spatialBsp),
        ("spatial", .spatialBsp), ("tree", .spatialBsp)
    ])
    func knownModesAndAliasesStayAccepted(value: String, expected: WindowManagementMode) throws {
        let path = try writeToml("goodstrategy", "[tiling]\ndefault_strategy = \"\(value)\"\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        #expect(!RoadieConfigLoader.validate(path: path).hasErrors)
        #expect(try RoadieConfigLoader.load(from: path).tiling.defaultStrategy == expected)
    }

    @Test
    func repositoryExampleStaysValid() throws {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("examples/roadies.toml").path
        guard FileManager.default.fileExists(atPath: path) else { return }

        #expect(!RoadieConfigLoader.validate(path: path).hasErrors)
        _ = try RoadieConfigLoader.load(from: path)
    }

    /// MIN-005 : les touches vides sont remplacées au décodage, le rapport reste sans erreur.
    @Test
    func emptyOrBlankTargetGridKeysAreNormalizedWithoutError() throws {
        let path = try writeToml("emptykeys", """
        [experimental.target_grid]
        confirm_action_key = ""
        reset_key = "   "
        back_key = " "
        exit_key = ""
        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let grid = try RoadieConfigLoader.load(from: path).experimental.targetGrid

        #expect(!RoadieConfigLoader.validate(path: path).hasErrors)
        #expect(grid.confirmActionKey == "space")
        #expect(grid.resetKey == "r")
        #expect(grid.backKey == "backspace")
        #expect(grid.exitKey == "escape")
    }
}

/// REL-035 : enregistrer une affinité ne modifie aucune autre règle du fichier.
@Suite
struct Audit022R4LotT5AffinityTests {
    private let rules = #"""
    [[rules]]
    id = "empty-title"
    enabled = true
    priority = 5
    stop_processing = false

    [rules.match]
    app = "Terminal"
    title = ""
    role = ""

    [rules.action]
    assign_stage = "dev"
    layout = ""

    [[rules]]
    id = "special-chars"
    enabled = true
    priority = 6
    stop_processing = false

    [rules.match]
    app = "Term\"inal\\"
    title = "a\nb\r\tc\"d\\e\u0001f\u007F"
    title_regex = "^x\\.y$"

    [rules.action]
    assign_stage = "dev"
    scratchpad = "line1\nline2"

    """#

    private func window(_ id: UInt32, app: String, title: String = "T") -> WindowSnapshot {
        WindowSnapshot(
            id: WindowID(rawValue: id), pid: Int32(id), appName: app, bundleID: "app.\(app)", title: title,
            frame: Rect(x: 0, y: 0, width: 100, height: 100), isOnScreen: true, isTileCandidate: true
        )
    }

    @Test
    func saveAndRemoveKeepEmptyAndSpecialStringsOfOtherRules() throws {
        let path = try writeToml("affinity", rules)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let before = try RoadieConfigLoader.loadRulesFile(from: path)
        let scope = StageScope(displayID: DisplayID(rawValue: "d"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let service = WindowRuleAffinityService(path: path, eventLog: EventLog(path: tempPath("r4t5-affinity-events")))

        let saved = service.saveAffinity(kind: .app, window: window(2, app: "App B"), scope: scope, display: powerDisplay("d"))
        let afterSave = try RoadieConfigLoader.loadRulesFile(from: path)
        let removed = service.removeAppAffinity(window: window(2, app: "App B"), scope: scope)
        let afterRemove = try RoadieConfigLoader.loadRulesFile(from: path)

        #expect(before.first { $0.id == "empty-title" }?.match.title == "")
        #expect(saved.changed)
        #expect(afterSave.count == 3)
        #expect(afterSave.filter { !$0.id.hasPrefix("affinity-") } == before)
        #expect(removed.changed)
        #expect(afterRemove == before)
    }

    @Test
    func emptyTitleRuleStillMatchesOnlyEmptyTitlesAfterSave() throws {
        let path = try writeToml("emptymatch", rules)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let scope = StageScope(displayID: DisplayID(rawValue: "d"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let service = WindowRuleAffinityService(path: path, eventLog: EventLog(path: tempPath("r4t5-affinity-events2")))

        _ = service.saveAffinity(kind: .app, window: window(2, app: "App B"), scope: scope, display: powerDisplay("d"))
        let rule = try #require(RoadieConfigLoader.loadRulesFile(from: path).first { $0.id == "empty-title" })

        let context = WindowRuleMatchContext(role: "")
        #expect(WindowRuleMatcher.matches(rule: rule, window: window(3, app: "Terminal", title: ""), context: context))
        #expect(!WindowRuleMatcher.matches(rule: rule, window: window(4, app: "Terminal", title: "Shell"), context: context))
    }

    @Test
    func affinityOnTitleWithControlCharactersRoundTrips() throws {
        let path = try writeToml("controltitle", "")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let title = "a\nb\r\tc\"d\\e\u{1}f"
        let scope = StageScope(displayID: DisplayID(rawValue: "d"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let service = WindowRuleAffinityService(path: path, eventLog: EventLog(path: tempPath("r4t5-affinity-events3")))

        let saved = service.saveAffinity(kind: .appTitle, window: window(2, app: "App B", title: title), scope: scope, display: powerDisplay("d"))
        let loaded = try RoadieConfigLoader.loadRulesFile(from: path)

        #expect(saved.changed)
        #expect(loaded.first?.match.title == title)
    }
}
