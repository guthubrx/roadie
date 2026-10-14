import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

@Suite
@MainActor
struct SettingsViewModelTests {
    private let fixture = """
    [fx.borders]
    enabled = false
    thickness = 2 # points

    [experimental.target_grid]
    # Grille de clic.
    rows = 3
    columns = 3
    hint_characters = "azeqsdwxcrtyfghvbnuiopjklm" # 26 lettres : la grille 4 × 3 reste valide
    """

    /// Modèle sur un fichier de configuration temporaire (jamais `~/.config`).
    private func makeModel(_ text: String? = nil) throws -> (SettingsViewModel, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-settings-view-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = directory.appendingPathComponent("roadies.toml")
        try (text ?? fixture).write(to: config, atomically: true, encoding: .utf8)
        let log = EventLog(path: directory.appendingPathComponent("events.jsonl").path)
        let service = SettingsService(configPath: config.path, eventLog: log, afterWrite: {})
        return (SettingsViewModel(service: service), config)
    }

    private func descriptor(_ id: String) throws -> SettingDescriptor {
        try #require(SettingsCatalog.find(id: id))
    }

    @Test
    func typingAFontKeepsDecimalDraftAndUpdatesImmediately() throws {
        let (model, _) = try makeModel()
        let setting = try descriptor("interface.settings_text_font_size")
        model.editText(setting, raw: "8.")
        #expect(model.text(for: setting) == "8.")
        #expect(model.interfaceFonts.settingsTextFontSize == 8)
        model.editText(setting, raw: "8.5")
        #expect(model.interfaceFonts.settingsTextFontSize == 8.5)
        #expect(model.text(for: setting) == "8.5")
        model.editText(setting, raw: "2")
        #expect(model.interfaceFonts.settingsTextFontSize == 8.5)
        model.editText(setting, raw: "24")
        #expect(model.interfaceFonts.settingsTextFontSize == 24)
        model.step(setting, by: 1)
        #expect(model.text(for: setting) == "25")
    }

    @Test
    func fontSizesAreIndependentImmediateAndPersistAcrossCategories() throws {
        let original = """
        [interface]
        settings_text_font_size = 17
        settings_help_font_size = 13
        settings_title_font_size = 25
        """
        let (model, config) = try makeModel(original)
        model.select(.grille)
        #expect(model.interfaceFonts.settingsTextFontSize == 17)
        #expect(model.interfaceFonts.settingsHelpFontSize == 13)
        #expect(model.interfaceFonts.settingsTitleFontSize == 25)
        let body = try descriptor("interface.settings_text_font_size")
        let help = try descriptor("interface.settings_help_font_size")
        model.apply(body, raw: "23")
        #expect(model.interfaceFonts.settingsTextFontSize == 23)
        #expect(model.interfaceFonts.settingsHelpFontSize == 13)
        #expect(model.interfaceFonts.settingsTitleFontSize == 25)
        model.apply(help, raw: "15")
        #expect(model.interfaceFonts.settingsHelpFontSize == 15)
        model.reset(body)
        #expect(model.interfaceFonts.settingsTextFontSize == 16)
        #expect(model.interfaceFonts.settingsHelpFontSize == 15)
        let reopened = SettingsViewModel(service: SettingsService(configPath: config.path, afterWrite: {}))
        #expect(reopened.interfaceFonts.settingsHelpFontSize == 15)
        #expect(reopened.interfaceFonts.settingsTitleFontSize == 25)
        #expect(try String(contentsOf: config, encoding: .utf8).contains("settings_help_font_size = 15"))
    }

    @Test
    func externalFontChangeUpdatesTheCacheWhileAnotherCategoryIsOpen() throws {
        let (model, config) = try makeModel("[interface]\nsettings_text_font_size = 16\n")
        model.select(.rail)
        try "[interface]\nsettings_text_font_size = 22\n".write(to: config, atomically: true, encoding: .utf8)
        model.refresh()
        #expect(model.category == .rail)
        #expect(model.interfaceFonts.settingsTextFontSize == 22)
        #expect(model.interfaceFonts.settingsHelpFontSize == 14)
    }

    @Test
    func nonCanonicalSplitPolicyIsDisplayedWithoutChangingItsMeaning() throws {
        let original = "[tiling]\nsplit_policy = \"Dwindle\"\n"
        let (model, config) = try makeModel(original)
        model.select(.tuilage)
        let split = try descriptor("tiling.split_policy")
        #expect(model.text(for: split) == "Dwindle")
        #expect(split.choiceValues(includingCurrent: model.text(for: split)).contains("Dwindle"))
        #expect(try String(contentsOf: config, encoding: .utf8) == original)
        model.apply(split, raw: "balanced")
        #expect(model.errors[split.id] == nil)
        #expect(model.text(for: split) == "balanced")
        #expect(!split.choiceValues(includingCurrent: model.text(for: split)).contains("Dwindle"))
    }

