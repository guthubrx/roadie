import AppKit
import RoadieAX
import RoadieCore
import Testing
@testable import RoadieDaemon

/// Session 122 : le sélecteur ne montre que les fenêtres ; ni titre « Roadie », ni résumé, ni aide en bas.
@MainActor
struct Spec122SwitcherChromeTests {
    private let entries = (1...6).map { i in
        WindowSwitcherEntry(window: WindowSnapshot(id: WindowID(rawValue: UInt32(i)), pid: 1,
            appName: "Application \(i)", bundleID: "fixture.\(i)", title: "Document \(i)",
            frame: Rect(x: 0, y: 0, width: 600, height: 400), isOnScreen: true, isTileCandidate: true),
            scope: nil, displayName: "Écran", desktopName: "Bureau 1", stageName: "Projet")
    }

    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }

    /// Textes visibles du panneau, hors cartes.
    private func chromeTexts(_ content: NSView) -> [String] {
        descendants(content).compactMap { $0 as? NSTextField }
            .filter { !$0.isHiddenOrHasHiddenAncestor && !($0 is NSSearchField) && !$0.stringValue.isEmpty
                && !($0.superview is WindowSwitcherCardView) }.map(\.stringValue)
    }

    @Test func onlyTheWindowsAreShown() throws {
        let panel = WindowSwitcherPanel(appearance: WindowSwitcherAppearance(config: WindowSwitcherConfig(preview: false)))
        defer { panel.close() }
        panel.configure(profile: WindowSwitcherShortcutConfig())
        panel.render(entries: entries, selectedID: entries[0].id, query: "", images: [:], previewImage: nil, emptyMessage: "Vide")
        let content = try #require(panel.contentView)
        let views = descendants(content)
        #expect(chromeTexts(content).isEmpty)
        #expect(views.compactMap { $0 as? NSSearchField }.allSatisfy { $0.isHidden })
        #expect(views.compactMap { $0 as? NSPopUpButton }.allSatisfy { $0.isHidden })
        let scroll = try #require(views.compactMap { $0 as? NSScrollView }.first { !$0.isHidden && $0.documentView?.subviews.contains { $0 is WindowSwitcherCardView } == true })
        #expect(scroll.frame.minY == 16)
        #expect(abs(content.bounds.height - scroll.frame.maxY - 16) < 1)
    }

    @Test func refusedActionAndSearchStillGetTheirPlace() throws {
        let panel = WindowSwitcherPanel(appearance: WindowSwitcherAppearance(config: WindowSwitcherConfig(preview: false)))
        defer { panel.close() }
        panel.configure(profile: WindowSwitcherShortcutConfig(searchVisibility: "always"))
        panel.render(entries: entries, selectedID: entries[0].id, query: "", images: [:], previewImage: nil, emptyMessage: "Vide")
        let content = try #require(panel.contentView)
        let search = try #require(descendants(content).compactMap { $0 as? NSSearchField }.first)
        #expect(!search.isHidden)
        #expect(abs(content.bounds.height - search.frame.maxY - 16) < 1)
        panel.showActionError()
        #expect(chromeTexts(content).contains { $0.hasPrefix("Action refusée") })
        let scroll = try #require(descendants(content).compactMap { $0 as? NSScrollView }.first { $0.documentView?.subviews.contains { $0 is WindowSwitcherCardView } == true })
        #expect(scroll.frame.minY > 16)
    }
}
