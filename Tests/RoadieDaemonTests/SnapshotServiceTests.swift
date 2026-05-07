import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

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
        let stageStore = StageStore(path: stagePath)
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

        #expect(switchResult.changed)
        #expect(switchWriter.requestedFrames[left.id] == Rect(x: 999, y: 499, width: 495, height: 500))
        #expect(switchWriter.requestedFrames[right.id] == Rect(x: 8, y: 8, width: 984, height: 484))
        try? FileManager.default.removeItem(atPath: stagePath)
    }

    @Test
    func stageCreateRenameListAndDeleteEmptyInactiveStage() {
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
        let list = commands.list()
        let deleteActive = commands.delete("1")
        let deleteCreated = commands.delete("9")
        let scope = stageStore.state().scopes.first { $0.displayID == display }

        #expect(create.changed)
        #expect(rename.changed)
        #expect(list.message.contains("9\tbsp\t0\tInbox"))
        #expect(!deleteActive.changed)
        #expect(deleteCreated.changed)
        #expect(scope?.stages.contains(where: { $0.id == StageID(rawValue: "9") }) == false)
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
        try? FileManager.default.removeItem(atPath: stagePath)
    }
}
