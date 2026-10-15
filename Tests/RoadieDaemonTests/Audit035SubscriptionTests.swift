import Foundation
import Testing
import RoadieDaemon

struct Audit035SubscriptionTests {
    @Test(arguments: [false, true])
    func malformedUTF8LineDoesNotDiscardItsValidNeighbours(rotated: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("events.jsonl")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        func line(_ type: String) throws -> Data {
            try encoder.encode(RoadieEvent(type: type)) + Data([10])
        }
        var data = try line("valid.before")
        data.append(contentsOf: [0xC3, 0x28, 10])
        data.append(try line("valid.after"))
        try data.write(to: url)
        let service = EventSubscriptionService(path: url.path)
        let cursor = service.start()
        if rotated {
            try FileManager.default.moveItem(at: url, to: URL(fileURLWithPath: url.path + ".1"))
            try line("valid.current").write(to: url)
        }
        let first = service.readAvailable(from: cursor)
        #expect(first.events.map(\.type) == ["valid.before", "valid.after"] + (rotated ? ["valid.current"] : []))
        #expect(service.readAvailable(from: first.cursor).events.isEmpty)
    }
}
