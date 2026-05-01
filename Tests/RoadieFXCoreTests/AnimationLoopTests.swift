import XCTest
@testable import RoadieFXCore

final class AnimationLoopTests: XCTestCase {
    func testStartStopIdempotent() {
        let loop = AnimationLoop()
        XCTAssertFalse(loop.isRunning)
        loop.start()
        XCTAssertTrue(loop.isRunning)
        loop.start()  // idempotent
        XCTAssertTrue(loop.isRunning)
        loop.stop()
        XCTAssertFalse(loop.isRunning)
        loop.stop()  // idempotent
    }

    func testRegisterUnregister() {
        let loop = AnimationLoop()
        let id = loop.register { _ in }
        loop.unregister(id)
        // Pas d'effet observable mais ne doit pas crash
        XCTAssertFalse(loop.isRunning)
    }

    func testMultipleHandlers() {
        let loop = AnimationLoop()
        let id1 = loop.register { _ in }
        let id2 = loop.register { _ in }
        XCTAssertNotEqual(id1, id2)
        loop.unregister(id1)
        loop.unregister(id2)
    }
}
