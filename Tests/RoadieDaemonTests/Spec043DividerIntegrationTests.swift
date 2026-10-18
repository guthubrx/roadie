import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages
import RoadieTiler
import Testing
@testable import RoadieDaemon

private final class Divider043Provider: SystemSnapshotProviding, @unchecked Sendable {
    var windowsRead = 0
    var entries: [WindowSnapshot]
    let screen: DisplaySnapshot
    init(screen: DisplaySnapshot, entries: [WindowSnapshot]) { self.screen = screen; self.entries = entries }
    func permissions(prompt: Bool) -> PermissionSnapshot { PermissionSnapshot(accessibilityTrusted: true) }
    func displays() -> [DisplaySnapshot] { [screen] }
    func windows() -> [WindowSnapshot] { windowsRead += 1; return entries }
}

private final class Divider043Writer: WindowFrameWriting, @unchecked Sendable {
    let provider: Divider043Provider
    let registry: WrittenFrameRegistry
    var requests = 0
    init(_ provider: Divider043Provider, _ registry: WrittenFrameRegistry) { self.provider = provider; self.registry = registry }
    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        requests += 1
        if let index = provider.entries.firstIndex(where: { $0.id == window.id }) { provider.entries[index].frame = Rect(frame) }
        return frame
    }
    func setFrames(_ updates: [WindowFrameUpdate], generation: UInt64) -> [WindowID: CGRect?] {
        updates.reduce(into: [:]) { values, update in
            let actual = setFrame(update.frame, of: update.window)
            registry.record(windowID: update.window.id.rawValue, requested: update.frame,
                            readBack: actual, generation: generation, at: Date())
            values.updateValue(actual, forKey: update.window.id)
        }
    }
}

@MainActor
private final class Divider043Fixture {
    let directory: URL
    let store: StageStore
    let provider: Divider043Provider
    let writer: Divider043Writer
    let service: SnapshotService
    let registry = WrittenFrameRegistry()
    let generations = PlacementGeneration()
    let scope: StageScope
    let original: BSPTree
    var config = RoadieConfig(tiling: TilingConfig(defaultStrategy: .spatialBsp, gapsOuter: 0, gapsInner: 10))
    var snapshot: DaemonSnapshot
    lazy var coordinator = DividerResizeCoordinator(service: service, configLoader: { [unowned self] in self.config },
        generations: generations, events: EventLog(path: directory.appendingPathComponent("divider-events.jsonl").path))

