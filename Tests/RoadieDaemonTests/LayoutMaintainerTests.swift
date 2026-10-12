import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon
import RoadieTiler

private final class SequenceProvider: SystemSnapshotProviding, @unchecked Sendable {
    private let display: DisplaySnapshot
    private let windowFrames: [[Rect]]
    private let nativeFullscreenWindowIDs: Set<WindowID>
    private var index = 0

    init(
        display: DisplaySnapshot,
        windowFrames: [[Rect]],
        nativeFullscreenWindowIDs: Set<WindowID> = []
    ) {
        self.display = display
        self.windowFrames = windowFrames
        self.nativeFullscreenWindowIDs = nativeFullscreenWindowIDs
    }

    func permissions(prompt: Bool) -> PermissionSnapshot {
        PermissionSnapshot(accessibilityTrusted: true)
    }

    func displays() -> [DisplaySnapshot] {
        [display]
    }

    func windows() -> [WindowSnapshot] {
        let frames = windowFrames[Swift.min(index, windowFrames.count - 1)]
        index += 1
        return frames.enumerated().map { offset, frame in
            WindowSnapshot(
                id: WindowID(rawValue: UInt32(offset + 1)),
                pid: Int32(offset + 10),
                appName: "App\(offset + 1)",
                bundleID: "app.\(offset + 1)",
                title: "Window\(offset + 1)",
                frame: frame,
                isOnScreen: true,
                isTileCandidate: true,
                furniture: nativeFullscreenWindowIDs.contains(WindowID(rawValue: UInt32(offset + 1)))
                    ? WindowFurniture(isNativeFullscreen: true)
                    : nil
            )
        }
    }
}

@Suite
struct WindowPinLayoutMaintainerTests {
    @Test
    func inactiveDesktopPinIsNotHiddenWhenDesktopIsActive() {
        let display = powerDisplay("display-main", index: 1, x: 0)
        let pinned = powerWindow(10, x: 100)
        let inactive = powerWindow(20, x: 500)
        let active = powerWindow(30, x: 700)
        let home = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let store = StageStore(path: tempPath("window-pin-maintainer-hide"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: display.id, activeStageID: StageID(rawValue: "2"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), members: [
                        PersistentStageMember(windowID: pinned.id, bundleID: pinned.bundleID, title: pinned.title, frame: pinned.frame),
                        PersistentStageMember(windowID: inactive.id, bundleID: inactive.bundleID, title: inactive.title, frame: inactive.frame)
                    ]),
                    PersistentStage(id: StageID(rawValue: "2"), members: [
                        PersistentStageMember(windowID: active.id, bundleID: active.bundleID, title: active.title, frame: active.frame)
                    ])
                ])
            ],
            windowPins: [
                PersistentWindowPin(
                    windowID: pinned.id,
                    homeScope: home,
                    pinScope: .desktop,
                    bundleID: pinned.bundleID,
                    title: pinned.title,
                    lastFrame: pinned.frame
                )
            ],
            activeDisplayID: display.id
        ))
        let provider = MultiDisplaySequenceProvider(displaySnapshots: [display], windowSnapshots: [[pinned, inactive, active]])
        let writer = RecordingWriter()
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)
        let maintainer = LayoutMaintainer(service: service)

        let tick = maintainer.tick()

        // A1 : masquage de la stage inactive et disposition de la stage active dans la même passe.
        #expect(tick.commands == 2)
        #expect(writer.requestedFrames[active.id] != nil)
        #expect(writer.requestedFrames[pinned.id] == nil)
        #expect(writer.requestedFrames[inactive.id] != nil)
    }

    @Test
    func visiblePinHiddenInCornerIsRestoredToLastFrame() {
        let display = powerDisplay("display-main", index: 1, x: 0)
        let visibleFrame = Rect(x: 150, y: 120, width: 300, height: 240)
        let hiddenFrame = Rect(
            x: display.visibleFrame.x - 299,
            y: display.visibleFrame.y + display.visibleFrame.height - 1,
            width: 300,
            height: 240
        )
        let hiddenPinned = WindowSnapshot(
            id: WindowID(rawValue: 10),
            pid: 10,
            appName: "Pinned",
            bundleID: "app.pinned",
            title: "Pinned",
            frame: hiddenFrame,
            isOnScreen: true,
            isTileCandidate: true
        )
        let home = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let store = StageStore(path: tempPath("window-pin-maintainer-restore"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: display.id, activeStageID: StageID(rawValue: "2"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), members: [
                        PersistentStageMember(windowID: hiddenPinned.id, bundleID: hiddenPinned.bundleID, title: hiddenPinned.title, frame: visibleFrame)
                    ]),
                    PersistentStage(id: StageID(rawValue: "2"))
                ])
            ],
            windowPins: [
                PersistentWindowPin(
                    windowID: hiddenPinned.id,
                    homeScope: home,
                    pinScope: .desktop,
                    bundleID: hiddenPinned.bundleID,
                    title: hiddenPinned.title,
                    lastFrame: visibleFrame
                )
            ],
            activeDisplayID: display.id
        ))
        let provider = MultiDisplaySequenceProvider(displaySnapshots: [display], windowSnapshots: [[hiddenPinned]])
        let writer = RecordingWriter()
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)
        let maintainer = LayoutMaintainer(service: service)

        let tick = maintainer.tick()

        #expect(tick.commands == 1)
        #expect(writer.requestedFrames[hiddenPinned.id] == visibleFrame)
    }

    @Test
    func inactiveWindowParkedOnOldBottomLeftIsReparkedToBottomRight() {
        let display = powerDisplay("display-main", index: 1, x: 0)
        let oldBottomLeft = Rect(
            x: display.visibleFrame.x + 1 - 300,
            y: display.visibleFrame.y + display.visibleFrame.height - 1,
            width: 300,
            height: 240
        )
        let inactive = WindowSnapshot(
            id: WindowID(rawValue: 10),
            pid: 10,
            appName: "Inactive",
            bundleID: "app.inactive",
            title: "Inactive",
            frame: oldBottomLeft,
            isOnScreen: true,
            isTileCandidate: true
        )
        let store = StageStore(path: tempPath("window-bottom-left-repark"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: display.id, activeStageID: StageID(rawValue: "2"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), members: [
                        PersistentStageMember(windowID: inactive.id, bundleID: inactive.bundleID, title: inactive.title, frame: inactive.frame)
                    ]),
                    PersistentStage(id: StageID(rawValue: "2"))
                ])
            ],
            activeDisplayID: display.id
        ))
        let provider = MultiDisplaySequenceProvider(displaySnapshots: [display], windowSnapshots: [[inactive]])
        let writer = RecordingWriter()
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)
        let maintainer = LayoutMaintainer(service: service)

        let tick = maintainer.tick()

        #expect(tick.commands == 1)
        #expect(writer.requestedFrames[inactive.id] == Rect(
            x: display.visibleFrame.x + display.visibleFrame.width - 1,
            y: display.visibleFrame.y + display.visibleFrame.height - 1,
            width: 300,
            height: 240
        ))
    }
}

private final class MultiDisplaySequenceProvider: SystemSnapshotProviding, @unchecked Sendable {
    private let displaySnapshots: [DisplaySnapshot]
    private let windowSnapshots: [[WindowSnapshot]]
    private let focusedID: WindowID?
    private var index = 0

    init(displaySnapshots: [DisplaySnapshot], windowSnapshots: [[WindowSnapshot]], focusedID: WindowID? = nil) {
        self.displaySnapshots = displaySnapshots
        self.windowSnapshots = windowSnapshots
        self.focusedID = focusedID
    }

    func permissions(prompt: Bool) -> PermissionSnapshot {
        PermissionSnapshot(accessibilityTrusted: true)
    }

    func displays() -> [DisplaySnapshot] {
        displaySnapshots
    }

    func windows() -> [WindowSnapshot] {
        let windows = windowSnapshots[Swift.min(index, windowSnapshots.count - 1)]
        index += 1
        return windows
    }

    func focusedWindowID() -> WindowID? {
        focusedID
    }
}

private final class DynamicDisplaySequenceProvider: SystemSnapshotProviding, @unchecked Sendable {
    private let displaySnapshots: [[DisplaySnapshot]]
    private let windowSnapshots: [[WindowSnapshot]]
    private var index = 0

    init(displaySnapshots: [[DisplaySnapshot]], windowSnapshots: [[WindowSnapshot]]) {
        self.displaySnapshots = displaySnapshots
        self.windowSnapshots = windowSnapshots
    }

    func permissions(prompt: Bool) -> PermissionSnapshot {
        PermissionSnapshot(accessibilityTrusted: true)
    }

    func displays() -> [DisplaySnapshot] {
        displaySnapshots[Swift.min(index, displaySnapshots.count - 1)]
    }

    func windows() -> [WindowSnapshot] {
        let windows = windowSnapshots[Swift.min(index, windowSnapshots.count - 1)]
        index += 1
        return windows
    }
}

private final class RecordingWriter: WindowFrameWriting, @unchecked Sendable {
    private(set) var requestedFrames: [WindowID: Rect] = [:]

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        requestedFrames[window.id] = Rect(frame)
        return frame
    }
}

private final class FailingWriter: WindowFrameWriting, @unchecked Sendable {
    private(set) var attempts = 0
    /// Exécuté à chaque tentative : simule une écriture concurrente pendant l'appel AX.
    var onAttempt: (() -> Void)?

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        attempts += 1
        onAttempt?()
        return nil
    }
}

private final class SequenceWriter: WindowFrameWriting, @unchecked Sendable {
    private let actualFrames: [WindowID: Rect]

    init(actualFrames: [WindowID: Rect]) {
        self.actualFrames = actualFrames
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        actualFrames[window.id]?.cgRect ?? frame
    }
}

private final class RecordingSequenceWriter: WindowFrameWriting, @unchecked Sendable {
    private let actualFrames: [WindowID: Rect]
    private(set) var requestedFrames: [WindowID: Rect] = [:]

    init(actualFrames: [WindowID: Rect]) {
        self.actualFrames = actualFrames
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        requestedFrames[window.id] = Rect(frame)
        return actualFrames[window.id]?.cgRect ?? frame
    }
}

private final class FocusedSystemSnapshotProvider: SystemSnapshotProviding, @unchecked Sendable {
    private let base: any SystemSnapshotProviding
    private let focusedID: WindowID?

    init(base: any SystemSnapshotProviding, focusedWindowID: WindowID?) {
        self.base = base
        self.focusedID = focusedWindowID
    }

    func permissions(prompt: Bool) -> PermissionSnapshot {
        base.permissions(prompt: prompt)
    }

    func displays() -> [DisplaySnapshot] {
        base.displays()
    }

    func windows() -> [WindowSnapshot] {
        base.windows()
    }

    func focusedWindowID() -> WindowID? {
        focusedID
    }
}

/// L'application refuse toute taille : chaque demande renvoie le même cadre (« clampé »).
private final class AlwaysClampedWriter: WindowFrameWriting, @unchecked Sendable {
    private let actual: Rect
    private(set) var attempts = 0

    init(actual: Rect) {
        self.actual = actual
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        attempts += 1
        return actual.cgRect
    }
}

private final class ClampingWriter: WindowFrameWriting, @unchecked Sendable {
    private let firstActual: Rect
    private(set) var requestedFrames: [Rect] = []

    init(firstActual: Rect) {
        self.firstActual = firstActual
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        requestedFrames.append(Rect(frame))
        return requestedFrames.count == 1 ? firstActual.cgRect : frame
    }
}

private func makeIntentStore() -> (path: String, store: LayoutIntentStore) {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("roadie-maintainer-intent-\(UUID().uuidString).json")
        .path
    return (path: path, store: LayoutIntentStore(path: path))
}

