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
