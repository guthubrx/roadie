import XCTest
@testable import RoadieCore

// MARK: - DisplayRegistryTests (SPEC-012 T003, T008)

final class DisplayRegistryTests: XCTestCase {

    // MARK: T003 smoke

    func testEmptyProvider() async {
        let provider = MockDisplayProvider(screens: [])
        let registry = DisplayRegistry(provider: provider)
        await registry.refresh()
        let count = await registry.count
        XCTAssertEqual(count, 0)
    }

    func testDisplaysIsEmptyBeforeRefresh() async {
        let provider = MockDisplayProvider(screens: [])
        let registry = DisplayRegistry(provider: provider)
        let count = await registry.count
        XCTAssertEqual(count, 0)
    }

    func testLookupOnEmptyRegistryReturnsNil() async {
        let provider = MockDisplayProvider(screens: [])
        let registry = DisplayRegistry(provider: provider)
        await registry.refresh()
        let byIndex = await registry.display(at: 1)
        let byID = await registry.display(forID: 0)
        let byUUID = await registry.display(forUUID: "anything")
        XCTAssertNil(byIndex)
        XCTAssertNil(byID)
        XCTAssertNil(byUUID)
    }

    func testSetActiveID() async {
        let provider = MockDisplayProvider(screens: [])
        let registry = DisplayRegistry(provider: provider)
        await registry.setActive(id: 42)
        let active = await registry.activeID
        XCTAssertEqual(active, 42)
    }
}