    @Test
    func legacyTilingChoicesAreDisplayedWithoutRewritingAndKeepTheirRawValues() throws {
        let original = "[tiling]\nsplit_policy = \"balanced\"\ndefault_strategy = \"mutableBsp\"\n"
        let (model, config) = try makeModel(original)
        model.select(.tuilage)
        let split = try descriptor("tiling.split_policy")
        let strategy = try descriptor("tiling.default_strategy")
        #expect(model.text(for: split) == "balanced")
        #expect(model.text(for: strategy) == "spatialBsp")
        guard case .choice(let choices) = split.kind else { Issue.record("choix attendu"); return }
        #expect(choices.contains(model.text(for: split)))
        #expect(try String(contentsOf: config, encoding: .utf8) == original)

        model.apply(split, raw: "dwindle")
        #expect(model.errors[split.id] == nil)
        #expect(model.text(for: split) == "dwindle")
        model.apply(split, raw: "balanced")
        #expect(model.errors[split.id] == nil)
        #expect(model.text(for: split) == "balanced")
        #expect(try String(contentsOf: config, encoding: .utf8).contains("split_policy = \"balanced\""))
        #expect(try String(contentsOf: config, encoding: .utf8).contains("default_strategy = \"mutableBsp\""))
        model.reset(split)
        #expect(model.text(for: split) == "largest_dim")
        #expect(model.isDefault(split))
    }

    @Test
    func opensOnGeneralThenRemembersTheLastCategory() throws {
        let (model, _) = try makeModel()
        model.prepareForShow(category: nil)
        #expect(model.category == .general)
        #expect(model.sections.map(\.category) == [.general])

        model.select(.grille)
        #expect(model.sections.map(\.category) == [.grille])
        #expect(model.sections.first?.descriptors == SettingsCatalog.descriptors(in: .grille))

        // Fermeture puis réouverture sans catégorie : la dernière vue reste.
        model.prepareForShow(category: nil)
        #expect(model.category == .grille)
        model.prepareForShow(category: .rail)
        #expect(model.category == .rail)
    }

    @Test
    func searchGroupsMatchesByCategoryAndEmptyQueryReturnsToCategory() throws {
        let (model, _) = try makeModel()
        model.select(.grille)
        model.query = "bordure"
        #expect(model.isSearching)
        #expect(model.sections.map(\.category) == [.bordures])
        let ids = model.sections.flatMap(\.descriptors).map(\.id)
        #expect(ids.count == 6)
        #expect(ids.allSatisfy { $0.hasPrefix("borders.") })

        model.query = ""
        #expect(!model.isSearching)
        #expect(model.sections.map(\.category) == [.grille])
    }

    @Test
    func searchIncludesEditableCollectionsAndKeepsTheirCategories() throws {
        let (model, _) = try makeModel()
        model.query = "stage"
        #expect(model.sections.contains { $0.descriptors.contains { $0.collection != nil } })
        #expect(model.sections.flatMap(\.descriptors).allSatisfy { $0.readOnlyReason == nil })
        // Choisir une catégorie quitte la recherche.
        model.select(.regles)
        #expect(model.query.isEmpty)
    }

    @Test
    func validEditIsAppliedAndReadBack() throws {
        let (model, config) = try makeModel()
        model.select(.grille)
        let rows = try descriptor("target_grid.rows")
        #expect(model.value(rows) == .int(3))

        model.drafts[rows.id] = "4"
        #expect(model.text(for: rows) == "4")
        model.commitDraft(rows)
        #expect(model.errors[rows.id] == nil)
        #expect(model.drafts[rows.id] == nil)
        #expect(model.value(rows) == .int(4))
        #expect(model.text(for: rows) == "4")
        #expect(try String(contentsOf: config, encoding: .utf8).contains("rows = 4\n"))
        // Relecture du fichier (comme après le signal du watcher).
        model.refresh()
        #expect(model.value(rows) == .int(4))
        #expect(!model.isDefault(rows))
    }

    @Test
    func resetButtonOnlyAppearsWhenTheValueDiffersFromTheDefault() throws {
        // Le fichier répète les défauts (rows = 3, thickness = 2) : rien à rétablir malgré la présence des lignes.
        let (model, _) = try makeModel()
        model.select(.grille)
        let rows = try descriptor("target_grid.rows")
        #expect(model.isDefault(rows))
        model.select(.bordures)
        let thickness = try descriptor("borders.thickness")
        #expect(model.isDefault(thickness))

        // Une valeur différente propose « Rétablir » ; revenir à la valeur par défaut le retire.
        model.apply(thickness, raw: "5")
        #expect(!model.isDefault(thickness))
        model.apply(thickness, raw: "2")
        #expect(model.isDefault(thickness))
    }

