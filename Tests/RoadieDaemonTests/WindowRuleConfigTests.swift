import Foundation
import Testing
import RoadieCore

@Suite
struct WindowRuleConfigTests {
    @Test
    func spec002RulesDecodeFromTomlFixture() throws {
        let url = try #require(Bundle.module.url(forResource: "Spec002Rules", withExtension: "toml"))

        let config = try RoadieConfigLoader.load(from: url.path)

        #expect(config.rules.count == 2)
        #expect(config.rules[0].id == "terminal-dev")
        #expect(config.rules[0].enabled)
        #expect(config.rules[0].priority == 10)
        #expect(config.rules[0].stopProcessing)
        #expect(config.rules[0].match.app == "Terminal")
        #expect(config.rules[0].match.titleRegex == "roadie|zsh")
        #expect(config.rules[0].action.assignDesktop == "dev")
        #expect(config.rules[0].action.assignStage == "shell")
        #expect(config.rules[0].action.gapOverride == 4)
        #expect(config.rules[1].action.scratchpad == "research")
    }
}
