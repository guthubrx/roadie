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
    func focusRightPrefersSameRowOverCloserUpperWindow() {
        let focused = powerWindow(1, frame: Rect(x: 150, y: 634, width: 465, height: 586))
        let sameRowRight = powerWindow(2, frame: Rect(x: 625, y: 634, width: 465, height: 586))
        let upperRight = powerWindow(3, frame: Rect(x: 150, y: 38, width: 940, height: 586))
        let farRight = powerWindow(4, frame: Rect(x: 1100, y: 634, width: 465, height: 586))
        let provider = PowerUserProvider(windows: [focused, sameRowRight, upperRight, farRight])
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("power-focus-row-stages"))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)
        _ = service.snapshot()

        let result = WindowCommandService(service: service, stageStore: store).focus(.right)

        #expect(result.changed)
        #expect(writer.focused.map(\.rawValue) == [2])
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

func powerWindow(_ id: UInt32, x: Double, app: String = "App") -> WindowSnapshot {
    powerWindow(id, frame: Rect(x: x, y: 100, width: 300, height: 300), app: app)
}

func powerWindow(_ id: UInt32, frame: Rect, app: String = "App") -> WindowSnapshot {
    WindowSnapshot(
        id: WindowID(rawValue: id),
        pid: Int32(id),
        appName: app,
        bundleID: "app.\(id)",
        title: "Window \(id)",
        frame: frame,
        isOnScreen: true,
        isTileCandidate: true
    )
}

func tempPath(_ name: String) -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString).json")
        .path
}
