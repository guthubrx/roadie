import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages
import RoadieTiler
import Testing
@testable import RoadieDaemon

private final class Placement037Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 10_000)
}

/// Une fenêtre CG apparaît avant que sa fenêtre AX soit accessible. Les échecs de
/// résolution ne créent aucune entrée au registre, comme dans l'écrivain réel.
private final class Placement037Writer: WindowFrameWriting, @unchecked Sendable {
    let provider: PowerUserProvider
    let base: PowerUserWriter
    let registry: WrittenFrameRegistry
    let clock: Placement037Clock
    var unavailable: Set<WindowID>
    var readSucceedsBeforeFailedLookup = false
    var attempts: [WindowID: Int] = [:]

    init(provider: PowerUserProvider, registry: WrittenFrameRegistry, clock: Placement037Clock, unavailable: Set<WindowID>) {
        self.provider = provider
        base = PowerUserWriter(provider: provider)
        self.registry = registry
        self.clock = clock
        self.unavailable = unavailable
    }

    func readFrame(of window: WindowSnapshot) -> CGRect? {
        unavailable.contains(window.id) && !readSucceedsBeforeFailedLookup
            ? nil : provider.snapshots.first { $0.id == window.id }?.frame.cgRect
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? { base.setFrame(frame, of: window) }

    func setFrames(_ updates: [WindowFrameUpdate], generation: UInt64) -> [WindowID: CGRect?] {
        var result: [WindowID: CGRect?] = [:]
        for update in updates {
            guard !registry.isOverBudget(windowID: update.window.id.rawValue, generation: generation) else { continue }
            attempts[update.window.id, default: 0] += 1
            guard !unavailable.contains(update.window.id) else {
                result.updateValue(nil, forKey: update.window.id)
                continue
            }
            let actual = base.setFrame(update.frame, of: update.window)
            registry.record(windowID: update.window.id.rawValue, requested: update.frame, readBack: actual,
                            generation: generation, at: clock.now)
            result.updateValue(actual, forKey: update.window.id)
        }
        return result
    }
}

enum Placement037Scenario: Sendable, CaseIterable {
    case becomesReady, staysUnavailable, lookupFailsAfterReadinessCheck
}

@Suite
struct Spec037PlacementReadinessTests {
    @Test(arguments: Placement037Scenario.allCases, [false, true])
    func unavailableTerminalDoesNotReserveAHoleAndResumesWithoutActivation(scenario: Placement037Scenario, sameDisplay: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("placement037-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func path(_ name: String) -> String { directory.appendingPathComponent(name).path }
        let external = DisplaySnapshot(id: DisplayID(rawValue: "external034"), index: 2, name: "External",
            frame: Rect(x: -2000, y: 0, width: 2000, height: 1000),
            visibleFrame: Rect(x: -2000, y: 0, width: 2000, height: 1000), isMain: false)
        let builtin = DisplaySnapshot(id: DisplayID(rawValue: "internal034"), index: 1, name: "Built-in",
            frame: Rect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: Rect(x: 0, y: 0, width: 1512, height: 982), isMain: true)
        let t3 = powerWindow(75411, x: -2000, y: 0, width: 1000, height: 1000, app: "T3")
        let teams = powerWindow(140, x: -1000, y: 0, width: 1000, height: 1000, app: "Teams")
        let terminal = powerWindow(99751, x: sameDisplay ? -1750 : 150, y: 290, width: 570, height: 436, app: "iTerm2")
        let other = powerWindow(4, x: 300, y: 100, width: 600, height: 400)
        let scope = StageScope(displayID: external.id, desktopID: DesktopID(rawValue: 4), stageID: StageID(rawValue: "4"))
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5,
            first: .split(orientation: .vertical, ratio: 0.5, first: .leaf(t3.id), second: .leaf(terminal.id)), second: .leaf(teams.id))
        let provider = PowerUserProvider(displays: [builtin, external], windows: [t3, teams, terminal, other])
        let store = StageStore(path: path("stages.json"))
        store.save(PersistentStageState(scopes: [PersistentStageScope(
            displayID: external.id, desktopID: scope.desktopID, activeStageID: scope.stageID,
            stages: [PersistentStage(id: scope.stageID, mode: .spatialBsp, members: [t3, teams, terminal].map {
                PersistentStageMember(windowID: $0.id, bundleID: $0.bundleID, title: $0.title, frame: $0.frame)
            }, bspTree: tree)])],
            desktopSelections: [PersistentDesktopSelection(displayID: external.id, currentDesktopID: scope.desktopID)],
            activeDisplayID: external.id))
        // Ce scénario d'attente AX conserve volontairement les fenêtres sur leurs écrans initiaux.
        let config = RoadieConfig(tiling: TilingConfig(defaultStrategy: .spatialBsp, gapsOuter: 0, gapsInner: 0),
            windowPlacement: WindowPlacementConfig(newAppsTarget: "macos"))
        let clock = Placement037Clock()
        let registry = WrittenFrameRegistry()
        let writer = Placement037Writer(provider: provider, registry: registry, clock: clock, unavailable: [terminal.id])
        let events = EventLog(path: path("events.jsonl"))
        let service = SnapshotService(provider: provider, frameWriter: writer, config: config,
            intentStore: LayoutIntentStore(path: path("intents.json")), stageStore: store, events: events,
            clock: { clock.now }, frameRegistry: registry, treeScopeApplications: TreeScopeApplicationCenter())
        let maintainer = LayoutMaintainer(service: service, events: events, store: store,
            dragActivity: WindowDragActivity(path: path("drag")), commandActivity: LayoutCommandActivity(path: path("commands")),
            mouseButtonsPressed: { false }, writtenFrames: registry, generations: PlacementGeneration(),
            readFrame: { writer.readFrame(of: $0) }, configService: ConfigReloadService(activeConfig: config, eventLog: events),
            now: { clock.now })
        let priorFailures = scenario == .lookupFailsAfterReadinessCheck ? 2 : 0
        if priorFailures > 0 {
            // La résolution peut disparaître entre la lecture et l'écriture. Deux appels
            // échoués avant AX ne doivent pas bloquer la première écriture réelle.
            writer.readSucceedsBeforeFailedLookup = true
            for _ in 0..<priorFailures {
                _ = maintainer.tick(cause: "safety")
                clock.now += 0.15
            }
            #expect(writer.attempts[terminal.id] == priorFailures)
            writer.readSucceedsBeforeFailedLookup = false
        }
        let frameBeforeWaiting = try #require(provider.snapshots.first { $0.id == t3.id }).frame
        for delay in [0.0, 0.15] {
            clock.now += delay
            _ = maintainer.tick(cause: "safety")
            #expect(provider.snapshots.first { $0.id == t3.id }?.frame == frameBeforeWaiting)
            #expect(provider.snapshots.first { $0.id == terminal.id }?.frame == terminal.frame)
        }
        #expect((writer.attempts[other.id] ?? 0) > 0, "l'autre écran continue de placer ses fenêtres")
        #expect(writer.attempts[terminal.id, default: 0] == priorFailures)
        let becomesReady = scenario != .staysUnavailable
        if becomesReady { writer.unavailable.remove(terminal.id) }
        for _ in 0..<100 {
            clock.now += 2
            _ = maintainer.tick(cause: "safety")
        }
        if becomesReady {
            #expect(provider.snapshots.first { $0.id == terminal.id }?.frame == Rect(x: -1500, y: 0, width: 500, height: 1000))
            #expect(provider.snapshots.first { $0.id == t3.id }?.frame == Rect(x: -2000, y: 0, width: 500, height: 1000))
            #expect(writer.attempts[terminal.id] == priorFailures + 1)
            #expect((registry.entry(for: terminal.id.rawValue)?.writesInGeneration ?? 0) <= 2)
        } else {
            #expect(provider.snapshots.first { $0.id == t3.id }?.frame == t3.frame)
            #expect(writer.attempts[terminal.id, default: 0] == 0)
            provider.snapshots.removeAll { $0.id == terminal.id }
            clock.now += 2
            _ = maintainer.tick(cause: "safety")
            #expect(provider.snapshots.first { $0.id == t3.id }?.frame == t3.frame)
        }
        #expect(provider.snapshots.first { $0.id == teams.id }?.frame == teams.frame)
        let log = try String(contentsOfFile: path("events.jsonl"), encoding: .utf8)
        #expect(!log.contains("write_budget_exhausted"))
    }

