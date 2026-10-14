import AppKit
import SwiftUI
import Testing
@testable import RoadieDaemon

@Suite
@MainActor
struct SettingsTypographyLiveTests {
    @Test
    func changingTheFontUpdatesTheExistingNativeMenuWithoutReopening() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-025-live-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("roadies.toml")
        try "[tiling]\nsplit_policy = \"balanced\"\n".write(to: config, atomically: true, encoding: .utf8)
        let model = SettingsViewModel(service: SettingsService(configPath: config.path, afterWrite: {}))
        model.select(.tuilage)
        let view = NSHostingView(rootView: SettingsView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        view.layoutSubtreeIfNeeded()
        let menu = try #require(firstMenu(in: view))
        #expect(menu.font?.pointSize == 16)
        let setting = try #require(SettingsCatalog.find(id: "interface.settings_text_font_size"))
        model.apply(setting, raw: "24")
        for _ in 0..<20 where menu.font?.pointSize != 24 {
            try await Task.sleep(for: .milliseconds(20))
            view.layoutSubtreeIfNeeded()
        }
        #expect(firstMenu(in: view) === menu)
        #expect(menu.font?.pointSize == 24)
        #expect(menu.menu?.font.pointSize == 24)
        #expect(model.interfaceFonts.settingsHelpFontSize == 14)
        #expect(model.interfaceFonts.settingsTitleFontSize == 22)
    }

    @Test
    func nativeSelectionWritesTheRawValueAndIgnoresDisabledLegacyItems() {
        var selected = "bsp"
        let binding = Binding(get: { selected }, set: { selected = $0 })
        let coordinator = SettingsChoicePicker.Coordinator(selection: binding)
        let menu = NSPopUpButton(frame: .zero, pullsDown: false)
        menu.addItem(withTitle: "Arbre persistant (spatialBsp)")
        menu.lastItem?.representedObject = "spatialBsp"
        coordinator.select(menu)
        #expect(selected == "spatialBsp")
        menu.addItem(withTitle: "Ancienne valeur")
        menu.lastItem?.representedObject = "Dwindle"
        menu.lastItem?.isEnabled = false
        menu.selectItem(at: 1)
        coordinator.select(menu)
        #expect(selected == "spatialBsp")
    }

    private func firstMenu(in view: NSView) -> NSPopUpButton? {
        if let menu = view as? NSPopUpButton { return menu }
        return view.subviews.lazy.compactMap { firstMenu(in: $0) }.first
    }
}
