import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

struct Spec096IdleSettingsTests {
    @Test func defaultsKeepThreeRowsInBothSections() {
        let config = TargetModeConfig()
        #expect(config.idleFrequentEnabled && config.idleRecentSearchesEnabled)
        #expect(config.idleFrequentCount == 3 && config.idleRecentSearchesCount == 3)
    }

    @Test func fileTurnsSectionsOffAndBoundsTheirDepth() throws {
        let path = tempPath("spec096") + ".toml"
        try """
        [experimental.target_mode]
        idle_frequent_enabled = false
        idle_frequent_count = 50
        idle_recent_searches_enabled = false
        idle_recent_searches_count = 0
        """.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let config = try RoadieConfigLoader.load(from: path).experimental.targetMode
        #expect(!config.idleFrequentEnabled && !config.idleRecentSearchesEnabled)
        #expect(config.idleFrequentCount == 10 && config.idleRecentSearchesCount == 1)
        #expect(RoadieConfigLoader.validate(path: path).items.allSatisfy { !$0.path.contains("idle_") })
    }

    @Test func settingsShowTheFourChoicesInSearch() throws {
        let keys = SettingsCatalog.all.filter { $0.tablePath == "experimental.target_mode" && $0.key.hasPrefix("idle_") }
        #expect(keys.map(\.key) == ["idle_frequent_enabled", "idle_frequent_count",
                                    "idle_recent_searches_enabled", "idle_recent_searches_count"])
        #expect(keys.allSatisfy { $0.category == .recherche })
    }
}
