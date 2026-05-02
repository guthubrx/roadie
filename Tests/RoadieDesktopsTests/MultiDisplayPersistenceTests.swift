import XCTest
import CoreGraphics
@testable import RoadieDesktops

// MARK: - MultiDisplayPersistenceTests (SPEC-012 T004, T012)

/// Vérifie le round-trip parse/encode de `WindowEntry.displayUUID`.
/// - Avec UUID : le champ `display_uuid` doit apparaître dans le TOML produit.
/// - Sans UUID : le champ ne doit PAS apparaître (backward-compat SPEC-011).
final class MultiDisplayPersistenceTests: XCTestCase {

    // MARK: T012 — Round-trip avec displayUUID

    func testRoundTripWithDisplayUUID() throws {
        let uuid = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
        let entry = WindowEntry(
            cgwid: 12345,
            bundleID: "com.apple.terminal",
            title: "iTerm",
            expectedFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
            stageID: 1,
            displayUUID: uuid
        )
        let desktop = RoadieDesktop(
            id: 1,
            stages: [DesktopStage(id: 1, windows: [12345])],
            windows: [entry]
        )
        let toml = serialize(desktop)
        XCTAssertTrue(toml.contains("display_uuid = \"\(uuid)\""),
                      "Le TOML doit contenir display_uuid quand renseigné")

        let parsed = try parseDesktop(from: toml)
        XCTAssertEqual(parsed.windows.first?.displayUUID, uuid)
    }

    func testRoundTripWithoutDisplayUUID() throws {
        let entry = WindowEntry(
            cgwid: 67890,
            bundleID: "org.mozilla.firefox",
            title: "Firefox",
            expectedFrame: CGRect(x: 0, y: 0, width: 1280, height: 800),
            stageID: 1
            // displayUUID omis — nil par défaut
        )
        let desktop = RoadieDesktop(
            id: 1,
            stages: [DesktopStage(id: 1, windows: [67890])],
            windows: [entry]
        )
        let toml = serialize(desktop)
        XCTAssertFalse(toml.contains("display_uuid"),
                       "Le TOML ne doit PAS contenir display_uuid si nil (backward-compat)")

        let parsed = try parseDesktop(from: toml)
        XCTAssertNil(parsed.windows.first?.displayUUID)
    }

    // MARK: Backward-compat — SPEC-011 state.toml sans display_uuid

    func testSpec011TomlLoadsClean() throws {
        let spec011TOML = """
        id = 1
        label = ""
        layout = "bsp"
        gaps_outer = 8
        gaps_inner = 4
        active_stage_id = 1

        [[stages]]
        id = 1
        label = ""
        windows = [99999]

        [[windows]]
        cgwid = 99999
        bundle_id = "com.apple.finder"
        title = "Finder"
        expected_x = 0.0
        expected_y = 0.0
        expected_w = 1280.0
        expected_h = 800.0
        stage_id = 1
        """
        let parsed = try parseDesktop(from: spec011TOML)
        XCTAssertNil(parsed.windows.first?.displayUUID,
                     "Un state.toml SPEC-011 sans display_uuid doit charger avec nil")
        XCTAssertEqual(parsed.windows.first?.cgwid, 99999)
    }
}
