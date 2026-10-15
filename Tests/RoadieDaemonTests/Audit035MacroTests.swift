import CoreGraphics
import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

struct Audit035MacroTests {
    @Test(arguments: ["negative-time", "long-wait", "duration", "schema", "event-count"])
    func invalidRecordingPostsNoEvents(variant: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var recording = TargetMacroRecording(name: "bad", durationSeconds: 0.01, events: [
            TargetMacroEvent(t: 0, kind: .keyDown, keyCode: 0),
            TargetMacroEvent(t: 0, kind: .keyUp, keyCode: 0)
        ])
        switch variant {
        case "negative-time": recording.events[1].t = -1
        case "long-wait": recording.events[1].t = 3_601
        case "duration": recording.durationSeconds = 3_601
        case "schema": recording.schemaVersion = 2
        default: recording.events = Array(repeating: recording.events[0], count: 20_001)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(recording).write(to: directory.appendingPathComponent("bad.json"))
        var posted = 0
        let service = TargetMacroService(
            service: SnapshotService(config: RoadieConfig()),
            config: TargetRecordConfig(replayEnabled: true, directory: directory.path),
            postEvent: { _ in posted += 1 }
        )
        let result = service.replay("bad")
        #expect(result.error == "replay_failed")
        #expect(!result.changed)
        #expect(posted == 0)
    }

    @Test
    func validRecordingStillReplaysBalancedKeyEvents() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = TargetMacroRecording(name: "valid", durationSeconds: 0.01, events: [
            TargetMacroEvent(t: 0, kind: .keyDown, keyCode: 0),
            TargetMacroEvent(t: 0, kind: .keyUp, keyCode: 0)
        ])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(recording).write(to: directory.appendingPathComponent("valid.json"))
        var posted: [CGEventType] = []
        let service = TargetMacroService(
            service: SnapshotService(config: RoadieConfig()),
            config: TargetRecordConfig(replayEnabled: true, directory: directory.path),
            postEvent: { posted.append($0.type) }
        )
        let result = service.replay("valid")
        #expect(result.error == nil)
        #expect(result.changed)
        #expect(posted == [.keyDown, .keyUp])
    }

    @Test(arguments: [-1, 65_536])
    func invalidKeyCodesAreRejectedBeforePlayback(keyCode: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = TargetMacroRecording(name: "bad", durationSeconds: 0.01, events: [
            TargetMacroEvent(t: 0, kind: .keyDown, keyCode: keyCode)
        ])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(recording).write(to: directory.appendingPathComponent("bad.json"))
        let service = TargetMacroService(config: TargetRecordConfig(replayEnabled: true, directory: directory.path))
        // Check the actual file loader first: a baseline failure cannot inject desktop input.
        var rejected = false
        do { _ = try service.inspect("bad") } catch { rejected = true }
        #expect(rejected, "Unrepresentable key code must be rejected by the file boundary")
        if rejected {
            let result = service.replay("bad")
            #expect(!result.changed)
            #expect(result.error == "replay_failed")
        }
    }
}
