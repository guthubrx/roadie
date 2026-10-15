import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieTiler
@testable import RoadieDaemon

@Suite
struct Spec029RestorationRetryTests {
    @Test(arguments: [WindowManagementMode.float, .spatialBsp])
    func unchangedFailedRestoreAndHideStopRetrying(mode: WindowManagementMode) throws {
        let harness = try RestorationRetryHarness(mode: mode)
        let originalMembership = harness.store.state().scopes.first?.stages.map { ($0.id, $0.members.map(\.windowID)) }
        let first = harness.maintainer.tick(cause: "safety")
        #expect(first.failed == 2)
        for index in 1...24 {
            harness.clock.date = harness.clock.date.addingTimeInterval(0.15)
            _ = harness.maintainer.tick(cause: index.isMultiple(of: 3) ? "safety" : "deadline")
        }
        // Dépasser deux expirations de la mémoire legacy : elles ne sont pas de nouvelles intentions.
        for elapsed in [31.0, 62.0] {
            harness.clock.date = Date(timeIntervalSince1970: 1_000 + elapsed)
            for cause in ["safety", "deadline", "ax:AXWindowMoved", "deadline"] {
                _ = harness.maintainer.tick(cause: cause)
            }
        }
        for id in harness.world.frames.keys {
            #expect(harness.world.attempts[id, default: []].count <= LayoutTolerance.writeBudgetPerGeneration)
        }
        #expect(harness.maintainer.nextDeadline(now: harness.clock.date).map { $0 > harness.clock.date } ?? true)
        let finalMembership = harness.store.state().scopes.first?.stages.map { ($0.id, $0.members.map(\.windowID)) }
        #expect(finalMembership?.map(\.0) == originalMembership?.map(\.0))
        #expect(finalMembership?.map(\.1) == originalMembership?.map(\.1))
        #expect(harness.world.frames[RestorationRetryHarness.activeID] == harness.initialActive)
        #expect(harness.world.frames[RestorationRetryHarness.inactiveID] == harness.initialInactive)
    }

    @Test(arguments: [WindowManagementMode.float, .spatialBsp])
    func healthyWindowStillMovesWhileItsNeighborRefusesRestoration(mode: WindowManagementMode) throws {
        let harness = try RestorationRetryHarness(mode: mode)
        let healthyID = RestorationRetryHarness.inactiveID
        harness.world.writableIDs.insert(healthyID)
        let first = harness.maintainer.tick(cause: "safety")
        #expect(first.failed == 1)
        #expect(HiddenWindowPlacement.isHidden(try #require(harness.world.frames[healthyID]).cgRect, in: [harness.world.display]))
        let before = harness.world.attempts[healthyID, default: []].count

        // L'application saine revient à l'écran : son masquage reste immédiat malgré le refus voisin.
        harness.world.frames[healthyID] = Rect(x: 240, y: 120, width: 360, height: 240)
        harness.clock.date = harness.clock.date.addingTimeInterval(0.5)
        _ = harness.maintainer.tick(cause: "ax:AXWindowMoved")
        #expect(harness.world.attempts[healthyID, default: []].count > before)
        #expect(HiddenWindowPlacement.isHidden(try #require(harness.world.frames[healthyID]).cgRect, in: [harness.world.display]))
        #expect(harness.world.attempts[RestorationRetryHarness.activeID, default: []].count <= LayoutTolerance.writeBudgetPerGeneration)
    }

    @Test(arguments: [WindowManagementMode.float, .spatialBsp])
    func unchangedAXEchoesDoNotRenewRestorationAttempts(mode: WindowManagementMode) throws {
        let harness = try RestorationRetryHarness(mode: mode)
        _ = harness.maintainer.tick(cause: "safety")
        for _ in 0..<20 {
            harness.clock.date = harness.clock.date.addingTimeInterval(0.15)
            _ = harness.maintainer.tick(cause: "ax:AXWindowMoved")
        }
        #expect(harness.world.attempts.values.allSatisfy { $0.count <= LayoutTolerance.writeBudgetPerGeneration })
    }

    @Test(arguments: [WindowManagementMode.float, .spatialBsp])
    func changedGeometryAllowsARealNewRestorationAttempt(mode: WindowManagementMode) throws {
        let harness = try RestorationRetryHarness(mode: mode)
        harness.exhaustAttempts()
        let before = harness.world.attempts[RestorationRetryHarness.inactiveID, default: []].count
        harness.world.frames[RestorationRetryHarness.inactiveID]?.width += 80
        harness.world.acceptWrites = true
        harness.clock.date = harness.clock.date.addingTimeInterval(0.5)
        _ = harness.maintainer.tick(cause: "ax:AXWindowResized")
        #expect(harness.world.attempts[RestorationRetryHarness.inactiveID, default: []].count > before)
        #expect(HiddenWindowPlacement.isHidden(try #require(harness.world.frames[RestorationRetryHarness.inactiveID]).cgRect, in: [harness.world.display]))
    }

