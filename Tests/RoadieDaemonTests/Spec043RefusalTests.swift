import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages
import RoadieTiler
import Testing
@testable import RoadieDaemon

private final class Refusal043Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 10_000)
    var gesture: GestureSession?
    var mouseDown = false
    var readable = true
    var onRead: (() -> CGRect?)?

    func advance(_ seconds: TimeInterval) { now += seconds }
    func takeGesture() -> GestureSession? {
        defer { gesture = nil }
        return gesture
    }
}

/// Réutilise le provider et l'écrivain existants ; seule la frontière AX ajoute
/// le minimum imposé par l'application et le registre du point d'écriture.
private final class Refusal043Writer: WindowFrameWriting, @unchecked Sendable {
    let base: PowerUserWriter
    let registry: WrittenFrameRegistry
    let clock: Refusal043Clock
    var minimums: [WindowID: CGSize] = [:]
    var attempts: [UInt64: [WindowID: Int]] = [:]

    init(provider: PowerUserProvider, registry: WrittenFrameRegistry, clock: Refusal043Clock) {
        base = PowerUserWriter(provider: provider)
        self.registry = registry
        self.clock = clock
    }

    func readFrame(of window: WindowSnapshot) -> CGRect? { base.readFrame(of: window) }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        let minimum = minimums[window.id] ?? .zero
        return base.setFrame(CGRect(x: frame.minX, y: frame.minY,
            width: max(frame.width, minimum.width), height: max(frame.height, minimum.height)), of: window)
    }

    func setFrames(_ updates: [WindowFrameUpdate], generation: UInt64) -> [WindowID: CGRect?] {
        var results: [WindowID: CGRect?] = [:]
        for update in updates {
            attempts[generation, default: [:]][update.window.id, default: 0] += 1
            let actual = setFrame(update.frame, of: update.window)
            registry.record(windowID: update.window.id.rawValue, requested: update.frame,
                readBack: actual, generation: generation, at: clock.now)
            results.updateValue(actual, forKey: update.window.id)
        }
        return results
    }
}

private struct Refusal043Harness {
    let directory: URL
    let provider: PowerUserProvider
    let writer: Refusal043Writer
    let registry: WrittenFrameRegistry
    let generations: PlacementGeneration
    let clock: Refusal043Clock
    let store: StageStore
    let maintainer: LayoutMaintainer
    let scope: StageScope
    let tree: BSPTree

    init(fourWindows: Bool = false) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("refusal043-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory
        func path(_ name: String) -> String { directory.appendingPathComponent(name).path }
        let display = powerDisplay("refusal043")
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        self.scope = scope
        let left: BSPTree = fourWindows
            ? .split(orientation: .horizontal, ratio: 0.5, first: .leaf(WindowID(rawValue: 1)), second: .leaf(WindowID(rawValue: 2)))
            : .leaf(WindowID(rawValue: 1))
        let right: BSPTree = fourWindows
            ? .split(orientation: .horizontal, ratio: 0.5, first: .leaf(WindowID(rawValue: 3)), second: .leaf(WindowID(rawValue: 4)))
            : .leaf(WindowID(rawValue: 2))
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: left, second: right)
        self.tree = tree
        let frames = tree.place(in: display.visibleFrame.cgRect, innerGap: 0)
        let windows = frames.keys.sorted().map { id in
            let frame = frames[id]!
            // Démarrer hors cible force une vraie première écriture dans chaque test.
            return powerWindow(id.rawValue, x: Double(frame.minX + 20), y: Double(frame.minY + 20),
                width: 300, height: 200)
        }
        let provider = PowerUserProvider(displays: [display], windows: windows)
        self.provider = provider
        let store = StageStore(path: path("stages.json"))
        self.store = store
        store.save(PersistentStageState(scopes: [PersistentStageScope(displayID: display.id,
            activeStageID: scope.stageID, stages: [PersistentStage(id: scope.stageID, mode: .spatialBsp,
                members: windows.map { PersistentStageMember(windowID: $0.id, bundleID: $0.bundleID, title: $0.title, frame: $0.frame) },
                bspTree: tree)])], activeDisplayID: display.id))
        let clock = Refusal043Clock()
        self.clock = clock
        let registry = WrittenFrameRegistry()
        self.registry = registry
        let generations = PlacementGeneration()
        self.generations = generations
        let writer = Refusal043Writer(provider: provider, registry: registry, clock: clock)
        self.writer = writer
        let events = EventLog(path: path("events.jsonl"))
        let config = RoadieConfig(tiling: TilingConfig(defaultStrategy: .spatialBsp, gapsOuter: 0, gapsInner: 0))
        let service = SnapshotService(provider: provider, frameWriter: writer, config: config,
            intentStore: LayoutIntentStore(path: path("intents.json")), stageStore: store,
            clock: { clock.now }, frameRegistry: registry, treeScopeApplications: TreeScopeApplicationCenter())
        maintainer = LayoutMaintainer(service: service, events: events, store: store,
            dragActivity: WindowDragActivity(path: path("drag.json")),
            commandActivity: LayoutCommandActivity(path: path("commands.json")),
            mouseButtonsPressed: { clock.mouseDown }, writtenFrames: registry, generations: generations,
            takeGesture: { clock.takeGesture() }, spaceProbe: { _ in true },
            readFrame: { window in
                if let onRead = clock.onRead { return onRead() }
                return clock.readable ? writer.readFrame(of: window) : nil
            }, configService: ConfigReloadService(activeConfig: config, eventLog: events), now: { clock.now })
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }
    func frame(_ id: UInt32) -> Rect? { provider.snapshots.first { $0.id.rawValue == id }?.frame }
    func setFrame(_ id: UInt32, _ frame: Rect) {
        provider.snapshots = provider.snapshots.map {
            var window = $0
            if window.id.rawValue == id { window.frame = frame }
            return window
        }
    }
    func resize(_ id: UInt32, to frame: Rect) throws {
        let start = try #require(self.frame(id)).cgRect
        setFrame(id, frame)
        clock.gesture = GestureSession(windowID: id, startFrame: start, startedAt: clock.now, endedAt: clock.now)
    }
    func learnMinimum() {
        writer.minimums[WindowID(rawValue: 1)] = CGSize(width: 700, height: 0)
        _ = maintainer.tick(cause: "command:startup")
        clock.advance(LayoutTolerance.refusalConfirmDelay)
        _ = maintainer.tick(cause: "deadline")
    }
    var repairCount: Int {
        let events = (try? String(contentsOf: directory.appendingPathComponent("events.jsonl"), encoding: .utf8)) ?? ""
        return events.components(separatedBy: "\"source\":\"tree_minimum_size\"").count - 1
    }
}

