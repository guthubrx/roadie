import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon
import RoadieStages
import RoadieTiler

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

/// Saisie utilisateur toute récente, moniteur actif : autorise le suivi du focus par la stage
/// (FR-009). Sans moniteur, ce suivi est refusé (T211).
private func recentUserInput() -> UserInputActivity {
    let input = UserInputActivity(monitoring: true)
    input.recordInput()
    return input
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
                    lastFrame: Rect(x: 0, y: 0, width: 100, height: 100),
                    // SPEC-016 FR-007 : absent depuis plus que la grâce de 45 s.
                    missingSince: Date().addingTimeInterval(-60)
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

private final class TransientFailureWriter: WindowFrameWriting, @unchecked Sendable {
    private let transientFailureWindowID: WindowID
    private(set) var attempts: [WindowID: Int] = [:]

    init(transientFailureWindowID: WindowID) {
        self.transientFailureWindowID = transientFailureWindowID
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        let nextAttempt = (attempts[window.id] ?? 0) + 1
        attempts[window.id] = nextAttempt
        if window.id == transientFailureWindowID, nextAttempt == 1 {
            return nil
        }
        return frame
    }

    func focus(_ window: WindowSnapshot) -> Bool { true }
}

@Suite
struct SnapshotServiceTests {
    @Test
    func tileCandidatesKeepTheirDisplaysWhenNoFocusedDisplayIsKnown() {
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
    func policyExcludedWindowDoesNotRemainStageManaged() {
        let display = DisplayID(rawValue: "display-a")
        let scope = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let stageStore = StageStore(path: tempPath("snapshot-policy-excluded-stage-managed"))
        let normal = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 10,
            appName: "Terminal",
            bundleID: "term",
            title: "main",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isOnScreen: true,
            isTileCandidate: true,
            subrole: "AXStandardWindow",
            role: "AXWindow",
            furniture: WindowFurniture(hasCloseButton: true, hasFullscreenButton: true, fullscreenButtonEnabled: true, isResizable: true)
        )
        let progress = WindowSnapshot(
            id: WindowID(rawValue: 2),
            pid: 20,
            appName: "Finder",
            bundleID: "com.apple.finder",
            title: "Copy",
            frame: Rect(x: 100, y: 100, width: 404, height: 88),
            isOnScreen: true,
            isTileCandidate: true,
            subrole: "AXStandardWindow",
            role: "AXWindow",
            furniture: WindowFurniture(hasCloseButton: true, hasMinimizeButton: true, hasZoomButton: true, isMain: true, isResizable: true)
        )
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: scope.stageID, stages: [
                PersistentStage(id: scope.stageID, members: [
                    PersistentStageMember(windowID: normal.id, bundleID: normal.bundleID, title: normal.title, frame: normal.frame),
                    PersistentStageMember(windowID: progress.id, bundleID: progress.bundleID, title: progress.title, frame: progress.frame),
                ]),
            ]),
        ]))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
                ],
                windowSnapshots: [normal, progress]
            ),
            frameWriter: RecordingWriter(),
            stageStore: stageStore
        )

        let snapshot = service.snapshot(followFocus: false)

        #expect(snapshot.windows.first { $0.window.id == progress.id }?.window.isTileCandidate == false)
        #expect(snapshot.windows.first { $0.window.id == progress.id }?.scope == nil)
        #expect(snapshot.state.stage(scope: scope)?.windowIDs == [normal.id])
        #expect(service.applyPlan(from: snapshot).commands.map(\.window.id) == [normal.id])
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
    func newTileCandidatesFollowFocusedDisplayByDefault() {
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
            config: RoadieConfig(),
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
    func temporarilyMissingWindowKeepsStageAcrossFullscreenTransition() {
        let display = DisplayID(rawValue: "display-a")
        let visible = WindowSnapshot(
            id: WindowID(rawValue: 101),
            pid: 10,
            appName: "Player",
            bundleID: "player",
            title: "video",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        let temporarilyMissing = WindowSnapshot(
            id: WindowID(rawValue: 202),
            pid: 20,
            appName: "Editor",
            bundleID: "editor",
            title: "document",
            frame: Rect(x: 100, y: 100, width: 500, height: 300),
            isOnScreen: true,
            isTileCandidate: true
        )
        let stageStore = StageStore(path: tempPath("snapshot-fullscreen-missing-window"))
        let eventPath = tempPath("snapshot-fullscreen-missing-window-events")
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [
                    PersistentStageMember(windowID: visible.id, bundleID: visible.bundleID, title: visible.title, frame: visible.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "2"), members: [
                    PersistentStageMember(windowID: temporarilyMissing.id, bundleID: temporarilyMissing.bundleID, title: temporarilyMissing.title, frame: temporarilyMissing.frame),
                ]),
            ]),
        ]))
        let displaySnapshot = DisplaySnapshot(
            id: display,
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )

        _ = SnapshotService(
            provider: FakeProvider(displaySnapshots: [displaySnapshot], windowSnapshots: [visible], focusedID: visible.id),
            stageStore: stageStore,
            events: EventLog(path: eventPath)
        ).snapshot(followFocus: false)

        var stateDuringFullscreen = stageStore.state()
        #expect(stateDuringFullscreen.scope(displayID: display).memberIDs(in: StageID(rawValue: "2")) == [temporarilyMissing.id])

        let snapshotAfterFullscreenExit = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [displaySnapshot],
                windowSnapshots: [visible, temporarilyMissing],
                focusedID: visible.id
            ),
            stageStore: stageStore,
            events: EventLog(path: eventPath)
        ).snapshot(followFocus: false)
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""

        let restoredEntry = snapshotAfterFullscreenExit.windows.first { $0.window.id == temporarilyMissing.id }
        #expect(restoredEntry?.scope == StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "2")))
        #expect(restoredEntry?.isNewlyScoped == false)
        #expect(events.contains("\"type\":\"windows.missing_reconciled\""))
        #expect(events.contains("\"markedMissing\":\"1\""))
        #expect(events.contains("\"restored\":\"1\""))
        var stateAfterFullscreenExit = stageStore.state()
        #expect(stateAfterFullscreenExit.scope(displayID: display).memberIDs(in: StageID(rawValue: "1")) == [visible.id])
        #expect(stateAfterFullscreenExit.scope(displayID: display).memberIDs(in: StageID(rawValue: "2")) == [temporarilyMissing.id])
        try? FileManager.default.removeItem(atPath: eventPath)
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
    func policyExcludedWindowsAreNotStageManaged() {
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
        #expect(scope == nil)
        #expect(persisted.scope(displayID: display).memberIDs(in: StageID(rawValue: "1")) == [])
        #expect(scope.flatMap { snapshot.state.stage(scope: $0)?.windowIDs } == nil)
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
        // Fenêtres tout juste découvertes (stage sans membres) : leur largeur de 100 points est
        // arbitraire, le `master_ratio` par défaut (0,6) s'applique : 594 = floor((1000 - 10) * 0,6).
        #expect(commands[0].frame == Rect(x: 0, y: 0, width: 594, height: 500))
        #expect(commands[1].frame == Rect(x: 604, y: 0, width: 396, height: 245))
        #expect(commands[2].frame == Rect(x: 604, y: 255, width: 396, height: 245))
        try? FileManager.default.removeItem(atPath: stagePath)
        try? FileManager.default.removeItem(atPath: intentPath)
    }

    /// SPEC-017 : une stage `mutableBsp` non migrée passe par l'arbre ; ses fenêtres cachées
    /// reviennent aux frames de l'arbre (50/50), sans dépendre de l'intent automatique.
    @Test
    func legacyTreeStageRestoresHiddenWindowsFromTheTree() {
        let displayID = DisplayID(rawValue: "display-a")
        let display = DisplaySnapshot(
            id: displayID,
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let first = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "one", frame: Rect(x: 999, y: 499, width: 300, height: 200), isOnScreen: true, isTileCandidate: true)
        let second = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "two", frame: Rect(x: 999, y: 499, width: 300, height: 200), isOnScreen: true, isTileCandidate: true)
        let scope = StageScope(displayID: displayID, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let stagePath = tempPath("mutable-bsp-hidden-stage")
        let intentPath = tempPath("mutable-bsp-hidden-intent")
        let stageStore = StageStore(path: stagePath)
        let intentStore = LayoutIntentStore(path: intentPath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: displayID, stages: [
                PersistentStage(id: StageID(rawValue: "1"), mode: .mutableBsp, members: [
                    PersistentStageMember(windowID: first.id, bundleID: first.bundleID, title: first.title, frame: first.frame),
                    PersistentStageMember(windowID: second.id, bundleID: second.bundleID, title: second.title, frame: second.frame),
                ])
            ])
        ]))
        intentStore.save(LayoutIntent(
            scope: scope,
            windowIDs: [first.id, second.id],
            placements: [
                first.id: Rect(x: 0, y: 0, width: 495, height: 500),
                second.id: Rect(x: 505, y: 0, width: 495, height: 500),
            ],
            source: .auto
        ))
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [display], windowSnapshots: [first, second]),
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .mutableBsp, gapsOuter: 0, gapsInner: 10)),
            intentStore: intentStore,
            stageStore: stageStore
        )

        let commands = service.applyPlan(from: service.snapshot()).commands
        #expect(commands.map(\.window.id) == [first.id, second.id])
        #expect(commands[0].frame == Rect(x: 0, y: 0, width: 495, height: 500))
        #expect(commands[1].frame == Rect(x: 505, y: 0, width: 495, height: 500))
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
            stageStore: stageStore,
            userInput: recentUserInput()
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
    func snapshotIgnoresStaleHiddenFocusAfterExplicitStageSwitch() {
        let display = DisplayID(rawValue: "display-a")
        let active = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "active", frame: Rect(x: 0, y: 0, width: 1000, height: 500), isOnScreen: true, isTileCandidate: true)
        let hidden = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "Teams", bundleID: "com.microsoft.teams2", title: "Call", frame: Rect(x: 999, y: 499, width: 1000, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-stale-hidden-focus-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: active.id, members: [
                        PersistentStageMember(windowID: active.id, bundleID: active.bundleID, title: active.title, frame: active.frame),
                    ]),
                    PersistentStage(id: StageID(rawValue: "2"), focusedWindowID: hidden.id, members: [
                        PersistentStageMember(windowID: hidden.id, bundleID: hidden.bundleID, title: hidden.title, frame: hidden.frame),
                    ]),
                ]),
            ],
            commandFocusProtection: CommandFocusProtection(
                displayID: display,
                desktopID: DesktopID(rawValue: 1),
                stageID: StageID(rawValue: "1"),
                windowID: active.id,
                staleFocusedWindowID: hidden.id,
                expiresAt: Date().addingTimeInterval(-1),
                staleFocusExpiresAt: Date().addingTimeInterval(60)
            )
        ))
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
        let persisted = stageStore.state()
        let persistedActiveStageID = persisted.scopes.first { $0.displayID == display }?.activeStageID

        #expect(snapshot.focusedWindowID == active.id)
        #expect(snapshot.state.activeScope(on: display) == StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1")))
        #expect(persistedActiveStageID == StageID(rawValue: "1"))
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func snapshotSuppressesHiddenCrossDisplayFocusWhenAWindowJustWentMissing() throws {
        let leftDisplay = powerDisplay("display-a", index: 1, x: 0)
        let rightDisplay = powerDisplay("display-b", index: 2, x: 1000)
        let activeLeft = powerWindow(1, x: 100)
        let missingLeft = powerWindow(2, x: 500)
        let hiddenRight = powerWindow(
            3,
            x: rightDisplay.visibleFrame.x + rightDisplay.visibleFrame.width - 1,
            y: rightDisplay.visibleFrame.y + rightDisplay.visibleFrame.height - 1,
            width: 300,
            height: 240,
            app: "Teams"
        )
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-cross-display-missing-focus-\(UUID().uuidString).json")
            .path
        let eventPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-cross-display-missing-focus-events-\(UUID().uuidString).jsonl")
            .path
        defer {
            try? FileManager.default.removeItem(atPath: stagePath)
            try? FileManager.default.removeItem(atPath: eventPath)
        }

        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: leftDisplay.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: activeLeft.id, members: [
                    PersistentStageMember(windowID: activeLeft.id, bundleID: activeLeft.bundleID, title: activeLeft.title, frame: activeLeft.frame),
                    PersistentStageMember(windowID: missingLeft.id, bundleID: missingLeft.bundleID, title: missingLeft.title, frame: missingLeft.frame),
                ]),
            ]),
            PersistentStageScope(displayID: rightDisplay.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1")),
                PersistentStage(id: StageID(rawValue: "2"), focusedWindowID: hiddenRight.id, members: [
                    PersistentStageMember(windowID: hiddenRight.id, bundleID: hiddenRight.bundleID, title: hiddenRight.title, frame: hiddenRight.frame),
                ]),
            ]),
        ], activeDisplayID: leftDisplay.id))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [leftDisplay, rightDisplay],
                windowSnapshots: [activeLeft, hiddenRight],
                focusedID: hiddenRight.id
            ),
            stageStore: stageStore,
            events: EventLog(path: eventPath)
        )

        let snapshot = service.snapshot()
        let persisted = stageStore.state()
        let events = try String(contentsOfFile: eventPath, encoding: .utf8)

        #expect(snapshot.focusedWindowID == activeLeft.id)
        #expect(snapshot.state.activeScope(on: leftDisplay.id)?.stageID == StageID(rawValue: "1"))
        #expect(snapshot.state.activeScope(on: rightDisplay.id)?.stageID == StageID(rawValue: "1"))
        #expect(persisted.activeDisplayID == leftDisplay.id)
        #expect(events.contains("\"type\":\"focus.hidden_cross_display_after_missing_suppressed\""))
        #expect(events.contains("\"markedMissingIDs\":\"2\""))
    }

    @Test
    func snapshotStillFollowsHiddenCrossDisplayFocusWhenNoWindowWentMissing() {
        let leftDisplay = powerDisplay("display-a", index: 1, x: 0)
        let rightDisplay = powerDisplay("display-b", index: 2, x: 1000)
        let activeLeft = powerWindow(1, x: 100)
        let hiddenRight = powerWindow(
            3,
            x: rightDisplay.visibleFrame.x + rightDisplay.visibleFrame.width - 1,
            y: rightDisplay.visibleFrame.y + rightDisplay.visibleFrame.height - 1,
            width: 300,
            height: 240,
            app: "Teams"
        )
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-cross-display-focus-allowed-\(UUID().uuidString).json")
            .path
        defer {
            try? FileManager.default.removeItem(atPath: stagePath)
        }

        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: leftDisplay.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: activeLeft.id, members: [
                    PersistentStageMember(windowID: activeLeft.id, bundleID: activeLeft.bundleID, title: activeLeft.title, frame: activeLeft.frame),
                ]),
            ]),
            PersistentStageScope(displayID: rightDisplay.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1")),
                PersistentStage(id: StageID(rawValue: "2"), focusedWindowID: hiddenRight.id, members: [
                    PersistentStageMember(windowID: hiddenRight.id, bundleID: hiddenRight.bundleID, title: hiddenRight.title, frame: hiddenRight.frame),
                ]),
            ]),
        ], activeDisplayID: leftDisplay.id))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [leftDisplay, rightDisplay],
                windowSnapshots: [activeLeft, hiddenRight],
                focusedID: hiddenRight.id
            ),
            stageStore: stageStore,
            userInput: recentUserInput()
        )

        let snapshot = service.snapshot()
        let persisted = stageStore.state()

        #expect(snapshot.focusedWindowID == hiddenRight.id)
        #expect(snapshot.state.activeScope(on: rightDisplay.id)?.stageID == StageID(rawValue: "2"))
        #expect(persisted.activeDisplayID == rightDisplay.id)
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
    func configExclusionsKeepMatchingBundlesOutOfStageManagement() {
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

        #expect(snapshot.windows.first?.scope == nil)
        #expect(snapshot.windows.first?.window.isTileCandidate == false)
        #expect(snapshot.windows.first?.scope.flatMap { snapshot.state.stage(scope: $0)?.windowIDs } == nil)
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

    /// SPEC-017 : la stage `mutableBsp` passe par l'arbre ; son arbre est celui que la migration
    /// déduit de la grille 2 x 2 (colonnes gauche et droite), la géométrie ne décide plus rien.
    @Test
    func legacyTreeWarpInsertsIntoImmediateNeighborSlot() {
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
                            },
                            bspTree: .split(
                                orientation: .vertical,
                                ratio: 0.5,
                                first: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(topLeft.id), second: .leaf(bottomLeft.id)),
                                second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(topRight.id), second: .leaf(bottomRight.id))
                            )
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
    func moveIntentIsNotPersistedWhenFrameIsClamped() {
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
        #expect(intent == nil)
        try? FileManager.default.removeItem(atPath: intentPath)
    }

    @Test
    func commandIntentIsNotPersistedOnPartialCommandFailure() {
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
        #expect(intent == nil)
        try? FileManager.default.removeItem(atPath: intentPath)
    }

    @Test
    func windowCommandEventCapturesWarpDirectionAndClampOutcome() {
        let display = DisplayID(rawValue: "display-a")
        let left = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "left", frame: Rect(x: 0, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let right = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "right", frame: Rect(x: 505, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let displaySnapshot = DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let eventPath = tempPath("window-command-warp-events")
        let service = WindowCommandService(
            service: SnapshotService(
                provider: FakeProvider(
                    displaySnapshots: [displaySnapshot],
                    windowSnapshots: [left, right],
                    focusedID: right.id
                ),
                frameWriter: DeterministicWriter(actualFrames: [
                    left.id: Rect(x: 505, y: 0, width: 574, height: 500),
                    right.id: Rect(x: 0, y: 0, width: 495, height: 500),
                ]),
                config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10))
            ),
            events: EventLog(path: eventPath)
        )

        let result = service.warp(.left)
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""

        #expect(result.changed)
        #expect(events.contains("\"type\":\"window.command\""))
        #expect(events.contains("\"verb\":\"warp\""))
        #expect(events.contains("\"direction\":\"left\""))
        #expect(events.contains("\"clamped\":\"1\""))
    }

    @Test
    func commandIntentWithLargeInternalGapIsInvalidated() {
        let display = DisplayID(rawValue: "display-a")
        let left = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "left", frame: Rect(x: 0, y: 0, width: 480, height: 1000), isOnScreen: true, isTileCandidate: true)
        let right = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "right", frame: Rect(x: 520, y: 0, width: 480, height: 1000), isOnScreen: true, isTileCandidate: true)
        let scope = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let intentPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-command-gap-intent-\(UUID().uuidString).json")
            .path
        let intentStore = LayoutIntentStore(path: intentPath)
        intentStore.save(LayoutIntent(
            scope: scope,
            windowIDs: [left.id, right.id],
            placements: [
                left.id: left.frame,
                right.id: right.frame,
            ],
            source: .command
        ))
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [
                    DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 1000), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 1000), isMain: true),
                ],
                windowSnapshots: [left, right]
            ),
            // Validation des intents : modes sans arbre seulement (SPEC-017 R2).
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .bsp, gapsOuter: 0, gapsInner: 10)),
            intentStore: intentStore
        )

        let plan = service.applyPlan(from: service.snapshot())

        #expect(intentStore.intent(for: scope) == nil)
        #expect(plan.commands.contains { $0.window.id == left.id || $0.window.id == right.id })
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
    func stageAssignFollowsTargetStageImmediately() {
        let display = DisplayID(rawValue: "display-a")
        let displaySnapshot = DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let left = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "left", frame: Rect(x: 0, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let right = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "right", frame: Rect(x: 505, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)

        for mode in WindowManagementMode.allCases {
            let stagePath = FileManager.default.temporaryDirectory
                .appendingPathComponent("roadie-stages-\(mode.rawValue)-\(UUID().uuidString).json")
                .path
            let stageStore = StageStore(path: stagePath)
            stageStore.save(PersistentStageState(scopes: [
                PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), mode: mode, focusedWindowID: right.id, members: [
                        PersistentStageMember(windowID: left.id, bundleID: left.bundleID, title: left.title, frame: left.frame),
                        PersistentStageMember(windowID: right.id, bundleID: right.bundleID, title: right.title, frame: right.frame),
                    ]),
                    PersistentStage(id: StageID(rawValue: "2"), mode: mode),
                ]),
            ]))

            let assignWriter = RecordingWriter()
            let assignService = SnapshotService(
                provider: FakeProvider(displaySnapshots: [displaySnapshot], windowSnapshots: [left, right], focusedID: right.id),
                frameWriter: assignWriter,
                config: RoadieConfig(),
                stageStore: stageStore
            )
            let assignResult = StageCommandService(service: assignService, store: stageStore).assign("2")
            var state = stageStore.state()

            #expect(assignResult.changed)
            #expect(assignWriter.requestedFrames[left.id] == Rect(x: 999, y: 0, width: 495, height: 500))
            if mode != .float {
                #expect(assignWriter.requestedFrames[right.id] == Rect(x: 8, y: 8, width: 984, height: 484))
            }
            #expect(assignWriter.focusedWindowIDs == [right.id])
            #expect(state.activeDisplayID == display)
            #expect(state.scope(displayID: display).activeStageID == StageID(rawValue: "2"))
            try? FileManager.default.removeItem(atPath: stagePath)
        }
    }

    @Test
    func stageAssignWindowNoFollowBlocksDelayedHiddenFocusFollow() {
        let display = DisplayID(rawValue: "display-a")
        let displaySnapshot = DisplaySnapshot(id: display, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let left = WindowSnapshot(id: WindowID(rawValue: 1), pid: 10, appName: "A", bundleID: "a", title: "left", frame: Rect(x: 0, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let right = WindowSnapshot(id: WindowID(rawValue: 2), pid: 11, appName: "B", bundleID: "b", title: "right", frame: Rect(x: 505, y: 0, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-stages-no-follow-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: right.id, members: [
                    PersistentStageMember(windowID: left.id, bundleID: left.bundleID, title: left.title, frame: left.frame),
                    PersistentStageMember(windowID: right.id, bundleID: right.bundleID, title: right.title, frame: right.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "2")),
            ]),
        ]))

        let hiddenRight = WindowSnapshot(id: right.id, pid: right.pid, appName: right.appName, bundleID: right.bundleID, title: right.title, frame: Rect(x: 999, y: 499, width: 495, height: 500), isOnScreen: true, isTileCandidate: true)
        let assignWriter = RecordingWriter()
        let assignService = SnapshotService(
            provider: FakeProvider(displaySnapshots: [displaySnapshot], windowSnapshots: [left, right], focusedID: right.id),
            frameWriter: assignWriter,
            config: RoadieConfig(),
            stageStore: stageStore
        )
        let assignResult = StageCommandService(service: assignService, store: stageStore)
            .assign(windowID: right.id, to: "2", displayID: display, focusAssignedWindow: false)
        var assignedState = stageStore.state()

        #expect(assignResult.changed)
        #expect(assignWriter.requestedFrames[right.id] == Rect(x: 999, y: 0, width: 495, height: 500))
        #expect(assignedState.scope(displayID: display).activeStageID == StageID(rawValue: "1"))

        let followService = SnapshotService(
            provider: FakeProvider(displaySnapshots: [displaySnapshot], windowSnapshots: [left, hiddenRight], focusedID: right.id),
            config: RoadieConfig(),
            stageStore: stageStore
        )
        let stillActive = followService.snapshot()

        #expect(stillActive.state.activeScope(on: display) == StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1")))
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
    func stageSummonRepairsWindowVisibleOnDifferentDisplay() {
        let leftDisplay = DisplayID(rawValue: "display-a")
        let rightDisplay = DisplayID(rawValue: "display-b")
        let leftSnapshot = DisplaySnapshot(id: leftDisplay, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 800), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 800), isMain: true)
        let rightSnapshot = DisplaySnapshot(id: rightDisplay, index: 2, name: "B", frame: Rect(x: 1000, y: 0, width: 1000, height: 800), visibleFrame: Rect(x: 1000, y: 0, width: 1000, height: 800), isMain: false)
        let window = WindowSnapshot(id: WindowID(rawValue: 7), pid: 7, appName: "Settings", bundleID: "settings", title: "Settings", frame: Rect(x: 1200, y: 100, width: 300, height: 300), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-summon-visible-repair-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: leftDisplay, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1")),
            ]),
            PersistentStageScope(displayID: rightDisplay, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [
                    PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
                ]),
            ]),
        ], activeDisplayID: leftDisplay))
        let writer = RecordingWriter()
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [leftSnapshot, rightSnapshot], windowSnapshots: [window], focusedID: window.id),
            frameWriter: writer,
            config: RoadieConfig(),
            stageStore: stageStore
        )

        let result = StageCommandService(service: service, store: stageStore).summon(windowID: window.id, displayID: leftDisplay)

        #expect(result.changed)
        let repaired = writer.requestedFrames[window.id]
        #expect(repaired != nil)
        if let repaired {
            let center = CGPoint(x: repaired.cgRect.midX, y: repaired.cgRect.midY)
            #expect(leftSnapshot.visibleFrame.cgRect.contains(center))
            #expect(!rightSnapshot.visibleFrame.cgRect.contains(center))
        }
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func snapshotLeavesVisibleDisplayDriftForMaintainerRepair() {
        let leftDisplay = DisplayID(rawValue: "display-a")
        let rightDisplay = DisplayID(rawValue: "display-b")
        let leftSnapshot = DisplaySnapshot(id: leftDisplay, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 800), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 800), isMain: true)
        let rightSnapshot = DisplaySnapshot(id: rightDisplay, index: 2, name: "B", frame: Rect(x: 1000, y: 0, width: 1000, height: 800), visibleFrame: Rect(x: 1000, y: 0, width: 1000, height: 800), isMain: false)
        let window = WindowSnapshot(id: WindowID(rawValue: 8), pid: 8, appName: "Settings", bundleID: "settings", title: "Settings", frame: Rect(x: 1200, y: 100, width: 300, height: 300), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-scope-physical-repair-\(UUID().uuidString).json")
            .path
        let eventPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-scope-physical-repair-\(UUID().uuidString).jsonl")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: leftDisplay, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [
                    PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: Rect(x: 100, y: 100, width: 300, height: 300)),
                ]),
            ]),
            PersistentStageScope(displayID: rightDisplay, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1")),
            ]),
        ], activeDisplayID: leftDisplay))
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [leftSnapshot, rightSnapshot], windowSnapshots: [window], focusedID: nil),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            stageStore: stageStore,
            events: EventLog(path: eventPath)
        )

        let snapshot = service.snapshot(followFocus: false)
        var state = stageStore.state()
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""

        #expect(snapshot.windows.first { $0.window.id == window.id }?.scope?.displayID == leftDisplay)
        #expect(state.scope(displayID: leftDisplay).memberIDs(in: StageID(rawValue: "1")) == [window.id])
        #expect(state.scope(displayID: rightDisplay).memberIDs(in: StageID(rawValue: "1")).isEmpty)
        #expect(!events.contains("window.scope_reconciled_to_physical_display"))
        try? FileManager.default.removeItem(atPath: stagePath)
        try? FileManager.default.removeItem(atPath: eventPath)
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
        #expect(writer.requestedFrames[left.id] == Rect(x: 999, y: 0, width: 495, height: 500))
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
        #expect(writer.requestedFrames[left.id] == Rect(x: 999, y: 0, width: 495, height: 500))
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
    func temporarilyMissingWindowIsNotPrunedAfterShortAXGap() {
        let display = DisplayID(rawValue: "display-a")
        let live = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 10,
            appName: "Terminal",
            bundleID: "terminal",
            title: "live",
            frame: Rect(x: 0, y: 0, width: 500, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        )
        let transient = WindowID(rawValue: 2)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-short-ax-gap-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(
                displayID: display,
                stages: [
                    PersistentStage(id: StageID(rawValue: "1"), members: [
                        PersistentStageMember(windowID: live.id, bundleID: live.bundleID, title: live.title, frame: live.frame),
                        PersistentStageMember(
                            windowID: transient,
                            bundleID: "editor",
                            title: "document",
                            frame: Rect(x: 500, y: 0, width: 500, height: 500),
                            missingSince: Date().addingTimeInterval(-90)
                        ),
                    ]),
                ]
            ),
        ]))
        let displaySnapshot = DisplaySnapshot(
            id: display,
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 1000, height: 500),
            visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
            isMain: true
        )
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [displaySnapshot], windowSnapshots: [live], focusedID: live.id),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            stageStore: stageStore
        )

        _ = service.snapshot()

        let scope = stageStore.state().scopes.first { $0.displayID == display }
        #expect(scope?.memberIDs(in: StageID(rawValue: "1")) == [live.id, transient])
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func snapshotMarksClosedWindowsMissingBeforePruningPersistentStages() {
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
        #expect(scope?.memberIDs(in: StageID(rawValue: "1")) == [live.id, closed])
        #expect(scope?.stages.first?.members.first { $0.windowID == closed }?.missingSince != nil)
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
        var staleIntent = LayoutIntent(scope: staleScope, windowIDs: [WindowID(rawValue: 2)], placements: [:])
        // SPEC-016 T015 : l'intent n'est purgé qu'après 10 min d'absence du display.
        staleIntent.displayMissingSince = Date().addingTimeInterval(-601)
        intentStore.save(staleIntent)
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
                        PersistentStageMember(windowID: stale.id, bundleID: stale.bundleID, title: stale.title, frame: stale.frame, pid: stale.pid),
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

        let report = StateAuditService(service: service, stageStore: stageStore).heal(isProcessAlive: { $0 != stale.pid })  // REL-002 : retrait sur preuve de fermeture
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

        let report = DaemonHealthService(
            service: service,
            stageStore: stageStore,
            pidFilePath: missingPidPath,
            componentRegistry: { [] }
        ).run()

        #expect(!report.failed)
        #expect(report.checks.contains(DaemonHealthCheck(level: .warn, name: "pidfile", message: "missing")))
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func daemonHealthReportsModularComponentsWhenMonolithicPidfileIsMissing() throws {
        let display = DisplayID(rawValue: "display-a")
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-health-components-\(UUID().uuidString).json")
            .path
        let missingPidPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-health-components-\(UUID().uuidString).pid")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(activeDisplayID: display))
        let component = "health-\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(atPath: stagePath)
        }
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

        let report = DaemonHealthService(
            service: service,
            stageStore: stageStore,
            pidFilePath: missingPidPath,
            componentRegistry: {
                [(component: component, pid: Int32(ProcessInfo.processInfo.processIdentifier), startedAt: Date())]
            }
        ).run()

        #expect(!report.failed)
        #expect(report.checks.contains { check in
            check.level == .ok
                && check.name == "components"
                && check.message.contains(component)
        })
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
        #expect(metrics.staleMembers == 1)
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
    func snapshotKeepsDisconnectedDisplayMembersWhenWindowsAreTemporarilyHidden() {
        let hostDisplay = DisplayID(rawValue: "built-in")
        let goneDisplay = DisplayID(rawValue: "fullscreen-space")
        let hiddenWindowID = WindowID(rawValue: 10)
        let liveDisplay = DisplaySnapshot(id: hostDisplay, index: 1, name: "Built-in", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let visibleHostWindow = WindowSnapshot(id: WindowID(rawValue: 20), pid: 20, appName: "A", bundleID: "a", title: "host-window", frame: Rect(x: 0, y: 0, width: 500, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-display-hidden-preserve-\(UUID().uuidString).json")
            .path
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: hostDisplay, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), name: "Host", members: [
                    PersistentStageMember(windowID: visibleHostWindow.id, bundleID: visibleHostWindow.bundleID, title: visibleHostWindow.title, frame: visibleHostWindow.frame),
                ]),
            ]),
            PersistentStageScope(displayID: goneDisplay, activeStageID: StageID(rawValue: "2"), stages: [
                PersistentStage(id: StageID(rawValue: "2"), name: "Fullscreen", members: [
                    PersistentStageMember(windowID: hiddenWindowID, bundleID: "a", title: "hidden", frame: Rect(x: 1000, y: 0, width: 500, height: 500)),
                ]),
            ]),
        ], activeDisplayID: hostDisplay))
        let service = SnapshotService(
            provider: FakeProvider(displaySnapshots: [liveDisplay], windowSnapshots: [visibleHostWindow], focusedID: nil),
            frameWriter: RecordingWriter(),
            stageStore: stageStore
        )

        _ = service.snapshot(followFocus: false)
        let stateAfterSnapshot = stageStore.state()

        #expect(stateAfterSnapshot.scopes.first { $0.displayID == goneDisplay }?.memberIDs(in: StageID(rawValue: "2")) == [hiddenWindowID])
        #expect(stateAfterSnapshot.scopes.first { $0.displayID == hostDisplay }?.memberIDs(in: StageID(rawValue: "1")) == [visibleHostWindow.id])
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
            TreeWindow(id: WindowID(rawValue: 99), appName: "gone.bundle", title: "gone", live: false),
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
            let intent = intentStore.intent(for: StageScope(displayID: sourceScope.displayID, desktopID: sourceScope.desktopID, stageID: sourceScope.activeStageID))
            #expect(intent?.windowIDs == [left.id])
            #expect(intent?.placements[left.id] == Rect(x: 0, y: 0, width: 1000, height: 500))
        }
        if let targetScope {
            let intent = intentStore.intent(for: StageScope(displayID: targetScope.displayID, desktopID: targetScope.desktopID, stageID: targetScope.activeStageID))
            #expect(intent?.windowIDs == [moving.id, target.id])
            #expect(intent?.placements[moving.id] == Rect(x: 1000, y: 0, width: 495, height: 500))
            #expect(intent?.placements[target.id] == Rect(x: 1505, y: 0, width: 495, height: 500))
        }
        try? FileManager.default.removeItem(atPath: stagePath)
        try? FileManager.default.removeItem(atPath: intentPath)
    }

    /// T212 : `window display N` n'écrit plus de déplacement initial (ni ses relances) avant le plan
    /// unique. Une écriture en échec n'est pas relancée par la commande : le maintainer la reprend.
    @Test
    func sendToDisplayWritesTheMovedWindowOnceWithoutIntermediateMove() throws {
        let displayA = DisplayID(rawValue: "display-a")
        let displayB = DisplayID(rawValue: "display-b")
        let sourceDisplay = DisplaySnapshot(id: displayA, index: 1, name: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500), isMain: true)
        let targetDisplay = DisplaySnapshot(id: displayB, index: 2, name: "B", frame: Rect(x: 1000, y: 0, width: 1000, height: 500), visibleFrame: Rect(x: 1000, y: 0, width: 1000, height: 500), isMain: false)
        let moving = WindowSnapshot(id: WindowID(rawValue: 44), pid: 10, appName: "A", bundleID: "a", title: "moving", frame: Rect(x: 100, y: 0, width: 500, height: 500), isOnScreen: true, isTileCandidate: true)
        let target = WindowSnapshot(id: WindowID(rawValue: 55), pid: 11, appName: "B", bundleID: "b", title: "target", frame: Rect(x: 1000, y: 0, width: 1000, height: 500), isOnScreen: true, isTileCandidate: true)
        let stagePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-display-retry-\(UUID().uuidString).json")
            .path
        let eventPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-display-retry-\(UUID().uuidString).jsonl")
            .path
        let stageStore = StageStore(path: stagePath)
        let writer = TransientFailureWriter(transientFailureWindowID: moving.id)
        let service = SnapshotService(
            provider: FakeProvider(
                displaySnapshots: [sourceDisplay, targetDisplay],
                windowSnapshots: [moving, target],
                focusedID: moving.id
            ),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 10)),
            stageStore: stageStore
        )

        let result = WindowCommandService(
            service: service,
            stageStore: stageStore,
            events: EventLog(path: eventPath)
        ).sendToDisplay(2)
        let events = try String(contentsOfFile: eventPath, encoding: .utf8)

        #expect(result.changed)
        #expect(writer.attempts[moving.id] == 1)
        #expect(!events.contains("\"type\":\"window_display_initial_move_retried\""))
        #expect(!events.contains("initialMoveAttempts"))
        try? FileManager.default.removeItem(atPath: stagePath)
        try? FileManager.default.removeItem(atPath: eventPath)
    }
}

