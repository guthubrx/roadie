import AppKit
import Foundation
import RoadieAX
import RoadieCore
import Testing
@testable import RoadieDaemon

private func presentationEntry(_ id: UInt32, display: String = "A", desktop: Int = 1, stage: String = "dev",
                               title: String? = nil, frame: Rect? = nil) -> WindowSwitcherEntry {
    WindowSwitcherEntry(window: WindowSnapshot(id: WindowID(rawValue: id), pid: Int32(id), appName: "Application \(id)",
        bundleID: "test.app.\(id)", title: title ?? "Fenêtre \(id)",
        frame: frame ?? Rect(x: Double((id - 1) % 2) * 500, y: 0, width: 500, height: 600), isOnScreen: true, isTileCandidate: true),
        scope: StageScope(displayID: DisplayID(rawValue: display), desktopID: DesktopID(rawValue: desktop), stageID: StageID(rawValue: stage)),
        displayName: "Écran \(display)", desktopName: desktop == 1 ? "Travail" : "Personnel",
        stageName: stage == "dev" ? "Développement" : (stage == "daily" ? "Quotidien" : "Communication"))
}

private var presentationEntries: [WindowSwitcherEntry] {
    [presentationEntry(1, title: "Serveur local"), presentationEntry(2, title: "Projet Roadie"),
     presentationEntry(3, stage: "com", title: "Boîte de réception"),
     presentationEntry(4, desktop: 2, stage: "daily", title: "Documents")]
}

struct Spec060GroupingTests {
    @Test func anonymousStagesUseRailLabelsInsteadOfInternalIdentifiers() throws {
        let display = DisplayID(rawValue: "A")
        let generated = StageID(rawValue: "stage-9c5ab47e-92f4")
        let member = PersistentStageMember(windowID: WindowID(rawValue: 1), bundleID: "fixture", title: "Terminal",
            frame: Rect(x: 0, y: 0, width: 500, height: 600))
        let scope = PersistentStageScope(displayID: display, stages: [PersistentStage(id: StageID(rawValue: "empty")),
            PersistentStage(id: generated, name: "Stage \(generated.rawValue)", members: [member]),
            PersistentStage(id: StageID(rawValue: "com"), name: "Communication")])
        let state = PersistentStageState(scopes: [scope])
        let labels = WindowSwitcherService.stageLabels(in: state, liveWindowIDs: [member.windowID])
        let key = StageScope(displayID: display, desktopID: scope.desktopID, stageID: generated)
        #expect(labels[key] == "Stage 1")
        let entry = WindowSwitcherEntry(window: presentationEntry(1).window, scope: key)
        #expect(WindowSwitcherGroups(entries: [entry]).stages.first?.title == "Stage sans nom")
        #expect(labels.values.allSatisfy { !$0.contains(generated.rawValue) })
    }

    @Test func scopesNotNamesSeparateHomonymsAndKeepInputOrder() {
        let entries = [presentationEntry(4, desktop: 2), presentationEntry(1), presentationEntry(2),
                       presentationEntry(3, display: "B"), presentationEntry(5, stage: "other")]
        let groups = WindowSwitcherGroups(entries: entries)
        #expect(groups.desktops.count == 3)
        #expect(groups.stages.count == 4)
        #expect(groups.stages.first?.entries.map(\.id) == [entries[0].id])
        #expect(groups.stages[1].entries.map(\.id) == [entries[1].id, entries[2].id])
        #expect(Set(groups.stages.map(\.id)).count == 4)
    }

    @Test func windowsWithoutScopesRemainVisibleInTheirOwnGroup() {
        let base = presentationEntry(9)
        let unknown = WindowSwitcherEntry(window: base.window, scope: nil)
        let groups = WindowSwitcherGroups(entries: [unknown, presentationEntry(1)])
        #expect(groups.desktops.count == 2)
        #expect(groups.stages.first?.title == "Autres fenêtres")
        #expect(groups.stages.first?.entries.first?.id == unknown.id)
    }