    @Test(arguments: [WindowManagementMode.float, .spatialBsp])
    func explicitNewCommandAllowsRestorationAfterFailure(mode: WindowManagementMode) throws {
        let harness = try RestorationRetryHarness(mode: mode)
        harness.exhaustAttempts()
        let before = harness.world.attempts[RestorationRetryHarness.inactiveID, default: []].count
        let activeBefore = harness.world.attempts[RestorationRetryHarness.activeID, default: []].count
        harness.world.acceptWrites = true
        harness.clock.date = harness.clock.date.addingTimeInterval(0.5)
        _ = harness.maintainer.tick(cause: "command:stage.restore")
        #expect(harness.world.attempts[RestorationRetryHarness.inactiveID, default: []].count > before)
        #expect(harness.world.attempts[RestorationRetryHarness.activeID, default: []].count > activeBefore)
        #expect(HiddenWindowPlacement.isHidden(try #require(harness.world.frames[RestorationRetryHarness.inactiveID]).cgRect, in: [harness.world.display]))
    }

    @Test(arguments: [WindowManagementMode.float, .spatialBsp])
    func recycledWindowIdentifierDoesNotInheritRestorationFailure(mode: WindowManagementMode) throws {
        let harness = try RestorationRetryHarness(mode: mode)
        harness.exhaustAttempts()
        let before = harness.world.attempts[RestorationRetryHarness.inactiveID, default: []].count
        let activeBefore = harness.world.attempts[RestorationRetryHarness.activeID, default: []].count
        harness.world.pidOverrides[RestorationRetryHarness.inactiveID] = 4_902
        harness.world.pidOverrides[RestorationRetryHarness.activeID] = 4_901
        harness.world.acceptWrites = true
        harness.clock.date = harness.clock.date.addingTimeInterval(0.5)
        _ = harness.maintainer.tick(cause: "safety")
        #expect(harness.world.attempts[RestorationRetryHarness.inactiveID, default: []].count > before)
        #expect(harness.world.attempts[RestorationRetryHarness.activeID, default: []].count > activeBefore)
    }

    @Test(arguments: [WindowManagementMode.float, .spatialBsp])
    func confirmedNewActivationRetriesOnceButDuplicateActivationsDoNot(mode: WindowManagementMode) throws {
        let harness = try RestorationRetryHarness(mode: mode)
        harness.exhaustAttempts()
        let before = harness.world.attempts[RestorationRetryHarness.activeID, default: []].count
        harness.clock.date = harness.clock.date.addingTimeInterval(0.5)
        _ = harness.maintainer.tick(cause: "ax:didActivateApplication")
        let afterActivation = harness.world.attempts[RestorationRetryHarness.activeID, default: []].count
        #expect(afterActivation > before)
        for _ in 0..<12 {
            harness.clock.date = harness.clock.date.addingTimeInterval(0.2)
            _ = harness.maintainer.tick(cause: "ax:didActivateApplication")
        }
        #expect(harness.world.attempts[RestorationRetryHarness.activeID, default: []].count == afterActivation)
        harness.world.focused = nil
        _ = harness.maintainer.tick(cause: "ax:AXFocusedWindowChanged")
        harness.world.focused = RestorationRetryHarness.activeID
        harness.world.acceptWrites = true
        _ = harness.maintainer.tick(cause: "ax:AXFocusedWindowChanged")
        #expect(harness.world.attempts[RestorationRetryHarness.activeID, default: []].count > afterActivation)
    }

