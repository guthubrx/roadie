import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

final class PowerUserProvider: SystemSnapshotProviding, @unchecked Sendable {
    var focusedID: WindowID?
    let displaySnapshots: [DisplaySnapshot]
    var snapshots: [WindowSnapshot]

    init(displays: [DisplaySnapshot] = [powerDisplay()], windows: [WindowSnapshot]) {
        self.displaySnapshots = displays
        self.snapshots = windows
        self.focusedID = windows.first?.id
    }

    func permissions(prompt: Bool) -> PermissionSnapshot { PermissionSnapshot(accessibilityTrusted: true) }
    func displays() -> [DisplaySnapshot] { displaySnapshots }
    func windows() -> [WindowSnapshot] { snapshots }
    func focusedWindowID() -> WindowID? { focusedID }
}

final class PowerUserWriter: WindowFrameWriting, @unchecked Sendable {
    let provider: PowerUserProvider
    private(set) var focused: [WindowID] = []
    private(set) var frames: [WindowID: Rect] = [:]

    init(provider: PowerUserProvider) {
        self.provider = provider
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        let rect = Rect(frame)
        frames[window.id] = rect
        provider.snapshots = provider.snapshots.map {
            guard $0.id == window.id else { return $0 }
            var updated = $0
            updated.frame = rect
            return updated
        }
        return frame
    }

    func focus(_ window: WindowSnapshot) -> Bool {
        focused.append(window.id)
        provider.focusedID = window.id
        return true
    }

    func reset(_ window: WindowSnapshot) -> Bool { true }
}

@Suite
struct PowerUserFocusCommandTests {
    @Test
    func focusBackAndForthUsesPreviousFocusedWindow() {
        let provider = PowerUserProvider(windows: [
            powerWindow(1, x: 0),
            powerWindow(2, x: 500)
        ])
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("power-focus-stages"))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)
        _ = service.snapshot()

        let focusRight = WindowCommandService(service: service, stageStore: store).focus(.right)
        let back = WindowCommandService(service: service, stageStore: store).focusBackAndForth()

        #expect(focusRight.changed)
        #expect(back.changed)
        #expect(writer.focused.map(\.rawValue) == [2, 1])
    }

    @Test
    func directionalFocusPrefersSameVisualBandBeforeDiagonalCandidate() {
        let provider = PowerUserProvider(windows: [
            powerWindow(1, x: 0, y: 400, width: 300, height: 300),
            powerWindow(2, x: 310, y: 400, width: 140, height: 300),
            powerWindow(3, x: 700, y: 400, width: 140, height: 300),
            powerWindow(4, x: 360, y: 90, width: 300, height: 300)
        ])
        provider.focusedID = WindowID(rawValue: 2)
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("power-focus-band"))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)
        _ = service.snapshot()

        let result = WindowCommandService(service: service, stageStore: store).focus(.right)

        #expect(result.changed)
        #expect(writer.focused.map(\.rawValue) == [3])
    }
}

func powerDisplay(_ id: String = "display-main", index: Int = 1, x: Double = 0) -> DisplaySnapshot {
    DisplaySnapshot(
        id: DisplayID(rawValue: id),
        index: index,
        name: id,
        frame: Rect(x: x, y: 0, width: 1000, height: 800),
        visibleFrame: Rect(x: x, y: 0, width: 1000, height: 800),
        isMain: index == 1
    )
}

func powerWindow(
    _ id: UInt32,
    x: Double,
    y: Double = 100,
    width: Double = 300,
    height: Double = 300,
    app: String = "App"
) -> WindowSnapshot {
    WindowSnapshot(
        id: WindowID(rawValue: id),
        pid: Int32(id),
        appName: app,
        bundleID: "app.\(id)",
        title: "Window \(id)",
        frame: Rect(x: x, y: y, width: width, height: height),
        isOnScreen: true,
        isTileCandidate: true
    )
}

func tempPath(_ name: String) -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString).json")
        .path
}
