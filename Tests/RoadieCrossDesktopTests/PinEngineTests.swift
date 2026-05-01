import XCTest
@testable import RoadieCrossDesktop

final class PinEngineTests: XCTestCase {
    func testNoRulesNoMatch() {
        let engine = PinEngine(rules: [],
                               labelResolver: { _ in nil },
                               indexResolver: { _ in nil })
        XCTAssertNil(engine.target(forBundleID: "com.foo"))
    }

    func testLabelMatch() {
        let labels = ["comm": "uuid-comm"]
        let engine = PinEngine(rules: [
            PinRule(bundleID: "com.tinyspeck.slackmacgap", desktopLabel: "comm")
        ], labelResolver: { labels[$0] }, indexResolver: { _ in nil })
        XCTAssertEqual(engine.target(forBundleID: "com.tinyspeck.slackmacgap"), "uuid-comm")
    }

    func testLabelUnknownReturnsNil() {
        let engine = PinEngine(rules: [
            PinRule(bundleID: "com.foo", desktopLabel: "doesnotexist")
        ], labelResolver: { _ in nil }, indexResolver: { _ in nil })
        XCTAssertNil(engine.target(forBundleID: "com.foo"))
    }

    func testIndexMatch() {
        let engine = PinEngine(rules: [
            PinRule(bundleID: "com.foo", desktopIndex: 3)
        ], labelResolver: { _ in nil },
           indexResolver: { idx in idx == 3 ? "uuid-3" : nil })
        XCTAssertEqual(engine.target(forBundleID: "com.foo"), "uuid-3")
    }

    func testIndexInvalidReturnsNil() {
        let engine = PinEngine(rules: [
            PinRule(bundleID: "com.foo", desktopIndex: 99)
        ], labelResolver: { _ in nil },
           indexResolver: { _ in nil })
        XCTAssertNil(engine.target(forBundleID: "com.foo"))
    }

    func testFirstRuleWinsOnMultiple() {
        let labels = ["a": "uuid-a", "b": "uuid-b"]
        let engine = PinEngine(rules: [
            PinRule(bundleID: "com.foo", desktopLabel: "a"),
            PinRule(bundleID: "com.foo", desktopLabel: "b")
        ], labelResolver: { labels[$0] }, indexResolver: { _ in nil })
        XCTAssertEqual(engine.target(forBundleID: "com.foo"), "uuid-a")
    }

    func testNoMatchForBundleID() {
        let engine = PinEngine(rules: [
            PinRule(bundleID: "com.foo", desktopLabel: "a")
        ], labelResolver: { _ in "uuid-a" }, indexResolver: { _ in nil })
        XCTAssertNil(engine.target(forBundleID: "com.bar"))
    }
}
