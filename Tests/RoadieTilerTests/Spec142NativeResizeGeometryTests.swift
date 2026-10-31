import CoreGraphics
import Testing
import RoadieCore
@testable import RoadieTiler

@Suite struct Spec142NativeResizeGeometryTests {
    private let a = WindowID(rawValue: 1)
    private let b = WindowID(rawValue: 2)
    private let c = WindowID(rawValue: 3)
    private let area = CGRect(x: -1000, y: -600, width: 1000, height: 600)

    @Test func neighborsFollowBeforeReleaseAndReturningDoesNotDrift() throws {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(a), second: .leaf(b))
        let start = try #require(tree.place(in: area, innerGap: 10)[a])
        let resize = try #require(BSPNativeResize(tree: tree, windowID: a, in: area, innerGap: 10))
        var frame = start
        frame.size.width += 100
        let changed = try #require(resize.layout(observedFrame: frame))
        #expect(changed.frames[b]?.minX == frame.maxX + 10)
        #expect(changed.frames[b]?.maxX == area.maxX)
        #expect(try #require(resize.layout(observedFrame: start)).frames == tree.place(in: area, innerGap: 10))
        #expect(changed.tree.windowIDs == tree.windowIDs)
    }

    @Test func cornerChangesTwoFencesAndKeepsAbsentLeaves() throws {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5,
            first: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(a), second: .leaf(c)),
            second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(b), second: .leaf(WindowID(rawValue: 99))))
        let absent: Set<WindowID> = [WindowID(rawValue: 99)]
        let resize = try #require(BSPNativeResize(tree: tree, windowID: a, in: area, innerGap: 10, excluding: absent))
        var frame = try #require(tree.projected(excluding: absent).place(in: area, innerGap: 10)[a])
        frame.size.width += 80
        frame.size.height += 50
        let layout = try #require(resize.layout(observedFrame: frame))
        #expect(layout.frames[b]?.minX == frame.maxX + 10)
        #expect(layout.frames[c]?.minY == frame.maxY + 10)
        #expect(layout.tree.windowIDs == tree.windowIDs)
        #expect(layout.frames[WindowID(rawValue: 99)] == nil)
    }

    @Test func movingWithoutResizingDoesNotChangeTree() throws {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(a), second: .leaf(b))
        let resize = try #require(BSPNativeResize(tree: tree, windowID: a, in: area))
        let start = try #require(tree.place(in: area, innerGap: 0)[a])
        #expect(resize.layout(observedFrame: start.offsetBy(dx: 30, dy: 20)) == nil)
        #expect(resize.layout(observedFrame: CGRect(x: 0, y: 0, width: CGFloat.nan, height: 10)) == nil)
    }

    @Test func nativeSourceIsNotInventedBelowNeighborMinimum() throws {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(a), second: .leaf(b))
        let resize = try #require(BSPNativeResize(tree: tree, windowID: a, in: area, innerGap: 10,
            knownMinimums: [b: CGSize(width: 400, height: 100)]))
        var frame = try #require(tree.place(in: area, innerGap: 10)[a])
        frame.size.width = 850
        let layout = try #require(resize.layout(observedFrame: frame))
        #expect(try #require(layout.frames[b]).width >= 400)
    }
}

@Suite struct Spec142NativeResizeCornersTests {
    @Test(arguments: [1, 2, 3, 4]) func allFourNativeCorners(id: UInt32) throws {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5,
            first: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(WindowID(rawValue: 1)), second: .leaf(WindowID(rawValue: 3))),
            second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(WindowID(rawValue: 2)), second: .leaf(WindowID(rawValue: 4))))
        let area = CGRect(x: -1200, y: -800, width: 1200, height: 800)
        let key = WindowID(rawValue: id)
        var frame = try #require(tree.place(in: area, innerGap: 10)[key])
        if id == 2 || id == 4 { frame.origin.x -= 80 }
        if id == 3 || id == 4 { frame.origin.y -= 50 }
        frame.size.width += 80; frame.size.height += 50
        let geometry = try #require(BSPNativeResize(tree: tree, windowID: key, in: area, innerGap: 10))
        #expect(try #require(geometry.layout(observedFrame: frame)).frames[key] == frame)
    }

    @Test func symmetricResizeUpdatesBothSameAxisAncestors() throws {
        let a = WindowID(rawValue: 1), b = WindowID(rawValue: 2), c = WindowID(rawValue: 3)
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.6,
            first: .split(orientation: .vertical, ratio: 0.5, first: .leaf(a), second: .leaf(b)), second: .leaf(c))
        let area = CGRect(x: 0, y: 0, width: 1200, height: 800)
        var frame = try #require(tree.place(in: area, innerGap: 10)[b])
        frame.origin.x -= 40; frame.size.width += 80
        let geometry = try #require(BSPNativeResize(tree: tree, windowID: b, in: area, innerGap: 10))
        #expect(try #require(geometry.layout(observedFrame: frame)).frames[b] == frame)
    }
}
