import AppKit
import Foundation
import RoadieCore
import Testing
@testable import RoadieDaemon

/// Session 101 : thèmes de la barre à la manière d'Alfred.
@Suite(.serialized)
@MainActor
struct Spec101ThemeTests {
    private let sample = """
    {"alfredtheme":{"name":"Mon Thème","window":{"color":"#102030E0","width":600,"roundness":10,"blur":12,"borderPadding":2,
    "borderColor":"#FF0000FF"},"search":{"background":"#00000020","text":{"size":30,"color":"#FFFFFFFF","colorSelected":"#FFFFFFFF",
    "font":"Avenir"}},"result":{"backgroundSelected":"#11223344","text":{"size":20,"color":"#EEEEEEFF","colorSelected":"#FFFFFFFF",
    "font":"Avenir"},"subtext":{"size":12,"color":"#AAAAAAFF","colorSelected":"#FFFFFFCC","font":"Avenir"}},"visualEffectMode":2}}
    """

    @Test func defaultThemeIsRoadieAndKeepsTheUserSizes() {
        let config = TargetModeConfig(searchTextFontSize: 20, commandTextFontSize: 16)
        let theme = LauncherThemeCatalog.resolve(config, dark: false) { [] }
        #expect(theme == .roadie)
        let style = TargetOverlayStyle.search(config, theme: theme)
        #expect(style.searchTextFontSize == 20)
        #expect(style.commandTextFontSize == 16)
        // Formule historique : 40 points à 15, 640 points de large.
        #expect(theme.barHeight(fontSize: 15) == 40)
        #expect(SearchBarLayout.make(bounds: CGRect(x: 0, y: 0, width: 1600, height: 1000), suggestions: 0, messageLines: 0).bar.width == 640)
    }

    @Test func alfredThemesBringTheirSizesFontsAndWidth() throws {
        let config = TargetModeConfig(theme: "alfred-dark")
        let theme = LauncherThemeCatalog.resolve(config, dark: false) { [] }
        #expect(theme.name == "Alfred Dark")
        let style = TargetOverlayStyle.search(config, theme: theme)
        #expect(style.searchTextFontSize == 34)
        #expect(style.commandTextFontSize == 18)
        #expect(style.searchFontFamily == "System Light")
        let bar = TargetSearchBar(query: "fi", matchCount: 0, properties: nil, isLoading: false)
        let layout = bar.layout(in: CGRect(x: 0, y: 0, width: 1600, height: 1000), style: style)
        #expect(layout.bar.width == 559)
        #expect(layout.bar.height == theme.barHeight(fontSize: 34))
        #expect(SearchBarRenderer.font(family: "System Light", size: 20).pointSize == 20)
    }

    @Test func darkModeUsesTheDarkThemeOnlyWhenSet() {
        let both = TargetModeConfig(theme: "alfred", themeDark: "alfred-modern-dark")
        #expect(LauncherThemeCatalog.resolve(both, dark: true) { [] }.id == "alfred-modern-dark")
        #expect(LauncherThemeCatalog.resolve(both, dark: false) { [] }.id == "alfred")
        let light = TargetModeConfig(theme: "alfred")
        #expect(LauncherThemeCatalog.resolve(light, dark: true) { [] }.id == "alfred")
        #expect(LauncherThemeCatalog.resolve(TargetModeConfig(theme: "inconnu"), dark: false) { [] } == .roadie)
    }