// MARK: - SPEC-016 lot E : snapshot transactionnel, suivi du focus, hystérésis, config à chaud

private final class StabilizationClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

private final class SnapshotCallCountingProvider: SystemSnapshotProviding, @unchecked Sendable {
    let display: DisplaySnapshot
    var windowList: [WindowSnapshot]
    var onWindows: (() -> Void)?
    private(set) var windowsCalls = 0

    init(display: DisplaySnapshot, windows: [WindowSnapshot]) {
        self.display = display
        self.windowList = windows
    }

    func permissions(prompt: Bool) -> PermissionSnapshot { PermissionSnapshot(accessibilityTrusted: true) }
    func displays() -> [DisplaySnapshot] { [display] }
    func windows() -> [WindowSnapshot] {
        windowsCalls += 1
        onWindows?()
        return windowList
    }
    func focusedWindowID() -> WindowID? { nil }
    func mouseLocation() -> CGPoint? { nil }
}

@Suite
struct SnapshotStabilizationTests {
    private let display = powerDisplay("display-main", index: 1, x: 0)

    private func member(_ window: WindowSnapshot) -> PersistentStageMember {
        PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame)
    }

    /// Stage 1 active (A et C), stage 2 inactive mais visible (B).
    private func twoStageStore(a: WindowSnapshot, b: WindowSnapshot, c: WindowSnapshot? = nil) -> StageStore {
        let store = StageStore(path: tempPath("stabilization-stages"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: display.id, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: a.id, members: [member(a)] + (c.map { [member($0)] } ?? [])),
                    PersistentStage(id: StageID(rawValue: "2"), members: [member(b)])
                ])
            ],
            activeDisplayID: display.id
        ))
        return store
    }

    private func service(
        windows: [WindowSnapshot],
        focusedID: WindowID? = nil,
        store: StageStore,
        clock: StabilizationClock,
        userInput: UserInputActivity = UserInputActivity(),
        persist: Bool = true,
        intentStore: LayoutIntentStore = LayoutIntentStore(path: tempPath("stabilization-intents"))
    ) -> SnapshotService {
        SnapshotService(
            provider: FakeProvider(displaySnapshots: [display], windowSnapshots: windows, focusedID: focusedID),
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            intentStore: intentStore,
            stageStore: store,
            events: EventLog(path: tempPath("stabilization-events")),
            persistStateChanges: persist,
            userInput: userInput,
            clock: { clock.now }
        )
    }

    private func activeStageID(_ store: StageStore) -> StageID? {
        store.state().scopes.first { $0.displayID == display.id }?.activeStageID
    }

    @Test
    func readerSnapshotWritesNoStateFile() throws {
        let a = powerWindow(1, x: 0)
        let b = powerWindow(2, x: 400)
        let newcomer = powerWindow(3, x: 800)
        let store = twoStageStore(a: a, b: b)
        let before = try Data(contentsOf: store.fileURL)
        let intentPath = tempPath("reader-intents")

        let snapshot = service(
            windows: [a, b, newcomer],
            focusedID: newcomer.id,
            store: store,
            clock: StabilizationClock(),
            persist: false,
            intentStore: LayoutIntentStore(path: intentPath)
        ).snapshot()

        #expect(snapshot.windows.contains { $0.window.id == newcomer.id && $0.scope != nil })
        #expect(try Data(contentsOf: store.fileURL) == before)
        #expect(!FileManager.default.fileExists(atPath: intentPath))
    }

    /// FR-037 : après disparition de l'écran de droite, la fenêtre est reportée hors de tout écran
    /// présent ; ce cadre n'écrase pas la dernière position visible du membre.
    @Test
    func frameOutsideEveryDisplayDoesNotOverwriteMemberFrame() {
        let a = powerWindow(1, x: 100)
        let b = powerWindow(2, x: 400)
        let store = twoStageStore(a: a, b: b)
        let movedOffscreen = powerWindow(1, x: 2_500)
        let movedVisible = powerWindow(2, x: 600)

        _ = service(
            windows: [movedOffscreen, movedVisible],
            focusedID: a.id,
            store: store,
            clock: StabilizationClock()
        ).snapshot()

        let members = store.state().scopes.flatMap(\.stages).flatMap(\.members)
        #expect(members.first { $0.windowID == a.id }?.frame == a.frame)
        #expect(members.first { $0.windowID == b.id }?.frame == movedVisible.frame)
    }

    /// Une ancienne position de masquage tombe sur le nouvel écran. Elle ne devient pas une
    /// position visible sauvegardée, même si le cache partagé est invalidé ou AX disparaît un tick.
    @Test(arguments: ["observed", "absent", "written", "written-direct", "written-partial"])
    func hotplugPreservesFrameOfPreviouslyHiddenWindow(observation: String) {
        let oldDisplay = DisplaySnapshot(
            id: display.id, index: 1, name: "Mac", frame: Rect(x: 0, y: 0, width: 2048, height: 1280),
            visibleFrame: Rect(x: 0, y: 30, width: 2048, height: 1250), isMain: true
        )
        let main = DisplaySnapshot(
            id: display.id, index: 1, name: "Mac", frame: Rect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: Rect(x: 0, y: 32, width: 1512, height: 950), isMain: true
        )
        let external = DisplaySnapshot(
            id: DisplayID(rawValue: "display-external"), index: 2, name: "LG",
            frame: Rect(x: 1512, y: -964, width: 3840, height: 2160),
            visibleFrame: Rect(x: 1512, y: -934, width: 3840, height: 2130), isMain: false
        )
        let a = powerWindow(1, x: 100)
        let b = powerWindow(2, x: 400)
        var hidden = b
        hidden.frame = Rect(x: 2047, y: 300, width: 940, height: 612)
        let store = twoStageStore(a: a, b: b)
        let clock = StabilizationClock()
        let writer = RecordingWriter()
        let frameWriter: any WindowFrameWriting = observation == "written-partial"
            ? FakeWriter(actualFrames: [b.id: hidden.frame]) : writer
        let home = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "2"))
        store.mutate { state in
            _ = state.setPin(window: b, homeScope: home, pinScope: .desktop, now: clock.now)
            state.windowBookmarks = [PersistentWindowBookmark(
                name: "hidden", windowID: b.id, scope: home, bundleID: b.bundleID, title: b.title,
                frame: b.frame, createdAt: clock.now, updatedAt: clock.now
            )]
        }
        let read = { (screens: [DisplaySnapshot], windows: [WindowSnapshot]) in
            SnapshotService(
                provider: FakeProvider(displaySnapshots: screens, windowSnapshots: windows), frameWriter: frameWriter,
                config: RoadieConfig(), stageStore: store, events: EventLog(path: tempPath("hidden-hotplug-events")), clock: { clock.now }
            )
        }
        let before = read([oldDisplay], [a, observation.hasPrefix("written") ? b : hidden])
        _ = before.snapshot(followFocus: false)
        if observation == "written" {
            #expect(before.apply(ApplyPlan(commands: [ApplyCommand(window: b, frame: hidden.frame)]), generation: PlacementGeneration.outsideBudget).applied == 1)
        } else if observation == "written-direct" {
            #expect(before.setFrame(hidden.frame.cgRect, of: b, generation: PlacementGeneration.outsideBudget) == hidden.frame.cgRect)
        } else if observation == "written-partial" {
            let result = before.apply(ApplyPlan(commands: [
                ApplyCommand(window: a, frame: a.frame), ApplyCommand(window: b, frame: hidden.frame)
            ]), generation: PlacementGeneration.outsideBudget)
            #expect(result.applied == 1 && result.failed == 1)
        }
        before.invalidateSharedSnapshot()
        clock.now += 2
        if observation == "absent" {
            _ = read([main, external], []).snapshot(followFocus: false)
            clock.now += 2
        }
        let after = read([main, external], [a, hidden]).snapshot(followFocus: false)
        let saved = store.state().scopes.flatMap(\.stages).flatMap(\.members).first { $0.windowID == b.id }
        #expect(saved?.frame == b.frame)
        #expect(store.state().pin(for: b.id)?.lastFrame == b.frame)
        #expect(store.state().windowBookmarks.first?.frame == b.frame)
        #expect(after.windows.first { $0.window.id == b.id }?.scope?.displayID == main.id)
        #expect(writer.requestedFrames.isEmpty == (observation != "written" && observation != "written-direct"))

        // Une vraie nouvelle position observée libère la preuve de masquage.
        var moved = hidden
        moved.frame = Rect(x: 2400, y: -800, width: 940, height: 612)
        clock.now += 1
        _ = read([main, external], [a, moved]).snapshot(followFocus: false)
        #expect(store.state().scopes.flatMap(\.stages).flatMap(\.members).first { $0.windowID == b.id }?.frame == moved.frame)
    }

    /// Une fenêtre masquée à l'ancien bord peut ressembler à une fenêtre agrandie sur
    /// l'écran reconnecté. La normalisation solo ne doit pas écraser son cadre utile.
    @Test
    func hotplugDoesNotSaveHiddenFrameAsSoloMaximizedFrame() {
        let main = DisplaySnapshot(
            id: display.id, index: 1, name: "Mac", frame: Rect(x: 0, y: 0, width: 2048, height: 1280),
            visibleFrame: Rect(x: 0, y: 30, width: 2048, height: 1250), isMain: true
        )
        let external = DisplaySnapshot(
            id: DisplayID(rawValue: "display-external"), index: 2, name: "External",
            frame: Rect(x: 2048, y: 0, width: 1920, height: 1080),
            visibleFrame: Rect(x: 2048, y: 0, width: 1920, height: 1080), isMain: false
        )
        let a = powerWindow(1, x: 100)
        let b = powerWindow(2, x: 2200)
        var hidden = b
        hidden.frame = Rect(x: 2047, y: 0, width: 1920, height: 1080)
        let store = StageStore(path: tempPath("hidden-solo-hotplug"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: main.id, stages: [PersistentStage(id: StageID(rawValue: "1"), members: [member(a)])]),
            PersistentStageScope(displayID: external.id, stages: [PersistentStage(id: StageID(rawValue: "1"), members: [member(b)])])
        ]))
        let clock = StabilizationClock()
        let read = { (screens: [DisplaySnapshot]) in
            SnapshotService(
                provider: FakeProvider(displaySnapshots: screens, windowSnapshots: [a, hidden]),
                frameWriter: RecordingWriter(), config: RoadieConfig(), stageStore: store, clock: { clock.now }
            )
        }
        let before = read([main])
        _ = before.snapshot(followFocus: false)
        #expect(store.state().scopes.flatMap(\.stages).flatMap(\.members).first { $0.windowID == b.id }?.frame == b.frame)
        before.invalidateSharedSnapshot()
        clock.now += 1

        _ = read([main, external]).snapshot(followFocus: false)

        #expect(store.state().scopes.flatMap(\.stages).flatMap(\.members).first { $0.windowID == b.id }?.frame == b.frame)
    }

    /// Le bord de l'ancien écran ne suffit pas à déclarer une fenêtre cachée : il faut une
    /// observation de masquage de cette fenêtre avant le branchement.
    @Test(arguments: [false, true])
    func oldScreenEdgeDoesNotHideAnUnobservedNormalWindow(reusedWindowID: Bool) {
        let a = powerWindow(1, x: 100)
        let b = powerWindow(2, x: 400)
        let store = twoStageStore(a: a, b: b)
        let clock = StabilizationClock()
        var previous = b
        if reusedWindowID { previous.frame = Rect(x: 999, y: 300, width: 940, height: 612) }
        let before = service(windows: [a, previous], store: store, clock: clock)
        _ = before.snapshot(followFocus: false)
        before.invalidateSharedSnapshot()
        let external = DisplaySnapshot(
            id: DisplayID(rawValue: "display-external"), index: 2, name: "LG",
            frame: Rect(x: 1000, y: -964, width: 3840, height: 2160),
            visibleFrame: Rect(x: 1000, y: -934, width: 3840, height: 2130), isMain: false
        )
        var moved = b
        if reusedWindowID { moved.pid += 1 }
        moved.frame = Rect(x: 999, y: 300, width: 940, height: 612)
        _ = SnapshotService(
            provider: FakeProvider(displaySnapshots: [display, external], windowSnapshots: [a, moved]),
            frameWriter: RecordingWriter(), config: RoadieConfig(), stageStore: store, clock: { clock.now }
        ).snapshot(followFocus: false)
        #expect(store.state().scopes.flatMap(\.stages).flatMap(\.members).first { $0.windowID == b.id }?.frame == moved.frame)
    }

    /// Les membres conservés sur un écran débranché depuis des mois gardent leur stage, mais
    /// leur première absence au retour ne crée pas de cartes de fenêtres imaginaires.
    @Test(arguments: [false, true])
    func historicalMissingMembersAreNotDisplayedAsLiveWindows(hasOldObservation: Bool) throws {
        let a = powerWindow(1, x: 100)
        let external = powerDisplay("display-external", index: 2, x: 1000)
        let clock = StabilizationClock()
        let oldObservation = hasOldObservation ? clock.now.addingTimeInterval(-120 * 24 * 60 * 60) : nil
        let ghosts = [powerWindow(900, x: 1200), powerWindow(901, x: 1500)]
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(ghosts[0].id), second: .leaf(ghosts[1].id))
        let store = StageStore(path: tempPath("historical-display-members"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display.id, stages: [PersistentStage(id: StageID(rawValue: "1"), members: [member(a)])]),
            PersistentStageScope(displayID: external.id, stages: [PersistentStage(
                id: StageID(rawValue: "1"), name: "Com", mode: .spatialBsp,
                members: ghosts.map { window in
                    var value = member(window)
                    value.lastSeenAt = oldObservation
                    return value
                }, bspTree: tree
            )])
        ], activeDisplayID: display.id))
        let read = { (screens: [DisplaySnapshot]) in
            SnapshotService(
                provider: FakeProvider(displaySnapshots: screens, windowSnapshots: [a]), frameWriter: RecordingWriter(),
                config: RoadieConfig(), stageStore: store, events: EventLog(path: tempPath("historical-members-events")), clock: { clock.now }
            ).snapshot(followFocus: false)
        }
        _ = read([display])
        clock.now += 2
        let snapshot = read([display, external])
        let scope = try #require(store.state().scopes.first { $0.displayID == external.id })
        let stage = try #require(scope.stages.first { $0.id.rawValue == "1" })
        #expect(RailController.railDisplayStage(stage, liveWindowIDs: Set(snapshot.windows.map(\.window.id)), now: clock.now).members.isEmpty)
        #expect(stage.name == "Com")
        #expect(stage.members.map(\.windowID) == ghosts.map(\.id))
        #expect(stage.bspTree == tree)
        #expect(stage.members.allSatisfy { $0.lastSeenAt == oldObservation && $0.missingSince == clock.now })
    }

    /// Une disparition réellement observée conserve sa carte quinze secondes. La conservation
    /// du membre est indépendante de ce délai d'affichage.
    @Test(arguments: [false, true])
    func recentlyObservedMissingMemberKeepsRailGrace(readerBeforeWriter: Bool) throws {
        let a = powerWindow(1, x: 100)
        let b = powerWindow(2, x: 400)
        let store = twoStageStore(a: a, b: b)
        let clock = StabilizationClock()
        _ = service(windows: [a, b], store: store, clock: clock).snapshot(followFocus: false)
        clock.now += 120
        _ = service(windows: [a, b], store: store, clock: clock).snapshot(followFocus: false)
        let seenAt = clock.now
        clock.now += 2
        if readerBeforeWriter {
            _ = service(windows: [a], store: store, clock: clock, persist: false).snapshot(followFocus: false)
        }
        _ = service(windows: [a], store: store, clock: clock).snapshot(followFocus: false)
        let stage = try #require(store.state().scopes.flatMap(\.stages).first { $0.id.rawValue == "2" })
        #expect(stage.members.first?.lastSeenAt == seenAt)
        #expect(RailController.railDisplayStage(stage, liveWindowIDs: [a.id], now: clock.now + 10).members.map(\.windowID) == [b.id])
        #expect(RailController.railDisplayStage(stage, liveWindowIDs: [a.id], now: clock.now + 16).members.isEmpty)
        #expect(stage.members.map(\.windowID) == [b.id])
    }

    @Test
    func confirmedDestructionHidesRailMemberAndEmptyStageImmediately() throws {
        let a = powerWindow(1, x: 100)
        let b = powerWindow(2, x: 400)
        let store = twoStageStore(a: a, b: b)
        let clock = StabilizationClock()
        let provider = SnapshotCallCountingProvider(display: display, windows: [a, b])
        let eventPath = tempPath("confirmed-close-events")
        let snapshotService = SnapshotService(
            provider: provider, frameWriter: RecordingWriter(), config: RoadieConfig(),
            stageStore: store, events: EventLog(path: eventPath),
            clock: { clock.now }
        )
        _ = snapshotService.producerSnapshot(cycle: 2)

        snapshotService.noteWindowDestroyed(b.id)
        provider.windowList = [a]
        clock.now += 0.02
        _ = snapshotService.producerSnapshot(cycle: 2)

        let scope = try #require(store.state().scopes.first)
        let stage = try #require(scope.stages.first { $0.id.rawValue == "2" })
        let member = try #require(stage.members.first)
        #expect(member.confirmedClosedAt == clock.now)
        #expect(member.missingSince == clock.now)
        #expect(RailController.railDisplayStage(stage, liveWindowIDs: [a.id], now: clock.now).members.isEmpty)
        #expect(!RailController.railVisibleStageIDs(in: scope, liveWindowIDs: [a.id], now: clock.now).contains(stage.id))
        #expect(RailController.railDisplayStage(stage, liveWindowIDs: [a.id, b.id], now: clock.now).members.map(\.windowID) == [b.id])
        #expect(stage.members.map(\.windowID) == [b.id])
        let events = try String(contentsOfFile: eventPath, encoding: .utf8)
        #expect(events.contains("\"type\":\"windows.missing_reconciled\""))
        #expect(events.contains("\"markedMissingIDs\":\"2\""))
    }

    @Test
    func destructionDuringWindowScanStillMarksMemberClosed() throws {
        let a = powerWindow(1, x: 100)
        let b = powerWindow(2, x: 400)
        let store = twoStageStore(a: a, b: b)
        let clock = StabilizationClock()
        let provider = SnapshotCallCountingProvider(display: display, windows: [a, b])
        let snapshotService = SnapshotService(
            provider: provider, frameWriter: RecordingWriter(), config: RoadieConfig(),
            stageStore: store, events: EventLog(path: tempPath("in-scan-close-events")),
            clock: { clock.now }
        )
        _ = snapshotService.producerSnapshot(cycle: 2)
        provider.onWindows = {
            provider.onWindows = nil
            clock.now += 0.02
            snapshotService.noteWindowDestroyed(b.id)
            provider.windowList = [a]
        }

        _ = snapshotService.producerSnapshot(cycle: 2)

        let stage = try #require(store.state().scopes.flatMap(\.stages).first { $0.id.rawValue == "2" })
        #expect(stage.members.first?.confirmedClosedAt != nil)
        #expect(RailController.railDisplayStage(stage, liveWindowIDs: [a.id], now: clock.now).members.isEmpty)
    }

    @Test
    func confirmedCloseChangesStageStoreRailSignature() {
        let a = powerWindow(1, x: 100)
        let b = powerWindow(2, x: 400)
        let store = twoStageStore(a: a, b: b)
        var state = store.state()
        let before = RailController.railSignature(for: state)

        state.markConfirmedClosed(windowIDs: [b.id], at: Date(timeIntervalSince1970: 123))

        #expect(RailController.railSignature(for: state) != before)
    }

    @Test
    func remappedWindowClearsConfirmedCloseMarker() throws {
        let a = powerWindow(1, x: 100)
        let b = powerWindow(2, x: 400)
        let store = twoStageStore(a: a, b: b)
        var state = store.state()
        let closedAt = Date(timeIntervalSince1970: 123)
        state.markConfirmedClosed(windowIDs: [b.id], at: closedAt)
        var restored = b
        restored.id = WindowID(rawValue: 22)
        restored.pid = 222

        state.reconcileWindowIDs(with: [a, restored], isProcessAlive: { _ in false })

        let member = try #require(state.scopes.flatMap(\.stages).flatMap(\.members).first { $0.windowID == restored.id })
        #expect(member.confirmedClosedAt == nil)
        #expect(member.missingSince == nil)
    }

    @Test
    func confirmedDestructionKeepsOtherRailMembersInTheirOrder() throws {
        let a = powerWindow(1, x: 100)
        let b = powerWindow(2, x: 400)
        let c = powerWindow(3, x: 700)
        let store = twoStageStore(a: a, b: b, c: c)
        let clock = StabilizationClock()
        let provider = SnapshotCallCountingProvider(display: display, windows: [a, b, c])
        let snapshotService = SnapshotService(
            provider: provider, frameWriter: RecordingWriter(), config: RoadieConfig(),
            stageStore: store, events: EventLog(path: tempPath("confirmed-close-order-events")),
            clock: { clock.now }
        )
        _ = snapshotService.producerSnapshot(cycle: 2)

        snapshotService.noteWindowDestroyed(c.id)
        provider.windowList = [a, b]
        clock.now += 0.02
        _ = snapshotService.producerSnapshot(cycle: 2)

        let scope = try #require(store.state().scopes.first)
        let stage = try #require(scope.stages.first { $0.id.rawValue == "1" })
        #expect(stage.members.map(\.windowID) == [a.id, c.id])
        #expect(RailController.railDisplayStage(stage, liveWindowIDs: [a.id, b.id], now: clock.now).members.map(\.windowID) == [a.id])
    }

    @Test
    func staleDestructionKeepsTransientRailGrace() throws {
        let a = powerWindow(1, x: 100)
        let b = powerWindow(2, x: 400)
        let store = twoStageStore(a: a, b: b)
        let clock = StabilizationClock()
        let provider = SnapshotCallCountingProvider(display: display, windows: [a, b])
        let snapshotService = SnapshotService(
            provider: provider, frameWriter: RecordingWriter(), config: RoadieConfig(),
            stageStore: store, events: EventLog(path: tempPath("stale-close-events")),
            clock: { clock.now }
        )
        _ = snapshotService.producerSnapshot(cycle: 2)
        snapshotService.noteWindowDestroyed(b.id)

        clock.now += 6
        provider.windowList = [a]
        _ = snapshotService.producerSnapshot(cycle: 2)

        let stage = try #require(store.state().scopes.flatMap(\.stages).first { $0.id.rawValue == "2" })
        #expect(stage.members.first?.confirmedClosedAt == nil)
        #expect(RailController.railDisplayStage(stage, liveWindowIDs: [a.id], now: clock.now).members.map(\.windowID) == [b.id])
    }

    @Test
    func onlyWriterSnapshotsConsumeTenRetriesPerDestroyedWindow() {
        let a = powerWindow(1, x: 100)
        let b = powerWindow(2, x: 400)
        let store = twoStageStore(a: a, b: b)
        let clock = StabilizationClock()
        let provider = SnapshotCallCountingProvider(display: display, windows: [a, b])
        let snapshotService = SnapshotService(
            provider: provider, frameWriter: RecordingWriter(), config: RoadieConfig(),
            stageStore: store, events: EventLog(path: tempPath("close-retry-events")),
            clock: { clock.now }
        )
        _ = snapshotService.producerSnapshot(cycle: 2)
        snapshotService.noteWindowDestroyed(b.id)

        _ = snapshotService.snapshot(followFocus: false)
        #expect(snapshotService.destroyedWindowRetryDeadline(now: clock.now) == nil)

        for pass in 0...10 {
            _ = snapshotService.producerSnapshot(cycle: 2)
            if pass == 5 { snapshotService.noteWindowDestroyed(b.id) }
            if pass < 10 {
                let retryAt = clock.now.addingTimeInterval(0.05)
                #expect(snapshotService.destroyedWindowRetryDeadline(now: clock.now) == retryAt)
                if pass == 0 {
                    _ = snapshotService.producerSnapshot(cycle: 2)
                    #expect(snapshotService.destroyedWindowRetryDeadline(now: clock.now) == retryAt)
                }
            } else {
                #expect(snapshotService.destroyedWindowRetryDeadline(now: clock.now) == nil)
            }
            clock.now += 0.051
        }
    }

    @Test
    func elapsedDestroyedWindowRetryRemainsRunnable() throws {
        let a = powerWindow(1, x: 100)
        let b = powerWindow(2, x: 400)
        let store = twoStageStore(a: a, b: b)
        let clock = StabilizationClock()
        let provider = SnapshotCallCountingProvider(display: display, windows: [a, b])
        let snapshotService = SnapshotService(
            provider: provider, frameWriter: RecordingWriter(), config: RoadieConfig(),
            stageStore: store, events: EventLog(path: tempPath("elapsed-close-retry-events")),
            clock: { clock.now }
        )
        let maintainer = LayoutMaintainer(
            service: snapshotService,
            dragActivity: WindowDragActivity(path: tempPath("elapsed-close-retry-drag"), enabled: false),
            commandActivity: LayoutCommandActivity(path: tempPath("elapsed-close-retry-command"), enabled: false),
            episodes: EpisodeContext(now: { clock.now }),
            now: { clock.now }
        )
        _ = snapshotService.producerSnapshot(cycle: 2)
        snapshotService.noteWindowDestroyed(b.id)
        _ = snapshotService.producerSnapshot(cycle: 2)
        let retryAt = try #require(snapshotService.destroyedWindowRetryDeadline(now: clock.now))

        clock.now += 0.10

        #expect(maintainer.nextDeadline(now: clock.now) == retryAt)
    }

    @Test
    func writerSnapshotDoesNotRewriteUnchangedState() throws {
        let a = powerWindow(1, x: 0)
        let b = powerWindow(2, x: 400)
        let store = twoStageStore(a: a, b: b)
        let clock = StabilizationClock()
        _ = service(windows: [a, b], focusedID: a.id, store: store, clock: clock).snapshot()
        let first = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.modificationDate] as? Date

        clock.now += 1
        _ = service(windows: [a, b], focusedID: a.id, store: store, clock: clock).snapshot()
        let second = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.modificationDate] as? Date

        #expect(first != nil)
        #expect(first == second)
    }

    @Test
    func stageIgnoresFocusChangeWithoutRecentUserInput() {
        let a = powerWindow(1, x: 0)
        let b = powerWindow(2, x: 400)
        let store = twoStageStore(a: a, b: b)
        let clock = StabilizationClock()
        let input = UserInputActivity(monitoring: true)

        let ignored = service(windows: [a, b], focusedID: b.id, store: store, clock: clock, userInput: input).snapshot()

        #expect(ignored.state.activeScope(on: display.id)?.stageID == StageID(rawValue: "1"))
        #expect(activeStageID(store) == StageID(rawValue: "1"))

        clock.now += 2
        input.recordInput(at: clock.now - 0.2)
        let followed = service(windows: [a, b], focusedID: b.id, store: store, clock: clock, userInput: input).snapshot()

        #expect(followed.state.activeScope(on: display.id)?.stageID == StageID(rawValue: "2"))
        #expect(activeStageID(store) == StageID(rawValue: "2"))
    }

    @Test
    func stageIgnoresFocusRightAfterWindowDisappearance() {
        let a = powerWindow(1, x: 0)
        let b = powerWindow(2, x: 400)
        let c = powerWindow(3, x: 800)
        let store = twoStageStore(a: a, b: b, c: c)
        let clock = StabilizationClock()
        let input = UserInputActivity(monitoring: true)
        _ = service(windows: [a, b, c], focusedID: a.id, store: store, clock: clock, userInput: input).snapshot()

        clock.now += 0.1
        _ = service(windows: [a, b], focusedID: a.id, store: store, clock: clock, userInput: input).snapshot()

        // Saisie postérieure à la disparition, mais moins de 500 ms après : focus ignoré.
        clock.now += 0.3
        input.recordInput(at: clock.now - 0.05)
        _ = service(windows: [a, b], focusedID: b.id, store: store, clock: clock, userInput: input).snapshot()
        #expect(activeStageID(store) == StageID(rawValue: "1"))

        clock.now += 0.3
        input.recordInput(at: clock.now - 0.05)
        _ = service(windows: [a, b], focusedID: b.id, store: store, clock: clock, userInput: input).snapshot()
        #expect(activeStageID(store) == StageID(rawValue: "2"))
    }

    /// T211 : sans moniteur de saisie actif, aucune saisie n'est prouvée ; la stage ne suit pas.
    @Test
    func stageIgnoresFocusChangeWithoutInputMonitor() {
        let a = powerWindow(1, x: 0)
        let b = powerWindow(2, x: 400)
        let store = twoStageStore(a: a, b: b)
        let clock = StabilizationClock()

        let snapshot = service(windows: [a, b], focusedID: b.id, store: store, clock: clock, userInput: UserInputActivity()).snapshot()

        #expect(snapshot.state.activeScope(on: display.id)?.stageID == StageID(rawValue: "1"))
        #expect(activeStageID(store) == StageID(rawValue: "1"))
    }

    /// T201 / FR-005 : la nouvelle fenêtre, focalisée dès son apparition, se greffe à côté du
    /// dernier membre focalisé de la stage (son focus précédent), pas sur la première feuille.
    @Test
    func newBSPWindowIsInsertedNextToPreviouslyFocusedMember() throws {
        let a = powerWindow(1, x: 0)
        let b = powerWindow(2, x: 400)
        let c = powerWindow(3, x: 800)
        let newcomer = powerWindow(4, x: 1200)
        let tree = BSPTree.split(
            orientation: .vertical,
            ratio: 0.5,
            first: .leaf(a.id),
            second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(b.id), second: .leaf(c.id))
        )
        let store = StageStore(path: tempPath("bsp-anchor-stages"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: display.id, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(
                        id: StageID(rawValue: "1"),
                        mode: .spatialBsp,
                        focusedWindowID: b.id,
                        members: [member(a), member(b), member(c)],
                        bspTree: tree
                    )
                ])
            ],
            activeDisplayID: display.id
        ))
        let service = service(windows: [a, b, c, newcomer], focusedID: newcomer.id, store: store, clock: StabilizationClock())

        // Réconciliation unique dans le snapshot (SPEC-017 T081), sans second appel.
        _ = service.snapshot()

        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let reconciled = try #require(store.state().bspTree(for: scope))
        #expect(Set(reconciled.windowIDs) == [a.id, b.id, c.id, newcomer.id])
        #expect(Self.sibling(of: newcomer.id, in: reconciled) == .leaf(b.id))
    }

    private static func sibling(of id: WindowID, in tree: BSPTree) -> BSPTree? {
        guard case .split(_, _, let first, let second) = tree else { return nil }
        if first == .leaf(id) { return second }
        if second == .leaf(id) { return first }
        return sibling(of: id, in: first) ?? sibling(of: id, in: second)
    }

    @Test
    func tileClassificationSurvivesUnreadableAttributes() {
        let store = StageStore(path: tempPath("hysteresis-stages"))
        let clock = StabilizationClock()
        let furniture = WindowFurniture(
            hasCloseButton: true,
            hasFullscreenButton: true,
            fullscreenButtonEnabled: true,
            hasMinimizeButton: true,
            hasZoomButton: true
        )
        var readable = powerWindow(7, x: 100, width: 400, height: 300)
        readable.title = ""
        readable.role = "AXWindow"
        readable.subrole = "AXStandardWindow"
        readable.furniture = furniture
        var unreadable = readable
        unreadable.role = nil
        unreadable.subrole = nil
        unreadable.furniture = nil
        var unknown = unreadable
        unknown.id = WindowID(rawValue: 8)

        let first = service(windows: [readable], store: store, clock: clock, persist: false).snapshot(followFocus: false)
        clock.now += 0.5
        let second = service(windows: [unreadable, unknown], store: store, clock: clock, persist: false).snapshot(followFocus: false)

        #expect(first.windows.first { $0.window.id == readable.id }?.window.isTileCandidate == true)
        #expect(second.windows.first { $0.window.id == readable.id }?.window.isTileCandidate == true)
        #expect(second.windows.first { $0.window.id == unknown.id }?.window.isTileCandidate == false)
    }

    @Test(arguments: [false, true])
    func slowSnapshotIsReusableAfterPublication(producer: Bool) {
        let provider = SnapshotCallCountingProvider(display: display, windows: [powerWindow(1, x: 0)])
        let clock = StabilizationClock()
        provider.onWindows = { clock.now += 2 }
        let service = SnapshotService(provider: provider, frameWriter: RecordingWriter(),
            config: RoadieConfig(), stageStore: StageStore(path: tempPath("slow-snapshot-stages")),
            events: EventLog(path: tempPath("slow-snapshot-events")), persistStateChanges: false,
            clock: { clock.now })
        if producer { _ = service.producerSnapshot(cycle: 2) }
        else { _ = service.snapshot() }
        clock.now += 0.1
        _ = service.sharedSnapshot()
        #expect(provider.windowsCalls == 1)
        clock.now += producer ? 0.51 : 0.06
        _ = service.sharedSnapshot()
        #expect(provider.windowsCalls == 2)
        service.invalidateSharedSnapshot()
        _ = service.sharedSnapshot()
        #expect(provider.windowsCalls == 3)
    }

    @Test
    func sharedSnapshotReusesRecentSnapshotUntilExpiredOrInvalidated() {
        let provider = SnapshotCallCountingProvider(display: display, windows: [powerWindow(1, x: 0)])
        let clock = StabilizationClock()
        let service = SnapshotService(
            provider: provider,
            frameWriter: RecordingWriter(),
            config: RoadieConfig(),
            stageStore: StageStore(path: tempPath("shared-snapshot-stages")),
            events: EventLog(path: tempPath("shared-snapshot-events")),
            persistStateChanges: false,
            clock: { clock.now }
        )

        _ = service.snapshot()
        clock.now += 0.1
        _ = service.sharedSnapshot()
        #expect(provider.windowsCalls == 1)

        clock.now += 0.1
        _ = service.sharedSnapshot()
        #expect(provider.windowsCalls == 2)

        service.invalidateSharedSnapshot()
        _ = service.sharedSnapshot()
        #expect(provider.windowsCalls == 3)

        _ = service.sharedSnapshot(followFocus: false)
        #expect(provider.windowsCalls == 4)
    }

    /// T212 / FR-023 : un lecteur du processus consomme le snapshot du tick du tiler pendant tout
    /// son cycle (intervalle + marge, borné à 600 ms) au lieu de rescanner après 150 ms.
    @Test
    func readerConsumesTilerSnapshotDuringItsCycle() {
        let provider = SnapshotCallCountingProvider(display: display, windows: [powerWindow(1, x: 0)])
        let clock = StabilizationClock()
        let statePath = tempPath("producer-snapshot-stages")
        func make(persist: Bool) -> SnapshotService {
            SnapshotService(
                provider: provider,
                frameWriter: RecordingWriter(),
                config: RoadieConfig(),
                intentStore: LayoutIntentStore(path: tempPath("producer-snapshot-intents")),
                stageStore: StageStore(path: statePath),
                events: EventLog(path: tempPath("producer-snapshot-events")),
                persistStateChanges: persist,
                clock: { clock.now }
            )
        }
        let tiler = make(persist: true)
        let reader = make(persist: false)

        _ = tiler.producerSnapshot(cycle: 0.5)
        clock.now += 0.4
        _ = reader.sharedSnapshot()
        #expect(provider.windowsCalls == 1)

        clock.now += 0.3
        _ = reader.sharedSnapshot()
        #expect(provider.windowsCalls == 2)

        // Borne de 600 ms même pour un tiler lent.
        _ = tiler.producerSnapshot(cycle: 2)
        clock.now += 0.65
        _ = reader.sharedSnapshot()
        #expect(provider.windowsCalls == 4)
    }

    @Test
    func soloTiledWindowIsNotPersistedAsMaximized() {
        let visible = display.visibleFrame
        let solo = powerWindow(4, x: visible.x, y: visible.y, width: visible.width, height: visible.height)
        let store = StageStore(path: tempPath("solo-maximized-stages"))

        _ = service(windows: [solo], store: store, clock: StabilizationClock()).snapshot(followFocus: false)

        let member = store.state().scopes.flatMap(\.stages).flatMap(\.members).first { $0.windowID == solo.id }
        #expect(member != nil)
        #expect(member?.presentationState != .maximized)
    }

    @Test
    func zoomIntentStaysValidWhileZoomedWindowRemainsInScope() {
        let a = powerWindow(1, x: 0, width: 600)
        let b = powerWindow(2, x: 0, width: 600)
        let store = twoStageStore(a: a, b: powerWindow(9, x: 900))
        store.mutate { state in
            guard var scope = state.scopes.first else { return }
            scope.assign(window: b, to: StageID(rawValue: "1"))
            state.update(scope)
        }
        let intents = LayoutIntentStore(path: tempPath("zoom-intents"))
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        intents.save(LayoutIntent(
            scope: scope,
            windowIDs: [a.id, b.id],
            placements: [a.id: display.visibleFrame, b.id: display.visibleFrame],
            source: .command,
            zoomedWindowID: a.id
        ))
        let clock = StabilizationClock()

        let zoomed = service(windows: [a, b], store: store, clock: clock, intentStore: intents)
        #expect(zoomed.hasValidLayoutIntent(scope: scope, in: zoomed.snapshot(followFocus: false)))

        let withoutZoomed = service(windows: [b], store: store, clock: clock, intentStore: intents)
        #expect(!withoutZoomed.hasValidLayoutIntent(scope: scope, in: withoutZoomed.snapshot(followFocus: false)))
    }
}

