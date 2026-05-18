import CoreGraphics
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

@Suite
struct TargetGridServiceTests {
    @Test
    func gridSplitsDisplayIntoDeterministicCells() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-main"),
            index: 1,
            name: "Main",
            frame: Rect(x: 0, y: 0, width: 900, height: 900),
            visibleFrame: Rect(x: 0, y: 0, width: 900, height: 900),
            isMain: true
        )

        let cells = TargetGridService.cells(
            display: display,
            parentPath: "",
            rows: 3,
            columns: 3,
            maxDepth: 3,
            alphabet: "asdfghjkl"
        )

        #expect(cells.count == 9)
        #expect(cells[0].path == "A")
        #expect(cells[0].frame == Rect(x: 0, y: 0, width: 300, height: 300))
        #expect(cells[8].path == "L")
        #expect(cells[8].frame == Rect(x: 600, y: 600, width: 300, height: 300))
    }

    @Test
    func nestedGridPathResolvesInsideParentCell() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-main"),
            index: 1,
            name: "Main",
            frame: Rect(x: 0, y: 0, width: 900, height: 900),
            visibleFrame: Rect(x: 0, y: 0, width: 900, height: 900),
            isMain: true
        )

        let cell = TargetGridService.cell(
            display: display,
            path: "AA",
            rows: 3,
            columns: 3,
            maxDepth: 3,
            alphabet: "asdfghjkl"
        )

        #expect(cell?.frame == Rect(x: 0, y: 0, width: 100, height: 100))
        #expect(cell?.center == CGPointCodable(CGPoint(x: 50, y: 50)))
    }

    @Test
    func gridCanUseFocusedWindowFrameAsRecursiveRoot() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-main"),
            index: 1,
            name: "Main",
            frame: Rect(x: 0, y: 0, width: 900, height: 900),
            visibleFrame: Rect(x: 0, y: 0, width: 900, height: 900),
            isMain: true
        )
        let windowFrame = Rect(x: 90, y: 180, width: 450, height: 450)

        let cells = TargetGridService.cells(
            display: display,
            rootFrame: windowFrame,
            parentPath: "",
            rows: 3,
            columns: 3,
            maxDepth: 3,
            alphabet: "asdfghjkl"
        )
        let nested = TargetGridService.cell(
            display: display,
            rootFrame: windowFrame,
            path: "AA",
            rows: 3,
            columns: 3,
            maxDepth: 3,
            alphabet: "asdfghjkl"
        )

        #expect(cells[0].frame == Rect(x: 90, y: 180, width: 150, height: 150))
        #expect(cells[8].frame == Rect(x: 390, y: 480, width: 150, height: 150))
        #expect(nested?.frame == Rect(x: 90, y: 180, width: 50, height: 50))
    }

    @Test
    func focusedWindowScopeUsesLiveProviderFocusAsRoot() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-main"),
            index: 1,
            name: "Main",
            frame: Rect(x: 0, y: 0, width: 900, height: 900),
            visibleFrame: Rect(x: 0, y: 0, width: 900, height: 900),
            isMain: true
        )
        let stale = WindowSnapshot(
            id: WindowID(rawValue: 10),
            pid: 10,
            appName: "Teams",
            bundleID: "com.microsoft.teams",
            title: "Call",
            frame: Rect(x: 0, y: 0, width: 300, height: 300),
            isOnScreen: true,
            isTileCandidate: true
        )
        let live = WindowSnapshot(
            id: WindowID(rawValue: 20),
            pid: 20,
            appName: "iTerm2",
            bundleID: "com.googlecode.iterm2",
            title: "Shell",
            frame: Rect(x: 450, y: 180, width: 360, height: 360),
            isOnScreen: true,
            isTileCandidate: true
        )
        let config = RoadieConfig(experimental: ExperimentalConfig(
            targetGrid: TargetGridConfig(enabled: true, rows: 3, columns: 3, maxDepth: 3, hintCharacters: "asdfghjkl")
        ))
        let service = SnapshotService(
            provider: GridProvider(displaySnapshots: [display], windowSnapshots: [stale, live], focusedID: live.id),
            frameWriter: GridWriter(),
            config: config,
            stageStore: StageStore(path: tempPath("target-grid-focused-root"))
        )
        let grid = TargetGridService(service: service)

        let root = grid.root(scope: .focusedWindow)
        let report = root.map { grid.report(root: $0) }

        #expect(root?.scope == .focusedWindow)
        #expect(root?.frame == live.frame)
        #expect(report?.cells.first?.frame == Rect(x: 450, y: 180, width: 120, height: 120))
    }

    @Test
    func gridPathForPointUsesConfiguredDepth() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-main"),
            index: 1,
            name: "Main",
            frame: Rect(x: 0, y: 0, width: 900, height: 900),
            visibleFrame: Rect(x: 0, y: 0, width: 900, height: 900),
            isMain: true
        )

        let path = TargetGridService.path(
            for: CGPoint(x: 50, y: 50),
            display: display,
            rows: 3,
            columns: 3,
            maxDepth: 3,
            alphabet: "asdfghjkl"
        )

        #expect(path == "AAG")
    }
}

private struct GridProvider: SystemSnapshotProviding {
    var permissionSnapshot = PermissionSnapshot(accessibilityTrusted: true)
    var displaySnapshots: [DisplaySnapshot]
    var windowSnapshots: [WindowSnapshot]
    var focusedID: WindowID?

    func permissions(prompt: Bool) -> PermissionSnapshot { permissionSnapshot }
    func displays() -> [DisplaySnapshot] { displaySnapshots }
    func windows() -> [WindowSnapshot] { windowSnapshots }
    func focusedWindowID() -> WindowID? { focusedID }
    func mouseLocation() -> CGPoint? { nil }
}

private final class GridWriter: WindowFrameWriting, @unchecked Sendable {
    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? { frame }
    func focus(_ window: WindowSnapshot) -> Bool { true }
}