@Suite
struct Spec043RefusalTests {
    @Test
    func confirmedOldRefusalCannotOverwriteFreshResize() throws {
        let h = try Refusal043Harness()
        defer { h.cleanup() }
        h.writer.minimums[WindowID(rawValue: 1)] = CGSize(width: 700, height: 0)
        _ = h.maintainer.tick(cause: "command:startup")
        let old = try #require(h.registry.entry(for: 1))
        h.clock.advance(LayoutTolerance.refusalConfirmDelay)
        let readBack = try #require(old.readBack)
        #expect(h.registry.confirmRefusal(windowID: 1, observed: readBack, at: h.clock.now))
        h.writer.minimums.removeAll()
        try h.resize(1, to: Rect(x: 0, y: 0, width: 400, height: 800))

        _ = h.maintainer.tick(cause: "drag")
        h.clock.advance(0.2)
        #expect(h.maintainer.tick(cause: "deadline").commands == 0)
        #expect(h.frame(1)?.width == 400)
        #expect(h.frame(2)?.x == 400)
        #expect(h.generations.current > old.generation)
        #expect(h.repairCount == 0)
    }

    @Test
    func pendingOldRefusalCannotConstrainGestureOnNeighbor() throws {
        let h = try Refusal043Harness()
        defer { h.cleanup() }
        h.writer.minimums[WindowID(rawValue: 1)] = CGSize(width: 700, height: 0)
        _ = h.maintainer.tick(cause: "command:startup")
        h.clock.advance(LayoutTolerance.refusalConfirmDelay)
        h.writer.minimums.removeAll()
        try h.resize(2, to: Rect(x: 400, y: 0, width: 600, height: 800))
        _ = h.maintainer.tick(cause: "drag")

        #expect(h.frame(1)?.width == 400)
        #expect(h.frame(2)?.x == 400)
        #expect(h.registry.entry(for: 1)?.refusalConfirmedAt == nil)
        #expect(h.repairCount == 0)
    }

    @Test
    func newIntentionMayRetrySameTargetRefusedByOldGeneration() throws {
        let h = try Refusal043Harness()
        defer { h.cleanup() }
        h.writer.minimums[WindowID(rawValue: 1)] = CGSize(width: 700, height: 0)
        _ = h.maintainer.tick(cause: "command:startup")
        let old = try #require(h.registry.entry(for: 1))
        h.writer.minimums.removeAll()
        h.clock.advance(0.05)
        _ = h.maintainer.tick(cause: "command:retile")

        #expect(h.frame(1)?.width == 500)
        #expect(h.registry.entry(for: 1)?.generation == h.generations.current)
        #expect(h.generations.current > old.generation)
    }

