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
}

/// Drapeau partagé entre le test et le fil du relevé.
private final class FlagBox: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.withLock { flag } }
    func set() { lock.withLock { flag = true } }
}
