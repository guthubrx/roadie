import AppKit
import Carbon
import Testing
import RoadieCore
import RoadieAX
@testable import RoadieDaemon

@Suite("Spec061 Vue d’ensemble")
struct Spec061OverviewTests {
    @Test func defaultsAndBounds() {
        #expect(OverviewConfig().presentation == "archipelago")
        #expect(OverviewConfig().loupe)
        #expect(OverviewConfig().hotkey.isEmpty)
        #expect(OverviewConfig(magnification: 400).magnification == 250)
        #expect(OverviewConfig(magnification: 0).magnification == 100)
        #expect(OverviewConfig(magnification: .nan).magnification == 150)
        #expect(OverviewConfig(presentation: "wrong").presentation == "archipelago")
        #expect(OverviewConfig().backgroundBlur == 20)
        #expect(OverviewConfig(backgroundBlur: 140).backgroundBlur == 100)
        #expect(OverviewConfig(backgroundBlur: -5).backgroundBlur == 0)
        #expect(OverviewConfig(backgroundBlur: .nan).backgroundBlur == 20)
        #expect(OverviewConfig().selectionWidth == 2 && OverviewConfig().selectionColor == "#66C2F7")
        #expect(OverviewConfig(selectionWidth: 20).selectionWidth == 8)
        #expect(OverviewConfig(selectionWidth: 0).selectionWidth == 1)
    }

    @Test func commandIsStrict() {
        for verb in ["show", "toggle", "hide", "status"] {
            #expect(OverviewController.command([verb])?.name == "overview.\(verb)")
        }
        #expect(OverviewController.command(["show", "garbage"]) == nil)
        #expect(OverviewController.command([]) == nil)
    }

    @Test func hoverRequiresNewMovementAndDwell() {
        var hover = OverviewHoverState()
        let a = OverviewHoverTarget(desktopID: OverviewDesktopID(displayID: DisplayID(rawValue: "A"), desktopID: DesktopID(rawValue: 1)), windowID: nil)
        let firstMove = hover.moved(to: a, at: 1)
        #expect(firstMove)
        #expect(hover.ready(at: 1.05) == nil)
        #expect(hover.ready(at: 1.11) == a)
        hover.consume()
        #expect(hover.ready(at: 2) == nil)
        let sameMove = hover.moved(to: a, at: 2)
        #expect(!sameMove)
    }
}

private func overviewFixture(_ count: Int) -> OverviewModel {
    var entries: [WindowSwitcherEntry] = []
    for i in 0..<count {
        let window = WindowSnapshot(id: WindowID(rawValue: UInt32(i + 1)), pid: 42, appName: "Terminal",
            bundleID: "fixture.terminal", title: "Fenêtre \(i + 1)", frame: Rect(x: 0, y: 0, width: 900, height: 600), isOnScreen: true, isTileCandidate: true)
        let display = DisplayID(rawValue: i % 2 == 0 ? "A" : "B")
        let scope = StageScope(displayID: display, desktopID: DesktopID(rawValue: i % 3 + 1), stageID: StageID(rawValue: "stage-\(i % 4)"))
        entries.append(WindowSwitcherEntry(window: window, scope: scope, displayName: "Écran", desktopName: "Travail", stageName: "Développement"))
    }
    let displays = ["A", "B"].enumerated().map { i, id in
        DisplaySnapshot(id: DisplayID(rawValue: id), index: i, name: "Écran \(id)", frame: Rect(x: 0, y: 0, width: 1920, height: 1080), visibleFrame: Rect(x: 0, y: 0, width: 1920, height: 1040), isMain: i == 0)
    }
    return OverviewModel(entries: entries, displays: displays, state: PersistentStageState())
}

