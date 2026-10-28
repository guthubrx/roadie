import AppKit
import Foundation
import RoadieCore
import Testing
import TOMLKit
@testable import RoadieDaemon

/// Session 108 : raccourcis réunis et réglables, gestionnaire Roadie ou BTT, conflits et pause de BTT.
@Suite
@MainActor
struct Spec108ShortcutsTests {
    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                                      context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
    }

    /// Disposition réduite : la touche 40 donne « k », 37 « l ».
    private let layout: [UInt32: String] = [37: "l", 40: "k", 8: "c"]

    @Test func barKeysHaveAlfredDefaultsAndReadTheirOwnKeys() throws {
        let defaults = TargetModeConfig()
        #expect(defaults.barKeys["large_type"] == "command+l")
        #expect(defaults.barKeys["close_all"] == "command+escape")
        #expect(defaults.barKeys.count == LauncherBarKeys.actions.count)
        let toml = """
        [experimental.target_mode]
        large_type_key = "cmd+k"
        preview_key = ""
        btt_pause_keys = ["Cmd+L"]

        [[shortcuts]]
        keys = "ctrl+alt+right"
        command = "roadie focus right"
        btt_uuid = "ABC"
        """
        let config = try TOMLDecoder().decode(RoadieConfig.self, from: toml)
        #expect(config.experimental.targetMode.barKeys["large_type"] == "command+k")
        #expect(config.experimental.targetMode.barKeys["preview"] == "")
        #expect(config.experimental.targetMode.bttPauseKeys == ["command+l"])
        #expect(config.shortcuts == [CommandShortcut(keys: "control+alt+right", command: "roadie focus right", bttUUID: "ABC")])
        #expect(config.shortcuts.first?.arguments == ["focus", "right"])
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-108-\(UUID().uuidString).toml")
        try toml.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let report = RoadieConfigLoader.validate(path: file.path)
        #expect(report.items.filter { $0.level != .ok }.map(\.message) == [])
    }

    @Test func commandArgumentsKeepQuotedWords() {
        #expect(CommandShortcut(keys: "", command: "stage rename 'Mon projet'").arguments == ["stage", "rename", "Mon projet"])
        #expect(CommandShortcut(keys: "", command: "/Users/x/.local/bin/roadie desktop focus 2").arguments == ["desktop", "focus", "2"])
    }

    @Test func barKeysFollowTheSettingAndTheSelectionState() throws {
        var keys = LauncherBarKeys.resolved([:])
        keys["large_type"] = "command+k"
        keys["select_toggle"] = ""
        let table = SearchInputPanel.barKeyTable(keys, layout: layout)
        #expect(table[BarKeyCombo(keyCode: 40, flags: .command)] == "large_type")
        #expect(table[BarKeyCombo(keyCode: 37, flags: .command)] == nil)
        let active = SelectionKeys(hasSelection: true, rowSelectable: true)
        #expect(SearchInputPanel.navigation(try key(40, .command), selection: active, barKeys: table)?.kind == .largeType)
        // ⌥↑ désactivée : la touche revient au champ ; ⌥↓ garde son rôle sur une ligne qui se choisit.
        #expect(SearchInputPanel.navigation(try key(126, .option), selection: active, barKeys: table) == nil)
        #expect(SearchInputPanel.navigation(try key(125, .option), selection: active, barKeys: table)?.kind == .selectAddNext)
        #expect(SearchInputPanel.navigation(try key(125, .option), selection: SelectionKeys(), barKeys: table) == nil)
        #expect(SearchInputPanel.navigation(try key(53, .command), barKeys: table)?.kind == .closeAll)
        #expect(SearchInputPanel.navigation(try key(53, []), barKeys: table)?.kind == .escape)
    }

    @Test func commandHotkeysSkipInvalidAndDuplicateKeys() {
        let plan = RoadieCommandHotkeys.plan([
            CommandShortcut(keys: "command+l", command: "focus right"),
            CommandShortcut(keys: "cmd+l", command: "focus left"),
            CommandShortcut(keys: "l", command: "focus up"),
            CommandShortcut(keys: "command+k", command: "focus down", enabled: false),
        ], layout: layout)
        #expect(plan.entries.map(\.arguments) == [["focus", "right"]])
        #expect(plan.issues == ["collision:command+l", "invalide:l"])
    }

    private let bttJSON = """
    [{"BTTUUID":"G1","BTTGroupName":"1 - Fenêtres","BTTTriggerClass":"BTTTriggerTypeKeyboardShortcut","BTTShortcutKeyCode":-1},
     {"BTTUUID":"T1","BTTTriggerParentUUID":"G1","BTTTriggerClass":"BTTTriggerTypeKeyboardShortcut","BTTShortcutKeyCode":37,
      "BTTShortcutModifierKeys":1048576,"BTTShellTaskActionScript":"/bin/bash:::-c:::-:::PATH=/opt/homebrew/bin:$PATH; roadie focus right"},
     {"BTTUUID":"T2","BTTTriggerClass":"BTTTriggerTypeKeyboardShortcut","BTTShortcutKeyCode":40,"BTTShortcutModifierKeys":1048576,
      "BTTEnabled":0,"BTTEnabled2":0,"BTTShellTaskActionScript":"roadie focus up"},
     {"BTTUUID":"T3","BTTTriggerClass":"BTTTriggerTypeKeyboardShortcut","BTTShortcutKeyCode":8,"BTTShortcutModifierKeys":1048576,
      "BTTShellTaskActionScript":"'/Users/x/.local/bin/roadie' switcher cycle --hold cmd"}]
    """

    @Test func bttTriggersAreReadWithTheirFolderCommandAndState() {
        let triggers = BTTRoadieTriggers.parse(bttJSON)
        #expect(triggers.map(\.id) == ["T1", "T2", "T3"])
        #expect(triggers[0].group == "1 - Fenêtres")
        #expect(triggers[0].command == "focus right")
        #expect(triggers[0].keys(layout: layout) == "command+l")
        #expect(triggers[1].enabled == false)
        // Le sélecteur garde ses profils : pas une commande de la liste.
        #expect(triggers[2].command == "")
        #expect(BTTRoadieTriggers.command(inScript: "/Users/x/scripts/roadie-record-toggle.sh") == nil)
        let fields = BTTRoadieTriggers.fields(keys: "command+shift+k", layout: layout)
        #expect(fields?["BTTShortcutKeyCode"] as? UInt32 == 40)
        #expect(fields?["BTTShortcutModifierKeys"] as? UInt64 == 1_179_648)
    }

    @Test func conflictsAndPauseUseThePhysicalKey() {
        let triggers = BTTRoadieTriggers.parse(bttJSON)
        let keys = [RoadieKey(id: "target_mode.large_type_key", label: "Grand texte", keys: "command+l", isBar: true),
                    RoadieKey(id: "target_mode.preview_key", label: "Aperçu", keys: "command+k", isBar: true)]
        let conflicts = ShortcutConflicts.find(keys, triggers: triggers, layout: layout)
        // ⌘K est dans BTT mais désactivé : seul ⌘L est en conflit.
        #expect(conflicts.map(\.trigger.id) == ["T1"])
        #expect(conflicts.first?.isBar == true)
        let index = [BarKeyCombo(keyCode: 37, flags: .command): ["T1"]]
        #expect(LauncherBTTPause.paused(keys: ["command+l", "command+k"], index: index, layout: layout) == ["T1"])
    }

    @Test func commandRowsShowWhoHandlesEachShortcut() {
        let triggers = BTTRoadieTriggers.parse(bttJSON)
        let taken = CommandShortcutRow.Entry(rowID: UUID(), keys: "control+alt+up", command: "focus up", enabled: true, bttUUID: "T2")
        let own = CommandShortcutRow.Entry(rowID: UUID(), keys: "command+k", command: "balance", enabled: false, bttUUID: "")
        let rows = CommandShortcutRow.rows(triggers: triggers, entries: [taken, own], layout: layout)
        #expect(rows.map(\.command) == ["focus right", "focus up", "balance"])
        #expect(rows.map(\.manager) == [.btt, .roadie, .off])
        #expect(rows[1].keys == "control+alt+up")
        #expect(rows[2].group == "Ajoutés dans Roadie")
    }

    @Test func shortcutsAreGatheredInTheirCategory() {
        let ids = Set(SettingsCatalog.descriptors(in: .raccourcis).map(\.id))
        for id in ["target_mode.search_hotkey", "target_mode.actions_hotkey", "overview.hotkey", "target_mode.view_cycle_hotkey",
                   "target_mode.pick_modifier", "target_grid.exit_key", "target_mode.large_type_key", "target_mode.btt_pause_keys", "shortcuts"] {
            #expect(ids.contains(id), "\(id)")
        }
        #expect(SettingsCatalog.descriptors(in: .recherche).allSatisfy { !$0.key.hasSuffix("_hotkey") })
        #expect(ShortcutCapture.value(keyCode: 49, modifiers: [], layout: [:], allowsPlainKeys: true) == "space")
        #expect(ShortcutCapture.value(keyCode: 49, modifiers: [], layout: [:]) == nil)
    }
}