@Suite
struct LayoutMaintainerTests {
    @Test
    func failedFrameDoesNotTriggerRepeatedApplyLoop() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let initial = Rect(x: 80, y: 80, width: 320, height: 240)
        let provider = SequenceProvider(display: display, windowFrames: [[initial], [initial]])
        let writer = FailingWriter()
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 0))
        )
        let maintainer = LayoutMaintainer(service: service)

        let first = maintainer.tick()
        let second = maintainer.tick()

        #expect(first.commands == 1)
        #expect(first.failed == 1)
        #expect(second.commands == 0)
        #expect(writer.attempts == 1)
    }

    @Test
    func failedFrameStaysSuppressedPastCooldownWhenObservedFrameIsUnchanged() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let initial = Rect(x: 80, y: 80, width: 320, height: 240)
        let provider = SequenceProvider(display: display, windowFrames: [[initial], [initial]])
        let writer = FailingWriter()
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 0))
        )
        var currentTime = Date(timeIntervalSince1970: 0)
        let maintainer = LayoutMaintainer(service: service, now: { currentTime })

        let first = maintainer.tick()
        currentTime = currentTime.addingTimeInterval(30)
        let second = maintainer.tick()

        #expect(first.failed == 1)
        #expect(second.commands == 0)
        #expect(writer.attempts == 1)
    }

    @Test
    func revertedAppliedFrameDoesNotTriggerRepeatedApplyLoop() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let initial = Rect(x: 80, y: 80, width: 320, height: 240)
        let provider = SequenceProvider(display: display, windowFrames: [[initial], [initial]])
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 0))
        )
        let maintainer = LayoutMaintainer(service: service)

        let first = maintainer.tick()
        let second = maintainer.tick()

        #expect(first.commands == 1)
        #expect(first.applied == 1)
        #expect(second.commands == 0)
    }

    @Test
    func activeWindowDragSuppressesMaintainerRelayout() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let initial = Rect(x: 80, y: 80, width: 320, height: 240)
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: SequenceProvider(display: display, windowFrames: [[initial]]),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 0))
        )
        let now = Date(timeIntervalSince1970: 100)
        let dragActivity = WindowDragActivity(path: tempPath("window-drag-activity-monolithic"))
        let maintainer = LayoutMaintainer(service: service, dragActivity: dragActivity, now: { now })
        dragActivity.markActive(windowID: WindowID(rawValue: 1), now: now, holdSeconds: 5)

        let tick = maintainer.tick()

        #expect(tick.commands == 0)
        #expect(writer.requestedFrames.isEmpty)
    }

    @Test
    func activeWindowDragSuppressesMaintainerRelayoutAcrossActivityInstances() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let provider = SequenceProvider(display: display, windowFrames: [
            [
                Rect(x: 0, y: 0, width: 495, height: 500),
                Rect(x: 505, y: 0, width: 495, height: 500),
            ],
            [
                Rect(x: 300, y: 120, width: 495, height: 500),
                Rect(x: 505, y: 0, width: 495, height: 500),
            ],
        ])
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .mutableBsp, gapsOuter: 0, gapsInner: 10))
        )
        var currentTime = Date(timeIntervalSince1970: 100)
        let activityPath = tempPath("window-drag-activity-modular")
        let dragProducer = WindowDragActivity(path: activityPath)
        let dragConsumer = WindowDragActivity(path: activityPath)
        let maintainer = LayoutMaintainer(service: service, dragActivity: dragConsumer, now: { currentTime })

        let initial = maintainer.tick()
        dragProducer.markActive(windowID: WindowID(rawValue: 1), now: currentTime, holdSeconds: 5)
        currentTime = currentTime.addingTimeInterval(0.1)
        let dragging = maintainer.tick()

        #expect(initial.commands == 0)
        #expect(dragging.commands == 0)
        #expect(!dragging.manualResizeDetected)
        #expect(writer.requestedFrames.isEmpty)
        dragProducer.reset()
    }

    @Test
    func activeLayoutCommandSuppressesNonTreeRelayout() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let provider = SequenceProvider(display: display, windowFrames: [
            [
                Rect(x: 0, y: 0, width: 495, height: 500),
                Rect(x: 505, y: 0, width: 495, height: 500),
            ],
            [
                Rect(x: 0, y: 0, width: 300, height: 500),
                Rect(x: 710, y: 0, width: 290, height: 500),
            ],
        ])
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .bsp, gapsOuter: 0, gapsInner: 10))
        )
        var currentTime = Date(timeIntervalSince1970: 100)
        let commandActivity = LayoutCommandActivity(path: tempPath("layout-command-activity"))
        commandActivity.reset()
        let maintainer = LayoutMaintainer(service: service, commandActivity: commandActivity, now: { currentTime })

        let initial = maintainer.tick()
        commandActivity.markActive(reason: "test", now: currentTime, holdSeconds: 5)
        currentTime = currentTime.addingTimeInterval(0.1)
        let suppressed = maintainer.tick()

        #expect(initial.commands == 0)
        #expect(suppressed.commands == 0)
        #expect(!suppressed.manualResizeDetected)
        #expect(writer.requestedFrames.isEmpty)
        commandActivity.reset()
    }

    @Test
    func dragReleaseSnapsBackWhenAuthoritativeLayoutIntentExists() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let provider = SequenceProvider(display: display, windowFrames: [
            [
                Rect(x: 0, y: 0, width: 495, height: 500),
                Rect(x: 505, y: 0, width: 495, height: 500),
            ],
            [
                Rect(x: 0, y: 0, width: 700, height: 500),
                Rect(x: 710, y: 0, width: 290, height: 500),
            ],
            [
                Rect(x: 0, y: 0, width: 700, height: 500),
                Rect(x: 710, y: 0, width: 290, height: 500),
            ],
        ])
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10))
        )
        var currentTime = Date(timeIntervalSince1970: 100)
        let dragActivity = WindowDragActivity(path: tempPath("window-drag-activity-release"))
        let maintainer = LayoutMaintainer(service: service, dragActivity: dragActivity, now: { currentTime })

        let initial = maintainer.tick()
        dragActivity.markActive(windowID: WindowID(rawValue: 1), now: currentTime, holdSeconds: 1)
        let dragging = maintainer.tick()
        currentTime = currentTime.addingTimeInterval(2)
        let released = maintainer.tick()

        #expect(initial.commands == 0)
        #expect(dragging.commands == 0)
        #expect(!released.manualResizeDetected)
        #expect(released.commands == 2)
        #expect(writer.requestedFrames[WindowID(rawValue: 1)] == Rect(x: 0, y: 0, width: 495, height: 500))
    }

    @Test
    func externalResizeSnapsBackToSavedLayoutIntent() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let provider = SequenceProvider(display: display, windowFrames: [
            [
                Rect(x: 0, y: 0, width: 495, height: 500),
                Rect(x: 505, y: 0, width: 495, height: 500),
            ],
            [
                Rect(x: 0, y: 0, width: 700, height: 500),
                Rect(x: 505, y: 0, width: 495, height: 500),
            ],
            [
                Rect(x: 0, y: 0, width: 700, height: 500),
                Rect(x: 505, y: 0, width: 495, height: 500),
            ],
        ])
        let writer = RecordingWriter()
        let intentPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-manual-resize-intent-\(UUID().uuidString).json")
            .path
        let eventPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-manual-resize-events-\(UUID().uuidString).jsonl")
            .path
        let intentStore = LayoutIntentStore(path: intentPath)
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        intentStore.save(LayoutIntent(
            scope: scope,
            windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)],
            placements: [
                WindowID(rawValue: 1): Rect(x: 0, y: 0, width: 495, height: 500),
                WindowID(rawValue: 2): Rect(x: 505, y: 0, width: 495, height: 500),
            ]
        ))
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            intentStore: intentStore
        )
        var currentTime = Date(timeIntervalSince1970: 0)
        let maintainer = LayoutMaintainer(service: service, events: EventLog(path: eventPath), now: { currentTime })

        let initial = maintainer.tick()
        let resizing = maintainer.tick()
        let debounced = maintainer.tick()
        currentTime = currentTime.addingTimeInterval(2)
        let settled = maintainer.tick()

        #expect(initial.commands == 0)
        #expect(!resizing.manualResizeDetected)
        #expect(resizing.commands == 1)
        #expect(!debounced.manualResizeDetected)
        #expect(debounced.commands == 0)
        #expect(settled.commands == 0)
        #expect(writer.requestedFrames[WindowID(rawValue: 1)] == Rect(x: 0, y: 0, width: 495, height: 500))
        #expect(intentStore.intent(for: scope)?.placements[WindowID(rawValue: 1)] == Rect(x: 0, y: 0, width: 495, height: 500))
        #expect(intentStore.intent(for: scope)?.placements[WindowID(rawValue: 2)] == Rect(x: 505, y: 0, width: 495, height: 500))
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        #expect(events.contains("\"type\":\"external_geometry_snapped_to_layout_model\""))
        try? FileManager.default.removeItem(atPath: intentPath)
        try? FileManager.default.removeItem(atPath: eventPath)
    }

    /// FR-017 (016) et A18 : un changement isolé est rangé tout de suite ; un second changement
    /// moins de `burstWindow` plus tard ouvre une rafale : le premier placement est conservé, rien
    /// n'est écrit pendant la rafale, puis une seule passe finale suit `burstQuiet` de calme.
    @Test(arguments: [0.08, 0.25])
    func tiledScopeMembershipChurnSettlesBeforeRelayout(spacing: Double) {
        let world = TreeWorld(frames: [treeW1: treeLeft, treeW2: treeRight])
        let harness = TreeHarness(
            "membership-burst-\(spacing)",
            world: world,
            store: StageStore(path: tempPath("membership-burst-\(spacing)")),
            strategy: .bsp
        )

        _ = harness.maintainer.tick(cause: "startup")
        harness.clock.advance(5)
        world.frames[treeW2] = nil
        let first = harness.maintainer.tick(cause: "AXUIElementDestroyed")
        let placedFirst = world.frames[treeW1]
        harness.clock.advance(spacing)
        world.frames[treeW3] = Rect(x: 100, y: 100, width: 300, height: 200)
        let duringBurst = harness.maintainer.tick(cause: "AXWindowCreated")
        harness.clock.advance(LayoutTolerance.burstQuiet)
        let final = harness.maintainer.tick(cause: "deadline")

        #expect(first.commands == 1)
        #expect(placedFirst == Rect(x: 0, y: 0, width: 1000, height: 500))
        #expect(duringBurst.commands == 0)
        #expect(final.commands >= 1)
        #expect(world.writes[treeW3]?.count == 1)
        #expect(harness.count("layout_stage_membership_settling") == 1)
    }

    /// A18 (remplace l'attente fixe de la 016, réécrit pour l'arbre) : la disparition d'une voisine
    /// est rangée tout de suite et la fenêtre focalisée cachée revient ; un second changement moins
    /// de `burstWindow` plus tard ouvre une rafale : ni restauration ni disposition avant le calme,
    /// puis une passe finale.
    @Test
    func focusedStageRestoreWaitsForRecentMissingMemberToSettle() {
        let hiddenCorner = Rect(x: 999, y: 499, width: 500, height: 500)
        let world = TreeWorld(frames: [treeW1: treeLeft, treeW2: treeRight])
        world.focused = treeW1
        let harness = TreeHarness(
            "focused-restore-burst",
            world: world,
            store: treeStore("focused-restore-burst", tree: treeSideBySide, frames: world.frames)
        )

        _ = harness.maintainer.tick(cause: "startup")
        harness.clock.advance(5)
        world.frames[treeW2] = nil
        world.frames[treeW1] = hiddenCorner
        let first = harness.maintainer.tick(cause: "AXUIElementDestroyed")
        let restored = world.frames[treeW1]
        harness.clock.advance(0.08)
        world.frames[treeW2] = treeRight
        world.frames[treeW1] = hiddenCorner
        let settling = harness.maintainer.tick(cause: "AXWindowCreated")
        let restoresDuringBurst = harness.count("stage_focus_restore")
        harness.clock.advance(LayoutTolerance.burstQuiet)
        let final = harness.maintainer.tick(cause: "deadline")

        #expect(first.commands >= 1)
        #expect(restored == Rect(x: 0, y: 0, width: 1000, height: 500))
        #expect(settling.commands == 0)
        #expect(restoresDuringBurst == 1)
        #expect(harness.count("layout_stage_membership_settling") == 1)
        #expect(final.commands >= 1)
        #expect(world.frames[treeW1] == treeLeft)
        #expect(world.frames[treeW2] == treeRight)
        #expect(harness.count("stage_focus_restore") == 2)
    }

    @Test
    func spatialBspTreeIsNotReconciledDuringMembershipChurn() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let first = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 11,
            appName: "App1",
            bundleID: "app.1",
            title: "Window1",
            frame: Rect(x: 0, y: 0, width: 495, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        let second = WindowSnapshot(
            id: WindowID(rawValue: 2),
            pid: 12,
            appName: "App2",
            bundleID: "app.2",
            title: "Window2",
            frame: Rect(x: 505, y: 0, width: 495, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        let firstDuringChurn = WindowSnapshot(
            id: first.id,
            pid: first.pid,
            appName: first.appName,
            bundleID: first.bundleID,
            title: first.title,
            frame: Rect(x: 0, y: 0, width: 700, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        let stageID = StageID(rawValue: "1")
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: stageID)
        let tree = BSPTree.split(
            orientation: .vertical,
            ratio: 0.5,
            first: .leaf(first.id),
            second: .leaf(second.id)
        )
        let store = StageStore(path: tempPath("roadie-spatial-membership-settle"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: display.id, activeStageID: stageID, stages: [
                    PersistentStage(id: stageID, mode: .spatialBsp, members: [
                        PersistentStageMember(windowID: first.id, bundleID: first.bundleID, title: first.title, frame: first.frame),
                        PersistentStageMember(windowID: second.id, bundleID: second.bundleID, title: second.title, frame: second.frame),
                    ], bspTree: tree)
                ])
            ],
            activeDisplayID: display.id
        ))
        let provider = MultiDisplaySequenceProvider(displaySnapshots: [display], windowSnapshots: [
            [first, second],
            [firstDuringChurn],
        ])
        let service = SnapshotService(
            provider: provider,
            frameWriter: RecordingWriter(),
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .spatialBsp, gapsOuter: 0, gapsInner: 10)),
            stageStore: store
        )
        let currentTime = Date()
        let maintainer = LayoutMaintainer(
            service: service,
            intervalSeconds: 0.1,
            store: store,
            now: { currentTime }
        )

        _ = maintainer.tick()
        _ = maintainer.tick()

        #expect(store.state().bspTree(for: scope) == tree)
    }

    @Test
    func commandActivityDoesNotDelayReclaimAfterStageMemberDisappears() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let live = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 10,
            appName: "Live",
            bundleID: "app.live",
            title: "Live",
            frame: Rect(x: 0, y: 0, width: 495, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        let now = Date()
        let closed = WindowID(rawValue: 2)
        let store = StageStore(path: tempPath("mutable-bsp-closed-member-command-activity"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: display.id, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), mode: .mutableBsp, members: [
                        PersistentStageMember(windowID: live.id, bundleID: live.bundleID, title: live.title, frame: live.frame),
                        PersistentStageMember(
                            windowID: closed,
                            bundleID: "app.closed",
                            title: "Closed",
                            frame: Rect(x: 505, y: 0, width: 495, height: 500),
                            lastSeenAt: now.addingTimeInterval(-1),
                            missingSince: now
                        ),
                    ])
                ])
            ],
            activeDisplayID: display.id
        ))
        let provider = MultiDisplaySequenceProvider(displaySnapshots: [display], windowSnapshots: [[live]])
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .mutableBsp, gapsOuter: 0, gapsInner: 10)),
            stageStore: store
        )
        let commandActivity = LayoutCommandActivity(path: tempPath("layout-command-activity-missing-reclaim"))
        commandActivity.markActive(reason: "test", now: now, holdSeconds: 5)
        let maintainer = LayoutMaintainer(service: service, store: store, commandActivity: commandActivity, now: { now.addingTimeInterval(0.1) })

        let tick = maintainer.tick()

        #expect(tick.commands == 1)
        #expect(writer.requestedFrames[live.id] == Rect(x: 0, y: 0, width: 1000, height: 500))
        commandActivity.reset()
    }

    @Test
    func externalResizeAfterRecentCommandIntentSnapsBackToCommandLayout() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let provider = SequenceProvider(display: display, windowFrames: [
            [
                Rect(x: 0, y: 0, width: 495, height: 500),
                Rect(x: 505, y: 0, width: 495, height: 500),
            ],
            [
                Rect(x: 0, y: 0, width: 700, height: 500),
                Rect(x: 505, y: 0, width: 495, height: 500),
            ],
            [
                Rect(x: 0, y: 0, width: 700, height: 500),
                Rect(x: 505, y: 0, width: 495, height: 500),
            ],
        ])
        let writer = RecordingWriter()
        let intentPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-manual-resize-command-intent-\(UUID().uuidString).json")
            .path
        let eventPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-manual-resize-command-events-\(UUID().uuidString).jsonl")
            .path
        let intentStore = LayoutIntentStore(path: intentPath)
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        var currentTime = Date(timeIntervalSince1970: 0)
        intentStore.save(LayoutIntent(
            scope: scope,
            windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)],
            placements: [
                WindowID(rawValue: 1): Rect(x: 0, y: 0, width: 495, height: 500),
                WindowID(rawValue: 2): Rect(x: 505, y: 0, width: 495, height: 500),
            ],
            createdAt: currentTime,
            source: .command
        ))
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            intentStore: intentStore
        )
        let maintainer = LayoutMaintainer(service: service, events: EventLog(path: eventPath), now: { currentTime })

        _ = maintainer.tick()
        let resizing = maintainer.tick()
        currentTime = currentTime.addingTimeInterval(2)
        let settled = maintainer.tick()

        #expect(!resizing.manualResizeDetected)
        #expect(resizing.commands == 1)
        #expect(settled.commands == 0)
        #expect(writer.requestedFrames[WindowID(rawValue: 1)] == Rect(x: 0, y: 0, width: 495, height: 500))
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        #expect(events.contains("\"type\":\"external_geometry_snapped_to_layout_model\""))
        try? FileManager.default.removeItem(atPath: intentPath)
        try? FileManager.default.removeItem(atPath: eventPath)
    }

    @Test
    func progressiveExternalResizeDuringCommandIntentSnapsBackOnceOutsideTolerance() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let provider = SequenceProvider(display: display, windowFrames: [
            [
                Rect(x: 0, y: 0, width: 495, height: 500),
                Rect(x: 505, y: 0, width: 495, height: 500),
            ],
            [
                Rect(x: 0, y: 0, width: 505, height: 500),
                Rect(x: 505, y: 0, width: 495, height: 500),
            ],
            [
                Rect(x: 0, y: 0, width: 515, height: 500),
                Rect(x: 505, y: 0, width: 495, height: 500),
            ],
        ])
        let writer = RecordingWriter()
        let intentPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-progressive-resize-command-intent-\(UUID().uuidString).json")
            .path
        let intentStore = LayoutIntentStore(path: intentPath)
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        var currentTime = Date(timeIntervalSince1970: 0)
        intentStore.save(LayoutIntent(
            scope: scope,
            windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)],
            placements: [
                WindowID(rawValue: 1): Rect(x: 0, y: 0, width: 495, height: 500),
                WindowID(rawValue: 2): Rect(x: 505, y: 0, width: 495, height: 500),
            ],
            createdAt: currentTime,
            source: .command
        ))
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            intentStore: intentStore
        )
        let maintainer = LayoutMaintainer(service: service, now: { currentTime })

        let initial = maintainer.tick()
        let smallStep = maintainer.tick()
        currentTime = currentTime.addingTimeInterval(0.2)
        let cumulativeStep = maintainer.tick()

        #expect(initial.commands == 0)
        #expect(smallStep.commands == 0)
        #expect(!smallStep.manualResizeDetected)
        #expect(!cumulativeStep.manualResizeDetected)
        #expect(cumulativeStep.commands == 1)
        #expect(writer.requestedFrames[WindowID(rawValue: 1)] == Rect(x: 0, y: 0, width: 495, height: 500))
        try? FileManager.default.removeItem(atPath: intentPath)
    }

    @Test
    func fullscreenLikeChangeDoesNotTriggerManualResizeOrRelayout() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let splitLeft = Rect(x: 0, y: 0, width: 495, height: 500)
        let splitRight = Rect(x: 505, y: 0, width: 495, height: 500)
        let fullscreen = Rect(x: 0, y: 0, width: 1000, height: 500)
        let writer = RecordingWriter()
        let intentTemp = makeIntentStore()
        defer { try? FileManager.default.removeItem(atPath: intentTemp.path) }
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        intentTemp.store.save(LayoutIntent(
            scope: scope,
            windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)],
            placements: [WindowID(rawValue: 1): splitLeft, WindowID(rawValue: 2): splitRight],
            source: .command
        ))
        let service = SnapshotService(
            provider: SequenceProvider(display: display, windowFrames: [
                [splitLeft, splitRight],
                [fullscreen, splitRight],
            ]),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            intentStore: intentTemp.store
        )
        let maintainer = LayoutMaintainer(service: service)

        let initial = maintainer.tick()
        // toggleFullscreen pose le marqueur de zoom (FR-001) : la taille seule ne suffit plus.
        intentTemp.store.save(LayoutIntent(
            scope: scope,
            windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)],
            placements: [WindowID(rawValue: 1): fullscreen, WindowID(rawValue: 2): splitRight],
            source: .command,
            zoomedWindowID: WindowID(rawValue: 1)
        ))
        let fullscreenTick = maintainer.tick()

        #expect(initial.commands == 0)
        #expect(fullscreenTick.commands == 1)
        #expect(!fullscreenTick.manualResizeDetected)
        #expect(writer.requestedFrames[WindowID(rawValue: 1)] == nil)
        #expect(writer.requestedFrames[WindowID(rawValue: 2)] == Rect(x: 999, y: 0, width: 495, height: 500))
    }

    @Test
    func fullscreenLikeWindowHidesActiveStageSiblings() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let fullscreen = Rect(x: 0, y: 0, width: 1000, height: 500)
        let small = Rect(x: 120, y: 0, width: 100, height: 500)
        let writer = RecordingWriter()
        let intentTemp = makeIntentStore()
        defer { try? FileManager.default.removeItem(atPath: intentTemp.path) }
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        intentTemp.store.save(LayoutIntent(
            scope: scope,
            windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)],
            placements: [WindowID(rawValue: 1): fullscreen, WindowID(rawValue: 2): small],
            source: .command,
            zoomedWindowID: WindowID(rawValue: 1)
        ))
        let service = SnapshotService(
            provider: SequenceProvider(
                display: display,
                windowFrames: [[fullscreen, small]]
            ),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            intentStore: intentTemp.store
        )
        let maintainer = LayoutMaintainer(service: service)

        let tick = maintainer.tick()

        #expect(tick.commands == 1)
        #expect(writer.requestedFrames[WindowID(rawValue: 1)] == nil)
        #expect(writer.requestedFrames[WindowID(rawValue: 2)] == Rect(x: 999, y: 0, width: 100, height: 500))
    }

    @Test
    func maximizedLikeWindowWithoutNativeSignalDoesNotHideActiveStageSiblings() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let fullscreenSized = Rect(x: 0, y: 0, width: 1000, height: 500)
        let small = Rect(x: 120, y: 0, width: 100, height: 500)
        let writer = RecordingWriter()
        let eventPath = tempPath("maximized-like-no-sibling-hide-events")
        defer { try? FileManager.default.removeItem(atPath: eventPath) }
        let service = SnapshotService(
            provider: SequenceProvider(display: display, windowFrames: [[fullscreenSized, small]]),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10))
        )
        let maintainer = LayoutMaintainer(service: service, events: EventLog(path: eventPath))

        _ = maintainer.tick()
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""

        #expect(writer.requestedFrames[WindowID(rawValue: 2)] != Rect(x: 999, y: 0, width: 100, height: 500))
        #expect(!events.contains("\"type\":\"fullscreen_stage_siblings_hidden\""))
    }

    @Test
    func shiftedScreenDominantFullscreenSizedWindowIsReanchoredAfterRestart() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 1000, y: -500, width: 1200, height: 800),
            visibleFrame: Rect(x: 1040, y: -460, width: 1100, height: 720),
            isMain: false
        )
        let shiftedFullscreenSized = Rect(x: 1540, y: -460, width: 1100, height: 720)
        let small = Rect(x: 1180, y: -460, width: 300, height: 720)
        let writer = RecordingWriter()
        let eventPath = tempPath("shifted-screen-dominant-reanchor-events")
        let intentTemp = makeIntentStore()
        defer { try? FileManager.default.removeItem(atPath: intentTemp.path) }
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        intentTemp.store.save(LayoutIntent(
            scope: scope,
            windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)],
            placements: [WindowID(rawValue: 1): shiftedFullscreenSized, WindowID(rawValue: 2): small],
            source: .command,
            zoomedWindowID: WindowID(rawValue: 1)
        ))
        let service = SnapshotService(
            provider: SequenceProvider(display: display, windowFrames: [[shiftedFullscreenSized, small]]),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            intentStore: intentTemp.store
        )
        let maintainer = LayoutMaintainer(service: service, events: EventLog(path: eventPath))

        let tick = maintainer.tick()
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""

        // A1 : recalage de la fenêtre zoomée et masquage de sa voisine dans la même passe.
        #expect(tick.commands == 2)
        #expect(writer.requestedFrames[WindowID(rawValue: 1)] == Rect(x: 1040, y: -460, width: 1100, height: 720))
        #expect(writer.requestedFrames[WindowID(rawValue: 2)] != nil)
        #expect(!frameIsVisible(writer.requestedFrames[WindowID(rawValue: 2)], on: display))
        #expect(events.contains("\"type\":\"fullscreen_sized_windows_reanchored\""))
        #expect(events.contains("\"type\":\"fullscreen_stage_siblings_hidden\""))
        try? FileManager.default.removeItem(atPath: eventPath)
    }

    @Test
    func parkedFullscreenSizedWindowIsNotTreatedAsActiveFullscreen() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 1000, y: -500, width: 1200, height: 800),
            visibleFrame: Rect(x: 1040, y: -460, width: 1100, height: 720),
            isMain: false
        )
        let parkedFullscreenSized = Rect(x: 2139, y: -460, width: 1100, height: 720)
        let small = Rect(x: 1180, y: -460, width: 300, height: 720)
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: SequenceProvider(display: display, windowFrames: [[parkedFullscreenSized, small]]),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10))
        )
        let maintainer = LayoutMaintainer(service: service)

        let tick = maintainer.tick()

        #expect(tick.commands > 0)
        #expect(writer.requestedFrames[WindowID(rawValue: 1)] != nil)
    }

    @Test
    func shiftedFullscreenSizedClampedWindowIsReanchoredBeforeSiblingHide() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 1000, y: -500, width: 1200, height: 800),
            visibleFrame: Rect(x: 1040, y: -460, width: 1100, height: 720),
            isMain: false
        )
        let smallLeft = Rect(x: 1100, y: -460, width: 300, height: 720)
        let smallRight = Rect(x: 1500, y: -460, width: 300, height: 720)
        let shiftedFullscreenSized = Rect(x: 1540, y: -460, width: 1100, height: 720)
        let rightTarget = Rect(x: 1595, y: -460, width: 545, height: 720)
        let eventPath = tempPath("shifted-fullscreen-clamped-events")
        let intentTemp = makeIntentStore()
        defer { try? FileManager.default.removeItem(atPath: intentTemp.path) }
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        intentTemp.store.save(LayoutIntent(
            scope: scope,
            windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)],
            placements: [WindowID(rawValue: 1): smallLeft, WindowID(rawValue: 2): smallRight],
            source: .command
        ))
        let service = SnapshotService(
            provider: SequenceProvider(display: display, windowFrames: [
                [smallLeft, smallRight],
                [shiftedFullscreenSized, rightTarget],
            ]),
            frameWriter: SequenceWriter(actualFrames: [
                WindowID(rawValue: 1): shiftedFullscreenSized,
                WindowID(rawValue: 2): rightTarget,
            ]),
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            intentStore: intentTemp.store
        )
        let maintainer = LayoutMaintainer(service: service, events: EventLog(path: eventPath))

        let clamped = maintainer.tick()
        let reanchored = maintainer.tick()
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""

        #expect(clamped.clamped == 0)
        #expect(reanchored.commands == 0)
        #expect(events.contains("\"type\":\"manual_resize_suppressed_by_command_intent\""))
        #expect(!events.contains("\"type\":\"mutable_bsp_resize_propagated\""))
        try? FileManager.default.removeItem(atPath: eventPath)
    }

    @Test
    func fullscreenSiblingHideIsNotAdoptedAsMutableBspResize() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let terminal = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 10,
            appName: "iTerm2",
            bundleID: "com.googlecode.iterm2",
            title: "Terminal",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        let horizon = WindowSnapshot(
            id: WindowID(rawValue: 2),
            pid: 11,
            appName: "Google Chrome",
            bundleID: "com.google.Chrome",
            title: "Horizon Studio",
            frame: Rect(x: 505, y: 0, width: 495, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        let hiddenHorizon = WindowSnapshot(
            id: horizon.id,
            pid: horizon.pid,
            appName: horizon.appName,
            bundleID: horizon.bundleID,
            title: horizon.title,
            frame: Rect(x: 999, y: 0, width: 495, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        let stagePath = tempPath("fullscreen-sibling-hide-no-mutable-adopt")
        let eventPath = tempPath("fullscreen-sibling-hide-no-mutable-adopt-events")
        let intentTemp = makeIntentStore()
        defer {
            try? FileManager.default.removeItem(atPath: stagePath)
            try? FileManager.default.removeItem(atPath: eventPath)
            try? FileManager.default.removeItem(atPath: intentTemp.path)
        }

        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), mode: .mutableBsp, focusedWindowID: terminal.id, members: [
                    PersistentStageMember(windowID: terminal.id, bundleID: terminal.bundleID, title: terminal.title, frame: terminal.frame),
                    PersistentStageMember(windowID: horizon.id, bundleID: horizon.bundleID, title: horizon.title, frame: horizon.frame),
                ]),
            ]),
        ], activeDisplayID: display.id))
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        intentTemp.store.save(LayoutIntent(
            scope: scope,
            windowIDs: [terminal.id, horizon.id],
            placements: [terminal.id: terminal.frame, horizon.id: horizon.frame],
            source: .command,
            zoomedWindowID: terminal.id
        ))

        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: MultiDisplaySequenceProvider(
                displaySnapshots: [display],
                windowSnapshots: [[terminal, horizon], [terminal, hiddenHorizon], [terminal, hiddenHorizon]],
                focusedID: terminal.id
            ),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .mutableBsp, gapsOuter: 0, gapsInner: 10)),
            intentStore: intentTemp.store,
            stageStore: stageStore
        )
        let maintainer = LayoutMaintainer(service: service, events: EventLog(path: eventPath), store: stageStore)

        let hidden = maintainer.tick()
        let stable = maintainer.tick()
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""

        #expect(hidden.commands == 1)
        #expect(writer.requestedFrames[horizon.id] == hiddenHorizon.frame)
        #expect(stable.commands == 0)
        #expect(!stable.manualResizeDetected)
        #expect(events.contains("\"type\":\"fullscreen_stage_siblings_hidden\""))
        #expect(!events.contains("\"type\":\"mutable_bsp_geometry_adopted\""))
        #expect(!events.contains("\"type\":\"layout_clamped\""))
    }

    @Test
    func fullscreenCommandRestoreIntentDoesNotRetileWhileFullscreenIsActive() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let fullscreen = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 11,
            appName: "Firefox",
            bundleID: "org.mozilla.firefox",
            title: "Fullscreen",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        let hiddenSibling = WindowSnapshot(
            id: WindowID(rawValue: 2),
            pid: 12,
            appName: "Finder",
            bundleID: "com.apple.finder",
            title: "Downloads",
            frame: Rect(x: 999, y: 0, width: 495, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        let stagePath = tempPath("fullscreen-command-restore-intent")
        let eventPath = tempPath("fullscreen-command-restore-intent-events")
        let intentTemp = makeIntentStore()
        defer {
            try? FileManager.default.removeItem(atPath: stagePath)
            try? FileManager.default.removeItem(atPath: eventPath)
            try? FileManager.default.removeItem(atPath: intentTemp.path)
        }

        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display.id, activeStageID: scope.stageID, stages: [
                PersistentStage(id: scope.stageID, mode: .mutableBsp, focusedWindowID: fullscreen.id, members: [
                    PersistentStageMember(windowID: fullscreen.id, bundleID: fullscreen.bundleID, title: fullscreen.title, frame: fullscreen.frame),
                    PersistentStageMember(windowID: hiddenSibling.id, bundleID: hiddenSibling.bundleID, title: hiddenSibling.title, frame: hiddenSibling.frame),
                ]),
            ]),
        ], activeDisplayID: display.id))
        intentTemp.store.save(LayoutIntent(
            scope: scope,
            windowIDs: [fullscreen.id, hiddenSibling.id],
            placements: [
                fullscreen.id: Rect(x: 0, y: 0, width: 495, height: 500),
                hiddenSibling.id: Rect(x: 505, y: 0, width: 495, height: 500),
            ],
            source: .command,
            zoomedWindowID: fullscreen.id
        ))

        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: MultiDisplaySequenceProvider(
                displaySnapshots: [display],
                windowSnapshots: [[fullscreen, hiddenSibling]],
                focusedID: fullscreen.id
            ),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .mutableBsp, gapsOuter: 0, gapsInner: 10)),
            intentStore: intentTemp.store,
            stageStore: stageStore
        )
        let maintainer = LayoutMaintainer(service: service, events: EventLog(path: eventPath), store: stageStore)

        let tick = maintainer.tick()
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""

        #expect(tick.commands == 0)
        #expect(writer.requestedFrames.isEmpty)
        #expect(intentTemp.store.intent(for: scope) != nil)
        #expect(!events.contains("\"type\":\"layout_apply\""))
    }

    @Test
    func manualResizeIsNotSuppressedByCommandIntentOnAnotherDisplay() {
        let displayA = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let displayB = DisplaySnapshot(
            id: DisplayID(rawValue: "display-b"),
            index: 2,
            name: "B",
            frame: Rect(x: 1000, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 1000, y: 0, width: 1000, height: 500),
            isMain: false
        )
        let a1 = WindowID(rawValue: 1)
        let a2 = WindowID(rawValue: 2)
        let b1 = WindowID(rawValue: 3)
        let b2 = WindowID(rawValue: 4)
        func window(_ id: WindowID, _ frame: Rect) -> WindowSnapshot {
            WindowSnapshot(
                id: id,
                pid: Int32(id.rawValue + 10),
                appName: "App\(id.rawValue)",
                bundleID: "app.\(id.rawValue)",
                title: "Window\(id.rawValue)",
                frame: frame,
                isOnScreen: true,
                isTileCandidate: true
            )
        }
        let provider = MultiDisplaySequenceProvider(displaySnapshots: [displayA, displayB], windowSnapshots: [
            [
                window(a1, Rect(x: 0, y: 0, width: 495, height: 500)),
                window(a2, Rect(x: 505, y: 0, width: 495, height: 500)),
                window(b1, Rect(x: 1000, y: 0, width: 495, height: 500)),
                window(b2, Rect(x: 1505, y: 0, width: 495, height: 500)),
            ],
            [
                window(a1, Rect(x: 0, y: 0, width: 700, height: 500)),
                window(a2, Rect(x: 505, y: 0, width: 495, height: 500)),
                window(b1, Rect(x: 1000, y: 0, width: 495, height: 500)),
                window(b2, Rect(x: 1505, y: 0, width: 495, height: 500)),
            ],
            [
                window(a1, Rect(x: 0, y: 0, width: 700, height: 500)),
                window(a2, Rect(x: 505, y: 0, width: 495, height: 500)),
                window(b1, Rect(x: 1000, y: 0, width: 495, height: 500)),
                window(b2, Rect(x: 1505, y: 0, width: 495, height: 500)),
            ],
        ])
        let intent = makeIntentStore()
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-cross-display-resize-stages-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        intent.store.save(LayoutIntent(
            scope: StageScope(displayID: displayB.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1")),
            windowIDs: [b1, b2],
            placements: [
                b1: Rect(x: 1000, y: 0, width: 495, height: 500),
                b2: Rect(x: 1505, y: 0, width: 495, height: 500),
            ],
            source: .command
        ))
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            intentStore: intent.store,
            stageStore: stageStore
        )
        var currentTime = Date(timeIntervalSince1970: 0)
        let maintainer = LayoutMaintainer(service: service, now: { currentTime })

        _ = maintainer.tick()
        let resizing = maintainer.tick()
        currentTime = currentTime.addingTimeInterval(2)
        let settled = maintainer.tick()

        #expect(resizing.manualResizeDetected)
        #expect(settled.commands == 1)
        #expect(writer.requestedFrames[a2] == Rect(x: 710, y: 0, width: 290, height: 500))
        try? FileManager.default.removeItem(atPath: intent.path)
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func ownAppliedFramesAreNotTreatedAsManualResizeOnNextTick() {
        let intent = makeIntentStore()
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let targetA = Rect(x: 0, y: 0, width: 495, height: 500)
        let targetB = Rect(x: 505, y: 0, width: 495, height: 500)
        let provider = SequenceProvider(display: display, windowFrames: [
            [
                Rect(x: 0, y: 0, width: 100, height: 100),
                Rect(x: 100, y: 0, width: 100, height: 100),
            ],
            [targetA, targetB],
        ])
        let service = SnapshotService(
            provider: provider,
            frameWriter: SequenceWriter(actualFrames: [
                WindowID(rawValue: 1): targetA,
                WindowID(rawValue: 2): targetB,
            ]),
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            intentStore: intent.store
        )
        let maintainer = LayoutMaintainer(service: service)

        let applied = maintainer.tick()
        let next = maintainer.tick()

        #expect(applied.commands == 2)
        #expect(!next.manualResizeDetected)
        #expect(next.commands == 0)
        try? FileManager.default.removeItem(atPath: intent.path)
    }

    @Test
    func growthClampedFramesAreExcludedWithoutPersistingBrokenLayoutIntent() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let firstInitial = Rect(x: 0, y: 0, width: 100, height: 500)
        let secondInitial = Rect(x: 120, y: 0, width: 100, height: 500)
        let firstTarget = Rect(x: 0, y: 0, width: 495, height: 500)
        let secondActual = Rect(x: 505, y: 0, width: 250, height: 500)
        let intentPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-clamp-intent-\(UUID().uuidString).json")
            .path
        let eventPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-clamp-events-\(UUID().uuidString).jsonl")
            .path
        let intentStore = LayoutIntentStore(path: intentPath)
        let config = RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10))

        let clampingService = SnapshotService(
            provider: SequenceProvider(display: display, windowFrames: [
                [firstInitial, secondInitial],
                [firstTarget, secondActual],
            ]),
            frameWriter: SequenceWriter(actualFrames: [
                WindowID(rawValue: 1): firstTarget,
                WindowID(rawValue: 2): secondActual,
            ]),
            config: config,
            intentStore: intentStore
        )
        let maintainer = LayoutMaintainer(service: clampingService, events: EventLog(path: eventPath))

        let tick = maintainer.tick()
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""

        // Plan (2) + réparation de la voisine (1) : le compteur inclut la réparation (FR-040).
        #expect(tick.commands == 3)
        #expect(tick.clamped == 1)
        #expect(events.contains("\"type\":\"layout_clamped_scope_repaired\""))
        #expect(events.contains("\"type\":\"layout_apply\""))
        #expect(events.contains("\"type\":\"layout_clamped\""))
        #expect(intentStore.intent(for: StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))) == nil)
        #expect(maintainer.tick().commands == 1)

        let restartedService = SnapshotService(
            provider: SequenceProvider(display: display, windowFrames: [[firstTarget, secondActual]]),
            frameWriter: SequenceWriter(actualFrames: [
                WindowID(rawValue: 1): firstTarget,
                WindowID(rawValue: 2): secondActual,
            ]),
            config: config,
            intentStore: intentStore
        )

        #expect(!restartedService.applyPlan(from: restartedService.snapshot()).commands.isEmpty)
        try? FileManager.default.removeItem(atPath: intentPath)
        try? FileManager.default.removeItem(atPath: eventPath)
    }

    @Test
    func clampedMinimumSizeSuppressesLaterSmallerRequests() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let firstInitial = Rect(x: 0, y: 0, width: 100, height: 500)
        let secondInitial = Rect(x: 120, y: 0, width: 100, height: 500)
        let firstTarget = Rect(x: 0, y: 0, width: 495, height: 500)
        let secondActual = Rect(x: 505, y: 0, width: 600, height: 500)
        let service = SnapshotService(
            provider: SequenceProvider(display: display, windowFrames: [
                [firstInitial, secondInitial],
                [firstTarget, secondActual],
            ]),
            frameWriter: SequenceWriter(actualFrames: [
                WindowID(rawValue: 1): firstTarget,
                WindowID(rawValue: 2): secondActual,
            ]),
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10))
        )
        let maintainer = LayoutMaintainer(service: service)

        let clamped = maintainer.tick()
        let suppressed = maintainer.tick()

        #expect(clamped.clamped == 1)
        #expect(suppressed.commands == 0)
    }

    @Test
    func clampedMinimumSizeSuppressesLaterSmallerRequestsEvenWhenMacOSShiftsPosition() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let firstInitial = Rect(x: 0, y: 0, width: 100, height: 500)
        let secondInitial = Rect(x: 120, y: 0, width: 100, height: 500)
        let firstTarget = Rect(x: 0, y: 0, width: 495, height: 500)
        let secondReportedActual = Rect(x: 505, y: 0, width: 600, height: 500)
        let secondMacOSAdjusted = Rect(x: 360, y: 0, width: 600, height: 500)
        let service = SnapshotService(
            provider: SequenceProvider(display: display, windowFrames: [
                [firstInitial, secondInitial],
                [firstTarget, secondMacOSAdjusted],
            ]),
            frameWriter: SequenceWriter(actualFrames: [
                WindowID(rawValue: 1): firstTarget,
                WindowID(rawValue: 2): secondReportedActual,
            ]),
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10))
        )
        let maintainer = LayoutMaintainer(service: service)

        let clamped = maintainer.tick()
        let suppressed = maintainer.tick()

        #expect(clamped.clamped == 1)
        #expect(suppressed.commands == 0)
    }

    @Test
    func clampedMinimumSizeSuppressesLaterSmallerRequestsEvenAfterWindowGrows() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let firstInitial = Rect(x: 0, y: 0, width: 100, height: 500)
        let secondInitial = Rect(x: 120, y: 0, width: 100, height: 500)
        let firstTarget = Rect(x: 0, y: 0, width: 495, height: 500)
        let secondReportedActual = Rect(x: 505, y: 0, width: 600, height: 500)
        let secondGrownByRepair = Rect(x: 300, y: 0, width: 700, height: 500)
        let service = SnapshotService(
            provider: SequenceProvider(display: display, windowFrames: [
                [firstInitial, secondInitial],
                [firstTarget, secondGrownByRepair],
            ]),
            frameWriter: SequenceWriter(actualFrames: [
                WindowID(rawValue: 1): firstTarget,
                WindowID(rawValue: 2): secondReportedActual,
            ]),
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10))
        )
        let maintainer = LayoutMaintainer(service: service)

        let clamped = maintainer.tick()
        let suppressed = maintainer.tick()

        #expect(clamped.clamped == 1)
        #expect(suppressed.commands == 0)
    }

    @Test
    func shrinkClampedWideWindowRepairsSiblingIntoRemainingSpace() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 2048, height: 1280),
            visibleFrame: Rect(x: 150, y: 38, width: 1898, height: 1234),
            isMain: true
        )
        let finder = Rect(x: 150, y: 38, width: 557, height: 1234)
        let firefoxInitial = Rect(x: 707, y: 38, width: 1341, height: 1234)
        let firefoxActual = Rect(x: 569, y: 38, width: 1479, height: 1234)
        let writer = RecordingSequenceWriter(actualFrames: [
            WindowID(rawValue: 2): firefoxActual,
        ])
        let eventPath = tempPath("shrink-clamped-wide-window-repair-events")
        defer { try? FileManager.default.removeItem(atPath: eventPath) }
        let service = SnapshotService(
            provider: SequenceProvider(display: display, windowFrames: [
                [finder, firefoxInitial],
            ]),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .bsp, gapsOuter: 0, gapsInner: 10))
        )
        let maintainer = LayoutMaintainer(service: service, events: EventLog(path: eventPath))

        let tick = maintainer.tick()
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""

        #expect(tick.clamped == 1)
        #expect(writer.requestedFrames[WindowID(rawValue: 1)] == Rect(x: 150, y: 38, width: 409, height: 1234))
        #expect(events.contains("\"type\":\"layout_clamped_scope_repaired\""))
    }

    /// T222 : avec le câblage de production, le budget A13 ne coupe pas la chaîne sans arbre.
    @Test(arguments: [false, true])
    func mutuallyClampedOversizedWindowsIsolateLargestWindowInsteadOfThrashing(productionWiring: Bool) {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 2048, height: 1280),
            visibleFrame: Rect(x: 150, y: 38, width: 1898, height: 1234),
            isMain: true
        )
        let finderInitial = Rect(x: 150, y: 38, width: 557, height: 1234)
        let firefoxInitial = Rect(x: 707, y: 38, width: 1341, height: 1234)
        let finderActual = Rect(x: 150, y: 38, width: 557, height: 1234)
        let firefoxActual = Rect(x: 536, y: 30, width: 1512, height: 1235)
        let writer = RecordingSequenceWriter(actualFrames: [
            WindowID(rawValue: 1): finderActual,
            WindowID(rawValue: 2): firefoxActual,
        ])
        let wiring = BudgetWiring(writer, production: productionWiring)
        let eventPath = tempPath("mutually-clamped-oversized-isolate-events")
        defer { try? FileManager.default.removeItem(atPath: eventPath) }
        let service = SnapshotService(
            provider: SequenceProvider(display: display, windowFrames: [
                [finderInitial, firefoxInitial],
            ]),
            frameWriter: wiring.writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .bsp, gapsOuter: 0, gapsInner: 10)),
            frameRegistry: wiring.registry ?? .shared
        )
        let maintainer = LayoutMaintainer(
            service: service, events: EventLog(path: eventPath),
            writtenFrames: wiring.registry, generations: wiring.generations
        )

        let tick = maintainer.tick()
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""

        // Les deux essais de disposition aux tailles minimales (FR-003) clampent aussi avant le masquage.
        #expect(tick.clamped >= 2)
        #expect(events.contains("\"type\":\"layout_clamped_scope_rearranged\"") == false)
        #expect(tick.applied >= 1)
        #expect(writer.requestedFrames[WindowID(rawValue: 1)] != finderInitial)
        #expect(events.contains("\"type\":\"layout_infeasible_scope_isolated\""))
        #expect(events.contains("\"keptWindowID\":\"2\""))
    }

    @Test
    func clampedHeightExcludesWindowAndRelayoutsRemainingTiles() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let firstInitial = Rect(x: 0, y: 0, width: 100, height: 500)
        let secondInitial = Rect(x: 120, y: 0, width: 100, height: 88)
        let firstTarget = Rect(x: 0, y: 0, width: 495, height: 500)
        let secondActual = Rect(x: 505, y: 0, width: 250, height: 88)
        let service = SnapshotService(
            provider: SequenceProvider(display: display, windowFrames: [
                [firstInitial, secondInitial],
                [firstTarget, secondActual],
            ]),
            frameWriter: SequenceWriter(actualFrames: [
                WindowID(rawValue: 1): firstTarget,
                WindowID(rawValue: 2): secondActual,
            ]),
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10))
        )
        let maintainer = LayoutMaintainer(service: service)

        let clamped = maintainer.tick()
        let reclaimed = maintainer.tick()

        #expect(clamped.clamped == 1)
        #expect(reclaimed.commands == 1)
    }

    @Test
    func stableVisibleDisplayDriftIsReconciledAfterRulesAndManualMovesHadPriority() throws {
        let leftDisplay = powerDisplay("display-a", index: 1, x: 0)
        let rightDisplay = powerDisplay("display-b", index: 2, x: 1000)
        let window = powerWindow(9, x: 1200, y: 100, width: 300, height: 300, app: "Settings")
        let stagePath = tempPath("layout-maintainer-physical-display-reconcile")
        let eventPath = tempPath("layout-maintainer-physical-display-reconcile-events")
        defer {
            try? FileManager.default.removeItem(atPath: stagePath)
            try? FileManager.default.removeItem(atPath: eventPath)
        }

        let store = StageStore(path: stagePath)
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: leftDisplay.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [
                    PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: Rect(x: 100, y: 100, width: 300, height: 300)),
                ]),
            ]),
            PersistentStageScope(displayID: rightDisplay.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1")),
            ]),
        ]))
        let service = SnapshotService(
            provider: MultiDisplaySequenceProvider(displaySnapshots: [leftDisplay, rightDisplay], windowSnapshots: [[window]]),
            frameWriter: RecordingWriter(),
            stageStore: store
        )
        let maintainer = LayoutMaintainer(service: service, events: EventLog(path: eventPath), store: store)

        let tick = maintainer.tick()
        var state = store.state()
        let events = try String(contentsOfFile: eventPath, encoding: .utf8)

        #expect(tick.commands >= 1)
        #expect(state.scope(displayID: leftDisplay.id).memberIDs(in: StageID(rawValue: "1")).isEmpty)
        #expect(state.scope(displayID: rightDisplay.id).memberIDs(in: StageID(rawValue: "1")) == [window.id])
        #expect(events.contains("\"type\":\"window.scope_reconciled_to_physical_display\""))
        #expect(events.contains("\"reason\":\"stable_visible_frame_on_different_display\""))
    }

    @Test
    func failedStableVisibleDisplayDriftDoesNotCommitMembership() throws {
        let leftDisplay = powerDisplay("display-a", index: 1, x: 0)
        let rightDisplay = powerDisplay("display-b", index: 2, x: 1000)
        let window = powerWindow(9, x: 1200, y: 100, width: 300, height: 300, app: "Settings")
        let stagePath = tempPath("layout-maintainer-physical-display-reconcile-failed")
        let eventPath = tempPath("layout-maintainer-physical-display-reconcile-failed-events")
        defer {
            try? FileManager.default.removeItem(atPath: stagePath)
            try? FileManager.default.removeItem(atPath: eventPath)
        }

        let store = StageStore(path: stagePath)
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: leftDisplay.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [
                    PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
                ]),
            ]),
            PersistentStageScope(displayID: rightDisplay.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1")),
            ]),
        ]))
        let writer = FailingWriter()
        let service = SnapshotService(
            provider: MultiDisplaySequenceProvider(displaySnapshots: [leftDisplay, rightDisplay], windowSnapshots: [[window]]),
            frameWriter: writer,
            stageStore: store
        )
        let clock = TestClock()
        let maintainer = LayoutMaintainer(service: service, events: EventLog(path: eventPath), store: store, now: { clock.now })

        let tick = maintainer.tick()
        let attempts = writer.attempts
        for _ in 0..<20 {
            clock.advance(0.1)
            _ = maintainer.tick(cause: "deadline")
        }
        #expect(writer.attempts == attempts)
        clock.advance(2)
        _ = maintainer.tick()
        #expect(writer.attempts > attempts)
        var state = store.state()
        let events = try String(contentsOfFile: eventPath, encoding: .utf8)

        #expect(tick.failed > 0)
        #expect(state.scope(displayID: leftDisplay.id).memberIDs(in: StageID(rawValue: "1")) == [window.id])
        #expect(state.scope(displayID: rightDisplay.id).memberIDs(in: StageID(rawValue: "1")).isEmpty)
        #expect(events.contains("\"type\":\"window.scope_reconcile_failed\""))
        #expect(!events.contains("\"type\":\"window.scope_reconciled_to_physical_display\""))
    }

    /// FR-013 : l'annulation d'une réconciliation d'écran échouée ne remet que le membre déplacé ;
    /// une écriture faite par un autre acteur pendant l'application AX est conservée.
    @Test
    func failedStableVisibleDisplayDriftRevertKeepsConcurrentChanges() throws {
        let leftDisplay = powerDisplay("display-a", index: 1, x: 0)
        let rightDisplay = powerDisplay("display-b", index: 2, x: 1000)
        let window = powerWindow(9, x: 1200, y: 100, width: 300, height: 300, app: "Settings")
        let stagePath = tempPath("layout-maintainer-physical-display-revert-concurrent")
        let eventPath = tempPath("layout-maintainer-physical-display-revert-concurrent-events")
        defer {
            try? FileManager.default.removeItem(atPath: stagePath)
            try? FileManager.default.removeItem(atPath: eventPath)
        }

        let store = StageStore(path: stagePath)
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: leftDisplay.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [
                    PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
                ]),
            ]),
            PersistentStageScope(displayID: rightDisplay.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1")),
            ]),
        ]))
        let writer = FailingWriter()
        writer.onAttempt = {
            store.mutate { $0.setLabel("concurrent", displayID: rightDisplay.id, desktopID: DesktopID(rawValue: 1)) }
        }
        let service = SnapshotService(
            provider: MultiDisplaySequenceProvider(displaySnapshots: [leftDisplay, rightDisplay], windowSnapshots: [[window]]),
            frameWriter: writer,
            stageStore: store
        )
        let maintainer = LayoutMaintainer(service: service, events: EventLog(path: eventPath), store: store)

        let tick = maintainer.tick()
        var state = store.state()

        #expect(tick.failed > 0)
        #expect(writer.attempts > 0)
        #expect(state.scope(displayID: leftDisplay.id).memberIDs(in: StageID(rawValue: "1")) == [window.id])
        #expect(state.scope(displayID: rightDisplay.id).memberIDs(in: StageID(rawValue: "1")).isEmpty)
        #expect(state.label(displayID: rightDisplay.id, desktopID: DesktopID(rawValue: 1)) == "concurrent")
    }

    @Test
    func stableVisibleDisplayDriftIsIgnoredImmediatelyAfterTopologyChange() throws {
        let initialDisplay = powerDisplay("display-a", index: 1, x: 0)
        let movedDisplay = powerDisplay("display-a", index: 2, x: 1000)
        let newDisplay = powerDisplay("display-b", index: 1, x: 0)
        let window = powerWindow(9, x: 100, y: 100, width: 300, height: 300, app: "Settings")
        let stagePath = tempPath("layout-maintainer-physical-display-reconcile-topology")
        let eventPath = tempPath("layout-maintainer-physical-display-reconcile-topology-events")
        defer {
            try? FileManager.default.removeItem(atPath: stagePath)
            try? FileManager.default.removeItem(atPath: eventPath)
        }

        let store = StageStore(path: stagePath)
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: initialDisplay.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [
                    PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
                ]),
            ]),
            PersistentStageScope(displayID: newDisplay.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1")),
            ]),
        ]))
        var currentTime = Date(timeIntervalSince1970: 0)
        let service = SnapshotService(
            provider: DynamicDisplaySequenceProvider(
                displaySnapshots: [[initialDisplay], [newDisplay, movedDisplay], [newDisplay, movedDisplay]],
                windowSnapshots: [[window], [window], [window]]
            ),
            frameWriter: RecordingWriter(),
            stageStore: store
        )
        let maintainer = LayoutMaintainer(
            service: service,
            events: EventLog(path: eventPath),
            intervalSeconds: 0.1,
            store: store,
            now: { currentTime }
        )

        _ = maintainer.tick()
        currentTime = Date(timeIntervalSince1970: 0.1)
        _ = maintainer.tick()
        currentTime = Date(timeIntervalSince1970: 2.0)
        _ = maintainer.tick()

        var state = store.state()
        let events = try String(contentsOfFile: eventPath, encoding: .utf8)
        #expect(state.scope(displayID: initialDisplay.id).memberIDs(in: StageID(rawValue: "1")) == [window.id])
        #expect(state.scope(displayID: newDisplay.id).memberIDs(in: StageID(rawValue: "1")).isEmpty)
        #expect(!events.contains("\"type\":\"window.scope_reconciled_to_physical_display\""))
    }

    @Test
    func displayTopologyChangeSuppressesRelayoutUntilSettled() {
        let displayA = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let displayB = DisplaySnapshot(
            id: DisplayID(rawValue: "display-b"),
            index: 2,
            name: "B",
            frame: Rect(x: 1000, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 1000, y: 0, width: 1000, height: 500),
            isMain: false
        )
        let firstTarget = Rect(x: 0, y: 0, width: 495, height: 500)
        let secondTarget = Rect(x: 505, y: 0, width: 495, height: 500)
        let firstSmall = Rect(x: 0, y: 0, width: 100, height: 500)
        let secondSmall = Rect(x: 120, y: 0, width: 100, height: 500)
        let first = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "first", frame: firstTarget, isOnScreen: true, isTileCandidate: true)
        let second = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "second", frame: secondTarget, isOnScreen: true, isTileCandidate: true)
        let firstNeedsLayout = WindowSnapshot(id: first.id, pid: first.pid, appName: first.appName, bundleID: first.bundleID, title: first.title, frame: firstSmall, isOnScreen: true, isTileCandidate: true)
        let secondNeedsLayout = WindowSnapshot(id: second.id, pid: second.pid, appName: second.appName, bundleID: second.bundleID, title: second.title, frame: secondSmall, isOnScreen: true, isTileCandidate: true)
        var currentTime = Date(timeIntervalSince1970: 0)
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: DynamicDisplaySequenceProvider(
                displaySnapshots: [[displayA], [displayA, displayB], [displayA, displayB]],
                windowSnapshots: [[first, second], [firstNeedsLayout, secondNeedsLayout], [firstNeedsLayout, secondNeedsLayout]]
            ),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10))
        )
        let maintainer = LayoutMaintainer(service: service, intervalSeconds: 0.1, now: { currentTime })

        #expect(maintainer.tick().commands == 0)
        currentTime = Date(timeIntervalSince1970: 0.1)
        let suppressed = maintainer.tick()
        #expect(suppressed.commands == 0)
        #expect(writer.requestedFrames.isEmpty)

        currentTime = Date(timeIntervalSince1970: 2.0)
        let applied = maintainer.tick()
        #expect(applied.commands == 2)
        #expect(writer.requestedFrames[first.id] == firstTarget)
        #expect(writer.requestedFrames[second.id] == secondTarget)
    }

    @Test
    func clampedFrameIsReanchoredToRequestedOriginWithActualSize() {
        let intent = makeIntentStore()
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let initial = Rect(x: 0, y: 80, width: 100, height: 100)
        let driftedClamp = Rect(x: 0, y: 80, width: 495, height: 240)
        let writer = ClampingWriter(firstActual: driftedClamp)
        let service = SnapshotService(
            provider: SequenceProvider(display: display, windowFrames: [[initial]]),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            intentStore: intent.store
        )
        let maintainer = LayoutMaintainer(service: service)

        let tick = maintainer.tick()

        #expect(tick.clamped == 1)
        #expect(writer.requestedFrames == [
            Rect(x: 0, y: 0, width: 1000, height: 500),
            Rect(x: 0, y: 0, width: 495, height: 240),
        ])
        try? FileManager.default.removeItem(atPath: intent.path)
    }

    @Test
    func inactiveStageWindowsAreHiddenInAerospaceCorner() {
        let intent = makeIntentStore()
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let window = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 10,
            appName: "A",
            bundleID: "a",
            title: "inactive",
            frame: Rect(x: 0, y: 0, width: 495, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-maintainer-stages-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(
                displayID: display.id,
                activeStageID: StageID(rawValue: "2"),
                stages: [
                    PersistentStage(id: StageID(rawValue: "1"), members: [
                        PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
                    ]),
                    PersistentStage(id: StageID(rawValue: "2")),
                ]
            ),
        ]))
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: SequenceProvider(display: display, windowFrames: [[window.frame]]),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            intentStore: intent.store,
            stageStore: stageStore
        )
        let maintainer = LayoutMaintainer(service: service)

        let tick = maintainer.tick()

        #expect(tick.commands == 1)
        #expect(writer.requestedFrames[window.id] == Rect(x: 999, y: 0, width: 495, height: 500))
        try? FileManager.default.removeItem(atPath: stagePath)
        try? FileManager.default.removeItem(atPath: intent.path)
    }

    @Test
    func inactiveFullscreenLikeStageWindowIsNotHidden() {
        let intent = makeIntentStore()
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let window = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 10,
            appName: "A",
            bundleID: "a",
            title: "fullscreen",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isOnScreen: true,
            isTileCandidate: true,
            // FR-001 : seul le plein écran signalé par macOS (ou un zoom de commande) protège la fenêtre.
            furniture: WindowFurniture(isNativeFullscreen: true)
        )
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-maintainer-fullscreen-hide-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(
                displayID: display.id,
                activeStageID: StageID(rawValue: "2"),
                stages: [
                    PersistentStage(id: StageID(rawValue: "1"), members: [
                        PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
                    ]),
                    PersistentStage(id: StageID(rawValue: "2")),
                ]
            ),
        ]))
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: MultiDisplaySequenceProvider(displaySnapshots: [display], windowSnapshots: [[window]]),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            intentStore: intent.store,
            stageStore: stageStore
        )
        let maintainer = LayoutMaintainer(service: service)

        let tick = maintainer.tick()

        #expect(tick.commands == 0)
        #expect(writer.requestedFrames.isEmpty)
        try? FileManager.default.removeItem(atPath: stagePath)
        try? FileManager.default.removeItem(atPath: intent.path)
    }

    @Test
    func inactiveFloatingStageWindowsAreRemovedFromStageManagement() {
        let intent = makeIntentStore()
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let window = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 10,
            appName: "Settings",
            bundleID: "settings",
            title: "Settings",
            frame: Rect(x: 0, y: 0, width: 640, height: 420),
            isOnScreen: true,
            isTileCandidate: true,
            subrole: "AXStandardWindow",
            role: "AXWindow",
            furniture: WindowFurniture(hasCloseButton: true, hasMinimizeButton: true, isMain: true, isResizable: false)
        )
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-maintainer-floating-stages-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(
                displayID: display.id,
                activeStageID: StageID(rawValue: "2"),
                stages: [
                    PersistentStage(id: StageID(rawValue: "1"), members: [
                        PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
                    ]),
                    PersistentStage(id: StageID(rawValue: "2")),
                ]
            ),
        ]))
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: MultiDisplaySequenceProvider(displaySnapshots: [display], windowSnapshots: [[window]]),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            intentStore: intent.store,
            stageStore: stageStore
        )
        let maintainer = LayoutMaintainer(service: service)

        let tick = maintainer.tick()

        #expect(tick.commands == 0)
        #expect(writer.requestedFrames.isEmpty)
        try? FileManager.default.removeItem(atPath: stagePath)
        try? FileManager.default.removeItem(atPath: intent.path)
    }

    @Test
    func focusedStageRestoreAndInactiveHidingShareOnePass() {
        let leftDisplay = powerDisplay("display-a", index: 1, x: 0)
        let rightDisplay = powerDisplay("display-b", index: 2, x: 1000)
        let focusedHidden = powerWindow(
            1,
            x: leftDisplay.visibleFrame.x + leftDisplay.visibleFrame.width - 1,
            y: leftDisplay.visibleFrame.y + leftDisplay.visibleFrame.height - 1,
            width: 300,
            height: 240
        )
        let inactiveRight = powerWindow(2, x: 1100, y: 100, width: 300, height: 240)
        let stagePath = tempPath("focused-restore-display-local-hide")
        let eventPath = tempPath("focused-restore-display-local-hide-events")
        defer {
            try? FileManager.default.removeItem(atPath: stagePath)
            try? FileManager.default.removeItem(atPath: eventPath)
        }

        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: leftDisplay.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: focusedHidden.id, members: [
                    PersistentStageMember(windowID: focusedHidden.id, bundleID: focusedHidden.bundleID, title: focusedHidden.title, frame: focusedHidden.frame),
                ]),
            ]),
            PersistentStageScope(displayID: rightDisplay.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1")),
                PersistentStage(id: StageID(rawValue: "2"), members: [
                    PersistentStageMember(windowID: inactiveRight.id, bundleID: inactiveRight.bundleID, title: inactiveRight.title, frame: inactiveRight.frame),
                ]),
            ]),
        ], activeDisplayID: leftDisplay.id))
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: MultiDisplaySequenceProvider(
                displaySnapshots: [leftDisplay, rightDisplay],
                windowSnapshots: [[focusedHidden, inactiveRight]],
                focusedID: focusedHidden.id
            ),
            frameWriter: writer,
            stageStore: stageStore
        )
        let maintainer = LayoutMaintainer(service: service, events: EventLog(path: eventPath), store: stageStore)

        let tick = maintainer.tick()
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""

        // A1 : la restauration du focus et le masquage de la stage inactive de l'autre écran se
        // font dans la même passe ; l'événement ne compte que le masquage de l'écran restauré.
        #expect(tick.commands == 2)
        #expect(writer.requestedFrames[focusedHidden.id] != nil)
        #expect(writer.requestedFrames[inactiveRight.id] != nil)
        #expect(!frameIsVisible(writer.requestedFrames[inactiveRight.id], on: rightDisplay))
        #expect(events.contains("\"type\":\"stage_focus_restore\""))
        #expect(events.contains("\"hiddenInactive\":\"0\""))
        #expect(events.contains("\"focusedDisplayID\":\"display-a\""))
    }

    @Test
    func focusedHiddenFullscreenSizedWindowRestoresWithoutBspRelayout() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let focusedHidden = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 11,
            appName: "Firefox",
            bundleID: "org.mozilla.firefox",
            title: "Fullscreen",
            frame: Rect(x: 999, y: 0, width: 1000, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        let siblingHidden = WindowSnapshot(
            id: WindowID(rawValue: 2),
            pid: 12,
            appName: "Finder",
            bundleID: "com.apple.finder",
            title: "Downloads",
            frame: Rect(x: 999, y: 0, width: 300, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        let stagePath = tempPath("focused-fullscreen-restore-no-bsp")
        let eventPath = tempPath("focused-fullscreen-restore-no-bsp-events")
        let intentTemp = makeIntentStore()
        defer {
            try? FileManager.default.removeItem(atPath: stagePath)
            try? FileManager.default.removeItem(atPath: eventPath)
            try? FileManager.default.removeItem(atPath: intentTemp.path)
        }

        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), mode: .mutableBsp, focusedWindowID: focusedHidden.id, members: [
                    PersistentStageMember(windowID: focusedHidden.id, bundleID: focusedHidden.bundleID, title: focusedHidden.title, frame: focusedHidden.frame),
                    PersistentStageMember(windowID: siblingHidden.id, bundleID: siblingHidden.bundleID, title: siblingHidden.title, frame: siblingHidden.frame),
                ]),
            ]),
        ], activeDisplayID: display.id))
        intentTemp.store.save(LayoutIntent(
            scope: scope,
            windowIDs: [focusedHidden.id, siblingHidden.id],
            placements: [focusedHidden.id: display.visibleFrame, siblingHidden.id: siblingHidden.frame],
            source: .command,
            zoomedWindowID: focusedHidden.id
        ))
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: MultiDisplaySequenceProvider(
                displaySnapshots: [display],
                windowSnapshots: [[focusedHidden, siblingHidden]],
                focusedID: focusedHidden.id
            ),
            frameWriter: writer,
            intentStore: intentTemp.store,
            stageStore: stageStore
        )
        let maintainer = LayoutMaintainer(service: service, events: EventLog(path: eventPath), store: stageStore)

        let tick = maintainer.tick()
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""

        #expect(tick.commands == 1)
        #expect(writer.requestedFrames[focusedHidden.id] == display.visibleFrame)
        #expect(writer.requestedFrames[siblingHidden.id] == nil)
        #expect(events.contains("\"type\":\"stage_focus_fullscreen_restore\""))
        #expect(!events.contains("\"type\":\"stage_focus_restore\""))
        #expect(!events.contains("\"type\":\"layout_clamped\""))
    }

    @Test
    func commandIntentBlocksImmediateReflow() {
        let intentTemp = makeIntentStore()
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let intentScope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let writer = RecordingWriter()
        let intentStore = intentTemp.store
        intentStore.save(
            LayoutIntent(
                scope: intentScope,
                windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)],
                placements: [
                    WindowID(rawValue: 1): Rect(x: 0, y: 0, width: 495, height: 500),
                    WindowID(rawValue: 2): Rect(x: 505, y: 0, width: 495, height: 500),
                ],
                source: .command
            )
        )

        let service = SnapshotService(
            provider: SequenceProvider(
                display: display,
                windowFrames: [
                    [Rect(x: 0, y: 0, width: 495, height: 500), Rect(x: 505, y: 0, width: 495, height: 500)],
                ]
            ),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            intentStore: intentStore
        )

        let maintainer = LayoutMaintainer(service: service, intervalSeconds: 0.1)
        let result = maintainer.tick()

        #expect(result.commands == 0)
        #expect(writer.requestedFrames.isEmpty)
        try? FileManager.default.removeItem(atPath: intentTemp.path)
    }

    @Test
    func unmatchedCommandIntentIsRetried() {
        let intentTemp = makeIntentStore()
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let intentScope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let writer = RecordingWriter()
        let intentStore = intentTemp.store
        intentStore.save(
            LayoutIntent(
                scope: intentScope,
                windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)],
                placements: [
                    WindowID(rawValue: 1): Rect(x: 0, y: 0, width: 495, height: 500),
                    WindowID(rawValue: 2): Rect(x: 505, y: 0, width: 495, height: 500),
                ],
                source: .command
            )
        )

        let service = SnapshotService(
            provider: SequenceProvider(
                display: display,
                windowFrames: [
                    [Rect(x: 0, y: 0, width: 300, height: 500), Rect(x: 700, y: 0, width: 300, height: 500)],
                ]
            ),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .bsp, gapsOuter: 0, gapsInner: 10)),
            intentStore: intentStore
        )

        let maintainer = LayoutMaintainer(service: service, intervalSeconds: 0.1)
        let result = maintainer.tick()

        #expect(result.commands == 2)
        #expect(writer.requestedFrames[WindowID(rawValue: 1)] == Rect(x: 0, y: 0, width: 495, height: 500))
        #expect(writer.requestedFrames[WindowID(rawValue: 2)] == Rect(x: 505, y: 0, width: 495, height: 500))
        try? FileManager.default.removeItem(atPath: intentTemp.path)
    }

    @Test
    func commandIntentCanKeepSmallPaneAfterFreshnessWindow() {
        let intentTemp = makeIntentStore()
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let intentScope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let writer = RecordingWriter()
        let intentStore = intentTemp.store
        intentStore.save(
            LayoutIntent(
                scope: intentScope,
                windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)],
                placements: [
                    WindowID(rawValue: 1): Rect(x: 0, y: 0, width: 100, height: 500),
                    WindowID(rawValue: 2): Rect(x: 110, y: 0, width: 890, height: 500),
                ],
                createdAt: Date().addingTimeInterval(-30),
                source: .command
            )
        )

        let service = SnapshotService(
            provider: SequenceProvider(
                display: display,
                windowFrames: [
                    [Rect(x: 0, y: 0, width: 495, height: 500), Rect(x: 505, y: 0, width: 495, height: 500)],
                ]
            ),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .bsp, gapsOuter: 0, gapsInner: 10)),
            intentStore: intentStore
        )

        let maintainer = LayoutMaintainer(service: service, intervalSeconds: 0.1)
        let result = maintainer.tick()

        #expect(result.commands == 2)
        #expect(writer.requestedFrames[WindowID(rawValue: 1)] == Rect(x: 0, y: 0, width: 100, height: 500))
        #expect(writer.requestedFrames[WindowID(rawValue: 2)] == Rect(x: 110, y: 0, width: 890, height: 500))
        try? FileManager.default.removeItem(atPath: intentTemp.path)
    }

    @Test
    func clampedCommandIntentIsStabilizedInsideDisplayBounds() {
        let intentTemp = makeIntentStore()
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let intentScope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let writer = ClampingWriter(firstActual: Rect(x: 900, y: 0, width: 1000, height: 500))
        let intentStore = intentTemp.store
        intentStore.save(
            LayoutIntent(
                scope: intentScope,
                windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)],
                placements: [
                    WindowID(rawValue: 1): Rect(x: 900, y: 0, width: 100, height: 500),
                    WindowID(rawValue: 2): Rect(x: 0, y: 0, width: 890, height: 500),
                ],
                createdAt: Date().addingTimeInterval(-30),
                source: .command
            )
        )

        let service = SnapshotService(
            provider: SequenceProvider(
                display: display,
                windowFrames: [
                    [Rect(x: 0, y: 0, width: 495, height: 500), Rect(x: 505, y: 0, width: 495, height: 500)],
                ]
            ),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .bsp, gapsOuter: 0, gapsInner: 10)),
            intentStore: intentStore
        )

        let maintainer = LayoutMaintainer(service: service, intervalSeconds: 0.1)
        let result = maintainer.tick()

        #expect(result.clamped == 1)
        #expect(writer.requestedFrames.first == Rect(x: 900, y: 0, width: 100, height: 500))
        #expect(writer.requestedFrames.last == Rect(x: 0, y: 0, width: 1000, height: 500))
        try? FileManager.default.removeItem(atPath: intentTemp.path)
    }

    @Test
    func focusJitterDoesNotTriggerRelayout() {
        let intentTemp = makeIntentStore()
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let intentScope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let intentStore = intentTemp.store
        let before = Rect(x: 0, y: 0, width: 495, height: 500)
        let right = Rect(x: 505, y: 0, width: 495, height: 500)
        intentStore.save(
            LayoutIntent(
                scope: intentScope,
                windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)],
                placements: [
                    WindowID(rawValue: 1): before,
                    WindowID(rawValue: 2): right,
                ]
            )
        )

        let focused = WindowID(rawValue: 2)
        let provider = SequenceProvider(
            display: display,
            windowFrames: [
                [before, right],
                [before, Rect(x: 505, y: 10, width: 495, height: 490)],
            ]
        )
        _ = SnapshotService(
            provider: provider,
            frameWriter: RecordingWriter(),
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            intentStore: intentStore
        )
        let focusedService = SnapshotService(
            provider: FocusedSystemSnapshotProvider(
                base: provider,
                focusedWindowID: focused
            ),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            intentStore: intentStore
        )
        let maintainer = LayoutMaintainer(service: focusedService)

        _ = maintainer.tick()
        let second = maintainer.tick()

        #expect(second.commands == 0)
        #expect(intentStore.intent(for: intentScope) != nil)
        try? FileManager.default.removeItem(atPath: intentTemp.path)
    }

    @Test
    func staleCommandIntentStillSuppressesReflowWhenLayoutMatchesWithoutRefreshingExpiry() {
        let intentTemp = makeIntentStore()
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let intentScope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let writer = RecordingWriter()
        let intentStore = intentTemp.store
        let initialCreatedAt = Date().addingTimeInterval(-30)
        intentStore.save(
            LayoutIntent(
                scope: intentScope,
                windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)],
                placements: [
                    WindowID(rawValue: 1): Rect(x: 0, y: 0, width: 700, height: 500),
                    WindowID(rawValue: 2): Rect(x: 710, y: 0, width: 290, height: 500),
                ],
                createdAt: initialCreatedAt,
                source: .command
            )
        )

        let service = SnapshotService(
            provider: SequenceProvider(
                display: display,
                windowFrames: [
                    [Rect(x: 0, y: 0, width: 700, height: 500), Rect(x: 710, y: 0, width: 290, height: 500)],
                ]
            ),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            intentStore: intentStore
        )

        let maintainer = LayoutMaintainer(service: service, intervalSeconds: 0.1)
        let result = maintainer.tick()

        #expect(result.commands == 0)
        #expect(writer.requestedFrames.isEmpty)
        #expect(intentStore.intent(for: intentScope)?.createdAt == initialCreatedAt)
        try? FileManager.default.removeItem(atPath: intentTemp.path)
    }
}

