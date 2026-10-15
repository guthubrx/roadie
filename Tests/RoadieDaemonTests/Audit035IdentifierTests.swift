import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

struct Audit035IdentifierTests {
    @Test
    func invalidSerializedIdentifiersThrowInsteadOfTrapping() throws {
        let empty = Data("\"\"".utf8)
        let zero = Data("0".utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(DisplayID.self, from: empty) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(StageID.self, from: empty) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(LogicalDisplayID.self, from: empty) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(DesktopID.self, from: zero) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(WindowID.self, from: zero) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(DesktopID.self, from: Data("-1".utf8)) }
    }

    @Test
    func validIdentifiersKeepTheirScalarWireFormat() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let display = DisplayID(rawValue: "external")
        let stage = StageID(rawValue: "work/with spaces")
        let desktop = DesktopID(rawValue: 1)
        let window = WindowID(rawValue: UInt32.max)
        let logical = LogicalDisplayID(displayID: display)
        #expect(try encoder.encode(display) == Data("\"external\"".utf8))
        #expect(try encoder.encode(desktop) == Data("1".utf8))
        #expect(try decoder.decode(DisplayID.self, from: encoder.encode(display)) == display)
        #expect(try decoder.decode(StageID.self, from: encoder.encode(stage)) == stage)
        #expect(try decoder.decode(DesktopID.self, from: encoder.encode(desktop)) == desktop)
        #expect(try decoder.decode(WindowID.self, from: encoder.encode(window)) == window)
        #expect(try decoder.decode(LogicalDisplayID.self, from: encoder.encode(logical)) == logical)
    }

    @Test
    func unreadableStateIsPreservedAndWritesAreRefused() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stages.json")
        let invalid = Data("{\"activeDisplayID\":\"\"}".utf8)
        try invalid.write(to: url)
        let store = StageStore(path: url.path)
        #expect(store.loadFailure != nil)
        #expect(store.state().scopes.isEmpty)
        store.save(PersistentStageState())
        #expect(try Data(contentsOf: url) == invalid)
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("stages.json.corrupt-") }
        #expect(backups.count == 1)
        #expect(try backups.map { try Data(contentsOf: $0) } == [invalid])
    }
}
