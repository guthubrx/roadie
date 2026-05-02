import XCTest
import TOMLKit
@testable import RoadieCore

final class ConfigDesktopsTests: XCTestCase {

    // MARK: - Valeurs par défaut (FR-018)

    func testDefaultValues() {
        let cfg = DesktopsConfig()
        XCTAssertTrue(cfg.enabled)
        XCTAssertEqual(cfg.count, 10)
        XCTAssertEqual(cfg.defaultFocus, 1)
        XCTAssertTrue(cfg.backAndForth)
        XCTAssertEqual(cfg.offscreenX, -30000)
        XCTAssertEqual(cfg.offscreenY, -30000)
    }

    // MARK: - Parsing TOML complet (FR-018)

    func testParsingFullSection() throws {
        let toml = """
        [desktops]
        enabled = true
        count = 5
        default_focus = 2
        back_and_forth = false
        offscreen_x = -20000
        offscreen_y = -20000
        """
        let config = try TOMLDecoder().decode(Config.self, from: toml)
        XCTAssertEqual(config.desktops.count, 5)
        XCTAssertEqual(config.desktops.defaultFocus, 2)
        XCTAssertFalse(config.desktops.backAndForth)
        XCTAssertEqual(config.desktops.offscreenX, -20000)
    }

    // MARK: - Section absente → défauts (FR-018, backward compat V1)

    func testMissingSectionFallsBackToDefaults() throws {
        // Pas de section [desktops] dans le TOML → decodeIfPresent retourne nil → .init()
        // Pas de section [daemon] non plus pour éviter le bug TOMLDecoder sur socket_path manquant.
        let toml = ""
        let config = try TOMLDecoder().decode(Config.self, from: toml)
        XCTAssertTrue(config.desktops.enabled)
        XCTAssertEqual(config.desktops.count, 10)
    }

    // MARK: - Rejet count = 0 (FR-001)

    func testCountZeroThrows() {
        let toml = """
        [desktops]
        count = 0
        """
        XCTAssertThrowsError(try TOMLDecoder().decode(Config.self, from: toml)) { error in
            // Vérifier que c'est bien une erreur liée au count invalide
            let description = "\(error)"
            XCTAssertTrue(description.contains("count") || description.contains("1..16"),
                          "Expected count validation error, got: \(description)")
        }
    }

    // MARK: - Rejet count = 17 (FR-001)

    func testCountSeventeenThrows() {
        let toml = """
        [desktops]
        count = 17
        """
        XCTAssertThrowsError(try TOMLDecoder().decode(Config.self, from: toml)) { error in
            let description = "\(error)"
            XCTAssertTrue(description.contains("count") || description.contains("1..16"),
                          "Expected count validation error, got: \(description)")
        }
    }

    // MARK: - Valeur limite basse et haute valides (FR-001)

    func testCountBoundaryValues() throws {
        let toml1 = "[desktops]\ncount = 1"
        let toml16 = "[desktops]\ncount = 16"
        let c1 = try TOMLDecoder().decode(Config.self, from: toml1)
        let c16 = try TOMLDecoder().decode(Config.self, from: toml16)
        XCTAssertEqual(c1.desktops.count, 1)
        XCTAssertEqual(c16.desktops.count, 16)
    }
}