private func overviewReferenceFixture() -> OverviewModel {
    let counts = [2, 4, 3, 2, 4, 1, 4, 3, 2, 3, 2, 2]
    let stageNames = ["Développement", "Documentation", "Communication", "Recherche", "Perso", "Lecture", "Terminal", "Work", "Conception", "Notes", "Projet", "Administration"]
    let names = ["LG HDR 4K", "Écran intégré", "Dell 27 pouces"]
    let apps = ["T3 Code", "iTerm2", "Firefox", "Calendrier", "Notes", "Outlook", "Safari", "iTerm2", "iTerm2", "Firefox", "KeePassXC"]
    var entries: [WindowSwitcherEntry] = []
    for (stage, count) in counts.enumerated() {
        for _ in 0..<count {
            let index = entries.count
            let scope = StageScope(displayID: DisplayID(rawValue: String(stage / 4)), desktopID: DesktopID(rawValue: (stage / 2) % 2 + 1), stageID: StageID(rawValue: String(format: "%02d", stage)))
            let window = WindowSnapshot(id: WindowID(rawValue: UInt32(index + 1)), pid: Int32(index % apps.count + 1), appName: apps[index % apps.count], bundleID: "fixture.reference", title: "Activité \(index + 1)", frame: Rect(x: 0, y: 0, width: 480, height: 300), isOnScreen: true, isTileCandidate: true)
            entries.append(WindowSwitcherEntry(window: window, scope: scope, displayName: names[stage / 4], stageName: stageNames[stage]))
        }
    }
    let displays = names.enumerated().map { index, name in
        DisplaySnapshot(id: DisplayID(rawValue: String(index)), index: index, name: name, frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: Rect(x: 0, y: 0, width: 1440, height: 900), isMain: index == 0)
    }
    return OverviewModel(entries: entries, displays: displays, state: PersistentStageState())
}

private func overviewScreenCaseFixture() -> OverviewModel {
    func window(_ id: UInt32, _ width: Double, _ height: Double) -> WindowSnapshot {
        WindowSnapshot(id: WindowID(rawValue: id), pid: 1, appName: "App", bundleID: "fixture", title: "F\(id)",
                       frame: Rect(x: 0, y: 0, width: width, height: height), isOnScreen: true, isTileCandidate: true)
    }
    let a = DisplayID(rawValue: "A"), b = DisplayID(rawValue: "B")
    var entries = (1...3).map { WindowSwitcherEntry(window: window($0, 700, 1000), scope: StageScope(displayID: a, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "perso"))) }
    entries.append(WindowSwitcherEntry(window: window(4, 1600, 900), scope: StageScope(displayID: b, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "perso"))))
    for i in 0..<6 {
        entries.append(WindowSwitcherEntry(window: window(UInt32(5 + i), 1600, 1000), scope: StageScope(displayID: b, desktopID: DesktopID(rawValue: 2), stageID: StageID(rawValue: "s\(i)"))))
    }
    let displays = [a, b].enumerated().map { i, id in
        DisplaySnapshot(id: id, index: i, name: id.rawValue, frame: Rect(x: 0, y: 0, width: 1728, height: 1117), visibleFrame: Rect(x: 0, y: 0, width: 1728, height: 1080), isMain: i == 0)
    }
    let state = PersistentStageState(scopes: [PersistentStageScope(displayID: b, stages: [
        PersistentStage(id: StageID(rawValue: "perso"), name: "Perso"), PersistentStage(id: StageID(rawValue: "com"), name: "Com"),
        PersistentStage(id: StageID(rawValue: "work"), name: "Work")])])
    return OverviewModel(entries: entries, displays: displays, state: state)
}

@Suite("Spec061 Géométrie et persistance")
struct Spec061OverviewGeometryTests {
    @Test(arguments: [11, 32, 64], ["archipelago", "bays"])
    func allWindowsAndGroupsRemainAccessible(count: Int, presentation: String) {
        let model = overviewFixture(count)
        #expect(model.entries.count == count)
        #expect(model.displays.count == 2)
        #expect(model.displays.flatMap(\.desktops).count == 6)
        for magnification in [100.0, 150.0, 250.0] {
            for enabled in [true, false] {
                for size in [CGSize(width: 1000, height: 650), CGSize(width: 1850, height: 980), CGSize(width: 3750, height: 2000)] {
                    let config = OverviewConfig(presentation: presentation, loupe: enabled, magnification: magnification)
                    let plan = OverviewLayout.make(model: model, viewport: size, config: config)
                    #expect(plan.cards.count == count)
                    #expect(Set(plan.cards.map { $0.entry.id }).count == count)
                    let bounds = CGRect(origin: .zero, size: plan.size).insetBy(dx: -0.01, dy: -0.01)
                    for card in plan.cards {
                        // Une seule page : la composition garde la taille de l’écran et les cartes restent visibles.
                        #expect(plan.size == size)
                        #expect(card.frame.width > 0 && card.frame.height >= 20, "viewport=\(size) loupe=\(enabled) zoom=\(magnification) card=\(card.frame)")
                        #expect(bounds.contains(card.frame))
                    }
                    for (i, card) in plan.cards.enumerated() {
                        #expect(plan.cards.dropFirst(i + 1).allSatisfy { !card.frame.intersects($0.frame) })
                    }
                    for (i, region) in plan.desktops.enumerated() {
                        #expect(plan.desktops.dropFirst(i + 1).allSatisfy { !region.frame.intersects($0.frame) })
                    }
                }
            }
        }
    }

