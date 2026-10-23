import AppKit
import RoadieAX
import RoadieCore
import Testing
@testable import RoadieDaemon

@MainActor
struct Spec060SwitcherFidelityTests {
    private func entries() -> [WindowSwitcherEntry] {
        (1...8).map { id in
            let desktop = id < 6 ? 1 : 2
            let stage = id < 4 ? "Développement" : id < 6 ? "Communication" : "Quotidien"
            return WindowSwitcherEntry(window: WindowSnapshot(id: WindowID(rawValue: UInt32(id)), pid: Int32(id),
                appName: "Application \(id)", bundleID: "fixture.\(id)", title: "Fenêtre \(id) - titre détaillé",
                frame: Rect(x: Double((id - 1) % 3) * 600, y: 0, width: 600, height: 1100),
                isOnScreen: true, isTileCandidate: true),
                scope: StageScope(displayID: DisplayID(rawValue: "écran"), desktopID: DesktopID(rawValue: desktop),
                                  stageID: StageID(rawValue: stage)),
                displayName: "Écran principal", desktopName: "Bureau \(desktop)", stageName: stage)
        }
    }

    @Test func portraitThumbnailCropsTheTopWithoutStretching() {
        let crop = WindowSwitcherThumbnailView.sourceRect(image: CGSize(width: 600, height: 1200), target: CGSize(width: 300, height: 168))
        #expect(crop == CGRect(x: 0, y: 864, width: 600, height: 336))
        let wide = WindowSwitcherThumbnailView.sourceRect(image: CGSize(width: 1600, height: 600), target: CGSize(width: 300, height: 168))
        #expect(abs(wide.midX - 800) < 0.01)
        #expect(wide.maxY == 600)
        #expect(WindowSwitcherThumbnailView.sourceRect(image: .zero, target: .zero) == .zero)
    }

    @Test func groupedCardsUseTheRowAndOneCaptionRatherThanRepeatingContext() {
        let appearance = WindowSwitcherAppearance(config: WindowSwitcherConfig(presentation: "sections"))
        let layout = WindowSwitcherGrid.layout(count: 3, appearance: appearance, available: 830)
        #expect(layout.columns == 3)
        #expect(abs(layout.contentSize.width - 830) < 0.01)
        #expect(appearance.captionHeight < WindowSwitcherGrid.labelsHeight(fontSize: 16))
        let two = WindowSwitcherGrid.layout(count: 2, appearance: appearance, available: 830)
        #expect(two.cardSize.height == layout.cardSize.height)
        let card = WindowSwitcherCardView(entry: entries()[0], image: nil, appearance: appearance, frame: layout.frames[0])
        let captions = card.subviews.compactMap { $0 as? NSTextField }.filter { !$0.isHidden }
        #expect(captions.count == 1)
        #expect(captions.first?.stringValue == entries()[0].window.title)
        let smallPreferredWidth = WindowSwitcherAppearance(config: WindowSwitcherConfig(thumbnailWidth: 120, presentation: "sections"))
        #expect(smallPreferredWidth.imageHeight(cardWidth: 400) == 140)
        #expect(smallPreferredWidth.imageHeight(cardWidth: 120) < 70)
    }

    @Test func spatialCardsUseTheirHeightForTheImageAndColumnsShareUsefulSpace() throws {
        let appearance = WindowSwitcherAppearance(config: WindowSwitcherConfig(presentation: "overview"))
        let card = WindowSwitcherCardView(entry: entries()[0], image: nil, appearance: appearance,
                                          frame: CGRect(x: 0, y: 0, width: 180, height: 400))
        let imageView = try #require(card.subviews.compactMap { $0 as? WindowSwitcherThumbnailView }.first)
        #expect(imageView.frame.height > 340)
        let groups = WindowSwitcherGroups(entries: entries())
        let columns = WindowSwitcherGroupedGeometry.layout(entries: entries(),
            appearance: WindowSwitcherAppearance(config: WindowSwitcherConfig(presentation: "stage_columns")),
            width: 1400, browsing: SwitcherBrowsingState(desktop: groups.desktops[0].id))
        #expect(columns.surfaces[0].width > columns.surfaces[1].width)
        #expect(columns.cards.prefix(3).allSatisfy { $0.frame.minY == columns.cards[0].frame.minY })
    }