@Suite
struct ConfigHotReloadTests {
    private func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test
    func currentConfigReloadsChangedFileAndKeepsLastValidConfig() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-hot-reload-\(UUID().uuidString).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        let eventPath = tempPath("config-hot-reload-events")
        try write("[tiling]\ngaps_inner = 10\n", to: url)
        let service = ConfigReloadService(activePath: url.path, eventLog: EventLog(path: eventPath))

        #expect(service.currentConfig().tiling.gapsInner == 10)

        try write("[tiling]\ngaps_inner = 140\n", to: url)
        #expect(service.currentConfig().tiling.gapsInner == 140)

        try write("[tiling]\ngaps_inner = \"not-a-number\"\n", to: url)
        #expect(service.currentConfig().tiling.gapsInner == 140)
        #expect(service.currentConfig().tiling.gapsInner == 140)
        #expect(service.state.lastValidation == .failed)

        let failures = (try String(contentsOfFile: eventPath, encoding: .utf8))
            .split(separator: "\n")
            .filter { $0.contains("\"config.reload_failed\"") }
        #expect(failures.count == 1)

        try write("[tiling]\ngaps_inner = 12\n", to: url)
        #expect(service.currentConfig().tiling.gapsInner == 12)
        #expect(service.state.lastValidation == .success)
    }
}

