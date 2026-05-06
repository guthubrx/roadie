import XCTest
import CoreGraphics
@testable import RoadieDesktops

final class ParserTests: XCTestCase {

    // MARK: - Fixture helpers

    private func makeDesktop1() -> RoadieDesktop {
        RoadieDesktop(
            id: 1,
            label: "code",
            layout: .bsp,
            gapsOuter: 8,
            gapsInner: 4,
            activeStageID: 1,
            stages: [DesktopStage(id: 1, label: "main", windows: [12345, 67890])],
            windows: [
                WindowEntry(cgwid: 12345, bundleID: "com.apple.Terminal",
                            title: "Terminal", expectedFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
                            stageID: 1),
                WindowEntry(cgwid: 67890, bundleID: "com.apple.mail",
                            title: "Mail", expectedFrame: CGRect(x: 950, y: 100, width: 600, height: 600),
                            stageID: 1)
            ]
        )
    }

    private func makeDesktop2() -> RoadieDesktop {
        RoadieDesktop(
            id: 2,
            label: "comm",
            layout: .masterStack,
            gapsOuter: 6,
            gapsInner: 2,
            activeStageID: 2,
            stages: [
                DesktopStage(id: 1, label: "alpha", windows: [11111]),
                DesktopStage(id: 2, label: "beta", windows: [22222])
            ],
            windows: [
                WindowEntry(cgwid: 11111, bundleID: "com.tinyspeck.slackmacgap",
                            title: "Slack", expectedFrame: CGRect(x: 0, y: 0, width: 1200, height: 800),
                            stageID: 1),
                WindowEntry(cgwid: 22222, bundleID: "com.apple.safari",
                            title: "Safari", expectedFrame: CGRect(x: 200, y: 200, width: 1400, height: 900),
                            stageID: 2)
            ]
        )
    }

    private func makeDesktop3() -> RoadieDesktop {
        // Desktop minimal sans label, layout floating
        RoadieDesktop(id: 3, label: nil, layout: .floating,
                      gapsOuter: 0, gapsInner: 0, activeStageID: 1,
                      stages: [DesktopStage(id: 1)], windows: [])
    }

    // MARK: - Round-trip sur 3 fixtures (T013)

    func testRoundTripDesktop1() throws {
        let original = makeDesktop1()
        let toml = serialize(original)
        let parsed = try parseDesktop(from: toml)
        XCTAssertEqual(parsed, original)
    }

    func testRoundTripDesktop2() throws {
        let original = makeDesktop2()
        let toml = serialize(original)
        let parsed = try parseDesktop(from: toml)
        XCTAssertEqual(parsed, original)
    }

    func testRoundTripDesktop3Minimal() throws {
        let original = makeDesktop3()
        let toml = serialize(original)
        let parsed = try parseDesktop(from: toml)
        XCTAssertEqual(parsed.id, 3)
        XCTAssertNil(parsed.label)
        XCTAssertEqual(parsed.layout, .floating)
        XCTAssertTrue(parsed.windows.isEmpty)
    }

    // MARK: - Corruption recovery : TOML invalide → throws (T013)

    func testInvalidTOMLThrows() {
        let bad = "this is not toml [[[[ broken"
        XCTAssertThrowsError(try parseDesktop(from: bad)) { error in
            if let e = error as? DesktopParseError, case .invalidTOML = e {
                // Attendu
            } else {
                XCTFail("Expected DesktopParseError.invalidTOML, got \(error)")
            }
        }
    }

    func testMissingIdThrows() {
        let toml = """
        layout = "bsp"
        gaps_outer = 8
        """
        XCTAssertThrowsError(try parseDesktop(from: toml)) { error in
            if let e = error as? DesktopParseError, case .missingField(let f) = e {
                XCTAssertEqual(f, "id")
            } else {
                XCTFail("Expected DesktopParseError.missingField(id), got \(error)")
            }
        }
    }

    func testEmptyTOMLThrows() {
        XCTAssertThrowsError(try parseDesktop(from: "")) { error in
            if let e = error as? DesktopParseError, case .missingField(let f) = e {
                XCTAssertEqual(f, "id")
            } else {
                XCTFail("Expected missingField(id), got \(error)")
            }
        }
    }

    // MARK: - Sérialisation : format lisible

    func testSerializeContainsExpectedKeys() {
        let desktop = makeDesktop1()
        let toml = serialize(desktop)
        XCTAssertTrue(toml.contains("id = 1"))
        XCTAssertTrue(toml.contains("label = \"code\""))
        XCTAssertTrue(toml.contains("layout = \"bsp\""))
        XCTAssertTrue(toml.contains("[[stages]]"))
        XCTAssertTrue(toml.contains("[[windows]]"))
        XCTAssertTrue(toml.contains("cgwid = 12345"))
        XCTAssertTrue(toml.contains("bundle_id = \"com.apple.Terminal\""))
    }
}
