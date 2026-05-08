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

    func permissions(prompt: Bool) -> PermissionSnapshot { permissionSnapshot }
    func displays() -> [DisplaySnapshot] { displaySnapshots }
    func windows() -> [WindowSnapshot] { windowSnapshots }
    func focusedWindowID() -> WindowID? { focusedID }
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
            config: RoadieConfig()
        )

        let snapshot = service.snapshot()

        #expect(snapshot.windows.first?.scope?.displayID == displayB)
        #expect(snapshot.windows.first?.scope?.desktopID == DesktopID(rawValue: 1))
        #expect(snapshot.windows.first?.scope?.stageID == StageID(rawValue: "1"))
        #expect(snapshot.state.stage(scope: snapshot.windows.first!.scope!)?.windowIDs == [window.id])
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
    func snapshotIgnoresMacFocusWhenItPointsToHiddenInactiveStage() {
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
    func configExclusionsKeepMatchingBundlesUnscoped() {
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

        #expect(service.snapshot().windows.first?.scope == nil)
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
    func snapshotMigratesDisconnectedDisplayScopesToFallbackDisplay() {
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
        let migrated = stageStore.state()
        let liveScope = migrated.scopes.first { $0.displayID == liveDisplay && $0.desktopID == desktop }

        #expect(migrated.scopes.allSatisfy { $0.displayID == liveDisplay })
        #expect(migrated.desktopSelections.allSatisfy { $0.displayID == liveDisplay })
        #expect(migrated.desktopLabels.isEmpty)
        #expect(migrated.activeDisplayID == liveDisplay)
        #expect(liveScope?.memberIDs(in: StageID(rawValue: "1")) == [liveWindow.id])
        #expect(liveScope?.memberIDs(in: StageID(rawValue: "2")) == [movedWindow.id])
        #expect(liveScope?.memberIDs(in: StageID(rawValue: "4")) == [hiddenWindow.id])
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func snapshotMigratesDisconnectedDisplayScopesToActiveLiveDisplayWhenSeveralRemain() {
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
        let migrated = stageStore.state()
        let scopeA = migrated.scopes.first { $0.displayID == displayA && $0.desktopID == desktop }
        let scopeB = migrated.scopes.first { $0.displayID == displayB && $0.desktopID == desktop }

        #expect(migrated.scopes.allSatisfy { $0.displayID != staleDisplay })
        #expect(migrated.activeDisplayID == displayB)
        #expect(scopeA?.memberIDs(in: StageID(rawValue: "3")).isEmpty ?? true)
        #expect(scopeB?.memberIDs(in: StageID(rawValue: "3")) == [window.id])
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
        #expect(healed.desktopSelections.allSatisfy { $0.displayID == display })
        #expect(healed.desktopLabels.isEmpty)
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
