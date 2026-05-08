import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

@Suite
struct TransientWindowDetectorTests {
    @Test
    func detectsSheetsDialogsAndOpenSavePanels() {
        let sheet = WindowSnapshot(
            id: WindowID(rawValue: 10),
            pid: 10,
            appName: "App",
            bundleID: "app",
            title: "Save",
            role: "AXWindow",
            subrole: "AXSheet",
            frame: Rect(x: 10, y: 10, width: 300, height: 200),
            isOnScreen: true,
            isTileCandidate: false
        )
        let provider = PowerUserProvider(windows: [sheet])
        let state = TransientWindowDetector(
            service: SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider))
        ).status()

        #expect(state.isActive)
        #expect(state.reason == .sheet)
    }

    @Test
    func recoversOffscreenTransientWindow() {
        let dialog = WindowSnapshot(
            id: WindowID(rawValue: 11),
            pid: 11,
            appName: "App",
            bundleID: "app",
            title: "Open",
            role: "AXDialog",
            subrole: nil,
            frame: Rect(x: 5000, y: 5000, width: 300, height: 200),
            isOnScreen: true,
            isTileCandidate: false
        )
        let provider = PowerUserProvider(windows: [dialog])
        let writer = PowerUserWriter(provider: provider)
        let detector = TransientWindowDetector(
            service: SnapshotService(provider: provider, frameWriter: writer),
            frameWriter: writer,
            events: EventLog(path: tempPath("transient-events"))
        )

        #expect(detector.status().recoverable)
        #expect(detector.recoverIfNeeded())
        #expect(writer.frames[dialog.id] == powerDisplay().visibleFrame)
    }
}