    @Test func browsingFollowsGlobalSelectionAndRecoversAfterFiltering() {
        let entries = presentationEntries
        var browsing = SwitcherBrowsingState()
        browsing.reconcile(groups: WindowSwitcherGroups(entries: entries), selectedID: entries[3].id)
        #expect(browsing.desktop?.desktop == DesktopID(rawValue: 2))
        browsing.reconcile(groups: WindowSwitcherGroups(entries: [entries[0]]), selectedID: nil)
        #expect(browsing.stage == SwitcherGroupID(scope: entries[0].scope))
        browsing.reconcile(groups: WindowSwitcherGroups(entries: []), selectedID: nil)
        #expect(browsing.desktop == nil && browsing.stage == nil)
    }

    @Test(arguments: WindowSwitcherPresentation.allCases, ["thumbnails", "icons", "list"])
    func everyPresentationKeepsCardsInsideDocument(presentation: WindowSwitcherPresentation, style: String) {
        let entries = presentationEntries
        var browsing = SwitcherBrowsingState()
        browsing.reconcile(groups: WindowSwitcherGroups(entries: entries), selectedID: entries[0].id)
        for width in [220.0, 500.0, 1000.0] {
            for font in [10.0, 16.0, 32.0] {
                let appearance = WindowSwitcherAppearance(config: WindowSwitcherConfig(style: style, fontSize: font, presentation: presentation.rawValue))
                let layout = WindowSwitcherGroupedGeometry.layout(entries: entries, appearance: appearance, width: width, browsing: browsing)
                #expect(!layout.cards.isEmpty)
                for card in layout.cards {
                    #expect(card.frame.minX >= 0 && card.frame.maxX <= width + 0.01)
                    #expect(card.frame.minY >= 0 && card.frame.maxY <= layout.size.height + 0.01)
                    #expect(card.frame.width > 0 && card.frame.height > 0)
                }
                #expect(Set(layout.cards.map(\.entry.id)).count == layout.cards.count)
                for (i, card) in layout.cards.enumerated() {
                    #expect(layout.cards.dropFirst(i + 1).allSatisfy { !card.frame.intersects($0.frame) })
                }
            }
        }
    }

    @Test(arguments: WindowSwitcherPresentation.allCases)
    func emptyResultsProduceNoCardsOrStaleGroups(presentation: WindowSwitcherPresentation) {
        let appearance = WindowSwitcherAppearance(config: WindowSwitcherConfig(presentation: presentation.rawValue))
        let layout = WindowSwitcherGroupedGeometry.layout(entries: [], appearance: appearance, width: 600, browsing: SwitcherBrowsingState())
        #expect(layout.cards.isEmpty && layout.headings.isEmpty)
        #expect(layout.size.height == 0)
    }

    @Test func viewsFilterOnlyTheirLocalGroupAndAllWindowViewsKeepEverything() {
        let entries = presentationEntries
        var state = SwitcherBrowsingState()
        state.reconcile(groups: WindowSwitcherGroups(entries: entries), selectedID: entries[0].id)
        for presentation in WindowSwitcherPresentation.allCases {
            let appearance = WindowSwitcherAppearance(config: WindowSwitcherConfig(presentation: presentation.rawValue))
            let layout = WindowSwitcherGroupedGeometry.layout(entries: entries, appearance: appearance, width: 1000, browsing: state)
            let expected = presentation == .hierarchy ? 2 : ([.desktopTabs, .stageColumns].contains(presentation) ? 3 : 4)
            #expect(layout.cards.count == expected)
            if presentation == .sections || presentation == .overview {
                #expect(layout.headings.filter(\.isDesktop).count == 2)
                #expect(layout.headings.filter { !$0.isDesktop }.count == 3)
            }
        }
    }

    @Test func spatialOverviewPreservesRelativeWindowPositionsAndFallsBackForOverlap() throws {
        let entries = [presentationEntry(1, frame: Rect(x: -1000, y: 0, width: 500, height: 600)),
                       presentationEntry(2, frame: Rect(x: -500, y: 0, width: 500, height: 300)),
                       presentationEntry(3, frame: Rect(x: -500, y: 300, width: 500, height: 300))]
        let frames = try #require(WindowSwitcherGroupedGeometry.spatialFrames(entries: entries, width: 600, fontSize: 16))
        #expect(frames[0].minX < frames[1].minX)
        #expect(frames[1].minY < frames[2].minY)
        #expect(abs(frames[0].height - (frames[1].height + frames[2].height + 6)) < 1)
        #expect(WindowSwitcherGroupedGeometry.spatialFrames(entries: [entries[0], entries[0]], width: 600, fontSize: 16) == nil)
        #expect(WindowSwitcherGroupedGeometry.spatialFrames(entries: entries, width: 120, fontSize: 32) == nil)
    }

