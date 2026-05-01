import XCTest
@testable import RoadieAnimations

final class BezierLibraryTests: XCTestCase {
    func testBuiltInsPresent() {
        let lib = BezierLibrary()
        XCTAssertNotNil(lib.curve(named: "linear"))
        XCTAssertNotNil(lib.curve(named: "ease"))
        XCTAssertNotNil(lib.curve(named: "easeInOut"))
        XCTAssertNotNil(lib.curve(named: "snappy"))
        XCTAssertNotNil(lib.curve(named: "smooth"))
        XCTAssertNotNil(lib.curve(named: "easeOutBack"))
    }

    func testUnknownReturnsNil() {
        let lib = BezierLibrary()
        XCTAssertNil(lib.curve(named: "doesnotexist"))
    }

    func testRegisterCustom() {
        let lib = BezierLibrary()
        XCTAssertNil(lib.curve(named: "myEase"))
        lib.register(name: "myEase", curve: .linear)
        XCTAssertNotNil(lib.curve(named: "myEase"))
    }
}
