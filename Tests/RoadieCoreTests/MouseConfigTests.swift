import XCTest
import TOMLKit
@testable import RoadieCore

final class MouseConfigTests: XCTestCase {
    func testDefaultsAbsentSection() throws {
        let toml = """
        [daemon]
        log_level = "info"
        """
        let cfg = try TOMLDecoder().decode(Config.self, from: toml)
        XCTAssertEqual(cfg.mouse.modifier, .ctrl)
        XCTAssertEqual(cfg.mouse.actionLeft, .move)
        XCTAssertEqual(cfg.mouse.actionRight, .resize)
        XCTAssertEqual(cfg.mouse.actionMiddle, .none)
        XCTAssertEqual(cfg.mouse.edgeThreshold, 30)
    }

    func testCustomModifierAndActions() throws {
        let toml = """
        [mouse]
        modifier = "alt"
        action_left = "resize"
        action_right = "move"
        action_middle = "move"
        edge_threshold = 50
        """
        let cfg = try TOMLDecoder().decode(Config.self, from: toml)
        XCTAssertEqual(cfg.mouse.modifier, .alt)
        XCTAssertEqual(cfg.mouse.actionLeft, .resize)
        XCTAssertEqual(cfg.mouse.actionRight, .move)
        XCTAssertEqual(cfg.mouse.actionMiddle, .move)
        XCTAssertEqual(cfg.mouse.edgeThreshold, 50)
    }

    func testInvalidValuesFallback() throws {
        let toml = """
        [mouse]
        modifier = "weird"
        action_left = "huh"
        edge_threshold = 5000
        """
        let cfg = try TOMLDecoder().decode(Config.self, from: toml)
        XCTAssertEqual(cfg.mouse.modifier, .ctrl, "invalid modifier → fallback ctrl")
        XCTAssertEqual(cfg.mouse.actionLeft, .move, "invalid action_left → fallback move")
        XCTAssertEqual(cfg.mouse.edgeThreshold, 200, "edge_threshold clamp à 200 max")
    }

    func testNoneActions() throws {
        let toml = """
        [mouse]
        action_left = "none"
        action_right = "none"
        """
        let cfg = try TOMLDecoder().decode(Config.self, from: toml)
        XCTAssertEqual(cfg.mouse.actionLeft, .none)
        XCTAssertEqual(cfg.mouse.actionRight, .none)
    }

    func testHyperModifier() throws {
        let toml = """
        [mouse]
        modifier = "hyper"
        """
        let cfg = try TOMLDecoder().decode(Config.self, from: toml)
        XCTAssertEqual(cfg.mouse.modifier, .hyper)
    }
}
