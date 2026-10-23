import AppKit
import RoadieCore
import RoadieAX
import Testing
@testable import RoadieDaemon

@MainActor
struct Spec056PanelRenderingTests {
    @Test(arguments: ["thumbnails", "icons", "list"])
    func nativePanelKeepsSelectionAndFitsItsScreen(style: String) throws {
        let appearance = WindowSwitcherAppearance(config: WindowSwitcherConfig(style: style, fontSize: 24))
        let panel = WindowSwitcherPanel(appearance: appearance)
        defer { panel.close() }
        let entries = (1...24).map { i in
            WindowSwitcherEntry(window: WindowSnapshot(id: WindowID(rawValue: UInt32(i)), pid: 1,
                appName: "Application \(i)", bundleID: "fixture.\(i)", title: "Document de travail \(i)",
                frame: Rect(x: 0, y: 0, width: 600, height: 400), isOnScreen: true, isTileCandidate: true),
                scope: nil, displayName: "Écran principal", desktopName: "Bureau 2", stageName: "Projet")
        }
        panel.render(entries: entries, selectedID: entries[2].id, query: "", images: [:],
                     previewImage: NSImage(size: NSSize(width: 600, height: 400)), emptyMessage: "Vide")
        let content = try #require(panel.contentView)
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let views = descendants(content)
        let cards = views.compactMap { $0 as? WindowSwitcherCardView }
        #expect(cards.count == 24)
        #expect(cards.filter(\.isSelected).map(\.entryID) == [entries[2].id])
        #expect(panel.frame.height <= 800)
        let search = try #require(views.compactMap { $0 as? NSSearchField }.first)
        let scroll = try #require(views.compactMap { $0 as? NSScrollView }.first)
        let preview = try #require(content.subviews.compactMap { $0 as? NSImageView }.first)
        #expect(search.frame.minX == 16)
        #expect(search.frame.maxX == content.bounds.width - 16)
        #expect(preview.frame.maxX < scroll.frame.minX)
        #expect(scroll.frame.maxX <= content.bounds.width - 16)
        #expect(preview.frame.height == scroll.frame.height)
        #expect(views.compactMap { $0 as? NSSearchField }.first?.font?.pointSize == 24)
        panel.switcherAppearance.fontSize = 18
        panel.render(entries: entries, selectedID: entries[2].id, query: "", images: [:], previewImage: nil, emptyMessage: "Vide")
        #expect(views.compactMap { $0 as? NSSearchField }.first?.font?.pointSize == 18)
        // Rendu natif hors écran : contrôle visuel complémentaire, pas une preuve de geste réel.
        if let directory = ProcessInfo.processInfo.environment["ROADIE_SWITCHER_RENDER_DIR"] {
            content.layoutSubtreeIfNeeded()
            let bitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
            content.cacheDisplay(in: content.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try data.write(to: url.appendingPathComponent("\(style).png"))
        }
    }
}
