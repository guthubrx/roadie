import XCTest
import CoreGraphics
@testable import RoadieCore

final class MouseQuadrantTests: XCTestCase {
    let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let edge: CGFloat = 30

    func testTopLeftCorner() {
        XCTAssertEqual(computeQuadrant(cursor: CGPoint(x: 5, y: 5),
                                       frame: frame, edgeThreshold: edge), .topLeft)
    }

    func testTopRightCorner() {
        XCTAssertEqual(computeQuadrant(cursor: CGPoint(x: 995, y: 10),
                                       frame: frame, edgeThreshold: edge), .topRight)
    }

    func testBottomLeftCorner() {
        XCTAssertEqual(computeQuadrant(cursor: CGPoint(x: 10, y: 795),
                                       frame: frame, edgeThreshold: edge), .bottomLeft)
    }

    func testBottomRightCorner() {
        XCTAssertEqual(computeQuadrant(cursor: CGPoint(x: 990, y: 790),
                                       frame: frame, edgeThreshold: edge), .bottomRight)
    }

    func testTopEdge() {
        XCTAssertEqual(computeQuadrant(cursor: CGPoint(x: 500, y: 10),
                                       frame: frame, edgeThreshold: edge), .top)
    }

    func testBottomEdge() {
        XCTAssertEqual(computeQuadrant(cursor: CGPoint(x: 500, y: 790),
                                       frame: frame, edgeThreshold: edge), .bottom)
    }

    func testLeftEdge() {
        XCTAssertEqual(computeQuadrant(cursor: CGPoint(x: 10, y: 400),
                                       frame: frame, edgeThreshold: edge), .left)
    }

    func testRightEdge() {
        XCTAssertEqual(computeQuadrant(cursor: CGPoint(x: 990, y: 400),
                                       frame: frame, edgeThreshold: edge), .right)
    }

    func testCenterFallsToCenterIfTrueCenter() {
        XCTAssertEqual(computeQuadrant(cursor: CGPoint(x: 500, y: 400),
                                       frame: frame, edgeThreshold: edge), .center)
    }

    func testQuadrantInLeftThirdTopThird() {
        // Cursor in left-third + top-third (mais pas edge)
        XCTAssertEqual(computeQuadrant(cursor: CGPoint(x: 200, y: 200),
                                       frame: frame, edgeThreshold: edge), .topLeft)
    }

    // MARK: - computeResizedFrame

    let start = CGRect(x: 100, y: 100, width: 800, height: 600)

    func testResizeBottomRight() {
        let r = computeResizedFrame(start: start,
                                    delta: CGPoint(x: 50, y: 30),
                                    quadrant: .bottomRight)
        XCTAssertEqual(r.origin, start.origin)
        XCTAssertEqual(r.size.width, 850)
        XCTAssertEqual(r.size.height, 630)
    }

    func testResizeTopLeft() {
        let r = computeResizedFrame(start: start,
                                    delta: CGPoint(x: -50, y: -30),
                                    quadrant: .topLeft)
        XCTAssertEqual(r.origin.x, 50)
        XCTAssertEqual(r.origin.y, 70)
        XCTAssertEqual(r.size.width, 850)
        XCTAssertEqual(r.size.height, 630)
    }

    func testResizeBottomEdge() {
        let r = computeResizedFrame(start: start,
                                    delta: CGPoint(x: 0, y: 100),
                                    quadrant: .bottom)
        XCTAssertEqual(r.origin, start.origin)
        XCTAssertEqual(r.size.width, 800)
        XCTAssertEqual(r.size.height, 700)
    }

    func testResizeMinClamp() {
        // Trying to shrink below 100x100 is clamped.
        let tiny = CGRect(x: 0, y: 0, width: 200, height: 200)
        let r = computeResizedFrame(start: tiny,
                                    delta: CGPoint(x: 500, y: 500),
                                    quadrant: .topLeft)
        XCTAssertGreaterThanOrEqual(r.size.width, 100)
        XCTAssertGreaterThanOrEqual(r.size.height, 100)
    }
}