    @Test
    func animatedPreAXFailureDoesNotBlockPlacementOnceWindowBecomesAXReady() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("placement037-anim-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func path(_ name: String) -> String { directory.appendingPathComponent(name).path }

        let display = powerDisplay()
        let t3 = powerWindow(184562, x: 0, y: 0, width: 500, height: 800, app: "T3")
        let terminal = powerWindow(306509, x: 150, y: 200, width: 570, height: 436, app: "iTerm2")
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(t3.id), second: .leaf(terminal.id))
        let provider = PowerUserProvider(displays: [display], windows: [t3, terminal])
        let store = StageStore(path: path("stages.json"))
        store.save(PersistentStageState(scopes: [PersistentStageScope(
            displayID: display.id, desktopID: scope.desktopID, activeStageID: scope.stageID,
            stages: [PersistentStage(id: scope.stageID, mode: .spatialBsp, members: [t3, terminal].map {
                PersistentStageMember(windowID: $0.id, bundleID: $0.bundleID, title: $0.title, frame: $0.frame)
            }, bspTree: tree)])],
            desktopSelections: [PersistentDesktopSelection(displayID: display.id, currentDesktopID: scope.desktopID)],
            activeDisplayID: display.id))
        let config = RoadieConfig(tiling: TilingConfig(defaultStrategy: .spatialBsp, gapsOuter: 0, gapsInner: 0))
        let clock = Placement037Clock()
        let registry = WrittenFrameRegistry()
        let generations = PlacementGeneration()
        let writer = Placement037Writer(provider: provider, registry: registry, clock: clock, unavailable: [terminal.id])
        let events = EventLog(path: path("events.jsonl"))
        let service = SnapshotService(provider: provider, frameWriter: writer, config: config,
            intentStore: LayoutIntentStore(path: path("intents.json")), stageStore: store, events: events,
            clock: { clock.now }, frameRegistry: registry, treeScopeApplications: TreeScopeApplicationCenter())
        let maintainer = LayoutMaintainer(service: service, events: events, store: store,
            dragActivity: WindowDragActivity(path: path("drag")), commandActivity: LayoutCommandActivity(path: path("commands")),
            mouseButtonsPressed: { false }, writtenFrames: registry, generations: generations,
            readFrame: { writer.readFrame(of: $0) }, configService: ConfigReloadService(activeConfig: config, eventLog: events),
            now: { clock.now })