    @Test func namedEmptyStagesArePreservedWithoutInventingDesktops() {
        let display = DisplaySnapshot(id: DisplayID(rawValue: "A"), index: 0, name: "Mac", frame: Rect(x: 0, y: 0, width: 1000, height: 700), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 700), isMain: true)
        let state = PersistentStageState(scopes: [
            PersistentStageScope(displayID: display.id, stages: [PersistentStage(id: StageID(rawValue: "dev"), name: "Développement")]),
            PersistentStageScope(displayID: display.id, desktopID: DesktopID(rawValue: 2), stages: [PersistentStage(id: StageID(rawValue: "work"), name: "Work")])])
        let model = OverviewModel(entries: [], displays: [display], state: state)
        #expect(model.displays.first?.desktops.first?.stages.first?.name == "Développement")
        #expect(model.entries.isEmpty)
        #expect(model.displays.first?.desktops.count == 1)
    }

    @Test func indexedProjectionKeepsStageOrderAndNamedEmptyDesktop() {
        let source = overviewFixture(3)
        let display = DisplaySnapshot(id: DisplayID(rawValue: "A"), index: 0, name: "Mac", frame: Rect(x: 0, y: 0, width: 1000, height: 700), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 700), isMain: true)
        let scope = PersistentStageScope(displayID: display.id, stages: [
            PersistentStage(id: StageID(rawValue: "second"), name: "Deuxième"),
            PersistentStage(id: StageID(rawValue: "first"), name: "Premier")])
        let state = PersistentStageState(scopes: [scope], desktopLabels: [PersistentDesktopLabel(displayID: display.id, desktopID: DesktopID(rawValue: 2), label: "Réserve")])
        let entries = source.entries.enumerated().map { i, e in
            WindowSwitcherEntry(window: e.window, scope: StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: i == 1 ? "second" : "first")))
        }
        let model = OverviewModel(entries: entries, displays: [display], state: state)
        #expect(model.displays[0].desktops.map(\.id.desktopID.rawValue) == [1, 2])
        #expect(model.displays[0].desktops[0].stages.map(\.name) == ["Deuxième", "Premier"])
        #expect(model.displays[0].desktops[0].entries.map(\.id) == [entries[1].id, entries[0].id, entries[2].id])
        #expect(model.displays[0].desktops[1].name == "Bureau 2 · Réserve")
    }

    @Test func approvedReferenceKeepsItsGeometry() throws {
        let plan = OverviewLayout.make(model: overviewReferenceFixture(), viewport: CGSize(width: 1440, height: 773), config: OverviewConfig(loupe: false))
        #expect(plan.size.height == 773)
        #expect(plan.cards.count == 32)
        let first = try #require(plan.desktops.first?.frame)
        #expect(abs(first.minX - 28) < 0.1)
        // Maquette : bureau à 33 points sous le titre d’écran ; centrage vertical (SPEC-071) du reste.
        let top = try #require(plan.displays.map(\.frame.minY).min())
        #expect(abs(first.minY - top - 33) < 0.1)
        #expect(abs(top - (773 - (plan.desktops.map(\.frame.maxY).max() ?? 0))) < 0.5)
        // Largeur des écrans selon leur besoin : les trois colonnes remplissent la largeur utile.
        #expect(abs((plan.displays.last?.frame.maxX ?? 0) - (1440 - 28)) < 0.5)
        // Même taille de carte partout ; la hauteur d’un bureau suit sa grille.
        #expect(Set(plan.cards.map { Int($0.frame.width.rounded()) }).count == 1)
    }

    @Test func singleWindowStaysCompact() {
        for presentation in ["archipelago", "bays"] {
            let plan = OverviewLayout.make(model: overviewFixture(1), viewport: CGSize(width: 1800, height: 1800),
                config: OverviewConfig(presentation: presentation, loupe: false))
            let card = plan.cards[0]
            #expect(card.frame.height < 1800 * 0.8)
            #expect(abs(card.frame.width / (card.frame.height - OverviewLayout.caption * plan.scale) - OverviewLayout.cardRatio) < 0.01)
        }
    }

    /// Cas réel du 24 octobre : trois fenêtres portrait sur l’écran intégré, sept sur l’écran externe.
    @Test func portraitWindowsShareRowsAndEverythingFits() throws {
        let model = overviewScreenCaseFixture()
        for presentation in ["archipelago", "bays"] {
            let size = CGSize(width: 1728, height: 1077)
            let plan = OverviewLayout.make(model: model, viewport: size, config: OverviewConfig(presentation: presentation, loupe: false))
            #expect(plan.size.height <= size.height, "\(presentation)")
            #expect(plan.cards.count == 10)
            for card in plan.cards {
                // Format unique pour tous les aperçus, quelle que soit la forme de la fenêtre.
                let ratio = card.frame.width / (card.frame.height - OverviewLayout.caption * plan.scale)
                #expect(abs(ratio - OverviewLayout.cardRatio) < 0.01)
            }
        }
    }

    @Test func elevenWindowsFitWithoutTallEmptyColumns() {
        let model = overviewFixture(11)
        let size = CGSize(width: 1200, height: 800)
        for presentation in ["archipelago", "bays"] {
            let plan = OverviewLayout.make(model: model, viewport: size,
                config: OverviewConfig(presentation: presentation))
            #expect(plan.size.height <= size.height)
            #expect(plan.cards.count == 11)
        }
    }

    @Test func loupeEnlargesWindowInsideItsStage() throws {
        let model = overviewFixture(32)
        let size = CGSize(width: 1440, height: 900)
        for presentation in ["archipelago", "bays"] {
            let config = OverviewConfig(presentation: presentation, magnification: 200)
            let baseline = OverviewLayout.make(model: model, viewport: size, config: OverviewConfig(presentation: presentation, loupe: false))
            let target = try #require(baseline.cards.first)
            let desktop = try #require(model.displays.flatMap(\.desktops).first { $0.entries.contains { $0.id == target.entry.id } })
            let plan = OverviewLayout.make(model: model, viewport: size, config: config, window: target.entry.id)
            let enlarged = try #require(plan.cards.first { $0.entry.id == target.entry.id })
            #expect(enlarged.frame.width * enlarged.frame.height > target.frame.width * target.frame.height)
            #expect(Set(plan.cards.map(\.entry.id)) == Set(baseline.cards.map(\.entry.id)))
        }
    }

    @Test func configRoundTripPreservesExistingText() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-061-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("roadies.toml")
        try "# conserver\n[focus]\nfocus_follows_mouse = false\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(try RoadieConfigLoader.load(from: url.path).overview == OverviewConfig())
        let settings = SettingsService(configPath: url.path, eventLog: EventLog(path: directory.appendingPathComponent("events").path), afterWrite: {})
        for (key, value) in [("presentation", "bays"), ("loupe", "false"), ("magnification", "200"), ("hotkey", "ctrl+alt+o"), ("background_blur", "35"), ("selection_color", "#FF8800"), ("selection_width", "4")] {
            if case .rejected(let reason) = settings.set("overview.\(key)", to: value) { Issue.record("\(reason)") }
        }
        let loaded = try RoadieConfigLoader.load(from: url.path)
        #expect(loaded.overview.presentation == "bays")
        #expect(!loaded.overview.loupe && loaded.overview.magnification == 200)
        #expect(loaded.overview.backgroundBlur == 35)
        #expect(loaded.overview.selectionColor == "#FF8800" && loaded.overview.selectionWidth == 4)
        #expect(!loaded.focus.focusFollowsMouse)
        #expect(try String(contentsOf: url, encoding: .utf8).contains("# conserver"))
        #expect(SettingsCatalog.find(id: "overview.presentation")?.choiceLabel("bays") == "Baies")
    }
}

