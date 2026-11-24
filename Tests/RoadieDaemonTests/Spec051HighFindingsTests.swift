import Darwin
import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

/// SPEC-051 : constats HIGH restants de l'audit performance.
@Suite
struct Spec051HighFindingsTests {
    @Test func disabledFocusFollowsMouseWakesOncePerSecond() {
        #expect(FocusFollowsMouseController.timerInterval(enabled: true) == 0.1)
        #expect(FocusFollowsMouseController.timerInterval(enabled: false) == 1)
    }

    @Test func generatedRulesPathIsMemoizedWithTheSameValue() {
        let path = "/tmp/roadie-051/roadies.toml"
        #expect(ConfigReloadService.generatedRulesPath(for: path) == RoadieConfigLoader.generatedRulesPath(for: path))
        #expect(ConfigReloadService.stamp(for: path).count == 2)
    }

    @Test func clickOutsideAManagedTitleBandStartsNoDragContext() {
        let frames = [CGRect(x: 100, y: 50, width: 600, height: 400)]
        #expect(RailController.clickMayStartWindowDrag(atAXPoint: CGPoint(x: 300, y: 60), frames: frames))
        #expect(RailController.clickMayStartWindowDrag(atAXPoint: CGPoint(x: 300, y: 92), frames: frames))
        #expect(!RailController.clickMayStartWindowDrag(atAXPoint: CGPoint(x: 300, y: 300), frames: frames))
        #expect(!RailController.clickMayStartWindowDrag(atAXPoint: CGPoint(x: 900, y: 60), frames: frames))
        #expect(!RailController.clickMayStartWindowDrag(atAXPoint: CGPoint(x: 300, y: 60), frames: []))
    }

