import Foundation

public struct DisplayID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "DisplayID must not be empty")
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

public struct DesktopID: RawRepresentable, Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: Int

    public init(rawValue: Int) {
        precondition(rawValue > 0, "DesktopID must be positive")
        self.rawValue = rawValue
    }

    public static func < (lhs: DesktopID, rhs: DesktopID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String { String(rawValue) }
}

public struct StageID: RawRepresentable, Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "StageID must not be empty")
        self.rawValue = rawValue
    }

    public static func < (lhs: StageID, rhs: StageID) -> Bool {
        lhs.rawValue.localizedStandardCompare(rhs.rawValue) == .orderedAscending
    }

    public var description: String { rawValue }
}

public struct WindowID: RawRepresentable, Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        precondition(rawValue > 0, "WindowID must be positive")
        self.rawValue = rawValue
    }

    public static func < (lhs: WindowID, rhs: WindowID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String { String(rawValue) }
}

public struct StageScope: Hashable, Codable, Sendable, CustomStringConvertible {
    public let displayID: DisplayID
    public let desktopID: DesktopID
    public let stageID: StageID

    public init(displayID: DisplayID, desktopID: DesktopID, stageID: StageID) {
        self.displayID = displayID
        self.desktopID = desktopID
        self.stageID = stageID
    }

    public var description: String {
        "\(displayID.rawValue)/\(desktopID.rawValue)/\(stageID.rawValue)"
    }
}