/// Fenêtres vivantes : le fournisseur renvoie les cadres posés par le moteur, l'écrivain impose
/// des tailles minimales comme une application réelle (SPEC-016 lot C).
private final class MinimumSizeWindows: SystemSnapshotProviding, WindowFrameWriting, @unchecked Sendable {
    private let display: DisplaySnapshot
    private let minimumSizes: [WindowID: CGSize]
    private var frames: [WindowID: Rect]
    private(set) var requestedFrames: [WindowID: Rect] = [:]

    init(display: DisplaySnapshot, frames: [WindowID: Rect], minimumSizes: [WindowID: CGSize]) {
        self.display = display
        self.frames = frames
        self.minimumSizes = minimumSizes
    }

    func permissions(prompt: Bool) -> PermissionSnapshot {
        PermissionSnapshot(accessibilityTrusted: true)
    }

    func displays() -> [DisplaySnapshot] {
        [display]
    }

    func windows() -> [WindowSnapshot] {
        frames.keys.sorted().map { id in
            WindowSnapshot(
                id: id,
                pid: Int32(id.rawValue + 10),
                appName: "App\(id.rawValue)",
                bundleID: "app.\(id.rawValue)",
                title: "Window\(id.rawValue)",
                frame: frames[id] ?? Rect(x: 0, y: 0, width: 0, height: 0),
                isOnScreen: true,
                isTileCandidate: true
            )
        }
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        requestedFrames[window.id] = Rect(frame)
        let minimum = minimumSizes[window.id] ?? .zero
        let actual = CGRect(
            x: frame.minX,
            y: frame.minY,
            width: max(frame.width, minimum.width),
            height: max(frame.height, minimum.height)
        )
        frames[window.id] = Rect(actual)
        return actual
    }
}

