import Foundation

/// Format des messages CLI ↔ daemon (cf. contracts/cli-protocol.md).
/// Encoding : JSON-lines sur Unix socket.

public struct Request: Codable {
    public let version: String
    public let command: String
    public let args: [String: String]?

    public init(command: String, args: [String: String]? = nil) {
        self.version = "roadie/1"
        self.command = command
        self.args = args
    }
}

public struct Response: Codable {
    public let version: String
    public let status: Status
    public let payload: [String: AnyCodable]?
    public let errorCode: String?
    public let errorMessage: String?

    public enum Status: String, Codable {
        case success, error
    }

    enum CodingKeys: String, CodingKey {
        case version
        case status
        case payload
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }

    public static func success(_ payload: [String: AnyCodable] = [:]) -> Response {
        Response(version: "roadie/1", status: .success, payload: payload, errorCode: nil, errorMessage: nil)
    }

    public static func error(_ code: ErrorCode, _ message: String) -> Response {
        Response(version: "roadie/1", status: .error, payload: nil, errorCode: code.rawValue, errorMessage: message)
    }
}

/// Type-erased Codable simple pour les payloads hétérogènes.
public struct AnyCodable: Codable, Sendable {
    public let value: Any

    public init(_ value: Any) { self.value = value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            value = s
        } else if let i = try? container.decode(Int.self) {
            value = i
        } else if let d = try? container.decode(Double.self) {
            value = d
        } else if let b = try? container.decode(Bool.self) {
            value = b
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            value = ""
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let s as String: try container.encode(s)
        case let i as Int: try container.encode(i)
        case let d as Double: try container.encode(d)
        case let b as Bool: try container.encode(b)
        case let arr as [Any]: try container.encode(arr.map { AnyCodable($0) })
        case let dict as [String: Any]: try container.encode(dict.mapValues { AnyCodable($0) })
        default: try container.encodeNil()
        }
    }
}
