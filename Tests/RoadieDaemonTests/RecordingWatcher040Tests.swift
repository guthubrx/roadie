import Foundation
import Testing
@testable import RoadieDaemon

@MainActor
struct RecordingWatcher040Tests {
    @Test func unrelatedAtomicWritesDoNotRefreshRecording() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("recording-watch-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = directory.appendingPathComponent("recording.json")
        var changes = 0
        let watcher = RailFileWatcher(path: { directory.path }, observedFile: { recording.path }, onChange: { changes += 1 })
        watcher.start()
        defer { watcher.stop() }
        try "{}".write(to: directory.appendingPathComponent("restore.json"), atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(150))
        #expect(changes == 0)
        for text in ["one", "two"] {
            let before = changes
            try text.write(to: recording, atomically: true, encoding: .utf8)
            for _ in 0..<100 where changes == before { try await Task.sleep(for: .milliseconds(10)) }
            #expect(changes > before)
        }
        let beforeDelete = changes
        try FileManager.default.removeItem(at: recording)
        for _ in 0..<100 where changes == beforeDelete { try await Task.sleep(for: .milliseconds(10)) }
        #expect(changes > beforeDelete)
    }
}
