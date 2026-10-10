import CoreGraphics
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

/// Écriture AX scriptée : délègue à `PowerUserWriter`, sauf pour les fenêtres `unreachable`
/// (introuvables, renvoie nil) et celles de `actual` (cadre réellement obtenu imposé).
/// `beforeSetFrame` s'exécute avant chaque écriture (sonde de verrou, action concurrente).
final class ScriptedFrameWriter: WindowFrameWriting, @unchecked Sendable {
    let inner: PowerUserWriter
    var unreachable: Set<WindowID> = []
    var actual: [WindowID: Rect] = [:]
    var beforeSetFrame: ((WindowSnapshot) -> Void)?
    private(set) var requested: [WindowID: [Rect]] = [:]

    init(provider: PowerUserProvider) {
        inner = PowerUserWriter(provider: provider)
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        beforeSetFrame?(window)
        requested[window.id, default: []].append(Rect(frame))
        guard !unreachable.contains(window.id) else { return nil }
        _ = inner.setFrame(frame, of: window)
        return (actual[window.id] ?? Rect(frame)).cgRect
    }

    func focus(_ window: WindowSnapshot) -> Bool { inner.focus(window) }
}

/// SPEC-016 T209 / T214 : couverture de `unhideAll` et reprise hors verrou.
@Suite
struct RestoreSafetyCoverageTests {
    private let stage1 = StageID(rawValue: "1")
    private let stage2 = StageID(rawValue: "2")
    private let hiddenFrame = Rect(x: 999, y: 100, width: 300, height: 300)
    private let visibleFrame = Rect(x: 400, y: 100, width: 300, height: 300)
    private let alivePID = ProcessInfo.processInfo.processIdentifier
    // Au-delà de pid_max (99998 sur macOS) : kill(pid, 0) renvoie ESRCH.
    private let deadPID: Int32 = 2_000_000_000

    private struct Fixture {
        let provider: PowerUserProvider
        let writer: ScriptedFrameWriter
        let service: RestoreSafetyService
        let restorePath: String
        let markerPath: String
        let paths: [String]
    }

