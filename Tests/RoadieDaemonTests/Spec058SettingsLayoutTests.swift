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
    @Test func longHelpPanelIsBoundedAtLargeFont() {
        let long = String(repeating: "Chaque valeur valide est appliquée immédiatement. ", count: 100)
        let screen = CGSize(width: 760, height: 520)
        let short = SettingsHelpGeometry(title: "Aide", text: "Une ligne.", fontSize: 14, screen: screen)
        let large = SettingsHelpGeometry(title: "Aide complète", text: long, fontSize: 32, screen: screen)
        #expect(short.height < large.height)
        #expect(large.height <= screen.height - 100)
        #expect(large.width <= screen.width - 48)
    }

    @Test func longHelpCanScrollToItsEnd() throws {
        let text = String(repeating: "Une explication complète doit rester accessible. ", count: 120) + "Fin de l'aide."
        let hosting = NSHostingView(rootView: SettingsHelpContent(title: "Aide longue", text: text, fontSize: 32))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 480), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.close() }
        hosting.layoutSubtreeIfNeeded()
        func views(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + views($0) } }
        let scroll = try #require(views(hosting).compactMap { $0 as? NSScrollView }.first)
        let document = try #require(scroll.documentView)
        #expect(document.bounds.height > scroll.contentSize.height)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: document.bounds.height - scroll.contentSize.height))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(scroll.contentView.bounds.maxY >= document.bounds.maxY - 1)
    }
}

@MainActor
struct Spec058SettingsTabsTests {
    @Test func tabsFillTheRowWithEqualWidthsAndKeepTheirNamesReadable() {
        let titles = ["Raccourci", "Fenêtres", "Navigation", "Apparence"]
        for (width, font, expectedColumns) in [(700.0, 17.0, 4), (460.0, 32.0, 2), (366.0, 32.0, 2), (240.0, 32.0, 1)] {
            let geometry = SettingsTabsGeometry(width: width, titles: titles, fontSize: font)
            #expect(geometry.columns == expectedColumns)
            let frames = titles.indices.map { geometry.frame(at: $0) }
            #expect(frames.allSatisfy { $0.minX >= 0 && $0.maxX <= width + 1 && $0.width == frames[0].width })
            #expect(abs(frames[expectedColumns - 1].maxX - width) < 1)
            let nativeFont = NSFont.systemFont(ofSize: font, weight: .semibold)
            for (title, frame) in zip(titles, frames) {
                #expect((title as NSString).size(withAttributes: [.font: nativeFont]).width + 16 <= frame.width)
            }
        }
    }
}

@MainActor
struct Spec058SettingsRenderingTests {
    @Test(arguments: SettingCategory.allCases)
    func everyCategoryRendersWithoutRewritingConfiguration(category: SettingCategory) throws {
        try render(category: category, width: 1040, font: 16)
    }

    @Test(arguments: SettingCategory.allCases, [8.0, 16.0, 23.0, 24.0, 32.0])
    func everyCategoryFitsAtMinimumWidth(category: SettingCategory, font: Double) throws {
        try render(category: category, width: 760, font: font)
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
        #expect(menus.allSatisfy { $0.alignmentRectInsets.left == 0 && $0.alignmentRectInsets.right == 0 })
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
