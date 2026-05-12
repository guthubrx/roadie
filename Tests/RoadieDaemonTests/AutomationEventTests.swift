import Foundation
import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct AutomationEventTests {
    @Test
    func spec002EventEnvelopeRoundTripsJSONPayloads() throws {
        let event = RoadieEventEnvelope(
            id: "evt-test",
            timestamp: Date(timeIntervalSince1970: 1_777_777_777),
            type: "window.focused",
            scope: .window,
            subject: AutomationSubject(kind: "window", id: "42"),
            correlationId: "cmd-test",
            cause: .ax,
            payload: [
                "windowId": .string("42"),
                "count": .int(2),
                "visible": .bool(true),
                "metadata": .object(["stage": .string("dev")]),
                "tags": .array([.string("focused"), .string("tile")]),
                "empty": .null
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(RoadieEventEnvelope.self, from: data)

        #expect(decoded == event)
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.payload["metadata"] == .object(["stage": .string("dev")]))
    }

    @Test
    func spec002EventLogReadsEnvelopeAndLegacyEvents() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-events-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let log = EventLog(path: url.path)
        let scope = StageScope(
            displayID: DisplayID(rawValue: "display-a"),
            desktopID: DesktopID(rawValue: 1),
            stageID: StageID(rawValue: "dev")
        )

        log.append(RoadieEventEnvelope(
            id: "evt-envelope",
            timestamp: Date(timeIntervalSince1970: 1_777_777_700),
            type: "command.applied",
            scope: .command,
            subject: AutomationSubject(kind: "command", id: "layout.flatten"),
            correlationId: "cmd-envelope",
            cause: .command,
            payload: ["result": .string("success")]
        ))
        log.append(RoadieEvent(
            type: "legacy.event",
            scope: scope,
            details: ["key": "value"],
            timestamp: Date(timeIntervalSince1970: 1_777_777_701)
        ))

        let envelopes = log.envelopes(limit: 10)

        #expect(envelopes.map(\.type) == ["command.applied", "legacy.event"])
        #expect(envelopes[0].id == "evt-envelope")
        #expect(envelopes[1].id.hasPrefix("legacy_"))
        #expect(envelopes[1].scope == .stage)
        #expect(envelopes[1].subject == AutomationSubject(kind: "stage", id: scope.description))
        #expect(envelopes[1].payload["key"] == .string("value"))
    }

    @Test
    func catalogContainsWindowPinEvents() {
        let catalog = AutomationEventCatalog()

        #expect(catalog.contains("window.pin_added"))
        #expect(catalog.contains("window.pin_scope_changed"))
        #expect(catalog.contains("window.pin_removed"))
        #expect(catalog.contains("window.pin_pruned"))
        #expect(catalog.contains("window.pin_collapsed"))
        #expect(catalog.contains("window.pin_restored"))
    }

    @Test
    func catalogContainsPinPopoverEvents() {
        let catalog = AutomationEventCatalog()

        #expect(catalog.contains("pin_popover.shown"))
        #expect(catalog.contains("pin_popover.ignored"))
        #expect(catalog.contains("pin_popover.action"))
        #expect(catalog.contains("pin_popover.failed"))
    }
}