    init(four: Bool = false, x: Double = 0) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("divider043-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let screen = powerDisplay("divider043", x: x)
        let scope = StageScope(displayID: screen.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        self.scope = scope
        let left: BSPTree = four ? .split(orientation: .horizontal, ratio: 0.5,
            first: .leaf(WindowID(rawValue: 1)), second: .leaf(WindowID(rawValue: 2))) : .leaf(WindowID(rawValue: 1))
        let right: BSPTree = four ? .split(orientation: .horizontal, ratio: 0.5,
            first: .leaf(WindowID(rawValue: 3)), second: .leaf(WindowID(rawValue: 4))) : .leaf(WindowID(rawValue: 2))
        original = .split(orientation: .vertical, ratio: 0.5, first: left, second: right)
        let windows = original.place(in: screen.visibleFrame.cgRect, innerGap: 10).sorted { $0.key < $1.key }.map { id, frame in
            powerWindow(id.rawValue, x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
        }
        provider = Divider043Provider(screen: screen, entries: windows)
        writer = Divider043Writer(provider, registry)
        store = StageStore(path: directory.appendingPathComponent("stages.json").path)
        store.save(PersistentStageState(scopes: [PersistentStageScope(displayID: screen.id,
            activeStageID: scope.stageID, stages: [PersistentStage(id: scope.stageID, mode: .spatialBsp,
                members: windows.map { PersistentStageMember(windowID: $0.id, bundleID: $0.bundleID, title: $0.title, frame: $0.frame) },
                bspTree: original)])], activeDisplayID: screen.id))
        var display = DisplayState(id: screen.id, currentDesktopID: scope.desktopID)
        display.desktops[scope.desktopID]?.stages[scope.stageID] = StageState(id: scope.stageID, name: "Test", mode: .spatialBsp,
                                                                          windowIDs: windows.map(\.id))
        snapshot = DaemonSnapshot(permissions: PermissionSnapshot(accessibilityTrusted: true), displays: [screen],
            windows: windows.map { ScopedWindowSnapshot(window: $0, scope: scope, pin: nil, isNewlyScoped: false) },
            state: RoadieState(displays: [screen.id: display]))
        service = SnapshotService(provider: provider, frameWriter: writer, config: config, railSettings: RailSettings.load(raw: ""),
            railRuntimeStateStore: RailRuntimeStateStore(path: directory.appendingPathComponent("rail.json").path),
            intentStore: LayoutIntentStore(path: directory.appendingPathComponent("intents.json").path),
            stageStore: store, frameRegistry: registry,
            treeScopeApplications: TreeScopeApplicationCenter())
    }

    func grip() throws -> SplitResizeHandle {
        try #require(coordinator.update(snapshot: snapshot).first { $0.divider.path.isEmpty })
    }
    func clean() { try? FileManager.default.removeItem(at: directory) }
}

@Suite @MainActor
struct Spec043DividerIntegrationTests {
    @Test
    func waitingNativeObservationDoesNotRevertTheFollowingExplicitResize() throws {
        let f = try Divider043Fixture(four: true)
        defer { f.clean() }
        let input = UserInputActivity()
        var now = Date()
        var pressed = false
        let maintainer = LayoutMaintainer(service: f.service,
            events: EventLog(path: f.directory.appendingPathComponent("native-events.jsonl").path),
            dragActivity: WindowDragActivity(path: f.directory.appendingPathComponent("drag.json").path),
            commandActivity: LayoutCommandActivity(path: f.directory.appendingPathComponent("command.json").path),
            mouseButtonsPressed: { pressed }, writtenFrames: f.registry, generations: f.generations,
            takeGesture: input.takeGesture, spaceProbe: { _ in true },
            readFrame: { window in f.provider.entries.first { $0.id == window.id }?.frame.cgRect },
            configService: ConfigReloadService(activeConfig: f.config, activePath: f.directory.appendingPathComponent("config.toml").path),
            now: { now })
        _ = maintainer.tick(cause: "command:startup")
        now.addTimeInterval(5)
        let initial = try #require(f.provider.entries.first { $0.id == WindowID(rawValue: 2) })
        input.observeGestures(target: { _ in (2, initial.frame.cgRect) }, onRelease: { _ in })
        input.mouseDown(at: .zero, now: now)
        input.mouseDragged()
        input.mouseUp(leftButton: true, now: now)
        _ = maintainer.tick(cause: "drag")
        #expect(maintainer.nextDeadline(now: now) != nil)
        let grip = try f.grip()
        pressed = true
        #expect(f.coordinator.begin(grip, at: grip.divider.position))
        input.claimExplicitResize()
        f.coordinator.queue(grip, at: CGPoint(x: 700, y: 400))
        f.coordinator.flush()
        let expected = f.provider.entries.map(\.frame)
        let written = f.writer.requests
        now.addTimeInterval(0.05)
        _ = maintainer.tick(cause: "safety")
        #expect(f.writer.requests == written)
        #expect(f.coordinator.isDragging)
        f.coordinator.end(cancelled: false)
        pressed = false
        for _ in 0..<6 {
            now.addTimeInterval(0.1)
            _ = maintainer.tick(cause: "safety")
            #expect(f.provider.entries.map(\.frame) == expected)
        }
        let persisted = try #require(f.store.state().bspTree(for: f.scope))
        let frames = persisted.place(in: f.provider.screen.visibleFrame.cgRect, innerGap: 10)
        #expect(f.provider.entries.allSatisfy { frames[$0.id] == $0.frame.cgRect })
    }

    @Test
    func nativeEdgeInDividerZoneSurvivesBorderDecorationsAndRelease() throws {
        let f = try Divider043Fixture(four: true)
        defer { f.clean() }
        let tiles = f.provider.entries
        f.provider.entries = tiles.enumerated().flatMap { index, tile -> [WindowSnapshot] in
            let border = WindowSnapshot(id: WindowID(rawValue: UInt32(100 + index)), pid: 7233,
                appName: "borders", bundleID: "", title: "",
                frame: Rect(tile.frame.cgRect.insetBy(dx: -12, dy: -12)),
                isOnScreen: true, isTileCandidate: false)
            return [border, tile]
        }
        let input = UserInputActivity()
        var now = Date()
        let maintainer = LayoutMaintainer(service: f.service,
            events: EventLog(path: f.directory.appendingPathComponent("native-events.jsonl").path),
            dragActivity: WindowDragActivity(path: f.directory.appendingPathComponent("drag.json").path),
            commandActivity: LayoutCommandActivity(path: f.directory.appendingPathComponent("command.json").path),
            mouseButtonsPressed: { false }, writtenFrames: f.registry, generations: f.generations,
            takeGesture: input.takeGesture, spaceProbe: { _ in true },
            readFrame: { window in f.provider.entries.first { $0.id == window.id }?.frame.cgRect },
            configService: ConfigReloadService(activeConfig: f.config, activePath: f.directory.appendingPathComponent("config.toml").path),
            now: { now })
        _ = maintainer.tick(cause: "command:startup")
        now.addTimeInterval(5)
        input.observeGestures(target: { point in
            FocusFollowsMousePicker.gestureTargetWindow(at: point, in: f.service.sharedSnapshot())
                .map { ($0.window.id.rawValue, $0.window.frame.cgRect) }
        }, onRelease: { _ in })
        // Le bord natif peut recevoir ce clic, même si une poignée géométrique est prévue ici.
        let point = CGPoint(x: 200, y: 403.5)
        #expect(f.coordinator.update(snapshot: f.snapshot).contains { $0.divider.hitRect.contains(point) })
        input.mouseDown(at: point, now: now)
        #expect(input.currentGesture?.windowID == 2)
        input.mouseDragged()
        let index = try #require(f.provider.entries.firstIndex { $0.id == WindowID(rawValue: 2) })
        let userFrame = Rect(x: 0, y: 425, width: 495, height: 375)
        f.provider.entries[index].frame = userFrame
        input.mouseUp(leftButton: true, now: now)
        _ = maintainer.tick(cause: "drag")
        #expect(f.provider.entries[index].frame == userFrame)
        for _ in 0..<4 {
            now.addTimeInterval(0.5)
            _ = maintainer.tick(cause: "safety")
        }
        #expect(f.provider.entries[index].frame == userFrame)
        let persisted = try #require(f.store.state().bspTree(for: f.scope))
        #expect(persisted.place(in: f.provider.screen.visibleFrame.cgRect, innerGap: 10)[WindowID(rawValue: 2)] == userFrame.cgRect)
    }

    /// Comparaison logicielle : vrais coordinateurs et persistance, fournisseur/écrivain simulés.
    /// La présentation initiale, les délais des événements et les appels AX réels sont exclus.
    private func compareResize(four: Bool, explicit: Bool) throws -> (Double, Int, Int) {
        let f = try Divider043Fixture(four: four)
        defer { f.clean() }
        var pending: GestureSession?
        var now = Date()
        let maintainer = LayoutMaintainer(service: f.service,
            events: EventLog(path: f.directory.appendingPathComponent("native-events.jsonl").path),
            dragActivity: WindowDragActivity(path: f.directory.appendingPathComponent("drag.json").path),
            commandActivity: LayoutCommandActivity(path: f.directory.appendingPathComponent("command.json").path),
            mouseButtonsPressed: { false }, writtenFrames: f.registry, generations: f.generations,
            takeGesture: { defer { pending = nil }; return pending }, spaceProbe: { _ in true },
            readFrame: { window in f.provider.entries.first { $0.id == window.id }?.frame.cgRect },
            configService: ConfigReloadService(activeConfig: f.config, activePath: f.directory.appendingPathComponent("config.toml").path),
            now: { now })
        _ = maintainer.tick(cause: "command:startup")
        now.addTimeInterval(5)
        let point = CGPoint(x: 700, y: 400)
        let grip = try f.grip()
        if explicit {
            #expect(f.coordinator.begin(grip, at: grip.divider.position))
            f.coordinator.queue(grip, at: point)
        } else {
            let index = try #require(f.provider.entries.firstIndex { $0.id == WindowID(rawValue: 1) })
            let start = f.provider.entries[index].frame.cgRect
            // macOS a déjà redimensionné la fenêtre manipulée ; Roadie doit ajuster ses voisines.
            f.provider.entries[index].frame.width = point.x - 5 - start.minX
            pending = GestureSession(windowID: 1, startFrame: start, startedAt: now.addingTimeInterval(-0.5),
                                     endedAt: now, didDrag: true)
            f.service.invalidateSharedSnapshot()
        }
        f.provider.windowsRead = 0
        f.writer.requests = 0
        let start = DispatchTime.now().uptimeNanoseconds
        if explicit { f.coordinator.end(cancelled: false) }
        else { _ = maintainer.tick(cause: "drag") }
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        let wanted = try #require(f.original.movingDivider(at: [], to: point,
            in: f.provider.screen.visibleFrame.cgRect, innerGap: 10))
        let expected = wanted.place(in: f.provider.screen.visibleFrame.cgRect, innerGap: 10)
        let persisted = try #require(f.store.state().bspTree(for: f.scope))
        #expect(persisted.place(in: f.provider.screen.visibleFrame.cgRect, innerGap: 10) == expected)
        #expect(f.provider.entries.allSatisfy { expected[$0.id] == $0.frame.cgRect })
        return (ms, f.provider.windowsRead, f.writer.requests)
    }