    @Test(arguments: WindowSwitcherPresentation.allCases)
    func groupedPanelStaysLandscapeOnTallAndWideScreensAndDetailsFollowSelection(presentation: WindowSwitcherPresentation) throws {
        let entries = entries()
        let panel = WindowSwitcherPanel(appearance: WindowSwitcherAppearance(config: WindowSwitcherConfig(presentation: presentation.rawValue)))
        defer { panel.close() }
        panel.configure(profile: WindowSwitcherShortcutConfig(searchVisibility: "always", actionsVisibility: "always"))
        for screen in [CGRect(x: 0, y: 0, width: 1200, height: 2000), CGRect(x: 0, y: 0, width: 1920, height: 1080)] {
            panel.layout(in: screen)
            panel.render(entries: entries, selectedID: entries[0].id, query: "", images: [:], previewImage: nil, emptyMessage: "Vide")
            #expect(panel.frame.width / panel.frame.height > 1.2)
            #expect(screen.contains(panel.frame))
            let content = try #require(panel.contentView)
            let detail = try #require(content.subviews.compactMap { $0 as? WindowSwitcherDetailView }.first)
            panel.select(entries[7].id, previewImage: nil)
            let labels = detail.subviews.compactMap { $0 as? NSTextField }.map(\.stringValue)
            #expect(labels.contains(entries[7].window.title))
            #expect(labels.contains("Bureau 2  ›  Quotidien"))
            var opened = false
            panel.onConfirm = { opened = true }
            let button = try #require(detail.subviews.compactMap { $0 as? NSButton }.first)
            button.performClick(nil)
            #expect(opened)
        }
    }

