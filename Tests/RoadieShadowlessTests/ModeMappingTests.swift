import XCTest
@testable import RoadieShadowless

final class ModeMappingTests: XCTestCase {
    func testAllModeReturnsClampedDensityRegardlessOfFloating() {
        XCTAssertEqual(targetDensity(isFloating: true, mode: .all, configDensity: 0.5), 0.5)
        XCTAssertEqual(targetDensity(isFloating: false, mode: .all, configDensity: 0.5), 0.5)
    }

    func testTiledOnlyMode() {
        // Fenêtre tilée (non floating) → density appliquée
        XCTAssertEqual(targetDensity(isFloating: false, mode: .tiledOnly, configDensity: 0.0), 0.0)
        // Fenêtre floating → nil (pas touchée)
        XCTAssertNil(targetDensity(isFloating: true, mode: .tiledOnly, configDensity: 0.0))
    }

    func testFloatingOnlyMode() {
        XCTAssertEqual(targetDensity(isFloating: true, mode: .floatingOnly, configDensity: 0.3), 0.3)
        XCTAssertNil(targetDensity(isFloating: false, mode: .floatingOnly, configDensity: 0.3))
    }

    func testDensityClampingAbove() {
        XCTAssertEqual(targetDensity(isFloating: false, mode: .all, configDensity: 1.5), 1.0)
    }

    func testDensityClampingBelow() {
        XCTAssertEqual(targetDensity(isFloating: false, mode: .all, configDensity: -0.2), 0.0)
    }

    func testDensityZeroNoOp() {
        XCTAssertEqual(targetDensity(isFloating: false, mode: .all, configDensity: 0.0), 0.0)
    }

    func testDensityOneIsDefault() {
        XCTAssertEqual(targetDensity(isFloating: false, mode: .all, configDensity: 1.0), 1.0)
    }
}
