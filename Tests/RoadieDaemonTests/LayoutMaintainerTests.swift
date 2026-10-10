import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon
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

        #expect(tick.commands == 1)
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

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        attempts += 1
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
    func activeLayoutCommandSuppressesMutableGeometryAdoption() {
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
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .mutableBsp, gapsOuter: 0, gapsInner: 10))
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

    @Test
    func mutableBspExternalResizeIsAdoptedAsLayoutConstraint() {
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
        let intentPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-mutable-resize-intent-\(UUID().uuidString).json")
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
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .mutableBsp, gapsOuter: 0, gapsInner: 10)),
            intentStore: intentStore
        )
        var currentTime = Date(timeIntervalSince1970: 0)
        let maintainer = LayoutMaintainer(service: service, now: { currentTime })

        let initial = maintainer.tick()
        let resizing = maintainer.tick()
        currentTime = currentTime.addingTimeInterval(2)
        let settled = maintainer.tick()

        #expect(initial.commands == 0)
        #expect(resizing.manualResizeDetected)
        #expect(resizing.commands == 0)
        #expect(settled.commands == 0)
        #expect(writer.requestedFrames.isEmpty)
        #expect(intentStore.intent(for: scope)?.placements[WindowID(rawValue: 1)] == Rect(x: 0, y: 0, width: 700, height: 500))
        #expect(intentStore.intent(for: scope)?.placements[WindowID(rawValue: 2)] == Rect(x: 710, y: 0, width: 290, height: 500))
        try? FileManager.default.removeItem(atPath: intentPath)
    }

    @Test
    func mutableBspExternalResizePropagatesToNeighborWithoutSnapback() {
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
                Rect(x: 710, y: 0, width: 290, height: 500),
            ],
        ])
        let writer = RecordingWriter()
        let intentPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-mutable-resize-neighbor-intent-\(UUID().uuidString).json")
            .path
        let eventPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-mutable-resize-neighbor-events-\(UUID().uuidString).jsonl")
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
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .mutableBsp, gapsOuter: 0, gapsInner: 10)),
            intentStore: intentStore
        )
        var currentTime = Date(timeIntervalSince1970: 0)
        let maintainer = LayoutMaintainer(service: service, events: EventLog(path: eventPath), now: { currentTime })

        let initial = maintainer.tick()
        let resizing = maintainer.tick()
        currentTime = currentTime.addingTimeInterval(2)
        let settled = maintainer.tick()

        #expect(initial.commands == 0)
        #expect(resizing.manualResizeDetected)
        #expect(resizing.commands == 1)
        #expect(settled.commands == 0)
        #expect(writer.requestedFrames[WindowID(rawValue: 1)] == nil)
        #expect(writer.requestedFrames[WindowID(rawValue: 2)] == Rect(x: 710, y: 0, width: 290, height: 500))
        #expect(intentStore.intent(for: scope)?.placements[WindowID(rawValue: 1)] == Rect(x: 0, y: 0, width: 700, height: 500))
        #expect(intentStore.intent(for: scope)?.placements[WindowID(rawValue: 2)] == Rect(x: 710, y: 0, width: 290, height: 500))
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        #expect(events.contains("\"type\":\"mutable_bsp_resize_propagated\""))
        try? FileManager.default.removeItem(atPath: intentPath)
        try? FileManager.default.removeItem(atPath: eventPath)
    }

    @Test
    func mutableBspHorizontalResizePreservesNestedVerticalSplit() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let store = StageStore(path: tempPath("mutable-bsp-horizontal-resize-axis"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: display.id, activeStageID: scope.stageID, stages: [
                    PersistentStage(id: scope.stageID, mode: .mutableBsp, members: [
                        PersistentStageMember(windowID: WindowID(rawValue: 1), bundleID: "app.1", title: "Window1", frame: Rect(x: 0, y: 0, width: 495, height: 500)),
                        PersistentStageMember(windowID: WindowID(rawValue: 2), bundleID: "app.2", title: "Window2", frame: Rect(x: 505, y: 0, width: 495, height: 245)),
                        PersistentStageMember(windowID: WindowID(rawValue: 3), bundleID: "app.3", title: "Window3", frame: Rect(x: 505, y: 255, width: 495, height: 245)),
                    ])
                ])
            ],
            activeDisplayID: display.id
        ))
        let provider = SequenceProvider(display: display, windowFrames: [
            [
                Rect(x: 0, y: 0, width: 495, height: 500),
                Rect(x: 505, y: 0, width: 495, height: 245),
                Rect(x: 505, y: 255, width: 495, height: 245),
            ],
            [
                Rect(x: 0, y: 0, width: 495, height: 500),
                Rect(x: 650, y: 0, width: 350, height: 245),
                Rect(x: 505, y: 255, width: 495, height: 245),
            ],
            [
                Rect(x: 0, y: 0, width: 640, height: 500),
                Rect(x: 650, y: 0, width: 350, height: 245),
                Rect(x: 650, y: 255, width: 350, height: 245),
            ],
        ])
        let writer = RecordingWriter()
        let intentStore = LayoutIntentStore(path: tempPath("mutable-bsp-horizontal-resize-axis-intent"))
        let eventPath = tempPath("mutable-bsp-horizontal-resize-axis-events")
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .mutableBsp, gapsOuter: 0, gapsInner: 10)),
            intentStore: intentStore,
            stageStore: store
        )
        let maintainer = LayoutMaintainer(service: service, events: EventLog(path: eventPath), store: store)

        let initial = maintainer.tick()
        let resized = maintainer.tick()
        let settled = maintainer.tick()

        let stage = store.state().scopes[0].stages[0]
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        #expect(initial.commands == 0)
        #expect(resized.manualResizeDetected)
        #expect(resized.commands == 2)
        #expect(settled.commands == 0)
        #expect(stage.members.map(\.windowID) == [WindowID(rawValue: 1), WindowID(rawValue: 2), WindowID(rawValue: 3)])
        #expect(writer.requestedFrames[WindowID(rawValue: 1)] == Rect(x: 0, y: 0, width: 640, height: 500))
        #expect(writer.requestedFrames[WindowID(rawValue: 2)] == nil)
        #expect(writer.requestedFrames[WindowID(rawValue: 3)] == Rect(x: 650, y: 255, width: 350, height: 245))
        #expect(intentStore.intent(for: scope)?.placements[WindowID(rawValue: 3)]?.height == 245)
        #expect(events.contains("\"resizeAxes\":\"2:horizontal\""))
    }

    @Test
    func tiledScopeMembershipChurnSettlesBeforeRelayout() {
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
        let provider = MultiDisplaySequenceProvider(displaySnapshots: [display], windowSnapshots: [
            [first, second],
            [firstDuringChurn],
            [firstDuringChurn],
        ])
        let writer = RecordingWriter()
        let eventPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-membership-settle-events-\(UUID().uuidString).jsonl")
            .path
        let service = SnapshotService(
            provider: provider,
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

        let initial = maintainer.tick()
        let settling = maintainer.tick()
        currentTime = currentTime.addingTimeInterval(3)
        let settled = maintainer.tick()

        #expect(initial.commands == 0)
        #expect(settling.commands == 0)
        #expect(settled.commands == 1)
        #expect(writer.requestedFrames[first.id] == Rect(x: 0, y: 0, width: 1000, height: 500))
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        #expect(events.contains("\"type\":\"layout_stage_membership_settling\""))
        try? FileManager.default.removeItem(atPath: eventPath)
    }

    @Test
    func focusedStageRestoreWaitsForRecentMissingMemberToSettle() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let focusedVisible = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 10,
            appName: "A",
            bundleID: "a",
            title: "focused",
            frame: Rect(x: 0, y: 0, width: 495, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        let sibling = WindowSnapshot(
            id: WindowID(rawValue: 2),
            pid: 11,
            appName: "B",
            bundleID: "b",
            title: "sibling",
            frame: Rect(x: 505, y: 0, width: 495, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        var focusedHidden = focusedVisible
        focusedHidden.frame = Rect(x: 999, y: 499, width: 495, height: 500)
        let stagePath = tempPath("focused-restore-membership-settling")
        let eventPath = tempPath("focused-restore-membership-settling-events")
        defer {
            try? FileManager.default.removeItem(atPath: stagePath)
            try? FileManager.default.removeItem(atPath: eventPath)
        }
        let stageStore = StageStore(path: stagePath)
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: MultiDisplaySequenceProvider(
                displaySnapshots: [display],
                windowSnapshots: [[focusedVisible, sibling], [focusedHidden]],
                focusedID: focusedVisible.id
            ),
            frameWriter: writer,
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
        currentTime = currentTime.addingTimeInterval(0.1)
        let settling = maintainer.tick()

        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        #expect(settling.commands == 0)
        #expect(writer.requestedFrames.isEmpty)
        #expect(events.contains("\"type\":\"layout_stage_membership_settling\""))
        #expect(!events.contains("\"type\":\"stage_focus_restore\""))
    }

    @Test
    func mutableBspDoesNotAdoptGeometryDuringMembershipChurn() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let firstInitial = WindowSnapshot(
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
            id: firstInitial.id,
            pid: firstInitial.pid,
            appName: firstInitial.appName,
            bundleID: firstInitial.bundleID,
            title: firstInitial.title,
            frame: Rect(x: 0, y: 0, width: 700, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let intentPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-mutable-churn-intent-\(UUID().uuidString).json")
            .path
        let eventPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-mutable-churn-events-\(UUID().uuidString).jsonl")
            .path
        let intentStore = LayoutIntentStore(path: intentPath)
        intentStore.save(LayoutIntent(
            scope: scope,
            windowIDs: [firstInitial.id, second.id],
            placements: [
                firstInitial.id: firstInitial.frame,
                second.id: second.frame,
            ]
        ))
        let provider = MultiDisplaySequenceProvider(displaySnapshots: [display], windowSnapshots: [
            [firstInitial, second],
            [firstDuringChurn],
        ])
        let service = SnapshotService(
            provider: provider,
            frameWriter: RecordingWriter(),
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .mutableBsp, gapsOuter: 0, gapsInner: 10)),
            intentStore: intentStore
        )
        let currentTime = Date()
        let maintainer = LayoutMaintainer(
            service: service,
            events: EventLog(path: eventPath),
            intervalSeconds: 0.1,
            now: { currentTime }
        )

        _ = maintainer.tick()
        let settling = maintainer.tick()

        #expect(settling.commands == 0)
        #expect(intentStore.intent(for: scope)?.windowIDs == [firstInitial.id, second.id])
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        #expect(events.contains("\"type\":\"layout_stage_membership_settling\""))
        #expect(!events.contains("\"type\":\"mutable_bsp_geometry_adopted\""))
        try? FileManager.default.removeItem(atPath: intentPath)
        try? FileManager.default.removeItem(atPath: eventPath)
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
    func mutableBspStableVisibleScopeIsNotAutomaticallyRelayouted() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let userLeft = Rect(x: 0, y: 0, width: 700, height: 500)
        let userRight = Rect(x: 710, y: 0, width: 290, height: 500)
        let provider = SequenceProvider(display: display, windowFrames: [
            [userLeft, userRight],
            [userLeft, userRight],
        ])
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .mutableBsp, gapsOuter: 0, gapsInner: 10))
        )
        let maintainer = LayoutMaintainer(service: service)

        let first = maintainer.tick()
        let second = maintainer.tick()

        #expect(first.commands == 0)
        #expect(second.commands == 0)
        #expect(writer.requestedFrames.isEmpty)
    }

    @Test
    func mutableBspStableSuppressionDoesNotSpamEvents() throws {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let left = Rect(x: 0, y: 0, width: 600, height: 500)
        let right = Rect(x: 700, y: 0, width: 300, height: 500)
        let eventPath = tempPath("mutable-bsp-stable-suppression-events")
        let provider = SequenceProvider(display: display, windowFrames: [
            [left, right],
            [left, right],
        ])
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .mutableBsp, gapsOuter: 0, gapsInner: 10))
        )
        let maintainer = LayoutMaintainer(service: service, events: EventLog(path: eventPath))

        let first = maintainer.tick()
        let second = maintainer.tick()

        #expect(first.commands == 0)
        #expect(second.commands == 0)
        #expect(writer.requestedFrames.isEmpty)
        let events = try String(contentsOfFile: eventPath, encoding: .utf8)
        #expect(events.components(separatedBy: "\"type\":\"mutable_bsp_auto_relayout_suppressed\"").count - 1 == 1)
        try? FileManager.default.removeItem(atPath: eventPath)
    }

    @Test
    func mutableBspOverlappingVisibleFramesAreRelayouted() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1200, height: 600),
            visibleFrame: Rect(x: 0, y: 0, width: 1200, height: 600),
            isMain: true
        )
        let wide = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 11,
            appName: "Wide",
            bundleID: "app.wide",
            title: "Wide",
            frame: Rect(x: 0, y: 0, width: 900, height: 600),
            isOnScreen: true,
            isTileCandidate: true
        )
        let overlapping = WindowSnapshot(
            id: WindowID(rawValue: 2),
            pid: 12,
            appName: "Overlap",
            bundleID: "app.overlap",
            title: "Overlap",
            frame: Rect(x: 600, y: 0, width: 300, height: 600),
            isOnScreen: true,
            isTileCandidate: true
        )
        let right = WindowSnapshot(
            id: WindowID(rawValue: 3),
            pid: 13,
            appName: "Right",
            bundleID: "app.right",
            title: "Right",
            frame: Rect(x: 910, y: 0, width: 290, height: 600),
            isOnScreen: true,
            isTileCandidate: true
        )
        let stageID = StageID(rawValue: "1")
        let store = StageStore(path: tempPath("mutable-bsp-overlap-relayout"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: display.id, activeStageID: stageID, stages: [
                    PersistentStage(id: stageID, mode: .mutableBsp, members: [
                        PersistentStageMember(windowID: wide.id, bundleID: wide.bundleID, title: wide.title, frame: wide.frame),
                        PersistentStageMember(windowID: overlapping.id, bundleID: overlapping.bundleID, title: overlapping.title, frame: overlapping.frame),
                        PersistentStageMember(windowID: right.id, bundleID: right.bundleID, title: right.title, frame: right.frame),
                    ])
                ])
            ],
            activeDisplayID: display.id
        ))
        let provider = MultiDisplaySequenceProvider(displaySnapshots: [display], windowSnapshots: [[wide, overlapping, right]])
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .mutableBsp, gapsOuter: 0, gapsInner: 10)),
            stageStore: store
        )
        let maintainer = LayoutMaintainer(service: service, store: store)

        let tick = maintainer.tick()

        #expect(tick.commands > 0)
        #expect(writer.requestedFrames[overlapping.id] != nil)
    }

    @Test
    func mutableBspRelayoutsLiveWindowsWhenStageMemberDisappears() {
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
        let closed = WindowID(rawValue: 2)
        let store = StageStore(path: tempPath("mutable-bsp-closed-member"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: display.id, stages: [
                    PersistentStage(id: StageID(rawValue: "1"), mode: .mutableBsp, members: [
                        PersistentStageMember(windowID: live.id, bundleID: live.bundleID, title: live.title, frame: live.frame),
                        PersistentStageMember(windowID: closed, bundleID: "app.closed", title: "Closed", frame: Rect(x: 505, y: 0, width: 495, height: 500)),
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
        let maintainer = LayoutMaintainer(service: service, store: store)

        let tick = maintainer.tick()

        #expect(tick.commands == 1)
        #expect(writer.requestedFrames[live.id] == Rect(x: 0, y: 0, width: 1000, height: 500))
        #expect(store.state().scopes.first?.memberIDs(in: StageID(rawValue: "1")) == [live.id, closed])
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
    func mutableBspNewWindowStillReceivesAutomaticLayout() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let left = Rect(x: 0, y: 0, width: 495, height: 500)
        let right = Rect(x: 505, y: 0, width: 495, height: 500)
        let newWindow = Rect(x: 300, y: 80, width: 300, height: 200)
        let provider = SequenceProvider(display: display, windowFrames: [
            [left, right],
            [left, right, newWindow],
        ])
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .mutableBsp, gapsOuter: 0, gapsInner: 10))
        )
        let maintainer = LayoutMaintainer(service: service)

        _ = maintainer.tick()
        let withNewWindow = maintainer.tick()

        #expect(withNewWindow.commands > 0)
        #expect(writer.requestedFrames[WindowID(rawValue: 3)] != nil)
    }

    @Test
    func mutableBspMultiWindowResizeAdoptsCurrentGeometryAndRepairsOrder() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let store = StageStore(path: tempPath("mutable-bsp-order-repair"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: display.id, stages: [
                    PersistentStage(id: StageID(rawValue: "1"), mode: .mutableBsp, members: [
                        PersistentStageMember(windowID: WindowID(rawValue: 1), bundleID: "app.1", title: "Window1", frame: Rect(x: 0, y: 0, width: 490, height: 500)),
                        PersistentStageMember(windowID: WindowID(rawValue: 2), bundleID: "app.2", title: "Window2", frame: Rect(x: 490, y: 251, width: 510, height: 249)),
                        PersistentStageMember(windowID: WindowID(rawValue: 3), bundleID: "app.3", title: "Window3", frame: Rect(x: 490, y: 0, width: 510, height: 250)),
                    ])
                ])
            ],
            activeDisplayID: display.id
        ))
        let provider = SequenceProvider(display: display, windowFrames: [
            [
                Rect(x: 0, y: 0, width: 490, height: 500),
                Rect(x: 490, y: 251, width: 510, height: 249),
                Rect(x: 490, y: 0, width: 510, height: 250),
            ],
            [
                Rect(x: 0, y: 0, width: 490, height: 500),
                Rect(x: 490, y: 301, width: 510, height: 199),
                Rect(x: 490, y: 0, width: 510, height: 300),
            ],
            [
                Rect(x: 0, y: 0, width: 490, height: 500),
                Rect(x: 490, y: 301, width: 510, height: 199),
                Rect(x: 490, y: 0, width: 510, height: 300),
            ],
        ])
        let writer = RecordingWriter()
        let intentStore = LayoutIntentStore(path: tempPath("mutable-bsp-order-intent"))
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .mutableBsp, gapsOuter: 0, gapsInner: 0)),
            intentStore: intentStore,
            stageStore: store
        )
        let maintainer = LayoutMaintainer(service: service, store: store)

        let initial = maintainer.tick()
        let resized = maintainer.tick()

        let stage = store.state().scopes[0].stages[0]
        #expect(initial.commands == 0)
        #expect(resized.manualResizeDetected)
        #expect(resized.commands == 0)
        #expect(stage.members.map(\.windowID) == [WindowID(rawValue: 1), WindowID(rawValue: 3), WindowID(rawValue: 2)])
        #expect(intentStore.intent(for: scope)?.windowIDs == [WindowID(rawValue: 1), WindowID(rawValue: 3), WindowID(rawValue: 2)])
        #expect(writer.requestedFrames.isEmpty)
    }

    @Test
    func mutableBspAdoptionIgnoresChangedWindowsOutsideActiveScope() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let activeScope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let store = StageStore(path: tempPath("mutable-bsp-cross-scope-adopt"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), mode: .mutableBsp, members: [
                        PersistentStageMember(windowID: WindowID(rawValue: 1), bundleID: "app.1", title: "Window1", frame: Rect(x: 0, y: 0, width: 495, height: 500)),
                        PersistentStageMember(windowID: WindowID(rawValue: 2), bundleID: "app.2", title: "Window2", frame: Rect(x: 505, y: 0, width: 495, height: 500)),
                    ])
                ]),
                PersistentStageScope(displayID: display.id, desktopID: DesktopID(rawValue: 2), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), mode: .mutableBsp, members: [
                        PersistentStageMember(windowID: WindowID(rawValue: 3), bundleID: "app.3", title: "Window3", frame: Rect(x: 999, y: 499, width: 300, height: 200)),
                    ])
                ]),
            ],
            desktopSelections: [
                PersistentDesktopSelection(displayID: display.id, currentDesktopID: DesktopID(rawValue: 1))
            ],
            activeDisplayID: display.id
        ))
        let provider = SequenceProvider(display: display, windowFrames: [
            [
                Rect(x: 0, y: 0, width: 495, height: 500),
                Rect(x: 505, y: 0, width: 495, height: 500),
                Rect(x: 999, y: 499, width: 300, height: 200),
            ],
            [
                Rect(x: 0, y: 0, width: 650, height: 500),
                Rect(x: 505, y: 0, width: 495, height: 500),
                Rect(x: 999, y: 450, width: 300, height: 200),
            ],
        ])
        let writer = RecordingWriter()
        let intentStore = LayoutIntentStore(path: tempPath("mutable-bsp-cross-scope-intent"))
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .mutableBsp, gapsOuter: 0, gapsInner: 10)),
            intentStore: intentStore,
            stageStore: store
        )
        let maintainer = LayoutMaintainer(service: service, store: store)

        _ = maintainer.tick()
        let resized = maintainer.tick()

        #expect(resized.manualResizeDetected)
        #expect(writer.requestedFrames[WindowID(rawValue: 2)] != nil)
        #expect(intentStore.intent(for: activeScope)?.placements[WindowID(rawValue: 3)] == nil)
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
            source: .command
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
            source: .command
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

        #expect(tick.commands == 1)
        #expect(writer.requestedFrames[WindowID(rawValue: 1)] == Rect(x: 1040, y: -460, width: 1100, height: 720))
        #expect(writer.requestedFrames[WindowID(rawValue: 2)] == nil)
        #expect(events.contains("\"type\":\"fullscreen_sized_windows_reanchored\""))
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
            source: .command
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
            source: .command
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

        #expect(tick.commands == 2)
        #expect(tick.clamped == 1)
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

    @Test
    func mutuallyClampedOversizedWindowsIsolateLargestWindowInsteadOfThrashing() {
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
        let eventPath = tempPath("mutually-clamped-oversized-isolate-events")
        defer { try? FileManager.default.removeItem(atPath: eventPath) }
        let service = SnapshotService(
            provider: SequenceProvider(display: display, windowFrames: [
                [finderInitial, firefoxInitial],
            ]),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .bsp, gapsOuter: 0, gapsInner: 10))
        )
        let maintainer = LayoutMaintainer(service: service, events: EventLog(path: eventPath))

        let tick = maintainer.tick()
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""

        #expect(tick.clamped == 2)
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
        let maintainer = LayoutMaintainer(service: service, events: EventLog(path: eventPath), store: store)

        let tick = maintainer.tick()
        var state = store.state()
        let events = try String(contentsOfFile: eventPath, encoding: .utf8)

        #expect(tick.failed > 0)
        #expect(state.scope(displayID: leftDisplay.id).memberIDs(in: StageID(rawValue: "1")) == [window.id])
        #expect(state.scope(displayID: rightDisplay.id).memberIDs(in: StageID(rawValue: "1")).isEmpty)
        #expect(events.contains("\"type\":\"window.scope_reconcile_failed\""))
        #expect(!events.contains("\"type\":\"window.scope_reconciled_to_physical_display\""))
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
            isTileCandidate: true
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
    func focusedStageRestoreOnlyHidesInactiveWindowsOnSameDisplay() {
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

        #expect(tick.commands == 1)
        #expect(writer.requestedFrames[focusedHidden.id] != nil)
        #expect(writer.requestedFrames[inactiveRight.id] == nil)
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
            source: .command
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
    func mutableBspUnmatchedCommandIntentIsRetriedBeforeStableSuppression() {
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
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .mutableBsp, gapsOuter: 0, gapsInner: 10)),
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
    func mutableBspCommandIntentCanKeepSmallPaneAfterFreshnessWindow() {
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
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .mutableBsp, gapsOuter: 0, gapsInner: 10)),
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
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .mutableBsp, gapsOuter: 0, gapsInner: 10)),
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