    @Test(arguments: WindowSwitcherPresentation.allCases)
    func nativeComparisonUsesEightPortraitWindows(presentation: WindowSwitcherPresentation) throws {
        let entries = entries()
        let images = Dictionary(uniqueKeysWithValues: entries.enumerated().map { index, entry in
            let image = NSImage(size: CGSize(width: 600, height: 1100))
            image.lockFocus()
            NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
            CGRect(x: 0, y: 0, width: 600, height: 1100).fill()
            NSColor(calibratedHue: CGFloat(index) / 10, saturation: 0.35, brightness: 0.35, alpha: 1).setFill()
            CGRect(x: 0, y: 1020, width: 600, height: 80).fill()
            (entry.window.title as NSString).draw(at: CGPoint(x: 30, y: 1040),
                withAttributes: [.font: NSFont.systemFont(ofSize: 26), .foregroundColor: NSColor.white])
            for row in 0..<18 {
                ("Projet Roadie    Ligne de contenu \(row + 1)" as NSString).draw(at: CGPoint(x: 30, y: 970 - row * 46),
                    withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 22, weight: .regular),
                                     .foregroundColor: row % 3 == 0 ? NSColor.systemTeal : NSColor.lightGray])
            }
            image.unlockFocus()
            return (entry.id, image)
        })
        let panel = WindowSwitcherPanel(appearance: WindowSwitcherAppearance(config: WindowSwitcherConfig(presentation: presentation.rawValue)))
        defer { panel.close() }
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.configure(profile: WindowSwitcherShortcutConfig(searchVisibility: "always", actionsVisibility: "always"))
        panel.layout(in: CGRect(x: 0, y: 0, width: 1600, height: 1000))
        panel.render(entries: entries, selectedID: entries[0].id, query: "", images: images, previewImage: images[entries[0].id], emptyMessage: "Vide")
        let content = try #require(panel.contentView)
        content.layoutSubtreeIfNeeded()
        let bitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        if let output = ProcessInfo.processInfo.environment["ROADIE_060_FIDELITY_RENDER_DIR"] {
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("\(presentation.rawValue).png"))
        }
    }

    @Test func elevenWindowsAcrossFourDesktopsFitOnePageAtSmallAndLargePreferredWidths() throws {
        let contexts: [(String, Int, String)] = [
            ("Externe", 2, "Développement"), ("Externe", 2, "Développement"),
            ("Intégré", 1, "Perso"), ("Intégré", 1, "Perso"), ("Intégré", 1, "Com"),
            ("Externe", 4, "Com"), ("Externe", 4, "Documents"),
            ("Intégré", 2, "Terminal"), ("Intégré", 2, "Terminal"),
            ("Intégré", 2, "Work"), ("Intégré", 2, "Work")]
        let entries = contexts.enumerated().map { index, context in
            WindowSwitcherEntry(window: WindowSnapshot(id: WindowID(rawValue: UInt32(index + 1)), pid: 1,
                appName: "Application", bundleID: "fixture", title: "Fenêtre \(index + 1)",
                frame: Rect(x: 0, y: 0, width: 600, height: 1100), isOnScreen: true, isTileCandidate: true),
                scope: StageScope(displayID: DisplayID(rawValue: context.0), desktopID: DesktopID(rawValue: context.1),
                                  stageID: StageID(rawValue: context.2)),
                displayName: context.0, desktopName: "Bureau \(context.1)", stageName: context.2)
        }
        let image = NSImage(size: CGSize(width: 600, height: 1100))
        image.lockFocus()
        NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
        CGRect(x: 0, y: 0, width: 600, height: 1100).fill()
        for row in 0..<20 {
            ("Projet Roadie · contenu \(row + 1)" as NSString).draw(at: CGPoint(x: 24, y: 1040 - row * 48),
                withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 24, weight: .regular), .foregroundColor: NSColor.systemTeal])
        }
        image.unlockFocus()
        let images = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, image) })
        for preferredWidth in [120.0, 220, 400] {
            for screen in [CGRect(x: 0, y: 0, width: 1920, height: 1080), CGRect(x: 0, y: 0, width: 3840, height: 2160)] {
                let panel = WindowSwitcherPanel(appearance: WindowSwitcherAppearance(config: WindowSwitcherConfig(
                    thumbnailWidth: preferredWidth, presentation: "sections")))
                defer { panel.close() }
                panel.configure(profile: WindowSwitcherShortcutConfig(searchVisibility: "always"))
                panel.layout(in: screen)
                panel.render(entries: entries, selectedID: entries[0].id, query: "", images: images, previewImage: image, emptyMessage: "Vide")
                let content = try #require(panel.contentView)
                let scroll = try #require(content.subviews.compactMap { $0 as? NSScrollView }.first {
                    $0.documentView?.subviews.contains(where: { $0 is WindowSwitcherCardView }) == true
                })
                let document = try #require(scroll.documentView)
                #expect(panel.renderedWindowIDs.count == 11)
                #expect(document.frame.height <= scroll.contentSize.height + 1)
                #expect(screen.contains(panel.frame))
                panel.select(entries.last?.id, previewImage: image)
                #expect(scroll.contentView.bounds.origin.y == 0)
                if preferredWidth == 120, screen.width == 1920,
                   let output = ProcessInfo.processInfo.environment["ROADIE_060_FIDELITY_RENDER_DIR"] {
                    content.layoutSubtreeIfNeeded()
                    let bitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
                    content.cacheDisplay(in: content.bounds, to: bitmap)
                    let png = try #require(bitmap.representation(using: .png, properties: [:]))
                    try png.write(to: URL(fileURLWithPath: output).appendingPathComponent("sections-onze-fenetres.png"))
                }
            }
        }
    }

    @Test func detailFitsLargeFontsAndShortPanes() throws {
        let detail = WindowSwitcherDetailView(frame: .zero)
        let entry = entries()[0]
        for size in [CGSize(width: 390, height: 180), CGSize(width: 360, height: 430)] {
            detail.frame.size = size
            detail.update(entry: entry, image: nil, icon: nil, appearance: WindowSwitcherAppearance(config: WindowSwitcherConfig(fontSize: 32)))
            for view in detail.subviews where !view.isHidden {
                #expect(view.frame.minX >= 0 && view.frame.maxX <= size.width)
                #expect(view.frame.minY >= 0 && view.frame.maxY <= size.height)
            }
        }
    }
}
