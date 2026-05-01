import XCTest
import CoreGraphics
@testable import RoadieAnimations

final class AnimationFactoryTests: XCTestCase {
    func testWindowOpenAlphaAndScale() {
        let lib = BezierLibrary()
        let rule = EventRule(event: "window_open",
                             properties: ["alpha", "scale"],
                             durationMs: 200, curve: "snappy")
        let ctx = EventContext(eventKind: "window_open", wid: 42)
        let anims = AnimationFactory.make(rule: rule, context: ctx, curveLib: lib)
        XCTAssertEqual(anims.count, 2)
        let alphaAnim = anims.first { $0.property == .alpha }!
        if case .scalar(let from) = alphaAnim.from, case .scalar(let to) = alphaAnim.to {
            XCTAssertEqual(from, 0.0)
            XCTAssertEqual(to, 1.0)
        } else { XCTFail() }
    }

    func testWindowCloseAlpha() {
        let lib = BezierLibrary()
        let rule = EventRule(event: "window_close", properties: ["alpha"],
                             durationMs: 150, curve: "smooth")
        let ctx = EventContext(eventKind: "window_close", wid: 1, currentAlpha: 1.0)
        let anims = AnimationFactory.make(rule: rule, context: ctx, curveLib: lib)
        XCTAssertEqual(anims.count, 1)
        if case .scalar(let to) = anims.first!.to {
            XCTAssertEqual(to, 0.0)
        } else { XCTFail() }
    }

    func testPulseGeneratesTwoAnimations() {
        let lib = BezierLibrary()
        let rule = EventRule(event: "window_focused",
                             properties: ["scale"], durationMs: 250,
                             curve: "easeOutBack", direction: nil, mode: "pulse")
        let ctx = EventContext(eventKind: "window_focused", wid: 7)
        let anims = AnimationFactory.make(rule: rule, context: ctx, curveLib: lib)
        XCTAssertEqual(anims.count, 2)
        // Première phase : 1.0 → 1.02
        if case .scalar(let to1) = anims[0].to {
            XCTAssertEqual(to1, 1.02, accuracy: 0.001)
        } else { XCTFail() }
        // Deuxième phase : 1.02 → 1.0
        if case .scalar(let to2) = anims[1].to {
            XCTAssertEqual(to2, 1.0, accuracy: 0.001)
        } else { XCTFail() }
    }

    func testUnknownCurveReturnsEmpty() {
        let lib = BezierLibrary()
        let rule = EventRule(event: "window_open", properties: ["alpha"],
                             durationMs: 200, curve: "doesnotexist")
        let ctx = EventContext(eventKind: "window_open", wid: 1)
        let anims = AnimationFactory.make(rule: rule, context: ctx, curveLib: lib)
        XCTAssertEqual(anims.count, 0)
    }

    func testNoWidReturnsEmpty() {
        let lib = BezierLibrary()
        let rule = EventRule(event: "window_open", properties: ["alpha"],
                             durationMs: 200, curve: "snappy")
        let ctx = EventContext(eventKind: "window_open", wid: nil)
        let anims = AnimationFactory.make(rule: rule, context: ctx, curveLib: lib)
        XCTAssertEqual(anims.count, 0)
    }

    func testWorkspaceSwitchHorizontal() {
        let lib = BezierLibrary()
        let rule = EventRule(event: "desktop_changed", properties: ["translateX"],
                             durationMs: 350, curve: "smooth", direction: "horizontal")
        let ctx = EventContext(eventKind: "desktop_changed", wid: 1, screenWidth: 1440)
        let anims = AnimationFactory.make(rule: rule, context: ctx, curveLib: lib)
        XCTAssertEqual(anims.count, 1)
        if case .scalar(let to) = anims.first!.to {
            XCTAssertEqual(to, -1440.0)
        } else { XCTFail() }
    }

    func testCrossfadeWithIncomingWIDsGeneratesPair() {
        let lib = BezierLibrary()
        let rule = EventRule(event: "stage_changed", properties: ["alpha"],
                             durationMs: 180, curve: "smooth",
                             direction: nil, mode: "crossfade")
        // Sortant = wid 1, entrants = [10, 20, 30]
        let ctx = EventContext(eventKind: "stage_changed", wid: 1,
                               currentAlpha: 1.0,
                               incomingWIDs: [10, 20, 30])
        let anims = AnimationFactory.make(rule: rule, context: ctx, curveLib: lib)
        // 1 sortante (wid 1, α 1→0) + 3 entrantes (wids 10/20/30, α 0→1) = 4
        XCTAssertEqual(anims.count, 4)
        let outgoing = anims.first { $0.wid == 1 }
        let incoming = anims.first { $0.wid == 10 }
        XCTAssertNotNil(outgoing)
        XCTAssertNotNil(incoming)
        if case .scalar(let toOut) = outgoing!.to { XCTAssertEqual(toOut, 0.0) } else { XCTFail() }
        if case .scalar(let toIn) = incoming!.to { XCTAssertEqual(toIn, 1.0) } else { XCTFail() }
    }

    func testWindowResizedFrameInterpolation() {
        let lib = BezierLibrary()
        let rule = EventRule(event: "window_resized", properties: ["frame"],
                             durationMs: 120, curve: "snappy")
        let from = CGRect(x: 0, y: 0, width: 100, height: 100)
        let to = CGRect(x: 100, y: 100, width: 200, height: 200)
        let ctx = EventContext(eventKind: "window_resized", wid: 5,
                               currentFrame: from, targetFrame: to)
        let anims = AnimationFactory.make(rule: rule, context: ctx, curveLib: lib)
        XCTAssertEqual(anims.count, 1)
        if case .rect(let r) = anims.first!.to {
            XCTAssertEqual(r.size.width, 200)
            XCTAssertEqual(r.origin.x, 100)
        } else { XCTFail("expected rect") }
    }
}
