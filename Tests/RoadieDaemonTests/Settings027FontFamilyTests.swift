import AppKit
import Foundation
import SwiftUI
import Testing
import RoadieCore
@testable import RoadieDaemon

@Suite
struct Settings027FontFamilyTests {
    private func withConfig(_ raw: String, run: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-027-fonts-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("roadies.toml")
        try raw.write(to: config, atomically: true, encoding: .utf8)
        try run(config)
    }

    @Test
    func defaultsAndIndependentFamiliesSurviveDecodingAndEncoding() throws {
        #expect(TargetModeConfig().searchFontFamily == "system")
        #expect(TargetModeConfig().commandFontFamily == "system")
        try withConfig("""
        [experimental.target_mode]
        search_font_family = "Helvetica"
        command_font_family = "Menlo"
        search_text_font_size = 23
        command_text_font_size = 18
        """) { url in
            let report = RoadieConfigLoader.validate(path: url.path)
            #expect(!report.hasErrors)
            #expect(!report.items.contains { $0.message.contains("inconnue") })
            let config = try RoadieConfigLoader.load(from: url.path)
            let mode = config.experimental.targetMode
            #expect(mode.searchFontFamily == "Helvetica")
            #expect(mode.commandFontFamily == "Menlo")
            #expect(mode.searchTextFontSize == 23)
            #expect(mode.commandTextFontSize == 18)
            let encoded = try JSONEncoder().encode(mode)
            #expect(try JSONDecoder().decode(TargetModeConfig.self, from: encoded) == mode)
            let initial = TargetOverlayStyle.search(TargetModeConfig())
            let changed = TargetOverlayStyle.search(mode)
            #expect(changed.searchFontFamily == "Helvetica")
            #expect(changed.commandFontFamily == "Menlo")
            #expect(changed != initial)
            var onlyFamily = initial
            onlyFamily.searchFontFamily = "Helvetica"
            #expect(onlyFamily != initial)
            onlyFamily = initial
            onlyFamily.commandFontFamily = "Menlo"
            #expect(onlyFamily != initial)
        }
    }

    @Test
    func readingMissingFamilyDoesNotRewriteItAndUpdatesRemainIndependent() throws {
        let absent = "RoadieAbsentFamily-027"
        let raw = """
        # Famille fournie par un autre ordinateur.
        [experimental.target_mode]
        search_font_family = "\(absent)"
        command_font_family = "Menlo"
        search_text_font_size = 23
        command_text_font_size = 18
        """
        try withConfig(raw) { url in
            let service = SettingsService(configPath: url.path, afterWrite: {})
            let descriptor = try #require(SettingsCatalog.find(id: "target_mode.search_font_family"))
            #expect(service.value(of: descriptor).value == .string(absent))
            #expect(try String(contentsOf: url, encoding: .utf8) == raw)
            #expect(service.set("target_mode.search_font_family", to: "Helvetica") ==
                    .applied(old: .string(absent), new: .string("Helvetica")))
            var mode = try RoadieConfigLoader.load(from: url.path).experimental.targetMode
            #expect(mode.searchFontFamily == "Helvetica")
            #expect(mode.commandFontFamily == "Menlo")
            #expect(mode.searchTextFontSize == 23)
            #expect(mode.commandTextFontSize == 18)
            #expect(service.reset("target_mode.search_font_family") ==
                    .applied(old: .string("Helvetica"), new: .string("system")))
            mode = try RoadieConfigLoader.load(from: url.path).experimental.targetMode
            #expect(mode.searchFontFamily == "system")
            #expect(mode.commandFontFamily == "Menlo")
            #expect(try String(contentsOf: url, encoding: .utf8).contains("# Famille fournie par un autre ordinateur."))
        }
    }

    @Test @MainActor
    func actualInstalledFamilyUsesChosenSizeAndAbsentFamilyUsesSystem() throws {
        _ = NSApplication.shared
        let family = try #require(NSFontManager.shared.availableFontFamilies.first {
            NSFontManager.shared.font(withFamily: $0, traits: [], weight: 5, size: 27) != nil
        })
        let installed = SearchBarRenderer.font(family: family, size: 27)
        #expect(installed.familyName == family)
        #expect(installed.pointSize == 27)
        let missing = SearchBarRenderer.font(family: "RoadieAbsentFamily-027", size: 31)
        #expect(missing == NSFont.systemFont(ofSize: 31, weight: .regular))
        #expect(missing.pointSize == 31)
        #expect(SearchBarRenderer.font(family: "system", size: 19) == NSFont.systemFont(ofSize: 19))
    }

    @Test @MainActor
    func pickerKeepsMissingFamilyAndUpdatesTheExistingMenuSize() async throws {
        _ = NSApplication.shared
        let missing = "RoadieAbsentFamily-027"
        var selected = missing
        let binding = Binding(get: { selected }, set: { selected = $0 })
        let view = NSHostingView(rootView: SettingsFontFamilyPicker(fontSize: 16, selection: binding))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 60),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        view.layoutSubtreeIfNeeded()
        let menu = try #require(firstMenu(in: view))
        #expect(menu.selectedItem?.representedObject as? String == missing)
        #expect(menu.selectedItem?.title.contains("secours système") == true)
        #expect(menu.selectedItem?.isEnabled == false)
        #expect(selected == missing)
        view.rootView = SettingsFontFamilyPicker(fontSize: 24, selection: binding)
        for _ in 0..<20 where menu.font?.pointSize != 24 {
            try await Task.sleep(for: .milliseconds(20))
            view.layoutSubtreeIfNeeded()
        }
        #expect(firstMenu(in: view) === menu)
        #expect(menu.font?.pointSize == 24)
        #expect(menu.selectedItem?.representedObject as? String == missing)
        #expect(selected == missing)
        menu.selectItem(at: 0)
        SettingsFontFamilyPicker.Coordinator(selection: binding).select(menu)
        #expect(selected == "system")
    }

    @MainActor
    private func firstMenu(in view: NSView) -> NSPopUpButton? {
        if let menu = view as? NSPopUpButton { return menu }
        return view.subviews.lazy.compactMap { firstMenu(in: $0) }.first
    }
}
