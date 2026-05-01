import XCTest
@testable import RoadieFXCore

final class OSAXBridgeTests: XCTestCase {
    func testSendWhenDisconnectedQueuesAndReturnsError() async {
        let bridge = OSAXBridge(socketPath: "/tmp/roadied-osax-test-nonexistent.sock")
        let result = await bridge.send(.noop)
        if case .error(let code, _) = result {
            XCTAssertEqual(code, "bridge_disconnected")
        } else {
            XCTFail("expected disconnected error")
        }
    }

    func testQueueDepthAfterSend() async {
        let bridge = OSAXBridge(socketPath: "/tmp/roadied-osax-test-nonexistent2.sock")
        _ = await bridge.send(.setAlpha(wid: 1, alpha: 0.5))
        _ = await bridge.send(.setAlpha(wid: 2, alpha: 0.5))
        let depth = await bridge.queueDepth
        XCTAssertEqual(depth, 2)
    }

    func testIsConnectedFalseWhenSocketAbsent() async {
        let bridge = OSAXBridge(socketPath: "/tmp/roadied-osax-test-nonexistent3.sock")
        let connected = await bridge.isConnected
        XCTAssertFalse(connected)
    }

    func testDisconnect() async {
        let bridge = OSAXBridge()
        await bridge.disconnect()
        let connected = await bridge.isConnected
        XCTAssertFalse(connected)
    }

    func testQueueCapAt1000() async {
        let bridge = OSAXBridge(socketPath: "/tmp/roadied-osax-test-cap.sock")
        // Envoie 1100 commandes : la queue doit cap à 1000.
        for i in 0..<1100 {
            _ = await bridge.send(.setAlpha(wid: CGWindowID(i), alpha: 0.5))
        }
        let depth = await bridge.queueDepth
        XCTAssertLessThanOrEqual(depth, OSAXBridge.maxQueueSize)
    }
}
