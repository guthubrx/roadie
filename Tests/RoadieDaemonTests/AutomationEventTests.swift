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
    func spec003ConfigReloadPublishesFailureAndPreserveEvents() throws {
        let valid = try #require(Bundle.module.url(forResource: "control-safety-valid", withExtension: "toml"))
        let invalid = try #require(Bundle.module.url(forResource: "control-safety-invalid", withExtension: "toml"))
        let eventPath = tempPath("config-reload-event-assertions")
        let config = try RoadieConfigLoader.load(from: valid.path)
        let log = EventLog(path: eventPath)
        let service = ConfigReloadService(activeConfig: config, activePath: valid.path, eventLog: log)

        _ = service.reload(path: invalid.path)
        let types = log.envelopes(limit: 10).map(\.type)

        #expect(types.contains("config.reload_requested"))
        #expect(types.contains("config.reload_failed"))
        #expect(types.contains("config.active_preserved"))
    }
}
