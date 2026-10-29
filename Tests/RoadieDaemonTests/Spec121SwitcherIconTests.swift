import AppKit
import RoadieAX
import RoadieCore
import Testing
@testable import RoadieDaemon

/// Session 121 : icône de l'application à côté du titre dans le sélecteur, affichée par défaut, taille automatique
/// ou choisie.
@MainActor
struct Spec121SwitcherIconTests {
    private let entry = WindowSwitcherEntry(window: WindowSnapshot(id: WindowID(rawValue: 1), pid: 1,
        appName: "Notes", bundleID: "com.apple.Notes", title: "Courses de la semaine",
        frame: Rect(x: 0, y: 0, width: 800, height: 600), isOnScreen: true, isTileCandidate: true),
        scope: nil, displayName: "Écran", desktopName: "Bureau 1", stageName: "Perso")

    private func loadSwitcher(_ text: String) throws -> WindowSwitcherConfig {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-121-\(UUID().uuidString).toml")
        try text.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return try RoadieConfigLoader.load(from: url.path).switcher
    }

    /// Icône du titre : la vue d'image qui n'est pas la vignette.
    private func captionIcon(_ card: WindowSwitcherCardView) -> NSImageView? {
        card.subviews.compactMap { $0 as? NSImageView }.first { !($0 is WindowSwitcherThumbnailView) }
    }

    @Test func iconIsShownByDefaultWithAnAutomaticSize() throws {
        #expect(WindowSwitcherConfig().appIcon)
        #expect(WindowSwitcherConfig().appIconSize == 0)
        let switcher = try loadSwitcher("[switcher]\napp_icon = false\napp_icon_size = 40\n")
        #expect(!switcher.appIcon)
        #expect(switcher.appIconSize == 40)
        #expect(try loadSwitcher("[switcher]\napp_icon_size = 5\n").appIconSize == 12)
        #expect(try loadSwitcher("[switcher]\napp_icon_size = 90\n").appIconSize == 64)
        #expect(try loadSwitcher("[switcher]\napp_icon_size = -3\n").appIconSize == 0)
    }

    @Test func automaticSizeFollowsTheTextAndTheCardWidth() {
        let classic = WindowSwitcherAppearance(config: WindowSwitcherConfig())
        // Deux lignes de texte en 16 points : 41,7 points de haut, icône de 38.
        #expect(classic.iconSide == 38)
        #expect(classic.captionHeight == classic.textHeight)
        #expect(classic.captionIconSide(cardWidth: 220) == 38)
        #expect(classic.captionIconSide(cardWidth: 120) == 24)
        let small = WindowSwitcherAppearance(config: WindowSwitcherConfig(fontSize: 10))
        #expect(small.iconSide < classic.iconSide)
        let compact = WindowSwitcherAppearance(config: WindowSwitcherConfig(presentation: "sections"))
        #expect(compact.iconSide == 22)
        #expect(WindowSwitcherAppearance(config: WindowSwitcherConfig(style: "list")).iconSide == 28)
        #expect(WindowSwitcherAppearance(config: WindowSwitcherConfig(style: "icons")).iconSide == 56)
    }

    @Test func cardPutsTheIconLeftOfTheTitle() throws {
        let appearance = WindowSwitcherAppearance(config: WindowSwitcherConfig())
        let layout = WindowSwitcherGrid.layout(count: 1, appearance: appearance, available: 220)
        let card = WindowSwitcherCardView(entry: entry, image: nil, appearance: appearance, frame: layout.frames[0],
                                          appIcon: NSImage(size: NSSize(width: 64, height: 64)))
        let icon = try #require(captionIcon(card))
        let title = try #require(card.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == entry.window.title })
        #expect(icon.frame.width == appearance.captionIconSide(cardWidth: layout.cardSize.width))
        #expect(title.frame.minX >= icon.frame.maxX)
        #expect(icon.frame.maxY <= layout.cardSize.height)
    }

    @Test func disabledIconLeavesTheTitleAtTheEdge() throws {
        let appearance = WindowSwitcherAppearance(config: WindowSwitcherConfig(appIcon: false))
        #expect(appearance.iconSide == 0)
        let card = WindowSwitcherCardView(entry: entry, image: nil, appearance: appearance,
                                          frame: CGRect(x: 0, y: 0, width: 220, height: 200))
        #expect(captionIcon(card) == nil)
        let title = try #require(card.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == entry.window.title })
        #expect(title.frame.minX == 8)
        // Le style Icônes garde son icône : c'est l'image de la carte.
        #expect(WindowSwitcherAppearance(config: WindowSwitcherConfig(style: "icons", appIcon: false)).iconSide == 56)
        let list = WindowSwitcherAppearance(config: WindowSwitcherConfig(style: "list", appIcon: false))
        let row = WindowSwitcherCardView(entry: entry, image: nil, appearance: list, frame: CGRect(x: 0, y: 0, width: 500, height: 60))
        #expect(row.subviews.compactMap { $0 as? WindowSwitcherThumbnailView }.allSatisfy { $0.isHidden })
    }

    @Test func chosenSizeGrowsTheCaptionAndTheCards() {
        let automatic = WindowSwitcherAppearance(config: WindowSwitcherConfig())
        let large = WindowSwitcherAppearance(config: WindowSwitcherConfig(appIconSize: 64))
        #expect(large.iconSide == 64)
        #expect(large.captionHeight == 68)
        #expect(large.captionIconSide(cardWidth: 220) == 64)
        let before = WindowSwitcherGrid.layout(count: 2, appearance: automatic, available: 900)
        let after = WindowSwitcherGrid.layout(count: 2, appearance: large, available: 900)
        #expect(after.cardSize.height > before.cardSize.height)
        let list = WindowSwitcherAppearance(config: WindowSwitcherConfig(style: "list", appIconSize: 48))
        #expect(WindowSwitcherGrid.layout(count: 1, appearance: list, available: 500).cardSize.height == 64)
        let icons = WindowSwitcherAppearance(config: WindowSwitcherConfig(style: "icons", appIconSize: 32))
        let iconsAuto = WindowSwitcherAppearance(config: WindowSwitcherConfig(style: "icons"))
        #expect(WindowSwitcherGrid.layout(count: 1, appearance: icons, available: 500).cardSize.height
            == WindowSwitcherGrid.layout(count: 1, appearance: iconsAuto, available: 500).cardSize.height - 24)
    }
}
