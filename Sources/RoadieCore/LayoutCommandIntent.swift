import Foundation

public struct LayoutCommandIntent: Codable, Equatable, Sendable {
    public var id: String
    public var command: LayoutCommandName
    public var target: LayoutCommandTarget?
    public var arguments: [String: String]
    public var source: LayoutCommandSource
    public var correlationId: String
    public var createdAt: Date

    public init(
        id: String,
        command: LayoutCommandName,
        target: LayoutCommandTarget? = nil,
        arguments: [String: String] = [:],
        source: LayoutCommandSource,
        correlationId: String,
        createdAt: Date = Date()
    ) {
        precondition(!id.isEmpty, "layout command intent id must not be empty")
        precondition(!correlationId.isEmpty, "layout command correlation id must not be empty")
        self.id = id
        self.command = command
        self.target = target
        self.arguments = arguments
        self.source = source
        self.correlationId = correlationId
        self.createdAt = createdAt
    }
}

public struct LayoutCommandName: RawRepresentable, Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "layout command name must not be empty")
        self.rawValue = rawValue
    }

    public static let split = LayoutCommandName(rawValue: "split")
    public static let joinWith = LayoutCommandName(rawValue: "joinWith")
    public static let flatten = LayoutCommandName(rawValue: "flatten")
    public static let insert = LayoutCommandName(rawValue: "insert")
    public static let zoomParent = LayoutCommandName(rawValue: "zoomParent")
    public static let focusBackAndForth = LayoutCommandName(rawValue: "focusBackAndForth")
    public static let desktopBackAndForth = LayoutCommandName(rawValue: "desktopBackAndForth")
    public static let summonWorkspace = LayoutCommandName(rawValue: "summonWorkspace")

    public var description: String { rawValue }
}

public struct LayoutCommandTarget: Codable, Equatable, Hashable, Sendable {
    public var kind: String
    public var id: String

    public init(kind: String, id: String) {
        precondition(!kind.isEmpty, "layout command target kind must not be empty")
        precondition(!id.isEmpty, "layout command target id must not be empty")
        self.kind = kind
        self.id = id
    }
}

public struct LayoutCommandSource: RawRepresentable, Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "layout command source must not be empty")
        self.rawValue = rawValue
    }

    public static let cli = LayoutCommandSource(rawValue: "cli")
    public static let betterTouchTool = LayoutCommandSource(rawValue: "btt")
    public static let rule = LayoutCommandSource(rawValue: "rule")
    public static let system = LayoutCommandSource(rawValue: "system")

    public var description: String { rawValue }
}
