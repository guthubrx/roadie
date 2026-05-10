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
    private(set) var zoomed: [WindowID] = []
    private(set) var nativeFullscreen: [WindowID] = []

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
    func toggleZoom(_ window: WindowSnapshot) -> Bool {
        zoomed.append(window.id)
        return true
    }
    func toggleNativeFullscreen(_ window: WindowSnapshot) -> Bool {
        nativeFullscreen.append(window.id)
        return true
    }
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

    @Test
    func fullscreenTogglesCallUnderlyingWindowActions() {
        let left = powerWindow(1, x: 0, y: 0, width: 495, height: 800)
        let right = powerWindow(2, x: 505, y: 0, width: 495, height: 800)
        let provider = PowerUserProvider(windows: [left, right])
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("power-fullscreen"))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)
        _ = service.snapshot()
        let commands = WindowCommandService(service: service, stageStore: store)

        let fullscreenOn = commands.toggleFullscreen()
        let fullscreenOff = commands.toggleFullscreen()
        let native = commands.toggleNativeFullscreen()

        #expect(fullscreenOn.changed)
        #expect(fullscreenOff.changed)
        #expect(native.changed)
        #expect(writer.frames[left.id] != nil)
        #expect(writer.frames[left.id] != Rect(x: 0, y: 0, width: 1000, height: 800))
        #expect(writer.nativeFullscreen.map(\.rawValue) == [1])
    }

    @Test
    func railHidesOnFocusedFullscreenWindowDisplay() {
        let display = powerDisplay()
        let fullscreen = powerWindow(1, x: 0, y: 0, width: 1000, height: 800)
        let regular = powerWindow(2, x: 40, y: 40, width: 420, height: 320)
        let provider = PowerUserProvider(displays: [display], windows: [fullscreen, regular])
        provider.focusedID = fullscreen.id
        let store = StageStore(path: tempPath("rail-fullscreen-stages"))
        let service = SnapshotService(provider: provider, stageStore: store)
        let snapshot = service.snapshot()

        #expect(RailController.fullscreenDisplayIDs(in: snapshot) == [display.id])
    }

    @Test
    func railStaysVisibleWhenFocusedWindowIsNotFullscreen() {
        let display = powerDisplay()
        let regular = powerWindow(1, x: 40, y: 40, width: 420, height: 320)
        let provider = PowerUserProvider(displays: [display], windows: [regular])
        provider.focusedID = regular.id
        let store = StageStore(path: tempPath("rail-regular-window-stages"))
        let service = SnapshotService(provider: provider, stageStore: store)
        let snapshot = service.snapshot()

        #expect(RailController.fullscreenDisplayIDs(in: snapshot).isEmpty)
    }

    @Test
    func focusedBorderIsHiddenWhenAnotherWindowOccludesFocusedWindow() {
        let display = powerDisplay()
        let occluder = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 1,
            appName: "Settings",
            bundleID: "settings",
            title: "Settings",
            frame: Rect(x: 120, y: 120, width: 360, height: 260),
            isOnScreen: true,
            isTileCandidate: false
        )
        let focused = powerWindow(2, x: 0, y: 0, width: 800, height: 600)
        let provider = PowerUserProvider(displays: [display], windows: [occluder, focused])
        provider.focusedID = focused.id
        let service = SnapshotService(provider: provider, stageStore: StageStore(path: tempPath("border-occlusion-stages")))
        let snapshot = service.snapshot()
        let target = snapshot.windows.first { $0.window.id == focused.id }!

        #expect(BorderController.isWindowVisiblyOccluded(target, in: snapshot))
    }

    @Test
    func focusedBorderIsShownWhenNoWindowOccludesFocusedWindow() {
        let display = powerDisplay()
        let focused = powerWindow(1, x: 0, y: 0, width: 800, height: 600)
        let aside = powerWindow(2, x: 820, y: 0, width: 160, height: 200)
        let provider = PowerUserProvider(displays: [display], windows: [focused, aside])
        provider.focusedID = focused.id
        let service = SnapshotService(provider: provider, stageStore: StageStore(path: tempPath("border-clear-stages")))
        let snapshot = service.snapshot()
        let target = snapshot.windows.first { $0.window.id == focused.id }!

        #expect(!BorderController.isWindowVisiblyOccluded(target, in: snapshot))
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
