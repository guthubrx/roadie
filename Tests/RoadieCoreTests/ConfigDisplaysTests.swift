import XCTest
import TOMLKit
@testable import RoadieCore

// MARK: - ConfigDisplaysTests (SPEC-012 T039, T040)
//
// Tests du parsing TOML de la section [[displays]] et de l'application
// des rules par `DisplayRegistry.applyRules`.

final class ConfigDisplaysTests: XCTestCase {

    // MARK: T039 — Parsing TOML 0 règle (backward-compat)

    func test_noDisplaysSection_returnsEmptyRules() throws {
        let toml = ""
        let config = try TOMLDecoder().decode(Config.self, from: toml)
        XCTAssertTrue(config.displays.isEmpty,
            "Absence de [[displays]] doit retourner un tableau vide (compat V1)")
    }

    // MARK: T039 — Parsing TOML 1 règle par index

    func test_oneRuleByIndex() throws {
        let toml = """
        [[displays]]
        match_index = 1
        default_strategy = "master_stack"
        gaps_outer = 12
        gaps_inner = 6
        """
        let config = try TOMLDecoder().decode(Config.self, from: toml)
        XCTAssertEqual(config.displays.count, 1)
        let rule = config.displays[0]
        XCTAssertEqual(rule.matchIndex, 1)
        XCTAssertNil(rule.matchUUID)
        XCTAssertNil(rule.matchName)
        XCTAssertEqual(rule.defaultStrategy, "master_stack")
        XCTAssertEqual(rule.gapsOuter, 12)
        XCTAssertEqual(rule.gapsInner, 6)
    }

    // MARK: T039 — Parsing TOML 2 règles : index + uuid

    func test_twoRules_indexAndUUID() throws {
        let toml = """
        [[displays]]
        match_index = 1
        default_strategy = "bsp"

        [[displays]]
        match_uuid = "AB12-CD34"
        default_strategy = "master_stack"
        gaps_outer = 20
        """
        let config = try TOMLDecoder().decode(Config.self, from: toml)
        XCTAssertEqual(config.displays.count, 2)
        XCTAssertEqual(config.displays[0].matchIndex, 1)
        XCTAssertEqual(config.displays[0].defaultStrategy, "bsp")
        XCTAssertEqual(config.displays[1].matchUUID, "AB12-CD34")
        XCTAssertEqual(config.displays[1].defaultStrategy, "master_stack")
        XCTAssertEqual(config.displays[1].gapsOuter, 20)
        XCTAssertNil(config.displays[1].gapsInner)
    }

    // MARK: T039 — Parsing TOML règle par name

    func test_ruleByName() throws {
        let toml = """
        [[displays]]
        match_name = "DELL U2723QE"
        gaps_outer = 0
        """
        let config = try TOMLDecoder().decode(Config.self, from: toml)
        XCTAssertEqual(config.displays.count, 1)
        XCTAssertEqual(config.displays[0].matchName, "DELL U2723QE")
        XCTAssertEqual(config.displays[0].gapsOuter, 0)
    }

    // MARK: T040 — applyRules : match par index → stratégie overridée

    func test_applyRules_matchByIndex_overridesStrategy() async {
        let provider = MockDisplayProvider(screens: NSScreen.screens.prefix(2).map { $0 })
        guard provider.screens.count >= 2 else {
            // Test skip sur mono-écran : nécessite 2 écrans physiques.
            return
        }
        let registry = DisplayRegistry(provider: provider, defaultStrategy: .bsp)
        await registry.refresh()

        // TilerStrategy.masterStack.rawValue = "masterStack" — c'est la valeur à passer.
        let rule = DisplayRule(matchIndex: 2, defaultStrategy: TilerStrategy.masterStack.rawValue)
        await registry.applyRules([rule])

        let d2 = await registry.display(at: 2)
        XCTAssertEqual(d2?.tilerStrategy, .masterStack,
            "applyRules avec matchIndex=2 doit overrider la stratégie de display 2")

        let d1 = await registry.display(at: 1)
        XCTAssertEqual(d1?.tilerStrategy, .bsp,
            "display 1 ne doit pas être modifié par une règle sur display 2")
    }

    // MARK: T040 — applyRules : match par uuid

    func test_applyRules_matchByUUID() async {
        let provider = MockDisplayProvider(screens: NSScreen.screens.prefix(1).map { $0 })
        let registry = DisplayRegistry(provider: provider, defaultStrategy: .bsp)
        await registry.refresh()

        let displays = await registry.displays
        guard let d = displays.first else { return }
        // Construire une règle avec l'UUID réel du 1er écran.
        let rule = DisplayRule(matchUUID: d.uuid, gapsOuter: 42)
        await registry.applyRules([rule])

        let updated = await registry.display(at: 1)
        XCTAssertEqual(updated?.gapsOuter, 42,
            "applyRules avec matchUUID doit overrider gapsOuter")
    }

    // MARK: T040 — applyRules : match par name

    func test_applyRules_matchByName() async {
        let provider = MockDisplayProvider(screens: NSScreen.screens.prefix(1).map { $0 })
        let registry = DisplayRegistry(provider: provider, defaultStrategy: .bsp)
        await registry.refresh()

        let displays = await registry.displays
        guard let d = displays.first else { return }
        let rule = DisplayRule(matchName: d.name, gapsInner: 16)
        await registry.applyRules([rule])

        let updated = await registry.display(at: 1)
        XCTAssertEqual(updated?.gapsInner, 16,
            "applyRules avec matchName doit overrider gapsInner")
    }

    // MARK: T040 — applyRules : règle sans match ne touche rien

    func test_applyRules_noMatch_leavesDisplayUnchanged() async {
        let provider = MockDisplayProvider(screens: NSScreen.screens.prefix(1).map { $0 })
        let registry = DisplayRegistry(provider: provider,
                                       defaultStrategy: .bsp,
                                       defaultGapsOuter: 8,
                                       defaultGapsInner: 4)
        await registry.refresh()

        // Règle qui ne peut pas matcher (index 99 n'existe pas).
        let rule = DisplayRule(matchIndex: 99, defaultStrategy: "master_stack", gapsOuter: 100)
        await registry.applyRules([rule])

        let d = await registry.display(at: 1)
        XCTAssertEqual(d?.tilerStrategy, .bsp, "display 1 ne doit pas changer si la règle ne matche pas")
        XCTAssertEqual(d?.gapsOuter, 8, "gapsOuter doit rester à la valeur par défaut")
    }

    // MARK: T040 — applyRules vide : aucune modification

    func test_applyRules_emptyRules_isNoop() async {
        let provider = MockDisplayProvider(screens: NSScreen.screens.prefix(1).map { $0 })
        let registry = DisplayRegistry(provider: provider, defaultStrategy: .bsp, defaultGapsOuter: 8)
        await registry.refresh()

        await registry.applyRules([])

        let d = await registry.display(at: 1)
        XCTAssertEqual(d?.tilerStrategy, .bsp)
        XCTAssertEqual(d?.gapsOuter, 8)
    }
}
