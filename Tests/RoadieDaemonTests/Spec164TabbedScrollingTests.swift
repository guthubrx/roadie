import AppKit
import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages
import RoadieTiler
import Testing
@testable import RoadieDaemon

/// Spec 164 — Layouts avancés : Onglets (`tabbed`) & Ruban défilant (`scrolling`).
@Suite(.serialized)
struct Spec164TabbedScrollingTests {
    private final class SpyWriter: WindowFrameWriting, @unchecked Sendable {
        private let lock = NSLock()
        var writtenFrames: [WindowID: CGRect] = [:]
        var focusedWindowIDs: [WindowID] = []

        func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
            lock.withLock { writtenFrames[window.id] = frame }
            return frame
        }

        func focus(_ window: WindowSnapshot) -> Bool {
            lock.withLock { focusedWindowIDs.append(window.id) }
            return true
        }

        func lastFocused() -> WindowID? {
            lock.withLock { focusedWindowIDs.last }
        }

        func lastFrame(for id: WindowID) -> CGRect? {
            lock.withLock { writtenFrames[id] }
        }
    }

    private final class MutableProvider: SystemSnapshotProviding, @unchecked Sendable {
        private let lock = NSLock()
        private var displaysStorage: [DisplaySnapshot]
        private var windowsStorage: [WindowSnapshot]
        private var focusedStorage: WindowID?

        init(displays: [DisplaySnapshot], windows: [WindowSnapshot], focused: WindowID?) {
            self.displaysStorage = displays
            self.windowsStorage = windows
            self.focusedStorage = focused
        }

        func setFocused(_ id: WindowID?) {
            lock.withLock { focusedStorage = id }
        }

        func permissions(prompt: Bool) -> PermissionSnapshot {
            PermissionSnapshot(accessibilityTrusted: true, screenRecordingGranted: true)
        }

        func displays() -> [DisplaySnapshot] { lock.withLock { displaysStorage } }
        func windows() -> [WindowSnapshot] { lock.withLock { windowsStorage } }
        func focusedWindowID() -> WindowID? { lock.withLock { focusedStorage } }
    }

    @MainActor
    private final class SpyTabBarRenderer: StageTabBarRendering {
        var renderedTargets: [[StageTabBarTarget]] = []
        var hideAllCalls = 0
        var lastSelectHandler: (@MainActor (WindowID) -> Void)?

        func render(_ targets: [StageTabBarTarget], onSelect: @escaping @MainActor (WindowID) -> Void) {
            renderedTargets.append(targets)
            lastSelectHandler = onSelect
        }

        func hideAll() {
            hideAllCalls += 1
        }
    }

    private func tempDir(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-spec164-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func display(_ id: String = "d1") -> DisplaySnapshot {
        DisplaySnapshot(
            id: DisplayID(rawValue: id),
            index: 1,
            name: "Display 1",
            frame: Rect(x: 0, y: 0, width: 1600, height: 900),
            visibleFrame: Rect(x: 0, y: 30, width: 1600, height: 870),
            isMain: true
        )
    }

    private func window(_ id: UInt32, app: String = "App", title: String = "Win", x: Double = 20) -> WindowSnapshot {
        WindowSnapshot(
            id: WindowID(rawValue: id),
            pid: 500,
            appName: app,
            bundleID: "com.example.\(app.lowercased())",
            title: title,
            frame: Rect(x: x, y: 60, width: 600, height: 600),
            isOnScreen: true,
            isTileCandidate: true,
            furniture: nil
        )
    }

    // MARK: - Config, Modes & Catalogue

    @Test func spec164ModesAliasesConfigValidationAndCatalog() throws {
        // Alias de modes
        for alias in ["tabbed", "tabs", "onglets"] {
            #expect(WindowManagementMode(roadieValue: alias) == .tabbed)
        }
        for alias in ["scrolling", "scroll", "ribbon", "niri", "ruban"] {
            #expect(WindowManagementMode(roadieValue: alias) == .scrolling)
        }
        #expect(WindowManagementMode.tabbed.isTiled)
        #expect(WindowManagementMode.scrolling.isTiled)
        #expect(WindowManagementMode.tabbed.allowsWindowOverlapOrOverflow)
        #expect(WindowManagementMode.scrolling.allowsWindowOverlapOrOverflow)
        #expect(!WindowManagementMode.bsp.allowsWindowOverlapOrOverflow)

        // Défauts & bornes
        let defaults = TilingConfig()
        #expect(defaults.tabbedBarHeight == 28)
        #expect(abs(defaults.scrollingColumnWidth - 0.65) < 0.001)
        #expect(TilingConfig(tabbedBarHeight: 5).tabbedBarHeight == 20)
        #expect(TilingConfig(tabbedBarHeight: 120).tabbedBarHeight == 44)
        #expect(abs(TilingConfig(scrollingColumnWidth: 0.05).scrollingColumnWidth - 0.25) < 0.001)
        #expect(abs(TilingConfig(scrollingColumnWidth: 2.0).scrollingColumnWidth - 1.0) < 0.001)

        // Validation TOML
        let dir = try tempDir("config")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("roadies.toml")
        try """
        [tiling]
        default_strategy = "ribbon"
        tabbed_bar_height = 34
        scrolling_column_width = 0.72
        """.write(to: file, atomically: true, encoding: .utf8)

        let report = RoadieConfigLoader.validate(path: file.path)
        #expect(!report.hasErrors)
        #expect(!report.items.contains { $0.level == .warning })

        let loaded = try RoadieConfigLoader.load(from: file.path)
        #expect(loaded.tiling.defaultStrategy == .scrolling)
        #expect(loaded.tiling.tabbedBarHeight == 34)
        #expect(abs(loaded.tiling.scrollingColumnWidth - 0.72) < 0.001)

        #expect(SettingsCatalog.find(id: "tiling.tabbed_bar_height") != nil)
        #expect(SettingsCatalog.find(id: "tiling.scrolling_column_width") != nil)
        #expect(LauncherSystemCommand.all().contains { $0.id == "roadie-mode-tabbed" })
        #expect(LauncherSystemCommand.all().contains { $0.id == "roadie-mode-scrolling" })
    }

    // MARK: - Géométrie TabbedLayoutStrategy

    @Test func tabbedLayoutFullFrameForSingleWindowAndStackedBelowBarForMultiple() throws {
        let scope = StageScope(displayID: DisplayID(rawValue: "d1"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let container = CGRect(x: 0, y: 30, width: 1600, height: 870)
        let gaps = Insets(top: 10, right: 10, bottom: 10, left: 10)
        let w1 = WindowID(rawValue: 1)
        let w2 = WindowID(rawValue: 2)
        let w3 = WindowID(rawValue: 3)

        // 1 fenêtre : aucune barre, tout le conteneur inset
        #expect(TabbedLayoutStrategy.tabBarFrame(in: container, outerGaps: gaps, barHeight: 28, windowCount: 1) == nil)
        let soloPlan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .tabbed,
            container: container,
            windowIDs: [w1],
            outerGaps: gaps,
            innerGap: 4,
            tabbedBarHeight: 28
        ))
        #expect(soloPlan.placements[w1] == CGRect(x: 10, y: 40, width: 1580, height: 850))

        // 3 fenêtres : barre de 30 pt en haut, toutes les fenêtres empilées dessous sans chevaucher la barre
        let bar = try #require(TabbedLayoutStrategy.tabBarFrame(in: container, outerGaps: gaps, barHeight: 30, windowCount: 3))
        #expect(bar == CGRect(x: 10, y: 40, width: 1580, height: 30))

        let multiPlan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .tabbed,
            container: container,
            windowIDs: [w1, w2, w3],
            outerGaps: gaps,
            innerGap: 4,
            tabbedBarHeight: 30
        ))
        let f1 = try #require(multiPlan.placements[w1])
        let f2 = try #require(multiPlan.placements[w2])
        let f3 = try #require(multiPlan.placements[w3])
        #expect(f1 == f2)
        #expect(f2 == f3)
        #expect(f1.minY == bar.maxY + 4)
        #expect(f1.maxY == 890)
        #expect(!bar.intersects(f1))
    }

    // MARK: - Géométrie ScrollingLayoutStrategy

    @Test func scrollingLayoutCentersFocusedColumnAndAvoidsHiddenCoordinates() throws {
        let d = display()
        let scope = StageScope(displayID: d.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let container = d.visibleFrame.cgRect
        let gaps = Insets(top: 10, right: 10, bottom: 10, left: 10)
        let w1 = WindowID(rawValue: 1)
        let w2 = WindowID(rawValue: 2)
        let w3 = WindowID(rawValue: 3)
        let w4 = WindowID(rawValue: 4)

        // Ruban tenant dans l'écran (2 fenêtres × 0.4 = 0.8 <= 1.0) : centré sans clamp
        let fitsPlan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .scrolling,
            container: container,
            windowIDs: [w1, w2],
            outerGaps: gaps,
            innerGap: 10,
            focusedWindowID: w1,
            scrollingColumnWidth: 0.4
        ))
        let p1 = try #require(fitsPlan.placements[w1])
        let p2 = try #require(fitsPlan.placements[w2])
        #expect(p1.width == floor(1580 * 0.4))
        #expect(p2.minX == p1.maxX + 10)
        #expect(p1.minX >= 10 && p2.maxX <= 1590)

        // Ruban plus large que l'écran (4 fenêtres × 0.65) : focus sur w2 centre w2 dans l'écran
        let midPlan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .scrolling,
            container: container,
            windowIDs: [w1, w2, w3, w4],
            outerGaps: gaps,
            innerGap: 8,
            focusedWindowID: w2,
            scrollingColumnWidth: 0.65
        ))
        let m1 = try #require(midPlan.placements[w1])
        let m2 = try #require(midPlan.placements[w2])
        let m3 = try #require(midPlan.placements[w3])
        let m4 = try #require(midPlan.placements[w4])
        #expect(abs(m2.midX - 800) <= 2)
        #expect(m1.minX < m2.minX)
        #expect(m3.minX > m2.minX)
        // Aucune colonne ne déclenche `HiddenWindowPlacement` (garde 24 pt en bord d'écran)
        for rect in [m1, m2, m3, m4] {
            #expect(!HiddenWindowPlacement.isHiddenOrLegacyOffscreen(rect, in: [d]))
        }

        // Focus sur la dernière colonne (w4) : collée à droite sans vide inutile
        let endPlan = LayoutPlanner.plan(LayoutRequest(
            scope: scope,
            mode: .scrolling,
            container: container,
            windowIDs: [w1, w2, w3, w4],
            outerGaps: gaps,
            innerGap: 8,
            focusedWindowID: w4,
            scrollingColumnWidth: 0.65
        ))
        let e4 = try #require(endPlan.placements[w4])
        #expect(e4.maxX == 1590)
    }

    // MARK: - Navigation clavier (`focus` / `move`) & CLI `mode`

    @Test func tabbedAndScrollingNavigationReordersAndFocusesCorrectly() throws {
        let dir = try tempDir("nav")
        defer { try? FileManager.default.removeItem(at: dir) }
        let stageStore = StageStore(path: dir.appendingPathComponent("stages.json").path)
        let eventLog = EventLog(path: dir.appendingPathComponent("events.jsonl").path)
        let w1 = window(11, app: "Notes", title: "A")
        let w2 = window(12, app: "Safari", title: "B")
        let w3 = window(13, app: "Terminal", title: "C")
        let provider = MutableProvider(displays: [display()], windows: [w1, w2, w3], focused: w1.id)
        let writer = SpyWriter()
        let config = RoadieConfig(tiling: TilingConfig(defaultStrategy: .tabbed, gapsOuter: 8, gapsInner: 4))
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: config,
            stageStore: stageStore,
            events: eventLog
        )
        _ = service.snapshot()

        // Passer en mode tabbed via StageCommandService
        let stageCmd = StageCommandService(service: service, store: stageStore, events: eventLog)
        let setTabbed = stageCmd.setMode(.tabbed)
        #expect(setTabbed.changed)

        let winCmd = WindowCommandService(service: service, stageStore: stageStore, events: eventLog)
        // focus right en tabbed : w1 -> w2
        let focusNext = winCmd.focus(.right)
        #expect(focusNext.changed)
        #expect(writer.lastFocused() == w2.id)

        // focus left depuis w1 boucle vers w3 !
        provider.setFocused(w1.id)
        let focusWrap = winCmd.focus(.left)
        #expect(focusWrap.changed)
        #expect(writer.lastFocused() == w3.id)

        // move right échange w1 et w2 dans stages.json
        provider.setFocused(w1.id)
        let moved = winCmd.move(.right)
        #expect(moved.changed)
        let afterMoveOrder = stageStore.state().scopes.first?.stages.first?.members.map(\.windowID)
        #expect(afterMoveOrder == [w2.id, w1.id, w3.id])

        // Basculer en mode scrolling (ordre actuel : [w2, w1, w3]) et naviguer vers la fenêtre DU MILIEU (w1)
        // depuis w2 : le ruban doit recentrer sur w1 (et non retomber sur le dernier membre w3).
        let setScrolling = stageCmd.setMode(.scrolling)
        #expect(setScrolling.changed)
        provider.setFocused(w2.id)
        let scrollToMiddle = winCmd.focus(.right)
        #expect(scrollToMiddle.changed)
        #expect(writer.lastFocused() == w1.id)
        let middleW1Frame = try #require(writer.lastFrame(for: w1.id))
        let middleW2Frame = try #require(writer.lastFrame(for: w2.id))
        let middleW3Frame = try #require(writer.lastFrame(for: w3.id))
        // w1 est centrée dans 1600 px (avec outerGaps 8 -> [8..1592], centre = 800)
        #expect(abs(middleW1Frame.midX - 800) <= 2)
        #expect(middleW2Frame.minX < middleW1Frame.minX)
        #expect(middleW1Frame.minX < middleW3Frame.minX)

        // focus(windowID:) sur la dernière colonne (w3) recentre ensuite sur w3 collée à droite
        let focusByID = winCmd.focus(windowID: w3.id)
        #expect(focusByID.changed)
        #expect(writer.lastFocused() == w3.id)
        let w3Frame = try #require(writer.lastFrame(for: w3.id))
        #expect(w3Frame.maxX >= 1580)

        // WidthAdjustmentService ne doit pas désorganiser le ruban scrolling (piloté par tiling.scrolling_column_width)
        let widthResult = WidthAdjustmentService(service: service, config: config, events: eventLog)
            .apply(WidthAdjustmentIntent(scope: .activeWindow, mode: .explicitRatio, targetRatio: 0.5))
        #expect(!widthResult.changed)
    }

    @Test func scrollingSixWindowsStaggersOverflowColumnsWithoutOverlapOrHiddenCollision() throws {
        let testScope = StageScope(displayID: DisplayID(rawValue: "d1"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let disp = DisplaySnapshot(
            id: DisplayID(rawValue: "d1"),
            index: 1,
            name: "Display 1",
            frame: Rect(x: 0, y: 0, width: 1580, height: 900),
            visibleFrame: Rect(x: 0, y: 0, width: 1580, height: 900),
            isMain: true
        )
        let container = disp.visibleFrame.cgRect
        let ids = (1...6).map { WindowID(rawValue: UInt32($0)) }
        let plan = LayoutPlanner.plan(LayoutRequest(
            scope: testScope,
            mode: .scrolling,
            container: container,
            windowIDs: ids,
            outerGaps: .zero,
            innerGap: 8,
            focusedWindowID: ids[0],
            scrollingColumnWidth: 0.65
        ))
        let xs = try ids.map { try #require(plan.placements[$0]).minX }
        // Strictement croissantes : zéro superposition exacte de colonnes hors écran
        for i in 0..<(xs.count - 1) {
            #expect(xs[i] < xs[i + 1])
        }
        // Aucune colonne ne satisfait HiddenWindowPlacement.isHiddenOrLegacyOffscreen
        for id in ids {
            let rect = try #require(plan.placements[id])
            #expect(!HiddenWindowPlacement.isHiddenOrLegacyOffscreen(rect, in: [disp]))
        }

        // Petit conteneur (32 pt) : ne doit jamais déclencher de faux masquage
        let tinyDisp = DisplaySnapshot(
            id: DisplayID(rawValue: "tiny"),
            index: 1,
            name: "Tiny",
            frame: Rect(x: 0, y: 0, width: 32, height: 32),
            visibleFrame: Rect(x: 0, y: 0, width: 32, height: 32),
            isMain: true
        )
        let tinyPlan = LayoutPlanner.plan(LayoutRequest(
            scope: testScope,
            mode: .scrolling,
            container: tinyDisp.visibleFrame.cgRect,
            windowIDs: [ids[0], ids[1], ids[2]],
            outerGaps: .zero,
            innerGap: 4,
            focusedWindowID: ids[0],
            scrollingColumnWidth: 0.65
        ))
        for id in [ids[0], ids[1], ids[2]] {
            let rect = try #require(tinyPlan.placements[id])
            #expect(!HiddenWindowPlacement.isHiddenOrLegacyOffscreen(rect, in: [tinyDisp]))
        }

        // Cadres non finis (NaN / Inf) rejetés proprement par les deux stratégies
        let nanContainer = CGRect(x: CGFloat.nan, y: 0, width: 1000, height: 800)
        let infContainer = CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 800)
        #expect(TabbedLayoutStrategy().plan(LayoutRequest(scope: testScope, mode: .tabbed, container: nanContainer, windowIDs: [ids[0], ids[1]])).placements.isEmpty)
        #expect(TabbedLayoutStrategy().plan(LayoutRequest(scope: testScope, mode: .tabbed, container: infContainer, windowIDs: [ids[0], ids[1]])).placements.isEmpty)
        #expect(ScrollingLayoutStrategy().plan(LayoutRequest(scope: testScope, mode: .scrolling, container: nanContainer, windowIDs: [ids[0], ids[1]])).placements.isEmpty)
        #expect(ScrollingLayoutStrategy().plan(LayoutRequest(scope: testScope, mode: .scrolling, container: infContainer, windowIDs: [ids[0], ids[1]])).placements.isEmpty)
    }

    // MARK: - StageTabBarController

    @Test @MainActor func tabBarControllerRendersOnlyForTabbedStagesWithAtLeastTwoWindows() async throws {
        let dir = try tempDir("tabbar")
        defer { try? FileManager.default.removeItem(at: dir) }
        let stageStore = StageStore(path: dir.appendingPathComponent("stages.json").path)
        let eventLog = EventLog(path: dir.appendingPathComponent("events.jsonl").path)
        let w1 = window(21, app: "Notes", title: "Spec")
        let w2 = window(22, app: "Terminal", title: "Build")
        let provider = MutableProvider(displays: [display()], windows: [w1, w2], focused: w1.id)

        // 1. Mode BSP -> 0 barre d'onglets, hideAll() appelé
        let bspConfig = RoadieConfig(tiling: TilingConfig(defaultStrategy: .bsp))
        let bspService = SnapshotService(
            provider: provider,
            config: bspConfig,
            stageStore: stageStore,
            events: eventLog
        )
        _ = bspService.snapshot()

        let spy = SpyTabBarRenderer()
        let controller = StageTabBarController(
            snapshotService: bspService,
            configLoader: { bspConfig },
            renderer: spy
        )
        await controller.refresh()
        #expect(spy.hideAllCalls == 1)
        #expect(spy.renderedTargets.isEmpty)

        // 2. Passage en mode tabbed avec 2 fenêtres -> 1 cible avec 2 onglets et w1 focalisé
        let stageCmd = StageCommandService(service: bspService, store: stageStore, events: eventLog)
        _ = stageCmd.setMode(.tabbed)
        _ = bspService.snapshot()

        await controller.refresh()
        #expect(spy.renderedTargets.count == 1)
        let target = try #require(spy.renderedTargets.first?.first)
        #expect(target.tabs.count == 2)
        #expect(target.tabs[0].windowID == w1.id && target.tabs[0].isFocused)
        #expect(target.tabs[1].windowID == w2.id && !target.tabs[1].isFocused)
        #expect(target.tabs[0].displayLabel == "Notes — Spec")
    }
}
