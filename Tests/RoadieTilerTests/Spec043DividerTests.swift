import CoreGraphics
import Testing
import RoadieCore
import RoadieTiler

@Suite
struct Spec043DividerTests {
    private func id(_ value: UInt32) -> WindowID { WindowID(rawValue: value) }
    private let rect = CGRect(x: 100, y: -800, width: 1000, height: 600)
    private var pair: BSPTree {
        .split(orientation: .vertical, ratio: 0.5, first: .leaf(id(1)), second: .leaf(id(2)))
    }
    private var four: BSPTree {
        .split(orientation: .vertical, ratio: 0.4,
               first: .split(orientation: .horizontal, ratio: 0.3, first: .leaf(id(1)), second: .leaf(id(2))),
               second: .split(orientation: .horizontal, ratio: 0.7, first: .leaf(id(3)), second: .leaf(id(4))))
    }

    @Test
    func twoWindowsExposeTheirActualGapAndRatio() throws {
        let divider = try #require(pair.dividers(in: rect, innerGap: 10).first)
        #expect(divider.path == [])
        #expect(divider.orientation == .vertical)
        #expect(divider.ratio == 0.5)
        #expect(divider.hitRect == CGRect(x: 596, y: -800, width: 8, height: 600))
        #expect(divider.position == CGPoint(x: 600, y: -500))
        for frame in pair.place(in: rect, innerGap: 10).values {
            #expect(frame.intersection(divider.hitRect).isEmpty)
        }
    }

    @Test
    func fourWindowsKeepPathsAndOnlyTheChosenRatioChanges() throws {
        let dividers = four.dividers(in: rect, innerGap: 10)
        #expect(dividers.map(\.path) == [[], [true], [false]])
        let changed = try #require(four.movingDivider(at: [false], to: CGPoint(x: 900, y: -500), in: rect, innerGap: 10))
        let after = changed.dividers(in: rect, innerGap: 10)
        #expect(after[0].ratio == dividers[0].ratio)
        #expect(after[1].ratio == dividers[1].ratio)
        #expect(after[2].ratio != dividers[2].ratio)
        #expect(changed.windowIDs == four.windowIDs)
        for divider in dividers {
            for frame in four.place(in: rect, innerGap: 10).values {
                #expect(frame.intersection(divider.hitRect).isEmpty)
            }
        }
    }

