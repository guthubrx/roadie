import Foundation
import Testing
import RoadieDaemon

struct Audit035EventLogTests {
    @Test
    func tailPreservesLongLinesAndTrailingNewlineVariants() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let lines = [String(repeating: "é", count: 90_000), "second", "third"]
        for suffix in ["", "\n"] {
            try (lines.joined(separator: "\n") + suffix).write(to: url, atomically: true, encoding: .utf8)
            let log = EventLog(path: url.path)
            #expect(log.tail(limit: 2) == Array(lines.suffix(2)))
            #expect(log.tail(limit: 10) == lines)
        }
    }

    @Test
    func measureLargeTail() throws {
        guard ProcessInfo.processInfo.environment["ROADIE_AUDIT_BENCHMARK"] == "1" else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        for bytes in [2_621_440, 10_485_760] {
            let line = String(repeating: "a", count: 127) + "\n"
            try String(repeating: line, count: bytes / 128).write(to: url, atomically: true, encoding: .utf8)
            let log = EventLog(path: url.path)
            _ = log.tail(limit: Int.max)
            var measurements: [Double] = []
            for _ in 0..<3 {
                let start = ContinuousClock.now
                #expect(log.tail(limit: Int.max).count == bytes / 128)
                let elapsed = start.duration(to: .now).components
                measurements.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
            }
            print("AUDIT035_TAIL bytes=\(bytes) milliseconds=\(measurements)")
        }
    }
}