    @Test func anExportedAlfredThemeIsReadAndListed() throws {
        let theme = try #require(AlfredAppearanceReader.theme(from: Data(sample.utf8), id: "mon-theme"))
        #expect(theme.name == "Mon Thème")
        #expect(theme.windowColor == "#102030E0")
        #expect(theme.width == 600)
        #expect(theme.borderWidth == 2)
        #expect(theme.title.size == 20)
        #expect(theme.title.font == "Avenir")
        #expect(theme.effect == .dark)
        #expect(theme.blurAppearance == .darkAqua)
        // Clés absentes : celles du thème Alfred.
        #expect(theme.shortcut == LauncherTheme.builtIn[1].shortcut)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-101-\(UUID().uuidString)")
        let alfred = folder.appendingPathComponent("alfred")
        try FileManager.default.createDirectory(at: alfred.appendingPathComponent("ABC-123"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(sample.utf8).write(to: folder.appendingPathComponent("Nuit Bleue.alfredappearance"))
        try Data(sample.replacingOccurrences(of: "Mon Thème", with: "Perso Alfred").utf8)
            .write(to: alfred.appendingPathComponent("ABC-123/theme.json"))
        let found = LauncherThemeCatalog.imported(user: folder, alfred: alfred)
        #expect(found.map(\.id) == ["nuit-bleue", "perso-alfred"])
        let config = TargetModeConfig(theme: "nuit-bleue")
        #expect(LauncherThemeCatalog.resolve(config, dark: false) { found }.name == "Mon Thème")
    }

    @Test func visibleResultsCapTheList() {
        let bounds = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let heights = [CGFloat](repeating: 40, count: 30)
        #expect(SearchBarLayout.makeRich(bounds: bounds, heights: heights, selected: 0).suggestionRows.count > 9)
        #expect(SearchBarLayout.makeRich(bounds: bounds, heights: heights, selected: 0, maxRows: 5).suggestionRows.count == 5)
        // La sélection reste visible au-delà de la limite.
        let scrolled = SearchBarLayout.makeRich(bounds: bounds, heights: heights, selected: 12, maxRows: 5)
        #expect(scrolled.visibleRange(count: 30, selected: 12).contains(12))
        #expect(TargetModeConfig(visibleResults: 1).visibleResults == 3)
        #expect(TargetModeConfig(visibleResults: 50).visibleResults == 20)
    }

    /// Chaque thème fourni se dessine et change l'image. Avec `ROADIE_THEME_PREVIEW_DIR`, les rendus sont
    /// écrits en PNG pour la page de preuves (rendu hors écran, aucun contenu privé).
    @Test func everyBuiltInThemeDrawsDifferently() throws {
        var rows: [SlashSuggestion] = [SlashSuggestion(text: "Applications", detail: "", kind: .header)]
        for (name, detail) in [("Firefox", "/Applications/Firefox.app"), ("Finder", "/System/Library/CoreServices/Finder.app"),
                               ("Réglages Système", "/System/Applications/System Settings.app")] {
            var row = SlashSuggestion(text: name, detail: detail, kind: .result, icon: .symbol("app"))
            row.shortcut = "⌘\(rows.count)"
            rows.append(row)
        }
        let bar = TargetSearchBar(query: "fi", matchCount: 3, properties: nil, isLoading: false,
                                  suggestions: rows, selectedSuggestion: 1, richRows: true)
        let bounds = CGRect(x: 0, y: 0, width: 900, height: 420)
        let output = ProcessInfo.processInfo.environment["ROADIE_THEME_PREVIEW_DIR"].map { URL(fileURLWithPath: $0) }
        var images: Set<Data> = []
        for theme in LauncherTheme.builtIn {
            let style = TargetOverlayStyle.search(TargetModeConfig(), theme: theme)
            let image = NSImage(size: bounds.size)
            image.lockFocus()
            NSColor(calibratedRed: 0.35, green: 0.45, blue: 0.55, alpha: 1).setFill()
            bounds.fill()
            SearchBarRenderer.draw(bar, in: bounds, style: style)
            image.unlockFocus()
            let data = try #require(image.tiffRepresentation)
            images.insert(data)
            if let output, let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) {
                try png.write(to: output.appendingPathComponent("\(theme.id).png"))
            }
        }
        #expect(images.count == LauncherTheme.builtIn.count)
    }
}
