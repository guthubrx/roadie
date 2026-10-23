import AppKit
import SwiftUI
import RoadieCore
import Testing
@testable import RoadieDaemon

struct Spec058SettingsGeometryTests {
    @Test func controlsShareColumnsEvenWhenLabelsHaveDifferentHeights() {
        let geometry = SettingsFormGeometry(width: 700, fontSize: 16)
        let short = geometry.frames(labelHeight: 20, controlHeight: 32)
        let long = geometry.frames(labelHeight: 70, controlHeight: 32)
        #expect(!geometry.stacked)
        #expect(short[1].minX == long[1].minX && short[1].maxX == long[1].maxX)
        #expect(long[0].height == 70)
        #expect(short[2].minX > short[1].maxX)
    }

    @Test(arguments: [8.0, 16.0, 24.0, 32.0])
    func narrowFormsKeepAllColumnsInsideTheirBounds(font: Double) {
        let geometry = SettingsFormGeometry(width: 360, fontSize: font)
        let frames = geometry.frames(labelHeight: 64, controlHeight: 44)
        #expect(frames.allSatisfy { $0.minX >= 0 && $0.maxX <= geometry.width })
        #expect(frames[1].minY >= frames[0].maxY)
    }
}

@MainActor
struct Spec058SettingsHelpTests {
    @Test func longHelpIsScrollBoundedAtLargeFontInsteadOfClippingItsText() {
        let long = String(repeating: "Chaque valeur valide est appliquée immédiatement. ", count: 100)
        let screen = CGSize(width: 760, height: 520)
        let short = SettingsHelpGeometry(title: "Aide", text: "Une ligne.", fontSize: 14, screen: screen)
        let large = SettingsHelpGeometry(title: "Aide complète", text: long, fontSize: 32, screen: screen)
        #expect(short.height < large.height)
        #expect(large.height <= screen.height - 100)
        #expect(large.width <= screen.width - 48)
    }
}

@MainActor
struct Spec058SettingsRenderingTests {
    @Test(arguments: SettingCategory.allCases)
    func everyCategoryRendersWithoutRewritingConfiguration(category: SettingCategory) throws {
        try render(category: category, width: 1040, font: 16)
    }

    @Test(arguments: SettingCategory.allCases)
    func everyCategoryFitsAtMinimumWidthAndLargeFont(category: SettingCategory) throws {
        try render(category: category, width: 760, font: 32)
    }

    private func render(category: SettingCategory, width: CGFloat, font: Double) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-058-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("roadies.toml")
        let original = """
        [interface]
        settings_text_font_size = \(font)
        settings_help_font_size = \(min(font, 24))
        [[rules]]
        id = "web-float"
        enabled = true
        priority = 100
        [rules.match]
        app = "Example"
        [rules.action]
        floating = true
        [[rules]]
        id = "documents"
        enabled = true
        [rules.match]
        app = "Documents"
        [rules.action]
        floating = false
        """
        try original.write(to: file, atomically: true, encoding: .utf8)
        let service = SettingsService(configPath: file.path, eventLog: EventLog(path: directory.appendingPathComponent("events.jsonl").path), afterWrite: {})
        let model = SettingsViewModel(service: service)
        model.select(category)
        let hosting = NSHostingView(rootView: SettingsView(model: model))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 760), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.frame = CGRect(x: 0, y: 0, width: width, height: 760)
        hosting.layoutSubtreeIfNeeded()
        defer { window.close() }
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        var labels = Set(SettingsCatalog.descriptors(in: category).filter {
            guard $0.collection == nil, case .choice = $0.kind else { return false }; return true
        }.map(\.label))
        if category == .selecteur { labels.formUnion(["Gestionnaire", "Au relâchement", "Champ de recherche", "Menu Actions"]) }
        let menus = descendants(hosting).compactMap { $0 as? NSPopUpButton }.filter { labels.contains($0.accessibilityLabel() ?? "") }
        #expect(menus.count == labels.count)
        let frames = menus.map { $0.convert($0.bounds, to: hosting) }
        #expect(menus.allSatisfy { menu in
            let font = menu.font ?? NSFont.systemFont(ofSize: 16)
            return menu.bounds.height >= ceil(font.ascender - font.descender + font.leading)
        })
        if let first = frames.first {
            #expect(frames.allSatisfy { abs($0.minX - first.minX) < 1 && abs($0.width - first.width) < 1 })
        }
        #expect(frames.allSatisfy { $0.minX >= 0 && $0.maxX <= width + 1 })
        #expect(try String(contentsOf: file, encoding: .utf8) == original)
        if let output = ProcessInfo.processInfo.environment["ROADIE_SETTINGS_RENDER_DIR"] {
            let folder = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: folder.appendingPathComponent("\(category.rawValue)-\(Int(width))-\(Int(font)).png"))
        }
    }
}
