import Foundation

public enum LogLevel: String, Codable, Sendable, Comparable {
    case debug, info, warn, error

    private var weight: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warn: return 2
        case .error: return 3
        }
    }
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.weight < rhs.weight }
}

public final class Logger: @unchecked Sendable {
    public static let shared = Logger()

    private let queue = DispatchQueue(label: "roadies.logger", qos: .utility)
    private var minLevel: LogLevel = .info
    private var fileHandle: FileHandle?
    private let logPath: String

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {
        let stateDir = (NSString(string: "~/.local/state/roadies").expandingTildeInPath as String)
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        logPath = "\(stateDir)/daemon.log"
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        fileHandle = FileHandle(forWritingAtPath: logPath)
        fileHandle?.seekToEndOfFile()
    }

    public func setMinLevel(_ level: LogLevel) {
        queue.sync { self.minLevel = level }
    }

    public func log(_ level: LogLevel, _ message: String, fields: [String: String] = [:]) {
        queue.async { [weak self] in
            guard let self = self, level >= self.minLevel else { return }
            var entry: [String: String] = [
                "ts": Logger.isoFormatter.string(from: Date()),
                "level": level.rawValue,
                "msg": message
            ]
            for (k, v) in fields { entry[k] = v }
            guard let line = self.encode(entry) else { return }
            if let handle = self.fileHandle, let data = (line + "\n").data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
            // Aussi sur stderr pour debug daemon en foreground
            FileHandle.standardError.write((line + "\n").data(using: .utf8) ?? Data())
            self.rotateIfNeeded()
        }
    }

    private func encode(_ dict: [String: String]) -> String? {
        // Encode JSON simple, sans dépendance, ordre stable.
        let keys = dict.keys.sorted()
        let pairs = keys.map { k -> String in
            let v = dict[k] ?? ""
            let escaped = v
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            return "\"\(k)\":\"\(escaped)\""
        }
        return "{" + pairs.joined(separator: ",") + "}"
    }

    private func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logPath),
              let size = attrs[.size] as? Int64,
              size > 10 * 1024 * 1024 else { return }
        // Rotation simple : rename .log → .log.1, recrée .log vide.
        try? fileHandle?.close()
        try? FileManager.default.removeItem(atPath: logPath + ".1")
        try? FileManager.default.moveItem(atPath: logPath, toPath: logPath + ".1")
        FileManager.default.createFile(atPath: logPath, contents: nil)
        fileHandle = FileHandle(forWritingAtPath: logPath)
    }
}

// Helpers globaux
public func logDebug(_ msg: String, _ fields: [String: String] = [:]) { Logger.shared.log(.debug, msg, fields: fields) }
public func logInfo(_ msg: String, _ fields: [String: String] = [:]) { Logger.shared.log(.info, msg, fields: fields) }
public func logWarn(_ msg: String, _ fields: [String: String] = [:]) { Logger.shared.log(.warn, msg, fields: fields) }
public func logError(_ msg: String, _ fields: [String: String] = [:]) { Logger.shared.log(.error, msg, fields: fields) }
