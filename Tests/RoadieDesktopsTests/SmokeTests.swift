import XCTest
@testable import RoadieDesktops

final class SmokeTests: XCTestCase {
    func testModuleVersion() {
        XCTAssertEqual(RoadieDesktops.version, "0.2.0")
    }
}
