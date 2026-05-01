import XCTest
@testable import RoadieCore

@MainActor
final class DesktopManagerTests: XCTestCase {

    func test_initialTransition_callsHookWithNilFrom() async {
        let mock = MockDesktopProvider(
            desktops: [DesktopInfo(uuid: "A", index: 1)],
            currentUUID: "A"
        )
        let dm = DesktopManager(provider: mock)
        var captured: (from: String?, to: String)?
        dm.onTransition = { from, to in captured = (from, to) }
        await dm.handleSpaceChange()
        XCTAssertEqual(captured?.from, nil)
        XCTAssertEqual(captured?.to, "A")
        XCTAssertEqual(dm.currentUUID, "A")
    }

    func test_userTransition_callsHookWithFromAndTo() async {
        let mock = MockDesktopProvider(
            desktops: [DesktopInfo(uuid: "A", index: 1),
                       DesktopInfo(uuid: "B", index: 2)],
            currentUUID: "A"
        )
        let dm = DesktopManager(provider: mock)
        var captured: [(from: String?, to: String)] = []
        dm.onTransition = { from, to in captured.append((from, to)) }
        await dm.handleSpaceChange() // initial → A
        mock.simulateTransition(to: "B")
        await dm.handleSpaceChange() // A → B
        XCTAssertEqual(captured.count, 2)
        XCTAssertEqual(captured[1].from, "A")
        XCTAssertEqual(captured[1].to, "B")
        XCTAssertEqual(dm.recentUUID, "A")
        XCTAssertEqual(dm.currentUUID, "B")
    }

    func test_resolveSelector_basic() async {
        let mock = MockDesktopProvider(
            desktops: [DesktopInfo(uuid: "A", index: 1),
                       DesktopInfo(uuid: "B", index: 2),
                       DesktopInfo(uuid: "C", index: 3)],
            currentUUID: "B"
        )
        // Désactive back_and_forth pour tester les selectors stricts.
        let dm = DesktopManager(provider: mock, backAndForth: false)
        await dm.handleSpaceChange()
        XCTAssertEqual(dm.resolveSelector("first"), "A")
        XCTAssertEqual(dm.resolveSelector("last"), "C")
        XCTAssertEqual(dm.resolveSelector("next"), "C")
        XCTAssertEqual(dm.resolveSelector("prev"), "A")
        XCTAssertEqual(dm.resolveSelector("2"), "B")
        XCTAssertEqual(dm.resolveSelector("99"), nil)
        XCTAssertEqual(dm.resolveSelector("zzz"), nil)
    }

    func test_resolveSelector_byLabel() async {
        let mock = MockDesktopProvider(
            desktops: [DesktopInfo(uuid: "A", index: 1),
                       DesktopInfo(uuid: "B", index: 2)],
            currentUUID: "A"
        )
        let dm = DesktopManager(provider: mock)
        await dm.handleSpaceChange()
        dm.setLabel("comm", for: "B")
        XCTAssertEqual(dm.resolveSelector("comm"), "B")
        XCTAssertEqual(dm.resolveSelector("dev"), nil) // pas posé
    }

    func test_backAndForth_redirectsCurrentToRecent() async {
        let mock = MockDesktopProvider(
            desktops: [DesktopInfo(uuid: "A", index: 1),
                       DesktopInfo(uuid: "B", index: 2)],
            currentUUID: "A"
        )
        let dm = DesktopManager(provider: mock, backAndForth: true)
        await dm.handleSpaceChange()
        mock.simulateTransition(to: "B")
        await dm.handleSpaceChange()
        // recentUUID = "A", currentUUID = "B"
        // Demander "2" (= B = current) doit rediriger vers recent (= A) avec back_and_forth.
        XCTAssertEqual(dm.resolveSelector("2"), "A")
    }

    func test_focus_delegatesToProvider() async {
        let mock = MockDesktopProvider(
            desktops: [DesktopInfo(uuid: "A", index: 1),
                       DesktopInfo(uuid: "B", index: 2)],
            currentUUID: "A"
        )
        let dm = DesktopManager(provider: mock)
        await dm.handleSpaceChange()
        dm.focus(uuid: "B")
        XCTAssertEqual(mock.focusRequests, ["B"])
    }
}
