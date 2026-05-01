import XCTest
import CoreGraphics
import RoadieFXCore
@testable import RoadieAnimations

final class AnimationQueueTests: XCTestCase {
    func makeAnim(wid: CGWindowID, prop: AnimatedProperty,
                  start: TimeInterval = 0, dur: TimeInterval = 1) -> Animation {
        Animation(wid: wid, property: prop,
                  from: .scalar(0), to: .scalar(1),
                  curve: .linear, startTime: start, duration: dur)
    }

    func testEnqueueSingle() async {
        let q = AnimationQueue()
        await q.enqueue(makeAnim(wid: 1, prop: .alpha))
        let count = await q.count
        XCTAssertEqual(count, 1)
    }

    func testCoalescingSameKey() async {
        let q = AnimationQueue()
        await q.enqueue(makeAnim(wid: 1, prop: .alpha))
        await q.enqueue(makeAnim(wid: 1, prop: .alpha))
        let count = await q.count
        XCTAssertEqual(count, 1, "coalescing should keep only 1")
    }

    func testDifferentKeysCoexist() async {
        let q = AnimationQueue()
        await q.enqueue(makeAnim(wid: 1, prop: .alpha))
        await q.enqueue(makeAnim(wid: 1, prop: .scale))
        await q.enqueue(makeAnim(wid: 2, prop: .alpha))
        let count = await q.count
        XCTAssertEqual(count, 3)
    }

    func testMaxConcurrentDropsOldest() async {
        let q = AnimationQueue(maxConcurrent: 3)
        for i in 0..<5 {
            await q.enqueue(makeAnim(wid: CGWindowID(i), prop: .alpha))
        }
        let count = await q.count
        XCTAssertEqual(count, 3)
    }

    func testCancelByWid() async {
        let q = AnimationQueue()
        await q.enqueue(makeAnim(wid: 1, prop: .alpha))
        await q.enqueue(makeAnim(wid: 1, prop: .scale))
        await q.enqueue(makeAnim(wid: 2, prop: .alpha))
        await q.cancel(wid: 1)
        let count = await q.count
        XCTAssertEqual(count, 1)
    }

    func testCancelAll() async {
        let q = AnimationQueue()
        await q.enqueue(makeAnim(wid: 1, prop: .alpha))
        await q.enqueue(makeAnim(wid: 2, prop: .scale))
        await q.cancelAll()
        let count = await q.count
        XCTAssertEqual(count, 0)
    }

    func testPauseStopsEmissions() async {
        let q = AnimationQueue()
        await q.enqueue(makeAnim(wid: 1, prop: .alpha))
        await q.pause()
        let cmds = await q.tick(now: 0.5)
        XCTAssertTrue(cmds.isEmpty)
    }

    func testTickEmitsCommandAtMid() async {
        let q = AnimationQueue()
        await q.enqueue(makeAnim(wid: 1, prop: .alpha, start: 0, dur: 1))
        let cmds = await q.tick(now: 0.5)
        XCTAssertEqual(cmds.count, 1)
        if case .setAlpha(_, let a) = cmds.first! {
            XCTAssertEqual(a, 0.5, accuracy: 0.005)
        } else { XCTFail() }
    }

    func testTickRemovesFinishedAnim() async {
        let q = AnimationQueue()
        await q.enqueue(makeAnim(wid: 1, prop: .alpha, start: 0, dur: 1))
        _ = await q.tick(now: 1.5)  // après fin
        let count = await q.count
        XCTAssertEqual(count, 0)
    }
}
