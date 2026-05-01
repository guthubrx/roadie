import XCTest
@testable import RoadieBlur

final class RuleMatcherTests: XCTestCase {
    func testNoRulesNoDefault() {
        let cfg = BlurConfig()
        XCTAssertEqual(radius(for: "com.foo", config: cfg), 0)
    }

    func testDefaultOnly() {
        var cfg = BlurConfig()
        cfg.defaultRadius = 15
        XCTAssertEqual(radius(for: "com.foo", config: cfg), 15)
    }

    func testRuleMatchOverridesDefault() {
        var cfg = BlurConfig()
        cfg.defaultRadius = 15
        cfg.rules = [BlurRule(bundleID: "com.tinyspeck.slackmacgap", radius: 30)]
        XCTAssertEqual(radius(for: "com.tinyspeck.slackmacgap", config: cfg), 30)
        XCTAssertEqual(radius(for: "com.other", config: cfg), 15)
    }

    func testClampAbove100() {
        var cfg = BlurConfig()
        cfg.rules = [BlurRule(bundleID: "com.foo", radius: 250)]
        XCTAssertEqual(radius(for: "com.foo", config: cfg), 100)
    }

    func testClampBelowZero() {
        var cfg = BlurConfig()
        cfg.rules = [BlurRule(bundleID: "com.foo", radius: -10)]
        XCTAssertEqual(radius(for: "com.foo", config: cfg), 0)
    }

    func testZeroIsValidNoOp() {
        var cfg = BlurConfig()
        cfg.defaultRadius = 0
        XCTAssertEqual(radius(for: "anything", config: cfg), 0)
    }
}