    @Test(arguments: [false, true])
    func nativeAndExplicitResizeReachTheSameLayout(four: Bool) throws {
        let native = try compareResize(four: four, explicit: false)
        let explicit = try compareResize(four: four, explicit: true)
        #expect(native.1 > 0)
        #expect(explicit.1 == 0)
        #expect(native.2 > 0 && explicit.2 > 0)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ROADIE_RESIZE_BENCHMARK"] == "1"))
    func benchmarkNativeAndExplicitSoftwarePaths() throws {
        for four in [false, true] {
            // Un échauffement de chaque chemin, puis sept paires dans un ordre alterné.
            _ = try compareResize(four: four, explicit: false)
            _ = try compareResize(four: four, explicit: true)
            for round in 0..<7 {
                for explicit in (round.isMultiple(of: 2) ? [false, true] : [true, false]) {
                    let (ms, scans, writes) = try compareResize(four: four, explicit: explicit)
                    print("RESIZE044 windows=\(four ? 4 : 2) route=\(explicit ? "handle" : "native") round=\(round) software_ms=\(ms) snapshots=\(scans) writes=\(writes) simulated_ax=true")
                }
            }
        }
    }

    @Test(arguments: [false, true])
    func borderDecorationsDoNotHideHandlesAndSettingStillControlsThem(four: Bool) throws {
        let f = try Divider043Fixture(four: four)
        defer { f.clean() }
        let expected = f.coordinator.update(snapshot: f.snapshot)
        #expect(expected.count == (four ? 3 : 1))
        let tiles = f.snapshot.windows
        for (index, tile) in tiles.enumerated() {
            let border = WindowSnapshot(id: WindowID(rawValue: UInt32(100 + index)), pid: 7233,
                appName: "borders", bundleID: "", title: "",
                frame: Rect(tile.window.frame.cgRect.insetBy(dx: -12, dy: -12)),
                isOnScreen: true, isTileCandidate: false)
            f.snapshot.windows.append(ScopedWindowSnapshot(window: border, scope: nil))
        }
        #expect(f.coordinator.update(snapshot: f.snapshot) == expected)
        f.config.tiling.resizeHandles = false
        #expect(f.coordinator.update(snapshot: f.snapshot).isEmpty)
        f.config.tiling.resizeHandles = true
        #expect(f.coordinator.update(snapshot: f.snapshot) == expected)
        #expect(f.store.state().bspTree(for: f.scope) == f.original)
        #expect(f.writer.requests == 0)
    }

    @Test(arguments: ["unknown", "title", "bundle", "role", "subrole", "furniture"])
    func onlyUnidentifiedBorderDecorationIsIgnored(kind: String) throws {
        let f = try Divider043Fixture()
        defer { f.clean() }
        var overlay = WindowSnapshot(id: WindowID(rawValue: 100), pid: 7233,
            appName: "borders", bundleID: "", title: "", frame: Rect(x: 450, y: 200, width: 100, height: 100),
            isOnScreen: true, isTileCandidate: false)
        switch kind {
        case "unknown": overlay.appName = "Unknown"
        case "title": overlay.title = "Document"
        case "bundle": overlay.bundleID = "com.example.editor"
        case "role": overlay.role = "AXWindow"
        case "subrole": overlay.subrole = "AXStandardWindow"
        default: overlay.furniture = WindowFurniture(hasCloseButton: true)
        }
        f.snapshot.windows.append(ScopedWindowSnapshot(window: overlay, scope: nil))
        #expect(f.coordinator.update(snapshot: f.snapshot).isEmpty)
    }

    @Test
    func clickingWithoutMovingDoesNotPersistRoundingNoise() throws {
        let f = try Divider043Fixture()
        defer { f.clean() }
        let grip = try f.grip()
        #expect(f.coordinator.begin(grip, at: grip.divider.position))
        f.coordinator.queue(grip, at: grip.divider.position)
        f.coordinator.end(cancelled: false)
        #expect(f.store.state().bspTree(for: f.scope) == f.original)
        #expect(f.writer.requests == 0)
        #expect(f.generations.current == 0)
    }

    @Test(arguments: [false, true])
    func returningToInitialPositionUsesReadBackFrames(four: Bool) throws {
        let f = try Divider043Fixture(four: four)
        defer { f.clean() }
        let grip = try f.grip()
        #expect(f.coordinator.begin(grip, at: grip.divider.position))
        f.coordinator.queue(grip, at: CGPoint(x: 700, y: 300))
        f.coordinator.flush()
        #expect(f.writer.requests == (four ? 4 : 2))
        f.coordinator.queue(grip, at: grip.divider.position)
        f.coordinator.end(cancelled: false)
        let original = f.original.place(in: f.provider.screen.visibleFrame.cgRect, innerGap: 10)
        let restored = try #require(f.store.state().bspTree(for: f.scope))
        #expect(restored.place(in: f.provider.screen.visibleFrame.cgRect, innerGap: 10) == original)
        #expect(f.provider.entries.allSatisfy { original[$0.id] == $0.frame.cgRect })
        #expect(f.writer.requests == (four ? 8 : 4))
        #expect(f.provider.windowsRead == 0)
    }

    @Test
    func floatingWindowAfterFirstTiledWindowStillOwnsItsVisiblePixels() throws {
        let f = try Divider043Fixture()
        defer { f.clean() }
        let popup = powerWindow(99, x: 450, y: 200, width: 100, height: 100)
        f.snapshot.windows.insert(ScopedWindowSnapshot(window: popup, scope: nil, pin: nil, isNewlyScoped: false), at: 1)
        #expect(f.coordinator.update(snapshot: f.snapshot).isEmpty)
    }

    @Test
    func placementToleranceNeverLetsHandleCoverActualWindow() throws {
        let f = try Divider043Fixture()
        defer { f.clean() }
        f.snapshot.windows[0].window.frame.width += 2
        #expect(f.coordinator.update(snapshot: f.snapshot).isEmpty)
    }

    @Test(arguments: [false, true])
    func latestPointerPersistsAndPlacesWithoutAcquiringAnotherSnapshot(four: Bool) throws {
        let f = try Divider043Fixture(four: four, x: -1000)
        defer { f.clean() }
        let grip = try f.grip()
        #expect(f.coordinator.begin(grip, at: grip.divider.position))
        f.coordinator.queue(grip, at: CGPoint(x: -400, y: 300))
        f.coordinator.queue(grip, at: CGPoint(x: -300, y: 300))
        #expect(f.writer.requests == 0)
        f.coordinator.end(cancelled: false)
        let tree = try #require(f.store.state().bspTree(for: f.scope))
        let wanted = try #require(f.original.movingDivider(at: [], to: CGPoint(x: -300, y: 300),
                                                          in: f.provider.screen.visibleFrame.cgRect, innerGap: 10))
        #expect(tree == wanted)
        let frames = wanted.place(in: f.provider.screen.visibleFrame.cgRect, innerGap: 10)
        #expect(f.provider.entries.allSatisfy { frames[$0.id] == $0.frame.cgRect })
        #expect(f.provider.windowsRead == 0)
        #expect(!f.coordinator.isDragging)
    }

    @Test(arguments: ["cancel", "generation", "stage", "tree", "configuration", "display"])
    func interruptedContextNeverAppliesQueuedTarget(reason: String) throws {
        let f = try Divider043Fixture()
        defer { f.clean() }
        let grip = try f.grip()
        #expect(f.coordinator.begin(grip, at: grip.divider.position))
        f.coordinator.queue(grip, at: CGPoint(x: 700, y: 300))
        switch reason {
        case "cancel": f.coordinator.end(cancelled: true)
        case "generation": _ = f.generations.next()
        case "stage": try f.store.mutateChecked { $0.scopes[0].activeStageID = StageID(rawValue: "2") }
        case "tree": try f.store.mutateChecked { $0.setBSPTree(.split(orientation: .vertical, ratio: 0.4,
            first: .leaf(WindowID(rawValue: 1)), second: .leaf(WindowID(rawValue: 2))), for: f.scope) }
        case "configuration": f.config.tiling.resizeHandles = false
        case "display": f.snapshot.displays.removeAll(); _ = f.coordinator.update(snapshot: f.snapshot)
        default: Issue.record("cas inconnu")
        }
        f.coordinator.flush()
        #expect(f.writer.requests == 0)
        #expect(!f.coordinator.isDragging)
    }

    @Test
    func disabledOrOccludedHandlesDoNotInterceptWindows() throws {
        let f = try Divider043Fixture()
        defer { f.clean() }
        #expect(try f.grip().divider.path.isEmpty)
        let popup = powerWindow(99, x: 450, y: 200, width: 100, height: 100)
        f.snapshot.windows.insert(ScopedWindowSnapshot(window: popup, scope: nil, pin: nil, isNewlyScoped: false), at: 0)
        #expect(f.coordinator.update(snapshot: f.snapshot).isEmpty)
        f.snapshot.windows.removeFirst()
        f.config.tiling.resizeHandles = false
        #expect(f.coordinator.update(snapshot: f.snapshot).isEmpty)
    }
}