        // Simule l'échec asynchrone d'une transition animée (ax_window_unavailable_or_quarantined)
        // qui mémorisait auparavant failedFrames[306509] pour 30 s.
        let targetFrame = Rect(x: 500, y: 0, width: 500, height: 800)
        let failedPlan = ApplyPlan(commands: [ApplyCommand(window: terminal, frame: targetFrame)])
        let failedResult = ApplyResult(attempted: 1, applied: 0, clamped: 0, failed: 1, items: [
            ApplyResultItem(windowID: terminal.id, status: .failed, requested: targetFrame, actual: nil)
        ])
        maintainer.recordTransition(failedResult, from: failedPlan, generation: generations.current)

        // Passe d'attente AX : la fenêtre est indisponible, `ax_ready_retry` est armé.
        _ = maintainer.tick(cause: "ax:AXWindowMoved")
        #expect(maintainer.nextDeadline(now: clock.now) != nil)
        #expect(provider.snapshots.first { $0.id == terminal.id }?.frame == terminal.frame)

        // 0.2 s plus tard (bien avant les 30 s de failedFrames), AX devient prêt :
        // la fenêtre doit être immédiatement placée dans le canevas.
        writer.unavailable.remove(terminal.id)
        clock.now += 0.2
        _ = maintainer.tick(cause: "deadline:ax_ready_retry")

        #expect(provider.snapshots.first { $0.id == terminal.id }?.frame == targetFrame)
        let log = try String(contentsOfFile: path("events.jsonl"), encoding: .utf8)
        #expect(log.contains("\"type\":\"layout_window_waiting_for_ax\""))
        #expect(log.contains("\"type\":\"layout_window_ax_ready\""))
    }

