import XCTest
@testable import RoadieDesktops

final class EventBusTests: XCTestCase {

    // MARK: - 1 publisher, 2 subscribers reçoivent l'event (T015)

    func testTwoSubscribersReceiveEvent() async throws {
        let bus = DesktopEventBus()
        let event = DesktopChangeEvent(event: "desktop_changed", from: "1", to: "2")

        let exp1 = expectation(description: "subscriber 1 receives event")
        let exp2 = expectation(description: "subscriber 2 receives event")

        let stream1 = await bus.subscribe()
        let stream2 = await bus.subscribe()

        let task1 = Task {
            for await e in stream1 {
                XCTAssertEqual(e.from, "1")
                XCTAssertEqual(e.to, "2")
                exp1.fulfill()
                break
            }
        }
        let task2 = Task {
            for await e in stream2 {
                XCTAssertEqual(e.from, "1")
                XCTAssertEqual(e.to, "2")
                exp2.fulfill()
                break
            }
        }

        // Petit délai pour que les tasks soient prêtes à lire
        try await Task.sleep(nanoseconds: 10_000_000)
        await bus.publish(event)

        await fulfillment(of: [exp1, exp2], timeout: 1.0)
        task1.cancel()
        task2.cancel()
    }

    // MARK: - Latence < 50 ms (T015, SC-007)

    func testEventLatencyUnder50ms() async throws {
        let bus = DesktopEventBus()
        let stream = await bus.subscribe()
        let exp = expectation(description: "event received within 50ms")

        let task = Task {
            let start = Date()
            for await _ in stream {
                let elapsed = Date().timeIntervalSince(start) * 1000
                XCTAssertLessThan(elapsed, 50, "Event latency \(elapsed) ms exceeds 50 ms")
                exp.fulfill()
                break
            }
        }

        try await Task.sleep(nanoseconds: 5_000_000)
        await bus.publish(DesktopChangeEvent(event: "desktop_changed", from: "1", to: "3"))

        await fulfillment(of: [exp], timeout: 1.0)
        task.cancel()
    }

    // MARK: - Cleanup à la déconnexion (T015)

    func testCleanupOnCancellation() async throws {
        let bus = DesktopEventBus()
        let stream = await bus.subscribe()

        let task = Task {
            for await _ in stream { break }
        }
        // S'assurer que la subscription est enregistrée
        try await Task.sleep(nanoseconds: 20_000_000)
        let countBefore = await bus.subscriberCount
        XCTAssertGreaterThan(countBefore, 0)

        task.cancel()
        // Laisser le temps à onTermination de s'exécuter
        try await Task.sleep(nanoseconds: 30_000_000)
        // Après annulation, le subscriber doit être retiré
        let countAfter = await bus.subscriberCount
        XCTAssertEqual(countAfter, 0)
    }

    // MARK: - Sérialisation JSON-line (format contrat)

    func testJSONLineFormat() {
        let event = DesktopChangeEvent(event: "desktop_changed", from: "1", to: "2",
                                       fromLabel: "code", toLabel: "comm", ts: 1700000000000)
        let line = event.toJSONLine()
        XCTAssertTrue(line.hasSuffix("\n"))
        XCTAssertTrue(line.contains("\"event\""))
        XCTAssertTrue(line.contains("desktop_changed"))
        XCTAssertTrue(line.contains("\"from\""))
        XCTAssertTrue(line.contains("\"to\""))
        XCTAssertTrue(line.contains("\"ts\""))
    }
}