    @Test
    func projectionRetainsFullTreePathAndAbsentLeaves() throws {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.2, first: .leaf(id(9)), second: pair)
        let divider = try #require(tree.dividers(in: rect, innerGap: 10, excluding: [id(9)]).first)
        #expect(divider.path == [false])
        #expect(divider.container == rect)
        #expect(tree.movingDivider(at: [], to: .zero, in: rect, excluding: [id(9)]) == nil)
        let changed = try #require(tree.movingDivider(at: [false], to: CGPoint(x: 700, y: -500),
                                                     in: rect, innerGap: 10, excluding: [id(9)]))
        guard case .split(let orientation, let ratio, let first, let second) = changed else {
            Issue.record("Racine perdue"); return
        }
        #expect(orientation == .vertical)
        #expect(ratio == 0.2)
        #expect(first == .leaf(id(9)))
        #expect(second.windowIDs == pair.windowIDs)
    }

    @Test
    func emptySingleAndInvalidPathsHaveNoDivider() {
        #expect(BSPTree.empty.dividers(in: rect).isEmpty)
        #expect(BSPTree.leaf(id(1)).dividers(in: rect).isEmpty)
        #expect(pair.dividers(in: rect, excluding: [id(1)]).isEmpty)
        #expect(pair.dividers(in: .zero).isEmpty)
        #expect(pair.movingDivider(at: [true], to: .zero, in: rect) == nil)
        #expect(pair.movingDivider(at: [], to: CGPoint(x: CGFloat.nan, y: 0), in: rect) == nil)
    }

    @Test
    func noGapNeverCoversAWindowAndFractionalGapStaysFree() {
        #expect(pair.dividers(in: rect, innerGap: 0).allSatisfy { $0.hitRect.isEmpty })
        let fractional = CGRect(x: 100.3, y: -800.2, width: 1000.6, height: 600.7)
        let frames = four.place(in: fractional, innerGap: 2.4)
        for divider in four.dividers(in: fractional, innerGap: 2.4) {
            for frame in frames.values {
                #expect(frame.intersection(divider.hitRect).isEmpty)
            }
        }
    }

    @Test(arguments: [CGPoint(x: -10000, y: -500), CGPoint(x: 10000, y: -500)])
    func movingIsClampedToExistingRatioBounds(point: CGPoint) throws {
        let changed = try #require(pair.movingDivider(at: [], to: point, in: rect, innerGap: 10))
        let divider = try #require(changed.dividers(in: rect, innerGap: 10).first)
        #expect(divider.ratio == (point.x < rect.minX ? 0.05 : 0.95))
    }

    @Test
    func minimumOfEitherSideBoundsTheMovement() throws {
        let minimums = [id(1): CGSize(width: 400, height: 0), id(2): CGSize(width: 350, height: 0)]
        for point in [CGPoint(x: -1000, y: -500), CGPoint(x: 4000, y: -500)] {
            let changed = try #require(pair.movingDivider(at: [], to: point, in: rect, innerGap: 10, knownMinimums: minimums))
            let frames = changed.place(in: rect, innerGap: 10)
            #expect(try #require(frames[id(1)]).width >= 400)
            #expect(try #require(frames[id(2)]).width >= 350)
        }
    }

    @Test
    func nestedMinimumKeepsUnrelatedRatiosAndAlreadyImpossibleSize() throws {
        let changed = try #require(four.movingDivider(at: [], to: CGPoint(x: 200, y: -500), in: rect, innerGap: 10,
                                                     knownMinimums: [id(2): CGSize(width: 350, height: 0)]))
        let frames = changed.place(in: rect, innerGap: 10)
        #expect(try #require(frames[id(2)]).width >= 350)
        #expect(changed.dividers(in: rect, innerGap: 10).dropFirst().map(\.ratio) == [0.3, 0.7])
        let impossible = try #require(pair.movingDivider(at: [], to: CGPoint(x: 200, y: -500), in: rect, innerGap: 10,
                                                        knownMinimums: [id(1): CGSize(width: 800, height: 0)]))
        #expect(impossible.place(in: rect, innerGap: 10)[id(1)] == pair.place(in: rect, innerGap: 10)[id(1)])
    }

    @Test
    func rereadingChosenPositionDoesNotDrift() throws {
        let target = CGPoint(x: 741, y: -500)
        let moved = try #require(pair.movingDivider(at: [], to: target, in: rect, innerGap: 10))
        let divider = try #require(moved.dividers(in: rect, innerGap: 10).first)
        #expect(divider.position.x == target.x)
        let reread = try #require(moved.movingDivider(at: [], to: divider.position, in: rect, innerGap: 10))
        #expect(reread.place(in: rect, innerGap: 10) == moved.place(in: rect, innerGap: 10))
    }

    @Test
    func screenTranslationProducesTheSameRatioAndRelativeGeometry() throws {
        let other = rect.offsetBy(dx: -2500, dy: 1800)
        let a = try #require(pair.movingDivider(at: [], to: CGPoint(x: 750, y: -500), in: rect, innerGap: 10))
        let b = try #require(pair.movingDivider(at: [], to: CGPoint(x: -1750, y: 1300), in: other, innerGap: 10))
        #expect(a == b)
        let left = try #require(a.dividers(in: rect, innerGap: 10).first)
        let right = try #require(b.dividers(in: other, innerGap: 10).first)
        #expect(left.hitRect.offsetBy(dx: -2500, dy: 1800) == right.hitRect)
    }
}