    @Test func arrowsReachBothUnequalWindowsInTheSpatialPlan() {
        let frames = [CGRect(x: 0, y: 0, width: 200, height: 400), CGRect(x: 210, y: 0, width: 200, height: 190),
                      CGRect(x: 210, y: 210, width: 200, height: 190)]
        #expect(SwitcherNavigation.destination(from: 0, direction: .right, frames: frames) == 1)
        #expect(SwitcherNavigation.destination(from: 1, direction: .down, frames: frames) == 2)
        #expect(SwitcherNavigation.destination(from: 2, direction: .left, frames: frames) == 0)
    }
}

@MainActor
struct Spec060SettingsTests {
    @Test func oldConfigurationIsNotRewrittenAndUsesTheClassicGrid() throws {
        let text = "[switcher]\nstyle = \"icons\"\n[[switcher.shortcuts]]\nid = \"all\"\nrelease_action = \"stay\"\n"
        try withConfig(text) { url, service in
            _ = SettingsViewModel(service: service)
            let config = try RoadieConfigLoader.load(from: url.path).switcher
            #expect(config.presentation == "classic")
            #expect(config.shortcuts[0].presentationOverride == nil)
            #expect(config.shortcuts[0].releaseAction == "stay")
            #expect(try String(contentsOf: url, encoding: .utf8) == text)
        }
    }

    @Test(arguments: WindowSwitcherPresentation.allCases)
    func choicesPersistImmediatelyAndProfilesCanOverrideAndInherit(presentation: WindowSwitcherPresentation) throws {
        try withConfig("[switcher]\n[[switcher.shortcuts]]\nid = \"all\"\n") { url, service in
            let outcome = service.set("switcher.presentation", to: presentation.rawValue)
            if case .rejected(let message) = outcome { Issue.record("\(message)") }
            var config = try RoadieConfigLoader.load(from: url.path).switcher
            #expect(config.presentation == presentation.rawValue)
            #expect(WindowSwitcherAppearance(config: config, profile: config.shortcuts[0]).presentation == presentation)
            let descriptor = try #require(SettingsCatalog.find(id: "switcher.shortcuts"))
            let collection = try service.collection(of: descriptor).get()
            guard case .rows(var rows) = collection else { Issue.record("Profils attendus"); return }
            rows[0].fields["presentation"] = .string("hierarchy")
            if case .rejected(let message) = service.setCollection(descriptor.id, .rows(rows)) { Issue.record("\(message)") }
            config = try RoadieConfigLoader.load(from: url.path).switcher
            #expect(WindowSwitcherAppearance(config: config, profile: config.shortcuts[0]).presentation == .hierarchy)
            rows[0].fields["presentation"] = .unset
            if case .rejected(let message) = service.setCollection(descriptor.id, .rows(rows)) { Issue.record("\(message)") }
            config = try RoadieConfigLoader.load(from: url.path).switcher
            #expect(WindowSwitcherAppearance(config: config, profile: config.shortcuts[0]).presentation == presentation)
            if case .rejected = service.set("switcher.presentation", to: "invalid") {} else { Issue.record("Valeur inconnue acceptée") }
        }
    }

    @Test func invalidValuesFallBackWithoutChangingReleaseAction() {
        let config = WindowSwitcherConfig(presentation: "other")
        let profile = WindowSwitcherShortcutConfig(releaseAction: "search", presentationOverride: "other")
        #expect(config.presentation == "classic" && profile.presentationOverride == nil)
        #expect(profile.releaseAction == "search")
    }

    private func withConfig(_ text: String, body: (URL, SettingsService) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-060-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("roadies.toml")
        try text.write(to: url, atomically: true, encoding: .utf8)
        try body(url, SettingsService(configPath: url.path, eventLog: EventLog(path: directory.appendingPathComponent("events.jsonl").path), afterWrite: {}))
    }
}

