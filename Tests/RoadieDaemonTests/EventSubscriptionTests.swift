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

    @Test
    func spec002SubscribeInitialStateEmitsSnapshotEvent() {
        let service = EventSubscriptionService(path: "/tmp/roadie-missing-\(UUID().uuidString).jsonl")
        let snapshot = RoadieStateSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_777_777_777),
            activeDisplayId: "display-main",
            activeDesktopId: "desktop-1",
            activeStageId: "stage-dev",
            focusedWindowId: "window-terminal",
            displays: [
                AutomationDisplaySnapshot(
                    id: "display-main",
                    name: "Built-in Display",
                    frame: Rect(x: 0, y: 0, width: 1728, height: 1117)
                )
            ],
            windows: [
                AutomationWindowSnapshot(id: "window-terminal", app: "Terminal", title: "roadie", isFocused: true)
            ]
        )

        let events = service.initialEvents(
            snapshot: snapshot,
            options: EventSubscriptionOptions(initialState: true)
        )

        #expect(events.count == 1)
        #expect(events[0].type == "state.snapshot")
        #expect(events[0].payload["activeDisplayId"] == .string("display-main"))
        #expect(events[0].payload["windowCount"] == .int(1))
    }

    @Test
    func spec002SubscribeReadsAppendedEventsUnderOneSecond() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-latency-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let log = EventLog(path: url.path)
        let service = EventSubscriptionService(path: url.path)
        let cursor = service.start(options: EventSubscriptionOptions(fromNow: true))

        let started = Date()
        log.append(event(id: "evt-latency", type: "window.focused"))
        let result = service.readAvailable(from: cursor)
        let elapsed = Date().timeIntervalSince(started)

        #expect(result.events.map(\.id) == ["evt-latency"])
        #expect(elapsed < 1.0)
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
