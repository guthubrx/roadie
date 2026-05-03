import XCTest
import CoreGraphics
@testable import RoadieCore
@testable import RoadieDesktops

final class DesktopRegistryPerDisplayTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DesktopRegistryPerDisplayTests-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testGlobalModeSetCurrentSyncsAllDisplays() async {
        let registry = DesktopRegistry(configDir: tempDir, displayUUID: "TEST-UUID-0001", count: 5, mode: .global)
        await registry.load()
        let did1: CGDirectDisplayID = 100
        let did2: CGDirectDisplayID = 200
        await registry.syncCurrentByDisplay(presentIDs: [did1, did2])

        await registry.setCurrent(2, on: did1)

        let map = await registry.currentByDisplay
        XCTAssertEqual(map[did1], 2)
        XCTAssertEqual(map[did2], 2, "global mode propagates to all displays")
    }

    func testPerDisplayModeSetCurrentIsLocal() async {
        let registry = DesktopRegistry(configDir: tempDir, displayUUID: "TEST-UUID-0001", count: 5, mode: .perDisplay)
        await registry.load()
        let did1: CGDirectDisplayID = 100
        let did2: CGDirectDisplayID = 200
        await registry.syncCurrentByDisplay(presentIDs: [did1, did2])

        await registry.setCurrent(3, on: did1)

        let map = await registry.currentByDisplay
        XCTAssertEqual(map[did1], 3)
        XCTAssertEqual(map[did2], 1, "perDisplay mode keeps did2 untouched")
    }

    func testSetModeGlobalToPerDisplayPreservesValues() async {
        let registry = DesktopRegistry(configDir: tempDir, displayUUID: "TEST-UUID-0001", count: 5, mode: .global)
        await registry.load()
        let did1: CGDirectDisplayID = 100
        let did2: CGDirectDisplayID = 200
        await registry.syncCurrentByDisplay(presentIDs: [did1, did2])
        await registry.setCurrent(2, on: did1)
        // Both at 2.

        await registry.setMode(.perDisplay)

        let map = await registry.currentByDisplay
        XCTAssertEqual(map[did1], 2)
        XCTAssertEqual(map[did2], 2, "transition preserves values")

        // Now mutations are independent.
        await registry.setCurrent(4, on: did1)
        let after = await registry.currentByDisplay
        XCTAssertEqual(after[did1], 4)
        XCTAssertEqual(after[did2], 2, "did2 not affected after mode flip")
    }

    func testSetModePerDisplayToGlobalSyncsToPrimary() async {
        let registry = DesktopRegistry(configDir: tempDir, displayUUID: "TEST-UUID-0001", count: 5, mode: .perDisplay)
        await registry.load()
        let primaryID = CGMainDisplayID()
        let did2: CGDirectDisplayID = 200
        await registry.syncCurrentByDisplay(presentIDs: [primaryID, did2])
        await registry.setCurrent(3, on: primaryID)
        await registry.setCurrent(5, on: did2)

        await registry.setMode(.global)

        let map = await registry.currentByDisplay
        XCTAssertEqual(map[primaryID], 3, "primary value preserved")
        XCTAssertEqual(map[did2], 3, "did2 synced to primary value")
    }

    func testCurrentIDForDisplayFallback() async {
        let registry = DesktopRegistry(configDir: tempDir, displayUUID: "TEST-UUID-0001", count: 5, mode: .perDisplay)
        await registry.load()
        let primaryID = CGMainDisplayID()
        await registry.syncCurrentByDisplay(presentIDs: [primaryID])

        let v = await registry.currentID(for: 999) // unknown display
        let cur = await registry.currentID
        XCTAssertEqual(v, cur, "unknown display falls back to global currentID")
    }
}