    /// Fenêtre 1 visible (stage active) ; `hiddenMember` est membre de la stage inactive 2.
    /// `liveWindows` complète la liste du provider (fenêtres listées à l'écran).
    private func makeFixture(
        displays: [DisplaySnapshot] = [powerDisplay()],
        liveWindows: [WindowSnapshot] = [],
        activeMembers: [PersistentStageMember] = [],
        hiddenMember: PersistentStageMember
    ) -> Fixture {
        let display = displays[0]
        let provider = PowerUserProvider(displays: displays, windows: [powerWindow(1, x: 0)] + liveWindows)
        let writer = ScriptedFrameWriter(provider: provider)
        let stagePath = tempPath("restore-coverage-stage")
        let restorePath = tempPath("restore-coverage")
        let markerPath = tempPath("restore-coverage-run")
        let eventsPath = tempPath("restore-coverage-events")
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display.id, activeStageID: stage1, stages: [
                PersistentStage(id: stage1, members: [
                    PersistentStageMember(windowID: WindowID(rawValue: 1), bundleID: "app.1", title: "Window 1", frame: provider.snapshots[0].frame, pid: 1)
                ] + activeMembers),
                PersistentStage(id: stage2, members: [hiddenMember])
            ])
        ], activeDisplayID: display.id))
        let events = EventLog(path: eventsPath)
        let snapshotService = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(),
            intentStore: LayoutIntentStore(path: tempPath("restore-coverage-intent")),
            stageStore: stageStore,
            events: events
        )
        let service = RestoreSafetyService(path: restorePath, markerPath: markerPath, service: snapshotService, eventLog: events)
        return Fixture(
            provider: provider,
            writer: writer,
            service: service,
            restorePath: restorePath,
            markerPath: markerPath,
            paths: [stagePath, restorePath, markerPath, eventsPath, "\(markerPath).recovery.lock"]
        )
    }

    private func member(_ id: UInt32, pid: Int32?, frame: Rect? = nil) -> PersistentStageMember {
        PersistentStageMember(windowID: WindowID(rawValue: id), bundleID: "app.\(id)", title: "Window \(id)", frame: frame ?? visibleFrame, pid: pid)
    }

    private func hiddenWindow(_ id: UInt32, frame: Rect) -> WindowSnapshot {
        var window = powerWindow(id, x: frame.x)
        window.frame = frame
        return window
    }

    private func cleanup(_ fixture: Fixture) {
        for path in fixture.paths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    /// Vrai si le verrou de reprise est libre à cet instant (sonde non bloquante).
    private func recoveryLockIsFree(_ markerPath: String) -> Bool {
        let fd = open("\(markerPath).recovery.lock", O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return false }
        _ = flock(fd, LOCK_UN)
        return true
    }

    @Test
    func restoresInactiveMemberAbsentFromVisibleSnapshot() {
        let fixture = makeFixture(hiddenMember: member(2, pid: alivePID))
        defer { cleanup(fixture) }

        let result = fixture.service.unhideAll()

        #expect(result.applied == 1)
        #expect(result.failed == 0)
        #expect(fixture.writer.requested[WindowID(rawValue: 2)] == [visibleFrame])
    }

    @Test
    func unreachableMemberOfLiveProcessBlocksCleanExit() throws {
        let fixture = makeFixture(hiddenMember: member(2, pid: alivePID))
        defer { cleanup(fixture) }
        fixture.writer.unreachable = [WindowID(rawValue: 2)]
        _ = try fixture.service.markRunStarted(pid: 42)

        let result = fixture.service.finishRun(pid: 42)

        #expect(result.failed == 1)
        #expect(fixture.service.shouldRestoreAfterProcessExit(pid: 42))
    }

    @Test
    func memberWithoutPidAbsentFromSnapshotCountsAsNotRestored() throws {
        let fixture = makeFixture(hiddenMember: member(2, pid: nil))
        defer { cleanup(fixture) }
        _ = try fixture.service.markRunStarted(pid: 42)

        let result = fixture.service.finishRun(pid: 42)

        #expect(result.failed == 1)
        #expect(fixture.writer.requested[WindowID(rawValue: 2)] == nil)
        #expect(fixture.service.shouldRestoreAfterProcessExit(pid: 42))
    }

    @Test
    func memberOfDeadProcessIsClosedAndAllowsCleanExit() throws {
        let fixture = makeFixture(hiddenMember: member(2, pid: deadPID))
        defer { cleanup(fixture) }
        _ = try fixture.service.markRunStarted(pid: 42)

        let result = fixture.service.finishRun(pid: 42)

        #expect(result.attempted == 0)
        #expect(result.failed == 0)
        #expect(!fixture.service.shouldRestoreAfterProcessExit(pid: 42))
    }

    @Test
    func restoresMemberLeftAtEdgeOfVanishedRightDisplay() {
        // L'écran de droite (1000..2000) a disparu : x = 1999 n'est plus reconnu comme masqué.
        let stale = hiddenWindow(2, frame: Rect(x: 1999, y: 100, width: 300, height: 300))
        let fixture = makeFixture(liveWindows: [stale], hiddenMember: member(2, pid: alivePID))
        defer { cleanup(fixture) }

        let result = fixture.service.unhideAll()

        #expect(result.applied == 1)
        #expect(result.failed == 0)
        // Le snapshot a pu recopier la frame hors écran dans le membre : la fenêtre revient alors
        // centrée sur l'écran restant, jamais à la position perdue.
        let requested = fixture.writer.requested[WindowID(rawValue: 2)]?.first
        #expect(requested.map { CGRect(x: 0, y: 0, width: 1000, height: 800).contains(CGPoint(x: $0.cgRect.midX, y: $0.cgRect.midY)) } == true)
    }

    /// T301 : voisine de la stage ACTIVE masquée par un zoom sur l'écran de droite, qui a disparu.
    /// Ni `isHidden` (bord d'un écran absent) ni la liste des stages non affichées ne la voient.
    private func zoomSiblingFixture() -> Fixture {
        let stale = hiddenWindow(3, frame: Rect(x: 1999, y: 100, width: 300, height: 300))
        return makeFixture(
            liveWindows: [stale],
            activeMembers: [member(3, pid: alivePID, frame: Rect(x: 600, y: 200, width: 300, height: 300))],
            hiddenMember: member(2, pid: deadPID)
        )
    }

    @Test
    func restoresActiveStageSiblingLeftOffAllDisplays() throws {
        let fixture = zoomSiblingFixture()
        defer { cleanup(fixture) }
        _ = try fixture.service.markRunStarted(pid: 42)

        let result = fixture.service.finishRun(pid: 42)

        #expect(result.applied == 1)
        #expect(result.failed == 0)
        #expect(fixture.writer.requested[WindowID(rawValue: 3)] == [Rect(x: 600, y: 200, width: 300, height: 300)])
        #expect(!fixture.service.shouldRestoreAfterProcessExit(pid: 42))
    }

    @Test
    func activeStageSiblingStillOffDisplaysBlocksCleanExit() throws {
        let fixture = zoomSiblingFixture()
        defer { cleanup(fixture) }
        fixture.writer.actual[WindowID(rawValue: 3)] = Rect(x: 1999, y: 100, width: 300, height: 300)
        _ = try fixture.service.markRunStarted(pid: 42)

        let result = fixture.service.finishRun(pid: 42)

        #expect(result.failed == 1)
        #expect(fixture.service.shouldRestoreAfterProcessExit(pid: 42))
    }

    @Test
    func clampedFrameStillHiddenCountsAsFailure() {
        let fixture = makeFixture(liveWindows: [hiddenWindow(2, frame: hiddenFrame)], hiddenMember: member(2, pid: alivePID))
        defer { cleanup(fixture) }
        fixture.writer.actual[WindowID(rawValue: 2)] = hiddenFrame

        let result = fixture.service.unhideAll()

        #expect(result.applied == 0)
        #expect(result.failed == 1)
    }

    @Test
    func clampedButVisibleFrameCountsAsSuccess() {
        let fixture = makeFixture(liveWindows: [hiddenWindow(2, frame: hiddenFrame)], hiddenMember: member(2, pid: alivePID))
        defer { cleanup(fixture) }
        fixture.writer.actual[WindowID(rawValue: 2)] = Rect(x: 450, y: 120, width: 200, height: 200)

        let result = fixture.service.unhideAll()

        #expect(result.applied == 1)
        #expect(result.failed == 0)
    }

    @Test
    func startRunRestoresOutsideRecoveryLock() throws {
        let fixture = makeFixture(liveWindows: [hiddenWindow(2, frame: hiddenFrame)], hiddenMember: member(2, pid: alivePID))
        defer { cleanup(fixture) }
        _ = try fixture.service.markRunStarted(pid: 41)
        var lockFree = false
        var watcherResult: RestoreSafetyApplyResult?? = .none
        fixture.writer.beforeSetFrame = { _ in
            lockFree = recoveryLockIsFree(fixture.markerPath)
            // Le watcher de l'instance 41 se réveille pendant la restauration du démarrage.
            if lockFree { watcherResult = .some(try? fixture.service.recoverAfterProcessExit(pid: 41) ?? nil) }
        }

        let recovery = try fixture.service.startRun(pid: 42)

        #expect(lockFree)
        #expect(recovery?.applied == 1)
        // Marqueur déjà repris : le watcher ne restaure pas une 2e fois.
        #expect(watcherResult == .some(nil))
        #expect(fixture.writer.requested[WindowID(rawValue: 2)]?.count == 1)
        #expect(fixture.service.runMarker()?.pid == 42)
    }

    @Test
    func watcherRestoresOutsideLockAndKeepsMarkerTakenByNewInstance() throws {
        let fixture = makeFixture(liveWindows: [hiddenWindow(2, frame: hiddenFrame)], hiddenMember: member(2, pid: alivePID))
        defer { cleanup(fixture) }
        _ = try fixture.service.markRunStarted(pid: 41)
        var lockFree = false
        var startRecovery: RestoreSafetyApplyResult?
        fixture.writer.beforeSetFrame = { _ in
            lockFree = recoveryLockIsFree(fixture.markerPath)
            // Redémarrage rapide pendant la restauration du watcher.
            if lockFree { startRecovery = try? fixture.service.startRun(pid: 43) }
        }

        let result = try fixture.service.recoverAfterProcessExit(pid: 41)

        #expect(lockFree)
        #expect(result?.applied == 1)
        // Restauration en cours par le watcher : le démarrage ne la relance pas.
        #expect(startRecovery == nil)
        #expect(fixture.writer.requested[WindowID(rawValue: 2)]?.count == 1)
        // Le marqueur repris par l'instance 43 n'est pas marqué propre par le watcher.
        #expect(fixture.service.runMarker()?.pid == 43)
        #expect(fixture.service.runMarker()?.cleanExit == false)
    }

    @Test
    func unreadableRestoreSnapshotIsKeptAndNeverOverwritten() throws {
        let fixture = makeFixture(hiddenMember: member(2, pid: alivePID))
        defer { cleanup(fixture) }
        let garbage = "{ not json"
        try garbage.write(toFile: fixture.restorePath, atomically: true, encoding: .utf8)
        let directory = (fixture.restorePath as NSString).deletingLastPathComponent
        let name = (fixture.restorePath as NSString).lastPathComponent
        defer {
            for entry in (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [] where entry.hasPrefix("\(name).corrupt-") {
                try? FileManager.default.removeItem(atPath: "\(directory)/\(entry)")
            }
        }

        #expect(throws: (any Error).self) { try fixture.service.writeSnapshot() }

        #expect(try String(contentsOfFile: fixture.restorePath, encoding: .utf8) == garbage)
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory).filter { $0.hasPrefix("\(name).corrupt-") }
        #expect(backups.count == 1)
        // La restauration reste possible sans le snapshot illisible.
        #expect(fixture.service.unhideAll().failed == 0)
    }

    @Test
    func componentLockSurvivesConcurrentAcquireAndRelease() throws {
        let component = "roadied-test-\(UUID().uuidString.prefix(8))"
        let lock = ComponentLockFile(component: component)
        DispatchQueue.concurrentPerform(iterations: 64) { index in
            if index.isMultiple(of: 2) { try? lock.acquire() } else { lock.release() }
        }
        lock.release()

        // Aucun descripteur perdu ne garde le flock : un autre détenteur l'obtient.
        let competing = ComponentLockFile(component: component)
        try competing.acquire()
        competing.release()
    }
}
