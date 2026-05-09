import Foundation
import Testing
import RoadieDaemon

@Suite
struct RestoreSafetyServiceTests {
    @Test
    func writesStatusAndAppliesManualSnapshot() throws {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100)])
        let writer = PowerUserWriter(provider: provider)
        let stageStore = StageStore(path: tempPath("restore-safety-stage"))
        let snapshotService = SnapshotService(provider: provider, frameWriter: writer, stageStore: stageStore)
        _ = snapshotService.snapshot()

        let restorePath = tempPath("restore-safety")
        defer { try? FileManager.default.removeItem(atPath: restorePath) }
        let service = RestoreSafetyService(path: restorePath, service: snapshotService)

        let snapshot = try service.writeSnapshot()
        provider.snapshots[0].frame.x = 400
        let status = service.status()
        let result = try service.apply()

        #expect(snapshot.windows.count == 1)
        #expect(status.exists)
        #expect(status.windowCount == 1)
        #expect(result.applied == 1)
        #expect(writer.frames[provider.snapshots[0].id]?.x == 100)
    }

    @Test
    func cleanExitMarkerPreventsCrashRestore() throws {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100)])
        let snapshotService = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider))
        let restorePath = tempPath("restore-marker")
        let markerPath = tempPath("restore-marker-run")
        defer {
            try? FileManager.default.removeItem(atPath: restorePath)
            try? FileManager.default.removeItem(atPath: markerPath)
        }
        let service = RestoreSafetyService(path: restorePath, markerPath: markerPath, service: snapshotService)

        _ = try service.markRunStarted(pid: 42)
        #expect(service.shouldRestoreAfterProcessExit(pid: 42))

        let marker = try service.markCleanExit(pid: 42)
        #expect(marker.cleanExit)
        #expect(!service.shouldRestoreAfterProcessExit(pid: 42))
    }
}