/// Câblage du budget A13 (T222). En production : un registre partagé par le service, le
/// maintainer et l'écrivain, la génération partagée du processus, et un écrivain qui, comme
/// `AXWindowFrameWriter`, inscrit chaque tentative avec sa génération et refuse une fenêtre au
/// budget épuisé. Sinon : le double d'origine et les registre et génération privés des tests.
private struct BudgetWiring {
    let writer: any WindowFrameWriting
    let registry: WrittenFrameRegistry?
    let generations: PlacementGeneration?

    init(_ inner: any WindowFrameWriting, production: Bool) {
        guard production else {
            (writer, registry, generations) = (inner, nil, nil)
            return
        }
        let registry = WrittenFrameRegistry()
        (writer, self.registry, generations) = (BudgetedWriter(inner, registry: registry), registry, .shared)
    }
}

private final class BudgetedWriter: WindowFrameWriting, @unchecked Sendable {
    private let inner: any WindowFrameWriting
    private let registry: WrittenFrameRegistry

    init(_ inner: any WindowFrameWriting, registry: WrittenFrameRegistry) {
        self.inner = inner
        self.registry = registry
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        setFrame(frame, of: window, generation: PlacementGeneration.shared.current)
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot, generation: UInt64) -> CGRect? {
        setFrames([WindowFrameUpdate(window: window, frame: frame)], generation: generation)[window.id] ?? nil
    }

    func setFrames(_ updates: [WindowFrameUpdate]) -> [WindowID: CGRect?] {
        setFrames(updates, generation: PlacementGeneration.shared.current)
    }

    func setFrames(_ updates: [WindowFrameUpdate], generation: UInt64) -> [WindowID: CGRect?] {
        var results: [WindowID: CGRect?] = [:]
        for update in updates {
            let id = update.window.id.rawValue
            var actual: CGRect?
            if !registry.isOverBudget(windowID: id, generation: generation) {
                actual = inner.setFrame(update.frame, of: update.window)
                registry.record(windowID: id, requested: update.frame, readBack: actual, generation: generation, at: Date())
            }
            results.updateValue(actual, forKey: update.window.id)
        }
        return results
    }
}

private func lotCDisplay(id: String = "display-a", x: Double = 0) -> DisplaySnapshot {
    DisplaySnapshot(
        id: DisplayID(rawValue: id),
        index: 1,
        name: id,
        frame: Rect(x: x, y: 0, width: 1000, height: 500),
        visibleFrame: Rect(x: x, y: 0, width: 1000, height: 500),
        isMain: x == 0
    )
}

private func lotCWindow(_ id: UInt32, _ frame: Rect, nativeFullscreen: Bool = false) -> WindowSnapshot {
    WindowSnapshot(
        id: WindowID(rawValue: id),
        pid: Int32(id + 10),
        appName: "App\(id)",
        bundleID: "app.\(id)",
        title: "Window\(id)",
        frame: frame,
        isOnScreen: true,
        isTileCandidate: true,
        furniture: nativeFullscreen ? WindowFurniture(isNativeFullscreen: true) : nil
    )
}

private func frameIsVisible(_ frame: Rect?, on display: DisplaySnapshot) -> Bool {
    guard let frame else { return false }
    let visible = display.visibleFrame
    return frame.x >= visible.x - 1
        && frame.y >= visible.y - 1
        && frame.x + frame.width <= visible.x + visible.width + 1
        && frame.y + frame.height <= visible.y + visible.height + 1
}

