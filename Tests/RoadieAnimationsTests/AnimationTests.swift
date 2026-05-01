import XCTest
import CoreGraphics
import RoadieFXCore
@testable import RoadieAnimations

final class AnimationTests: XCTestCase {
    func testValueAtStart() {
        let anim = Animation(wid: 1, property: .alpha,
                             from: .scalar(0.0), to: .scalar(1.0),
                             curve: .linear, startTime: 100.0, duration: 1.0)
        let v = anim.value(at: 100.0)
        if case .scalar(let s) = v {
            XCTAssertEqual(s, 0.0, accuracy: 0.005)
        } else { XCTFail("expected scalar at start") }
    }

    func testValueAtMiddleLinear() {
        let anim = Animation(wid: 1, property: .alpha,
                             from: .scalar(0.0), to: .scalar(1.0),
                             curve: .linear, startTime: 100.0, duration: 1.0)
        let v = anim.value(at: 100.5)
        if case .scalar(let s) = v {
            XCTAssertEqual(s, 0.5, accuracy: 0.005)
        } else { XCTFail("expected scalar at mid") }
    }

    func testValueAfterEndIsNil() {
        let anim = Animation(wid: 1, property: .alpha,
                             from: .scalar(0.0), to: .scalar(1.0),
                             curve: .linear, startTime: 100.0, duration: 1.0)
        XCTAssertNil(anim.value(at: 101.5))
    }

    func testCommandSetAlpha() {
        let anim = Animation(wid: 42, property: .alpha,
                             from: .scalar(0.0), to: .scalar(1.0),
                             curve: .linear, startTime: 100.0, duration: 1.0)
        let cmd = anim.toCommand(value: .scalar(0.5))
        XCTAssertEqual(cmd, .setAlpha(wid: 42, alpha: 0.5))
    }

    func testCommandFrameSetFrame() {
        let target = CGRect(x: 10, y: 20, width: 100, height: 200)
        let anim = Animation(wid: 1, property: .frame,
                             from: .rect(.zero), to: .rect(target),
                             curve: .linear, startTime: 0, duration: 1)
        let cmd = anim.toCommand(value: .rect(target))
        guard case .setFrame(let wid, let x, let y, let w, let h) = cmd else {
            XCTFail("expected setFrame"); return
        }
        XCTAssertEqual(wid, 1)
        XCTAssertEqual(x, 10.0, accuracy: 0.001)
        XCTAssertEqual(y, 20.0, accuracy: 0.001)
        XCTAssertEqual(w, 100.0, accuracy: 0.001)
        XCTAssertEqual(h, 200.0, accuracy: 0.001)
    }

    func testLerpScalar() {
        let v = AnimationValue.lerp(from: .scalar(0), to: .scalar(10), t: 0.3)
        if case .scalar(let s) = v {
            XCTAssertEqual(s, 3.0, accuracy: 0.001)
        } else { XCTFail() }
    }

    func testLerpRect() {
        let from = CGRect(x: 0, y: 0, width: 100, height: 100)
        let to = CGRect(x: 100, y: 100, width: 200, height: 200)
        let v = AnimationValue.lerp(from: .rect(from), to: .rect(to), t: 0.5)
        if case .rect(let r) = v {
            XCTAssertEqual(r.origin.x, 50, accuracy: 0.001)
            XCTAssertEqual(r.size.width, 150, accuracy: 0.001)
        } else { XCTFail() }
    }

    func testKeyEquality() {
        let k1 = AnimationKey(wid: 1, property: .alpha)
        let k2 = AnimationKey(wid: 1, property: .alpha)
        let k3 = AnimationKey(wid: 1, property: .scale)
        XCTAssertEqual(k1, k2)
        XCTAssertNotEqual(k1, k3)
    }
}
