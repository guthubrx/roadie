import XCTest
@testable import RoadieBorders

final class ConfigTests: XCTestCase {
    func testParseHexColor6Digits() {
        let c = parseHexColor("#7AA2F7")
        XCTAssertNotNil(c)
        XCTAssertEqual(c?.r, 0x7A)
        XCTAssertEqual(c?.g, 0xA2)
        XCTAssertEqual(c?.b, 0xF7)
        XCTAssertEqual(c?.a, 0xFF)
    }

    func testParseHexColor8Digits() {
        let c = parseHexColor("#7AA2F780")
        XCTAssertEqual(c?.r, 0x7A)
        XCTAssertEqual(c?.a, 0x80)
    }

    func testParseHexColorWithoutHash() {
        let c = parseHexColor("FF0000")
        XCTAssertEqual(c?.r, 0xFF)
        XCTAssertEqual(c?.g, 0x00)
        XCTAssertEqual(c?.b, 0x00)
    }

    func testParseHexColorInvalid() {
        XCTAssertNil(parseHexColor(""))
        XCTAssertNil(parseHexColor("foo"))
        XCTAssertNil(parseHexColor("#ZZZZZZ"))
        XCTAssertNil(parseHexColor("#12345"))   // 5 chars
    }

    func testThicknessClamping() {
        var cfg = BordersConfig()
        cfg.thickness = 100
        XCTAssertEqual(cfg.clampedThickness, 20)
        cfg.thickness = -5
        XCTAssertEqual(cfg.clampedThickness, 0)
        cfg.thickness = 5
        XCTAssertEqual(cfg.clampedThickness, 5)
    }

    func testActiveColorWithoutOverride() {
        let cfg = BordersConfig()
        XCTAssertEqual(activeColor(forStage: "1", config: cfg), "#7AA2F7")
        XCTAssertEqual(activeColor(forStage: nil, config: cfg), "#7AA2F7")
    }

    func testActiveColorWithStageOverride() {
        var cfg = BordersConfig()
        cfg.stageOverrides = [
            StageOverride(stageID: "1", activeColor: "#9ECE6A"),
            StageOverride(stageID: "2", activeColor: "#F7768E")
        ]
        XCTAssertEqual(activeColor(forStage: "1", config: cfg), "#9ECE6A")
        XCTAssertEqual(activeColor(forStage: "2", config: cfg), "#F7768E")
        XCTAssertEqual(activeColor(forStage: "3", config: cfg), "#7AA2F7")  // fallback
    }
}