extension LayoutMaintainerTests {
    /// FR-001 : une fenêtre seule tilée (marges 8) remplit presque l'écran sans être en plein écran.
    /// Une nouvelle fenêtre de la stage est tilée, pas cachée.
    @Test
    func singleTiledWindowStageTilesNewWindowInsteadOfHidingIt() {
        let display = lotCDisplay()
        let single = lotCWindow(1, Rect(x: 8, y: 8, width: 984, height: 484))
        let newcomer = lotCWindow(2, Rect(x: 100, y: 100, width: 300, height: 200))
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let intentTemp = makeIntentStore()
        let eventPath = tempPath("lot-c-single-window-new-window-events")
        defer {
            try? FileManager.default.removeItem(atPath: intentTemp.path)
            try? FileManager.default.removeItem(atPath: eventPath)
        }
        intentTemp.store.save(LayoutIntent(
            scope: scope,
            windowIDs: [single.id],
            placements: [single.id: single.frame],
            createdAt: Date().addingTimeInterval(-60),
            source: .command
        ))
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: MultiDisplaySequenceProvider(
                displaySnapshots: [display],
                windowSnapshots: [[single], [single, newcomer]]
            ),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 8, gapsInner: 8)),
            intentStore: intentTemp.store
        )
        let maintainer = LayoutMaintainer(service: service, events: EventLog(path: eventPath))

        _ = maintainer.tick()
        let tick = maintainer.tick()
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""

        #expect(tick.commands >= 1)
        #expect(frameIsVisible(writer.requestedFrames[newcomer.id], on: display))
        #expect(!events.contains("\"type\":\"fullscreen_stage_siblings_hidden\""))
    }

    /// FR-016 : le plein écran natif sur l'écran 1 n'empêche pas la disposition de l'écran 2.
    @Test
    func nativeFullscreenOnOneDisplayDoesNotStopOtherDisplay() {
        let displayA = lotCDisplay(id: "display-a", x: 0)
        let displayB = lotCDisplay(id: "display-b", x: 1000)
        let fullscreen = lotCWindow(1, displayA.frame, nativeFullscreen: true)
        let left = lotCWindow(2, Rect(x: 1100, y: 50, width: 300, height: 200))
        let right = lotCWindow(3, Rect(x: 1500, y: 50, width: 300, height: 200))
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: MultiDisplaySequenceProvider(
                displaySnapshots: [displayA, displayB],
                windowSnapshots: [[fullscreen, left, right]]
            ),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10))
        )
        let maintainer = LayoutMaintainer(service: service)

        let tick = maintainer.tick()

        #expect(tick.commands >= 2)
        #expect(writer.requestedFrames[fullscreen.id] == nil)
        #expect(frameIsVisible(writer.requestedFrames[left.id], on: displayB))
        #expect(frameIsVisible(writer.requestedFrames[right.id], on: displayB))
    }

    /// Scénario FR-002 : fenêtre 1 zoomée par commande (intent `zoomedWindowID`), fenêtre 2
    /// cachée dans le coin et focalisée par le système (Cmd-Tab).
    private struct ZoomSiblingScenario {
        let display = lotCDisplay()
        let zoomed: WindowSnapshot
        let hiddenSibling: WindowSnapshot
        let scope: StageScope
        let writer = RecordingWriter()
        let intentStore: LayoutIntentStore
        let eventPath: String
        let maintainer: LayoutMaintainer
        let cleanupPaths: [String]

        /// `laterFrames` : cadres (fenêtre 1, fenêtre 2) des snapshots suivant le premier.
        init(name: String, laterFrames: [(Rect, Rect)]) {
            zoomed = lotCWindow(1, display.visibleFrame)
            hiddenSibling = lotCWindow(2, Rect(x: 999, y: 0, width: 495, height: 500))
            scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: scope1)
            let stagePath = tempPath(name)
            eventPath = tempPath("\(name)-events")
            let intentTemp = makeIntentStore()
            intentStore = intentTemp.store
            cleanupPaths = [stagePath, eventPath, intentTemp.path]
            let stageStore = StageStore(path: stagePath)
            stageStore.save(PersistentStageState(scopes: [
                PersistentStageScope(displayID: display.id, activeStageID: scope1, stages: [
                    PersistentStage(id: scope1, mode: .bsp, focusedWindowID: hiddenSibling.id, members: [
                        PersistentStageMember(windowID: zoomed.id, bundleID: zoomed.bundleID, title: zoomed.title, frame: zoomed.frame),
                        PersistentStageMember(windowID: hiddenSibling.id, bundleID: hiddenSibling.bundleID, title: hiddenSibling.title, frame: hiddenSibling.frame),
                    ]),
                ]),
            ], activeDisplayID: display.id))
            intentStore.save(LayoutIntent(
                scope: scope,
                windowIDs: [zoomed.id, hiddenSibling.id],
                placements: [zoomed.id: zoomed.frame, hiddenSibling.id: hiddenSibling.frame],
                source: .command,
                zoomedWindowID: zoomed.id
            ))
            let snapshots = [[zoomed, hiddenSibling]] + laterFrames.map { frames in
                [lotCWindow(1, frames.0), lotCWindow(2, frames.1)]
            }
            let service = SnapshotService(
                provider: MultiDisplaySequenceProvider(
                    displaySnapshots: [display],
                    windowSnapshots: snapshots,
                    focusedID: hiddenSibling.id
                ),
                frameWriter: writer,
                config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
                intentStore: intentStore,
                stageStore: stageStore
            )
            maintainer = LayoutMaintainer(service: service, events: EventLog(path: eventPath), store: stageStore)
        }

        var events: String {
            (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        }

        func cleanup() {
            for path in cleanupPaths {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }

    /// FR-002 : après un zoom de commande, Cmd-Tab vers une voisine cachée la rend visible et
    /// sort explicitement du zoom (marqueur retiré) ; le scope est redisposé et la voisine n'est
    /// plus recachée. Avant SPEC-016 T208, le marqueur était conservé et le scope restait exclu.
    @Test
    func focusOnHiddenSiblingAfterZoomMakesItVisible() {
        let scenario = ZoomSiblingScenario(
            name: "lot-c-zoom-focus-sibling",
            laterFrames: [(Rect(x: 0, y: 0, width: 1000, height: 500), Rect(x: 252, y: 0, width: 496, height: 500))]
        )
        defer { scenario.cleanup() }

        let restore = scenario.maintainer.tick()
        let restoredFrame = scenario.writer.requestedFrames[scenario.hiddenSibling.id]
        _ = scenario.maintainer.tick()
        let events = scenario.events

        #expect(restore.commands >= 1)
        #expect(frameIsVisible(restoredFrame, on: scenario.display))
        #expect(events.contains("\"type\":\"stage_focus_restore\""))
        #expect(events.contains("\"type\":\"layout_zoom_exited\""))
        #expect(scenario.intentStore.intent(for: scenario.scope)?.zoomedWindowID == nil)
        // La fenêtre zoomée reprend une tuile : elle ne couvre plus tout l'écran.
        #expect((scenario.writer.requestedFrames[scenario.zoomed.id]?.width ?? .infinity) < scenario.display.visibleFrame.width)
        #expect(frameIsVisible(scenario.writer.requestedFrames[scenario.hiddenSibling.id], on: scenario.display))
        #expect(!events.contains("\"type\":\"fullscreen_stage_siblings_hidden\""))
    }

    /// FR-002 : après la sortie du zoom, un changement de géométrie dans le scope n'est plus
    /// ignoré comme « plein écran » : une disposition est appliquée au tick suivant.
    @Test
    func geometryChangeAfterZoomExitIsLaidOut() {
        let left = Rect(x: 0, y: 0, width: 495, height: 500)
        let right = Rect(x: 505, y: 0, width: 495, height: 500)
        let scenario = ZoomSiblingScenario(
            name: "lot-c-zoom-exit-geometry",
            laterFrames: [
                (left, right),
                // La fenêtre 2 est déplacée hors de sa tuile.
                (left, Rect(x: 200, y: 50, width: 400, height: 300)),
            ]
        )
        defer { scenario.cleanup() }

        _ = scenario.maintainer.tick()
        #expect(scenario.writer.requestedFrames[scenario.zoomed.id] == left)
        _ = scenario.maintainer.tick()
        let relayout = scenario.maintainer.tick()

        #expect(relayout.commands >= 1)
        #expect(scenario.writer.requestedFrames[scenario.zoomed.id] == left)
        #expect(scenario.writer.requestedFrames[scenario.hiddenSibling.id] == right)
        #expect(!scenario.events.contains("\"type\":\"fullscreen_scope_change_suppressed\""))
    }

    /// FR-017, A18 : la rafale de changements de membres de l'écran 1 n'exclut que son scope ;
    /// l'écran 2 est toujours redisposé dans la même passe. Le premier changement de l'écran 1,
    /// isolé, est rangé tout de suite (A18).
    @Test
    func membershipSettlingOnOneDisplayDoesNotStopOtherDisplay() {
        let displayA = lotCDisplay()
        let displayB = lotCDisplay(id: "display-b", x: 1000)
        let bRight = Rect(x: 1505, y: 0, width: 495, height: 500)
        let eventPath = tempPath("two-display-membership-settling-events")
        defer { try? FileManager.default.removeItem(atPath: eventPath) }
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: MultiDisplaySequenceProvider(displaySnapshots: [displayA, displayB], windowSnapshots: [
                [
                    lotCWindow(1, Rect(x: 0, y: 0, width: 495, height: 500)),
                    lotCWindow(2, Rect(x: 505, y: 0, width: 495, height: 500)),
                    lotCWindow(3, Rect(x: 1000, y: 0, width: 495, height: 500)),
                    lotCWindow(4, bRight),
                ],
                // Écran 1 : la fenêtre 2 disparaît (premier changement, isolé).
                [
                    lotCWindow(1, Rect(x: 0, y: 0, width: 495, height: 500)),
                    lotCWindow(3, Rect(x: 1000, y: 0, width: 495, height: 500)),
                    lotCWindow(4, bRight),
                ],
                // 80 ms plus tard, écran 1 : la fenêtre 2 revient (rafale). Écran 2 : la 4 est déplacée.
                [
                    lotCWindow(1, Rect(x: 0, y: 0, width: 1000, height: 500)),
                    lotCWindow(2, Rect(x: 505, y: 0, width: 495, height: 500)),
                    lotCWindow(3, Rect(x: 1000, y: 0, width: 495, height: 500)),
                    lotCWindow(4, Rect(x: 1200, y: 50, width: 400, height: 300)),
                ],
            ]),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .bsp, gapsOuter: 0, gapsInner: 10))
        )
        var currentTime = Date()
        let maintainer = LayoutMaintainer(
            service: service,
            events: EventLog(path: eventPath),
            intervalSeconds: 0.1,
            now: { currentTime }
        )

        _ = maintainer.tick()
        currentTime = currentTime.addingTimeInterval(0.1)
        let first = maintainer.tick()
        let placedFirst = writer.requestedFrames[WindowID(rawValue: 1)]
        currentTime = currentTime.addingTimeInterval(0.08)
        let tick = maintainer.tick()
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""

        #expect(first.commands >= 1)
        #expect(placedFirst == Rect(x: 0, y: 0, width: 1000, height: 500))
        #expect(events.contains("\"type\":\"layout_stage_membership_settling\""))
        #expect(writer.requestedFrames[WindowID(rawValue: 2)] == nil)
        #expect(tick.commands >= 1)
        #expect(writer.requestedFrames[WindowID(rawValue: 4)] == bRight)
    }

    /// FR-017 : activer une autre stage n'est pas un changement de membres : la nouvelle stage est
    /// disposée tout de suite, sans période de stabilisation.
    @Test
    func stageSwitchIsNotTreatedAsMembershipChange() {
        let displayA = lotCDisplay()
        let displayB = lotCDisplay(id: "display-b", x: -1000)
        let stage2 = StageID(rawValue: "2")
        let stagePath = tempPath("two-display-stage-switch-no-settling")
        let eventPath = tempPath("two-display-stage-switch-no-settling-events")
        defer {
            try? FileManager.default.removeItem(atPath: stagePath)
            try? FileManager.default.removeItem(atPath: eventPath)
        }
        // Coin bas-droit de l'écran 1, comme les autres tests de fenêtres cachées.
        let hidden = { (id: UInt32) in lotCWindow(id, Rect(x: 999, y: 499, width: 495, height: 500)) }
        let member = { (window: WindowSnapshot) in
            PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame)
        }
        let a1 = lotCWindow(1, Rect(x: 0, y: 0, width: 495, height: 500))
        let a2 = lotCWindow(2, Rect(x: 505, y: 0, width: 495, height: 500))
        let b5 = lotCWindow(5, displayB.visibleFrame)
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: displayA.id, activeStageID: scope1, stages: [
                PersistentStage(id: scope1, mode: .bsp, members: [member(a1), member(a2)]),
                PersistentStage(id: stage2, mode: .bsp, members: [member(hidden(3)), member(hidden(4))]),
            ]),
            PersistentStageScope(displayID: displayB.id, activeStageID: scope1, stages: [
                PersistentStage(id: scope1, mode: .bsp, members: [member(b5)]),
            ]),
        ], activeDisplayID: displayA.id))
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: MultiDisplaySequenceProvider(displaySnapshots: [displayA, displayB], windowSnapshots: [
                [a1, a2, hidden(3), hidden(4), b5],
                // Après la bascule : la stage 1 est cachée, les fenêtres de la stage 2 réapparaissent
                // à leurs propres cadres.
                [hidden(1), hidden(2), lotCWindow(3, Rect(x: 100, y: 50, width: 300, height: 200)),
                 lotCWindow(4, Rect(x: 500, y: 50, width: 300, height: 200)), b5],
            ]),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .bsp, gapsOuter: 0, gapsInner: 10)),
            stageStore: stageStore
        )
        var currentTime = Date()
        let maintainer = LayoutMaintainer(
            service: service,
            events: EventLog(path: eventPath),
            intervalSeconds: 0.1,
            store: stageStore,
            now: { currentTime }
        )

        _ = maintainer.tick()
        stageStore.mutate { state in
            var scope = state.scope(displayID: displayA.id)
            scope.activeStageID = stage2
            state.update(scope)
        }
        currentTime = currentTime.addingTimeInterval(0.1)
        _ = maintainer.tick()
        // Au-delà de l'anti-rebond des gestes (0,35 s) mais bien avant la fin d'une stabilisation
        // de membres (2 s) : la nouvelle stage doit déjà être disposée.
        currentTime = currentTime.addingTimeInterval(0.5)
        let switched = maintainer.tick()
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""

        #expect(!events.contains("\"type\":\"layout_stage_membership_settling\""))
        #expect(switched.commands >= 2)
        #expect(writer.requestedFrames[WindowID(rawValue: 3)] == Rect(x: 0, y: 0, width: 495, height: 500))
        #expect(writer.requestedFrames[WindowID(rawValue: 4)] == Rect(x: 505, y: 0, width: 495, height: 500))
    }

    /// FR-040 : une commande limitée à l'écran 1 exclut seulement son scope ; le plan de l'écran 2
    /// est appliqué. L'activité globale (sans scope) garde le comportement historique.
    @Test
    func scopedCommandActivityOnOneDisplayDoesNotStopOtherDisplay() {
        let displayA = lotCDisplay()
        let displayB = lotCDisplay(id: "display-b", x: 1000)
        let commandScope = StageScope(displayID: displayA.id, desktopID: DesktopID(rawValue: 1), stageID: scope1)
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: MultiDisplaySequenceProvider(displaySnapshots: [displayA, displayB], windowSnapshots: [[
                lotCWindow(1, Rect(x: 100, y: 50, width: 300, height: 200)),
                lotCWindow(2, Rect(x: 500, y: 50, width: 300, height: 200)),
                lotCWindow(3, Rect(x: 1100, y: 50, width: 300, height: 200)),
                lotCWindow(4, Rect(x: 1500, y: 50, width: 300, height: 200)),
            ]]),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10))
        )
        let now = Date()
        let commandActivity = LayoutCommandActivity(path: tempPath("scoped-command-activity"), enabled: true)
        commandActivity.reset()
        defer { commandActivity.reset() }
        commandActivity.markActive(reason: "test", scopes: [commandScope], now: now, holdSeconds: 5)
        let activity = commandActivity.activity(now: now)
        let maintainer = LayoutMaintainer(service: service, commandActivity: commandActivity, now: { now.addingTimeInterval(0.1) })

        let tick = maintainer.tick()

        #expect(activity?.isGlobal == false)
        #expect(activity?.scopes == [commandScope])
        #expect(tick.commands >= 2)
        #expect(writer.requestedFrames[WindowID(rawValue: 1)] == nil)
        #expect(writer.requestedFrames[WindowID(rawValue: 2)] == nil)
        #expect(frameIsVisible(writer.requestedFrames[WindowID(rawValue: 3)], on: displayB))
        #expect(frameIsVisible(writer.requestedFrames[WindowID(rawValue: 4)], on: displayB))
    }

    /// FR-003 : une grille de trois fenêtres dont deux refusent de rétrécir est replanifiée aux
    /// tailles minimales connues, sans masquage, et reste stable au tick suivant.
    /// T222 : avec le câblage de production, le budget A13 ne coupe pas la chaîne sans arbre.
    @Test(arguments: [false, true])
    func gridWithTwoClampedWindowsIsRearrangedInsteadOfHidden(productionWiring: Bool) {
        let display = lotCDisplay()
        let windows = MinimumSizeWindows(
            display: display,
            frames: [
                WindowID(rawValue: 1): Rect(x: 0, y: 0, width: 200, height: 200),
                WindowID(rawValue: 2): Rect(x: 300, y: 0, width: 200, height: 200),
                WindowID(rawValue: 3): Rect(x: 600, y: 0, width: 200, height: 200),
            ],
            minimumSizes: [
                WindowID(rawValue: 2): CGSize(width: 200, height: 300),
                WindowID(rawValue: 3): CGSize(width: 200, height: 300),
            ]
        )
        let eventPath = tempPath("lot-c-grid-two-clamped-events")
        let intentTemp = makeIntentStore()
        defer {
            try? FileManager.default.removeItem(atPath: eventPath)
            try? FileManager.default.removeItem(atPath: intentTemp.path)
        }
        let wiring = BudgetWiring(windows, production: productionWiring)
        let service = SnapshotService(
            provider: windows,
            frameWriter: wiring.writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .masterStack, gapsOuter: 0, gapsInner: 10)),
            intentStore: intentTemp.store,
            frameRegistry: wiring.registry ?? .shared
        )
        let maintainer = LayoutMaintainer(
            service: service, events: EventLog(path: eventPath),
            writtenFrames: wiring.registry, generations: wiring.generations
        )

        let first = maintainer.tick()
        let second = maintainer.tick()
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        let finalFrames = windows.windows().map(\.frame)

        #expect(first.clamped >= 2)
        #expect(events.contains("\"type\":\"layout_clamped_scope_rearranged\""))
        #expect(!events.contains("\"type\":\"layout_infeasible_scope_isolated\""))
        #expect(finalFrames.allSatisfy { frameIsVisible($0, on: display) })
        #expect(second.commands == 0)
    }

    /// FR-004 : un échec mémorisé expire après 30 s ; la commande est retentée.
    @Test
    func failedFrameIsRetriedAfterRefusalMemoryExpires() {
        let display = lotCDisplay()
        let initial = Rect(x: 80, y: 80, width: 320, height: 240)
        let writer = FailingWriter()
        let service = SnapshotService(
            provider: SequenceProvider(display: display, windowFrames: [[initial]]),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 0))
        )
        var currentTime = Date(timeIntervalSince1970: 0)
        let maintainer = LayoutMaintainer(service: service, now: { currentTime })

        let first = maintainer.tick()
        currentTime = currentTime.addingTimeInterval(31)
        let retried = maintainer.tick()

        #expect(first.failed == 1)
        #expect(retried.commands == 1)
        #expect(writer.attempts == 2)
    }

    /// FR-004 : un refus de TAILLE (cadre obtenu différent du cadre demandé) est mémorisé, puis
    /// oublié après 30 s : le cadre est redemandé (audit TEST-002 ; l'échec complet est couvert
    /// par `failedFrameIsRetriedAfterRefusalMemoryExpires`).
    @Test
    func clampedSizeRefusalIsRetriedAfterRefusalMemoryExpires() {
        let display = lotCDisplay()
        let initial = Rect(x: 80, y: 80, width: 320, height: 240)
        let writer = AlwaysClampedWriter(actual: initial)
        let service = SnapshotService(
            provider: SequenceProvider(display: display, windowFrames: [[initial]]),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 0))
        )
        var currentTime = Date(timeIntervalSince1970: 0)
        let maintainer = LayoutMaintainer(service: service, now: { currentTime })

        let first = maintainer.tick()
        let requestsAfterFirst = writer.attempts
        currentTime = currentTime.addingTimeInterval(1)
        _ = maintainer.tick()
        let requestsWhileRemembered = writer.attempts
        currentTime = currentTime.addingTimeInterval(31)
        let retried = maintainer.tick()

        // Le premier tick applique puis répare dans le même tick (2 demandes) ; le refus
        // mémorisé bloque toute nouvelle demande, puis l'expiration relance la disposition.
        #expect(first.clamped == 1)
        #expect(requestsAfterFirst > 0)
        #expect(requestsWhileRemembered == requestsAfterFirst)
        #expect(retried.commands == 1)
        #expect(writer.attempts > requestsWhileRemembered)
    }

    /// FR-010 : aucun plan n'est appliqué tant qu'un bouton de souris est enfoncé.
    @Test
    func pressedMouseButtonSuspendsLayoutApply() {
        let display = lotCDisplay()
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: SequenceProvider(display: display, windowFrames: [[
                Rect(x: 80, y: 80, width: 320, height: 240),
                Rect(x: 500, y: 80, width: 320, height: 240),
            ]]),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10))
        )
        var pressed = true
        let maintainer = LayoutMaintainer(service: service, mouseButtonsPressed: { pressed })

        let held = maintainer.tick()
        let heldFrames = writer.requestedFrames
        pressed = false
        let released = maintainer.tick()

        #expect(held.commands == 0)
        #expect(heldFrames.isEmpty)
        #expect(released.commands >= 1)
    }
}

private let scope1 = StageID(rawValue: "1")

// MARK: - SPEC-017 : modes à arbre, rafales, garde de bureau, budget d'écriture

/// Monde simulé : le relevé et l'écriture partagent les mêmes frames. Une écriture respecte la
/// taille minimale de l'application et peut être décalée (`writeOffsetX`), comme une vraie app.
private final class TreeWorld: SystemSnapshotProviding, WindowFrameWriting, @unchecked Sendable {
    let screens: [DisplaySnapshot]
    var frames: [WindowID: Rect]
    var minimumSizes: [WindowID: CGSize] = [:]
    var writeOffsetX: [WindowID: Double] = [:]
    var nativeFullscreen: Set<WindowID> = []
    /// Frames imposées par l'application aux prochaines écritures, dans l'ordre.
    var forcedResults: [WindowID: [Rect]] = [:]
    var focused: WindowID?
    /// Appelé à chaque écriture (horloge qui avance pendant l'écriture, T209).
    var onWrite: () -> Void = {}
    /// Fenêtres dont la lecture AX fraîche échoue (T218).
    var unreadable: Set<WindowID> = []
    var unwritable: Set<WindowID> = []
    /// Registre tenu par l'écrivain, comme `AXWindowFrameWriter` (commandes comprises, T219).
    var registry: WrittenFrameRegistry?
    var now: () -> Date = Date.init
    var accessibilityTrusted = true
    private(set) var writes: [WindowID: [Rect]] = [:]
    /// Énumérations complètes des fenêtres (relevés AX, T210).
    private(set) var enumerations = 0

    init(displays: [DisplaySnapshot] = [lotCDisplay()], frames: [WindowID: Rect]) {
        self.screens = displays
        self.frames = frames
    }

    var totalWrites: Int { writes.values.reduce(0) { $0 + $1.count } }

    func permissions(prompt: Bool) -> PermissionSnapshot { PermissionSnapshot(accessibilityTrusted: accessibilityTrusted) }
    func displays() -> [DisplaySnapshot] { screens }
    func focusedWindowID() -> WindowID? { focused }

    func windows() -> [WindowSnapshot] {
        enumerations += 1
        return frames.keys.sorted().map { id in
            var window = lotCWindow(id.rawValue, frames[id] ?? Rect(x: 0, y: 0, width: 0, height: 0))
            if nativeFullscreen.contains(id) {
                // Fenêtre de document complète : sans boutons, la politique de tiling l'écarterait.
                window.furniture = WindowFurniture(
                    hasCloseButton: true, hasFullscreenButton: true, fullscreenButtonEnabled: true,
                    hasMinimizeButton: true, hasZoomButton: true, isNativeFullscreen: true
                )
            }
            return window
        }
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        writes[window.id, default: []].append(Rect(frame))
        onWrite()
        guard !unwritable.contains(window.id) else { return nil }
        if var forced = forcedResults[window.id], !forced.isEmpty {
            let actual = forced.removeFirst()
            forcedResults[window.id] = forced
            frames[window.id] = actual
            return actual.cgRect
        }
        let minimum = minimumSizes[window.id] ?? .zero
        let actual = Rect(
            x: frame.minX + (writeOffsetX[window.id] ?? 0),
            y: frame.minY,
            width: max(frame.width, minimum.width),
            height: max(frame.height, minimum.height)
        )
        frames[window.id] = actual
        return actual.cgRect
    }

    func setFrames(_ updates: [WindowFrameUpdate], generation: UInt64) -> [WindowID: CGRect?] {
        var results: [WindowID: CGRect?] = [:]
        for update in updates {
            let actual = setFrame(update.frame, of: update.window)
            results[update.window.id] = actual
            registry?.record(windowID: update.window.id.rawValue, requested: update.frame, readBack: actual, generation: generation, at: now())
        }
        return results
    }
}

/// Stage 1 d'un écran en mode arbre (`spatialBsp`, ou `mode`), avec son arbre et ses membres.
private func treeStore(
    _ name: String,
    display: DisplaySnapshot = lotCDisplay(),
    tree: BSPTree,
    frames: [WindowID: Rect],
    inactive: [WindowID: Rect] = [:],
    activeStage: StageID = StageID(rawValue: "1"),
    mode: WindowManagementMode = .spatialBsp
) -> StageStore {
    let member = { (id: WindowID, frame: Rect) in
        PersistentStageMember(windowID: id, bundleID: "app.\(id.rawValue)", title: "Window\(id.rawValue)", frame: frame)
    }
    let store = StageStore(path: tempPath(name))
    var stages = [PersistentStage(
        id: StageID(rawValue: "1"),
        mode: mode,
        members: frames.keys.sorted().map { member($0, frames[$0]!) },
        bspTree: tree
    )]
    if !inactive.isEmpty {
        stages.append(PersistentStage(id: StageID(rawValue: "2"), mode: .spatialBsp, members: inactive.keys.sorted().map { member($0, inactive[$0]!) }))
    }
    store.save(PersistentStageState(
        scopes: [PersistentStageScope(displayID: display.id, activeStageID: activeStage, stages: stages)],
        activeDisplayID: display.id
    ))
    return store
}

/// Maintainer et service isolés (état, intents, registre, journal) sur un monde simulé.
private struct TreeHarness {
    let world: TreeWorld
    let store: StageStore
    let registry = WrittenFrameRegistry()
    let eventPath: String
    let maintainer: LayoutMaintainer
    let service: SnapshotService
    let generations = PlacementGeneration()
    let clock: TestClock
    let episodes: EpisodeContext

    init(
        _ name: String,
        world: TreeWorld,
        store: StageStore,
        strategy: WindowManagementMode = .spatialBsp,
        gapsInner: Double = 0,
        clock: TestClock = TestClock(),
        spaceProbe: ((String) -> Bool?)? = nil,
        takeGesture: (() -> GestureSession?)? = nil,
        dragActivity: WindowDragActivity = .shared,
        commandActivity: LayoutCommandActivity = .shared,
        ruleEngine: WindowRuleEngine? = nil
    ) {
        self.world = world
        self.store = store
        self.clock = clock
        let episodes = EpisodeContext(now: { clock.now })
        self.episodes = episodes
        eventPath = tempPath("\(name)-events")
        world.registry = registry
        world.now = { clock.now }
        let scan = ReplayableSnapshotProvider(base: world)
        // Les commandes de ce service publient au maintainer de ce harnais, comme dans le daemon (T219).
        let applications = TreeScopeApplicationCenter()
        service = SnapshotService(
            provider: scan,
            frameWriter: world,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: strategy, gapsOuter: 0, gapsInner: gapsInner)),
            intentStore: LayoutIntentStore(path: tempPath("\(name)-intents")),
            stageStore: store,
            clock: { clock.now },
            frameRegistry: registry,
            treeScopeApplications: applications
        )
        maintainer = LayoutMaintainer(
            service: service,
            scanReplay: scan,
            events: EventLog(path: eventPath, episodes: episodes),
            ruleEngine: ruleEngine,
            store: store,
            dragActivity: dragActivity,
            commandActivity: commandActivity,
            writtenFrames: registry,
            generations: generations,
            takeGesture: takeGesture ?? { nil },
            spaceProbe: spaceProbe ?? { _ in true },
            readFrame: { [world] window in world.unreadable.contains(window.id) ? nil : world.frames[window.id]?.cgRect },
            episodes: episodes,
            now: { clock.now }
        )
        let maintainer = UncheckedBox(maintainer)
        applications.setHandler { maintainer.value.noteTreeScopeApplied($0) }
    }

    /// Commande sur l'arbre du scope (A15, T219) : mutation, puis application par `applyTreeScope`.
    @discardableResult
    func command(_ name: String, _ mutation: (BSPTree) -> BSPTree = { $0 }) -> MaintenanceTick {
        store.mutate { state in
            if let tree = state.bspTree(for: treeScope) { state.setBSPTree(mutation(tree), for: treeScope) }
        }
        return service.applyTreeScope(treeScope, cause: "command:\(name)", generation: generations.next())
    }

    var events: String { (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? "" }

    func count(_ type: String) -> Int {
        events.components(separatedBy: "\"type\":\"\(type)\"").count - 1
    }
}

private let treeW1 = WindowID(rawValue: 1)
private let treeW2 = WindowID(rawValue: 2)
private let treeW3 = WindowID(rawValue: 3)
/// Deux fenêtres côte à côte, 50/50, sur l'écran 1000x500 sans marges.
private let treeSideBySide = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(treeW1), second: .leaf(treeW2))
private let treeLeft = Rect(x: 0, y: 0, width: 500, height: 500)
private let treeRight = Rect(x: 500, y: 0, width: 500, height: 500)

/// Horloge de test réglable, partagée par le maintainer et l'épisode.
private final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

