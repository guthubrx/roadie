import Foundation
import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct PerformanceLogServiceTests {
    @Test
    func summarizesInteractionEventsFromEventLogOnly() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-performance-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let log = EventLog(path: url.path)
        log.append(RoadieEvent(type: "stage.changed"))
        log.append(RoadieEvent(type: "stage.changed"))
        log.append(RoadieEvent(type: "config.reloaded"))

        let service = PerformanceLogService(eventLog: log)
        let summary = service.summary(limit: 20)
        let recent = service.recent(limit: 5)

        #expect(summary.sampleCount == 2)
        #expect(summary.rows.first?.eventType == "stage.changed")
        #expect(summary.rows.first?.count == 2)
        #expect(recent.map(\.type) == ["stage.changed", "stage.changed"])
    }
}
