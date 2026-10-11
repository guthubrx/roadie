import Foundation
import Testing
import RoadieCore
import RoadieDaemon

/// Horloge modifiable pour fermer un épisode sans attendre.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_777_777_777.25)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

@Suite
struct EventEpisodeTests {
    private func tempLog() -> (EventLog, URL, TestClock, EpisodeContext) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-episode-\(UUID().uuidString).jsonl")
        let clock = TestClock()
        let context = EpisodeContext(now: { clock.now })
        return (EventLog(path: url.path, episodes: context), url, clock, context)
    }

    @Test
    func legacyLineWithoutNewFieldsDecodes() throws {
        let line = #"{"details":{"commands":"1"},"timestamp":"2026-05-25T10:33:43Z","type":"layout_apply"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let event = try decoder.decode(RoadieEvent.self, from: Data(line.utf8))
        let envelopeLine = #"{"schemaVersion":1,"id":"e","timestamp":"2026-05-25T10:33:43Z","type":"x","cause":"system","payload":{}}"#
        let envelope = try decoder.decode(RoadieEventEnvelope.self, from: Data(envelopeLine.utf8))

        #expect(event.type == "layout_apply")
        #expect(event.tsMs == nil)
        #expect(event.episodeId == nil)
        #expect(envelope.tsMs == nil)
    }

    @Test
    func tsMsMatchesTimestampAndSurvivesTheLog() throws {
        let (log, url, _, _) = tempLog()
        defer { try? FileManager.default.removeItem(at: url) }
        let date = Date(timeIntervalSince1970: 1_777_777_777.25)
        log.append(RoadieEvent(type: "layout_apply", timestamp: date))
        log.append(RoadieEventEnvelope(id: "evt", timestamp: date, type: "window.focused", cause: .ax))

        let lines = log.tail(limit: 2)
        let objects = try lines.map { try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }

        for object in objects {
            #expect((object["tsMs"] as? NSNumber)?.int64Value == 1_777_777_777_250)
            #expect(object["timestamp"] is String)
        }
        #expect(date.epochMilliseconds / 1000 == 1_777_777_777)
    }

    @Test
    func episodeIdIsSetByContextAndStableAcrossContinue() throws {
        let (log, url, clock, context) = tempLog()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(context.current == nil)

        let id = context.begin(cause: "ax:moved")
        log.append(RoadieEvent(type: "a"))
        clock.advance(0.6)
        #expect(context.continue() == id)
        clock.advance(0.6)
        log.append(RoadieEvent(type: "b"))
        log.append(RoadieEvent(type: "c", episodeId: "ep_explicit"))

        #expect(id == "ep_1777777777250")
        #expect(context.currentCause == "ax:moved")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let events = try log.tail(limit: 3).map { try decoder.decode(RoadieEvent.self, from: Data($0.utf8)) }
        #expect(events.map(\.episodeId) == [id, id, "ep_explicit"])
    }

    @Test
    func episodeClosesAfterOneSecondWithoutActivityAndNewCauseGetsNewId() {
        let clock = TestClock()
        let context = EpisodeContext(now: { clock.now })
        let first = context.begin(cause: "command:x")

        clock.advance(1.5)
        #expect(context.current == nil)
        #expect(context.continue() == nil)

        let second = context.begin(cause: "drag")
        let third = context.begin(cause: "drag")
        #expect(first != second)
        #expect(second != third)
        #expect(context.current == third)
    }

    @Test
    func catalogDeclaresLayoutEventsAndKeepsObsoleteMutableBspTypes() {
        let catalog = AutomationEventCatalog()
        for type in ["layout_echo_ignored", "layout_app_response_accepted", "layout_external_change_reverted",
                     "layout_manual_gesture", "space_transition_guard", "state_migrated"] {
            #expect(catalog.contains(type))
            #expect(!catalog.isObsolete(type))
        }
        for type in ["mutable_bsp_geometry_adopted", "mutable_bsp_order_repaired", "mutable_bsp_resize_propagated"] {
            #expect(catalog.contains(type))
            #expect(catalog.isObsolete(type))
        }
    }
}