private let treeScope = StageScope(displayID: DisplayID(rawValue: "display-a"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
private let treeContainer = CGRect(x: 0, y: 0, width: 1000, height: 500)

/// Référence non `Sendable` passée à un rappel `@Sendable` d'un test mono-thread.
private final class UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// Session de geste rendue une seule fois, comme `UserInputActivity.takeGesture()` (A17).
private final class GestureBox: @unchecked Sendable {
    var session: GestureSession?
    func take() -> GestureSession? {
        defer { session = nil }
        return session
    }
}

@Suite
struct TreeLayoutMaintainerTests {
    /// US1 / A6 : une fenêtre ouverte seule est rangée tout de suite, en une passe ; `layout_apply`
    /// porte la cause et les compteurs, `layout_stable` suit une observation à 100 ms (A20).
    @Test
    func newWindowIsPlacedInOnePassWithoutWaiting() {
        let world = TreeWorld(frames: [treeW1: treeLeft, treeW2: treeRight])
        world.focused = treeW2
        let harness = TreeHarness("tree-new-window", world: world, store: treeStore("tree-new-window", tree: treeSideBySide, frames: world.frames))

        let startup = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(5)
        world.frames[treeW3] = Rect(x: 100, y: 100, width: 300, height: 200)
        let opened = harness.maintainer.tick(cause: "ax:AXWindowCreated")
        let tree = harness.store.state().bspTree(for: treeScope)
        harness.clock.advance(0.15)
        let after = harness.maintainer.tick(cause: "safety")

        #expect(startup.commands == 0)
        #expect(opened.commands >= 1)
        #expect(world.writes[treeW3]?.count == 1)
        #expect(tree?.windowIDs.contains(treeW3) == true)
        for (id, frame) in tree?.place(in: treeContainer, innerGap: 0) ?? [:] {
            #expect(world.frames[id] == Rect(frame))
        }
        #expect(after.commands == 0)
        #expect(harness.count("layout_apply") == 1)
        #expect(harness.events.contains("\"cause\":\"ax:AXWindowCreated\""))
        #expect(harness.events.contains("\"scans\":\"1\""))
        #expect(harness.events.contains("\"layoutVersion\":"))
        #expect(harness.events.contains("\"windowWrites\":"))
        #expect(harness.count("layout_stable") == 1)
        #expect(harness.count("layout_stage_membership_settling") == 0)
    }

    /// US1.3 : une fenêtre fermée rend sa place à sa voisine, en une passe.
    @Test
    func closedWindowGivesItsPlaceToNeighborInOnePass() {
        let world = TreeWorld(frames: [treeW1: treeLeft, treeW2: treeRight])
        let harness = TreeHarness("tree-closed-window", world: world, store: treeStore("tree-closed-window", tree: treeSideBySide, frames: world.frames))

        _ = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(5)
        world.frames[treeW2] = nil
        let closed = harness.maintainer.tick(cause: "ax:AXUIElementDestroyed")
        harness.clock.advance(1)
        let after = harness.maintainer.tick(cause: "safety")

        #expect(closed.commands == 1)
        #expect(world.frames[treeW1] == Rect(treeContainer))
        #expect(world.writes[treeW1]?.count == 1)
        #expect(after.commands == 0)
    }

    /// A18 : deux changements espacés de plus de `burstWindow` sont deux changements isolés,
    /// chacun rangé tout de suite.
    @Test
    func spacedMembershipChangesAreEachPlacedImmediately() {
        let world = TreeWorld(frames: [treeW1: treeLeft, treeW2: treeRight])
        let harness = TreeHarness("tree-spaced-changes", world: world, store: treeStore("tree-spaced-changes", tree: treeSideBySide, frames: world.frames))

        _ = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(5)
        world.frames[treeW2] = nil
        let first = harness.maintainer.tick(cause: "ax:AXUIElementDestroyed")
        harness.clock.advance(0.4)
        world.frames[treeW3] = Rect(x: 100, y: 100, width: 300, height: 200)
        let second = harness.maintainer.tick(cause: "ax:AXWindowCreated")

        #expect(first.commands >= 1)
        #expect(second.commands >= 1)
        #expect(world.writes[treeW3]?.count == 1)
        #expect(harness.count("layout_stage_membership_settling") == 0)
    }

    /// A6 : une rafale qui ne se calme pas est close au plafond `burstCap`, même si les
    /// changements continuent ; la passe finale part alors.
    @Test
    func membershipBurstIsClosedAtBurstCap() {
        let world = TreeWorld(frames: [treeW1: treeLeft, treeW2: treeRight])
        let harness = TreeHarness("tree-burst-cap", world: world, store: treeStore("tree-burst-cap", tree: treeSideBySide, frames: world.frames))
        let extra = Rect(x: 100, y: 100, width: 300, height: 200)

        _ = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(5)
        let start = harness.clock.now
        var held: [Int] = []
        var capped = MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
        for step in 0...13 {
            harness.clock.now = start.addingTimeInterval(0.08 * Double(step))
            world.frames[treeW3] = step.isMultiple(of: 2) ? extra : nil
            let tick = harness.maintainer.tick(cause: "ax:AXWindowCreated")
            if (1...12).contains(step) { held.append(tick.commands) }
            if step == 13 { capped = tick }
        }

        #expect(held.allSatisfy { $0 == 0 })
        #expect(capped.commands >= 1)
        #expect(harness.count("layout_stage_membership_settling") >= 1)
    }

    /// A1, A15 : masquage d'une stage inactive et disposition de la stage active dans la même passe.
    @Test
    func hidingAndLayoutShareOnePass() {
        let world = TreeWorld(frames: [
            treeW1: Rect(x: 50, y: 50, width: 300, height: 200),
            treeW2: Rect(x: 400, y: 50, width: 300, height: 200),
            treeW3: Rect(x: 100, y: 100, width: 300, height: 200),
        ])
        let store = treeStore(
            "tree-unified-plan",
            tree: treeSideBySide,
            frames: [treeW1: world.frames[treeW1]!, treeW2: world.frames[treeW2]!],
            inactive: [treeW3: world.frames[treeW3]!]
        )
        let harness = TreeHarness("tree-unified-plan", world: world, store: store)

        let tick = harness.maintainer.tick(cause: "command:startup")

        #expect(tick.commands == 3)
        #expect(world.frames[treeW1] == treeLeft)
        #expect(world.frames[treeW2] == treeRight)
        #expect(!frameIsVisible(world.frames[treeW3], on: lotCDisplay()))
        #expect(harness.count("layout_apply") == 1)
        #expect(harness.count("stage_hide_inactive") == 1)
    }

    /// A15, T210 : une règle qui change la stage active, le masquage de l'ancienne stage et la
    /// disposition de la nouvelle se font dans la même passe, sur une copie de travail construite
    /// sur le relevé de la passe : une seule énumération des fenêtres.
    @Test
    func ruleChangingActiveStageHidesAndLaysOutInOnePass() {
        let world = TreeWorld(frames: [treeW1: Rect(treeContainer)])
        let store = treeStore("tree-rule-stage", tree: .leaf(treeW1), frames: world.frames)
        store.mutate { state in
            var scope = state.scope(displayID: treeScope.displayID)
            scope.ensureStage(StageID(rawValue: "2"), mode: .spatialBsp)
            state.update(scope)
        }
        let harness = TreeHarness(
            "tree-rule-stage",
            world: world,
            store: store,
            ruleEngine: WindowRuleEngine(rules: [
                WindowRule(id: "app2-stage2", match: RuleMatch(app: "App2"), action: RuleAction(assignStage: "2", follow: true))
            ])
        )

        _ = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(5)
        world.frames[treeW2] = Rect(x: 100, y: 100, width: 300, height: 200)
        let enumerationsBefore = world.enumerations
        let tick = harness.maintainer.tick(cause: "ax:AXWindowCreated")
        var state = store.state()

        #expect(state.scope(displayID: treeScope.displayID).activeStageID == StageID(rawValue: "2"))
        #expect(tick.commands == 2)
        #expect(!frameIsVisible(world.frames[treeW1], on: lotCDisplay()))
        #expect(world.frames[treeW2] == Rect(treeContainer))
        #expect(harness.count("layout_apply") == 1)
        #expect(harness.events.contains("\"scans\":\"1\""))
        #expect(world.enumerations - enumerationsBefore == 1)
    }

    /// US2.2 : une application qui confirme le placement à 5 pt près n'est ni redemandée ni prise
    /// pour un geste ; l'écho est journalisé une fois et la frame acceptée.
    @Test
    func echoWithFewPointsOfDifferenceIsNotRewritten() {
        let world = TreeWorld(frames: [treeW1: Rect(x: 50, y: 50, width: 300, height: 200), treeW2: treeRight])
        world.writeOffsetX[treeW1] = 5
        let harness = TreeHarness("tree-echo", world: world, store: treeStore("tree-echo", tree: treeSideBySide, frames: world.frames))

        _ = harness.maintainer.tick(cause: "command:startup")
        var later = 0
        for (step, cause) in [(0.05, "ax:AXWindowMoved"), (0.05, "deadline"), (0.2, "deadline"), (2, "safety"), (60, "safety")] {
            harness.clock.advance(step)
            later += harness.maintainer.tick(cause: cause).commands
        }

        #expect(world.writes[treeW1]?.count == 1)
        #expect(later == 0)
        #expect(harness.count("layout_manual_gesture") == 0)
        #expect(harness.count("layout_echo_ignored") == 1)
        #expect(harness.events.contains("\"reason\":\"refusal_without_minimum\""))
    }

    /// US2 : l'oscillation 97/25 px du journal réel, rejouée, ne provoque ni propagation ni geste :
    /// une écriture, puis la frame de l'application est acceptée.
    @Test
    func oscillatingApplicationHeightIsNotPropagated() {
        let stacked = BSPTree.split(orientation: .horizontal, ratio: 0.5, first: .leaf(treeW1), second: .leaf(treeW2))
        let targets = stacked.place(in: treeContainer, innerGap: 0)
        let bottom = Rect(targets[treeW2]!)
        let world = TreeWorld(frames: [treeW1: Rect(targets[treeW1]!), treeW2: Rect(x: 0, y: 300, width: 1000, height: 150)])
        let short = { (height: Double) in Rect(x: bottom.x, y: bottom.y, width: bottom.width, height: height) }
        world.forcedResults[treeW2] = [short(97)]
        let store = treeStore("tree-oscillation", tree: stacked, frames: world.frames)
        let harness = TreeHarness("tree-oscillation", world: world, store: store)

        _ = harness.maintainer.tick(cause: "command:startup")
        var commands = 0
        for (delay, height) in [(0.1, 97.0), (0.2, 25.0), (1.2, 97.0), (1.0, 25.0), (1.5, 97.0), (2.0, 25.0)] {
            harness.clock.advance(delay)
            world.frames[treeW2] = short(height)
            commands += harness.maintainer.tick(cause: "ax:AXWindowResized").commands
        }

        #expect(world.writes[treeW2]?.count == 1)
        #expect(commands == 0)
        #expect(store.state().bspTree(for: treeScope) == stacked)
        #expect(harness.count("layout_manual_gesture") == 0)
    }

    /// A4, A13 : un changement externe (application qui se redimensionne seule, outil clavier) est
    /// ramené une fois à l'arbre par génération, puis accepté sans lutte.
    @Test
    func externalChangeIsRevertedOnceThenAccepted() {
        let world = TreeWorld(frames: [treeW1: Rect(x: 50, y: 50, width: 300, height: 200), treeW2: treeRight])
        let store = treeStore("tree-external", tree: treeSideBySide, frames: world.frames)
        let harness = TreeHarness("tree-external", world: world, store: store)

        _ = harness.maintainer.tick(cause: "command:startup")
        var commands: [Int] = []
        for x in [120.0, 140, 160] {
            harness.clock.advance(5)
            world.frames[treeW1] = Rect(x: x, y: 20, width: 400, height: 300)
            commands.append(harness.maintainer.tick(cause: "ax:AXWindowMoved").commands)
        }

        #expect(commands == [1, 0, 0])
        #expect(world.writes[treeW1]?.count == 2)
        #expect(store.state().bspTree(for: treeScope) == treeSideBySide)
        #expect(harness.count("layout_external_change_reverted") == 1)
        #expect(harness.count("layout_app_response_accepted") >= 1)
    }

    /// A2, A13, A14, A16 : un refus de taille est confirmé par une relecture fraîche sans
    /// notification, puis corrigé une fois par l'ancêtre de l'axe contraint ; au plus 2 écritures
    /// par fenêtre et par génération, voisine comprise.
    @Test
    func confirmedRefusalIsCorrectedOnceWithinWriteBudget() {
        let world = TreeWorld(frames: [treeW1: Rect(x: 50, y: 50, width: 300, height: 200), treeW2: Rect(x: 600, y: 50, width: 300, height: 200)])
        world.minimumSizes[treeW1] = CGSize(width: 700, height: 0)
        let store = treeStore("tree-refusal", tree: treeSideBySide, frames: world.frames)
        let harness = TreeHarness("tree-refusal", world: world, store: store)

        let writtenAt = harness.clock.now
        _ = harness.maintainer.tick(cause: "command:startup")
        let pendingDeadline = harness.maintainer.nextDeadline(now: harness.clock.now)
        harness.clock.advance(LayoutTolerance.refusalConfirmDelay)
        let corrected = harness.maintainer.tick(cause: "deadline")
        var later = 0
        for _ in 0..<3 {
            harness.clock.advance(1)
            later += harness.maintainer.tick(cause: "safety").commands
        }

        #expect(pendingDeadline == writtenAt.addingTimeInterval(LayoutTolerance.refusalConfirmDelay))
        // La fenêtre refusée est déjà à sa nouvelle cible : seule la voisine est réécrite.
        #expect(corrected.commands == 1)
        #expect(world.writes[treeW1]?.count == 1)
        #expect(world.writes[treeW2]?.count == 2)
        #expect((world.frames[treeW1]?.width ?? 0) >= 700)
        #expect((world.frames[treeW2]?.x ?? 0) >= 700)
        #expect(later == 0)
        #expect(harness.events.contains("\"source\":\"tree_minimum_size\""))
        // T222 : le budget A13 tient toujours pour l'arbre, avec l'écrivain qui tient le registre.
        for id in [treeW1, treeW2] {
            #expect((harness.registry.entry(for: id.rawValue)?.writesInGeneration ?? 0) <= LayoutTolerance.writeBudgetPerGeneration)
        }
    }

    /// T228 : un échange asymétrique ajuste les splits imbriqués sans reprendre toute la grande
    /// case au terminal. Le plan corrigé reste dans le budget et atteint la stabilité.
    @Test(arguments: [0.0, 120.0])
    func nestedSwapMinimumCorrectionKeepsWriteBudgetAndReachesStability(neighbourMinimum: Double) {
        let terminal = treeW3
        let fourth = WindowID(rawValue: 4)
        let container = CGRect(x: 150, y: 38, width: 1890, height: 1234)
        let display = DisplaySnapshot(
            id: treeScope.displayID, index: 1, name: "nested-swap",
            frame: Rect(container), visibleFrame: Rect(container), isMain: true
        )
        let tree = BSPTree.split(
            orientation: .vertical, ratio: 0.657, first: .leaf(treeW1),
            second: .split(
                orientation: .horizontal, ratio: 0.5, first: .leaf(treeW2),
                second: .split(orientation: .vertical, ratio: 0.5, first: .leaf(terminal), second: .leaf(fourth))
            )
        )
        let world = TreeWorld(displays: [display], frames: tree.place(in: container, innerGap: 10).mapValues(Rect.init))
        world.minimumSizes[treeW1] = CGSize(width: 840, height: 120)
        world.minimumSizes[fourth] = CGSize(width: neighbourMinimum, height: 0)
        let store = treeStore("tree-nested-swap", display: display, tree: tree, frames: world.frames)
        let harness = TreeHarness("tree-nested-swap", world: world, store: store, gapsInner: 10)

        #expect(harness.maintainer.tick(cause: "command:startup").commands == 0)
        harness.clock.advance(5)
        let command = harness.command("swap") { $0.swapping(terminal, treeW1) }
        let generation = harness.generations.current
        #expect(command.commands == 2)
        #expect(harness.registry.entry(for: treeW1.rawValue)?.hasRefusal == true)
        harness.clock.advance(LayoutTolerance.refusalConfirmDelay)
        let corrected = harness.maintainer.tick(cause: "deadline")

        #expect(corrected.commands > 0)
        #expect((world.frames[treeW1]?.width ?? 0) >= 840)
        #expect((world.frames[terminal]?.width ?? 0) >= 840)
        let finalTree = store.state().bspTree(for: treeScope)
        #expect(finalTree?.windowIDs == tree.swapping(terminal, treeW1).windowIDs)
        for (id, target) in finalTree?.place(in: container, innerGap: 10) ?? [:] {
            #expect(world.frames[id] == Rect(target))
            #expect((world.writes[id]?.count ?? 0) <= LayoutTolerance.writeBudgetPerGeneration)
            #expect((harness.registry.entry(for: id.rawValue)?.writesInGeneration ?? 0) <= LayoutTolerance.writeBudgetPerGeneration)
        }
        #expect(harness.generations.current == generation)
        #expect(harness.count("layout_clamped_scope_repaired") == 1)
        harness.clock.advance(0.1)
        #expect(harness.maintainer.tick(cause: "deadline").commands == 0)
        #expect(harness.count("layout_stable") == 1)
        for _ in 0..<3 {
            harness.clock.advance(1)
            #expect(harness.maintainer.tick(cause: "safety").commands == 0)
        }
        #expect(harness.generations.current == generation)
    }

    /// T225, A20 : après la correction d'un refus, la stabilité vise les cibles du plan corrigé.
    /// La fenêtre refusée, déjà à sa nouvelle cible, n'est pas réécrite ; `layout_stable` suit la
    /// lecture 100 ms après l'écriture de correction. L'épisode suivant a son propre
    /// `layout_stable`, compté depuis sa propre passe.
    @Test
    func stabilityAfterRefusalCorrectionTargetsCorrectedPlan() {
        let world = TreeWorld(frames: [treeW1: Rect(x: 50, y: 50, width: 300, height: 200), treeW2: Rect(x: 600, y: 50, width: 300, height: 200)])
        world.minimumSizes[treeW1] = CGSize(width: 700, height: 0)
        let harness = TreeHarness("tree-refusal-stable", world: world, store: treeStore("tree-refusal-stable", tree: treeSideBySide, frames: world.frames))

        _ = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(LayoutTolerance.refusalConfirmDelay)
        let corrected = harness.maintainer.tick(cause: "deadline")
        let stableAtCorrection = harness.count("layout_stable")
        harness.clock.advance(0.1)
        _ = harness.maintainer.tick(cause: "deadline")
        let stableAfterCorrection = harness.count("layout_stable")
        let refusedWrites = world.writes[treeW1]?.count

        harness.clock.advance(5)
        world.frames[treeW2] = nil
        let next = harness.maintainer.tick(cause: "ax:AXUIElementDestroyed")
        harness.clock.advance(0.1)
        _ = harness.maintainer.tick(cause: "deadline")

        #expect(corrected.commands == 1)
        #expect(refusedWrites == 1)
        #expect(stableAtCorrection == 0)
        #expect(stableAfterCorrection == 1)
        #expect(next.commands == 1)
        #expect(harness.count("layout_stable") == 2)
        // Première : 200 ms depuis la passe de démarrage ; seconde : 100 ms depuis sa propre passe.
        #expect(harness.events.contains("\"stableAfterMs\":\"200\""))
        #expect(harness.events.contains("\"stableAfterMs\":\"100\""))
    }

    /// T225, A20 : un épisode qui écrit avant la lecture de stabilité du précédent compte son
    /// `stableAfterMs` depuis sa propre passe.
    @Test
    func overlappingEpisodeCountsStabilityFromItsOwnPass() {
        let world = TreeWorld(frames: [treeW1: Rect(x: 50, y: 50, width: 300, height: 200), treeW2: Rect(x: 600, y: 50, width: 300, height: 200)])
        let harness = TreeHarness("tree-stable-overlap", world: world, store: treeStore("tree-stable-overlap", tree: treeSideBySide, frames: world.frames))

        harness.episodes.begin(cause: "command:startup")
        _ = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(0.05)
        harness.episodes.begin(cause: "ax:AXUIElementDestroyed")
        world.frames[treeW2] = nil
        let closed = harness.maintainer.tick(cause: "ax:AXUIElementDestroyed")
        harness.clock.advance(0.1)
        _ = harness.maintainer.tick(cause: "deadline")

        #expect(closed.commands == 1)
        #expect(harness.count("layout_stable") == 1)
        #expect(harness.events.contains("\"stableAfterMs\":\"100\""))
    }

    /// A2 : une correction infaisable (taille minimale plus grande que l'écran) laisse le
    /// chevauchement, comme yabai : la frame obtenue est acceptée, sans nouvelle écriture.
    @Test
    func infeasibleRefusalIsAcceptedWithoutRetry() {
        let world = TreeWorld(frames: [treeW1: Rect(x: 50, y: 50, width: 300, height: 200), treeW2: treeRight])
        world.minimumSizes[treeW1] = CGSize(width: 1200, height: 0)
        let store = treeStore("tree-refusal-infeasible", tree: treeSideBySide, frames: world.frames)
        let harness = TreeHarness("tree-refusal-infeasible", world: world, store: store)

        _ = harness.maintainer.tick(cause: "command:startup")
        var later = 0
        for step in [LayoutTolerance.refusalConfirmDelay, 1, 1] {
            harness.clock.advance(step)
            later += harness.maintainer.tick(cause: "deadline").commands
        }

        #expect(world.writes[treeW1]?.count == 1)
        #expect(later == 0)
        #expect(store.state().bspTree(for: treeScope) == treeSideBySide)
        #expect(harness.events.contains("\"reason\":\"minimum_size_infeasible\""))
    }

    /// SC-003, FR-017 : une stage rangée et laissée au repos 60 s ne reçoit aucun placement, et
    /// rien n'est en attente.
    @Test
    func idleArrangedStageReceivesNoPlacement() {
        let world = TreeWorld(frames: [treeW1: treeLeft, treeW2: treeRight])
        let harness = TreeHarness("tree-idle", world: world, store: treeStore("tree-idle", tree: treeSideBySide, frames: world.frames))

        var commands = harness.maintainer.tick(cause: "command:startup").commands
        for _ in 0..<30 {
            harness.clock.advance(2)
            commands += harness.maintainer.tick(cause: "safety").commands
        }

        #expect(commands == 0)
        #expect(world.totalWrites == 0)
        #expect(harness.count("layout_apply") == 0)
        #expect(harness.maintainer.nextDeadline(now: harness.clock.now) == nil)
    }

    /// A5 : le retour d'un membre manquant ouvre la garde de l'écran ; elle tient la passe tant que
    /// le bureau n'est pas un bureau utilisateur, puis se ferme sur la sonde (`userSpace`).
    @Test
    func memberReturnGuardClosesOnUserSpace() {
        let world = TreeWorld(frames: [treeW1: treeLeft, treeW2: treeRight])
        let probe = ProbeBox(false)
        let harness = TreeHarness(
            "tree-guard-user-space",
            world: world,
            store: treeStore("tree-guard-user-space", tree: treeSideBySide, frames: world.frames),
            spaceProbe: { _ in probe.value }
        )

        _ = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(5)
        world.frames[treeW2] = nil
        _ = harness.maintainer.tick(cause: "ax:AXUIElementDestroyed")
        harness.clock.advance(5)
        world.frames[treeW2] = Rect(x: 0, y: 0, width: 1000, height: 500)
        let guarded = harness.maintainer.tick(cause: "ax:AXWindowCreated")
        let pollDeadline = harness.maintainer.nextDeadline(now: harness.clock.now)
        harness.clock.advance(LayoutTolerance.spaceGuardPoll)
        probe.value = true
        let released = harness.maintainer.tick(cause: "deadline")

        #expect(guarded.commands == 0)
        #expect(pollDeadline == harness.clock.now)
        #expect(released.commands >= 1)
        #expect(world.frames[treeW1] == treeLeft)
        #expect(world.frames[treeW2] == treeRight)
        #expect(harness.events.contains("\"closedBy\":\"userSpace\""))
        #expect(harness.events.contains("\"reason\":\"member_return\""))
    }

    /// A5, A20 : à la sortie du plein écran natif, la garde reste ouverte jusqu'au plafond si le
    /// bureau utilisateur n'est jamais confirmé (`timeout`) ; l'épisode reste ouvert pendant la garde.
    @Test
    func fullscreenExitGuardTimesOutWithinOneEpisode() {
        let world = TreeWorld(frames: [treeW1: treeLeft, treeW2: Rect(treeContainer)])
        world.nativeFullscreen = [treeW2]
        world.focused = treeW1
        let harness = TreeHarness(
            "tree-guard-timeout",
            world: world,
            store: treeStore("tree-guard-timeout", tree: treeSideBySide, frames: world.frames),
            spaceProbe: { _ in false }
        )

        _ = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(5)
        world.nativeFullscreen = []
        let episode = harness.episodes.begin(cause: "ax:AXWindowResized")
        let opened = harness.clock.now
        var held = harness.maintainer.tick(cause: "ax:AXWindowResized").commands
        var released = MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
        while let deadline = harness.maintainer.nextDeadline(now: harness.clock.now),
              deadline <= opened.addingTimeInterval(LayoutTolerance.spaceGuardCap) {
            harness.clock.now = deadline
            let tick = harness.maintainer.tick(cause: "deadline")
            if harness.clock.now < opened.addingTimeInterval(LayoutTolerance.spaceGuardCap) {
                held += tick.commands
            } else {
                released = tick
                break
            }
        }

        #expect(held == 0)
        #expect(released.commands >= 1)
        #expect(harness.episodes.current == episode)
        #expect(harness.events.contains("\"closedBy\":\"timeout\""))
        #expect(harness.events.contains("\"reason\":\"fullscreen_exit\""))
        #expect(world.frames[treeW2] == treeRight)
    }

    /// A19 : sonde indisponible, la garde se ferme sur `spaceDidChange` reçu après l'ouverture,
    /// puis deux lectures fraîches identiques espacées de `spaceGuardPoll`.
    @Test
    func guardFallsBackToSpaceDidChangeAndStableReads() {
        let world = TreeWorld(frames: [treeW1: treeLeft, treeW2: treeRight])
        let harness = TreeHarness(
            "tree-guard-fallback",
            world: world,
            store: treeStore("tree-guard-fallback", tree: treeSideBySide, frames: world.frames),
            spaceProbe: { _ in nil }
        )

        _ = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(5)
        world.frames[treeW2] = nil
        _ = harness.maintainer.tick(cause: "ax:AXUIElementDestroyed")
        harness.clock.advance(5)
        world.frames[treeW2] = Rect(x: 0, y: 0, width: 1000, height: 500)
        let opened = harness.maintainer.tick(cause: "ax:AXWindowCreated")
        harness.clock.advance(LayoutTolerance.spaceGuardPoll)
        let withoutSignal = harness.maintainer.tick(cause: "deadline")
        harness.clock.advance(0.01)
        harness.maintainer.spaceDidChange(displayUUID: nil)
        harness.clock.advance(LayoutTolerance.spaceGuardPoll)
        let sampled = harness.maintainer.tick(cause: "ax:activeSpaceDidChange")
        harness.clock.advance(LayoutTolerance.spaceGuardPoll)
        let released = harness.maintainer.tick(cause: "deadline")

        #expect(opened.commands == 0)
        #expect(withoutSignal.commands == 0)
        #expect(sampled.commands == 0)
        #expect(released.commands >= 1)
        #expect(harness.events.contains("\"closedBy\":\"spaceDidChange\""))
    }

    /// US3.3, A4 : un redimensionnement à la souris déplace la frontière de l'arbre au relâchement ;
    /// la voisine s'ajuste une seule fois et la fenêtre déplacée n'est pas réécrite.
    @Test
    func resizeGestureMovesTreeFenceAndNeighborOnce() {
        let world = TreeWorld(frames: [treeW1: treeLeft, treeW2: treeRight])
        let store = treeStore("tree-gesture-resize", tree: treeSideBySide, frames: world.frames)
        let gesture = GestureBox()
        let harness = TreeHarness("tree-gesture-resize", world: world, store: store, takeGesture: gesture.take)

        _ = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(5)
        world.frames[treeW1] = Rect(x: 0, y: 0, width: 700, height: 500)
        gesture.session = GestureSession(windowID: treeW1.rawValue, startFrame: treeLeft.cgRect, startedAt: harness.clock.now, endedAt: harness.clock.now)
        let released = harness.maintainer.tick(cause: "drag")
        harness.clock.advance(1)
        let after = harness.maintainer.tick(cause: "safety")

        #expect(released.commands == 1)
        #expect(world.writes[treeW1] == nil)
        #expect(world.frames[treeW2] == Rect(x: 700, y: 0, width: 300, height: 500))
        #expect(after.commands == 0)
        #expect(harness.count("layout_manual_gesture") == 1)
        #expect(harness.events.contains("\"ratio\":\"0.700\""))
        #expect(harness.events.contains("\"cause\":\"drag\""))
        if case .split(_, let ratio, _, _) = store.state().bspTree(for: treeScope) {
            #expect(abs(ratio - 0.7) < 0.01)
        } else {
            Issue.record("arbre attendu")
        }
    }

    @Test(arguments: [false, true])
    func recognizedBspGestureOverridesSavedGridAndSurvivesFocusChange(commandInProgress: Bool) {
        let display = DisplaySnapshot(id: lotCDisplay().id, index: 1, name: "External", frame: Rect(x: 0, y: 0, width: 1000, height: 1000), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 1000), isMain: true)
        let frames: [WindowID: Rect] = [
            treeW1: Rect(x: 0, y: 0, width: 500, height: 499),
            treeW2: Rect(x: 0, y: 500, width: 500, height: 500),
            WindowID(rawValue: 3): Rect(x: 500, y: 0, width: 500, height: 499),
            WindowID(rawValue: 4): Rect(x: 500, y: 500, width: 500, height: 500),
        ]
        let world = TreeWorld(displays: [display], frames: frames)
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5,
            first: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(treeW1), second: .leaf(treeW2)),
            second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(WindowID(rawValue: 3)), second: .leaf(WindowID(rawValue: 4))))
        let store = treeStore("bsp-four-quarters-gesture", display: display, tree: tree, frames: frames, mode: .bsp)
        let gesture = GestureBox()
        let activity = LayoutCommandActivity(path: tempPath("bsp-grid-command-activity"), enabled: true)
        defer { activity.reset() }
        let harness = TreeHarness("bsp-four-quarters-gesture", world: world, store: store, strategy: .bsp, takeGesture: gesture.take, commandActivity: activity)
        _ = harness.maintainer.tick()
        #expect(harness.service.hasValidLayoutIntent(scope: treeScope, in: harness.service.snapshot()))
        harness.clock.advance(5)
        if commandInProgress { activity.markActive(reason: "test", scopes: [treeScope], now: harness.clock.now, holdSeconds: 5) }
        let id = WindowID(rawValue: 3)
        gesture.session = GestureSession(windowID: 3, startFrame: frames[id]!.cgRect, startedAt: harness.clock.now, endedAt: harness.clock.now)
        world.frames[id] = Rect(x: 400, y: 0, width: 600, height: 499)
        _ = harness.maintainer.tick(cause: "drag")
        harness.clock.advance(0.5)
        _ = harness.maintainer.tick(cause: "deadline")

        #expect(world.frames[id] == Rect(x: 400, y: 0, width: 600, height: 499))
        #expect(world.frames[treeW1]?.width == 400)
        #expect(world.frames[treeW2]?.width == 400)
        #expect(world.frames[WindowID(rawValue: 4)] == Rect(x: 400, y: 500, width: 600, height: 500))
        #expect(harness.count("external_geometry_snapped_to_layout_model") == 0)
        let settled = world.frames
        world.focused = treeW2
        world.frames[id] = frames[id]
        harness.clock.advance(5)
        _ = harness.maintainer.tick(cause: "ax:didActivateApplication")
        #expect(world.frames == settled)
    }

    @Test
    func knownMinimumLimitsGestureBeforeWritingRefusedNeighborSize() {
        let world = TreeWorld(frames: [treeW1: treeLeft, treeW2: treeRight])
        world.frames[treeW1] = Rect(x: 0, y: 0, width: 650, height: 500)
        world.minimumSizes[treeW1] = CGSize(width: 600, height: 0)
        let store = treeStore("tree-known-minimum-gesture", tree: treeSideBySide, frames: world.frames)
        let gesture = GestureBox()
        let harness = TreeHarness("tree-known-minimum-gesture", world: world, store: store, takeGesture: gesture.take)
        _ = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(0.11)
        _ = harness.maintainer.tick(cause: "deadline")
        harness.clock.advance(0.2)
        _ = harness.maintainer.tick(cause: "deadline")
        world.frames[treeW1] = Rect(x: 0, y: 0, width: 610, height: 500)
        harness.clock.advance(2)
        _ = harness.maintainer.tick(cause: "ax:AXWindowResized")
        let start = world.frames[treeW2]!.cgRect
        let previousWrites = world.writes[treeW1]?.count ?? 0
        harness.clock.advance(5)
        world.frames[treeW2] = Rect(x: 300, y: 0, width: 700, height: 500)
        gesture.session = GestureSession(windowID: treeW2.rawValue, startFrame: start, startedAt: harness.clock.now, endedAt: harness.clock.now)
        let tick = harness.maintainer.tick(cause: "drag")

        #expect(tick.clamped == 0)
        #expect((world.writes[treeW1]?.count ?? 0) == previousWrites)
        #expect(world.frames[treeW1]?.width == 600)
        #expect(world.frames[treeW2]?.x == 600)
        harness.clock.advance(1)
        #expect(harness.maintainer.tick().commands == 0)
    }

    @Test(arguments: [WindowManagementMode.bsp, .spatialBsp], [false, true])
    func changedFrameRetriesFailedDisplayRepairAndRecoveryCommitsMembership(targetMode: WindowManagementMode, geometryChanged: Bool) {
        let target = lotCDisplay(id: "target", x: 1000)
        let id = WindowID(rawValue: 9)
        let world = TreeWorld(displays: [lotCDisplay(), target], frames: [id: Rect(x: 1200, y: 100, width: 300, height: 300)])
        world.unwritable.insert(id)
        let store = treeStore("drift-failure-recovery", tree: .leaf(id), frames: world.frames, mode: .bsp)
        let harness = TreeHarness("drift-failure-recovery", world: world, store: store, strategy: targetMode)
        #expect(harness.maintainer.tick().failed > 0)
        #expect(store.state().scopes.first(where: { $0.displayID == lotCDisplay().id })?.stages.first?.mode == .bsp)
        let initialWrites = world.totalWrites
        for _ in 0..<20 {
            harness.clock.advance(0.1)
            _ = harness.maintainer.tick(cause: "deadline")
        }
        #expect(world.totalWrites == initialWrites)
        if geometryChanged {
            world.frames[id] = Rect(x: 1250, y: 100, width: 300, height: 300)
            harness.clock.advance(0.2)
            _ = harness.maintainer.tick(cause: "ax:AXWindowMoved")
            #expect(world.totalWrites > initialWrites)
        }
        world.unwritable.remove(id)
        harness.clock.advance(3.1)
        #expect(harness.maintainer.tick().failed == 0)
        #expect(harness.service.snapshot().windows.first(where: { $0.window.id == id })?.scope?.displayID == target.id)
        #expect(harness.count("window.scope_reconciled_to_physical_display") + harness.count("window_manual_display_move_adopted") >= 1)
    }

    /// T231 : un clic hors du cadre, sur la poignée, doit conserver le redimensionnement au premier essai.
    @MainActor
    @Test
    func resizeFromOutsideRightEdgeMovesFenceOnFirstAttempt() {
        let world = TreeWorld(frames: [treeW1: treeLeft, treeW2: Rect(x: 510, y: 0, width: 490, height: 500)])
        let store = treeStore("tree-gesture-edge", tree: treeSideBySide, frames: world.frames)
        let input = UserInputActivity()
        let harness = TreeHarness("tree-gesture-edge", world: world, store: store, gapsInner: 10, takeGesture: input.takeGesture)
        _ = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(5)
        let initial = world.frames[treeW1]!.cgRect
        input.observeGestures(target: { point in
            FocusFollowsMousePicker.gestureTargetWindow(at: point, in: harness.service.sharedSnapshot())
                .map { ($0.window.id.rawValue, $0.window.frame.cgRect) }
        }, onRelease: { _ in })

        input.mouseDown(at: CGPoint(x: initial.maxX + 2, y: initial.midY), now: harness.clock.now)
        #expect(input.currentGesture?.windowID == treeW1.rawValue)
        world.frames[treeW1] = Rect(x: 0, y: 0, width: 700, height: 500)
        input.mouseUp(leftButton: true, now: harness.clock.now.addingTimeInterval(0.5))
        _ = harness.maintainer.tick(cause: "drag")

        #expect(world.frames[treeW1]?.width == 700)
        #expect(world.frames[treeW2] == Rect(x: 710, y: 0, width: 290, height: 500))
        #expect(harness.count("layout_manual_gesture") == 1)
        #expect(harness.count("layout_external_change_reverted") == 0)
    }

    /// US3.3 : la frontière d'un geste horizontal ne touche pas le split imbriqué de la voisine
    /// (réécriture pour l'arbre de `mutableBspHorizontalResizePreservesNestedVerticalSplit`).
    @Test
    func resizeGesturePreservesNestedSplit() {
        let nested = BSPTree.split(
            orientation: .vertical, ratio: 0.5, first: .leaf(treeW1),
            second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(treeW2), second: .leaf(treeW3))
        )
        let targets = nested.place(in: treeContainer, innerGap: 0)
        let world = TreeWorld(frames: targets.mapValues { Rect($0) })
        let store = treeStore("tree-gesture-nested", tree: nested, frames: world.frames)
        let gesture = GestureBox()
        let harness = TreeHarness("tree-gesture-nested", world: world, store: store, takeGesture: gesture.take)

        _ = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(5)
        world.frames[treeW1] = Rect(x: 0, y: 0, width: 640, height: 500)
        gesture.session = GestureSession(windowID: treeW1.rawValue, startFrame: targets[treeW1], startedAt: harness.clock.now, endedAt: harness.clock.now)
        _ = harness.maintainer.tick(cause: "drag")

        #expect(world.frames[treeW2]?.x == 640)
        #expect(world.frames[treeW3]?.x == 640)
        #expect(world.frames[treeW2]?.height == Rect(targets[treeW2]!).height)
        #expect(world.frames[treeW3]?.height == Rect(targets[treeW3]!).height)
        #expect(world.writes[treeW2]?.count == 1)
        #expect(world.writes[treeW3]?.count == 1)
    }

    /// A17 : une position changée sans dépôt ramène la fenêtre à l'arbre, même juste après une
    /// écriture de Roadie (pas de réponse d'application pour un geste).
    @Test
    func moveGestureWithoutDropSnapsBackToTree() {
        let world = TreeWorld(frames: [treeW1: Rect(x: 50, y: 50, width: 300, height: 200), treeW2: treeRight])
        let store = treeStore("tree-gesture-move", tree: treeSideBySide, frames: world.frames)
        let gesture = GestureBox()
        let harness = TreeHarness("tree-gesture-move", world: world, store: store, takeGesture: gesture.take)

        _ = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(0.3)
        world.frames[treeW1] = Rect(x: 80, y: 40, width: 500, height: 500)
        gesture.session = GestureSession(windowID: treeW1.rawValue, startFrame: treeLeft.cgRect, startedAt: harness.clock.now, endedAt: harness.clock.now)
        let released = harness.maintainer.tick(cause: "drag")

        #expect(released.commands == 1)
        #expect(world.frames[treeW1] == treeLeft)
        #expect(store.state().bspTree(for: treeScope) == treeSideBySide)
    }

    /// A17, T216 : un dépôt reconnu (navrail, glisser-déposer) consomme la session avant la passe :
    /// aucune frontière n'est ajustée. La preuve est la session consommée, pas une grâce.
    @Test
    func gestureConsumedByDropDoesNotMoveFence() {
        let world = TreeWorld(frames: [treeW1: treeLeft, treeW2: treeRight])
        let store = treeStore("tree-gesture-drop", tree: treeSideBySide, frames: world.frames)
        let gesture = GestureBox()
        let harness = TreeHarness("tree-gesture-drop", world: world, store: store, takeGesture: gesture.take)

        _ = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(5)
        world.frames[treeW1] = Rect(x: 0, y: 0, width: 700, height: 500)
        gesture.session = GestureSession(windowID: treeW1.rawValue, startFrame: treeLeft.cgRect, startedAt: harness.clock.now, endedAt: harness.clock.now)
        _ = gesture.take() // dépôt reconnu
        _ = harness.maintainer.tick(cause: "drag")

        #expect(store.state().bspTree(for: treeScope) == treeSideBySide)
        #expect(harness.count("layout_manual_gesture") == 0)
    }

    /// T216 : une grâce de commande ou de fin de glisser sans dépôt reconnu ne supprime pas le
    /// geste ; la session non consommée ajuste la frontière (A17).
    @Test
    func releaseGraceWithoutDropKeepsGesture() {
        let world = TreeWorld(frames: [treeW1: treeLeft, treeW2: treeRight])
        let store = treeStore("tree-gesture-grace", tree: treeSideBySide, frames: world.frames)
        let gesture = GestureBox()
        let activity = LayoutCommandActivity(path: tempPath("tree-gesture-grace-activity"), enabled: true)
        let drag = WindowDragActivity(path: tempPath("tree-gesture-grace-drag"))
        defer {
            activity.reset()
            drag.reset()
        }
        let harness = TreeHarness(
            "tree-gesture-grace", world: world, store: store, takeGesture: gesture.take,
            dragActivity: drag, commandActivity: activity
        )

        _ = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(5)
        activity.markActive(reason: "rail_drop", scopes: [treeScope], now: harness.clock.now, holdSeconds: 2)
        drag.finish(now: harness.clock.now)
        world.frames[treeW1] = Rect(x: 0, y: 0, width: 700, height: 500)
        gesture.session = GestureSession(windowID: treeW1.rawValue, startFrame: treeLeft.cgRect, startedAt: harness.clock.now, endedAt: harness.clock.now)
        _ = harness.maintainer.tick(cause: "drag")

        #expect(harness.count("layout_manual_gesture") == 1)
        #expect(world.frames[treeW2] == Rect(x: 700, y: 0, width: 300, height: 500))
    }

    /// T216 : un dépôt reconnu par un autre processus laisse sa preuve dans le fichier partagé du
    /// glisser (`lastDrop`) ; la session de ce processus, ouverte avant, n'ajuste aucune frontière.
    @Test
    func dropProofFromAnotherProcessSuppressesGesture() {
        let world = TreeWorld(frames: [treeW1: treeLeft, treeW2: treeRight])
        let store = treeStore("tree-gesture-drop-proof", tree: treeSideBySide, frames: world.frames)
        let gesture = GestureBox()
        let path = tempPath("tree-gesture-drop-proof-drag")
        let producer = WindowDragActivity(path: path)
        let consumer = WindowDragActivity(path: path)
        defer { producer.reset() }
        let harness = TreeHarness("tree-gesture-drop-proof", world: world, store: store, takeGesture: gesture.take, dragActivity: consumer)

        _ = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(5)
        let startedAt = harness.clock.now
        producer.markActive(windowID: treeW1, now: startedAt)
        harness.clock.advance(0.3)
        world.frames[treeW1] = Rect(x: 0, y: 0, width: 700, height: 500)
        producer.finish(now: harness.clock.now, droppedWindowID: treeW1)
        gesture.session = GestureSession(windowID: treeW1.rawValue, startFrame: treeLeft.cgRect, startedAt: startedAt, endedAt: harness.clock.now)
        _ = harness.maintainer.tick(cause: "drag")

        #expect(store.state().bspTree(for: treeScope) == treeSideBySide)
        #expect(harness.count("layout_manual_gesture") == 0)
    }

    /// A17 (2), T206 : relâchement reçu par le maintainer avant le dépôt, glisser encore actif : la
    /// passe ne consomme pas la session ; le dépôt la consomme ensuite ; aucune frontière ajustée.
    @Test
    func releaseBeforeDropLeavesSessionToDrop() {
        let world = TreeWorld(frames: [treeW1: treeLeft, treeW2: treeRight])
        let store = treeStore("tree-gesture-release-first", tree: treeSideBySide, frames: world.frames)
        let gesture = GestureBox()
        let drag = WindowDragActivity(path: tempPath("tree-gesture-release-first-drag"))
        defer { drag.reset() }
        let harness = TreeHarness("tree-gesture-release-first", world: world, store: store, takeGesture: gesture.take, dragActivity: drag)

        _ = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(5)
        drag.markActive(windowID: treeW1, now: harness.clock.now)
        world.frames[treeW1] = Rect(x: 0, y: 0, width: 700, height: 500)
        let session = GestureSession(windowID: treeW1.rawValue, startFrame: treeLeft.cgRect, startedAt: harness.clock.now, endedAt: harness.clock.now)
        gesture.session = session
        let beforeDrop = harness.maintainer.tick(cause: "drag")
        #expect(gesture.session == session)
        let dropped = gesture.take() // le dépôt consomme la session
        drag.finish(now: harness.clock.now)
        harness.clock.advance(0.02)
        _ = harness.maintainer.tick(cause: "drag")

        #expect(beforeDrop.commands == 0)
        #expect(dropped == session)
        #expect(store.state().bspTree(for: treeScope) == treeSideBySide)
        #expect(harness.count("layout_manual_gesture") == 0)
    }

    /// A17 (1), T206 : fenêtre détruite pendant le geste : aucune frontière ajustée, la voisine
    /// reprend la place en une passe.
    @Test
    func windowDestroyedDuringGestureGivesPlaceWithoutFence() {
        let world = TreeWorld(frames: [treeW1: treeLeft, treeW2: treeRight])
        let store = treeStore("tree-gesture-destroyed", tree: treeSideBySide, frames: world.frames)
        let gesture = GestureBox()
        let harness = TreeHarness("tree-gesture-destroyed", world: world, store: store, takeGesture: gesture.take)

        _ = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(5)
        world.frames[treeW1] = nil
        harness.service.noteWindowDestroyed(treeW1)
        gesture.session = GestureSession(windowID: treeW1.rawValue, startFrame: treeLeft.cgRect, startedAt: harness.clock.now, endedAt: harness.clock.now)
        let released = harness.maintainer.tick(cause: "drag")
        harness.clock.advance(1)
        let after = harness.maintainer.tick(cause: "safety")

        #expect(released.commands == 1)
        #expect(world.frames[treeW2] == Rect(treeContainer))
        #expect(world.writes[treeW2]?.count == 1)
        #expect(after.commands == 0)
        #expect(harness.count("layout_manual_gesture") == 0)
    }

    /// R12 : l'activité d'une commande ne suspend pas un scope à arbre (la commande applique
    /// elle-même l'arbre), contrairement aux modes sans arbre.
    @Test
    func commandActivityDoesNotSuspendTreeScope() {
        let world = TreeWorld(frames: [treeW1: Rect(x: 50, y: 50, width: 300, height: 200), treeW2: treeRight])
        let activity = LayoutCommandActivity(path: tempPath("tree-command-activity"), enabled: true)
        defer { activity.reset() }
        let harness = TreeHarness(
            "tree-command-activity",
            world: world,
            store: treeStore("tree-command-activity", tree: treeSideBySide, frames: world.frames),
            commandActivity: activity
        )
        activity.markActive(reason: "test", now: harness.clock.now, holdSeconds: 5)

        let tick = harness.maintainer.tick(cause: "command:startup")

        #expect(tick.commands == 1)
        #expect(world.frames[treeW1] == treeLeft)
    }

    // MARK: Convergence (T205, T209, T211, T217, T218, T219)

    /// A15, T205 : une commande appliquée par `applyTreeScope` pendant une rafale clôt l'attente du
    /// scope : la passe suivante écrit sans attendre `burstQuiet`.
    @Test
    func commandClosesMembershipBurst() {
        let world = TreeWorld(frames: [treeW1: treeLeft, treeW2: treeRight])
        world.focused = treeW2
        let harness = TreeHarness("tree-command-burst", world: world, store: treeStore("tree-command-burst", tree: treeSideBySide, frames: world.frames))

        _ = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(5)
        world.frames[treeW3] = Rect(x: 100, y: 100, width: 300, height: 200)
        _ = harness.maintainer.tick(cause: "ax:AXWindowCreated")
        harness.clock.advance(0.05)
        world.frames[treeW3] = nil
        let held = harness.maintainer.tick(cause: "ax:AXUIElementDestroyed")
        harness.clock.advance(0.02)
        let command = harness.command("balance")
        harness.clock.advance(0.01)
        #expect(world.writes[treeW1] == nil)
        world.frames[treeW1] = Rect(x: 40, y: 30, width: 400, height: 300)
        let after = harness.maintainer.tick(cause: "ax:AXWindowMoved")

        #expect(held.commands == 0)
        #expect(harness.count("layout_stage_membership_settling") == 1)
        #expect(command.commands >= 1)
        #expect(after.commands == 1)
        #expect(world.frames[treeW1] == treeLeft)
    }

    /// A15, T205 : une commande pendant une garde de bureau ouverte la clôt (`closedBy=command`) :
    /// la passe suivante écrit sans attendre `spaceGuardCap`.
    @Test
    func commandClosesSpaceGuard() {
        let world = TreeWorld(frames: [treeW1: treeLeft, treeW2: treeRight])
        let harness = TreeHarness(
            "tree-command-guard",
            world: world,
            store: treeStore("tree-command-guard", tree: treeSideBySide, frames: world.frames),
            spaceProbe: { _ in false }
        )

        _ = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(5)
        world.frames[treeW2] = nil
        _ = harness.maintainer.tick(cause: "ax:AXUIElementDestroyed")
        harness.clock.advance(5)
        world.frames[treeW2] = Rect(treeContainer)
        let guarded = harness.maintainer.tick(cause: "ax:AXWindowCreated")
        harness.clock.advance(0.2)
        let command = harness.command("balance")
        harness.clock.advance(1.1)
        world.frames[treeW1] = Rect(x: 40, y: 30, width: 400, height: 300)
        let after = harness.maintainer.tick(cause: "ax:AXWindowMoved")

        #expect(guarded.commands == 0)
        #expect(command.commands >= 1)
        #expect(after.commands == 1)
        #expect(world.frames[treeW1] == treeLeft)
        #expect(harness.events.contains("\"closedBy\":\"command\""))
        #expect(!harness.events.contains("\"closedBy\":\"timeout\""))
    }

    /// A20, T209 : la lecture de stabilité a lieu 100 ms après la fin de l'écriture, pas après le
    /// début de la passe (ici, chaque écriture dure 30 ms).
    @Test
    func stabilityIsReadAfterWriteEnd() {
        let clock = TestClock()
        let world = TreeWorld(frames: [treeW1: Rect(x: 50, y: 50, width: 300, height: 200), treeW2: Rect(x: 600, y: 50, width: 300, height: 200)])
        world.onWrite = { clock.advance(0.03) }
        let harness = TreeHarness("tree-stability-write-end", world: world, store: treeStore("tree-stability-write-end", tree: treeSideBySide, frames: world.frames), clock: clock)

        let start = clock.now
        _ = harness.maintainer.tick(cause: "command:startup")
        let writeEnd = clock.now
        let deadline = harness.maintainer.nextDeadline(now: clock.now)
        clock.now = writeEnd.addingTimeInterval(0.09)
        _ = harness.maintainer.tick(cause: "safety")
        let early = harness.count("layout_stable")
        clock.now = deadline ?? clock.now
        _ = harness.maintainer.tick(cause: "deadline")

        #expect(writeEnd.timeIntervalSince(start) >= 0.06 - 1e-6)
        #expect(abs((deadline ?? .distantPast).timeIntervalSince(writeEnd) - 0.1) < 1e-6)
        #expect(early == 0)
        #expect(harness.count("layout_stable") == 1)
    }

    /// T219, A20 : une commande appliquée sur l'arbre arme la vérification de stabilité 100 ms après
    /// son écriture ; la passe d'échéance la constate sans réécrire, dans la génération de la commande.
    @Test
    func commandArmsStabilityAndKeepsItsGeneration() {
        let world = TreeWorld(frames: [treeW1: treeLeft, treeW2: treeRight])
        let harness = TreeHarness("tree-command-stability", world: world, store: treeStore("tree-command-stability", tree: treeSideBySide, frames: world.frames))

        _ = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(5)
        let command = harness.command("swap") { $0.swapping(treeW1, treeW2) }
        let appliedAt = harness.clock.now
        let generation = harness.generations.current
        let deadline = harness.maintainer.nextDeadline(now: appliedAt)
        harness.clock.now = deadline ?? appliedAt
        let tick = harness.maintainer.tick(cause: "deadline")

        #expect(command.commands == 2)
        #expect(world.frames[treeW1] == treeRight)
        #expect(abs((deadline ?? .distantPast).timeIntervalSince(appliedAt) - 0.1) < 1e-6)
        #expect(tick.commands == 0)
        #expect(harness.count("layout_stable") == 1)
        #expect(harness.events.contains("\"layoutVersion\":\"\(generation)\""))
        #expect(harness.generations.current == generation)
    }

    /// Un dépôt entre écrans suspend le maintien pendant le geste, applique l'aperçu aux deux
    /// arbres, puis se stabilise sans réécrire ni ramener la fenêtre sur l'écran d'origine.
    @Test(arguments: [false, true])
    func crossDisplayDropKeepsPreviewPlacementAfterRelease(destinationHasWindow: Bool) throws {
        let main = DisplaySnapshot(
            id: treeScope.displayID, index: 1, name: "Mac",
            frame: Rect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: Rect(x: 0, y: 32, width: 1512, height: 950), isMain: true
        )
        let external = DisplaySnapshot(
            id: DisplayID(rawValue: "display-external"), index: 2, name: "LG",
            frame: Rect(x: 1512, y: -964, width: 3840, height: 2160),
            visibleFrame: Rect(x: 1512, y: -934, width: 3840, height: 2130), isMain: false
        )
        let sourceScope = StageScope(displayID: main.id, desktopID: DesktopID(rawValue: 2), stageID: treeScope.stageID)
        let targetScope = StageScope(displayID: external.id, desktopID: DesktopID(rawValue: 1), stageID: treeScope.stageID)
        var frames = treeSideBySide.place(in: main.visibleFrame.cgRect, innerGap: 0).mapValues { Rect($0) }
        if destinationHasWindow { frames[treeW3] = external.visibleFrame }
        let world = TreeWorld(displays: [main, external], frames: frames)
        let member = { (id: WindowID) in
            PersistentStageMember(windowID: id, bundleID: "app.\(id.rawValue)", title: "Window\(id.rawValue)", frame: frames[id]!)
        }
        let store = StageStore(path: tempPath("tree-cross-display-drop"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: main.id, desktopID: sourceScope.desktopID, stages: [
                    PersistentStage(id: sourceScope.stageID, mode: .spatialBsp, members: [member(treeW1), member(treeW2)], bspTree: treeSideBySide)
                ]),
                PersistentStageScope(displayID: external.id, stages: [
                    PersistentStage(id: targetScope.stageID, mode: .spatialBsp, members: destinationHasWindow ? [member(treeW3)] : [], bspTree: destinationHasWindow ? .leaf(treeW3) : .empty)
                ])
            ],
            desktopSelections: [PersistentDesktopSelection(displayID: main.id, currentDesktopID: sourceScope.desktopID)],
            activeDisplayID: main.id
        ))
        let drag = WindowDragActivity(path: tempPath("tree-cross-display-drop-activity"))
        defer { drag.reset() }
        let gesture = GestureBox()
        let harness = TreeHarness("tree-cross-display-drop", world: world, store: store, takeGesture: gesture.take, dragActivity: drag)
        #expect(harness.maintainer.tick(cause: "command:startup").commands == 0)
        harness.clock.advance(5)
        let engine = DropPreviewEngine(service: harness.service)
        let context = engine.makeContext()
        let startedAt = harness.clock.now
        drag.markActive(windowID: treeW1, now: startedAt, holdSeconds: 5)
        world.frames[treeW1] = Rect(x: 2000, y: -400, width: 400, height: 300)
        let before = world.totalWrites
        #expect(harness.maintainer.tick(cause: "drag").commands == 0)
        let candidate = try #require(engine.candidate(sourceWindowID: treeW1, atAXPoint: CGPoint(x: 3432, y: -244), context: context))
        #expect(candidate.scope == targetScope)
        #expect(world.totalWrites == before)
        #expect(store.state().bspTree(for: sourceScope) == treeSideBySide)

        let result = StageCommandService(service: harness.service, store: store, events: EventLog(path: harness.eventPath)).place(
            windowID: treeW1, displayID: candidate.displayID, orderedWindowIDs: candidate.orderedWindowIDs,
            placements: candidate.placements, treeMutation: candidate.treeMutation
        )
        gesture.session = GestureSession(windowID: treeW1.rawValue, startFrame: frames[treeW1]?.cgRect, startedAt: startedAt, endedAt: harness.clock.now)
        drag.finish(now: harness.clock.now, droppedWindowID: treeW1)
        let writesAfterDrop = world.totalWrites
        let generation = try #require(harness.registry.entry(for: treeW1.rawValue)).generation
        harness.clock.advance(0.1)
        #expect(harness.maintainer.tick(cause: "ax:AXWindowMoved").commands == 0)
        #expect(result.changed)
        #expect(store.state().stageScope(for: treeW1) == targetScope)
        #expect(store.state().bspTree(for: sourceScope) == .leaf(treeW2))
        #expect(world.frames[treeW2] == main.visibleFrame)
        for (id, expected) in candidate.placements { #expect(world.frames[id] == expected) }
        #expect(world.frames[treeW1] == Rect(candidate.frame))
        #expect(world.totalWrites == writesAfterDrop)
        #expect(world.writes.values.allSatisfy { $0.count == 1 })
        #expect(world.frames.keys.allSatisfy { harness.registry.entry(for: $0.rawValue)?.generation == generation })
        #expect(harness.count("layout_stable") == 1)
        #expect(harness.count("layout_manual_gesture") == 0)
        harness.clock.advance(5)
        #expect(harness.maintainer.tick(cause: "safety").commands == 0)
        #expect(world.totalWrites == writesAfterDrop)
    }

    /// T217 : une fenêtre d'un scope à arbre posée sur un autre écran, sans geste ni commande,
    /// n'est pas rattachée à cet écran : elle est ramenée à l'arbre.
    @Test
    func treeScopeIgnoresPhysicalDisplayDrift() {
        let left = lotCDisplay(id: "display-a", x: 0)
        let right = lotCDisplay(id: "display-b", x: 1000)
        let world = TreeWorld(displays: [left, right], frames: [treeW1: treeLeft, treeW2: treeRight])
        let store = treeStore("tree-drift", display: left, tree: treeSideBySide, frames: world.frames)
        let harness = TreeHarness("tree-drift", world: world, store: store)

        _ = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(10)
        world.frames[treeW1] = Rect(x: 1200, y: 50, width: 400, height: 300)
        let tick = harness.maintainer.tick(cause: "safety")

        #expect(store.state().stageScope(for: treeW1) == treeScope)
        #expect(!harness.events.contains("window.scope_reconciled_to_physical_display"))
        #expect(tick.commands == 1)
        #expect(world.frames[treeW1] == treeLeft)
    }

    /// T218 : une lecture AX échouée ne confirme pas un refus ; elle est retentée `spaceGuardPoll`
    /// plus tard, et la lecture suivante confirme et corrige.
    @Test
    func failedReadDoesNotConfirmRefusal() {
        let world = TreeWorld(frames: [treeW1: Rect(x: 50, y: 50, width: 300, height: 200), treeW2: Rect(x: 600, y: 50, width: 300, height: 200)])
        world.minimumSizes[treeW1] = CGSize(width: 700, height: 0)
        let store = treeStore("tree-refusal-unreadable", tree: treeSideBySide, frames: world.frames)
        let harness = TreeHarness("tree-refusal-unreadable", world: world, store: store)

        _ = harness.maintainer.tick(cause: "command:startup")
        world.unreadable = [treeW1, treeW2]
        harness.clock.advance(LayoutTolerance.refusalConfirmDelay)
        let unreadableAt = harness.clock.now
        let unreadable = harness.maintainer.tick(cause: "deadline")
        let retry = harness.maintainer.nextDeadline(now: harness.clock.now)
        let stableWhileUnreadable = harness.count("layout_stable")
        world.unreadable = []
        harness.clock.now = retry ?? harness.clock.now
        let corrected = harness.maintainer.tick(cause: "deadline")

        #expect(unreadable.commands == 0)
        #expect(stableWhileUnreadable == 0)
        #expect(abs((retry ?? .distantPast).timeIntervalSince(unreadableAt) - LayoutTolerance.spaceGuardPoll) < 1e-6)
        #expect(corrected.commands == 1)
        #expect(harness.events.contains("\"source\":\"tree_minimum_size\""))
    }

    /// Audit REL-002 : une relecture qui ne tranche pas (ni la frame demandée, ni la frame relue)
    /// est retentée `spaceGuardPoll` plus tard, comme une lecture échouée, et non au plancher
    /// de l'ordonnanceur à chaque passe pendant `echoWindow`.
    @Test
    func inconclusiveRefusalReadIsDelayed() {
        let world = TreeWorld(frames: [treeW1: Rect(x: 50, y: 50, width: 300, height: 200), treeW2: Rect(x: 600, y: 50, width: 300, height: 200)])
        world.minimumSizes[treeW1] = CGSize(width: 700, height: 0)
        let store = treeStore("tree-refusal-inconclusive", tree: treeSideBySide, frames: world.frames)
        let harness = TreeHarness("tree-refusal-inconclusive", world: world, store: store)

        _ = harness.maintainer.tick(cause: "command:startup")
        let refused = world.frames[treeW1] ?? Rect(x: 0, y: 0, width: 0, height: 0)
        world.frames[treeW1] = Rect(x: refused.x, y: refused.y, width: refused.width, height: refused.height - 77)
        harness.clock.advance(LayoutTolerance.refusalConfirmDelay)
        let readAt = harness.clock.now
        let inconclusive = harness.maintainer.tick(cause: "deadline")
        let retry = harness.maintainer.nextDeadline(now: harness.clock.now)

        #expect(inconclusive.commands == 0)
        #expect(abs((retry ?? .distantPast).timeIntervalSince(readAt) - LayoutTolerance.spaceGuardPoll) < 1e-6)
    }

    /// T218 : sonde indisponible et lectures échouées : la garde ne se ferme pas sur
    /// `spaceDidChange` faute d'observation fraîche ; elle attend son plafond.
    @Test
    func guardWithFailedReadsWaitsForCap() {
        let world = TreeWorld(frames: [treeW1: treeLeft, treeW2: treeRight])
        let harness = TreeHarness(
            "tree-guard-unreadable",
            world: world,
            store: treeStore("tree-guard-unreadable", tree: treeSideBySide, frames: world.frames),
            spaceProbe: { _ in nil }
        )

        _ = harness.maintainer.tick(cause: "command:startup")
        harness.clock.advance(5)
        world.frames[treeW2] = nil
        _ = harness.maintainer.tick(cause: "ax:AXUIElementDestroyed")
        harness.clock.advance(5)
        world.frames[treeW2] = Rect(treeContainer)
        world.unreadable = [treeW2]
        let opened = harness.clock.now
        _ = harness.maintainer.tick(cause: "ax:AXWindowCreated")
        harness.maintainer.spaceDidChange(displayUUID: nil)
        var held = 0
        while let deadline = harness.maintainer.nextDeadline(now: harness.clock.now),
              deadline < opened.addingTimeInterval(LayoutTolerance.spaceGuardCap) {
            harness.clock.now = deadline
            held += harness.maintainer.tick(cause: "deadline").commands
        }
        harness.clock.now = opened.addingTimeInterval(LayoutTolerance.spaceGuardCap)
        let released = harness.maintainer.tick(cause: "deadline")

        #expect(held == 0)
        #expect(released.commands >= 1)
        #expect(!harness.events.contains("\"closedBy\":\"spaceDidChange\""))
        #expect(harness.events.contains("\"closedBy\":\"timeout\""))
    }

    /// T211 : le vrai maintainer relié à l'ordonnanceur, horloge contrôlée. La fin d'une rafale
    /// part à son échéance réelle, et la passe finale range le scope.
    @MainActor
    @Test
    func schedulerRunsMaintainerBurstEndAtItsDeadline() {
        let world = TreeWorld(frames: [treeW1: treeLeft, treeW2: treeRight])
        world.focused = treeW2
        let harness = TreeHarness("tree-sched-burst", world: world, store: treeStore("tree-sched-burst", tree: treeSideBySide, frames: world.frames))
        let run = TreeSchedulerRun(harness)

        run.scheduler.request(cause: "command:startup")
        run.timer.advance(by: 1)
        let start = harness.clock.now
        world.frames[treeW3] = Rect(x: 100, y: 100, width: 300, height: 200)
        run.scheduler.request(cause: "ax:AXWindowCreated")
        run.timer.advance(by: 0.08)
        world.frames[treeW3] = nil
        run.scheduler.request(cause: "ax:AXUIElementDestroyed")
        run.timer.advance(by: 2)

        // Passes : 15 ms (création), 95 ms (rafale ouverte), puis la fin de rafale à 95 + 100 ms.
        let burstEnd = start.addingTimeInterval(0.195)
        #expect(run.passes.contains { $0.cause == "deadline" && abs($0.at.timeIntervalSince(burstEnd)) < 0.001 })
        #expect(harness.events.contains("\"cause\":\"deadline:burst\""))
        #expect(world.frames[treeW1] == treeLeft)
        #expect(world.frames[treeW2] == treeRight)
        #expect(run.timer.armedCount == 0)
    }

    /// T211 : la garde de bureau ouverte à la sortie du plein écran se ferme à son plafond de
    /// 1,5 s (au plancher de 15 ms près), par la passe que l'ordonnanceur arme lui-même.
    @MainActor
    @Test
    func schedulerClosesSpaceGuardAtCap() {
        let world = TreeWorld(frames: [treeW1: treeLeft, treeW2: Rect(treeContainer)])
        world.nativeFullscreen = [treeW2]
        world.focused = treeW1
        let harness = TreeHarness(
            "tree-sched-guard",
            world: world,
            store: treeStore("tree-sched-guard", tree: treeSideBySide, frames: world.frames),
            spaceProbe: { _ in false }
        )
        let run = TreeSchedulerRun(harness)

        run.scheduler.request(cause: "command:startup")
        run.timer.advance(by: 1)
        world.nativeFullscreen = []
        run.scheduler.request(cause: "ax:AXWindowResized", delay: .externalChange)
        run.timer.advance(by: 3)

        let held = harness.events
            .components(separatedBy: "\"heldMs\":\"").dropFirst().first?
            .prefix { $0.isNumber }
        #expect(harness.events.contains("\"closedBy\":\"timeout\""))
        #expect(held.flatMap { Int($0) }.map { $0 >= 1500 && $0 <= 1515 } == true)
        #expect(world.frames[treeW2] == treeRight)
        #expect(run.timer.armedCount == 0)
    }

    /// T211, A14 : un refus de taille est confirmé par la passe d'échéance armée 100 ms après
    /// l'écriture, puis corrigé une fois.
    @MainActor
    @Test
    func schedulerConfirmsRefusalAtItsDeadline() {
        let world = TreeWorld(frames: [treeW1: Rect(x: 50, y: 50, width: 300, height: 200), treeW2: Rect(x: 600, y: 50, width: 300, height: 200)])
        world.minimumSizes[treeW1] = CGSize(width: 700, height: 0)
        let harness = TreeHarness("tree-sched-refusal", world: world, store: treeStore("tree-sched-refusal", tree: treeSideBySide, frames: world.frames))
        let run = TreeSchedulerRun(harness)

        let start = harness.clock.now
        run.scheduler.request(cause: "command:startup")
        run.timer.advance(by: 2)

        let confirmAt = start.addingTimeInterval(0.015 + LayoutTolerance.refusalConfirmDelay)
        #expect(run.passes.contains { $0.cause == "deadline" && abs($0.at.timeIntervalSince(confirmAt)) < 0.001 })
        #expect(harness.events.contains("\"source\":\"tree_minimum_size\""))
        #expect(world.writes[treeW1]?.count == 1)
        #expect(world.writes[treeW2]?.count == 2)
        #expect((world.frames[treeW2]?.x ?? 0) >= 700)
        #expect(run.timer.armedCount == 0)
    }

    /// T224 : pendant la grâce de fin de glisser d'un scope sans arbre (`bsp`), la passe s'arrête
    /// avant ses échéances. L'échéance rendue est la fin de la grâce : au plus une passe pendant
    /// la grâce, une à sa fin, qui solde la stabilité.
    @MainActor
    @Test
    func dragReleaseGraceDefersDeadlinesToItsEnd() {
        let world = TreeWorld(frames: [treeW1: Rect(x: 50, y: 50, width: 300, height: 200), treeW2: Rect(x: 600, y: 50, width: 300, height: 200)])
        let drag = WindowDragActivity(path: tempPath("tree-sched-drag-grace"))
        defer { drag.reset() }
        let store = treeStore("tree-sched-drag-grace", tree: treeSideBySide, frames: world.frames, mode: .bsp)
        let harness = TreeHarness("tree-sched-drag-grace", world: world, store: store, strategy: .bsp, dragActivity: drag)
        let run = TreeSchedulerRun(harness)

        run.scheduler.request(cause: "command:startup")
        run.timer.advance(by: 0.015)
        let placed = run.passes.count
        // Le glisser finit juste après la passe, qui a armé la lecture de stabilité à 100 ms.
        drag.finish(now: harness.clock.now)
        let graceEnd = harness.clock.now.addingTimeInterval(0.9)
        run.timer.advance(by: 2)

        let during = run.passes.dropFirst(placed).filter { $0.at <= graceEnd }
        let after = run.passes.filter { $0.at > graceEnd }
        #expect(placed == 1)
        #expect(world.totalWrites >= 1)
        #expect(during.count <= 1)
        #expect(after.count == 1)
        #expect(after.first.map { $0.at.timeIntervalSince(graceEnd) < 0.001 } == true)
        #expect(harness.count("layout_stable") == 1)
        #expect(run.timer.armedCount == 0)
    }

    /// T224 : accessibilité refusée, la passe s'arrête avant ses échéances ; aucune passe
    /// d'échéance n'est relancée.
    @MainActor
    @Test
    func accessibilityDeniedArmsNoDeadline() {
        let world = TreeWorld(frames: [treeW1: Rect(x: 50, y: 50, width: 300, height: 200), treeW2: Rect(x: 600, y: 50, width: 300, height: 200)])
        let harness = TreeHarness("tree-sched-ax-denied", world: world, store: treeStore("tree-sched-ax-denied", tree: treeSideBySide, frames: world.frames))
        let run = TreeSchedulerRun(harness)

        run.scheduler.request(cause: "command:startup")
        run.timer.advance(by: 0.015)
        // La passe a écrit : stabilité armée à 100 ms. Une passe d'événement voit ensuite
        // l'accessibilité refusée, avant cette échéance.
        world.accessibilityTrusted = false
        run.scheduler.request(cause: "ax:AXFocusedWindowChanged")
        run.timer.advance(by: 2)

        #expect(world.totalWrites >= 1)
        #expect(run.passes.map(\.cause) == ["command:startup", "ax:AXFocusedWindowChanged"])
        #expect(harness.maintainer.nextDeadline(now: harness.clock.now) == nil)
        #expect(run.timer.armedCount == 0)
    }
}

