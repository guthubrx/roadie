import AppKit
import Foundation
import RoadieAX
import RoadieCore
import RoadieTiler
import Testing
@testable import RoadieDaemon

private final class Drag033Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 10_000)
}

@Suite @MainActor
struct Spec033DragFlowTests {
    /// Rejoue le geste complet dans un monde isolé, aux coordonnées négatives de l'incident.
    /// Aucun appel AX n'est adressé aux applications réelles de l'utilisateur.
    @Test(arguments: [false, true])
    func twoBottomDropsOnExternalDisplayStayPlacedAcrossMaintenance(staleDestroy: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("drag033-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func path(_ name: String) -> String { directory.appendingPathComponent(name).path }
        let external = DisplaySnapshot(
            id: DisplayID(rawValue: "external033"), index: 2, name: "External",
            frame: Rect(x: -3200, y: -968, width: 3200, height: 1800),
            visibleFrame: Rect(x: -3050, y: -930, width: 3044, height: 1754), isMain: false)
        let builtin = DisplaySnapshot(
            id: DisplayID(rawValue: "internal033"), index: 1, name: "Built-in",
            frame: Rect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: Rect(x: 0, y: 32, width: 1512, height: 950), isMain: true)
        let scope = StageScope(displayID: external.id, desktopID: DesktopID(rawValue: 4), stageID: StageID(rawValue: "4"))
        let t3 = powerWindow(75411, x: -3050, y: -930, width: 1517, height: 872, app: "T3")
        let teams = powerWindow(140, x: -1523, y: -930, width: 1517, height: 1754, app: "Teams")
        let outlook = powerWindow(614, x: -3050, y: -48, width: 1517, height: 872, app: "Outlook")
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5,
            first: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(t3.id), second: .leaf(outlook.id)), second: .leaf(teams.id))
        let provider = PowerUserProvider(displays: [builtin, external], windows: [outlook, teams, t3])
        provider.focusedID = outlook.id
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: path("stages.json"))
        store.save(PersistentStageState(scopes: [PersistentStageScope(
            displayID: external.id, desktopID: scope.desktopID, activeStageID: scope.stageID,
            stages: [PersistentStage(id: scope.stageID, mode: .spatialBsp, members: provider.snapshots.map {
                PersistentStageMember(windowID: $0.id, bundleID: $0.bundleID, title: $0.title, frame: $0.frame)
            }, bspTree: tree)])],
            desktopSelections: [PersistentDesktopSelection(displayID: external.id, currentDesktopID: scope.desktopID)],
            activeDisplayID: external.id))
        let config = RoadieConfig(tiling: TilingConfig(defaultStrategy: .spatialBsp, gapsOuter: 0, gapsInner: 10))
        let events = EventLog(path: path("events.jsonl"))
        let clock = Drag033Clock()
        let registry = WrittenFrameRegistry()
        let applications = TreeScopeApplicationCenter()
        let input = UserInputActivity(monitoring: true)
        let drag = WindowDragActivity(path: path("drag"))
        let commands = LayoutCommandActivity(path: path("commands"))
        let service = SnapshotService(provider: provider, frameWriter: writer, config: config,
            intentStore: LayoutIntentStore(path: path("intents.json")), stageStore: store, events: events,
            userInput: input, clock: { clock.now }, frameRegistry: registry, treeScopeApplications: applications)
        let preview = DropPreviewController(engine: DropPreviewEngine(service: service))
        let controller = WindowDragReorderController(preview: preview,
            commandService: StageCommandService(service: service, store: store, events: events, commandActivity: commands),
            events: events, userInput: input, dragActivity: drag)
        defer { controller.cancelPendingDrag() }
        let maintainer = LayoutMaintainer(service: service, events: events, store: store, dragActivity: drag,
            commandActivity: commands, mouseButtonsPressed: { false }, writtenFrames: registry,
            readFrame: { window in provider.snapshots.first { $0.id == window.id }?.frame.cgRect },
            configService: ConfigReloadService(activeConfig: config, eventLog: events), now: { clock.now })
        _ = service.snapshot(followFocus: false)
        if staleDestroy { service.noteWindowDestroyed(outlook.id) }
        let expected: [WindowID: Rect] = [
            t3.id: Rect(x: -3050, y: -930, width: 1517, height: 1754),
            teams.id: Rect(x: -1523, y: -930, width: 1517, height: 872),
            outlook.id: Rect(x: -1523, y: -48, width: 1517, height: 872),
        ]
        func nsPoint(_ point: CGPoint) -> CGPoint {
            RoadieScreenCoordinate.axRectToNS(CGRect(origin: point, size: .zero)).origin
        }
        for attempt in 1...2 {
            let current = try #require(provider.snapshots.first { $0.id == outlook.id }).frame.cgRect
            controller.handleMouseDown(at: nsPoint(CGPoint(x: current.midX, y: current.minY + 18)))
            #expect(controller.hasActiveDrag, "geste \(attempt) reconnu")
            let target = try #require(provider.snapshots.first { $0.id == teams.id }).frame.cgRect
            let drop = CGPoint(x: target.midX, y: target.maxY - 80)
            controller.handleMouseDragged(to: nsPoint(drop))
            let candidate = try #require(preview.candidate)
            #expect(candidate.operation == .insertDown)
            #expect(candidate.targetWindowID == teams.id)
            #expect(candidate.placements == expected)
            // L'aperçu écrit en arrière-plan. Attendre les voisines avant de simuler
            // le déplacement natif de la source, sans mutation concurrente du mock.
            for _ in 0..<150 {
                if expected.filter({ $0.key != outlook.id }).allSatisfy({ id, frame in
                    provider.snapshots.first { $0.id == id }?.frame == frame
                }) { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            // La fenêtre se déplace nativement pendant le geste ; le contexte de départ reste figé.
            provider.snapshots = provider.snapshots.map { window in
                var updated = window
                if window.id == outlook.id { updated.frame = Rect(x: drop.x - 200, y: drop.y - 18, width: 1517, height: 872) }
                return updated
            }
            controller.handleMouseUp(at: nsPoint(drop))
            for _ in 0..<150 {
                if !preview.isHoldingLayout { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(!preview.isHoldingLayout)
            #expect(!controller.hasActiveDrag)
            #expect(drag.lastDrop()?.windowID == outlook.id)
            for (id, frame) in expected { #expect(provider.snapshots.first { $0.id == id }?.frame == frame) }
            for _ in 0..<3 {
                clock.now += 2
                let result = maintainer.tick(cause: "ax:AXWindowMoved")
                #expect(result.failed == 0)
                for (id, frame) in expected { #expect(provider.snapshots.first { $0.id == id }?.frame == frame) }
            }
            #expect(store.state().bspTree(for: scope)?.windowIDs == [t3.id, teams.id, outlook.id])
        }
        let log = try String(contentsOfFile: path("events.jsonl"), encoding: .utf8)
        #expect(log.components(separatedBy: "\"type\":\"window_drag_apply\"").count - 1 == 2)
        if staleDestroy { #expect(log.contains("window_destruction_retracted")) }
    }
}
