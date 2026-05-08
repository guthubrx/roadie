import Foundation

public struct WindowRule: Equatable, Codable, Sendable {
    public var id: String
    public var enabled: Bool
    public var priority: Int
    public var stopProcessing: Bool
    public var match: RuleMatch
    public var action: RuleAction

    public init(
        id: String,
        enabled: Bool = true,
        priority: Int = 0,
        stopProcessing: Bool = false,
        match: RuleMatch = RuleMatch(),
        action: RuleAction = RuleAction()
    ) {
        self.id = id
        self.enabled = enabled
        self.priority = priority
        self.stopProcessing = stopProcessing
        self.match = match
        self.action = action
    }

    enum CodingKeys: String, CodingKey {
        case id
        case enabled
        case priority
        case stopProcessing = "stop_processing"
        case match
        case action
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        stopProcessing = try container.decodeIfPresent(Bool.self, forKey: .stopProcessing) ?? false
        match = try container.decodeIfPresent(RuleMatch.self, forKey: .match) ?? RuleMatch()
        action = try container.decodeIfPresent(RuleAction.self, forKey: .action) ?? RuleAction()
    }
}

public struct RuleMatch: Equatable, Codable, Sendable {
    public var app: String?
    public var appRegex: String?
    public var title: String?
    public var titleRegex: String?
    public var role: String?
    public var subrole: String?
    public var display: String?
    public var desktop: String?
    public var stage: String?
    public var isFloating: Bool?

    public init(
        app: String? = nil,
        appRegex: String? = nil,
        title: String? = nil,
        titleRegex: String? = nil,
        role: String? = nil,
        subrole: String? = nil,
        display: String? = nil,
        desktop: String? = nil,
        stage: String? = nil,
        isFloating: Bool? = nil
    ) {
        self.app = app
        self.appRegex = appRegex
        self.title = title
        self.titleRegex = titleRegex
        self.role = role
        self.subrole = subrole
        self.display = display
        self.desktop = desktop
        self.stage = stage
        self.isFloating = isFloating
    }

    enum CodingKeys: String, CodingKey {
        case app
        case appRegex = "app_regex"
        case title
        case titleRegex = "title_regex"
        case role
        case subrole
        case display
        case desktop
        case stage
        case isFloating = "is_floating"
    }
}

public struct RuleAction: Equatable, Codable, Sendable {
    public var manage: Bool?
    public var exclude: Bool?
    public var assignDesktop: String?
    public var assignStage: String?
    public var floating: Bool?
    public var layout: String?
    public var gapOverride: Int?
    public var scratchpad: String?
    public var emitEvent: Bool?

    public init(
        manage: Bool? = nil,
        exclude: Bool? = nil,
        assignDesktop: String? = nil,
        assignStage: String? = nil,
        floating: Bool? = nil,
        layout: String? = nil,
        gapOverride: Int? = nil,
        scratchpad: String? = nil,
        emitEvent: Bool? = nil
    ) {
        self.manage = manage
        self.exclude = exclude
        self.assignDesktop = assignDesktop
        self.assignStage = assignStage
        self.floating = floating
        self.layout = layout
        self.gapOverride = gapOverride
        self.scratchpad = scratchpad
        self.emitEvent = emitEvent
    }

    enum CodingKeys: String, CodingKey {
        case manage
        case exclude
        case assignDesktop = "assign_desktop"
        case assignStage = "assign_stage"
        case floating
        case layout
        case gapOverride = "gap_override"
        case scratchpad
        case emitEvent = "emit_event"
    }
}

public struct RuleEvaluation: Equatable, Codable, Sendable {
    public var ruleId: String
    public var windowId: String
    public var matched: Bool
    public var actionsApplied: [String]
    public var reason: String
    public var correlationId: String?

    public init(
        ruleId: String,
        windowId: String,
        matched: Bool,
        actionsApplied: [String] = [],
        reason: String,
        correlationId: String? = nil
    ) {
        self.ruleId = ruleId
        self.windowId = windowId
        self.matched = matched
        self.actionsApplied = actionsApplied
        self.reason = reason
        self.correlationId = correlationId
    }
}
