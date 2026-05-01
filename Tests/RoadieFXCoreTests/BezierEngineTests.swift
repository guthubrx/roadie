import XCTest
@testable import RoadieFXCore

final class BezierEngineTests: XCTestCase {
    func testLinearAtBoundaries() {
        let curve = BezierCurve.linear
        XCTAssertEqual(curve.sample(0.0), 0.0, accuracy: 0.005)
        XCTAssertEqual(curve.sample(1.0), 1.0, accuracy: 0.005)
    }

    func testLinearAtMiddle() {
        let curve = BezierCurve.linear
        XCTAssertEqual(curve.sample(0.5), 0.5, accuracy: 0.005)
    }

    func testEaseStartsSlow() {
        let curve = BezierCurve.ease
        XCTAssertEqual(curve.sample(0.0), 0.0, accuracy: 0.005)
        // ease commence lentement, sample à 0.1 doit être < 0.1
        XCTAssertLessThan(curve.sample(0.1), 0.2)
    }

    func testEaseInOutSymmetric() {
        let curve = BezierCurve.easeInOut
        // easeInOut symétrique : sample(0.5) ≈ 0.5
        XCTAssertEqual(curve.sample(0.5), 0.5, accuracy: 0.05)
    }

    func testEaseOutBackOvershoots() {
        let curve = BezierCurve.easeOutBack
        // Doit dépasser 1.0 vers la fin (overshoot)
        let mid = curve.sample(0.7)
        XCTAssertGreaterThan(mid, 1.0)
    }

    func testClampingTBeyondRange() {
        let curve = BezierCurve.linear
        XCTAssertEqual(curve.sample(-1.0), 0.0, accuracy: 0.005)
        XCTAssertEqual(curve.sample(2.0), 1.0, accuracy: 0.005)
    }

    func testCustomCurveSnappy() {
        let snappy = BezierCurve.snappy
        XCTAssertEqual(snappy.sample(0.0), 0.0, accuracy: 0.005)
        XCTAssertEqual(snappy.sample(1.0), 1.0, accuracy: 0.005)
        // snappy : commence rapide, finit lentement avec léger overshoot
        XCTAssertGreaterThan(snappy.sample(0.5), 0.5)
    }

    func testHashable() {
        let a = BezierCurve.linear
        let b = BezierCurve.linear
        XCTAssertEqual(a, b)
    }
}
