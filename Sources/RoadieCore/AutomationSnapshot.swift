import Foundation

public struct RoadieStateSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var activeDisplayId: String?
    public var activeDesktopId: String?
    public var activeStageId: String?
    public var focusedWindowId: String?
    public var displays: [AutomationDisplaySnapshot]
    public var desktops: [AutomationDesktopSnapshot]
    public var stages: [AutomationStageSnapshot]
    public var windows: [AutomationWindowSnapshot]
    public var groups: [AutomationGroupSnapshot]
    public var rules: [AutomationRuleSnapshot]

    public init(
        schemaVersion: Int = 1,
        generatedAt: Date = Date(),
        activeDisplayId: String? = nil,
        activeDesktopId: String? = nil,
        activeStageId: String? = nil,
        focusedWindowId: String? = nil,
        displays: [AutomationDisplaySnapshot] = [],
        desktops: [AutomationDesktopSnapshot] = [],
        stages: [AutomationStageSnapshot] = [],
        windows: [AutomationWindowSnapshot] = [],
        groups: [AutomationGroupSnapshot] = [],
        rules: [AutomationRuleSnapshot] = []
    ) {
        precondition(schemaVersion > 0, "schemaVersion must be positive")
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.activeDisplayId = activeDisplayId
        self.activeDesktopId = activeDesktopId
        self.activeStageId = activeStageId
        self.focusedWindowId = focusedWindowId
        self.displays = displays
        self.desktops = desktops
        self.stages = stages
        self.windows = windows
        self.groups = groups
        self.rules = rules
    }
}

public struct AutomationDisplaySnapshot: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var frame: Rect
    public var activeDesktopId: String?

    public init(id: String, name: String, frame: Rect, activeDesktopId: String? = nil) {
        self.id = id
        self.name = name
        self.frame = frame
        self.activeDesktopId = activeDesktopId
    }
}

public struct AutomationDesktopSnapshot: Codable, Equatable, Sendable {
    public var id: String
    public var displayId: String
    public var label: String?
    public var activeStageId: String?

    public init(id: String, displayId: String, label: String? = nil, activeStageId: String? = nil) {
        self.id = id
        self.displayId = displayId
        self.label = label
        self.activeStageId = activeStageId
    }
}

public struct AutomationStageSnapshot: Codable, Equatable, Sendable {
    public var id: String
    public var desktopId: String
    public var name: String
    public var mode: String
    public var windowIds: [String]
    public var focusedWindowId: String?

    public init(
        id: String,
        desktopId: String,
        name: String,
        mode: String,
        windowIds: [String] = [],
        focusedWindowId: String? = nil
    ) {
        self.id = id
        self.desktopId = desktopId
        self.name = name
        self.mode = mode
        self.windowIds = windowIds
        self.focusedWindowId = focusedWindowId
    }
}

public enum WindowPresentationState: String, Codable, Equatable, Sendable {
    case normal
    case maximized
    case nativeFullscreen
}

public struct AutomationWindowSnapshot: Codable, Equatable, Sendable {
    public var id: String
    public var app: String
    public var title: String
    public var displayId: String?
    public var desktopId: String?
    public var stageId: String?
    public var frame: Rect?
    public var isFocused: Bool
    public var isFloating: Bool
    public var presentationState: WindowPresentationState

    public init(
        id: String,
        app: String,
        title: String,
        displayId: String? = nil,
        desktopId: String? = nil,
        stageId: String? = nil,
        frame: Rect? = nil,
        isFocused: Bool = false,
        isFloating: Bool = false,
        presentationState: WindowPresentationState = .normal
    ) {
        self.id = id
        self.app = app
        self.title = title
        self.displayId = displayId
        self.desktopId = desktopId
        self.stageId = stageId
        self.frame = frame
        self.isFocused = isFocused
        self.isFloating = isFloating
        self.presentationState = presentationState
    }

    enum CodingKeys: String, CodingKey {
        case id, app, title, displayId, desktopId, stageId, frame, isFocused, isFloating, presentationState
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.app = try c.decode(String.self, forKey: .app)
        self.title = try c.decode(String.self, forKey: .title)
        self.displayId = try c.decodeIfPresent(String.self, forKey: .displayId)
        self.desktopId = try c.decodeIfPresent(String.self, forKey: .desktopId)
        self.stageId = try c.decodeIfPresent(String.self, forKey: .stageId)
        self.frame = try c.decodeIfPresent(Rect.self, forKey: .frame)
        self.isFocused = try c.decodeIfPresent(Bool.self, forKey: .isFocused) ?? false
        self.isFloating = try c.decodeIfPresent(Bool.self, forKey: .isFloating) ?? false
        self.presentationState = try c.decodeIfPresent(WindowPresentationState.self, forKey: .presentationState) ?? .normal
    }
}

public struct AutomationGroupSnapshot: Codable, Equatable, Sendable {
    public var id: String
    public var stageId: String
    public var memberIds: [String]
    public var activeMemberId: String?
    public var presentation: String

    public init(id: String, stageId: String, memberIds: [String], activeMemberId: String? = nil, presentation: String = "stack") {
        self.id = id
        self.stageId = stageId
        self.memberIds = memberIds
        self.activeMemberId = activeMemberId
        self.presentation = presentation
    }
}

public struct AutomationRuleSnapshot: Codable, Equatable, Sendable {
    public var id: String
    public var enabled: Bool
    public var priority: Int
    public var description: String?

    public init(id: String, enabled: Bool = true, priority: Int, description: String? = nil) {
        self.id = id
        self.enabled = enabled
        self.priority = priority
        self.description = description
    }
}
