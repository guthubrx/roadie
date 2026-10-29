import Foundation
import RoadieAX
import RoadieCore
import Testing
@testable import RoadieDaemon

/// Session 125 : fenêtres d'appoint (rappels, boîtes de dialogue) flottantes par leur titre, et critères de
/// taille jugés sur le premier cadre de la fenêtre.
struct Spec125AuxiliaryWindowsTests {
    /// Relevé réel du rappel de Thunderbird (`roadie window explain`) : rien ne le distingue de la boîte de
    /// réception, sauf son titre.
    private func thunderbird(_ id: UInt32, _ title: String, main: Bool) -> WindowSnapshot {
        WindowSnapshot(id: WindowID(rawValue: id), pid: 7, appName: "Thunderbird", bundleID: "org.mozilla.thunderbird", title: title,
                       frame: Rect(x: 0, y: 0, width: 1837, height: 2114), isOnScreen: true, isTileCandidate: true,
                       subrole: "AXStandardWindow", role: "AXWindow",
                       furniture: WindowFurniture(hasCloseButton: true, hasFullscreenButton: true, fullscreenButtonEnabled: true,
                                                  hasMinimizeButton: true, hasZoomButton: true, isMain: main, isResizable: true))
    }

    private func decision(_ window: WindowSnapshot, rules: [WindowRule], initialFrame: Rect? = nil) -> SnapshotService.TilingDecision {
        var config = RoadieConfig()
        config.rules = rules
        return SnapshotService.tilingDecision(for: window, config: config, context: .init(config: config), initialFrame: initialFrame)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-125-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func matches(_ regex: String, _ title: String) throws -> Bool {
        try NSRegularExpression(pattern: regex).firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil
    }

    @Test func listTitleGeneralizesNumbersAndAcceptsWildcards() throws {
        #expect(FloatingWindowTitles.text(fromTitle: " 1 Reminder ") == "# Reminder")
        #expect(FloatingWindowTitles.text(fromTitle: "Issue #12 (*)") == "Issue *# (*)")
        #expect(FloatingWindowTitles.text(fromTitle: "  ") == nil)
        let reminder = FloatingWindowTitles.regex("# Reminder")
        for (title, expected) in [("1 Reminder", true), ("3 Reminders", true), ("12 reminder", true),
                                  ("Reminder", false), ("Inbox - 1 Reminder", false), ("1 Reminder settings", false)] {
            #expect(try matches(reminder, title) == expected, "\(title)")
        }
        let format = FloatingWindowTitles.regex("Format (cellules) *")
        #expect(try matches(format, "Format (cellules) — Classeur1"))
        #expect(try !matches(format, "Format cellules"))
    }

    @Test func listLoadsAsRulesThatWinOverTheAppRule() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("roadies.toml").path
        try "[[exclusions.floating_windows]]\napp = \"thunderbird\"\ntitle = \"# Reminder\"\n".write(toFile: path, atomically: true, encoding: .utf8)
        let inbox = thunderbird(1, "Inbox - courrier", main: true)
        // Règle de l'application « toujours tuiler », dans le fichier des règles générées.
        #expect(WindowRuleAffinityService(path: RoadieConfigLoader.generatedRulesPath(for: path)).saveTiling(.tile, window: inbox).changed)
        let config = try RoadieConfigLoader.load(from: path)
        #expect(RoadieConfigLoader.validate(path: path).items.filter { $0.path.contains("floating_windows") }.isEmpty)
        let rule = try #require(config.rules.first { $0.id.hasPrefix(FloatingWindowTitles.rulePrefix) })
        #expect(rule.priority > 9_000 && rule.action.floating == true)
        let context = SnapshotService.TilingPolicyContext(config: config)
        let reminder = SnapshotService.tilingDecision(for: thunderbird(2, "2 Reminders", main: false), config: config, context: context)
        #expect(!reminder.tile)
        #expect(reminder.reason.hasPrefix("règle float-title-"))
        #expect(SnapshotService.tilingDecision(for: inbox, config: config, context: context).tile)
    }

    @Test func menuAddsAndRemovesTheWindowInTheUserList() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("roadies.toml").path
        try "# Ma configuration\n[tiling]\ngaps_inner = 4\n".write(toFile: path, atomically: true, encoding: .utf8)
        let list = FloatingWindowSettings(settings: SettingsService(configPath: path, afterWrite: {}))
        let reminder = thunderbird(2, "1 Reminder", main: false)
        let later = thunderbird(3, "4 Reminders", main: false)
        #expect(list.listedTitle(for: reminder) == nil)
        #expect(list.setFloating(true, window: reminder).changed)
        #expect(!list.setFloating(true, window: later).changed)
        #expect(list.listedTitle(for: later) == "# Reminder")
        #expect(list.listedTitle(for: thunderbird(1, "Inbox - courrier", main: true)) == nil)
        let text = try String(contentsOfFile: path, encoding: .utf8)
        #expect(text.contains("[[exclusions.floating_windows]]") && text.contains("# Ma configuration"))
        #expect(try RoadieConfigLoader.load(from: path).exclusions.floatingWindows == [FloatingWindowConfig(app: "Thunderbird", title: "# Reminder")])
        #expect(list.setFloating(false, window: later).changed)
        #expect(list.listedTitle(for: reminder) == nil)
        #expect(try RoadieConfigLoader.load(from: path).exclusions.floatingWindows.isEmpty)
    }

    @Test func sizeCriteriaJudgeTheFirstFrame() {
        // Panneau court sans plein écran, tuilé ensuite à la taille de sa place.
        var panel = WindowSnapshot(id: WindowID(rawValue: 9), pid: 8, appName: "Outil", bundleID: "doc.outil", title: "Progression",
                                   frame: Rect(x: 0, y: 0, width: 1200, height: 900), isOnScreen: true, isTileCandidate: true,
                                   subrole: "AXStandardWindow", role: "AXWindow",
                                   furniture: WindowFurniture(hasCloseButton: true, hasMinimizeButton: true, isResizable: true))
        #expect(decision(panel, rules: []).tile)
        let born = decision(panel, rules: [], initialFrame: Rect(x: 0, y: 0, width: 420, height: 140))
        #expect(!born.tile)
        #expect(born.reason.contains("180 points"))
        // La décision garde le vrai cadre de la fenêtre.
        panel.isTileCandidate = true
        var config = RoadieConfig()
        config.rules = []
        let classified = SnapshotService.applyTilingPolicy(to: panel, config: config, context: .init(config: config),
                                                           initialFrame: Rect(x: 0, y: 0, width: 420, height: 140))
        #expect(classified.frame == panel.frame)
        #expect(!classified.isTileCandidate)
    }
}
