import Foundation

public struct CollectionSpec: Equatable, Sendable {
    public enum Shape: Equatable, Sendable {
        case list(element: SettingKind, suggestions: [String], minCount: Int, unique: Bool, sorted: Bool)
        case rows(table: String, fields: [CollectionFieldSpec], uniqueKey: String?, oneOf: [[String]])
        case advanced(table: String)
    }
    public let shape: Shape
    public let defaultValue: CollectionValue
    public init(shape: Shape, defaultValue: CollectionValue) {
        self.shape = shape
        self.defaultValue = defaultValue
    }
}

public struct CollectionFieldSpec: Equatable, Sendable {
    public let path: [String]
    public let label: String
    public let help: String
    public let kind: SettingKind
    public let required: Bool
    public let defaultValue: SettingValue
    public init(path: [String], label: String, help: String, kind: SettingKind, required: Bool,
                defaultValue: SettingValue) {
        self.path = path
        self.label = label
        self.help = help
        self.kind = kind
        self.required = required
        self.defaultValue = defaultValue
    }
}

public enum CollectionValue: Equatable, Sendable {
    case list([SettingValue])
    case rows([CollectionRow])
    case advanced(String)
}

public struct CollectionRow: Equatable, Sendable {
    public var fields: [String: SettingValue]
    public var sourceIndex: Int?
    public init(fields: [String: SettingValue], sourceIndex: Int? = nil) {
        self.fields = fields
        self.sourceIndex = sourceIndex
    }
}