    @Test
    func secondObservationMustBeFreshAndRemainInConfirmationWindow() throws {
        let h = try Refusal043Harness()
        defer { h.cleanup() }
        h.writer.minimums[WindowID(rawValue: 1)] = CGSize(width: 700, height: 0)
        _ = h.maintainer.tick(cause: "command:startup")
        h.clock.readable = false
        h.clock.advance(LayoutTolerance.refusalConfirmDelay)
        _ = h.maintainer.tick(cause: "deadline")
        #expect(h.registry.entry(for: 1)?.refusalConfirmedAt == nil)
        #expect(h.repairCount == 0)
        h.clock.readable = true
        h.clock.advance(LayoutTolerance.echoWindow)
        _ = h.maintainer.tick(cause: "safety")
        #expect(h.registry.entry(for: 1)?.refusalConfirmedAt == nil)
        #expect(h.repairCount == 0)
    }

    @Test(arguments: [false, true])
    func readStartedForOldWriteCannotConfirmReplacementWrite(newGeneration: Bool) throws {
        let h = try Refusal043Harness()
        defer { h.cleanup() }
        h.writer.minimums[WindowID(rawValue: 1)] = CGSize(width: 700, height: 0)
        _ = h.maintainer.tick(cause: "command:startup")
        let old = try #require(h.registry.entry(for: 1))
        let delayed = try #require(old.readBack)
        // Le snapshot a déjà vu la cible. La réponse AX retardée porte encore l'ancien refus.
        h.setFrame(1, Rect(old.requested))
        h.clock.onRead = {
            h.clock.onRead = nil
            h.registry.record(windowID: 1, requested: CGRect(x: 0, y: 0, width: 400, height: 800),
                readBack: delayed, generation: newGeneration ? h.generations.next() : old.generation, at: h.clock.now)
            return delayed
        }
        h.clock.advance(LayoutTolerance.refusalConfirmDelay)
        _ = h.maintainer.tick(cause: "deadline")

        #expect(h.registry.entry(for: 1)?.generation == h.generations.current)
        #expect(h.registry.entry(for: 1)?.refusalConfirmedAt == nil)
        #expect(h.repairCount == 0)
    }

    @Test
    func observedSmallerUserSizeInvalidatesOnlyItsOldMinimum() throws {
        let h = try Refusal043Harness()
        defer { h.cleanup() }
        h.learnMinimum()
        #expect(h.repairCount == 1)
        h.writer.minimums.removeAll()
        h.clock.advance(0.2)
        try h.resize(1, to: Rect(x: 0, y: 0, width: 400, height: 800))
        _ = h.maintainer.tick(cause: "drag")

        #expect(h.frame(1)?.width == 400)
        #expect(h.frame(2)?.x == 400)
        #expect(h.repairCount == 1)
    }

    @Test
    func newGenerationDuringReadCancelsObsoleteTreeWrites() throws {
        let h = try Refusal043Harness()
        defer { h.cleanup() }
        h.writer.minimums[WindowID(rawValue: 1)] = CGSize(width: 700, height: 0)
        _ = h.maintainer.tick(cause: "command:startup")
        let old = try #require(h.registry.entry(for: 1))
        let delayed = try #require(old.readBack)
        let attempts = h.writer.attempts
        h.clock.onRead = {
            h.clock.onRead = nil
            h.registry.record(windowID: 1, requested: CGRect(x: 0, y: 0, width: 400, height: 800),
                readBack: delayed, generation: h.generations.next(), at: h.clock.now)
            return delayed
        }
        h.clock.advance(LayoutTolerance.refusalConfirmDelay)
        _ = h.maintainer.tick(cause: "deadline")

        #expect(h.writer.attempts == attempts)
        #expect(h.registry.entry(for: 1)?.requested.width == 400)
        #expect(h.registry.entry(for: 1)?.generation == h.generations.current)
        #expect(h.registry.entry(for: 1)?.refusalConfirmedAt == nil)
    }

    @Test(arguments: [false, true])
    func identityChangeDoesNotReuseLearnedMinimum(changeBundle: Bool) throws {
        let h = try Refusal043Harness()
        defer { h.cleanup() }
        h.learnMinimum()
        h.writer.minimums.removeAll()
        if changeBundle {
            h.provider.snapshots[0].bundleID = "app.replacement"
        } else {
            h.provider.snapshots[0].pid += 1000
        }
        h.clock.advance(0.2)
        _ = h.maintainer.tick(cause: "safety")
        try h.resize(2, to: Rect(x: 400, y: 0, width: 600, height: 800))
        _ = h.maintainer.tick(cause: "drag")

        #expect(h.frame(1)?.width == 400)
        #expect(h.frame(2)?.x == 400)
    }