    @Test(arguments: [WindowManagementMode.float, .spatialBsp], [true, false])
    func partiallyFailedRestorationStaysWithinBudget(mode: WindowManagementMode, readable: Bool) throws {
        let harness = try RestorationRetryHarness(mode: mode)
        harness.world.readable = readable
        harness.world.partialFailureGrowth = 20
        _ = harness.maintainer.tick(cause: "safety")
        for index in 1...24 {
            harness.clock.date = harness.clock.date.addingTimeInterval(0.15)
            _ = harness.maintainer.tick(cause: index.isMultiple(of: 3) ? "ax:AXWindowMoved" : "deadline")
        }
        let activeAttempts = harness.world.attempts[RestorationRetryHarness.activeID, default: []].count
        #expect(activeAttempts > 0)
        #expect(activeAttempts <= LayoutTolerance.writeBudgetPerGeneration)
        #expect(harness.world.attempts[RestorationRetryHarness.inactiveID, default: []].count <= LayoutTolerance.writeBudgetPerGeneration)
        #expect(harness.maintainer.nextDeadline(now: harness.clock.date).map { $0 > harness.clock.date } ?? true)

        // Une vraie activation permet de reprendre même si le refus partiel a épuisé le budget.
        harness.world.acceptWrites = true
        harness.clock.date = harness.clock.date.addingTimeInterval(0.5)
        _ = harness.maintainer.tick(cause: "ax:didActivateApplication")
        #expect(harness.world.attempts[RestorationRetryHarness.activeID, default: []].count > activeAttempts)
        #expect(!HiddenWindowPlacement.isHidden(try #require(harness.world.frames[RestorationRetryHarness.activeID]).cgRect, in: [harness.world.display]))
    }

    @Test(arguments: [WindowManagementMode.float, .spatialBsp])
    func delayedPartialResponseAfterReadBackKeepsItsRestorationBudget(mode: WindowManagementMode) throws {
        let harness = try RestorationRetryHarness(mode: mode)
        harness.world.deferredResponseFraction = 0.2
        _ = harness.maintainer.tick(cause: "safety")
        // L'échec et sa relecture ont eu lieu. Le déplacement n'est pas encore publié.
        #expect(harness.world.frames[RestorationRetryHarness.activeID] == harness.initialActive)
        #expect(!harness.world.deferredResponses.isEmpty)
        for index in 1...24 {
            harness.clock.date = harness.clock.date.addingTimeInterval(0.15)
            _ = harness.maintainer.tick(cause: index.isMultiple(of: 3) ? "ax:AXWindowMoved" : "deadline")
        }
        #expect(harness.world.publishedDeferredResponses > 0)
        for id in [RestorationRetryHarness.activeID, RestorationRetryHarness.inactiveID] {
            #expect(harness.world.attempts[id, default: []].count <= LayoutTolerance.writeBudgetPerGeneration)
        }
        #expect(harness.maintainer.nextDeadline(now: harness.clock.date).map { $0 > harness.clock.date } ?? true)

        let before = harness.world.attempts[RestorationRetryHarness.inactiveID, default: []].count
        harness.world.acceptWrites = true
        _ = harness.maintainer.tick(cause: "command:stage.restore")
        #expect(harness.world.attempts[RestorationRetryHarness.inactiveID, default: []].count > before)
        #expect(HiddenWindowPlacement.isHidden(try #require(harness.world.frames[RestorationRetryHarness.inactiveID]).cgRect, in: [harness.world.display]))
    }

    @Test(arguments: [WindowManagementMode.float, .spatialBsp])
    func explicitConfigurationChangeAllowsRestorationAfterFailure(mode: WindowManagementMode) throws {
        let harness = try RestorationRetryHarness(mode: mode)
        harness.exhaustAttempts()
        let before = harness.world.attempts[RestorationRetryHarness.activeID, default: []].count
        harness.world.acceptWrites = true
        harness.maintainer.configurationChanged(invalidateLayoutIntents: true)
        harness.clock.date = harness.clock.date.addingTimeInterval(0.5)
        _ = harness.maintainer.tick(cause: "command:config.reload")
        #expect(harness.world.attempts[RestorationRetryHarness.activeID, default: []].count > before)
        #expect(!HiddenWindowPlacement.isHidden(try #require(harness.world.frames[RestorationRetryHarness.activeID]).cgRect, in: [harness.world.display]))
    }
}

private final class RestorationRetryClock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_000)
}

private final class RestorationRetryHarness {
    static let activeID = WindowID(rawValue: 901)
    static let inactiveID = WindowID(rawValue: 902)
    let directory: URL
    let world: RestorationRetryWorld
    let store: StageStore
    let maintainer: LayoutMaintainer
    let clock = RestorationRetryClock()
    let initialActive = Rect(x: 999, y: 799, width: 300, height: 240)
    let initialInactive = Rect(x: 200, y: 100, width: 320, height: 240)

