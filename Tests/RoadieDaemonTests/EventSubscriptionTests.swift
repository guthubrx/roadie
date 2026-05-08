import Foundation
import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct EventSubscriptionTests {
    @Test
    func spec002SubscribeFromNowSkipsExistingEvents() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-subscribe-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let log = EventLog(path: url.path)
        let service = EventSubscriptionService(path: url.path)

        log.append(event(id: "evt-before", type: "window.created"))
        let cursor = service.start(options: EventSubscriptionOptions(fromNow: true))
        log.append(event(id: "evt-after", type: "window.focused"))

        let result = service.readAvailable(from: cursor)

        #expect(result.events.map(\.id) == ["evt-after"])
        #expect(result.cursor.offset > cursor.offset)
    }

    private func event(id: String, type: String, scope: AutomationScope = .window) -> RoadieEventEnvelope {
        RoadieEventEnvelope(
            id: id,
            timestamp: Date(timeIntervalSince1970: 1_777_777_777),
            type: type,
            scope: scope,
            subject: AutomationSubject(kind: "window", id: "42"),
            correlationId: "cmd-\(id)",
            cause: .ax,
            payload: ["windowId": .string("42")]
        )
    }
}