    @Test
    func validNeighborMinimumStillBoundsFreshGesture() throws {
        let h = try Refusal043Harness()
        defer { h.cleanup() }
        h.learnMinimum()
        let writes = h.writer.base.frameHistory[WindowID(rawValue: 1)]?.count
        h.clock.advance(0.2)
        try h.resize(2, to: Rect(x: 400, y: 0, width: 600, height: 800))
        _ = h.maintainer.tick(cause: "drag")

        #expect(h.frame(1)?.width == 700)
        #expect(h.frame(2)?.x == 700)
        #expect(h.writer.base.frameHistory[WindowID(rawValue: 1)]?.count == writes)
    }

    @Test
    func movedStageDoesNotReuseMinimumFromPreviousScope() throws {
        let h = try Refusal043Harness()
        defer { h.cleanup() }
        h.learnMinimum()
        h.writer.minimums.removeAll()
        h.store.mutate { state in
            state.scopes[0].stages[0].id = StageID(rawValue: "2")
            state.scopes[0].activeStageID = StageID(rawValue: "2")
        }
        h.clock.advance(0.2)
        try h.resize(2, to: Rect(x: 400, y: 0, width: 600, height: 800))
        _ = h.maintainer.tick(cause: "drag")

        #expect(h.frame(1)?.width == 400)
        #expect(h.frame(2)?.x == 400)
        #expect(h.repairCount == 1)
    }

    @Test
    func oldConfirmedRefusalDoesNotRearmDeadlineInNewGeneration() throws {
        let h = try Refusal043Harness()
        defer { h.cleanup() }
        h.learnMinimum()
        h.clock.advance(0.2)
        _ = h.maintainer.tick(cause: "deadline")
        _ = h.generations.next()

        let deadline = h.maintainer.nextDeadline(now: h.clock.now)
        #expect(deadline.map { $0 > h.clock.now } ?? true)
    }

    @Test
    func nativeFullscreenDoesNotApplyPendingMinimumCorrection() throws {
        let h = try Refusal043Harness()
        defer { h.cleanup() }
        h.writer.minimums[WindowID(rawValue: 1)] = CGSize(width: 700, height: 0)
        _ = h.maintainer.tick(cause: "command:startup")
        h.provider.snapshots[0].furniture = WindowFurniture(hasCloseButton: true,
            hasFullscreenButton: true, fullscreenButtonEnabled: true, hasMinimizeButton: true,
            hasZoomButton: true, isNativeFullscreen: true)
        h.setFrame(1, Rect(x: 0, y: 0, width: 1000, height: 800))
        h.clock.advance(LayoutTolerance.refusalConfirmDelay)
        _ = h.maintainer.tick(cause: "ax:AXWindowResized")

        #expect(h.store.state().bspTree(for: h.scope) == h.tree)
        #expect(h.frame(1) == Rect(x: 0, y: 0, width: 1000, height: 800))
        #expect(h.repairCount == 0)
    }

    @Test(arguments: [false, true])
    func repeatedRefusalsStayWithinSameGenerationBudget(fourWindows: Bool) throws {
        let h = try Refusal043Harness(fourWindows: fourWindows)
        defer { h.cleanup() }
        h.writer.minimums[WindowID(rawValue: 1)] = CGSize(width: 700, height: 0)
        h.writer.minimums[WindowID(rawValue: fourWindows ? 3 : 2)] = CGSize(width: 450, height: 0)
        _ = h.maintainer.tick(cause: "command:startup")
        let generation = h.generations.current
        for _ in 0..<4 {
            h.clock.advance(LayoutTolerance.refusalConfirmDelay)
            _ = h.maintainer.tick(cause: "deadline")
        }
        let writes = h.writer.attempts
        let repairs = h.repairCount
        for _ in 0..<4 {
            h.clock.advance(1)
            #expect(h.maintainer.tick(cause: "safety").commands == 0)
        }

        #expect(h.generations.current == generation)
        #expect(h.writer.attempts == writes)
        #expect(h.repairCount == repairs)
        #expect(h.writer.attempts[generation]?.values.allSatisfy { $0 <= LayoutTolerance.writeBudgetPerGeneration } == true)
    }

    @Test
    func pressedMouseKeepsRefusalPendingUntilRelease() throws {
        let h = try Refusal043Harness()
        defer { h.cleanup() }
        h.writer.minimums[WindowID(rawValue: 1)] = CGSize(width: 700, height: 0)
        _ = h.maintainer.tick(cause: "command:startup")
        h.clock.mouseDown = true
        h.clock.advance(LayoutTolerance.refusalConfirmDelay)
        #expect(h.maintainer.tick(cause: "ax:AXWindowResized").commands == 0)
        #expect(h.registry.entry(for: 1)?.refusalConfirmedAt == nil)
        h.clock.mouseDown = false
        _ = h.maintainer.tick(cause: "deadline")
        #expect(h.repairCount == 1)
    }
}
