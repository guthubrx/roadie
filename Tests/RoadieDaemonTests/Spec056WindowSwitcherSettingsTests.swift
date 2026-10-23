import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

@Suite
@MainActor
struct Spec056WindowSwitcherSettingsTests {
    private func makeModel() throws -> SettingsViewModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-056-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = directory.appendingPathComponent("roadies.toml")
        try "".write(to: config, atomically: true, encoding: .utf8)
        let log = EventLog(path: directory.appendingPathComponent("events.jsonl").path)
        return SettingsViewModel(service: SettingsService(configPath: config.path, eventLog: log, afterWrite: {}))
    }

    private func loadSwitcher(_ text: String) throws -> WindowSwitcherConfig {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-056-\(UUID().uuidString).toml")
        try text.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return try RoadieConfigLoader.load(from: url.path).switcher
    }

    private func withService(_ text: String, _ run: (SettingsService, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-056-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("roadies.toml")
        try text.write(to: file, atomically: false, encoding: .utf8)
        let log = EventLog(path: directory.appendingPathComponent("events.jsonl").path)
        try run(SettingsService(configPath: file.path, eventLog: log, afterWrite: {}), file)
    }

    private func descriptor(_ id: String) throws -> SettingDescriptor {
        try #require(SettingsCatalog.find(id: id))
    }

    private func expectApplied(_ result: SettingChangeResult) {
        guard case .applied = result else { Issue.record("écriture refusée : \(result)"); return }
    }

    private func row(_ profile: WindowSwitcherShortcutConfig) -> CollectionRow {
        CollectionRow(fields: [
            "id": .string(profile.id),
            "name": .string(profile.name),
            "hotkey": .string(profile.hotkey),
            "scope": .string(profile.scope),
            "release_action": .string(profile.releaseAction),
            "sort_order": .string(profile.sortOrder),
            "include_minimized": .bool(profile.includeMinimized),
            "include_hidden": .bool(profile.includeHidden),
            "include_fullscreen": .bool(profile.includeFullscreen),
            "one_per_app": .bool(profile.onePerApp),
        ])
    }

    @Test func profileLimitAndKeyCollisionsAreRejectedBeforeWriting() throws {
        try withService("") { service, file in
            let descriptor = try descriptor("switcher.shortcuts")
            let tooMany = (0..<10).map { row(WindowSwitcherShortcutConfig(id: "p\($0)", hotkey: "")) }
            #expect(!service.validateCollection(descriptor, value: .rows(tooMany)).isEmpty)
            let clash = [row(WindowSwitcherShortcutConfig(id: "a")),
                         row(WindowSwitcherShortcutConfig(id: "b", hotkey: "control+option+shift+tab"))]
            #expect(!service.validateCollection(descriptor, value: .rows(clash)).isEmpty)
            guard case .rejected = service.setCollection(descriptor.id, .rows(clash)) else {
                Issue.record("Raccourci conflictuel enregistré"); return
            }
            #expect(try String(contentsOf: file, encoding: .utf8).isEmpty)
            let commandOnly = [row(WindowSwitcherShortcutConfig(id: "command", hotkey: ""))]
            #expect(service.validateCollection(descriptor, value: .rows(commandOnly)).isEmpty)
            expectApplied(service.setCollection(descriptor.id, .rows(commandOnly)))
            #expect(try RoadieConfigLoader.load(from: file.path).switcher.shortcuts.first?.hotkey == "")
        }
    }

    @Test
    func defaultsMatchTheContract() {
        let switcher = WindowSwitcherConfig()
        #expect(switcher.enabled)
        #expect(switcher.style == "thumbnails")
        #expect(switcher.autoSize)
        #expect(switcher.thumbnailWidth == 220)
        #expect(switcher.fontSize == 16)
        #expect(switcher.fontFamily == "system")
        #expect(switcher.preview)
        #expect(switcher.excludedBundles.isEmpty)
        #expect(switcher.shortcuts == [WindowSwitcherShortcutConfig()])

        let profile = WindowSwitcherShortcutConfig()
        #expect(profile.id == "all")
        #expect(profile.name == "Toutes les fenêtres")
        #expect(profile.hotkey == "ctrl+alt+tab")
        #expect(profile.scope == "all")
        #expect(profile.releaseAction == "focus")
        #expect(profile.sortOrder == "recent")
        #expect(profile.includeMinimized)
        #expect(profile.includeHidden)
        #expect(profile.includeFullscreen)
        #expect(!profile.onePerApp)
    }

    @Test
    func catalogDefaultsMatchTheConfigDefaults() throws {
        let defaults = WindowSwitcherConfig()
        #expect(try descriptor("switcher.enabled").defaultValue == .bool(defaults.enabled))
        #expect(try descriptor("switcher.style").defaultValue == .string(defaults.style))
        #expect(try descriptor("switcher.auto_size").defaultValue == .bool(defaults.autoSize))
        #expect(try descriptor("switcher.thumbnail_width").defaultValue == .double(defaults.thumbnailWidth))
        #expect(try descriptor("switcher.font_size").defaultValue == .double(defaults.fontSize))
        #expect(try descriptor("switcher.font_family").defaultValue == .string(defaults.fontFamily))
        #expect(try descriptor("switcher.preview").defaultValue == .bool(defaults.preview))
    }

    @Test
    func switcherSettingsSitInTheSelecteurCategory() throws {
        let ids = [
            "switcher.enabled", "switcher.style", "switcher.auto_size", "switcher.thumbnail_width",
            "switcher.font_size", "switcher.font_family", "switcher.preview",
            "switcher.excluded_bundles", "switcher.shortcuts",
        ]
        for id in ids {
            #expect(try descriptor(id).category == .selecteur, "\(id)")
        }
    }

    @Test
    func selecteurCategoryListsEverySwitcherSettingInCatalogOrder() throws {
        let model = try makeModel()
        model.select(.selecteur)
        #expect(model.category == .selecteur)
        #expect(model.sections.map(\.category) == [.selecteur])
        #expect(model.sections.first?.descriptors.map(\.id) == [
            "switcher.enabled", "switcher.style", "switcher.auto_size", "switcher.thumbnail_width",
            "switcher.font_size", "switcher.font_family", "switcher.preview",
            "switcher.excluded_bundles", "switcher.shortcuts",
        ])
    }

    @Test
    func missingSwitcherSectionLoadsTheDefaults() throws {
        let switcher = try loadSwitcher("[fx.borders]\nenabled = true\n")
        #expect(switcher == WindowSwitcherConfig())
    }

    @Test
    func everySwitcherFieldDecodesFromToml() throws {
        let switcher = try loadSwitcher("""
        [switcher]
        enabled = false
        style = "list"
        auto_size = false
        thumbnail_width = 300
        font_size = 18
        font_family = "  Menlo  "
        preview = false
        excluded_bundles = ["com.apple.finder"]

        [[switcher.shortcuts]]
        id = "stage"
        name = "Stage actif"
        hotkey = "Ctrl + Alt + S"
        scope = "stage"
        release_action = "stay"
        sort_order = "title"
        include_minimized = false
        include_hidden = false
        include_fullscreen = false
        one_per_app = true
        """)
        #expect(!switcher.enabled)
        #expect(switcher.style == "list")
        #expect(!switcher.autoSize)
        #expect(switcher.thumbnailWidth == 300)
        #expect(switcher.fontSize == 18)
        #expect(switcher.fontFamily == "Menlo")
        #expect(!switcher.preview)
        #expect(switcher.excludedBundles == ["com.apple.finder"])
        #expect(switcher.shortcuts.count == 1)
        let profile = try #require(switcher.shortcuts.first)
        #expect(profile.id == "stage")
        #expect(profile.name == "Stage actif")
        #expect(profile.hotkey == "ctrl+alt+s")
        #expect(profile.scope == "stage")
        #expect(profile.releaseAction == "stay")
        #expect(profile.sortOrder == "title")
        #expect(!profile.includeMinimized)
        #expect(!profile.includeHidden)
        #expect(!profile.includeFullscreen)
        #expect(profile.onePerApp)
    }

    @Test
    func numericSwitcherValuesAreClampedAtLoad() throws {
        let low = try loadSwitcher("[switcher]\nthumbnail_width = 119\nfont_size = 9\n")
        #expect(low.thumbnailWidth == 120)
        #expect(low.fontSize == 10)
        let high = try loadSwitcher("[switcher]\nthumbnail_width = 401\nfont_size = 33.5\n")
        #expect(high.thumbnailWidth == 400)
        #expect(high.fontSize == 32)
    }

    @Test
    func invalidSwitcherChoicesFallBackToSafeValues() throws {
        let switcher = try loadSwitcher("[switcher]\nstyle = \"grid\"\nfont_family = \"   \"\n")
        #expect(switcher.style == "thumbnails")
        #expect(switcher.fontFamily == "system")

        let loaded = try loadSwitcher("[[switcher.shortcuts]]\nid = \"x\"\nscope = \"galaxy\"\nrelease_action = \"close\"\nsort_order = \"random\"\n")
        let shortcut = try #require(loaded.shortcuts.first)
        #expect(shortcut.scope == "all")
        #expect(shortcut.releaseAction == "focus")
        #expect(shortcut.sortOrder == "recent")
    }

    @Test
    func aShortcutWithOnlyAnIdKeepsEveryOtherDefault() throws {
        let loaded = try loadSwitcher("[[switcher.shortcuts]]\nid = \"minimal\"\n")
        #expect(loaded.shortcuts == [WindowSwitcherShortcutConfig(id: "minimal")])
    }

    @Test
    func anEmptyHotkeyMeansNoKeyboardShortcut() throws {
        let loaded = try loadSwitcher("[[switcher.shortcuts]]\nid = \"menu\"\nhotkey = \"\"\n")
        let shortcut = try #require(loaded.shortcuts.first)
        #expect(shortcut.hotkey.isEmpty)
    }

    @Test
    func profilesAreDedupedByIdAndCappedAtNine() throws {
        let profiles = (1...12).map { WindowSwitcherShortcutConfig(id: "p\($0)") }
        let capped = WindowSwitcherConfig(shortcuts: profiles + [WindowSwitcherShortcutConfig(id: "p1", scope: "stage")])
        #expect(capped.shortcuts.map(\.id) == (1...9).map { "p\($0)" })
        #expect(capped.shortcuts.first?.scope == "all")

        let duplicates = WindowSwitcherConfig(shortcuts: [
            WindowSwitcherShortcutConfig(id: "same", scope: "stage"),
            WindowSwitcherShortcutConfig(id: "same", scope: "desktop"),
        ])
        #expect(duplicates.shortcuts.map(\.scope) == ["stage"])

        let toml = (1...10).map { "[[switcher.shortcuts]]\nid = \"p\($0)\"\n" }.joined()
        let loaded = try loadSwitcher(toml)
        #expect(loaded.shortcuts.count == 9)
        #expect(loaded.shortcuts.last?.id == "p9")
    }

    @Test
    func shortcutChoicesHaveFrenchLabels() throws {
        let spec = try #require(try descriptor("switcher.shortcuts").collection)
        guard case .rows(_, let fields, _, _) = spec.shape else { Issue.record("rows attendu"); return }
        for key in ["scope", "release_action", "sort_order"] {
            let field = try #require(fields.first(where: { $0.path == [key] }))
            guard case .choice(let choices) = field.kind else { Issue.record("choix attendu : \(key)"); continue }
            for choice in choices {
                #expect(field.choiceLabels[choice] != nil, "\(key).\(choice)")
            }
        }
    }

    @Test
    func shortcutDefaultRowMatchesTheConfigDefaults() throws {
        let spec = try #require(try descriptor("switcher.shortcuts").collection)
        guard case .rows(let rows) = spec.defaultValue else { Issue.record("rows attendu"); return }
        #expect(rows == [row(WindowSwitcherShortcutConfig())])
    }

    @Test
    func profileEditorRejectsDuplicateIdsEmptyIdsAndUnknownChoices() throws {
        let spec = try #require(try descriptor("switcher.shortcuts").collection)
        #expect(SettingsCollectionCodec.validate(spec, value: .rows([row(WindowSwitcherShortcutConfig())])).isEmpty)

        let duplicates = [row(WindowSwitcherShortcutConfig(id: "same")), row(WindowSwitcherShortcutConfig(id: "same", scope: "stage"))]
        #expect(SettingsCollectionCodec.validate(spec, value: .rows(duplicates))["1.id"] == "Identifiant déjà utilisé.")

        let emptyID = [row(WindowSwitcherShortcutConfig(id: ""))]
        #expect(SettingsCollectionCodec.validate(spec, value: .rows(emptyID))["0.id"] == "Ce champ est obligatoire.")

        var unknownScope = row(WindowSwitcherShortcutConfig(id: "bad"))
        unknownScope.fields["scope"] = .string("galaxy")
        #expect(SettingsCollectionCodec.validate(spec, value: .rows([unknownScope]))["0.scope"] != nil)
    }

    @Test
    func shortcutProfilesSurviveSaveAndReloadWithEveryField() throws {
        try withService("[fx.borders]\nenabled = true\n") { service, file in
            let d = try descriptor("switcher.shortcuts")
            let stage = WindowSwitcherShortcutConfig(
                id: "stage", name: "Stage actif", hotkey: "ctrl+alt+s", scope: "stage",
                releaseAction: "stay", sortOrder: "title",
                includeMinimized: false, includeHidden: false, includeFullscreen: false, onePerApp: true
            )
            let app = WindowSwitcherShortcutConfig(id: "app", name: "Application", hotkey: "ctrl+alt+a", scope: "application")
            expectApplied(service.setCollection(d.id, .rows([row(stage), row(app)])))
            #expect(service.validity().isValid)
            #expect(try RoadieConfigLoader.load(from: file.path).switcher.shortcuts == [stage, app])

            guard case .rows(let rows) = try service.collection(of: d).get() else {
                Issue.record("rows attendu"); return
            }
            #expect(rows.compactMap { $0.fields["id"] } == [.string("stage"), .string("app")])

            expectApplied(service.resetCollection(d.id))
            #expect(try service.collection(of: d).get() == d.collection?.defaultValue)
            #expect(try RoadieConfigLoader.load(from: file.path).switcher.shortcuts == [WindowSwitcherShortcutConfig()])
        }
    }

    @Test
    func excludedBundlesSurviveSaveAndReset() throws {
        try withService("[fx.borders]\nenabled = true\n") { service, file in
            let d = try descriptor("switcher.excluded_bundles")
            expectApplied(service.setCollection(d.id, .list([.string("com.apple.finder")])))
            #expect(try RoadieConfigLoader.load(from: file.path).switcher.excludedBundles == ["com.apple.finder"])
            #expect(try service.collection(of: d).get() == .list([.string("com.apple.finder")]))

            expectApplied(service.resetCollection(d.id))
            #expect(try service.collection(of: d).get() == .list([]))
            #expect(try RoadieConfigLoader.load(from: file.path).switcher.excludedBundles.isEmpty)
        }
    }

    @Test
    func scalarSwitcherSettingsWriteAndRejectOutOfContractValues() throws {
        try withService("[fx.borders]\nenabled = true\n") { service, file in
            expectApplied(service.set("switcher.style", to: "list"))
            expectApplied(service.set("switcher.thumbnail_width", to: "300"))
            guard case .rejected = service.set("switcher.thumbnail_width", to: "500") else {
                Issue.record("largeur hors plage acceptée"); return
            }
            guard case .rejected = service.set("switcher.style", to: "grid") else {
                Issue.record("style hors liste accepté"); return
            }
            let switcher = try RoadieConfigLoader.load(from: file.path).switcher
            #expect(switcher.style == "list")
            #expect(switcher.thumbnailWidth == 300)
        }
    }
}
