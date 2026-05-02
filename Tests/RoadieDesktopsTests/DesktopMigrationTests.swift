import XCTest
@testable import RoadieDesktops

final class DesktopMigrationTests: XCTestCase {
    private var tempDir: URL!
    private let primaryUUID = "TEST-UUID-PRIMARY-1234"

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DesktopMigrationTests-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testNoLegacyNoOp() throws {
        let count = try DesktopMigration.runIfNeeded(
            configDir: tempDir, primaryUUID: primaryUUID)
        XCTAssertEqual(count, 0)
    }

    func testMigratesLegacyV2ToV3() throws {
        let fm = FileManager.default
        // Setup V2 layout : desktops/1/state.toml + desktops/2/state.toml + current.txt
        let legacy = tempDir.appendingPathComponent("desktops")
        try fm.createDirectory(at: legacy.appendingPathComponent("1"),
                               withIntermediateDirectories: true)
        try fm.createDirectory(at: legacy.appendingPathComponent("2"),
                               withIntermediateDirectories: true)
        try "[stages]\n".write(to: legacy.appendingPathComponent("1/state.toml"),
                              atomically: true, encoding: .utf8)
        try "[stages]\n".write(to: legacy.appendingPathComponent("2/state.toml"),
                              atomically: true, encoding: .utf8)
        try "2\n".write(to: legacy.appendingPathComponent("current.txt"),
                       atomically: true, encoding: .utf8)

        let count = try DesktopMigration.runIfNeeded(
            configDir: tempDir, primaryUUID: primaryUUID)
        XCTAssertGreaterThan(count, 0)

        let target = tempDir
            .appendingPathComponent("displays/\(primaryUUID)/desktops")
        XCTAssertTrue(fm.fileExists(atPath: target.appendingPathComponent("1/state.toml").path))
        XCTAssertTrue(fm.fileExists(atPath: target.appendingPathComponent("2/state.toml").path))

        let curURL = tempDir
            .appendingPathComponent("displays/\(primaryUUID)/current.toml")
        XCTAssertTrue(fm.fileExists(atPath: curURL.path))
        let curContent = try String(contentsOf: curURL, encoding: .utf8)
        XCTAssertTrue(curContent.contains("current_desktop_id = 2"))
    }

    func testIdempotentSecondRun() throws {
        let fm = FileManager.default
        let legacy = tempDir.appendingPathComponent("desktops")
        try fm.createDirectory(at: legacy.appendingPathComponent("1"),
                               withIntermediateDirectories: true)
        try "[stages]\n".write(to: legacy.appendingPathComponent("1/state.toml"),
                              atomically: true, encoding: .utf8)

        // First run : migration happens.
        let count1 = try DesktopMigration.runIfNeeded(
            configDir: tempDir, primaryUUID: primaryUUID)
        XCTAssertGreaterThan(count1, 0)

        // Second run : noop.
        let count2 = try DesktopMigration.runIfNeeded(
            configDir: tempDir, primaryUUID: primaryUUID)
        XCTAssertEqual(count2, 0)
    }
}