    init(mode: WindowManagementMode) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-spec029-retry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let world = RestorationRetryWorld(frames: [Self.activeID: initialActive, Self.inactiveID: initialInactive])
        self.world = world
        store = StageStore(path: directory.appendingPathComponent("stages.json").path)
        let member = { (id: WindowID, frame: Rect) in
            PersistentStageMember(windowID: id, bundleID: "test.restore.\(id.rawValue)", title: "Test \(id.rawValue)", frame: frame)
        }
        store.save(PersistentStageState(scopes: [PersistentStageScope(
            displayID: world.display.id,
            activeStageID: StageID(rawValue: "1"),
            stages: [
                PersistentStage(id: StageID(rawValue: "1"), mode: mode, focusedWindowID: Self.activeID,
                    members: [member(Self.activeID, initialActive)], bspTree: mode == .spatialBsp ? .leaf(Self.activeID) : nil),
                PersistentStage(id: StageID(rawValue: "2"), mode: mode, members: [member(Self.inactiveID, initialInactive)])
            ]
        )], activeDisplayID: world.display.id))
        let clock = clock
        let replay = ReplayableSnapshotProvider(base: world)
        let registry = WrittenFrameRegistry()
        let service = SnapshotService(provider: replay, frameWriter: world,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: mode, gapsOuter: 0, gapsInner: 0)),
            railRuntimeStateStore: RailRuntimeStateStore(path: directory.appendingPathComponent("rail.json").path),
            intentStore: LayoutIntentStore(path: directory.appendingPathComponent("intents.json").path),
            stageStore: store, events: EventLog(path: directory.appendingPathComponent("service-events.jsonl").path),
            clock: { clock.date }, frameRegistry: registry, treeScopeApplications: TreeScopeApplicationCenter())
        let episodes = EpisodeContext(now: { clock.date })
        maintainer = LayoutMaintainer(service: service, scanReplay: replay,
            events: EventLog(path: directory.appendingPathComponent("events.jsonl").path, episodes: episodes),
            store: store, dragActivity: WindowDragActivity(enabled: false), commandActivity: LayoutCommandActivity(enabled: false),
            mouseButtonsPressed: { false }, writtenFrames: registry, generations: PlacementGeneration(),
            takeGesture: { nil }, spaceProbe: { _ in true },
            readFrame: { world.readable ? world.frames[$0.id]?.cgRect : nil }, episodes: episodes, now: { clock.date })
    }

    func exhaustAttempts() {
        _ = maintainer.tick(cause: "safety")
        for _ in 0..<4 {
            clock.date = clock.date.addingTimeInterval(0.2)
            _ = maintainer.tick(cause: "deadline")
        }
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}

private final class RestorationRetryWorld: SystemSnapshotProviding, WindowFrameWriting, @unchecked Sendable {
    let display = DisplaySnapshot(id: DisplayID(rawValue: "spec029-retry"), index: 1, name: "Test",
        frame: Rect(x: 0, y: 0, width: 1000, height: 800), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 800), isMain: true)
    var frames: [WindowID: Rect]
    var attempts: [WindowID: [Rect]] = [:]
    var pidOverrides: [WindowID: Int32] = [:]
    var acceptWrites = false
    var writableIDs: Set<WindowID> = []
    var readable = true
    var partialFailureGrowth: Double = 0
    var deferredResponseFraction: Double = 0
    var deferredResponses: [WindowID: Rect] = [:]
    var publishedDeferredResponses = 0
    var focused: WindowID? = RestorationRetryHarness.activeID
    init(frames: [WindowID: Rect]) { self.frames = frames }
    func permissions(prompt: Bool) -> PermissionSnapshot { PermissionSnapshot(accessibilityTrusted: true) }
    func displays() -> [DisplaySnapshot] { [display] }
    func focusedWindowID() -> WindowID? { focused }
    func windows() -> [WindowSnapshot] {
        for (id, response) in deferredResponses {
            frames[id] = response
            publishedDeferredResponses += 1
        }
        deferredResponses.removeAll()
        return frames.keys.sorted().map { id in
            WindowSnapshot(id: id, pid: pidOverrides[id] ?? Int32(id.rawValue), appName: "Test", bundleID: "test.restore.\(id.rawValue)",
                title: "Test \(id.rawValue)", frame: frames[id]!, isOnScreen: true, isTileCandidate: true)
        }
    }
    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        attempts[window.id, default: []].append(Rect(frame))
        guard acceptWrites || writableIDs.contains(window.id) else {
            // L'appel AX a modifié la taille, puis échoué : aucun résultat utilisable n'est renvoyé.
            if partialFailureGrowth != 0 { frames[window.id]?.width += partialFailureGrowth }
            if deferredResponseFraction > 0, let current = frames[window.id] {
                let fraction = deferredResponseFraction
                deferredResponses[window.id] = Rect(
                    x: current.x + (frame.minX - current.x) * fraction,
                    y: current.y + (frame.minY - current.y) * fraction,
                    width: current.width + (frame.width - current.width) * fraction,
                    height: current.height + (frame.height - current.height) * fraction
                )
            }
            return nil
        }
        frames[window.id] = Rect(frame)
        return frame
    }
}
