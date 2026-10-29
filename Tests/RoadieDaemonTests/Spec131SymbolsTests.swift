import AppKit
import Foundation
import Testing
@testable import RoadieDaemon

/// Session 131 : navigateur SF Symbols (Alfred 6), données de macOS.
struct Spec131SymbolsTests {
    @Test func queryKeywords() {
        #expect(LauncherSymbols.query("symbols heart") == "heart")
        #expect(LauncherSymbols.query("symboles") == "" && LauncherSymbols.query("sf cloud") == "cloud")
        #expect(LauncherSymbols.query("sfx") == nil && LauncherSymbols.query("symbolique") == nil)
    }

    @Test func macOSCatalogIsReadAndSearchable() throws {
        let catalog = LauncherSymbols.load()
        try #require(catalog.symbols.count > 9_000, "CoreGlyphs absent")
        let heart = LauncherSymbols.search("heart.circle", in: catalog.symbols)
        #expect(heart.first?.name.hasPrefix("heart.circle") == true)
        let fill = try #require(catalog.symbols.first { $0.name == "heart.circle.fill" })
        #expect(fill.categories.contains("health"))
        #expect(LauncherSymbols.versions(of: fill, releases: catalog.releases).first?.system == "macOS")
        // Mot-clé : « octothorpe » trouve « number ».
        #expect(LauncherSymbols.search("octothorpe", in: catalog.symbols).contains { $0.name == "number" })
        #expect(LauncherSymbols.search("", in: catalog.symbols, limit: 10).count == 10)
        #expect(NSImage(systemSymbolName: fill.name, accessibilityDescription: nil) != nil)
    }

    @Test func rankingAndCategories() {
        let symbols = [LauncherSymbols.Symbol(name: "cloud.heart", categories: [], keywords: [], release: "2019"),
                       LauncherSymbols.Symbol(name: "heart", categories: ["health"], keywords: [], release: "2019"),
                       LauncherSymbols.Symbol(name: "bolt", categories: [], keywords: ["heart attack"], release: "2019")]
        #expect(LauncherSymbols.search("heart", in: symbols).map(\.name) == ["heart", "cloud.heart", "bolt"])
        #expect(LauncherSymbols.categoryName("health") == "Santé" && LauncherSymbols.categoryName("nouveau") == "Nouveau")
        let releases = ["2019": ["macOS": "10.15", "iOS": "13.0", "visionOS": "1.0"]]
        #expect(LauncherSymbols.versions(of: symbols[1], releases: releases).map(\.system) == ["macOS", "iOS", "visionOS"])
    }

    /// Rendu hors écran pour le contrôle visuel (`ROADIE_131_SHOTS=<dossier>`).
    @MainActor @Test func offscreenRenders() throws {
        guard let folder = ProcessInfo.processInfo.environment["ROADIE_131_SHOTS"] else { return }
        let grid = SymbolGridView(frame: NSRect(x: 0, y: 0, width: SymbolGridView.cell * 6, height: SymbolGridView.cell * 4))
        grid.symbols = LauncherSymbols.search("heart", in: LauncherSymbols.load().symbols, limit: 24)
        grid.selection = 8
        grid.appearance = NSAppearance(named: .darkAqua)
        try png(grid, background: NSColor(white: 0.13, alpha: 1), to: "\(folder)/symbols-grid.png")
        let text = NSTextView(usingTextLayoutManager: false)
        text.frame = NSRect(x: 0, y: 0, width: 520, height: 220)
        text.textStorage?.setAttributedString(WorkflowMarkdownRenderer.render(
            "# Fuseaux\n\n| Ville | Heure | Écart |\n|:------|:-----:|------:|\n| Tokyo | 03:00 | +8 |\n| Lima | 13:00 | -6 |",
            folder: "/", font: .systemFont(ofSize: 14), width: 520))
        text.isVerticallyResizable = false
        text.frame = NSRect(x: 0, y: 0, width: 520, height: 220)
        try png(text, background: .white, to: "\(folder)/markdown-table.png")
    }

    @MainActor private func png(_ view: NSView, background: NSColor, to path: String) throws {
        let host = NSView(frame: view.bounds)
        host.wantsLayer = true
        host.layer?.backgroundColor = background.cgColor
        host.addSubview(view)
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
