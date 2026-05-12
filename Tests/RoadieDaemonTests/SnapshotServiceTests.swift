import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon
import RoadieStages

private struct FakeProvider: SystemSnapshotProviding {
    var permissionSnapshot = PermissionSnapshot(accessibilityTrusted: true)
    var displaySnapshots: [DisplaySnapshot]
    var windowSnapshots: [WindowSnapshot]
    var focusedID: WindowID?
    var mousePoint: CGPoint?

    func permissions(prompt: Bool) -> PermissionSnapshot { permissionSnapshot }
    func displays() -> [DisplaySnapshot] { displaySnapshots }
    func windows() -> [WindowSnapshot] { windowSnapshots }
    func focusedWindowID() -> WindowID? { focusedID }
    func mouseLocation() -> CGPoint? { mousePoint }
}

@Suite
struct WindowPinSnapshotTests {
    @Test
    func desktopPinKeepsHomeScopeButLeavesActiveLayout() {
        let display = powerDisplay("display-main", index: 1, x: 0)
        let pinned = powerWindow(10, x: 100)
        let active = powerWindow(20, x: 500)
        let home = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let store = StageStore(path: tempPath("window-pin-desktop-snapshot"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: display.id, activeStageID: StageID(rawValue: "2"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), members: [
                        PersistentStageMember(windowID: pinned.id, bundleID: pinned.bundleID, title: pinned.title, frame: pinned.frame)
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
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [display], windowSnapshots: [pinned, active]),
            frameWriter: RecordingWriter(),
            stageStore: store
        )

        let snapshot = service.snapshot(followFocus: false)

        #expect(snapshot.windows.first { $0.window.id == pinned.id }?.scope == home)
        #expect(snapshot.windows.first { $0.window.id == pinned.id }?.pin?.pinScope == .desktop)
        #expect(snapshot.state.stage(scope: home)?.windowIDs.isEmpty == true)
        #expect(snapshot.state.stage(scope: StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "2")))?.windowIDs == [active.id])
        #expect(service.applyPlan(from: snapshot).commands.map(\.window.id) == [active.id])
    }

    @Test
    func pinVisibilityIsLimitedByScope() {
        let home = StageScope(displayID: DisplayID(rawValue: "main"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let sameDesktop = StageScope(displayID: home.displayID, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "2"))
        let otherDesktop = StageScope(displayID: home.displayID, desktopID: DesktopID(rawValue: 2), stageID: StageID(rawValue: "1"))
        let otherDisplay = StageScope(displayID: DisplayID(rawValue: "side"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let desktopPin = PersistentWindowPin(
            windowID: WindowID(rawValue: 10),
            homeScope: home,
            pinScope: .desktop,
            bundleID: "app",
            title: "Doc",
            lastFrame: Rect(x: 0, y: 0, width: 100, height: 100)
        )
        let allDesktopsPin = PersistentWindowPin(
            windowID: WindowID(rawValue: 10),
            homeScope: home,
            pinScope: .allDesktops,
            bundleID: "app",
            title: "Doc",
            lastFrame: Rect(x: 0, y: 0, width: 100, height: 100)
        )

        #expect(desktopPin.visibility(in: sameDesktop).shouldBeVisible)
        #expect(desktopPin.visibility(in: otherDesktop).shouldBeVisible == false)
        #expect(allDesktopsPin.visibility(in: otherDesktop).shouldBeVisible)
        #expect(allDesktopsPin.visibility(in: otherDisplay).shouldBeVisible == false)
    }

    @Test
    func snapshotPrunesMissingWindowPinsAndLogsEvent() {
        let display = powerDisplay("display-main", index: 1, x: 0)
        let home = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let store = StageStore(path: tempPath("window-pin-prune-snapshot"))
        let eventPath = tempPath("window-pin-prune-events")
        store.save(PersistentStageState(
            scopes: [PersistentStageScope(displayID: display.id)],
            windowPins: [
                PersistentWindowPin(
                    windowID: WindowID(rawValue: 999),
                    homeScope: home,
                    pinScope: .desktop,
                    bundleID: "app.missing",
                    title: "Missing",
                    lastFrame: Rect(x: 0, y: 0, width: 100, height: 100)
                )
            ],
            activeDisplayID: display.id
        ))
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [display], windowSnapshots: []),
            frameWriter: RecordingWriter(),
            stageStore: store,
            events: EventLog(path: eventPath)
        )

        _ = service.snapshot(followFocus: false)

        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        #expect(store.state().windowPins.isEmpty)
        #expect(events.contains("window.pin_pruned"))
    }
}

private final class SequenceSnapshotProvider: SystemSnapshotProviding, @unchecked Sendable {
    var permissionSnapshot = PermissionSnapshot(accessibilityTrusted: true)
    let displaySnapshots: [DisplaySnapshot]
    let windowSnapshots: [[WindowSnapshot]]
    let focusedID: WindowID?
    private var index = 0

    init(displaySnapshots: [DisplaySnapshot], windowSnapshots: [[WindowSnapshot]], focusedID: WindowID? = nil) {
        self.displaySnapshots = displaySnapshots
        self.windowSnapshots = windowSnapshots
        self.focusedID = focusedID
    }

    func permissions(prompt: Bool) -> PermissionSnapshot { permissionSnapshot }
    func displays() -> [DisplaySnapshot] { displaySnapshots }
    func windows() -> [WindowSnapshot] {
        let windows = windowSnapshots[Swift.min(index, windowSnapshots.count - 1)]
        index += 1
        return windows
    }
    func focusedWindowID() -> WindowID? { focusedID }
}

private struct FakeWriter: WindowFrameWriting {
    var actualFrames: [WindowID: Rect]

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        actualFrames[window.id]?.cgRect
    }
}

private final class RecordingWriter: WindowFrameWriting, @unchecked Sendable {
    private(set) var requestedFrames: [WindowID: Rect] = [:]
    private(set) var focusedWindowIDs: [WindowID] = []

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        requestedFrames[window.id] = Rect(frame)
        return frame
    }

    func focus(_ window: WindowSnapshot) -> Bool {
        focusedWindowIDs.append(window.id)
        return true
    }
}

private final class DeterministicWriter: WindowFrameWriting, @unchecked Sendable {
    private let actualFrames: [WindowID: Rect]
    private(set) var requestedFrames: [WindowID: Rect] = [:]

    init(actualFrames: [WindowID: Rect]) {
        self.actualFrames = actualFrames
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        requestedFrames[window.id] = Rect(frame)
        return actualFrames[window.id]?.cgRect
    }

    func focus(_ window: WindowSnapshot) -> Bool { true }
}

private final class PartialFailureWriter: WindowFrameWriting, @unchecked Sendable {
    private let actualFrames: [WindowID: Rect?]

    init(actualFrames: [WindowID: Rect?]) {
        self.actualFrames = actualFrames
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        guard let maybeActual = actualFrames[window.id] else { return nil }
        return maybeActual?.cgRect
    }

    func focus(_ window: WindowSnapshot) -> Bool { true }
}