@MainActor
struct Spec060PanelTests {
    @Test func thumbnailRefreshPreservesManualScrollUntilSelectionChanges() throws {
        let entries = (1...60).map { presentationEntry(UInt32($0)) }
        let panel = WindowSwitcherPanel(appearance: WindowSwitcherAppearance(config: WindowSwitcherConfig(presentation: "sections")))
        defer { panel.close() }
        panel.layout(in: CGRect(x: 0, y: 0, width: 1200, height: 800))
        panel.render(entries: entries, selectedID: entries[0].id, query: "", images: [:], previewImage: nil, emptyMessage: "Vide")
        let content = try #require(panel.contentView)
        let scroll = try #require(content.subviews.compactMap { $0 as? NSScrollView }.first { $0.documentView?.subviews.contains(where: { $0 is WindowSwitcherCardView }) == true })
        scroll.contentView.scroll(to: CGPoint(x: 0, y: 400))
        scroll.reflectScrolledClipView(scroll.contentView)
        let before = scroll.contentView.bounds.origin
        #expect(before.y > 0)
        panel.render(entries: entries, selectedID: entries[0].id, query: "", images: [:], previewImage: nil, emptyMessage: "Vide")
        #expect(scroll.contentView.bounds.origin == before)
        panel.select(entries.last?.id, previewImage: nil)
        #expect(scroll.contentView.bounds.origin.y > before.y)
    }

