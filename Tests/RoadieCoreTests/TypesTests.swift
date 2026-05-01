import XCTest
@testable import RoadieCore

final class TypesTests: XCTestCase {
    func test_direction_orientation() {
        XCTAssertEqual(Direction.left.orientation, .horizontal)
        XCTAssertEqual(Direction.right.orientation, .horizontal)
        XCTAssertEqual(Direction.up.orientation, .vertical)
        XCTAssertEqual(Direction.down.orientation, .vertical)
    }

    func test_direction_sign() {
        XCTAssertEqual(Direction.left.sign, -1)
        XCTAssertEqual(Direction.up.sign, -1)
        XCTAssertEqual(Direction.right.sign, 1)
        XCTAssertEqual(Direction.down.sign, 1)
    }

    func test_orientation_opposite() {
        XCTAssertEqual(Orientation.horizontal.opposite, .vertical)
        XCTAssertEqual(Orientation.vertical.opposite, .horizontal)
    }

    func test_subrole_floating_default() {
        XCTAssertFalse(AXSubrole.standard.isFloatingByDefault)
        XCTAssertTrue(AXSubrole.dialog.isFloatingByDefault)
        XCTAssertTrue(AXSubrole.sheet.isFloatingByDefault)
        XCTAssertTrue(AXSubrole.systemDialog.isFloatingByDefault)
    }

    func test_subrole_init_from_ax_value() {
        XCTAssertEqual(AXSubrole(rawAXValue: "AXStandardWindow"), .standard)
        XCTAssertEqual(AXSubrole(rawAXValue: "AXDialog"), .dialog)
        XCTAssertEqual(AXSubrole(rawAXValue: nil), .unknown)
        XCTAssertEqual(AXSubrole(rawAXValue: "garbage"), .unknown)
    }

    func test_window_state_isTileable() {
        let standard = WindowState(cgWindowID: 1, pid: 1, bundleID: "com.app",
                                   title: "t", frame: .zero,
                                   subrole: .standard, isFloating: false)
        XCTAssertTrue(standard.isTileable)

        let floating = WindowState(cgWindowID: 1, pid: 1, bundleID: "com.app",
                                   title: "t", frame: .zero,
                                   subrole: .dialog, isFloating: true)
        XCTAssertFalse(floating.isTileable)
    }
}