@Suite("Spec061 Rendu natif", .serialized)
@MainActor
struct Spec061OverviewNativeTests {
    @Test func escapeClosesTheOverlayWithoutCreatingASpace() throws {
        let panel = OverviewPanel(events: EventLog(path: NSTemporaryDirectory() + "roadie-061-escape-events"))
        panel.setFrame(CGRect(x: -10000, y: -10000, width: 1440, height: 900), display: false)
        panel.orderFront(nil)
        var closed = false
        panel.onKey = { code, _ in
            if code == 53 { panel.dismiss { closed = true } }
        }
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        panel.sendEvent(event)
        #expect(closed)
        #expect(!panel.isVisible)
        #expect(!panel.styleMask.contains(.fullScreen))
        #expect(panel.level == .statusBar)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        panel.onKey = nil
    }

    @Test func nativeCanvasKeepsAllCardsAndDrawsBothLayouts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-061-native")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for presentation in ["archipelago", "bays"] {
            let canvas = OverviewCanvas(frame: CGRect(x: 0, y: 0, width: 1200, height: 800))
            canvas.model = overviewFixture(11)
            canvas.viewport = CGSize(width: 1200, height: 800)
            canvas.config = OverviewConfig(presentation: presentation)
            canvas.focusedDesktop = canvas.model.displays.first?.desktops.first?.id
            canvas.selectedID = canvas.model.entries.first?.id
            canvas.rebuild()
            #expect(canvas.plan.cards.count == 11)
            let bitmap = try #require(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
            canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: directory.appendingPathComponent("\(presentation).png"))
            #expect(!data.isEmpty)
        }
    }

    @Test func nativeMouseMovementChangesLoupeWithoutActivationOrOscillation() async throws {
        let canvas = OverviewCanvas(frame: CGRect(x: 0, y: 0, width: 1200, height: 800))
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 1200, height: 800), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        canvas.model = overviewFixture(11)
        canvas.viewport = CGSize(width: 1200, height: 800)
        canvas.focusedDesktop = canvas.model.displays.first?.desktops.first?.id
        canvas.rebuild()
        window.orderFront(nil)
        defer { canvas.cancelHover(); window.orderOut(nil) }
        var activations = 0
        canvas.onOpen = { _ in activations += 1 }
        let target = try #require(canvas.plan.desktops.last?.desktop.id)
        func moveToTarget() throws {
            let rect = try #require(canvas.plan.desktops.first { $0.desktop.id == target }?.frame)
            let location = canvas.convert(CGPoint(x: rect.midX, y: rect.minY + 12), to: nil)
            let event = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: location, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 0, pressure: 0))
            canvas.mouseMoved(with: event)
        }
        try moveToTarget()
        try await Task.sleep(for: .milliseconds(180))
        #expect(canvas.focusedDesktop == target)
        try await Task.sleep(for: .milliseconds(180))
        #expect(canvas.focusedDesktop == target)
        #expect(activations == 0)
        let first = try #require(canvas.model.entries.first?.id)
        canvas.select(first)
        try moveToTarget()
        try await Task.sleep(for: .milliseconds(180))
        #expect(canvas.focusedDesktop == target)
        #expect(activations == 0)
    }

    @Test func pointerMagnifiesTheActualWindowInBothPresentations() async throws {
        for presentation in ["archipelago", "bays"] {
            let canvas = OverviewCanvas(frame: CGRect(x: 0, y: 0, width: 1200, height: 800))
            let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 1200, height: 800), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = canvas
            canvas.model = overviewFixture(11); canvas.viewport = CGSize(width: 1200, height: 800)
            canvas.config = OverviewConfig(presentation: presentation)
            canvas.rebuild(); window.orderFront(nil)
            defer { canvas.cancelHover(); window.orderOut(nil) }
            let target = try #require(canvas.plan.cards.first)
            let location = canvas.convert(CGPoint(x: target.frame.midX, y: target.frame.midY), to: nil)
            let event = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: location, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 0, pressure: 0))
            var opened = 0; canvas.onOpen = { _ in opened += 1 }
            canvas.mouseMoved(with: event)
            try await Task.sleep(for: .milliseconds(180))
            #expect(canvas.magnifiedID == target.entry.id)
            let lens = try #require(canvas.magnifiedFrame)
            #expect(lens.width > target.frame.width)
            #expect(opened == 0)
            let bitmap = try #require(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
            canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("roadie-061-native/\(presentation)-loupe.png"))
        }
    }

    @Test func nativePanelRendersApprovedReference() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("roadie-061-native")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for presentation in ["archipelago", "bays"] {
            let panel = OverviewPanel(events: EventLog(path: directory.appendingPathComponent("events").path))
            panel.canvas.model = overviewReferenceFixture()
            panel.canvas.selectedID = WindowID(rawValue: 1)
            if let folder = ProcessInfo.processInfo.environment["ROADIE_OVERVIEW_REFERENCE_ASSETS"] {
                for i in 1...32 {
                    let url = URL(fileURLWithPath: folder).appendingPathComponent("w\((i - 1) % 11 + 1).svg")
                    panel.canvas.images[WindowID(rawValue: UInt32(i))] = NSImage(contentsOf: url)
                }
            }
            for i in 1...11 {
                panel.canvas.appIcons[Int32(i)] = NSImage(size: CGSize(width: 26, height: 26), flipped: false) { rect in
                    NSColor(calibratedHue: CGFloat(i) / 13, saturation: 0.55, brightness: 0.85, alpha: 1).setFill()
                    NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
                    (String(i) as NSString).draw(at: CGPoint(x: 5, y: 5), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white])
                    return true
                }
            }
            panel.config = OverviewConfig(presentation: presentation, loupe: false)
            panel.syncControls()
            panel.setFrame(CGRect(x: -10000, y: -10000, width: 1440, height: 900), display: false)
            panel.windowDidResize(Notification(name: NSWindow.didResizeNotification))
            let view = try #require(panel.contentView)
            panel.orderFront(nil)
            defer { panel.orderOut(nil) }
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: directory.appendingPathComponent("reference-\(presentation).png"))
            #expect(panel.canvas.plan.cards.count == 32)
        }
    }

    @Test func nativePanelRendersScreenCase() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("roadie-061-native")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for presentation in ["archipelago", "bays"] {
            let panel = OverviewPanel(events: EventLog(path: directory.appendingPathComponent("events").path))
            panel.canvas.model = overviewScreenCaseFixture()
            panel.config = OverviewConfig(presentation: presentation, loupe: false)
            panel.syncControls()
            panel.setFrame(CGRect(x: -10000, y: -10000, width: 1728, height: 1117), display: false)
            panel.windowDidResize(Notification(name: NSWindow.didResizeNotification))
            let view = try #require(panel.contentView)
            panel.orderFront(nil)
            defer { panel.orderOut(nil) }
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: directory.appendingPathComponent("screen-case-\(presentation).png"))
            #expect(panel.canvas.plan.size.height <= panel.canvas.viewport.height)
        }
    }

    /// Comparaison avec la maquette injectée des mêmes données : ROADIE_OVERVIEW_REAL_JSON (export `roadie query`)
    /// et ROADIE_OVERVIEW_REFERENCE_ASSETS (images fictives de la maquette). Sans ces variables, rien n’est rendu.
    @Test func nativePanelRendersRealExport() throws {
        guard let path = ProcessInfo.processInfo.environment["ROADIE_OVERVIEW_REAL_JSON"],
              let assets = ProcessInfo.processInfo.environment["ROADIE_OVERVIEW_REFERENCE_ASSETS"] else { return }
        struct Export: Decodable {
            struct Screen: Decodable { let id: String; let name: String; let frame: Rect }
            struct Desk: Decodable { let id: String; let name: String; let screen: String; let active: Bool }
            struct StageItem: Decodable { let id: String; let name: String; let desk: String; let count: Int }
            struct Win: Decodable { let id: String; let app: String; let title: String; let frame: Rect; let stage: String; let desktop: String; let screen: String }
            let screens: [Screen]; let desks: [Desk]; let stages: [StageItem]; let windows: [Win]
        }
        let export = try JSONDecoder().decode(Export.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        func desktopID(_ desk: String) -> DesktopID { DesktopID(rawValue: Int(desk.split(separator: "/").last ?? "1") ?? 1) }
        let displays = export.screens.enumerated().map { index, screen in
            DisplaySnapshot(id: DisplayID(rawValue: screen.id), index: index, name: screen.name, frame: screen.frame, visibleFrame: screen.frame, isMain: index == 0)
        }
        var scopes: [PersistentStageScope] = []
        for desk in export.desks {
            let stages = export.stages.filter { $0.desk == desk.id }.map { PersistentStage(id: StageID(rawValue: String($0.id.split(separator: "/").last ?? "")), name: $0.name) }
            scopes.append(PersistentStageScope(displayID: DisplayID(rawValue: desk.screen), desktopID: desktopID(desk.id), stages: stages))
        }
        let selections = export.desks.filter(\.active).map { PersistentDesktopSelection(displayID: DisplayID(rawValue: $0.screen), currentDesktopID: desktopID($0.id)) }
        let state = PersistentStageState(scopes: scopes, desktopSelections: selections)
        let kinds = ["Firefox": 3, "Thunderbird": 6, "iTerm2": 2, "Microsoft Word": 5, "X": 7, "T3 Code (Beta)": 1, "KeePassXC": 11]
        var entries: [WindowSwitcherEntry] = []
        var images: [WindowID: NSImage] = [:]
        for (index, win) in export.windows.enumerated() {
            let id = WindowID(rawValue: UInt32(win.id) ?? UInt32(index + 1))
            let window = WindowSnapshot(id: id, pid: Int32(kinds[win.app] ?? 7), appName: win.app, bundleID: "export", title: win.title, frame: win.frame, isOnScreen: true, isTileCandidate: true)
            let scope = StageScope(displayID: DisplayID(rawValue: win.screen), desktopID: desktopID(win.desktop), stageID: StageID(rawValue: String(win.stage.split(separator: "/").last ?? "")))
            entries.append(WindowSwitcherEntry(window: window, scope: scope))
            images[id] = NSImage(contentsOf: URL(fileURLWithPath: assets).appendingPathComponent("w\(kinds[win.app] ?? 7).svg"))
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("roadie-061-native")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for presentation in ["archipelago", "bays"] {
            for loupe in [false, true] {
                let panel = OverviewPanel(events: EventLog(path: directory.appendingPathComponent("events").path))
                panel.canvas.model = OverviewModel(entries: entries, displays: displays, state: state)
                panel.canvas.images = images
                panel.canvas.selectedID = entries.first?.id
                if loupe { panel.canvas.magnifiedID = entries.first?.id }
                panel.config = OverviewConfig(presentation: presentation, loupe: loupe, magnification: 160)
                panel.syncControls()
                panel.setFrame(CGRect(x: -10000, y: -10000, width: 1440, height: 900), display: false)
                panel.windowDidResize(Notification(name: NSWindow.didResizeNotification))
                let view = try #require(panel.contentView)
                panel.orderFront(nil)
                defer { panel.orderOut(nil) }
                let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let data = try #require(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: directory.appendingPathComponent("real-\(presentation)\(loupe ? "-loupe" : "").png"))
                #expect(panel.canvas.plan.cards.count == entries.count)
            }
        }
    }

    @Test func receiverAvailabilityFollowsLifecycle() {
        let controller = OverviewController(events: EventLog(path: NSTemporaryDirectory() + "roadie-061-lifecycle-events"))
        #expect(!OverviewController.receiverAvailable)
        let unavailable = CLICommandRouter().run(["overview", "show"])
        #expect(unavailable.exitCode == 1)
        #expect(unavailable.stderr.contains("receiver unavailable"))
        controller.start()
        #expect(OverviewController.receiverAvailable)
        controller.stop()
        #expect(!OverviewController.receiverAvailable)
    }

    @Test func shortcutSignaturesDoNotConsumeEachOther() {
        var calls = 0
        let overview = TargetSearchHotkey(signature: 0x5244_4F56) { calls += 1 }
        #expect(overview.handle(EventHotKeyID(signature: 0x5244_5352, id: 1)) != 0)
        #expect(overview.handle(EventHotKeyID(signature: 0x5244_5357, id: 1000)) != 0)
        #expect(calls == 0)
        #expect(overview.handle(EventHotKeyID(signature: 0x5244_4F56, id: 1)) == 0)
        #expect(calls == 1)
    }
}