@Suite
struct SnapshotServiceTests {
    @Test
    func tileCandidatesAreAssignedToDefaultStageOnContainingDisplay() {
        let displayA = DisplayID(rawValue: "display-a")
        let displayB = DisplayID(rawValue: "display-b")
        let stageStore = StageStore(path: tempPath("snapshot-default-stage-containing-display"))
        let window = WindowSnapshot(
            id: WindowID(rawValue: 100),
            pid: 123,
            appName: "App",
            bundleID: "com.example.app",
            title: "Document",
            frame: Rect(x: 1200, y: 100, width: 400, height: 300),
            isOnScreen: true,
            isTileCandidate: true
        )
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: displayA, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 800), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 800), isMain: true),
                    DisplaySnapshot(id: displayB, index: 2, name: "B", frame: Rect(x: 1000, y: 0, width: 1000, height: 800), visibleFrame: Rect(x: 1000, y: 0, width: 1000, height: 800), isMain: false),
                ],
                windowSnapshots: [window]
            ),
            config: RoadieConfig(),
            stageStore: stageStore
        )

        let snapshot = service.snapshot()

        #expect(snapshot.windows.first?.scope?.displayID == displayB)
        #expect(snapshot.windows.first?.scope?.desktopID == DesktopID(rawValue: 1))
        #expect(snapshot.windows.first?.scope?.stageID == StageID(rawValue: "1"))
        #expect(snapshot.state.stage(scope: snapshot.windows.first!.scope!)?.windowIDs == [window.id])
    }

    @Test
    func newTileCandidatesCanFollowMouseDisplay() {
        let displayA = DisplayID(rawValue: "display-a")
        let displayB = DisplayID(rawValue: "display-b")
        let stageStore = StageStore(path: tempPath("snapshot-new-window-mouse-display"))
        let window = WindowSnapshot(
            id: WindowID(rawValue: 101),
            pid: 123,
            appName: "App",
            bundleID: "com.example.app",
            title: "Document",
            frame: Rect(x: 1200, y: 100, width: 400, height: 300),
            isOnScreen: true,
            isTileCandidate: true
        )
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: displayA, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 800), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 800), isMain: true),
                    DisplaySnapshot(id: displayB, index: 2, name: "B", frame: Rect(x: 1000, y: 0, width: 1000, height: 800), visibleFrame: Rect(x: 1000, y: 0, width: 1000, height: 800), isMain: false),
                ],
                windowSnapshots: [window],
                mousePoint: CGPoint(x: 200, y: 200)
            ),
            config: RoadieConfig(windowPlacement: WindowPlacementConfig(newAppsTarget: "mouse")),
            stageStore: stageStore
        )

        let snapshot = service.snapshot()

        #expect(snapshot.windows.first?.scope?.displayID == displayA)
        #expect(snapshot.windows.first?.scope?.stageID == StageID(rawValue: "1"))
    }

    @Test
    func newTileCandidatesCanFollowFocusedDisplay() {
        let displayA = DisplayID(rawValue: "display-a")
        let displayB = DisplayID(rawValue: "display-b")
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-focused-display-stages-\(UUID().uuidString).json")
            .path
        defer { try? FileManager.default.removeItem(atPath: stagePath) }
        var persisted = PersistentStageState()
        persisted.focusDisplay(displayA)
        StageStore(path: stagePath).save(persisted)
        let window = WindowSnapshot(
            id: WindowID(rawValue: 102),
            pid: 123,
            appName: "App",
            bundleID: "com.example.app",
            title: "Document",
            frame: Rect(x: 1200, y: 100, width: 400, height: 300),
            isOnScreen: true,
            isTileCandidate: true
        )
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: displayA, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 800), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 800), isMain: true),
                    DisplaySnapshot(id: displayB, index: 2, name: "B", frame: Rect(x: 1000, y: 0, width: 1000, height: 800), visibleFrame: Rect(x: 1000, y: 0, width: 1000, height: 800), isMain: false),
                ],
                windowSnapshots: [window],
                mousePoint: CGPoint(x: 1500, y: 200)
            ),
            config: RoadieConfig(windowPlacement: WindowPlacementConfig(newAppsTarget: "focused_display")),
            stageStore: StageStore(path: stagePath)
        )

        let snapshot = service.snapshot()

        #expect(snapshot.windows.first?.scope?.displayID == displayA)
    }

    @Test
    func staleDisplayMembershipIsPreservedUntilParkingHeal() {
        let staleDisplay = DisplayID(rawValue: "display-old")
        let liveDisplay = DisplayID(rawValue: "display-new")
        let window = WindowSnapshot(
            id: WindowID(rawValue: 103),
            pid: 123,
            appName: "App",
            bundleID: "com.example.app",
            title: "Document",
            frame: Rect(x: 1200, y: 100, width: 400, height: 300),
            isOnScreen: true,
            isTileCandidate: true
        )
        let stageStore = StageStore(path: tempPath("snapshot-stale-display-reassign"))
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: staleDisplay, activeStageID: StageID(rawValue: "4"), stages: [
                PersistentStage(id: StageID(rawValue: "4"), members: [
                    PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
                ]),
            ]),
        ], activeDisplayID: staleDisplay))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: liveDisplay, index: 1, name: "New", frame: Rect(x: 1000, y: 0, width: 1000, height: 800), visibleFrame: Rect(x: 1000, y: 0, width: 1000, height: 800), isMain: true),
                ],
                windowSnapshots: [window],
                focusedID: window.id
            ),
            config: RoadieConfig(),
            stageStore: stageStore
        )

        let snapshot = service.snapshot()
        let persisted = stageStore.state()

        #expect(snapshot.windows.first?.scope == nil)
        #expect(persisted.scopes.contains { $0.displayID == staleDisplay })
        let staleScope = persisted.scopes.first { $0.displayID == staleDisplay }
        let liveScope = persisted.scopes.first { $0.displayID == liveDisplay }
        #expect(persisted.activeDisplayID == liveDisplay)
        #expect(staleScope?.memberIDs(in: StageID(rawValue: "4")) == [window.id])
        #expect(liveScope?.memberIDs(in: StageID(rawValue: "1")).isEmpty == true)
    }

    @Test
    func nonTileCandidatesRemainUnscoped() {
        let display = DisplayID(rawValue: "display-a")
        let window = WindowSnapshot(
            id: WindowID(rawValue: 200),
            pid: 123,
            appName: "Panel",
            bundleID: "com.example.panel",
            title: "Panel",
            frame: Rect(x: 10, y: 10, width: 30, height: 30),
            isOnScreen: true,
            isTileCandidate: false
        )
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 800), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 800), isMain: true),
                ],
                windowSnapshots: [window]
            ),
            config: RoadieConfig()
        )

        let snapshot = service.snapshot()

        #expect(snapshot.windows.first?.scope == nil)
    }

    @Test
    func policyExcludedWindowsAreScopedButNotTiled() {
        let display = DisplayID(rawValue: "display-a")
        let window = WindowSnapshot(
            id: WindowID(rawValue: 201),
            pid: 123,
            appName: "Settings",
            bundleID: "com.example.settings",
            title: "Full Disk Access",
            frame: Rect(x: 10, y: 10, width: 720, height: 620),
            isOnScreen: true,
            isTileCandidate: true,
            subrole: "AXStandardWindow",
            role: "AXWindow",
            furniture: WindowFurniture(
                hasCloseButton: true,
                hasMinimizeButton: true,
                hasZoomButton: true,
                isMain: true,
                isResizable: false
            )
        )
        let stageStore = StageStore(path: tempPath("snapshot-floating-stage-scoped"))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 800), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 800), isMain: true),
                ],
                windowSnapshots: [window]
            ),
            config: RoadieConfig(),
            stageStore: stageStore
        )

        let snapshot = service.snapshot()
        let scope = snapshot.windows.first?.scope
        var persisted = stageStore.state()

        #expect(snapshot.windows.first?.window.isTileCandidate == false)
        #expect(scope == StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1")))
        #expect(persisted.scope(displayID: display).memberIDs(in: StageID(rawValue: "1")) == [window.id])
        #expect(scope.flatMap { snapshot.state.stage(scope: $0)?.windowIDs } == [])
        #expect(service.applyPlan(from: snapshot).commands.isEmpty)
    }

    @Test
    func applyPlanUsesVisibleFrameOfEachDisplay() {
        let display = DisplayID(rawValue: "display-a")
        let first = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 10,
            appName: "A",
            bundleID: "a",
            title: "one",
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            isOnScreen: true,
            isTileCandidate: true
        )
        let second = WindowSnapshot(
            id: WindowID(rawValue: 2),
            pid: 11,
            appName: "B",
            bundleID: "b",
            title: "two",
            frame: Rect(x: 100, y: 0, width: 100, height: 100),
            isOnScreen: true,
            isTileCandidate: true
        )
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 800), visibleFrame: Rect(x: 0, y: 20, width: 1000, height: 780), isMain: true),
                ],
                windowSnapshots: [first, second]
            ),
            config: RoadieConfig()
        )

        let plan = service.applyPlan(from: service.snapshot())

        #expect(plan.commands.map(\.window.id) == [first.id, second.id])
        #expect(plan.commands[0].frame == Rect(x: 8, y: 28, width: 490, height: 764))
        #expect(plan.commands[1].frame == Rect(x: 502, y: 28, width: 490, height: 764))
    }

    @Test
    func applyPlanLetsDisplayOverrideBaseGapOverrideGlobalSideGaps() {
        let displayA = DisplayID(rawValue: "display-a")
        let displayB = DisplayID(rawValue: "display-b")
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-display-gap-stages-\(UUID().uuidString).json")
            .path
        let intentPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-display-gap-intents-\(UUID().uuidString).json")
            .path
        let first = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 10,
            appName: "A",
            bundleID: "a",
            title: "one",
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            isOnScreen: true,
            isTileCandidate: true
        )
        let second = WindowSnapshot(
            id: WindowID(rawValue: 2),
            pid: 11,
            appName: "B",
            bundleID: "b",
            title: "two",
            frame: Rect(x: 1200, y: 0, width: 100, height: 100),
            isOnScreen: true,
            isTileCandidate: true
        )
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: displayA, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                    DisplaySnapshot(id: displayB, index: 2, name: "B", frame: Rect(x: 1000, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 1000, y: 0, width: 1000, height: 500), isMain: false),
                ],
                windowSnapshots: [first, second]
            ),
            config: RoadieConfig(tiling: TilingConfig(
                gapsOuter: 8,
                gapsOuterLeft: 150,
                displayOverrides: [
                    DisplayTilingOverride(displayID: displayB.rawValue, gapsOuter: 20)
                ],
                gapsInner: 10
            )),
            railSettings: RailSettings.load(raw: ""),
            intentStore: LayoutIntentStore(path: intentPath),
            stageStore: StageStore(path: stagePath)
        )
        defer {
            try? FileManager.default.removeItem(atPath: stagePath)
            try? FileManager.default.removeItem(atPath: intentPath)
        }

        let plan = service.applyPlan(from: service.snapshot())

        #expect(plan.commands.map(\.window.id) == [first.id, second.id])
        #expect(plan.commands[0].frame == Rect(x: 150, y: 8, width: 842, height: 484))
        #expect(plan.commands[1].frame == Rect(x: 1020, y: 20, width: 960, height: 460))
    }

    @Test
    func applyPlanTracksVisibleRailWidthWhenResizeLayoutModeIsEnabled() {
        let display = DisplayID(rawValue: "display-a")
        let first = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 10,
            appName: "A",
            bundleID: "a",
            title: "one",
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            isOnScreen: true,
            isTileCandidate: true
        )
        let second = WindowSnapshot(
            id: WindowID(rawValue: 2),
            pid: 11,
            appName: "B",
            bundleID: "b",
            title: "two",
            frame: Rect(x: 100, y: 0, width: 100, height: 100),
            isOnScreen: true,
            isTileCandidate: true
        )
        let railStatePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-rail-runtime-\(UUID().uuidString).json")
            .path
        let railStore = RailRuntimeStateStore(path: railStatePath)
        railStore.setVisibleWidth(150, for: display)
        defer { try? FileManager.default.removeItem(atPath: railStatePath) }

        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                ],
                windowSnapshots: [first, second]
            ),
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 8, gapsOuterLeft: 150, gapsInner: 10)),
            railSettings: RailSettings.load(raw: """
            [fx.rail]
            auto_hide = true
            edge_hit_width = 8
            layout_mode = "resize"
            """),
            railRuntimeStateStore: railStore
        )

        let plan = service.applyPlan(from: service.snapshot())

        #expect(plan.commands.map(\.window.id) == [first.id, second.id])
        #expect(plan.commands[0].frame == Rect(x: 150, y: 8, width: 416, height: 484))
        #expect(plan.commands[1].frame == Rect(x: 576, y: 8, width: 416, height: 484))
    }

    @Test
    func applyPlanUsesCollapsedRailWidthWhenDynamicLeftGapIsEnabled() {
        let display = DisplayID(rawValue: "display-a")
        let first = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 10,
            appName: "A",
            bundleID: "a",
            title: "one",
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            isOnScreen: true,
            isTileCandidate: true
        )
        let second = WindowSnapshot(
            id: WindowID(rawValue: 2),
            pid: 11,
            appName: "B",
            bundleID: "b",
            title: "two",
            frame: Rect(x: 100, y: 0, width: 100, height: 100),
            isOnScreen: true,
            isTileCandidate: true
        )
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                ],
                windowSnapshots: [first, second]
            ),
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 8, gapsOuterLeft: 150, gapsInner: 10)),
            railSettings: RailSettings.load(raw: """
            [fx.rail]
            auto_hide = true
            edge_hit_width = 8
            dynamic_left_gap = true
            """)
        )

        let plan = service.applyPlan(from: service.snapshot())

        #expect(plan.commands.map(\.window.id) == [first.id, second.id])
        #expect(plan.commands[0].frame == Rect(x: 8, y: 8, width: 487, height: 484))
        #expect(plan.commands[1].frame == Rect(x: 505, y: 8, width: 487, height: 484))
    }

    @Test
    func applyPlanSkipsWindowsAlreadyAtTargetFrames() {
        let display = DisplayID(rawValue: "display-a")
        let first = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 10,
            appName: "A",
            bundleID: "a",
            title: "one",
            frame: Rect(x: 8, y: 28, width: 490, height: 764),
            isOnScreen: true,
            isTileCandidate: true
        )
        let second = WindowSnapshot(
            id: WindowID(rawValue: 2),
            pid: 11,
            appName: "B",
            bundleID: "b",
            title: "two",
            frame: Rect(x: 502, y: 28, width: 490, height: 764),
            isOnScreen: true,
            isTileCandidate: true
        )
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 800), visibleFrame: Rect(x: 0, y: 20, width: 1000, height: 780), isMain: true),
                ],
                windowSnapshots: [first, second]
            ),
            config: RoadieConfig()
        )

        #expect(service.applyPlan(from: service.snapshot(), priorityWindowIDs: [second.id]).commands.isEmpty)
    }

    @Test
    func persistentActiveStageModeControlsApplyPlan() {
        let display = DisplayID(rawValue: "display-a")
        let windows = [
            WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "one", frame: Rect(x: 0, y: 0, width: 100, height: 100), isOnScreen: true, isTileCandidate: true),
            WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "two", frame: Rect(x: 100, y: 0, width: 100, height: 100), isOnScreen: true, isTileCandidate: true),
            WindowSnapshot(id: WindowID(rawValue: 3), pid: 12, appName: "C", bundleID: "c", title: "three", frame: Rect(x: 200, y: 0, width: 100, height: 100), isOnScreen: true, isTileCandidate: true),
        ]
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-mode-stages-\(UUID().uuidString).json")
            .path
        let intentPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-mode-intent-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        let intentStore = LayoutIntentStore(path: intentPath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(
                displayID: display,
                stages: [PersistentStage(id: StageID(rawValue: "1"), mode: .masterStack)]
            ),
        ]))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                ],
                windowSnapshots: windows
            ),
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            intentStore: intentStore,
            stageStore: stageStore
        )

        let snapshot = service.snapshot()
        let scope = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let commands = service.applyPlan(from: snapshot).commands

        #expect(snapshot.state.stage(scope: scope)?.mode == .masterStack)
        #expect(commands.map(\.window.id) == windows.map(\.id))
        #expect(commands[0].frame == Rect(x: 0, y: 0, width: 100, height: 500))
        #expect(commands[1].frame == Rect(x: 110, y: 0, width: 890, height: 245))
        #expect(commands[2].frame == Rect(x: 110, y: 255, width: 890, height: 245))
        try? FileManager.default.removeItem(atPath: stagePath)
        try? FileManager.default.removeItem(atPath: intentPath)
    }

    @Test
    func configWorkspacesSeedPersistentStageNames() {
        let display = DisplayID(rawValue: "display-a")
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-config-stage-names-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                ],
                windowSnapshots: []
            ),
            config: RoadieConfig(stageManager: StageManagerConfig(workspaces: [
                StageDefinition(id: "1", displayName: "Work"),
                StageDefinition(id: "2", displayName: "Com"),
            ])),
            stageStore: stageStore
        )

        _ = service.snapshot()
        let scope = stageStore.state().scopes.first { $0.displayID == display }

        #expect(scope?.stages.map(\.name) == ["Work", "Com"])
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func snapshotPersistsFocusedWindowInStage() {
        let display = DisplayID(rawValue: "display-a")
        let first = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "one", frame: Rect(x: 0, y: 0, width: 400, height: 500), isOnScreen: true, isTileCandidate: true)
        let second = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "two", frame: Rect(x: 410, y: 0, width: 400, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-focused-stage-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                ],
                windowSnapshots: [first, second],
                focusedID: first.id
            ),
            stageStore: stageStore
        )

        let snapshot = service.snapshot()
        let scope = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let persistedStage = stageStore.state().scopes.first { $0.displayID == display }?.stages.first { $0.id == scope.stageID }

        #expect(snapshot.state.stage(scope: scope)?.focusedWindowID == first.id)
        #expect(persistedStage?.focusedWindowID == first.id)
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func snapshotSwitchesStageWhenMacFocusPointsToHiddenInactiveStage() {
        let display = DisplayID(rawValue: "display-a")
        let active = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "active", frame: Rect(x: 0, y: 0, width: 1000, height: 500), isOnScreen: true, isTileCandidate: true)
        let hidden = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "hidden", frame: Rect(x: 999, y: 499, width: 1000, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-hidden-focus-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: active.id, members: [
                    PersistentStageMember(windowID: active.id, bundleID: active.bundleID, title: active.title, frame: active.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "2"), focusedWindowID: hidden.id, members: [
                    PersistentStageMember(windowID: hidden.id, bundleID: hidden.bundleID, title: hidden.title, frame: hidden.frame),
                ]),
            ]),
        ]))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                ],
                windowSnapshots: [active, hidden],
                focusedID: hidden.id
            ),
            stageStore: stageStore
        )

        let snapshot = service.snapshot()
        var persisted = stageStore.state()

        #expect(snapshot.focusedWindowID == hidden.id)
        #expect(snapshot.state.activeScope(on: display) == StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "2")))
        #expect(persisted.scope(displayID: display).activeStageID == StageID(rawValue: "2"))
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func snapshotCanIgnoreMacFocusWhenStageFollowsFocusIsDisabled() {
        let display = DisplayID(rawValue: "display-a")
        let active = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "active", frame: Rect(x: 0, y: 0, width: 1000, height: 500), isOnScreen: true, isTileCandidate: true)
        let hidden = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "hidden", frame: Rect(x: 999, y: 499, width: 1000, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-hidden-focus-disabled-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: active.id, members: [
                    PersistentStageMember(windowID: active.id, bundleID: active.bundleID, title: active.title, frame: active.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "2"), focusedWindowID: hidden.id, members: [
                    PersistentStageMember(windowID: hidden.id, bundleID: hidden.bundleID, title: hidden.title, frame: hidden.frame),
                ]),
            ]),
        ]))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                ],
                windowSnapshots: [active, hidden],
                focusedID: hidden.id
            ),
            config: RoadieConfig(focus: FocusConfig(stageFollowsFocus: false)),
            stageStore: stageStore
        )

        let snapshot = service.snapshot()

        #expect(snapshot.focusedWindowID == active.id)
        #expect(snapshot.state.activeScope(on: display) == StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1")))
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func floatStageModeDoesNotReplaySavedTilingIntent() {
        let display = DisplayID(rawValue: "display-a")
        let first = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "one", frame: Rect(x: 10, y: 10, width: 200, height: 200), isOnScreen: true, isTileCandidate: true)
        let second = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "two", frame: Rect(x: 300, y: 10, width: 200, height: 200), isOnScreen: true, isTileCandidate: true)
        let scope = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-float-stages-\(UUID().uuidString).json")
            .path
        let intentPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-float-intent-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        let intentStore = LayoutIntentStore(path: intentPath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(
                displayID: display,
                stages: [PersistentStage(id: scope.stageID, mode: .float)]
            ),
        ]))
        intentStore.save(LayoutIntent(scope: scope, windowIDs: [first.id, second.id], placements: [
            first.id: Rect(x: 0, y: 0, width: 495, height: 500),
            second.id: Rect(x: 505, y: 0, width: 495, height: 500),
        ]))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                ],
                windowSnapshots: [first, second]
            ),
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            intentStore: intentStore,
            stageStore: stageStore
        )

        #expect(service.applyPlan(from: service.snapshot()).commands.isEmpty)
        try? FileManager.default.removeItem(atPath: stagePath)
        try? FileManager.default.removeItem(atPath: intentPath)
    }

    @Test
    func bspUsesSpatialOrderAfterManualReposition() {
        let display = DisplayID(rawValue: "display-a")
        let first = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 10,
            appName: "A",
            bundleID: "a",
            title: "one",
            frame: Rect(x: 505, y: 0, width: 495, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        let second = WindowSnapshot(
            id: WindowID(rawValue: 2),
            pid: 11,
            appName: "B",
            bundleID: "b",
            title: "two",
            frame: Rect(x: 0, y: 0, width: 495, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                ],
                windowSnapshots: [first, second]
            ),
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10))
        )

        #expect(service.applyPlan(from: service.snapshot(), priorityWindowIDs: [second.id]).commands.isEmpty)
    }

    @Test
    func bspNewWindowDoesNotInheritStaleManualRatio() {
        let display = DisplayID(rawValue: "display-a")
        let first = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 10,
            appName: "A",
            bundleID: "a",
            title: "one",
            frame: Rect(x: 0, y: 0, width: 800, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        let second = WindowSnapshot(
            id: WindowID(rawValue: 2),
            pid: 11,
            appName: "B",
            bundleID: "b",
            title: "two",
            frame: Rect(x: 810, y: 0, width: 190, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                ],
                windowSnapshots: [first, second]
            ),
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10))
        )

        let commands = service.applyPlan(from: service.snapshot()).commands

        #expect(commands.map(\.window.id) == [first.id, second.id])
        #expect(commands[0].frame == Rect(x: 0, y: 0, width: 495, height: 500))
        #expect(commands[1].frame == Rect(x: 505, y: 0, width: 495, height: 500))
    }

    @Test
    func staleIntentWithHoleIsInvalidatedAndRebalanced() {
        let display = DisplayID(rawValue: "display-a")
        let first = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 10,
            appName: "Firefox",
            bundleID: "org.mozilla.firefox",
            title: "left",
            frame: Rect(x: 0, y: 0, width: 495, height: 245),
            isOnScreen: true,
            isTileCandidate: true
        )
        let second = WindowSnapshot(
            id: WindowID(rawValue: 2),
            pid: 11,
            appName: "Finder",
            bundleID: "com.apple.finder",
            title: "right",
            frame: Rect(x: 505, y: 0, width: 495, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        let scope = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let intentPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-stale-intent-\(UUID().uuidString).json")
            .path
        let intentStore = LayoutIntentStore(path: intentPath)
        intentStore.save(LayoutIntent(scope: scope, windowIDs: [first.id, second.id], placements: [
            first.id: first.frame,
            second.id: second.frame,
        ]))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                ],
                windowSnapshots: [first, second]
            ),
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            intentStore: intentStore
        )

        let commands = service.applyPlan(from: service.snapshot()).commands

        #expect(commands.first { $0.window.id == first.id }?.frame == Rect(x: 0, y: 0, width: 495, height: 500))
        #expect(intentStore.intent(for: scope) == nil)
        try? FileManager.default.removeItem(atPath: intentPath)
    }

    @Test
    func completeNonCanonicalIntentIsPreserved() {
        let display = DisplayID(rawValue: "display-a")
        let leftTop = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "left-top", frame: Rect(x: 0, y: 0, width: 660, height: 245), isOnScreen: true, isTileCandidate: true)
        let leftBottom = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "left-bottom", frame: Rect(x: 0, y: 255, width: 660, height: 245), isOnScreen: true, isTileCandidate: true)
        let right = WindowSnapshot(id: WindowID(rawValue: 3), pid: 12, appName: "C", bundleID: "c", title: "right", frame: Rect(x: 670, y: 0, width: 330, height: 500), isOnScreen: true, isTileCandidate: true)
        let scope = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let intentPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-complete-intent-\(UUID().uuidString).json")
            .path
        let intentStore = LayoutIntentStore(path: intentPath)
        intentStore.save(LayoutIntent(scope: scope, windowIDs: [leftTop.id, leftBottom.id, right.id], placements: [
            leftTop.id: leftTop.frame,
            leftBottom.id: leftBottom.frame,
            right.id: right.frame,
        ]))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                ],
                windowSnapshots: [leftTop, leftBottom, right]
            ),
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            intentStore: intentStore
        )

        #expect(service.applyPlan(from: service.snapshot()).commands.isEmpty)
        #expect(intentStore.intent(for: scope) != nil)
        try? FileManager.default.removeItem(atPath: intentPath)
    }

    @Test
    func autoIntentWithTinyTileIsInvalidated() {
        let display = DisplayID(rawValue: "display-a")
        let left = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "left", frame: Rect(x: 150, y: 38, width: 790, height: 1182), isOnScreen: true, isTileCandidate: true)
        let bottomRight = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "bottom-right", frame: Rect(x: 950, y: 170, width: 1090, height: 1050), isOnScreen: true, isTileCandidate: true)
        let tinyTopRight = WindowSnapshot(id: WindowID(rawValue: 3), pid: 12, appName: "C", bundleID: "c", title: "tiny-top-right", frame: Rect(x: 950, y: 38, width: 1090, height: 122), isOnScreen: true, isTileCandidate: true)
        let scope = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let intentPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-tiny-intent-\(UUID().uuidString).json")
            .path
        let intentStore = LayoutIntentStore(path: intentPath)
        intentStore.save(LayoutIntent(scope: scope, windowIDs: [left.id, bottomRight.id, tinyTopRight.id], placements: [
            left.id: left.frame,
            bottomRight.id: bottomRight.frame,
            tinyTopRight.id: tinyTopRight.frame,
        ]))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 2048, height: 1280), visibleFrame: Rect(x: 0, y: 30, width: 2048, height: 1250), isMain: true),
                ],
                windowSnapshots: [left, bottomRight, tinyTopRight]
            ),
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            intentStore: intentStore
        )

        let commands = service.applyPlan(from: service.snapshot()).commands

        #expect(!commands.isEmpty)
        #expect(intentStore.intent(for: scope) == nil)
        try? FileManager.default.removeItem(atPath: intentPath)
    }

    @Test
    func configExclusionsKeepMatchingBundlesScopedButUntiled() {
        let display = DisplayID(rawValue: "display-a")
        let window = WindowSnapshot(
            id: WindowID(rawValue: 300),
            pid: 123,
            appName: "Settings",
            bundleID: "com.apple.systempreferences",
            title: "Settings",
            frame: Rect(x: 10, y: 10, width: 500, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 800), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 800), isMain: true),
                ],
                windowSnapshots: [window]
            ),
            config: RoadieConfig(exclusions: ExclusionsConfig(floatingBundles: ["com.apple.systempreferences"]))
        )

        let snapshot = service.snapshot()

        #expect(snapshot.windows.first?.scope == StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1")))
        #expect(snapshot.windows.first?.window.isTileCandidate == false)
        #expect(snapshot.windows.first?.scope.flatMap { snapshot.state.stage(scope: $0)?.windowIDs } == [])
        #expect(service.applyPlan(from: snapshot).commands.isEmpty)
    }

    @Test
    func applyReportsAppliedClampedAndFailedFrames() {
        let applied = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "a", frame: Rect(x: 0, y: 0, width: 10, height: 10), isOnScreen: true, isTileCandidate: true)
        let clamped = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "b", frame: Rect(x: 0, y: 0, width: 10, height: 10), isOnScreen: true, isTileCandidate: true)
        let failed = WindowSnapshot(id: WindowID(rawValue: 3), pid: 12, appName: "C", bundleID: "c", title: "c", frame: Rect(x: 0, y: 0, width: 10, height: 10), isOnScreen: true, isTileCandidate: true)
        let requested = Rect(x: 10, y: 10, width: 100, height: 100)
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [], windowSnapshots: []),
            frameWriter: FakeWriter(actualFrames: [
                applied.id: requested,
                clamped.id: Rect(x: 10, y: 10, width: 40, height: 100),
            ])
        )

        let result = service.apply(ApplyPlan(commands: [
            ApplyCommand(window: applied, frame: requested),
            ApplyCommand(window: clamped, frame: requested),
            ApplyCommand(window: failed, frame: requested),
        ]))

        #expect(result.attempted == 3)
        #expect(result.applied == 1)
        #expect(result.clamped == 1)
        #expect(result.failed == 1)
        #expect(result.items.map(\.status) == [.applied, .clamped, .failed])
    }

    @Test
    func warpMovesSmallWindowAcrossRootSplitInsteadOfSwappingFrames() {
        let display = DisplayID(rawValue: "display-a")
        let left = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "left", frame: Rect(x: 0, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let topRight = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "top-right", frame: Rect(x: 505, y: 0, width: 495, height: 245), isOnScreen: true, isTileCandidate: true)
        let bottomRight = WindowSnapshot(id: WindowID(rawValue: 3), pid: 12, appName: "C", bundleID: "c", title: "bottom-right", frame: Rect(x: 505, y: 255, width: 495, height: 245), isOnScreen: true, isTileCandidate: true)
        let provider = FakeProvider(
            displaySnapshots: [
                DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
            ],
            windowSnapshots: [left, topRight, bottomRight],
            focusedID: topRight.id
        )
        let config = RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10))
        let intentPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-test-\(UUID().uuidString).json")
            .path
        let intentStore = LayoutIntentStore(path: intentPath)

        let swapWriter = RecordingWriter()
        let swapService = WindowCommandService(service: SnapshotService(provider: provider, frameWriter: swapWriter, config: config, intentStore: intentStore))
        let swapResult = swapService.move(Direction.left)

        #expect(swapResult.changed)
        #expect(swapWriter.requestedFrames == [
            topRight.id: left.frame,
            left.id: topRight.frame,
        ])

        let warpWriter = RecordingWriter()
        let warpService = WindowCommandService(service: SnapshotService(provider: provider, frameWriter: warpWriter, config: config, intentStore: intentStore))
        let warpResult = warpService.warp(Direction.left)

        #expect(warpResult.changed)
        #expect(warpWriter.requestedFrames[topRight.id] == Rect(x: 0, y: 0, width: 660, height: 245))
        #expect(warpWriter.requestedFrames[left.id] == Rect(x: 0, y: 255, width: 660, height: 245))
        #expect(warpWriter.requestedFrames[bottomRight.id] == Rect(x: 670, y: 0, width: 330, height: 500))
        #expect(warpWriter.requestedFrames != swapWriter.requestedFrames)
        try? FileManager.default.removeItem(atPath: intentPath)
    }

    @Test
    func mutableBspWarpInsertsIntoImmediateNeighborSlot() {
        let display = DisplayID(rawValue: "display-a")
        let topLeft = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "top-left", frame: Rect(x: 0, y: 0, width: 495, height: 245), isOnScreen: true, isTileCandidate: true)
        let topRight = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "top-right", frame: Rect(x: 505, y: 0, width: 495, height: 245), isOnScreen: true, isTileCandidate: true)
        let bottomLeft = WindowSnapshot(id: WindowID(rawValue: 3), pid: 12, appName: "C", bundleID: "c", title: "bottom-left", frame: Rect(x: 0, y: 255, width: 495, height: 245), isOnScreen: true, isTileCandidate: true)
        let bottomRight = WindowSnapshot(id: WindowID(rawValue: 4), pid: 13, appName: "D", bundleID: "d", title: "bottom-right", frame: Rect(x: 505, y: 255, width: 495, height: 245), isOnScreen: true, isTileCandidate: true)
        let provider = FakeProvider(
            displaySnapshots: [
                DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
            ],
            windowSnapshots: [topLeft, topRight, bottomLeft, bottomRight],
            focusedID: bottomRight.id
        )
        let config = RoadieConfig(tiling: TilingConfig(defaultStrategy: .mutableBsp, gapsOuter: 0, gapsInner: 10))
        let stageStore = StageStore(path: FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-mutable-warp-\(UUID().uuidString).json")
            .path)
        stageStore.save(PersistentStageState(
            scopes: [
                PersistentStageScope(
                    displayID: display,
                    stages: [
                        PersistentStage(
                            id: StageID(rawValue: "1"),
                            mode: .mutableBsp,
                            focusedWindowID: bottomRight.id,
                            members: [topLeft, topRight, bottomLeft, bottomRight].map {
                                PersistentStageMember(windowID: $0.id, bundleID: $0.bundleID, title: $0.title, frame: $0.frame)
                            }
                        ),
                    ]
                ),
            ],
            activeDisplayID: display
        ))
        let writer = RecordingWriter()
        let service = WindowCommandService(
            service: SnapshotService(provider: provider, frameWriter: writer, config: config, stageStore: stageStore),
            stageStore: stageStore
        )

        let result = service.warp(Direction.left)

        #expect(result.changed)
        #expect(writer.requestedFrames[bottomRight.id] == Rect(x: 0, y: 255, width: 242, height: 245))
        #expect(writer.requestedFrames[bottomLeft.id] == Rect(x: 252, y: 255, width: 243, height: 245))
        #expect(writer.requestedFrames[topRight.id] == Rect(x: 505, y: 0, width: 495, height: 500))
        #expect(writer.requestedFrames[topLeft.id] == nil)
    }

    @Test
    func swapIntentPreventsMaintainerFromRevertingToSpatialBSPOrder() {
        let display = DisplayID(rawValue: "display-a")
        let left = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "left", frame: Rect(x: 0, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let right = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "right", frame: Rect(x: 505, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let displaySnapshot = DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let config = RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10))
        let intentPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-test-\(UUID().uuidString).json")
            .path
        let intentStore = LayoutIntentStore(path: intentPath)

        let writer = RecordingWriter()
        let commandService = WindowCommandService(service: SnapshotService(
            provider: FakeProvider(displaySnapshots: [displaySnapshot], windowSnapshots: [left, right], focusedID: right.id),
            frameWriter: writer,
            config: config,
            intentStore: intentStore
        ))

        let swapResult = commandService.move(Direction.left)

        #expect(swapResult.changed)
        #expect(writer.requestedFrames == [
            right.id: left.frame,
            left.id: right.frame,
        ])

        let postSwapLeft = WindowSnapshot(id: left.id, pid: left.pid, appName: left.appName, bundleID: left.bundleID, title: left.title, frame: right.frame, isOnScreen: true, isTileCandidate: true)
        let postSwapRight = WindowSnapshot(id: right.id, pid: right.pid, appName: right.appName, bundleID: right.bundleID, title: right.title, frame: left.frame, isOnScreen: true, isTileCandidate: true)
        let maintainerService = SnapshotService(
            provider: FakeProvider(displaySnapshots: [displaySnapshot], windowSnapshots: [postSwapLeft, postSwapRight], focusedID: right.id),
            config: config,
            intentStore: intentStore
        )

        #expect(maintainerService.applyPlan(from: maintainerService.snapshot()).commands.isEmpty)
        try? FileManager.default.removeItem(atPath: intentPath)
    }

    @Test
    func moveIntentPersistsAsCommandEvenWhenClamped() {
        let display = DisplayID(rawValue: "display-a")
        let left = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "left", frame: Rect(x: 0, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let right = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "right", frame: Rect(x: 505, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let displaySnapshot = DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let intentPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-command-clamp-intent-\(UUID().uuidString).json")
            .path
        let intentStore = LayoutIntentStore(path: intentPath)
        let writer = DeterministicWriter(actualFrames: [
            left.id: Rect(x: 505, y: 0, width: 495, height: 250),
            right.id: Rect(x: 0, y: 0, width: 495, height: 500),
        ])
        let service = WindowCommandService(
            service: SnapshotService(
                provider: FakeProvider(
                    displaySnapshots: [displaySnapshot],
                    windowSnapshots: [left, right],
                    focusedID: right.id
                ),
                frameWriter: writer,
                config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
                intentStore: intentStore
            )
        )

        let result = service.move(Direction.left)

        let intent = intentStore.intent(for: StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1")))
        #expect(result.changed)
        #expect(intent?.source == .command)
        #expect(intent?.placements[left.id] == Rect(x: 505, y: 0, width: 495, height: 250))
        try? FileManager.default.removeItem(atPath: intentPath)
    }

    @Test
    func commandIntentPersistsOnPartialCommandFailure() {
        let display = DisplayID(rawValue: "display-a")
        let left = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "left", frame: Rect(x: 0, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let right = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "right", frame: Rect(x: 505, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let displaySnapshot = DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let intentPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-command-partial-fail-intent-\(UUID().uuidString).json")
            .path
        let intentStore = LayoutIntentStore(path: intentPath)
        let service = WindowCommandService(
            service: SnapshotService(
                provider: FakeProvider(
                    displaySnapshots: [displaySnapshot],
                    windowSnapshots: [left, right],
                    focusedID: right.id
                ),
                frameWriter: PartialFailureWriter(actualFrames: [
                    left.id: nil,
                    right.id: Rect(x: 0, y: 0, width: 495, height: 500),
                ]),
                config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
                intentStore: intentStore
            )
        )

        let result = service.move(Direction.left)

        let intent = intentStore.intent(for: StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1")))
        #expect(result.changed)
        #expect(intent?.source == .command)
        #expect(intent?.windowIDs.count == 2)
        try? FileManager.default.removeItem(atPath: intentPath)
    }

    @Test
    func commandIntentPersistsWithRecentDriftAndDoesNotGetInvalidated() {
        let display = DisplayID(rawValue: "display-a")
        let left = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 10,
            appName: "A",
            bundleID: "a",
            title: "left",
            frame: Rect(x: 0, y: 0, width: 495, height: 250),
            isOnScreen: true,
            isTileCandidate: true
        )
        let right = WindowSnapshot(
            id: WindowID(rawValue: 2),
            pid: 11,
            appName: "B",
            bundleID: "b",
            title: "right",
            frame: Rect(x: 505, y: 0, width: 495, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        let displaySnapshot = DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let intentScope = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let intentPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-command-drift-intent-\(UUID().uuidString).json")
            .path
        let intentStore = LayoutIntentStore(path: intentPath)
        intentStore.save(LayoutIntent(
            scope: intentScope,
            windowIDs: [left.id, right.id],
            placements: [
                left.id: Rect(x: 0, y: 0, width: 495, height: 500),
                right.id: Rect(x: 505, y: 0, width: 495, height: 500),
            ],
            createdAt: Date(),
            source: .command
        ))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [displaySnapshot],
                windowSnapshots: [left, right]
            ),
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            intentStore: intentStore
        )
        let snapshot = service.snapshot()
        let plan = service.applyPlan(from: snapshot)

        #expect(!plan.commands.isEmpty)
        #expect(intentStore.intent(for: intentScope) != nil)
        #expect(plan.commands.first?.window.id == left.id)
        try? FileManager.default.removeItem(atPath: intentPath)
    }

    @Test
    func moveFallsBackToActiveStageFocusedWindowWhenAXFocusIsUnavailable() {
        let display = DisplayID(rawValue: "display-a")
        let left = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "left", frame: Rect(x: 0, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let topRight = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "top-right", frame: Rect(x: 505, y: 0, width: 495, height: 245), isOnScreen: true, isTileCandidate: true)
        let bottomRight = WindowSnapshot(id: WindowID(rawValue: 3), pid: 12, appName: "C", bundleID: "c", title: "bottom-right", frame: Rect(x: 505, y: 255, width: 495, height: 245), isOnScreen: true, isTileCandidate: true)
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                ],
                windowSnapshots: [left, topRight, bottomRight],
                focusedID: nil
            ),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10))
        )

        let result = WindowCommandService(service: service).move(.up)

        #expect(result.changed)
        #expect(writer.requestedFrames.keys.contains(bottomRight.id))
        #expect(writer.focusedWindowIDs == [bottomRight.id])
    }

    @Test
    func resizeCommandReflowsLayoutAroundResizedWindowAndPersistsIntent() {
        let display = DisplayID(rawValue: "display-a")
        let left = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "left", frame: Rect(x: 0, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let right = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "right", frame: Rect(x: 505, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let resizedRight = WindowSnapshot(id: right.id, pid: right.pid, appName: right.appName, bundleID: right.bundleID, title: right.title, frame: Rect(x: 505, y: 0, width: 575, height: 500), isOnScreen: true, isTileCandidate: true)
        let displaySnapshot = DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let provider = SequenceSnapshotProvider(
            displaySnapshots: [displaySnapshot],
            windowSnapshots: [
                [left, right],
                [left, resizedRight],
            ],
            focusedID: right.id
        )
        let writer = RecordingWriter()
        let intentPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-resize-command-intent-\(UUID().uuidString).json")
            .path
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-resize-command-stages-\(UUID().uuidString).json")
            .path
        let intentStore = LayoutIntentStore(path: intentPath)
        let stageStore = StageStore(path: stagePath)
        let service = WindowCommandService(
            service: SnapshotService(
                provider: provider,
                frameWriter: writer,
                config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
                intentStore: intentStore,
                stageStore: stageStore
            )
        )

        let result = service.resize(.right)
        let scope = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let intent = intentStore.intent(for: scope)

        #expect(result.changed)
        #expect(writer.requestedFrames[right.id] == Rect(x: 425, y: 0, width: 575, height: 500))
        #expect(writer.requestedFrames[left.id] == Rect(x: 0, y: 0, width: 415, height: 500))
        #expect(intent?.source == .command)
        #expect(intent?.placements[right.id] == Rect(x: 425, y: 0, width: 575, height: 500))
        try? FileManager.default.removeItem(atPath: intentPath)
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func stageAssignAndSwitchHideAndRestoreMembers() {
        let display = DisplayID(rawValue: "display-a")
        let displaySnapshot = DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let left = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "left", frame: Rect(x: 0, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let right = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "right", frame: Rect(x: 505, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-stages-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)

        let assignWriter = RecordingWriter()
        let assignService = SnapshotService(
            provider: FakeProvider(displaySnapshots: [displaySnapshot], windowSnapshots: [left, right], focusedID: right.id),
            frameWriter: assignWriter,
            config: RoadieConfig(),
            stageStore: stageStore
        )
        let assignResult = StageCommandService(service: assignService, store: stageStore).assign("2")

        #expect(assignResult.changed)
        #expect(assignWriter.requestedFrames[right.id] == Rect(x: 999, y: 499, width: 495, height: 500))

        let hiddenRight = WindowSnapshot(id: right.id, pid: right.pid, appName: right.appName, bundleID: right.bundleID, title: right.title, frame: Rect(x: 999, y: 499, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let switchWriter = RecordingWriter()
        let switchService = SnapshotService(
            provider: FakeProvider(displaySnapshots: [displaySnapshot], windowSnapshots: [left, hiddenRight], focusedID: left.id),
            frameWriter: switchWriter,
            config: RoadieConfig(),
            stageStore: stageStore
        )
        let switchResult = StageCommandService(service: switchService, store: stageStore).switchTo("2")
        let state = stageStore.state()

        #expect(switchResult.changed)
        #expect(switchWriter.requestedFrames[left.id] == Rect(x: 999, y: 499, width: 495, height: 500))
        #expect(switchWriter.requestedFrames[right.id] == Rect(x: 8, y: 8, width: 984, height: 484))
        #expect(switchWriter.focusedWindowIDs == [right.id])
        #expect(state.activeDisplayID == display)
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func stageSummonMovesExplicitWindowToActiveStage() {
        let display = DisplayID(rawValue: "display-a")
        let displaySnapshot = DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let left = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "left", frame: Rect(x: 0, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let hiddenRight = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "right", frame: Rect(x: 999, y: 499, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-summon-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: left.id, members: [
                    PersistentStageMember(windowID: left.id, bundleID: left.bundleID, title: left.title, frame: left.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "2"), focusedWindowID: hiddenRight.id, members: [
                    PersistentStageMember(windowID: hiddenRight.id, bundleID: hiddenRight.bundleID, title: hiddenRight.title, frame: Rect(x: 505, y: 0, width: 495, height: 500)),
                ]),
            ]),
        ]))

        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [displaySnapshot], windowSnapshots: [left, hiddenRight], focusedID: left.id),
            frameWriter: writer,
            config: RoadieConfig(),
            stageStore: stageStore
        )
        let result = StageCommandService(service: service, store: stageStore).summon(windowID: hiddenRight.id, displayID: display)
        var state = stageStore.state()
        let scope = state.scope(displayID: display, desktopID: DesktopID(rawValue: 1))

        #expect(result.changed)
        #expect(scope.memberIDs(in: StageID(rawValue: "1")) == [left.id, hiddenRight.id])
        #expect(scope.memberIDs(in: StageID(rawValue: "2")).isEmpty)
        #expect(scope.stages.first { $0.id == StageID(rawValue: "2") }?.focusedWindowID == nil)
        #expect(writer.focusedWindowIDs == [hiddenRight.id])
        #expect(writer.requestedFrames[hiddenRight.id] != hiddenRight.frame)
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func desktopFocusHidesOutgoingDesktopAndRestoresIncomingDesktop() {
        let display = DisplayID(rawValue: "display-a")
        let displaySnapshot = DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let left = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "left", frame: Rect(x: 0, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let right = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "right", frame: Rect(x: 999, y: 499, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-desktops-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: display, desktopID: DesktopID(rawValue: 1), activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: left.id, members: [
                        PersistentStageMember(windowID: left.id, bundleID: left.bundleID, title: left.title, frame: left.frame),
                    ]),
                ]),
                PersistentStageScope(displayID: display, desktopID: DesktopID(rawValue: 2), activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: right.id, members: [
                        PersistentStageMember(windowID: right.id, bundleID: right.bundleID, title: right.title, frame: Rect(x: 505, y: 0, width: 495, height: 500)),
                    ]),
                ]),
            ],
            desktopSelections: [PersistentDesktopSelection(displayID: display, currentDesktopID: DesktopID(rawValue: 1))]
        ))
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [displaySnapshot], windowSnapshots: [left, right], focusedID: left.id),
            frameWriter: writer,
            config: RoadieConfig(),
            stageStore: stageStore
        )

        let result = DesktopCommandService(service: service, store: stageStore).focus(DesktopID(rawValue: 2))
        let state = stageStore.state()

        #expect(result.changed)
        #expect(writer.requestedFrames[left.id] == Rect(x: 999, y: 499, width: 495, height: 500))
        #expect(writer.requestedFrames[right.id] == Rect(x: 8, y: 8, width: 984, height: 484))
        #expect(writer.focusedWindowIDs == [right.id])
        #expect(state.currentDesktopID(for: display) == DesktopID(rawValue: 2))
        #expect(state.lastDesktopID(for: display) == DesktopID(rawValue: 1))
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func snapshotDoesNotFollowFocusBackToHiddenDesktopWindow() {
        let display = DisplayID(rawValue: "display-a")
        let displaySnapshot = DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let hiddenOldDesktop = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "hidden", frame: Rect(x: 999, y: 499, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let visibleCurrentDesktop = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "visible", frame: Rect(x: 0, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-hidden-focus-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: display, desktopID: DesktopID(rawValue: 1), activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: hiddenOldDesktop.id, members: [
                        PersistentStageMember(windowID: hiddenOldDesktop.id, bundleID: hiddenOldDesktop.bundleID, title: hiddenOldDesktop.title, frame: hiddenOldDesktop.frame),
                    ]),
                ]),
                PersistentStageScope(displayID: display, desktopID: DesktopID(rawValue: 2), activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: visibleCurrentDesktop.id, members: [
                        PersistentStageMember(windowID: visibleCurrentDesktop.id, bundleID: visibleCurrentDesktop.bundleID, title: visibleCurrentDesktop.title, frame: visibleCurrentDesktop.frame),
                    ]),
                ]),
            ],
            desktopSelections: [PersistentDesktopSelection(displayID: display, currentDesktopID: DesktopID(rawValue: 2))]
        ))
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [displaySnapshot], windowSnapshots: [hiddenOldDesktop, visibleCurrentDesktop], focusedID: hiddenOldDesktop.id),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            stageStore: stageStore
        )

        let snapshot = service.snapshot()
        let state = stageStore.state()

        #expect(snapshot.state.display(display)?.currentDesktopID == DesktopID(rawValue: 2))
        #expect(state.currentDesktopID(for: display) == DesktopID(rawValue: 2))
        #expect(snapshot.focusedWindowID == visibleCurrentDesktop.id)
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func windowDesktopAssignMovesActiveWindowToTargetDesktopWithoutFollowing() {
        let display = DisplayID(rawValue: "display-a")
        let displaySnapshot = DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let left = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "left", frame: Rect(x: 0, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-window-desktop-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: display, desktopID: DesktopID(rawValue: 1), activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: left.id, members: [
                        PersistentStageMember(windowID: left.id, bundleID: left.bundleID, title: left.title, frame: left.frame),
                    ]),
                ]),
                PersistentStageScope(displayID: display, desktopID: DesktopID(rawValue: 2)),
            ],
            desktopSelections: [PersistentDesktopSelection(displayID: display, currentDesktopID: DesktopID(rawValue: 1))]
        ))
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [displaySnapshot], windowSnapshots: [left], focusedID: left.id),
            frameWriter: writer,
            config: RoadieConfig(),
            stageStore: stageStore
        )

        let result = DesktopCommandService(service: service, store: stageStore).assignActiveWindow(to: DesktopID(rawValue: 2))
        let state = stageStore.state()
        let source = state.scopes.first { $0.displayID == display && $0.desktopID == DesktopID(rawValue: 1) }
        let target = state.scopes.first { $0.displayID == display && $0.desktopID == DesktopID(rawValue: 2) }

        #expect(result.changed)
        #expect(writer.requestedFrames[left.id] == Rect(x: 999, y: 499, width: 495, height: 500))
        #expect(source?.memberIDs(in: StageID(rawValue: "1")) == [])
        #expect(target?.memberIDs(in: StageID(rawValue: "1")) == [left.id])
        #expect(state.currentDesktopID(for: display) == DesktopID(rawValue: 1))
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func desktopLabelPersistsAndAppearsInList() {
        let display = DisplayID(rawValue: "display-a")
        let displaySnapshot = DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-desktop-label-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [displaySnapshot], windowSnapshots: []),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            stageStore: stageStore
        )

        let labelResult = DesktopCommandService(service: service, store: stageStore).label(DesktopID(rawValue: 2), as: "Research")
        let listResult = DesktopCommandService(service: service, store: stageStore).list()
        let state = stageStore.state()

        #expect(labelResult.changed)
        #expect(state.label(displayID: display, desktopID: DesktopID(rawValue: 2)) == "Research")
        #expect(listResult.message.contains("2\tResearch"))
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func displayFocusPersistsActiveDisplayAndRestoresFocusedStageWindow() {
        let leftDisplay = DisplayID(rawValue: "display-a")
        let rightDisplay = DisplayID(rawValue: "display-b")
        let leftSnapshot = DisplaySnapshot(id: leftDisplay, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let rightSnapshot = DisplaySnapshot(id: rightDisplay, index: 2, name: "B", frame: Rect(x: 1000, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 1000, y: 0, width: 1000, height: 500), isMain: false)
        let left = WindowSnapshot(id: WindowID(rawValue: 1), pid: 1, appName: "A", bundleID: "a", title: "left", frame: Rect(x: 0, y: 0, width: 500, height: 500), isOnScreen: true, isTileCandidate: true)
        let right = WindowSnapshot(id: WindowID(rawValue: 2), pid: 2, appName: "B", bundleID: "b", title: "right", frame: Rect(x: 1000, y: 0, width: 500, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-display-focus-\(UUID().uuidString).json")
            .path
        let eventPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-display-focus-\(UUID().uuidString).jsonl")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: leftDisplay, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: left.id, members: [
                    PersistentStageMember(windowID: left.id, bundleID: left.bundleID, title: left.title, frame: left.frame),
                ]),
            ]),
            PersistentStageScope(displayID: rightDisplay, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: right.id, members: [
                    PersistentStageMember(windowID: right.id, bundleID: right.bundleID, title: right.title, frame: right.frame),
                ]),
            ]),
        ]))
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [leftSnapshot, rightSnapshot], windowSnapshots: [left, right], focusedID: right.id),
            frameWriter: writer,
            config: RoadieConfig(),
            stageStore: stageStore
        )

        let result = DisplayCommandService(service: service, store: stageStore, events: EventLog(path: eventPath)).focus(index: 2)
        let state = stageStore.state()
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""

        #expect(result.changed)
        #expect(state.activeDisplayID == rightDisplay)
        #expect(writer.focusedWindowIDs == [right.id])
        #expect(events.contains("\"type\":\"display_focus\""))
        #expect(events.contains("\"displayID\":\"display-b\""))
        try? FileManager.default.removeItem(atPath: stagePath)
        try? FileManager.default.removeItem(atPath: eventPath)
    }

    @Test
    func displayTopologyFindsDirectionalNeighborByGeometry() {
        let center = DisplaySnapshot(id: DisplayID(rawValue: "center"), index: 1, name: "Center", frame: Rect(x: 0, y: 0, width: 1000, height: 800), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 800), isMain: true)
        let right = DisplaySnapshot(id: DisplayID(rawValue: "right"), index: 2, name: "Right", frame: Rect(x: 1000, y: 0, width: 1200, height: 800), visibleFrame: Rect(x: 1000, y: 0, width: 1200, height: 800), isMain: false)
        let upper = DisplaySnapshot(id: DisplayID(rawValue: "upper"), index: 3, name: "Upper", frame: Rect(x: 200, y: -900, width: 800, height: 900), visibleFrame: Rect(x: 200, y: -900, width: 800, height: 900), isMain: false)
        let farRight = DisplaySnapshot(id: DisplayID(rawValue: "far-right"), index: 4, name: "Far Right", frame: Rect(x: 2400, y: 300, width: 1000, height: 800), visibleFrame: Rect(x: 2400, y: 300, width: 1000, height: 800), isMain: false)

        #expect(DisplayTopology.neighbor(from: center, direction: .right, in: [center, farRight, right, upper])?.id == right.id)
        #expect(DisplayTopology.neighbor(from: center, direction: .up, in: [center, farRight, right, upper])?.id == upper.id)
        #expect(DisplayTopology.neighbor(from: center, direction: .left, in: [center, farRight, right, upper]) == nil)
    }

    @Test
    func displayTopologyRejectsMostlyDiagonalNeighbors() {
        let builtIn = DisplaySnapshot(
            id: DisplayID(rawValue: "built-in"),
            index: 1,
            name: "Built-in",
            frame: Rect(x: 0, y: 0, width: 2048, height: 1280),
            visibleFrame: Rect(x: 0, y: 30, width: 2048, height: 1250),
            isMain: true
        )
        let diagonalUpperRight = DisplaySnapshot(
            id: DisplayID(rawValue: "lg"),
            index: 2,
            name: "LG",
            frame: Rect(x: 2048, y: -964, width: 3840, height: 2160),
            visibleFrame: Rect(x: 2048, y: -934, width: 3840, height: 2130),
            isMain: false
        )

        #expect(DisplayTopology.neighbor(from: builtIn, direction: .up, in: [builtIn, diagonalUpperRight]) == nil)
        #expect(DisplayTopology.neighbor(from: builtIn, direction: .right, in: [builtIn, diagonalUpperRight])?.id == diagonalUpperRight.id)
    }

    @Test
    func directionalDisplayFocusUsesAdjacentDisplay() {
        let leftDisplay = DisplayID(rawValue: "display-a")
        let rightDisplay = DisplayID(rawValue: "display-b")
        let leftSnapshot = DisplaySnapshot(id: leftDisplay, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let rightSnapshot = DisplaySnapshot(id: rightDisplay, index: 2, name: "B", frame: Rect(x: 1000, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 1000, y: 0, width: 1000, height: 500), isMain: false)
        let left = WindowSnapshot(id: WindowID(rawValue: 1), pid: 1, appName: "A", bundleID: "a", title: "left", frame: Rect(x: 0, y: 0, width: 500, height: 500), isOnScreen: true, isTileCandidate: true)
        let right = WindowSnapshot(id: WindowID(rawValue: 2), pid: 2, appName: "B", bundleID: "b", title: "right", frame: Rect(x: 1000, y: 0, width: 500, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-display-direction-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: leftDisplay, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: left.id, members: [
                    PersistentStageMember(windowID: left.id, bundleID: left.bundleID, title: left.title, frame: left.frame),
                ]),
            ]),
            PersistentStageScope(displayID: rightDisplay, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: right.id, members: [
                    PersistentStageMember(windowID: right.id, bundleID: right.bundleID, title: right.title, frame: right.frame),
                ]),
            ]),
        ], activeDisplayID: leftDisplay))
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [leftSnapshot, rightSnapshot], windowSnapshots: [left, right], focusedID: left.id),
            frameWriter: writer,
            config: RoadieConfig(),
            stageStore: stageStore
        )

        let result = DisplayCommandService(service: service, store: stageStore).focus(.right)

        #expect(result.changed)
        #expect(stageStore.state().activeDisplayID == rightDisplay)
        #expect(writer.focusedWindowIDs == [right.id])
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func directionalWindowMoveFallsThroughToAdjacentDisplayAtStageEdge() {
        let leftDisplay = DisplayID(rawValue: "display-a")
        let rightDisplay = DisplayID(rawValue: "display-b")
        let leftSnapshot = DisplaySnapshot(id: leftDisplay, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let rightSnapshot = DisplaySnapshot(id: rightDisplay, index: 2, name: "B", frame: Rect(x: 1000, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 1000, y: 0, width: 1000, height: 500), isMain: false)
        let moving = WindowSnapshot(id: WindowID(rawValue: 1), pid: 1, appName: "A", bundleID: "a", title: "moving", frame: Rect(x: 0, y: 0, width: 1000, height: 500), isOnScreen: true, isTileCandidate: true)
        let target = WindowSnapshot(id: WindowID(rawValue: 2), pid: 2, appName: "B", bundleID: "b", title: "target", frame: Rect(x: 1000, y: 0, width: 1000, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-window-display-edge-\(UUID().uuidString).json")
            .path
        let intentPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-window-display-edge-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: leftDisplay, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: moving.id, members: [
                    PersistentStageMember(windowID: moving.id, bundleID: moving.bundleID, title: moving.title, frame: moving.frame),
                ]),
            ]),
            PersistentStageScope(displayID: rightDisplay, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: target.id, members: [
                    PersistentStageMember(windowID: target.id, bundleID: target.bundleID, title: target.title, frame: target.frame),
                ]),
            ]),
        ], activeDisplayID: leftDisplay))
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [leftSnapshot, rightSnapshot], windowSnapshots: [moving, target], focusedID: moving.id),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            intentStore: LayoutIntentStore(path: intentPath),
            stageStore: stageStore
        )

        let result = WindowCommandService(service: service, stageStore: stageStore).move(.right)
        let rightScope = stageStore.state().scopes.first { $0.displayID == rightDisplay }

        #expect(result.changed)
        #expect(rightScope?.memberIDs(in: StageID(rawValue: "1")) == [target.id, moving.id])
        #expect(writer.focusedWindowIDs == [moving.id])
        try? FileManager.default.removeItem(atPath: stagePath)
        try? FileManager.default.removeItem(atPath: intentPath)
    }

    @Test
    func directionalWindowFocusChoosesGeometricEntryWindowOnAdjacentDisplay() {
        let leftDisplay = DisplayID(rawValue: "display-a")
        let rightDisplay = DisplayID(rawValue: "display-b")
        let leftSnapshot = DisplaySnapshot(id: leftDisplay, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 800), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 800), isMain: true)
        let rightSnapshot = DisplaySnapshot(id: rightDisplay, index: 2, name: "B", frame: Rect(x: 1000, y: -400, width: 1600, height: 1200), visibleFrame: Rect(x: 1000, y: -400, width: 1600, height: 1200), isMain: false)
        let source = WindowSnapshot(id: WindowID(rawValue: 1), pid: 1, appName: "Terminal", bundleID: "term", title: "source", frame: Rect(x: 0, y: 0, width: 1000, height: 800), isOnScreen: true, isTileCandidate: true)
        let lowerLeft = WindowSnapshot(id: WindowID(rawValue: 2), pid: 2, appName: "Terminal", bundleID: "term", title: "lower-left", frame: Rect(x: 1000, y: 400, width: 800, height: 400), isOnScreen: true, isTileCandidate: true)
        let lowerRight = WindowSnapshot(id: WindowID(rawValue: 3), pid: 3, appName: "Grayjay", bundleID: "grayjay", title: "lower-right", frame: Rect(x: 1800, y: 400, width: 800, height: 400), isOnScreen: true, isTileCandidate: true)
        let upperLeft = WindowSnapshot(id: WindowID(rawValue: 4), pid: 4, appName: "Browser", bundleID: "browser", title: "upper-left", frame: Rect(x: 1000, y: -400, width: 800, height: 400), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-window-focus-entry-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: leftDisplay, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: source.id, members: [
                    PersistentStageMember(windowID: source.id, bundleID: source.bundleID, title: source.title, frame: source.frame),
                ]),
            ]),
            PersistentStageScope(displayID: rightDisplay, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: lowerRight.id, members: [
                    PersistentStageMember(windowID: lowerLeft.id, bundleID: lowerLeft.bundleID, title: lowerLeft.title, frame: lowerLeft.frame),
                    PersistentStageMember(windowID: lowerRight.id, bundleID: lowerRight.bundleID, title: lowerRight.title, frame: lowerRight.frame),
                    PersistentStageMember(windowID: upperLeft.id, bundleID: upperLeft.bundleID, title: upperLeft.title, frame: upperLeft.frame),
                ]),
            ]),
        ], activeDisplayID: leftDisplay))
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [leftSnapshot, rightSnapshot], windowSnapshots: [source, lowerLeft, lowerRight, upperLeft], focusedID: source.id),
            frameWriter: writer,
            config: RoadieConfig(),
            stageStore: stageStore
        )

        let result = WindowCommandService(service: service, stageStore: stageStore).focus(.right)

        #expect(result.changed)
        #expect(writer.focusedWindowIDs == [lowerLeft.id])
        #expect(stageStore.state().activeDisplayID == rightDisplay)
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func directionalWindowFocusAcrossOffsetDisplaysFollowsVisualOverlap() {
        let builtInDisplay = DisplayID(rawValue: "built-in")
        let externalDisplay = DisplayID(rawValue: "external")
        let builtIn = DisplaySnapshot(
            id: builtInDisplay,
            index: 1,
            name: "Built-in",
            frame: Rect(x: 0, y: 0, width: 2048, height: 1280),
            visibleFrame: Rect(x: 0, y: 0, width: 2048, height: 1280),
            isMain: true
        )
        let external = DisplaySnapshot(
            id: externalDisplay,
            index: 2,
            name: "External",
            frame: Rect(x: 2048, y: -964, width: 3840, height: 2160),
            visibleFrame: Rect(x: 2048, y: -964, width: 3840, height: 2160),
            isMain: false
        )
        let source = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 1,
            appName: "BlueJay",
            bundleID: "bluejay",
            title: "Grayjay",
            frame: Rect(x: 2198, y: 110, width: 1836, height: 1026),
            isOnScreen: true,
            isTileCandidate: true
        )
        let topRight = WindowSnapshot(
            id: WindowID(rawValue: 2),
            pid: 2,
            appName: "iTerm2",
            bundleID: "iterm",
            title: "Nettoyer et liberer",
            frame: Rect(x: 1100, y: 38, width: 940, height: 586),
            isOnScreen: true,
            isTileCandidate: true
        )
        let bottomRight = WindowSnapshot(
            id: WindowID(rawValue: 3),
            pid: 3,
            appName: "iTerm2",
            bundleID: "iterm",
            title: "SIP",
            frame: Rect(x: 1100, y: 634, width: 940, height: 586),
            isOnScreen: true,
            isTileCandidate: true
        )
        let topLeft = WindowSnapshot(
            id: WindowID(rawValue: 4),
            pid: 4,
            appName: "iTerm2",
            bundleID: "iterm",
            title: "Shell",
            frame: Rect(x: 150, y: 38, width: 940, height: 586),
            isOnScreen: true,
            isTileCandidate: true
        )
        let externalScope = StageScope(displayID: externalDisplay, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "2"))
        let builtInScope = StageScope(displayID: builtInDisplay, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "4"))
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-window-focus-offset-display-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: externalDisplay, desktopID: externalScope.desktopID, activeStageID: externalScope.stageID, stages: [
                PersistentStage(id: externalScope.stageID, focusedWindowID: source.id, members: [
                    PersistentStageMember(windowID: source.id, bundleID: source.bundleID, title: source.title, frame: source.frame),
                ]),
            ]),
            PersistentStageScope(displayID: builtInDisplay, desktopID: builtInScope.desktopID, activeStageID: builtInScope.stageID, stages: [
                PersistentStage(id: builtInScope.stageID, focusedWindowID: topRight.id, members: [
                    PersistentStageMember(windowID: topRight.id, bundleID: topRight.bundleID, title: topRight.title, frame: topRight.frame),
                    PersistentStageMember(windowID: bottomRight.id, bundleID: bottomRight.bundleID, title: bottomRight.title, frame: bottomRight.frame),
                    PersistentStageMember(windowID: topLeft.id, bundleID: topLeft.bundleID, title: topLeft.title, frame: topLeft.frame),
                ]),
            ]),
        ], activeDisplayID: externalDisplay))
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [builtIn, external], windowSnapshots: [source, topRight, bottomRight, topLeft], focusedID: source.id),
            frameWriter: writer,
            config: RoadieConfig(),
            stageStore: stageStore
        )

        let result = WindowCommandService(service: service, stageStore: stageStore).focus(.left)

        #expect(result.changed)
        #expect(writer.focusedWindowIDs == [topRight.id])
        #expect(stageStore.state().activeDisplayID == builtInDisplay)
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func focusFollowsMousePickerTargetsActiveStageWindowAtPoint() {
        let display = DisplayID(rawValue: "display-a")
        let scope = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let inactiveScope = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "2"))
        var state = RoadieState()
        state.ensureDisplay(display)
        try? state.createStage(id: scope.stageID, name: "Active", in: display, desktopID: scope.desktopID)
        try? state.createStage(id: inactiveScope.stageID, name: "Inactive", in: display, desktopID: inactiveScope.desktopID)
        try? state.switchStage(scope.stageID, in: display, desktopID: scope.desktopID)
        let active = WindowSnapshot(id: WindowID(rawValue: 1), pid: 1, appName: "A", bundleID: "a", title: "active", frame: Rect(x: 0, y: 0, width: 100, height: 100), isOnScreen: true, isTileCandidate: true)
        let inactive = WindowSnapshot(id: WindowID(rawValue: 2), pid: 2, appName: "B", bundleID: "b", title: "inactive", frame: Rect(x: 0, y: 0, width: 80, height: 80), isOnScreen: true, isTileCandidate: true)
        try? state.assignWindow(active.id, to: scope)
        try? state.assignWindow(inactive.id, to: inactiveScope)
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [],
            windows: [
                ScopedWindowSnapshot(window: active, scope: scope),
                ScopedWindowSnapshot(window: inactive, scope: inactiveScope),
            ],
            state: state
        )

        let target = FocusFollowsMousePicker.targetWindow(at: CGPoint(x: 40, y: 40), in: snapshot)

        #expect(target?.window.id == active.id)
    }

    @Test
    func stageCreateRenameReorderListAndDeleteEmptyInactiveStage() {
        let display = DisplayID(rawValue: "display-a")
        let displaySnapshot = DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let window = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "left", frame: Rect(x: 0, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-stage-crud-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [displaySnapshot], windowSnapshots: [window], focusedID: window.id),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            stageStore: stageStore
        )
        let commands = StageCommandService(service: service, store: stageStore)

        let create = commands.create("9", name: "Scratch")
        let rename = commands.rename("9", to: "Inbox")
        let reorder = commands.reorder("9", to: 1)
        let list = commands.list()
        let deleteActive = commands.delete("1")
        let deleteCreated = commands.delete("9")
        let scope = stageStore.state().scopes.first { $0.displayID == display }

        #expect(create.changed)
        #expect(rename.changed)
        #expect(reorder.changed)
        #expect(list.message.split(separator: "\n").dropFirst().first?.contains("\t9\tbsp\t0\tInbox") == true)
        #expect(list.message.contains("9\tbsp\t0\tInbox"))
        #expect(!deleteActive.changed)
        #expect(deleteCreated.changed)
        #expect(scope?.stages.contains(where: { $0.id == StageID(rawValue: "9") }) == false)
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func stageRenameWithDisplayIDRenamesClickedDisplayStageOnly() {
        let activeDisplay = DisplayID(rawValue: "display-a")
        let clickedDisplay = DisplayID(rawValue: "display-b")
        let stageID = StageID(rawValue: "2")
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-stage-rename-display-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: activeDisplay, activeStageID: stageID, stages: [
                PersistentStage(id: stageID, name: "Active Display Stage"),
            ]),
            PersistentStageScope(displayID: clickedDisplay, activeStageID: stageID, stages: [
                PersistentStage(id: stageID, name: "Clicked Display Stage"),
            ]),
        ], activeDisplayID: activeDisplay))
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [
                DisplaySnapshot(id: activeDisplay, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                DisplaySnapshot(id: clickedDisplay, index: 2, name: "B", frame: Rect(x: 1000, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 1000, y: 0, width: 1000, height: 500), isMain: false),
            ], windowSnapshots: []),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            stageStore: stageStore
        )
        let commands = StageCommandService(service: service, store: stageStore)

        let result = commands.rename(stageID.rawValue, to: "Renamed From Rail", displayID: clickedDisplay)
        let state = stageStore.state()
        let activeScope = state.scopes.first { $0.displayID == activeDisplay }
        let clickedScope = state.scopes.first { $0.displayID == clickedDisplay }

        #expect(result.changed)
        #expect(activeScope?.stages.first { $0.id == stageID }?.name == "Active Display Stage")
        #expect(clickedScope?.stages.first { $0.id == stageID }?.name == "Renamed From Rail")
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func stageCommandsUseCurrentDesktopScope() {
        let display = DisplayID(rawValue: "display-a")
        let displaySnapshot = DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let window = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "left", frame: Rect(x: 0, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-stage-current-desktop-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: display, desktopID: DesktopID(rawValue: 1), activeStageID: StageID(rawValue: "1")),
                PersistentStageScope(displayID: display, desktopID: DesktopID(rawValue: 2), activeStageID: StageID(rawValue: "1")),
            ],
            desktopSelections: [PersistentDesktopSelection(displayID: display, currentDesktopID: DesktopID(rawValue: 2))]
        ))
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [displaySnapshot], windowSnapshots: [window], focusedID: window.id),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            stageStore: stageStore
        )
        let commands = StageCommandService(service: service, store: stageStore)

        _ = commands.create("9", name: "D2")
        _ = commands.assign("9")
        let state = stageStore.state()
        let desktop1 = state.scopes.first { $0.displayID == display && $0.desktopID == DesktopID(rawValue: 1) }
        let desktop2 = state.scopes.first { $0.displayID == display && $0.desktopID == DesktopID(rawValue: 2) }

        #expect(desktop1?.stages.contains(where: { $0.id == StageID(rawValue: "9") }) == false)
        #expect(desktop2?.stages.contains(where: { $0.id == StageID(rawValue: "9") }) == true)
        #expect(desktop2?.memberIDs(in: StageID(rawValue: "9")) == [window.id])
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func snapshotPrunesClosedWindowsFromPersistentStages() {
        let display = DisplayID(rawValue: "display-a")
        let displaySnapshot = DisplaySnapshot(
            id: display,
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let live = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 10,
            appName: "A",
            bundleID: "a",
            title: "live",
            frame: Rect(x: 0, y: 0, width: 495, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        let closed = WindowID(rawValue: 2)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-prune-stages-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(
                displayID: display,
                stages: [
                    PersistentStage(id: StageID(rawValue: "1"), members: [
                        PersistentStageMember(windowID: live.id, bundleID: live.bundleID, title: live.title, frame: live.frame),
                        PersistentStageMember(windowID: closed, bundleID: "gone", title: "closed", frame: Rect(x: 505, y: 0, width: 495, height: 500)),
                    ]),
                ]
            ),
        ]))
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [displaySnapshot], windowSnapshots: [live], focusedID: live.id),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            stageStore: stageStore
        )

        _ = service.snapshot()

        let scope = stageStore.state().scopes.first { $0.displayID == display }
        #expect(scope?.memberIDs(in: StageID(rawValue: "1")) == [live.id])
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func snapshotPrunesDisconnectedActiveDisplay() {
        let liveDisplay = DisplayID(rawValue: "display-live")
        let staleDisplay = DisplayID(rawValue: "display-stale")
        let displaySnapshot = DisplaySnapshot(id: liveDisplay, index: 1, name: "Live", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-prune-display-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(activeDisplayID: staleDisplay))
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [displaySnapshot], windowSnapshots: []),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            stageStore: stageStore
        )

        _ = service.snapshot()

        #expect(stageStore.state().activeDisplayID == liveDisplay)
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func snapshotPrunesLayoutIntentsForDisconnectedDisplays() {
        let liveDisplay = DisplayID(rawValue: "display-live")
        let staleDisplay = DisplayID(rawValue: "display-stale")
        let liveScope = StageScope(displayID: liveDisplay, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let staleScope = StageScope(displayID: staleDisplay, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let displaySnapshot = DisplaySnapshot(id: liveDisplay, index: 1, name: "Live", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let intentPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-prune-intents-\(UUID().uuidString).json")
            .path
        let intentStore = LayoutIntentStore(path: intentPath)
        intentStore.save(LayoutIntent(scope: liveScope, windowIDs: [WindowID(rawValue: 1)], placements: [:]))
        intentStore.save(LayoutIntent(scope: staleScope, windowIDs: [WindowID(rawValue: 2)], placements: [:]))
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [displaySnapshot], windowSnapshots: []),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            intentStore: intentStore
        )

        _ = service.snapshot()

        #expect(intentStore.intent(for: liveScope) != nil)
        #expect(intentStore.intent(for: staleScope) == nil)
        try? FileManager.default.removeItem(atPath: intentPath)
    }

    @Test
    func eventLogAppendsJsonLines() throws {
        let eventPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-events-\(UUID().uuidString).jsonl")
            .path
        let log = EventLog(path: eventPath)

        log.append(RoadieEvent(type: "one", details: ["value": "1"]))
        log.append(RoadieEvent(type: "two"))

        let lines = try String(contentsOfFile: eventPath, encoding: .utf8)
            .split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].contains("\"type\":\"one\""))
        #expect(lines[1].contains("\"type\":\"two\""))
        #expect(log.tail(limit: 1).count == 1)
        #expect(log.tail(limit: 1).first?.contains("\"type\":\"two\"") == true)
        try? FileManager.default.removeItem(atPath: eventPath)
    }

    @Test
    func selfTestPassesForHealthySnapshot() {
        let display = DisplayID(rawValue: "display-a")
        let displaySnapshot = DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-self-test-ok-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(activeDisplayID: display))
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [displaySnapshot], windowSnapshots: []),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            stageStore: stageStore
        )

        let report = SelfTestService(service: service, stageStore: stageStore).run()

        #expect(!report.failed)
        #expect(report.checks.contains(SelfTestCheck(level: .ok, name: "accessibility", message: "accessibilityTrusted=true")))
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func snapshotKeepsDisconnectedDisplayScopesWithoutFallbackReassign() {
        let liveDisplay = DisplayID(rawValue: "display-live")
        let staleDisplay = DisplayID(rawValue: "display-stale")
        let desktop = DesktopID(rawValue: 1)
        let displaySnapshot = DisplaySnapshot(
            id: liveDisplay,
            index: 1,
            name: "Built-in",
            frame: Rect(x: 0, y: 0, width: 1000, height: 600),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 600),
            isMain: true
        )
        let liveWindow = WindowSnapshot(id: WindowID(rawValue: 10), pid: 10, appName: "Terminal", bundleID: "term", title: "live", frame: Rect(x: 0, y: 0, width: 500, height: 600), isOnScreen: true, isTileCandidate: true)
        let movedWindow = WindowSnapshot(id: WindowID(rawValue: 20), pid: 20, appName: "Firefox", bundleID: "firefox", title: "moved", frame: Rect(x: 500, y: 0, width: 500, height: 600), isOnScreen: true, isTileCandidate: true)
        let hiddenWindow = WindowSnapshot(id: WindowID(rawValue: 30), pid: 30, appName: "Terminal", bundleID: "term", title: "hidden", frame: Rect(x: 999, y: 599, width: 500, height: 400), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-disconnected-display-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: liveDisplay, desktopID: desktop, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), members: [
                        PersistentStageMember(windowID: liveWindow.id, bundleID: liveWindow.bundleID, title: liveWindow.title, frame: liveWindow.frame),
                    ]),
                ]),
                PersistentStageScope(displayID: staleDisplay, desktopID: desktop, activeStageID: StageID(rawValue: "2"), stages: [
                    PersistentStage(id: StageID(rawValue: "2"), members: [
                        PersistentStageMember(windowID: movedWindow.id, bundleID: movedWindow.bundleID, title: movedWindow.title, frame: movedWindow.frame),
                    ]),
                    PersistentStage(id: StageID(rawValue: "4"), members: [
                        PersistentStageMember(windowID: hiddenWindow.id, bundleID: hiddenWindow.bundleID, title: hiddenWindow.title, frame: hiddenWindow.frame),
                    ]),
                ]),
            ],
            desktopSelections: [
                PersistentDesktopSelection(displayID: liveDisplay, currentDesktopID: desktop),
                PersistentDesktopSelection(displayID: staleDisplay, currentDesktopID: desktop),
            ],
            desktopLabels: [
                PersistentDesktopLabel(displayID: staleDisplay, desktopID: desktop, label: "External"),
            ],
            activeDisplayID: staleDisplay
        ))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [displaySnapshot],
                windowSnapshots: [liveWindow, movedWindow, hiddenWindow],
                focusedID: movedWindow.id
            ),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            stageStore: stageStore
        )

        _ = service.snapshot()
        let updated = stageStore.state()
        let liveScope = updated.scopes.first { $0.displayID == liveDisplay && $0.desktopID == desktop }
        let staleScope = updated.scopes.first { $0.displayID == staleDisplay && $0.desktopID == desktop }

        #expect(updated.scopes.contains { $0.displayID == staleDisplay })
        #expect(updated.desktopSelections.contains { $0.displayID == staleDisplay })
        #expect(updated.desktopLabels.contains { $0.displayID == staleDisplay && $0.label == "External" })
        #expect(updated.activeDisplayID == liveDisplay)
        #expect(liveScope?.memberIDs(in: StageID(rawValue: "1")) == [liveWindow.id])
        #expect(staleScope?.memberIDs(in: StageID(rawValue: "2")) == [movedWindow.id])
        #expect(staleScope?.memberIDs(in: StageID(rawValue: "4")) == [hiddenWindow.id])
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func snapshotKeepsDisconnectedDisplayScopesWithoutContainingDisplayReassign() {
        let displayA = DisplayID(rawValue: "display-a")
        let displayB = DisplayID(rawValue: "display-b")
        let staleDisplay = DisplayID(rawValue: "display-stale")
        let desktop = DesktopID(rawValue: 1)
        let first = DisplaySnapshot(id: displayA, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 600), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 600), isMain: true)
        let second = DisplaySnapshot(id: displayB, index: 2, name: "B", frame: Rect(x: 1000, y: 0, width: 1000, height: 600), visibleFrame: Rect(x: 1000, y: 0, width: 1000, height: 600), isMain: false)
        let window = WindowSnapshot(id: WindowID(rawValue: 40), pid: 40, appName: "Terminal", bundleID: "term", title: "migrated", frame: Rect(x: 1000, y: 0, width: 500, height: 600), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-disconnected-display-active-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: displayA, desktopID: desktop, activeStageID: StageID(rawValue: "1")),
                PersistentStageScope(displayID: displayB, desktopID: desktop, activeStageID: StageID(rawValue: "1")),
                PersistentStageScope(displayID: staleDisplay, desktopID: desktop, activeStageID: StageID(rawValue: "3"), stages: [
                    PersistentStage(id: StageID(rawValue: "3"), members: [
                        PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
                    ]),
                ]),
            ],
            activeDisplayID: displayB
        ))
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [first, second], windowSnapshots: [window], focusedID: window.id),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            stageStore: stageStore
        )

        _ = service.snapshot()
        let updated = stageStore.state()
        let scopeA = updated.scopes.first { $0.displayID == displayA && $0.desktopID == desktop }
        let scopeB = updated.scopes.first { $0.displayID == displayB && $0.desktopID == desktop }
        let staleScope = updated.scopes.first { $0.displayID == staleDisplay && $0.desktopID == desktop }

        #expect(updated.scopes.contains { $0.displayID == staleDisplay })
        #expect(updated.activeDisplayID == displayB)
        #expect(scopeA?.memberIDs(in: StageID(rawValue: "3")).isEmpty ?? true)
        #expect(scopeB?.memberIDs(in: StageID(rawValue: "1")).isEmpty == true)
        #expect(staleScope?.memberIDs(in: StageID(rawValue: "3")) == [window.id])
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func snapshotCreatesEmptyScopeForNewlyConnectedDisplay() {
        let existingDisplay = DisplayID(rawValue: "display-existing")
        let newDisplay = DisplayID(rawValue: "display-new")
        let desktop = DesktopID(rawValue: 1)
        let first = DisplaySnapshot(id: existingDisplay, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 600), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 600), isMain: true)
        let second = DisplaySnapshot(id: newDisplay, index: 2, name: "B", frame: Rect(x: 1000, y: 0, width: 1000, height: 600), visibleFrame: Rect(x: 1000, y: 0, width: 1000, height: 600), isMain: false)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-new-display-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: existingDisplay, desktopID: desktop, activeStageID: StageID(rawValue: "1")),
        ], activeDisplayID: existingDisplay))
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [first, second], windowSnapshots: []),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            stageStore: stageStore
        )

        _ = service.snapshot()
        let state = stageStore.state()
        let newScope = state.scopes.first { $0.displayID == newDisplay && $0.desktopID == desktop }

        #expect(newScope?.activeStageID == StageID(rawValue: "1"))
        #expect(newScope?.stages.map(\.id).contains(StageID(rawValue: "1")) == true)
        #expect(state.activeDisplayID == existingDisplay)
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func selfTestFailsWhenAccessibilityIsDenied() {
        let display = DisplayID(rawValue: "display-a")
        let displaySnapshot = DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let provider = FakeProvider(
            permissionSnapshot: PermissionSnapshot(accessibilityTrusted: false),
            displaySnapshots: [displaySnapshot],
            windowSnapshots: []
        )
        let service = SnapshotService(
            provider: provider,
            frameWriter: RecordingWriter(),
            config: RoadieConfig()
        )

        let report = SelfTestService(service: service).run()

        #expect(report.failed)
        #expect(report.checks.contains(SelfTestCheck(level: .fail, name: "accessibility", message: "accessibilityTrusted=false")))
    }

    @Test
    func selfTestWarnsOnTinyLiveTiles() {
        let display = DisplayID(rawValue: "display-a")
        let scope = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let displaySnapshot = DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 2048, height: 1280), visibleFrame: Rect(x: 0, y: 30, width: 2048, height: 1250), isMain: true)
        let normal = WindowSnapshot(id: WindowID(rawValue: 1), pid: 1, appName: "A", bundleID: "a", title: "normal", frame: Rect(x: 0, y: 30, width: 1000, height: 1190), isOnScreen: true, isTileCandidate: true)
        let tiny = WindowSnapshot(id: WindowID(rawValue: 2), pid: 2, appName: "B", bundleID: "b", title: "tiny", frame: Rect(x: 1010, y: 30, width: 1000, height: 122), isOnScreen: true, isTileCandidate: true)
        var state = PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: scope.stageID, stages: [
                PersistentStage(id: scope.stageID, members: [
                    PersistentStageMember(windowID: normal.id, bundleID: normal.bundleID, title: normal.title, frame: normal.frame),
                    PersistentStageMember(windowID: tiny.id, bundleID: tiny.bundleID, title: tiny.title, frame: tiny.frame),
                ]),
            ]),
        ])
        state.focusDisplay(display)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-self-test-tiny-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(state)
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [displaySnapshot], windowSnapshots: [normal, tiny]),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            stageStore: stageStore
        )

        let report = SelfTestService(service: service, stageStore: stageStore).run()

        #expect(report.checks.contains(SelfTestCheck(level: .warn, name: "tile-sizes", message: "tinyTiles=1")))
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func stateAuditPassesForHealthyState() {
        let display = DisplayID(rawValue: "display-a")
        let window = WindowSnapshot(id: WindowID(rawValue: 1), pid: 1, appName: "A", bundleID: "a", title: "one", frame: Rect(x: 0, y: 0, width: 1000, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-audit-ok-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: window.id, members: [
                    PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
                ]),
            ]),
        ], activeDisplayID: display))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                ],
                windowSnapshots: [window],
                focusedID: window.id
            ),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            stageStore: stageStore
        )

        let report = StateAuditService(service: service, stageStore: stageStore).run()

        #expect(!report.failed)
        #expect(report.checks.contains(StateAuditCheck(level: .ok, name: "duplicate-membership", message: "windows=0")))
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func stateAuditFailsOnDuplicateMembership() {
        let display = DisplayID(rawValue: "display-a")
        let window = WindowSnapshot(id: WindowID(rawValue: 1), pid: 1, appName: "A", bundleID: "a", title: "one", frame: Rect(x: 0, y: 0, width: 1000, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-audit-bad-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: WindowID(rawValue: 99), members: [
                    PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "2"), members: [
                    PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
                ]),
            ]),
        ], activeDisplayID: display))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                ],
                windowSnapshots: [window],
                focusedID: window.id
            ),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            stageStore: stageStore
        )

        let report = StateAuditService(service: service, stageStore: stageStore).run()

        #expect(report.failed)
        #expect(report.checks.contains(StateAuditCheck(level: .fail, name: "duplicate-membership", message: "windows=1")))
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func parkedStagesAreWarnNotFail() {
        let display = DisplayID(rawValue: "display-a")
        let staleDisplay = DisplayID(rawValue: "display-stale")
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-audit-parked-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        let logicalID = LogicalDisplayID(displayID: staleDisplay)
        let origin = StageOrigin(
            logicalDisplayID: logicalID,
            displayID: staleDisplay,
            desktopID: DesktopID(rawValue: 1),
            stageID: StageID(rawValue: "docs"),
            position: 1,
            nameAtParking: "Docs",
            parkedAt: Date()
        )
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1")),
            PersistentStageScope(displayID: staleDisplay, logicalDisplayID: logicalID, stages: [
                PersistentStage(id: StageID(rawValue: "docs"), name: "Docs", parkingState: .parked, origin: origin, hostDisplayID: display),
            ]),
        ], activeDisplayID: display))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                ],
                windowSnapshots: [],
                focusedID: nil
            ),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            stageStore: stageStore
        )

        let report = StateAuditService(service: service, stageStore: stageStore).run()

        #expect(!report.failed)
        #expect(report.checks.contains(StateAuditCheck(level: .warn, name: "stale-scopes", message: "count=1")))
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func lostWindowRiskFailsOnlyWhenUnrecoverable() {
        let display = DisplayID(rawValue: "display-a")
        let window = WindowSnapshot(id: WindowID(rawValue: 1), pid: 1, appName: "A", bundleID: "a", title: "one", frame: Rect(x: 0, y: 0, width: 1000, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-audit-unrecoverable-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [
                    PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "2"), members: [
                    PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
                ]),
            ]),
        ], activeDisplayID: display))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                ],
                windowSnapshots: [window],
                focusedID: window.id
            ),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            stageStore: stageStore
        )

        let report = StateAuditService(service: service, stageStore: stageStore).run()

        #expect(report.failed)
        #expect(report.checks.contains(StateAuditCheck(level: .fail, name: "duplicate-membership", message: "windows=1")))
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func stateHealRepairsDuplicateStaleAndBrokenFocusState() {
        let display = DisplayID(rawValue: "display-a")
        let staleDisplay = DisplayID(rawValue: "display-stale")
        let live = WindowSnapshot(id: WindowID(rawValue: 1), pid: 1, appName: "A", bundleID: "a", title: "live", frame: Rect(x: 0, y: 0, width: 1000, height: 500), isOnScreen: true, isTileCandidate: true)
        let stale = WindowSnapshot(id: WindowID(rawValue: 2), pid: 2, appName: "B", bundleID: "b", title: "stale", frame: Rect(x: 0, y: 0, width: 1000, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-heal-bad-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "missing"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: WindowID(rawValue: 99), members: [
                        PersistentStageMember(windowID: live.id, bundleID: live.bundleID, title: live.title, frame: live.frame),
                        PersistentStageMember(windowID: stale.id, bundleID: stale.bundleID, title: stale.title, frame: stale.frame),
                    ]),
                    PersistentStage(id: StageID(rawValue: "2"), members: [
                        PersistentStageMember(windowID: live.id, bundleID: live.bundleID, title: live.title, frame: live.frame),
                    ]),
                ]),
                PersistentStageScope(displayID: staleDisplay, activeStageID: StageID(rawValue: "1")),
            ],
            desktopSelections: [
                PersistentDesktopSelection(displayID: display),
                PersistentDesktopSelection(displayID: staleDisplay),
            ],
            desktopLabels: [
                PersistentDesktopLabel(displayID: staleDisplay, desktopID: DesktopID(rawValue: 1), label: "Gone"),
            ],
            activeDisplayID: staleDisplay
        ))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                ],
                windowSnapshots: [live],
                focusedID: live.id
            ),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            stageStore: stageStore
        )

        let report = StateAuditService(service: service, stageStore: stageStore).heal()
        var healed = stageStore.state()
        let scope = healed.scope(displayID: display, desktopID: DesktopID(rawValue: 1))

        #expect(report.repaired > 0)
        #expect(!report.audit.failed)
        #expect(scope.activeStageID == StageID(rawValue: "1"))
        #expect(scope.memberIDs(in: StageID(rawValue: "1")) == [live.id])
        #expect(scope.memberIDs(in: StageID(rawValue: "2")).isEmpty)
        #expect(healed.desktopSelections.contains { $0.displayID == staleDisplay })
        #expect(healed.desktopLabels.contains { $0.displayID == staleDisplay && $0.label == "Gone" })
        #expect(healed.activeDisplayID == display)
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func daemonHealthReportsRunningPidAndHealthyState() throws {
        let display = DisplayID(rawValue: "display-a")
        let window = WindowSnapshot(id: WindowID(rawValue: 1), pid: 1, appName: "A", bundleID: "a", title: "one", frame: Rect(x: 0, y: 0, width: 1000, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-health-stage-\(UUID().uuidString).json")
            .path
        let pidPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-health-pid-\(UUID().uuidString).pid")
            .path
        try String(ProcessInfo.processInfo.processIdentifier).write(toFile: pidPath, atomically: true, encoding: .utf8)
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: window.id, members: [
                    PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
                ]),
            ]),
        ], activeDisplayID: display))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                ],
                windowSnapshots: [window],
                focusedID: window.id
            ),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            stageStore: stageStore
        )

        let report = DaemonHealthService(service: service, stageStore: stageStore, pidFilePath: pidPath).run()

        #expect(!report.failed)
        #expect(report.checks.contains(DaemonHealthCheck(level: .ok, name: "self-test", message: "failed=false")))
        #expect(report.checks.contains(DaemonHealthCheck(level: .ok, name: "state-audit", message: "failed=false")))
        try? FileManager.default.removeItem(atPath: stagePath)
        try? FileManager.default.removeItem(atPath: pidPath)
    }

    @Test
    func daemonHealthWarnsWhenPidfileIsMissing() {
        let display = DisplayID(rawValue: "display-a")
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-health-missing-\(UUID().uuidString).json")
            .path
        let missingPidPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-health-missing-\(UUID().uuidString).pid")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(activeDisplayID: display))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                ],
                windowSnapshots: []
            ),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            stageStore: stageStore
        )

        let report = DaemonHealthService(service: service, stageStore: stageStore, pidFilePath: missingPidPath).run()

        #expect(!report.failed)
        #expect(report.checks.contains(DaemonHealthCheck(level: .warn, name: "pidfile", message: "missing")))
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func daemonHealRepairsStateAndAppliesPendingLayout() throws {
        let display = DisplayID(rawValue: "display-a")
        let left = WindowSnapshot(id: WindowID(rawValue: 1), pid: 1, appName: "A", bundleID: "a", title: "left", frame: Rect(x: 0, y: 0, width: 300, height: 500), isOnScreen: true, isTileCandidate: true)
        let right = WindowSnapshot(id: WindowID(rawValue: 2), pid: 2, appName: "B", bundleID: "b", title: "right", frame: Rect(x: 300, y: 0, width: 300, height: 500), isOnScreen: true, isTileCandidate: true)
        let displaySnapshot = DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-daemon-heal-\(UUID().uuidString).json")
            .path
        let pidPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-daemon-heal-\(UUID().uuidString).pid")
            .path
        try String(ProcessInfo.processInfo.processIdentifier).write(toFile: pidPath, atomically: true, encoding: .utf8)
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [
                    PersistentStageMember(windowID: left.id, bundleID: left.bundleID, title: left.title, frame: left.frame),
                    PersistentStageMember(windowID: right.id, bundleID: right.bundleID, title: right.title, frame: right.frame),
                ]),
            ]),
        ], activeDisplayID: display))
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [displaySnapshot], windowSnapshots: [left, right], focusedID: left.id),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            stageStore: stageStore
        )

        let report = DaemonHealthService(service: service, stageStore: stageStore, pidFilePath: pidPath).heal()

        #expect(!report.failed)
        #expect(report.layout.attempted == 2)
        #expect(writer.requestedFrames[left.id] == Rect(x: 0, y: 0, width: 495, height: 500))
        #expect(writer.requestedFrames[right.id] == Rect(x: 505, y: 0, width: 495, height: 500))
        try? FileManager.default.removeItem(atPath: stagePath)
        try? FileManager.default.removeItem(atPath: pidPath)
    }

    @Test
    func metricsExposeRuntimeAndStateCounters() {
        let display = DisplayID(rawValue: "display-a")
        let staleDisplay = DisplayID(rawValue: "display-stale")
        let live = WindowSnapshot(id: WindowID(rawValue: 1), pid: 1, appName: "A", bundleID: "a", title: "live", frame: Rect(x: 0, y: 0, width: 300, height: 500), isOnScreen: true, isTileCandidate: true)
        let duplicate = WindowSnapshot(id: WindowID(rawValue: 2), pid: 2, appName: "B", bundleID: "b", title: "duplicate", frame: Rect(x: 300, y: 0, width: 300, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-metrics-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [
                    PersistentStageMember(windowID: live.id, bundleID: live.bundleID, title: live.title, frame: live.frame),
                    PersistentStageMember(windowID: duplicate.id, bundleID: duplicate.bundleID, title: duplicate.title, frame: duplicate.frame),
                    PersistentStageMember(windowID: WindowID(rawValue: 99), bundleID: "gone", title: "gone", frame: live.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "2"), members: [
                    PersistentStageMember(windowID: duplicate.id, bundleID: duplicate.bundleID, title: duplicate.title, frame: duplicate.frame),
                ]),
            ]),
            PersistentStageScope(displayID: staleDisplay),
        ], activeDisplayID: display))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                ],
                windowSnapshots: [live, duplicate],
                focusedID: live.id
            ),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            stageStore: stageStore
        )

        let metrics = MetricsService(service: service, stageStore: stageStore).collect()

        #expect(metrics.displays == 1)
        #expect(metrics.tileableWindows == 2)
        #expect(metrics.scopedWindows == 2)
        #expect(metrics.activeStages == 1)
        #expect(metrics.duplicateWindows == 1)
        #expect(metrics.staleMembers == 0)
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func snapshotPreservesDisconnectedDisplayMembershipUntilParkingHeal() {
        let hostDisplay = DisplayID(rawValue: "built-in")
        let goneDisplay = DisplayID(rawValue: "external")
        let liveDisplay = DisplaySnapshot(id: hostDisplay, index: 1, name: "Built-in", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let movedBySystem = WindowSnapshot(id: WindowID(rawValue: 10), pid: 10, appName: "A", bundleID: "a", title: "external-window", frame: Rect(x: 0, y: 0, width: 500, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-display-disconnect-preserve-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: hostDisplay, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), name: "Host"),
            ]),
            PersistentStageScope(displayID: goneDisplay, activeStageID: StageID(rawValue: "2"), stages: [
                PersistentStage(id: StageID(rawValue: "2"), name: "External", members: [
                    PersistentStageMember(windowID: movedBySystem.id, bundleID: movedBySystem.bundleID, title: movedBySystem.title, frame: Rect(x: 1000, y: 0, width: 500, height: 500)),
                ]),
            ]),
        ], activeDisplayID: hostDisplay))
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [liveDisplay], windowSnapshots: [movedBySystem], focusedID: nil),
            frameWriter: RecordingWriter(),
            stageStore: stageStore
        )

        let snapshot = service.snapshot(followFocus: false)
        var stateAfterSnapshot = stageStore.state()

        #expect(snapshot.windows.first { $0.window.id == movedBySystem.id }?.scope == nil)
        #expect(stateAfterSnapshot.scopes.first { $0.displayID == goneDisplay }?.memberIDs(in: StageID(rawValue: "2")) == [movedBySystem.id])
        #expect(stateAfterSnapshot.scopes.first { $0.displayID == hostDisplay }?.memberIDs(in: StageID(rawValue: "1")).isEmpty == true)

        let report = DisplayParkingService().transition(state: &stateAfterSnapshot, liveDisplays: [liveDisplay], windows: [movedBySystem])
        #expect(report.kind == .park)
        #expect(report.parkedStageCount == 1)
        #expect(stateAfterSnapshot.scopes.first { $0.displayID == hostDisplay }?.stages.contains {
            $0.parkingState == .parked && $0.members.map(\.windowID) == [movedBySystem.id]
        } == true)
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func treeDumpExposesDisplayDesktopStageAndWindowHierarchy() {
        let display = DisplayID(rawValue: "display-a")
        let live = WindowSnapshot(id: WindowID(rawValue: 1), pid: 1, appName: "Terminal", bundleID: "term", title: "live", frame: Rect(x: 0, y: 0, width: 1000, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-tree-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, desktopID: DesktopID(rawValue: 1), activeStageID: StageID(rawValue: "2"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), name: "One"),
                PersistentStage(id: StageID(rawValue: "2"), name: "Two", mode: .masterStack, members: [
                    PersistentStageMember(windowID: live.id, bundleID: live.bundleID, title: live.title, frame: live.frame),
                    PersistentStageMember(windowID: WindowID(rawValue: 99), bundleID: "gone.bundle", title: "gone", frame: live.frame),
                ]),
            ]),
        ], activeDisplayID: display))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true),
                ],
                windowSnapshots: [live],
                focusedID: live.id
            ),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            stageStore: stageStore
        )

        let dump = TreeDumpService(service: service, stageStore: stageStore).dump()

        #expect(dump.displays.first?.desktops.first?.active == true)
        #expect(dump.displays.first?.desktops.first?.stages.first { $0.id == StageID(rawValue: "2") }?.active == true)
        #expect(dump.displays.first?.desktops.first?.stages.first { $0.id == StageID(rawValue: "2") }?.mode == .masterStack)
        #expect(dump.displays.first?.desktops.first?.stages.first { $0.id == StageID(rawValue: "2") }?.windows == [
            TreeWindow(id: live.id, appName: live.appName, title: live.title, live: true),
        ])
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func sendToDisplayMovesMembershipAndRelayoutsBothDisplays() {
        let displayA = DisplayID(rawValue: "display-a")
        let displayB = DisplayID(rawValue: "display-b")
        let sourceDisplay = DisplaySnapshot(id: displayA, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let targetDisplay = DisplaySnapshot(id: displayB, index: 2, name: "B", frame: Rect(x: 1000, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 1000, y: 0, width: 1000, height: 500), isMain: false)
        let left = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "left", frame: Rect(x: 0, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let moving = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "moving", frame: Rect(x: 505, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let target = WindowSnapshot(id: WindowID(rawValue: 3), pid: 12, appName: "C", bundleID: "c", title: "target", frame: Rect(x: 1000, y: 0, width: 1000, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-display-stages-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        let intentPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-display-intents-\(UUID().uuidString).json")
            .path
        let intentStore = LayoutIntentStore(path: intentPath)
        let writer = RecordingWriter()
        let config = RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [sourceDisplay, targetDisplay],
                windowSnapshots: [left, moving, target],
                focusedID: moving.id
            ),
            frameWriter: writer,
            config: config,
            intentStore: intentStore,
            stageStore: stageStore
        )

        let result = WindowCommandService(service: service, stageStore: stageStore).sendToDisplay(2)
        let state = stageStore.state()
        let sourceScope = state.scopes.first { $0.displayID == displayA }
        let targetScope = state.scopes.first { $0.displayID == displayB }

        #expect(result.changed)
        #expect(sourceScope?.memberIDs(in: StageID(rawValue: "1")) == [left.id])
        #expect(targetScope?.memberIDs(in: StageID(rawValue: "1")) == [target.id, moving.id])
        #expect(writer.requestedFrames[left.id] == Rect(x: 0, y: 0, width: 1000, height: 500))
        #expect(writer.requestedFrames[moving.id] == Rect(x: 1000, y: 0, width: 495, height: 500))
        #expect(writer.requestedFrames[target.id] == Rect(x: 1505, y: 0, width: 495, height: 500))
        if let sourceScope {
            #expect(intentStore.intent(for: StageScope(displayID: sourceScope.displayID, desktopID: sourceScope.desktopID, stageID: sourceScope.activeStageID)) == nil)
        }
        if let targetScope {
            #expect(intentStore.intent(for: StageScope(displayID: targetScope.displayID, desktopID: targetScope.desktopID, stageID: targetScope.activeStageID)) == nil)
        }
        try? FileManager.default.removeItem(atPath: stagePath)
        try? FileManager.default.removeItem(atPath: intentPath)
    }
}
