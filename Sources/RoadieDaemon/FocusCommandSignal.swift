import Foundation
import RoadieCore

public struct FocusCommandSignal: Codable, Equatable, Sendable {
    public var sequence: UInt64
    public var windowID: WindowID
    public var timestamp: Date

    public init(sequence: UInt64, windowID: WindowID, timestamp: Date) {
        self.sequence = sequence
        self.windowID = windowID
        self.timestamp = timestamp
    }
}

public struct FocusCommandSignalStore: Sendable {
    private let url: URL

    public init(path: String = Self.defaultPath()) {
        self.url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    public var fileURL: URL {
        url
    }

    public static func defaultPath() -> String {
        if ProcessInfo.processInfo.processName.lowercased().contains("test") {
            return "\(NSTemporaryDirectory())roadie-test-focus-command-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString).json"
        }
        return "~/.local/state/roadies/focus-command.json"
    }

    public func load() -> FocusCommandSignal? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        if let signal = try? decoder.decode(FocusCommandSignal.self, from: data) {
            return signal
        }
        let legacyDecoder = JSONDecoder()
        legacyDecoder.dateDecodingStrategy = .iso8601
        return try? legacyDecoder.decode(FocusCommandSignal.self, from: data)
    }

    public func ensureFile() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                try Data().write(to: url, options: .atomic)
            }
        } catch {
            fputs("roadie: failed to prepare focus command signal: \(error)\n", stderr)
        }
    }

    public func save(_ signal: FocusCommandSignal) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            try encoder.encode(signal).write(to: url, options: .atomic)
        } catch {
            fputs("roadie: failed to write focus command signal: \(error)\n", stderr)
        }
    }
}
