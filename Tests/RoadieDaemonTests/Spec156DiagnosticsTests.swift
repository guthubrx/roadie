import Foundation
import Testing
@testable import RoadieDaemon

@Suite(.serialized) @MainActor struct Spec156DiagnosticsTests {
    @Test func ordinaryPreparationRetryIsCountedWithoutTwoExtraEvents() async throws {
        let path = tempPath("spec156-preparation")
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: path + ".lock")
        }
        var now = Date(timeIntervalSince1970: 1_000)
        var scheduled: (@MainActor () -> Void)?
        var preparations = 0, ticks = 0
        let scheduler = TickScheduler(tick: { _ in
            ticks += 1
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
        }, nextDeadline: { _ in nil }, isBlocked: { false }, now: { now }, schedule: { _, action in
            scheduled = action
            return {}
        }, events: EventLog(path: path), prepare: { preparations += 1; return preparations > 1 })
        defer { scheduler.stop() }
        scheduler.request(cause: "test")
        now.addTimeInterval(0.02)
        let first = try #require(scheduled); scheduled = nil; first()
        for _ in 0..<100 {
            if scheduled != nil { break }
            try? await Task.sleep(for: .milliseconds(2))
        }
        now.addTimeInterval(0.1)
        let second = try #require(scheduled); scheduled = nil; second()
        for _ in 0..<100 {
            if ticks == 1 { break }
            try? await Task.sleep(for: .milliseconds(2))
        }
        let rows = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n")
            .compactMap { try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        #expect(preparations == 2 && ticks == 1)
        #expect(!rows.contains { $0["type"] as? String == "layout.preparation" })
        let event = try #require(rows.first { $0["type"] as? String == "live_tick" })
        let details = try #require(event["details"] as? [String: String])
        #expect(details["preparationRetries"] == "1")
        #expect(details["resultPhase"] == "immediate")
    }
}
