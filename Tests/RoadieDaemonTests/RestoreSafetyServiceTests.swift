import Foundation
import Testing
import RoadieAX
import RoadieCore
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

/// SPEC-016 T068 : restauration des fenêtres masquées et verrou d'instance.
@Suite
struct RestoreSafetyLifecycleTests {
    private let stage1 = StageID(rawValue: "1")
    private let stage2 = StageID(rawValue: "2")
    // Écran 0..1000 : la frame de masquage est au bord droit (x = 999).
    private let hiddenFrame = Rect(x: 999, y: 100, width: 300, height: 300)
    private let visibleFrame = Rect(x: 400, y: 100, width: 300, height: 300)

    private struct Fixture {
        let provider: PowerUserProvider
        let writer: PowerUserWriter
        let service: RestoreSafetyService
        let paths: [String]
    }

    /// Fenêtre 1 visible dans la stage active, fenêtre 2 masquée dans une stage inactive dont
    /// le membre garde la dernière frame visible.
    private func makeFixture() -> Fixture {
        let display = powerDisplay()
        var hidden = powerWindow(2, x: hiddenFrame.x)
        hidden.frame = hiddenFrame
        let provider = PowerUserProvider(displays: [display], windows: [powerWindow(1, x: 0), hidden])
        let writer = PowerUserWriter(provider: provider)
        let stagePath = tempPath("restore-lifecycle-stage")
        let restorePath = tempPath("restore-lifecycle")
        let markerPath = tempPath("restore-lifecycle-run")
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display.id, activeStageID: stage1, stages: [
                PersistentStage(id: stage1, members: [
                    PersistentStageMember(windowID: WindowID(rawValue: 1), bundleID: "app.1", title: "Window 1", frame: provider.snapshots[0].frame)
                ]),
                PersistentStage(id: stage2, members: [
                    PersistentStageMember(windowID: WindowID(rawValue: 2), bundleID: "app.2", title: "Window 2", frame: visibleFrame)
                ])
            ])
        ], activeDisplayID: display.id))
        let eventsPath = tempPath("restore-lifecycle-events")
        let events = EventLog(path: eventsPath)
        let snapshotService = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(),
            intentStore: LayoutIntentStore(path: tempPath("restore-lifecycle-intent")),
            stageStore: stageStore,
            events: events
        )
        let service = RestoreSafetyService(path: restorePath, markerPath: markerPath, service: snapshotService, eventLog: events)
        return Fixture(provider: provider, writer: writer, service: service, paths: [stagePath, restorePath, markerPath, eventsPath])
    }

    private func cleanup(_ fixture: Fixture) {
        for path in fixture.paths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    @Test
    func unhideAllRestoresHiddenWindowToMemberVisibleFrame() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        let result = fixture.service.unhideAll()

        #expect(result.applied == 1)
        #expect(result.failed == 0)
        #expect(fixture.writer.frames[WindowID(rawValue: 2)] == visibleFrame)
        #expect(fixture.writer.frames[WindowID(rawValue: 1)] == nil)
    }

    @Test
    func snapshotNeverContainsHiddenFrame() throws {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        let snapshot = try fixture.service.writeSnapshot()

        let hiddenEntry = snapshot.windows.first { $0.windowID == 2 }
        #expect(hiddenEntry?.frame == visibleFrame)
        #expect(!snapshot.windows.contains { $0.frame.x == hiddenFrame.x })
    }

    @Test
    func finishRunMarksCleanExitOnlyAfterRestore() throws {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        _ = try fixture.service.markRunStarted(pid: 42)

        let result = fixture.service.finishRun(pid: 42)

        #expect(result.failed == 0)
        #expect(fixture.writer.frames[WindowID(rawValue: 2)] == visibleFrame)
        #expect(!fixture.service.shouldRestoreAfterProcessExit(pid: 42))
    }

    @Test
    func startRunRecoversUncleanPreviousRunBeforeTakingMarker() throws {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        _ = try fixture.service.markRunStarted(pid: 41)

        let recovery = try fixture.service.startRun(pid: 42)

        #expect(recovery?.applied == 1)
        #expect(fixture.writer.frames[WindowID(rawValue: 2)] == visibleFrame)
        #expect(fixture.service.runMarker()?.pid == 42)
        // Le watcher de l'instance 41 trouve un marqueur repris : il ne restaure pas une 2e fois.
        #expect(try fixture.service.recoverAfterProcessExit(pid: 41) == nil)
    }

    @Test
    func instanceLockRefusesSecondHolderEvenWithoutPidFile() throws {
        let component = "roadied-test-\(UUID().uuidString.prefix(8))"
        let lock = ComponentLockFile(component: component)
        try lock.acquire()
        defer { lock.release() }
        // Le refus vient du flock, pas du fichier PID.
        try FileManager.default.removeItem(atPath: ComponentLockFile.pidFilePath(for: component))

        let competing = ComponentLockFile(component: component)
        #expect(throws: ComponentLockError.self) { try competing.acquire() }

        lock.release()
        try competing.acquire()
        competing.release()
    }
}
