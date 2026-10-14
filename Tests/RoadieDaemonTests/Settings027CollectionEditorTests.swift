import Foundation
import RoadieCore
import Testing
@testable import RoadieDaemon

@Suite
@MainActor
struct Settings027CollectionEditorTests {
    private func withEditor(_ id: String, text: String = "", run: (SettingsCollectionEditorModel, URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("settings027-editor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("roadies.toml")
        try text.write(to: file, atomically: true, encoding: .utf8)
        let descriptor = try #require(SettingsCatalog.find(id: id))
        let service = SettingsService(configPath: file.path, eventLog: EventLog(path: folder.appendingPathComponent("events.jsonl").path), afterWrite: {})
        try run(SettingsCollectionEditorModel(descriptor: descriptor, service: service), file)
    }

    @Test
    func listsApplyValidEditsAndKeepANewIncompleteEntryLocal() throws {
        try withEditor("exclusions.floating_bundles", text: "[exclusions]\nfloating_bundles = [\"com.example.old\"]\n") { editor, file in
            let existing = try #require(editor.items.first)
            editor.editItem(existing.id, raw: "com.example.new")
            #expect(try RoadieConfigLoader.load(from: file.path).exclusions.floatingBundles == ["com.example.new"])
            editor.addItem()
            #expect(try RoadieConfigLoader.load(from: file.path).exclusions.floatingBundles == ["com.example.new"])
            let added = try #require(editor.items.last)
            editor.editItem(added.id, raw: "com.example.second")
            #expect(try RoadieConfigLoader.load(from: file.path).exclusions.floatingBundles == ["com.example.new", "com.example.second"])
            editor.removeItem(existing.id)
            #expect(try RoadieConfigLoader.load(from: file.path).exclusions.floatingBundles == ["com.example.second"])
        }
    }

    @Test
    func addingAStageWaitsForRequiredFieldsAndKeepsRowIdentity() throws {
        try withEditor("stage_manager.workspaces") { editor, file in
            editor.addRow()
            let row = try #require(editor.rows.first)
            let id = try #require(editor.fields.first { $0.path == ["id"] })
            let name = try #require(editor.fields.first { $0.path == ["display_name"] })
            editor.editField(row: row.id, field: id, raw: "dev")
            #expect(try RoadieConfigLoader.load(from: file.path).stageManager.workspaces.isEmpty)
            editor.editField(row: row.id, field: name, raw: "Travail")
            #expect(try RoadieConfigLoader.load(from: file.path).stageManager.workspaces.first?.displayName == "Travail")
            editor.reload()
            #expect(editor.rows.first?.id == row.id)
            editor.editField(row: row.id, field: name, raw: "")
            #expect(try RoadieConfigLoader.load(from: file.path).stageManager.workspaces.first?.displayName == "Travail")
            #expect(editor.rows.first?.raw["display_name"] == "")
            editor.removeRow(row.id)
            #expect(try RoadieConfigLoader.load(from: file.path).stageManager.workspaces.isEmpty)
        }
    }

    @Test
    func marginFormsApplyNumbersPreserveUnknownFieldsAndKeepDecimalDrafts() throws {
        let original = "[[tiling.display_overrides]]\ndisplay_id = \"screen-A\"\ngaps_outer = 8 # marge\nfuture_option = \"keep\"\n"
        try withEditor("tiling.display_overrides", text: original) { editor, file in
            let row = try #require(editor.rows.first)
            let gap = try #require(editor.fields.first { $0.path == ["gaps_outer"] })
            editor.editField(row: row.id, field: gap, raw: "12.")
            #expect(try RoadieConfigLoader.load(from: file.path).tiling.displayOverrides.first?.gapsOuter == 12)
            editor.reload()
            #expect(editor.rows.first?.raw["gaps_outer"] == "12.")
            editor.editField(row: row.id, field: gap, raw: "12.5")
            #expect(try RoadieConfigLoader.load(from: file.path).tiling.displayOverrides.first?.gapsOuter == 12.5)
            #expect(try String(contentsOf: file, encoding: .utf8).contains("future_option = \"keep\""))
            #expect(try String(contentsOf: file, encoding: .utf8).contains("# marge"))
        }
    }

    @Test
    func anExternalEditDoesNotOverwriteTheDraftOrTheFile() throws {
        try withEditor("exclusions.floating_bundles", text: "[exclusions]\nfloating_bundles = [\"com.example.old\"]\n") { editor, file in
            let row = try #require(editor.items.first)
            let external = "[exclusions]\nfloating_bundles = [\"com.example.external\"]\n"
            try external.write(to: file, atomically: true, encoding: .utf8)
            editor.editItem(row.id, raw: "com.example.user")
            #expect(try String(contentsOf: file, encoding: .utf8) == external)
            #expect(editor.items.first?.raw == "com.example.user")
            #expect(!editor.messages.isEmpty)
            editor.reload(discardDrafts: true)
            #expect(editor.items.first?.raw == "com.example.external")
        }
    }

    @Test
    func aWidthPresetCanBeAddedBetweenExistingValuesWithoutManualSorting() throws {
        try withEditor("width_adjustment.presets", text: "[width_adjustment]\npresets = [0.5, 1.0]\n") { editor, file in
            editor.addItem()
            let item = try #require(editor.items.last)
            editor.editItem(item.id, raw: "0.75")
            #expect(try RoadieConfigLoader.load(from: file.path).widthAdjustment.presets == [0.5, 0.75, 1])
            #expect(editor.messages.isEmpty)
        }
    }

    @Test
    func movingAStageChangesItsOrderAndPreservesUnknownFields() throws {
        let original = """
        [[stage_manager.workspaces]]
        id = "1"
        display_name = "Travail"
        future_note = "premier"

        [[stage_manager.workspaces]]
        id = "2"
        display_name = "Messages"
        future_note = "second"
        """
        try withEditor("stage_manager.workspaces", text: original) { editor, file in
            let row = try #require(editor.rows.last)
            editor.moveRow(row.id, by: -1)
            #expect(try RoadieConfigLoader.load(from: file.path).stageManager.workspaces.map(\.id) == ["2", "1"])
            #expect(editor.rows.first?.id == row.id)
            let stored = try String(contentsOf: file, encoding: .utf8)
            #expect(stored.contains("future_note = \"premier\""))
            #expect(stored.contains("future_note = \"second\""))
        }
    }

    @Test
    func anExternalChangeIsRefreshedAfterAValidEditHasBeenApplied() throws {
        try withEditor("exclusions.floating_bundles", text: "[exclusions]\nfloating_bundles = [\"com.example.old\"]\n") { editor, file in
            let item = try #require(editor.items.first)
            editor.editItem(item.id, raw: "com.example.user")
            #expect(editor.messages.isEmpty)
            try "[exclusions]\nfloating_bundles = [\"com.example.external\"]\n".write(to: file, atomically: true, encoding: .utf8)
            editor.reload()
            #expect(editor.items.first?.raw == "com.example.external")
            #expect(editor.items.first?.id == item.id)
            #expect(editor.messages.isEmpty)
        }
    }

    @Test
    func anExternalChangeKeepsAStillIncompleteDraftVisible() throws {
        try withEditor("exclusions.floating_bundles", text: "[exclusions]\nfloating_bundles = [\"com.example.old\"]\n") { editor, file in
            let item = try #require(editor.items.first)
            editor.editItem(item.id, raw: "")
            let external = "[exclusions]\nfloating_bundles = [\"com.example.external\"]\n"
            try external.write(to: file, atomically: true, encoding: .utf8)
            editor.reload()
            #expect(editor.items.first?.raw == "")
            #expect(editor.items.first?.id == item.id)
            #expect(!editor.messages.isEmpty)
            #expect(try String(contentsOf: file, encoding: .utf8) == external)
        }
    }

    @Test
    func editingPriorityPreservesAnExplicitEmptyTitleCriterion() throws {
        let original = """
        [[rules]]
        id = "travail"
        priority = 1
        match = { app = "Safari", title = "" }
        action = { floating = true }
        """
        try withEditor("rules", text: original) { editor, file in
            let row = try #require(editor.rows.first)
            let priority = try #require(editor.fields.first { $0.path == ["priority"] })
            editor.editField(row: row.id, field: priority, raw: "2")
            let rule = try #require(try RoadieConfigLoader.load(from: file.path).rules.first)
            #expect(rule.priority == 2)
            #expect(rule.match.title == "")
            #expect(rule.match.app == "Safari")
            #expect(editor.messages.isEmpty)
        }
    }

    @Test
    func deliberatelyEmptyingANonEmptyTitleRemovesTheCriterion() throws {
        let original = """
        [[rules]]
        id = "travail"
        match = { app = "Safari", title = "Tableau de bord" }
        action = { floating = true }
        """
        try withEditor("rules", text: original) { editor, file in
            let row = try #require(editor.rows.first)
            let title = try #require(editor.fields.first { $0.path == ["match", "title"] })
            editor.editField(row: row.id, field: title, raw: "")
            let rule = try #require(try RoadieConfigLoader.load(from: file.path).rules.first)
            #expect(rule.match.title == nil)
            #expect(rule.match.app == "Safari")
            #expect(editor.messages.isEmpty)
        }
    }
}