/// Ordonnanceur réel branché sur le maintainer d'un harnais, avec une minuterie manuelle qui
/// avance l'horloge du harnais (T211).
@MainActor
private final class TreeSchedulerRun {
    let timer: TreeTimer
    private(set) var passes: [(cause: String, at: Date)] = []
    private(set) var scheduler: TickScheduler!

    init(_ harness: TreeHarness) {
        let timer = TreeTimer(clock: harness.clock)
        self.timer = timer
        scheduler = TickScheduler(
            tick: { [unowned self] cause in
                passes.append((cause, harness.clock.now))
                return harness.maintainer.tick(cause: cause)
            },
            nextDeadline: { harness.maintainer.nextDeadline(now: $0) },
            isBlocked: { false },
            now: { harness.clock.now },
            schedule: { timer.schedule($0, $1) },
            episodes: harness.episodes,
            events: nil
        )
    }
}

/// Minuterie manuelle : les actions partent quand l'horloge avance au-delà de leur échéance.
@MainActor
private final class TreeTimer {
    let clock: TestClock
    private var items: [(id: Int, due: Date, action: @MainActor () -> Void)] = []
    private var nextID = 0

    init(clock: TestClock) { self.clock = clock }

    var armedCount: Int { items.count }

    func schedule(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> () -> Void {
        let id = nextID
        nextID += 1
        items.append((id, clock.now.addingTimeInterval(delay), action))
        return { [weak self] in self?.items.removeAll { $0.id == id } }
    }

    func advance(by seconds: TimeInterval) {
        let target = clock.now.addingTimeInterval(seconds)
        while let next = items.filter({ $0.due <= target }).min(by: { $0.due < $1.due }) {
            items.removeAll { $0.id == next.id }
            clock.now = max(clock.now, next.due)
            next.action()
        }
        clock.now = target
    }
}

private final class ProbeBox: @unchecked Sendable {
    var value: Bool?
    init(_ value: Bool?) { self.value = value }
}


@Suite
struct NavrailMaximizationRefusalTests {
    @Test
    func minimumWidthOverlappingRailDoesNotHideSiblingsOrPersistZoom() throws {
        let left = powerWindow(261, x: 150, y: 0, width: 350, height: 800)
        let sibling = powerWindow(262, x: 510, y: 0, width: 490, height: 800)
        let provider = PowerUserProvider(windows: [left, sibling])
        let writer = AlwaysClampedWriter(actual: Rect(x: 150, y: 0, width: 1000, height: 800))
        let store = StageStore(path: tempPath("spec019-refusal"))
        let service = SnapshotService(provider: provider, frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0)), railSettings: .load(raw: ""), stageStore: store)
        let scope = try #require(service.snapshot().windows.first?.scope)
        let result = WindowCommandService(service: service, stageStore: store).toggleMaximize()
        #expect(!result.changed)
        #expect(service.effectiveIntentStore.intent(for: scope)?.zoomedWindowID == nil)
        #expect(provider.snapshots.first(where: { $0.id == sibling.id })?.frame == sibling.frame)
        #expect(writer.attempts <= 2)
    }
}
