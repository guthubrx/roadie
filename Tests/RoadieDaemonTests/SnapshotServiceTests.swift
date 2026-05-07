import CoreGraphics
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

private struct FakeProvider: SystemSnapshotProviding {
    var permissionSnapshot = PermissionSnapshot(accessibilityTrusted: true)
    var displaySnapshots: [DisplaySnapshot]
    var windowSnapshots: [WindowSnapshot]

    func permissions(prompt: Bool) -> PermissionSnapshot { permissionSnapshot }
    func displays() -> [DisplaySnapshot] { displaySnapshots }
    func windows() -> [WindowSnapshot] { windowSnapshots }
}

private struct FakeWriter: WindowFrameWriting {
    var actualFrames: [WindowID: Rect]

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        actualFrames[window.id]?.cgRect
    }
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
}