    @Test
    func collectionEditorsShowTheirExistingListsAndRules() throws {
        let (model, _) = try makeModel(fixture + """


        [exclusions]
        floating_bundles = ["com.example.alpha", "com.example.beta"]

        [[rules]]
        id = "a"
        match = { app = "Alpha" }
        action = { floating = true }

        [[rules]]
        id = "b"
        match = { app = "Beta" }
        action = { floating = true }
        """)
        model.select(.regles)
        let entries = model.sections.flatMap(\.descriptors)
        let rules = try #require(entries.first { $0.key == "rules" })
        let bundles = try #require(entries.first { $0.key == "floating_bundles" })
        let rulesEditor = SettingsCollectionEditorModel(descriptor: rules, service: model.service)
        #expect(rulesEditor.rows.count == 2)
        #expect(rulesEditor.rows.map { $0.raw["id"] } == ["a", "b"])
        let bundlesEditor = SettingsCollectionEditorModel(descriptor: bundles, service: model.service)
        #expect(bundlesEditor.items.map(\.raw) == ["com.example.alpha", "com.example.beta"])

        // Un réglage modifiable n'a pas de résumé.
        model.select(.grille)
        #expect(model.readOnlySummary(try descriptor("target_grid.rows")) == nil)
    }

    @Test
    func rejectedEditShowsTheCauseAndKeepsTheOriginalValue() throws {
        let (model, config) = try makeModel()
        model.select(.grille)
        let rows = try descriptor("target_grid.rows")
        let before = try String(contentsOf: config, encoding: .utf8)

        model.drafts[rows.id] = "99"
        model.commitDraft(rows)
        let error = try #require(model.errors[rows.id])
        #expect(error.contains("hors plage"))
        #expect(model.text(for: rows) == "3")
        #expect(try String(contentsOf: config, encoding: .utf8) == before)

        // Une édition valide efface la cause.
        model.apply(rows, raw: "5")
        #expect(model.errors[rows.id] == nil)
        #expect(model.value(rows) == .int(5))
    }

    @Test
    func toggleAndStepperApplyAtOnce() throws {
        let (model, _) = try makeModel()
        model.select(.bordures)
        let enabled = try descriptor("borders.enabled")
        model.apply(enabled, raw: "true")
        #expect(model.value(enabled) == .bool(true))

        model.select(.grille)
        let rows = try descriptor("target_grid.rows")
        model.step(rows, by: 1)
        #expect(model.value(rows) == .int(4))
        model.step(rows, by: -1)
        #expect(model.value(rows) == .int(3))
    }

    @Test
    func resetRestoresTheDefault() throws {
        let (model, config) = try makeModel()
        model.select(.bordures)
        let thickness = try descriptor("borders.thickness")
        model.apply(thickness, raw: "5")
        #expect(model.value(thickness) == .double(5))
        #expect(!model.isDefault(thickness))

        model.reset(thickness)
        #expect(model.isDefault(thickness))
        #expect(model.value(thickness) == thickness.defaultValue)
        #expect(!(try String(contentsOf: config, encoding: .utf8)).contains("thickness ="))
        model.refresh()
        #expect(model.isDefault(thickness))
    }

    @Test
    func invalidFileLocksTheControls() throws {
        let (model, config) = try makeModel("""
        [experimental.target_grid]
        rows = "beaucoup"
        """)
        #expect(model.isLocked)
        #expect(model.validity.errorCount > 0)
        #expect(!model.validity.messages.isEmpty)
        #expect(model.validityText.hasPrefix("\(model.validity.errorCount) erreur"))

        let before = try String(contentsOf: config, encoding: .utf8)
        let columns = try descriptor("target_grid.columns")
        model.apply(columns, raw: "4")
        model.reset(columns)
        #expect(try String(contentsOf: config, encoding: .utf8) == before)
    }

    @Test
    func collectionsCannotBeOverwrittenWithAScalar() throws {
        let (model, config) = try makeModel()
        model.select(.regles)
        let entries = try #require(model.sections.first?.descriptors)
        #expect(!entries.isEmpty)
        #expect(entries.allSatisfy { $0.collection != nil })

        let before = try String(contentsOf: config, encoding: .utf8)
        for entry in entries {
            model.apply(entry, raw: "x")
        }
        #expect(try String(contentsOf: config, encoding: .utf8) == before)
        #expect(!model.errors.isEmpty)
    }

    @Test
    func externalChangeIsReadBackWithoutLosingTheSearch() throws {
        let (model, config) = try makeModel()
        let rows = try descriptor("target_grid.rows")
        model.select(.grille)
        model.query = "lignes"
        try fixture.replacingOccurrences(of: "rows = 3", with: "rows = 7")
            .write(to: config, atomically: true, encoding: .utf8)

        model.refresh()
        #expect(model.value(rows) == .int(7))
        #expect(model.query == "lignes")
        #expect(model.category == .grille)
    }

    @Test
    func emptyingAnOptionalFieldRestoresItsDefault() throws {
        let (model, _) = try makeModel()
        model.select(.tuilage)
        let top = try descriptor("tiling.gaps_outer_top")
        model.apply(top, raw: "4")
        #expect(model.text(for: top) == "4")
        model.drafts[top.id] = ""
        model.commitDraft(top)
        #expect(model.isDefault(top))
        #expect(model.text(for: top) == "")
    }
}
