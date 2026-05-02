import XCTest
@testable import RoadieDesktops

/// Tests US5 — Stream d'events (T051, SC-007).
/// Couvre : latence < 50 ms, filtre types, limite 16 subscribers, cleanup.
final class EventStreamTests: XCTestCase {

    // MARK: - Latence < 50 ms (SC-007)

    func testEventReceivedWithin50ms() async throws {
        let bus = DesktopEventBus()
        let stream = await bus.subscribe()
        var receivedAt: Date?

        let task = Task {
            for await _ in stream {
                receivedAt = Date()
                break
            }
        }
        // Attendre que la subscription soit enregistrée
        try await Task.sleep(nanoseconds: 5_000_000)

        let before = Date()
        await bus.publish(DesktopChangeEvent(event: "desktop_changed", from: "1", to: "2"))

        // Attendre réception (max 200 ms pour le test)
        var waited: TimeInterval = 0
        while receivedAt == nil && waited < 0.2 {
            try await Task.sleep(nanoseconds: 5_000_000)
            waited += 0.005
        }
        task.cancel()

        let elapsed = (receivedAt ?? Date()).timeIntervalSince(before) * 1000
        XCTAssertNotNil(receivedAt, "Event non reçu")
        XCTAssertLessThan(elapsed, 50, "Latence \(elapsed) ms dépasse 50 ms (SC-007)")
    }

    // MARK: - Filtre par types (T049)

    func testDesktopChangedEventJsonLine() {
        let event = DesktopChangeEvent(
            event: "desktop_changed", from: "1", to: "2",
            fromLabel: "code", toLabel: "comm", ts: 1700000000000
        )
        let line = event.toJSONLine()
        XCTAssertTrue(line.contains("\"desktop_changed\""))
        XCTAssertTrue(line.contains("\"from_label\""))
        XCTAssertTrue(line.contains("\"to_label\""))
        XCTAssertFalse(line.contains("\"desktop_id\""),
                       "desktop_changed ne doit pas avoir desktop_id")
    }

    func testStageChangedEventJsonLine() {
        let event = DesktopChangeEvent(
            event: "stage_changed", from: "1", to: "2",
            desktopID: "3", ts: 1700000000000
        )
        let line = event.toJSONLine()
        XCTAssertTrue(line.contains("\"stage_changed\""))
        XCTAssertTrue(line.contains("\"desktop_id\""))
        XCTAssertTrue(line.contains("\"3\""))
        XCTAssertFalse(line.contains("\"from_label\""),
                       "stage_changed ne doit pas avoir from_label")
    }

    // MARK: - Limite 16 subscribers (T049)

    func testMaxSubscribersLimit() async throws {
        let bus = DesktopEventBus()
        var tasks: [Task<Void, Never>] = []

        // Ouvrir 16 subscribers
        for _ in 0..<16 {
            let stream = await bus.subscribe()
            let t = Task {
                for await _ in stream { break }
            }
            tasks.append(t)
        }

        // Attendre l'enregistrement
        try await Task.sleep(nanoseconds: 20_000_000)
        let count = await bus.subscriberCount
        XCTAssertEqual(count, 16, "Doit avoir exactement 16 subscribers")

        // Annuler tous
        tasks.forEach { $0.cancel() }
        try await Task.sleep(nanoseconds: 30_000_000)
        let afterCancel = await bus.subscriberCount
        XCTAssertEqual(afterCancel, 0, "Tous les subscribers doivent être retirés après cancel")
    }

    // MARK: - Cleanup à la déconnexion (T049, T051)

    func testSubscriberCleanupOnCancel() async throws {
        let bus = DesktopEventBus()
        let stream = await bus.subscribe()

        let task = Task {
            for await _ in stream { break }
        }

        try await Task.sleep(nanoseconds: 15_000_000)
        let before = await bus.subscriberCount
        XCTAssertGreaterThan(before, 0)

        task.cancel()
        try await Task.sleep(nanoseconds: 40_000_000)

        let after = await bus.subscriberCount
        XCTAssertEqual(after, 0, "Subscriber doit être retiré après annulation")
    }

    // MARK: - Plusieurs subscribers reçoivent tous le même event

    func testMultipleSubscribersAllReceive() async throws {
        let bus = DesktopEventBus()

        let count = 3
        var received = Array(repeating: false, count: count)
        var tasks: [Task<Void, Never>] = []

        for i in 0..<count {
            let stream = await bus.subscribe()
            let idx = i
            let t = Task {
                for await _ in stream {
                    received[idx] = true
                    break
                }
            }
            tasks.append(t)
        }

        try await Task.sleep(nanoseconds: 15_000_000)
        await bus.publish(DesktopChangeEvent(event: "desktop_changed", from: "1", to: "2"))
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(received.allSatisfy { $0 }, "Tous les subscribers doivent recevoir l'event")
        tasks.forEach { $0.cancel() }
    }
}