    @Test
    func zoomedStageDefersHidingNewcomerWhileSystemFocusIsUnreadableThenExitsZoom() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("placement037-zoom-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func path(_ name: String) -> String { directory.appendingPathComponent(name).path }

        let display = powerDisplay()
        let zoomed = powerWindow(184562, x: 0, y: 0, width: 1000, height: 800, app: "T3")
        let newcomer = powerWindow(306509, x: 150, y: 200, width: 570, height: 436, app: "iTerm2")
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let provider = PowerUserProvider(displays: [display], windows: [zoomed, newcomer])
        // Le serveur AX de l'app nouvellement lancée ne répond pas encore : focus système illisible.
        provider.focusedID = nil
        let store = StageStore(path: path("stages.json"))
        store.save(PersistentStageState(scopes: [PersistentStageScope(
            displayID: display.id, desktopID: scope.desktopID, activeStageID: scope.stageID,
            stages: [PersistentStage(id: scope.stageID, mode: .spatialBsp, focusedWindowID: zoomed.id, members: [
                PersistentStageMember(windowID: zoomed.id, bundleID: zoomed.bundleID, title: zoomed.title, frame: zoomed.frame)
            ])])],
            desktopSelections: [PersistentDesktopSelection(displayID: display.id, currentDesktopID: scope.desktopID)],
            activeDisplayID: display.id))
        let intents = LayoutIntentStore(path: path("intents.json"))
        intents.save(LayoutIntent(scope: scope, windowIDs: [zoomed.id],
            placements: [zoomed.id: zoomed.frame], source: .command,
            zoomedWindowID: zoomed.id, zoomReservesRail: true,
            restorePlacements: [zoomed.id: Rect(x: 0, y: 0, width: 500, height: 800)]))
        let config = RoadieConfig(tiling: TilingConfig(defaultStrategy: .spatialBsp, gapsOuter: 0, gapsInner: 0))
        let clock = Placement037Clock()
        let registry = WrittenFrameRegistry()
        let writer = Placement037Writer(provider: provider, registry: registry, clock: clock, unavailable: [newcomer.id])
        let events = EventLog(path: path("events.jsonl"))
        let service = SnapshotService(provider: provider, frameWriter: writer, config: config,
            intentStore: intents, stageStore: store, events: events,
            clock: { clock.now }, frameRegistry: registry, treeScopeApplications: TreeScopeApplicationCenter())
        let maintainer = LayoutMaintainer(service: service, events: events, store: store,
            dragActivity: WindowDragActivity(path: path("drag")), commandActivity: LayoutCommandActivity(path: path("commands")),
            mouseButtonsPressed: { false }, writtenFrames: registry, generations: PlacementGeneration(),
            readFrame: { writer.readFrame(of: $0) }, configService: ConfigReloadService(activeConfig: config, eventLog: events),
            now: { clock.now })

        // Tick 1 : le focus système est nil (iTerm2 initialise AX). La nouvelle fenêtre ne doit PAS
        // être cachée hors écran, et un retry rapide doit être armé.
        _ = maintainer.tick(cause: "safety")
        #expect(provider.snapshots.first { $0.id == newcomer.id }?.frame == newcomer.frame)
        #expect(writer.attempts[newcomer.id, default: 0] == 0)
        #expect(maintainer.nextDeadline(now: clock.now) != nil)

        // Tick 2 : 0.2 s plus tard, AX répond et confirme le focus sur la nouvelle fenêtre.
        // Roadie sort du zoom et place directement les deux fenêtres dans le canevas.
        writer.unavailable.remove(newcomer.id)
        provider.focusedID = newcomer.id
        clock.now += 0.2
        _ = maintainer.tick(cause: "deadline:ax_ready_retry")

        #expect(intents.intent(for: scope)?.zoomedWindowID == nil)
        let zoomedAfter = try #require(provider.snapshots.first { $0.id == zoomed.id }?.frame)
        let newcomerAfter = try #require(provider.snapshots.first { $0.id == newcomer.id }?.frame)
        #expect(zoomedAfter.width == 500)
        #expect(newcomerAfter.width == 500)
        #expect(display.visibleFrame.cgRect.contains(newcomerAfter.cgRect))
        let log = try String(contentsOfFile: path("events.jsonl"), encoding: .utf8)
        #expect(log.contains("\"type\":\"layout_zoom_exited\""))
        #expect(!log.contains("\"type\":\"fullscreen_stage_siblings_hidden\""))
    }
}