    /// B-01 : un relevé sans changement d'état ne prend pas le verrou exclusif de `stages.json`.
    @Test func unchangedSnapshotDoesNotWaitForTheStateLock() async throws {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100)])
        let store = StageStore(path: tempPath("spec051-lock-stages"))
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider),
                                      config: RoadieConfig(), intentStore: LayoutIntentStore(path: tempPath("spec051-lock-intents")),
                                      stageStore: store, events: EventLog(path: tempPath("spec051-lock-events")),
                                      persistStateChanges: true)
        _ = service.snapshot()
        _ = service.snapshot()

        let lockPath = FileLock.lockPath(for: store.fileURL)
        let fd = open(lockPath, O_RDWR | O_CREAT, 0o644)
        try #require(fd >= 0)
        #expect(flock(fd, LOCK_SH) == 0)
        let done = FlagBox()
        Thread.detachNewThread {
            _ = service.snapshot()
            done.set()
        }
        var waited = 0
        while !done.value, waited < 100 { usleep(10_000); waited += 1 }
        let finishedWhileLocked = done.value
        flock(fd, LOCK_UN)
        close(fd)
        while !done.value { usleep(10_000) }
        #expect(finishedWhileLocked)
    }

    /// Lot C : un minimum confirmé (Spec043) ajuste immédiatement la coupe lors de l'insertion d'une nouvelle
    /// fenêtre dans le même scope, sans violer les gardes d'identité (`pid`/`bundleID`) ni de scope.
    @Test func confirmedMinimumAdjustsNewInsertionSplitAndRespectsIdentityAndDestroy() throws {
        let w1 = powerWindow(1, x: 0)
        let w2 = powerWindow(2, x: 500)
        let provider = PowerUserProvider(windows: [w1])
        let clockBox = ClockBox(Date(timeIntervalSince1970: 1_700_000_000))
        var config = RoadieConfig()
        config.tiling.defaultStrategy = .spatialBsp
        config.tiling.gapsOuter = 0
        config.tiling.gapsInner = 0
        let store = StageStore(path: tempPath("lot-c-min-stages"))
        let service = SnapshotService(
            provider: provider,
            frameWriter: PowerUserWriter(provider: provider),
            config: config,
            intentStore: LayoutIntentStore(path: tempPath("lot-c-min-intents")),
            stageStore: store,
            events: EventLog(path: tempPath("lot-c-min-events")),
            persistStateChanges: true,
            clock: { clockBox.now }
        )
        let snap1 = service.snapshot()
        let scope = try #require(snap1.windows.first?.scope)
        service.syncConfirmedMinimums([
            w1.id: SnapshotProcessState.ConfirmedMinimum(
                pid: w1.pid, bundleID: w1.bundleID, scope: scope, size: CGSize(width: 900, height: 0)
            )
        ])

        // Une nouvelle fenêtre rejoint le même scope : la coupe respecte déjà les 900 px confirmés de w1.
        provider.snapshots = [w1, w2]
        let snap2 = service.snapshot()
        let plan2 = service.layoutPlan(from: snap2, scope: scope, orderedWindowIDs: [w1.id, w2.id])
        let firstW1 = try #require(plan2.placements[w1.id])
        let firstW2 = try #require(plan2.placements[w2.id])
        #expect(firstW1.width >= 900)
        #expect(firstW1.width + firstW2.width == snap2.displays[0].visibleFrame.cgRect.width)

        // Après destruction confirmée de w1, son minimum est purgé de `processState` : une nouvelle
        // insertion réelle impliquant le même identifiant (réutilisé par macOS) repart sur 50/50.
        service.noteWindowDestroyed(w1.id)
        provider.snapshots = []
        _ = service.snapshot()
        clockBox.advance(by: 30)
        provider.snapshots = [w1]
        let snapReborn = service.snapshot()
        let rebornScope = try #require(snapReborn.windows.first?.scope)
        provider.snapshots = [w1, w2]
        let snap3 = service.snapshot()
        let plan3 = service.layoutPlan(from: snap3, scope: rebornScope, orderedWindowIDs: [w1.id, w2.id])
        let fallbackW1 = try #require(plan3.placements[w1.id])
        #expect(fallbackW1.width < 900)
    }

    /// Lot C : `reconcileTrees` applique les marges extérieures (`outerGaps`) lors de la correction
    /// prédictive de coupe, afin que le placement final après `outerGaps` atteigne bien le minimum.
    @Test func confirmedMinimumAccountsForOuterGapsOnNewInsertion() throws {
        let w1 = powerWindow(10, x: 0)
        let w2 = powerWindow(11, x: 500)
        let provider = PowerUserProvider(windows: [w1])
        var config = RoadieConfig()
        config.tiling.defaultStrategy = .spatialBsp
        config.tiling.gapsOuter = 20
        config.tiling.gapsInner = 10
        let service = SnapshotService(
            provider: provider,
            frameWriter: PowerUserWriter(provider: provider),
            config: config,
            intentStore: LayoutIntentStore(path: tempPath("lot-c-outer-intents")),
            stageStore: StageStore(path: tempPath("lot-c-outer-stages")),
            events: EventLog(path: tempPath("lot-c-outer-events")),
            persistStateChanges: true
        )
        let snap1 = service.snapshot()
        let scope = try #require(snap1.windows.first?.scope)
        service.syncConfirmedMinimums([
            w1.id: SnapshotProcessState.ConfirmedMinimum(
                pid: w1.pid, bundleID: w1.bundleID, scope: scope, size: CGSize(width: 900, height: 0)
            )
        ])

        provider.snapshots = [w1, w2]
        let snap2 = service.snapshot()
        let plan2 = service.layoutPlan(from: snap2, scope: scope, orderedWindowIDs: [w1.id, w2.id])
        let placedW1 = try #require(plan2.placements[w1.id])
        let placedW2 = try #require(plan2.placements[w2.id])
        let containerWidth = try #require(service.treeContainer(for: scope, in: snap2)).width
        #expect(containerWidth < snap2.displays[0].visibleFrame.cgRect.width)
        #expect(placedW1.width >= 900)
        #expect(placedW1.width + placedW2.width + 10 == containerWidth)
    }

    /// Lot C : un minimum confirmé réalisable au-delà du plafond de ratio 0,95 (ex. 980 / 1000)
    /// est honoré aussi bien par `layoutPlan` réel (via `SizedTree`) que par `previewPlacements`.
    @Test func confirmedMinimumBeyondRatioCapMatchesBetweenLayoutPlanAndPreview() throws {
        let w1 = powerWindow(20, x: 0)
        let w2 = powerWindow(21, x: 500)
        let provider = PowerUserProvider(windows: [w1])
        var config = RoadieConfig()
        config.tiling.defaultStrategy = .spatialBsp
        config.tiling.gapsOuter = 0
        config.tiling.gapsInner = 0
        let service = SnapshotService(
            provider: provider,
            frameWriter: PowerUserWriter(provider: provider),
            config: config,
            intentStore: LayoutIntentStore(path: tempPath("lot-c-cap-intents")),
            stageStore: StageStore(path: tempPath("lot-c-cap-stages")),
            events: EventLog(path: tempPath("lot-c-cap-events")),
            persistStateChanges: true
        )
        let snap1 = service.snapshot()
        let scope = try #require(snap1.windows.first?.scope)
        service.syncConfirmedMinimums([
            w1.id: SnapshotProcessState.ConfirmedMinimum(
                pid: w1.pid, bundleID: w1.bundleID, scope: scope, size: CGSize(width: 980, height: 0)
            )
        ])

        let preview = service.previewPlacements(scope: scope, incoming: w2.id, in: snap1)
        #expect(preview[w1.id]?.width == 980)
        #expect(preview[w2.id]?.width == 20)

        provider.snapshots = [w1, w2]
        let snap2 = service.snapshot()
        let plan2 = service.layoutPlan(from: snap2, scope: scope, orderedWindowIDs: [w1.id, w2.id])
        #expect(plan2.placements[w1.id]?.width == 980)
        #expect(plan2.placements[w2.id]?.width == 20)
    }

    /// Lot D : un glisser ordinaire hors barre de titre (`hasCandidateWindow == false`) ne déclenche
    /// aucun événement `drag.real_unprepared`.
    @Test func unpreparedDragIsReportedOnlyWhenPressTargetedACandidateWindow() {
        #expect(!WindowDragReorderController.shouldReportUnpreparedDrag(nativeMovementPassed: false, hasCandidateWindow: false))
        #expect(WindowDragReorderController.shouldReportUnpreparedDrag(nativeMovementPassed: false, hasCandidateWindow: true))
        #expect(!WindowDragReorderController.shouldReportUnpreparedDrag(nativeMovementPassed: true, hasCandidateWindow: true))
    }
}

/// Drapeau partagé entre le test et le fil du relevé.
private final class FlagBox: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.withLock { flag } }
    func set() { lock.withLock { flag = true } }
}

private final class ClockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ initial: Date) { self.current = initial }
    var now: Date { lock.withLock { current } }
    func advance(by seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}
