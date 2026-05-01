import XCTest
@testable import RoadieCore

final class FXConfigTests: XCTestCase {
    func testDefaults() {
        let cfg = FXConfig()
        XCTAssertEqual(cfg.dylibDir, "~/.local/lib/roadie/")
        XCTAssertEqual(cfg.osaxSocketPath, "/var/tmp/roadied-osax.sock")
        XCTAssertNil(cfg.checksumFile)
        XCTAssertFalse(cfg.disableLoading)
    }

    func testLoadFromMissingSection() {
        let toml = """
        [tiling]
        gaps_outer = 8
        """
        let cfg = FXConfig.load(fromTOML: toml)
        XCTAssertEqual(cfg.dylibDir, "~/.local/lib/roadie/")
    }

    func testLoadFromTOML() {
        let toml = """
        [fx]
        dylib_dir = "/custom/path/"
        disable_loading = true
        """
        let cfg = FXConfig.load(fromTOML: toml)
        XCTAssertEqual(cfg.dylibDir, "/custom/path/")
        XCTAssertTrue(cfg.disableLoading)
    }

    func testExpandedDylibDir() {
        let cfg = FXConfig(dylibDir: "~/test/")
        XCTAssertFalse(cfg.expandedDylibDir.contains("~"))
        XCTAssertTrue(cfg.expandedDylibDir.hasSuffix("test/") || cfg.expandedDylibDir.hasSuffix("test"))
    }
}
