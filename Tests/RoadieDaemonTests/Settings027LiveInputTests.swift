import Foundation
import RoadieCore
import Testing
@testable import RoadieDaemon

@Suite
@MainActor
struct Settings027LiveInputTests {
    private func withModel(_ text: String, run: (SettingsViewModel, URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("settings027-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("roadies.toml")
        try text.write(to: file, atomically: true, encoding: .utf8)
        let service = SettingsService(configPath: file.path, eventLog: EventLog(path: folder.appendingPathComponent("events.jsonl").path), afterWrite: {})
        try run(SettingsViewModel(service: service), file)
    }

    @Test
    func typingAGapPersistsTheValidValueWithoutSubmitOrBlur() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("settings027-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("roadies.toml")
        try "[tiling]\ngaps_outer = 8\n".write(to: file, atomically: true, encoding: .utf8)
        let service = SettingsService(configPath: file.path, eventLog: EventLog(path: folder.appendingPathComponent("events.jsonl").path), afterWrite: {})
        let model = SettingsViewModel(service: service)
        let gap = try #require(SettingsCatalog.find(id: "tiling.gaps_outer"))
        model.editText(gap, raw: "20")
        #expect(try RoadieConfigLoader.load(from: file.path).tiling.gapsOuter == 20)
        #expect(model.text(for: gap) == "20")
    }

    @Test
    func incompleteNumbersAndColorsKeepTheLastValidValue() throws {
        try withModel("[tiling]\ngaps_outer = 8\n[fx.borders]\nthickness = 2\n") { model, file in
            let gap = try #require(SettingsCatalog.find(id: "tiling.gaps_outer"))
            let thickness = try #require(SettingsCatalog.find(id: "borders.thickness"))
            let color = try #require(SettingsCatalog.find(id: "borders.active_color"))
            model.editText(gap, raw: "-")
            #expect(try RoadieConfigLoader.load(from: file.path).tiling.gapsOuter == 8)
            #expect(model.text(for: gap) == "-")
            model.editText(thickness, raw: "3.")
            #expect(model.value(thickness) == .double(3))
            model.refresh()
            #expect(model.text(for: thickness) == "3.")
            model.editText(thickness, raw: "3.5")
            #expect(model.value(thickness) == .double(3.5))
            model.editText(color, raw: "#123456")
            #expect(model.value(color) == .string("#123456"))
            model.editText(color, raw: "#123")
            #expect(model.value(color) == .string("#123456"))
            #expect(model.text(for: color) == "#123")
        }
    }

    @Test
    func nullableGapClearsImmediatelyAndUnrelatedRefreshKeepsDrafts() throws {
        try withModel("[tiling]\ngaps_outer = 8\ngaps_outer_top = 12\n") { model, file in
            model.select(.tuilage)
            let top = try #require(SettingsCatalog.find(id: "tiling.gaps_outer_top"))
            let gap = try #require(SettingsCatalog.find(id: "tiling.gaps_outer"))
            model.editText(top, raw: "")
            #expect(model.value(top) == .unset)
            #expect(!(try String(contentsOf: file, encoding: .utf8)).contains("gaps_outer_top ="))
            model.editText(gap, raw: "-")
            model.refresh()
            #expect(model.text(for: gap) == "-")
            #expect(model.category == .tuilage)
            model.editText(gap, raw: "24")
            #expect(try RoadieConfigLoader.load(from: file.path).tiling.gapsOuter == 24)
            #expect(model.value(top) == .unset)
        }
    }

    @Test
    func liveInputCannotWriteThroughAnInvalidConfiguration() throws {
        let original = "[experimental.target_grid]\nrows = \"many\"\n"
        try withModel(original) { model, file in
            let gap = try #require(SettingsCatalog.find(id: "tiling.gaps_outer"))
            model.editText(gap, raw: "20")
            #expect(model.isLocked)
            #expect(try String(contentsOf: file, encoding: .utf8) == original)
        }
    }

    @Test
    func integerAndTextFieldsPersistWhileTheUserKeepsTyping() throws {
        try withModel("[experimental.target_grid]\nrows = 3\ncolumns = 3\nhint_characters = \"abcdefghijklmnopqrstuvwxyz\"\n") { model, file in
            let rows = try #require(SettingsCatalog.find(id: "target_grid.rows"))
            let stage = try #require(SettingsCatalog.find(id: "stage_manager.default_stage"))
            model.editText(rows, raw: "4")
            #expect(try RoadieConfigLoader.load(from: file.path).experimental.targetGrid.rows == 4)
            model.editText(rows, raw: "99")
            #expect(try RoadieConfigLoader.load(from: file.path).experimental.targetGrid.rows == 4)
            model.editText(stage, raw: "travail")
            #expect(try RoadieConfigLoader.load(from: file.path).stageManager.defaultStage == "travail")
            model.refresh()
            #expect(model.text(for: rows) == "99")
            #expect(model.text(for: stage) == "travail")
        }
    }

    @Test
    func aSavedScalarShowsAnExternalEditAndDoesNotWriteItBackOnBlur() throws {
        try withModel("[tiling]\ngaps_outer = 8\n") { model, file in
            model.select(.tuilage)
            let gap = try #require(SettingsCatalog.find(id: "tiling.gaps_outer"))
            model.editText(gap, raw: "8")
            let external = "[tiling]\ngaps_outer = 12\n"
            try external.write(to: file, atomically: true, encoding: .utf8)
            model.refresh()
            #expect(model.text(for: gap) == "12")
            model.commitDraft(gap)
            #expect(try String(contentsOf: file, encoding: .utf8) == external)
        }
    }

    @Test
    func blurringASavedScalarDoesNotOverwriteAnExternalEditBeforeTheWatcher() throws {
        try withModel("[tiling]\ngaps_outer = 8\n") { model, file in
            let gap = try #require(SettingsCatalog.find(id: "tiling.gaps_outer"))
            model.editText(gap, raw: "8")
            let external = "[tiling]\ngaps_outer = 12\n"
            try external.write(to: file, atomically: true, encoding: .utf8)
            model.commitDraft(gap)
            #expect(try String(contentsOf: file, encoding: .utf8) == external)
            #expect(model.text(for: gap) == "12")
        }
    }

    @Test
    func refreshingOurOwnWritePreservesTheDecimalFormat() throws {
        try withModel("[tiling]\ngaps_outer = 8\n") { model, file in
            model.select(.tuilage)
            let gap = try #require(SettingsCatalog.find(id: "tiling.gaps_outer"))
            model.editText(gap, raw: "8.50")
            model.refresh()
            #expect(model.text(for: gap) == "8.50")
            #expect(try RoadieConfigLoader.load(from: file.path).tiling.gapsOuter == 8.5)
        }
    }

    @Test
    func incompleteDraftsSurviveAnExternalRefreshAndAreRejectedOnBlur() throws {
        try withModel("[tiling]\ngaps_outer = 8\n[fx.borders]\nactive_color = \"#123456\"\n") { model, file in
            model.select(.tuilage)
            let gap = try #require(SettingsCatalog.find(id: "tiling.gaps_outer"))
            let color = try #require(SettingsCatalog.find(id: "borders.active_color"))
            model.editText(gap, raw: "-")
            model.editText(color, raw: "#123")
            let external = "[tiling]\ngaps_outer = 12\n[fx.borders]\nactive_color = \"#ABCDEF\"\n"
            try external.write(to: file, atomically: true, encoding: .utf8)
            model.refresh()
            #expect(model.text(for: gap) == "-")
            #expect(model.text(for: color) == "#123")
            model.commitDraft(gap)
            model.commitDraft(color)
            #expect(model.errors[gap.id] != nil)
            #expect(model.errors[color.id] != nil)
            #expect(try String(contentsOf: file, encoding: .utf8) == external)
        }
    }
}
