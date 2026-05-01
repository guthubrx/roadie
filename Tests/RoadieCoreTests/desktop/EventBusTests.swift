import XCTest
@testable import RoadieCore

@MainActor
final class EventBusTests: XCTestCase {

    func test_jsonLine_includesCommonFields() {
        let event = DesktopEvent(name: "desktop_changed",
                                 ts: Date(timeIntervalSince1970: 1714579371.832),
                                 payload: ["from": "uuid-A", "to": "uuid-B"])
        let line = event.toJSONLine()
        XCTAssertTrue(line.hasSuffix("\n"))
        guard let data = line.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("invalid JSON: \(line)")
            return
        }
        XCTAssertEqual(dict["event"] as? String, "desktop_changed")
        XCTAssertEqual(dict["version"] as? Int, 1)
        XCTAssertEqual(dict["from"] as? String, "uuid-A")
        XCTAssertEqual(dict["to"] as? String, "uuid-B")
        XCTAssertNotNil(dict["ts"] as? String)
    }

    func test_publishToSubscriber_deliversEvent() async {
        let bus = EventBus()
        let stream = bus.subscribe()
        bus.publish(DesktopEvent(name: "x", payload: ["k": "v"]))
        var iter = stream.makeAsyncIterator()
        let received = await iter.next()
        XCTAssertEqual(received?.name, "x")
        XCTAssertEqual(received?.payload["k"], "v")
    }

    func test_multipleSubscribers_allReceiveEvent() async {
        let bus = EventBus()
        let s1 = bus.subscribe()
        let s2 = bus.subscribe()
        XCTAssertEqual(bus.subscriberCount, 2)
        bus.publish(DesktopEvent(name: "shared"))

        var i1 = s1.makeAsyncIterator()
        var i2 = s2.makeAsyncIterator()
        let r1 = await i1.next()
        let r2 = await i2.next()
        XCTAssertEqual(r1?.name, "shared")
        XCTAssertEqual(r2?.name, "shared")
    }

    func test_publishOrder_preservedPerSubscriber() async {
        let bus = EventBus()
        let stream = bus.subscribe()
        bus.publish(DesktopEvent(name: "a"))
        bus.publish(DesktopEvent(name: "b"))
        bus.publish(DesktopEvent(name: "c"))
        var iter = stream.makeAsyncIterator()
        let names = await [iter.next()?.name, iter.next()?.name, iter.next()?.name]
        XCTAssertEqual(names, ["a", "b", "c"])
    }

    func test_singleton_isShared() {
        let s1 = EventBus.shared
        let s2 = EventBus.shared
        XCTAssertTrue(s1 === s2)
    }
}
