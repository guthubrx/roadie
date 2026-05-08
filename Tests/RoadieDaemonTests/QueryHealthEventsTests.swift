import Foundation
import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct QueryHealthEventsTests {
    @Test
    func queryHealthAndEventsExposePayloads() {
        let eventPath = tempPath("query-events")
        let events = EventLog(path: eventPath)
        events.append(RoadieEventEnvelope(
            id: "evt-test",
            type: "window.created",
            scope: .window,
            subject: AutomationSubject(kind: "window", id: "1"),
            cause: .system,
            payload: ["windowID": .string("1")]
        ))
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100)])
        let query = AutomationQueryService(
            service: SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider)),
            eventLog: events
        )

        #expect(query.query("health").kind == "health")
        if case .array(let rows) = query.query("events").data {
            #expect(!rows.isEmpty)
        } else {
            Issue.record("events query did not return an array")
        }
        try? FileManager.default.removeItem(atPath: eventPath)
    }
}