/// REL-030 : `master_ratio` de la configuration arrive au plan master-stack du daemon.
/// Deux cas :
/// - géométrie existante (fenêtres déjà membres de la stage) : le moteur garde une largeur en place
///   (maître actuel, ou bord de la pile collé au bord droit) et se sert du ratio configuré pour
///   choisir entre elles : ici 30 % ou 70 % ;
/// - nouvelles fenêtres (tout juste découvertes, largeur arbitraire donnée par macOS) : leur largeur
///   est ignorée et le ratio configuré s'applique : ici 80 % ou 20 %.
@Suite
struct MasterRatioWiringTests {
    @Test
    func configuredMasterRatioDrivesTheMasterStackPlan() {
        let display = powerDisplay("display-main", index: 1, x: 0)
        let master = powerWindow(10, x: 0, y: 0)
        let other = powerWindow(20, x: 700, y: 0)
        func masterWidth(_ ratio: Double) -> Double? {
            let store = StageStore(path: tempPath("master-ratio-wiring-\(ratio)"))
            store.save(PersistentStageState(
                scopes: [
                    PersistentStageScope(displayID: display.id, activeStageID: StageID(rawValue: "1"), stages: [
                        PersistentStage(id: StageID(rawValue: "1"), mode: .masterStack, members: [
                            PersistentStageMember(windowID: master.id, bundleID: master.bundleID, title: master.title, frame: master.frame),
                            PersistentStageMember(windowID: other.id, bundleID: other.bundleID, title: other.title, frame: other.frame),
                        ]),
                    ]),
                ],
                activeDisplayID: display.id
            ))
            let service = SnapshotService(
                provider: FakeProvider(displaySnapshots: [display], windowSnapshots: [master, other]),
                frameWriter: RecordingWriter(),
                config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .masterStack, gapsOuter: 0, gapsInner: 0, masterRatio: ratio)),
                // Stockage dédié : sinon une disposition mémorisée par un autre test remplace le plan.
                intentStore: LayoutIntentStore(path: tempPath("master-ratio-intents-\(ratio)")),
                stageStore: store
            )
            let plan = service.applyPlan(from: service.snapshot(followFocus: false))
            return plan.commands.first { $0.window.id == master.id }?.frame.width
        }

        #expect(masterWidth(0.8) == 300)
        #expect(masterWidth(0.2) == 700)
    }

    @Test
    func configuredMasterRatioAppliesToNewlyDiscoveredWindows() {
        let display = powerDisplay("display-main", index: 1, x: 0)
        let master = powerWindow(10, x: 0, y: 0)
        let other = powerWindow(20, x: 700, y: 0)
        func frames(_ ratio: Double) -> (master: Double?, other: Double?, otherX: Double?) {
            // Stockage vide : les deux fenêtres sont découvertes pendant ce snapshot (isNewlyScoped).
            let service = SnapshotService(
                provider: FakeProvider(displaySnapshots: [display], windowSnapshots: [master, other]),
                frameWriter: RecordingWriter(),
                config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .masterStack, gapsOuter: 0, gapsInner: 0, masterRatio: ratio)),
                intentStore: LayoutIntentStore(path: tempPath("master-ratio-new-intents-\(ratio)")),
                stageStore: StageStore(path: tempPath("master-ratio-new-\(ratio)"))
            )
            let snapshot = service.snapshot(followFocus: false)
            let allNew = snapshot.windows.allSatisfy { $0.isNewlyScoped }
            #expect(allNew)
            let plan = service.applyPlan(from: snapshot)
            let masterCommand = plan.commands.first { $0.window.id == master.id }
            let otherCommand = plan.commands.first { $0.window.id == other.id }
            return (masterCommand?.frame.width, otherCommand?.frame.width, otherCommand?.frame.x)
        }

        let wide = frames(0.8)
        #expect(wide.master == 800)
        #expect(wide.other == 200)
        #expect(wide.otherX == 800)
        #expect(frames(0.2).master == 200)
    }
}
