import XCTest
import TOMLKit
@testable import RoadieCore

final class ConfigDesktopsModeTests: XCTestCase {
    func testDefaultModeIsGlobal() throws {
        let toml = """
        [desktops]
        enabled = true
        count = 10
        """
        let cfg = try TOMLDecoder().decode(Config.self, from: toml)
        XCTAssertEqual(cfg.desktops.mode, .global)
    }

    func testPerDisplayMode() throws {
        let toml = """
        [desktops]
        mode = "per_display"
        """
        let cfg = try TOMLDecoder().decode(Config.self, from: toml)
        XCTAssertEqual(cfg.desktops.mode, .perDisplay)
    }

    func testInvalidModeFallbacksToGlobal() throws {
        let toml = """
        [desktops]
        mode = "weird_unknown_mode"
        """
        let cfg = try TOMLDecoder().decode(Config.self, from: toml)
        // FR-002 : valeur invalide → fallback global
        XCTAssertEqual(cfg.desktops.mode, .global)
    }

    func testGlobalModeExplicit() throws {
        let toml = """
        [desktops]
        mode = "global"
        """
        let cfg = try TOMLDecoder().decode(Config.self, from: toml)
        XCTAssertEqual(cfg.desktops.mode, .global)
    }
}
