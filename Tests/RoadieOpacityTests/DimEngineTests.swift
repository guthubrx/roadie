import XCTest
@testable import RoadieOpacity

final class DimEngineTests: XCTestCase {
    func testFocusedWithoutRule() {
        XCTAssertEqual(targetAlpha(focused: true, baseline: 0.85, perAppRule: nil), 1.0)
    }

    func testFocusedWithRule() {
        XCTAssertEqual(targetAlpha(focused: true, baseline: 0.85, perAppRule: 0.92), 0.92)
    }

    func testInactiveWithoutRule() {
        XCTAssertEqual(targetAlpha(focused: false, baseline: 0.85, perAppRule: nil), 0.85)
    }

    func testInactiveWithRuleMoreRestrictiveThanBaseline() {
        // Rule 0.5 plus restrictive que baseline 0.85 → rule gagne
        XCTAssertEqual(targetAlpha(focused: false, baseline: 0.85, perAppRule: 0.5), 0.5)
    }

    func testInactiveWithRuleLessRestrictiveThanBaseline() {
        // Rule 0.92 moins restrictive que baseline 0.85 → baseline gagne (min)
        XCTAssertEqual(targetAlpha(focused: false, baseline: 0.85, perAppRule: 0.92), 0.85)
    }

    func testClampAbove() {
        XCTAssertEqual(targetAlpha(focused: true, baseline: 0.85, perAppRule: 1.5), 1.0)
    }

    func testClampBelow() {
        XCTAssertEqual(targetAlpha(focused: false, baseline: -0.2, perAppRule: nil), 0.0)
    }

    func testRuleMatcherEmpty() {
        let m = RuleMatcher([])
        XCTAssertNil(m.alpha(for: "anything"))
    }

    func testRuleMatcherMatch() {
        let m = RuleMatcher([AppRule(bundleID: "com.foo", alpha: 0.9)])
        XCTAssertEqual(m.alpha(for: "com.foo"), 0.9)
        XCTAssertNil(m.alpha(for: "com.bar"))
    }
}
