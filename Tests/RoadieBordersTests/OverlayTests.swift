import XCTest
import AppKit
@testable import RoadieBorders

final class OverlayTests: XCTestCase {
    func testNSColorFromValidHex() {
        let c = nsColor(fromHex: "#7AA2F7")
        XCTAssertNotNil(c)
        XCTAssertEqual(c?.redComponent ?? 0, 0x7A / 255.0, accuracy: 0.001)
        XCTAssertEqual(c?.greenComponent ?? 0, 0xA2 / 255.0, accuracy: 0.001)
        XCTAssertEqual(c?.blueComponent ?? 0, 0xF7 / 255.0, accuracy: 0.001)
    }

    func testNSColorFromHexWithAlpha() {
        let c = nsColor(fromHex: "#FF000080")
        XCTAssertNotNil(c)
        XCTAssertEqual(c?.alphaComponent ?? 0, 0x80 / 255.0, accuracy: 0.001)
    }

    func testNSColorFromInvalidHexReturnsNil() {
        XCTAssertNil(nsColor(fromHex: "garbage"))
        XCTAssertNil(nsColor(fromHex: "#XYZ"))
        XCTAssertNil(nsColor(fromHex: ""))
    }

    @MainActor
    func testOverlayInitWithValidFrame() {
        let frame = CGRect(x: 100, y: 100, width: 400, height: 300)
        let overlay = BorderOverlay(wid: 42, frame: frame, thickness: 2, color: .red)
        XCTAssertEqual(overlay.trackedWID, 42)
        XCTAssertEqual(overlay.thickness, 2)
        XCTAssertEqual(overlay.trackedFrame, frame)
        overlay.close()
    }

    @MainActor
    func testOverlayUpdateFrame() {
        let initialFrame = CGRect(x: 100, y: 100, width: 400, height: 300)
        let overlay = BorderOverlay(wid: 1, frame: initialFrame, thickness: 2, color: .blue)
        let newFrame = CGRect(x: 200, y: 200, width: 500, height: 400)
        overlay.updateFrame(newFrame)
        XCTAssertEqual(overlay.trackedFrame, newFrame)
        overlay.close()
    }

    @MainActor
    func testOverlayUpdateThickness() {
        let frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        let overlay = BorderOverlay(wid: 1, frame: frame, thickness: 2, color: .green)
        overlay.updateThickness(8)
        XCTAssertEqual(overlay.thickness, 8)
        overlay.close()
    }

    @MainActor
    func testOverlayUpdateColor() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let overlay = BorderOverlay(wid: 1, frame: frame, thickness: 1, color: .red)
        overlay.updateColor(.yellow)
        XCTAssertEqual(overlay.color, .yellow)
        overlay.close()
    }
}
