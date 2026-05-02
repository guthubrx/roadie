import XCTest
import CoreGraphics
@testable import RoadieDesktops

final class DesktopPersistenceTests: XCTestCase {
    private var tempDir: URL!
    private let uuid = "TEST-UUID-DISP-A"

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DesktopPersistenceTests-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testRoundTripCurrent() {
        DesktopPersistence.saveCurrent(configDir: tempDir, displayUUID: uuid, currentID: 3)
        let loaded = DesktopPersistence.loadCurrent(configDir: tempDir, displayUUID: uuid)
        XCTAssertEqual(loaded, 3)
    }

    func testLoadCurrentMissingFile() {
        let loaded = DesktopPersistence.loadCurrent(configDir: tempDir, displayUUID: "NONEXISTENT")
        XCTAssertNil(loaded)
    }

    func testRoundTripDesktopWindows() {
        let snaps = [
            DesktopPersistence.WindowSnapshot(
                cgwid: 12345,
                bundleID: "com.googlecode.iterm2",
                titlePrefix: "Default ~/.zsh — Mac",
                expectedFrame: CGRect(x: 100, y: 50, width: 1024, height: 768)),
            DesktopPersistence.WindowSnapshot(
                cgwid: 67890,
                bundleID: "com.apple.Safari",
                titlePrefix: "Apple",
                expectedFrame: CGRect(x: 0, y: 0, width: 800, height: 600)),
        ]
        DesktopPersistence.saveDesktopWindows(
            configDir: tempDir, displayUUID: uuid, desktopID: 2, windows: snaps)
        let loaded = DesktopPersistence.loadDesktopWindows(
            configDir: tempDir, displayUUID: uuid, desktopID: 2)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].cgwid, 12345)
        XCTAssertEqual(loaded[0].bundleID, "com.googlecode.iterm2")
        XCTAssertEqual(loaded[1].cgwid, 67890)
        XCTAssertEqual(loaded[1].expectedFrame.size.width, 800)
    }

    func testLoadDesktopWindowsMissingFile() {
        let loaded = DesktopPersistence.loadDesktopWindows(
            configDir: tempDir, displayUUID: uuid, desktopID: 99)
        XCTAssertEqual(loaded.count, 0)
    }

    func testTitleEscaping() {
        let snap = DesktopPersistence.WindowSnapshot(
            cgwid: 1,
            bundleID: "test",
            titlePrefix: #"weird "title" with \backslash"#,
            expectedFrame: CGRect(x: 0, y: 0, width: 100, height: 100))
        DesktopPersistence.saveDesktopWindows(
            configDir: tempDir, displayUUID: uuid, desktopID: 1, windows: [snap])
        let loaded = DesktopPersistence.loadDesktopWindows(
            configDir: tempDir, displayUUID: uuid, desktopID: 1)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].titlePrefix, #"weird "title" with \backslash"#)
    }
}