    @Test(arguments: WindowSwitcherPresentation.allCases)
    func heldCommandArrowsHoverAndPressUseTheSameSelectedIdentity(presentation: WindowSwitcherPresentation) throws {
        let entries = Array(presentationEntries.prefix(2))
        let panel = WindowSwitcherPanel(appearance: WindowSwitcherAppearance(config: WindowSwitcherConfig(presentation: presentation.rawValue)))
        defer { panel.close() }
        panel.configure(profile: WindowSwitcherShortcutConfig(), navigationModifiers: [.command])
        panel.layout(in: CGRect(x: 0, y: 0, width: 1440, height: 900))
        panel.render(entries: entries, selectedID: entries[0].id, query: "", images: [:], previewImage: nil, emptyMessage: "Vide")
        var highlighted = entries[0].id
        panel.onHighlight = { highlighted = $0; panel.select($0, previewImage: nil) }
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124))
        panel.sendEvent(event)
        #expect(highlighted == entries[1].id)
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let content = try #require(panel.contentView)
        let first = try #require(descendants(content).compactMap { $0 as? WindowSwitcherCardView }.first { $0.entryID == entries[0].id })
        panel.hover(at: first.convert(CGPoint(x: first.bounds.midX, y: first.bounds.midY), to: nil))
        #expect(highlighted == entries[0].id)
        var activated: WindowID?
        panel.onSelect = { activated = $0 }
        #expect(first.accessibilityPerformPress())
        #expect(activated == entries[0].id)
    }

    @Test(arguments: WindowSwitcherPresentation.allCases)
    func nativeRenderingShowsTheSelectedWindowAndItsGroup(presentation: WindowSwitcherPresentation) throws {
        let entries = presentationEntries
        let image = NSImage(size: CGSize(width: 800, height: 500))
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSRect(x: 0, y: 0, width: 800, height: 500).fill()
        ("Fenêtre de test\n\nServeur local\nProjet Roadie" as NSString).draw(at: CGPoint(x: 30, y: 260),
            withAttributes: [.font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.labelColor])
        image.unlockFocus()
        let images = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, image) })
        let panel = WindowSwitcherPanel(appearance: WindowSwitcherAppearance(config: WindowSwitcherConfig(presentation: presentation.rawValue)))
        defer { panel.close() }
        panel.configure(profile: WindowSwitcherShortcutConfig(searchVisibility: "always", actionsVisibility: "always"))
        panel.layout(in: CGRect(x: 0, y: 0, width: 1440, height: 900))
        panel.render(entries: entries, selectedID: entries[0].id, query: "", images: images, previewImage: image, emptyMessage: "Vide")
        let content = try #require(panel.contentView)
        content.layoutSubtreeIfNeeded()
        let bitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let selectedCard = descendants(content).compactMap { $0 as? WindowSwitcherCardView }.first { $0.isSelected }
        let selected = try #require(selectedCard)
        #expect(selected.entryID == entries[0].id)
        for view in selected.subviews { #expect(view.frame.maxY <= selected.bounds.maxY + 1) }
        if let output = ProcessInfo.processInfo.environment["ROADIE_060_RENDER_DIR"] {
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("\(presentation.rawValue).png"))
        }
    }

    @Test(arguments: WindowSwitcherPresentation.allCases)
    func selectionCrossesGroupsWithoutChangingTheGlobalWindowList(presentation: WindowSwitcherPresentation) throws {
        let entries = presentationEntries
        let panel = WindowSwitcherPanel(appearance: WindowSwitcherAppearance(config: WindowSwitcherConfig(presentation: presentation.rawValue)))
        defer { panel.close() }
        panel.configure(profile: WindowSwitcherShortcutConfig(searchVisibility: "always"))
        panel.layout(in: CGRect(x: 0, y: 0, width: 1200, height: 800))
        panel.render(entries: entries, selectedID: entries[0].id, query: "", images: [:], previewImage: nil, emptyMessage: "Aucune fenêtre")
        #expect(panel.renderedWindowIDs.contains(entries[0].id))
        panel.select(entries[3].id, previewImage: nil)
        #expect(panel.renderedWindowIDs.contains(entries[3].id))
        panel.select(entries[0].id, previewImage: nil)
        #expect(panel.renderedWindowIDs.contains(entries[0].id))
        var highlighted: WindowID?
        panel.onHighlight = { highlighted = $0; panel.select($0, previewImage: nil) }
        if [.stageColumns, .desktopTabs].contains(presentation) {
            panel.chooseGroup(SwitcherGroupID(scope: entries[3].scope, desktopOnly: true))
            #expect(highlighted == entries[3].id)
        } else if presentation == .hierarchy {
            panel.chooseGroup(SwitcherGroupID(scope: entries[2].scope))
            #expect(highlighted == entries[2].id)
        }
        panel.render(entries: [entries[3]], selectedID: entries[3].id, query: "Documents", images: [:], previewImage: nil, emptyMessage: "Aucune fenêtre")
        #expect(panel.renderedWindowIDs == [entries[3].id])
        #expect(entries == presentationEntries)
    }

    @Test(arguments: WindowSwitcherPresentation.allCases)
    func nativeLayoutsFitSmallScreensAndCanChangeWhileOpen(presentation: WindowSwitcherPresentation) throws {
        let entries = presentationEntries
        let panel = WindowSwitcherPanel(appearance: WindowSwitcherAppearance(config: WindowSwitcherConfig(fontSize: 32)))
        defer { panel.close() }
        panel.configure(profile: WindowSwitcherShortcutConfig(searchVisibility: "always", actionsVisibility: "always"))
        panel.layout(in: CGRect(x: 0, y: 0, width: 390, height: 600))
        panel.render(entries: entries, selectedID: entries[0].id, query: "", images: [:], previewImage: nil, emptyMessage: "Vide")
        panel.switcherAppearance = WindowSwitcherAppearance(config: WindowSwitcherConfig(fontSize: 32, presentation: presentation.rawValue))
        panel.configure(profile: WindowSwitcherShortcutConfig(searchVisibility: "always", actionsVisibility: "always"))
        panel.render(entries: entries, selectedID: entries[0].id, query: "", images: [:], previewImage: nil, emptyMessage: "Vide")
        #expect(panel.frame.minX >= 0 && panel.frame.maxX <= 390)
        #expect(panel.frame.minY >= 0 && panel.frame.maxY <= 600)
        let content = try #require(panel.contentView)
        for view in content.subviews where !view.isHidden {
            #expect(view.frame.minX >= 0 && view.frame.maxX <= content.bounds.maxX + 1)
            #expect(view.frame.minY >= 0 && view.frame.maxY <= content.bounds.maxY + 1)
        }
        let field = try #require(content.subviews.compactMap { $0 as? NSSearchField }.first)
        #expect(field.frame.width == content.bounds.width - 32)
    }
}
