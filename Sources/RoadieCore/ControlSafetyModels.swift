import Foundation

public enum DaemonStatus: String, Codable, Sendable, Equatable {
    case running
    case stopped
    case degraded
    case unknown
}

public enum ConfigStatus: String, Codable, Sendable, Equatable {
    case valid
    case reloadPending
    case reloadFailed
    case fallback
}

public struct ControlCenterState: Codable, Equatable, Sendable {
    public var daemonStatus: DaemonStatus
    public var configPath: String?
    public var configStatus: ConfigStatus
    public var activeDesktop: String?
    public var activeStage: String?
    public var windowCount: Int
    public var lastError: String?
    public var lastReloadAt: Date?
    public var actions: ControlCenterActions

    public init(
        daemonStatus: DaemonStatus = .unknown,
        configPath: String? = nil,
        configStatus: ConfigStatus = .valid,
        activeDesktop: String? = nil,
        activeStage: String? = nil,
        windowCount: Int = 0,
        lastError: String? = nil,
        lastReloadAt: Date? = nil,
        actions: ControlCenterActions = ControlCenterActions()
    ) {
        self.daemonStatus = daemonStatus
        self.configPath = configPath
        self.configStatus = configStatus
        self.activeDesktop = activeDesktop
        self.activeStage = activeStage
        self.windowCount = windowCount
        self.lastError = lastError
        self.lastReloadAt = lastReloadAt
        self.actions = actions
    }
}

public struct ControlCenterActions: Codable, Equatable, Sendable {
    public var canReloadConfig: Bool
    public var canReapplyLayout: Bool
    public var canRevealConfig: Bool
    public var canRevealState: Bool
    public var canQuitSafely: Bool

    public init(
        canReloadConfig: Bool = true,
        canReapplyLayout: Bool = true,
        canRevealConfig: Bool = true,
        canRevealState: Bool = true,
        canQuitSafely: Bool = true
    ) {
        self.canReloadConfig = canReloadConfig
        self.canReapplyLayout = canReapplyLayout
        self.canRevealConfig = canRevealConfig
        self.canRevealState = canRevealState
        self.canQuitSafely = canQuitSafely
    }
}

public enum ConfigReloadValidation: String, Codable, Sendable, Equatable {
    case success
    case failed
    case skipped
}

public struct ConfigReloadState: Codable, Equatable, Sendable {
    public var activePath: String?
    public var activeVersion: String?
    public var pendingPath: String?
    public var lastValidation: ConfigReloadValidation
    public var lastError: String?
    public var lastAttemptAt: Date?
    public var lastAppliedAt: Date?

    public init(
        activePath: String? = nil,
        activeVersion: String? = nil,
        pendingPath: String? = nil,
        lastValidation: ConfigReloadValidation = .skipped,
        lastError: String? = nil,
        lastAttemptAt: Date? = nil,
        lastAppliedAt: Date? = nil
    ) {
        self.activePath = activePath
        self.activeVersion = activeVersion
        self.pendingPath = pendingPath
        self.lastValidation = lastValidation
        self.lastError = lastError
        self.lastAttemptAt = lastAttemptAt
        self.lastAppliedAt = lastAppliedAt
    }
}

public struct RestoreSafetySnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var createdAt: Date
    public var daemonPID: Int32?
    public var windows: [RestoreWindowState]
    public var activeDisplayID: String?
    public var activeDesktop: String?
    public var activeStage: String?

    public init(
        schemaVersion: Int = 1,
        createdAt: Date = Date(),
        daemonPID: Int32? = nil,
        windows: [RestoreWindowState] = [],
        activeDisplayID: String? = nil,
        activeDesktop: String? = nil,
        activeStage: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.daemonPID = daemonPID
        self.windows = windows
        self.activeDisplayID = activeDisplayID
        self.activeDesktop = activeDesktop
        self.activeStage = activeStage
    }
}

public struct RestoreWindowState: Codable, Equatable, Sendable {
    public var windowID: UInt32?
    public var identity: WindowIdentityV2
    public var frame: Rect
    public var visibleFrame: Rect
    public var wasManaged: Bool
    public var wasHiddenByRoadie: Bool
    public var stageScope: String?
    public var groupID: String?

    public init(
        windowID: UInt32? = nil,
        identity: WindowIdentityV2,
        frame: Rect,
        visibleFrame: Rect,
        wasManaged: Bool = true,
        wasHiddenByRoadie: Bool = false,
        stageScope: String? = nil,
        groupID: String? = nil
    ) {
        self.windowID = windowID
        self.identity = identity
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.wasManaged = wasManaged
        self.wasHiddenByRoadie = wasHiddenByRoadie
        self.stageScope = stageScope
        self.groupID = groupID
    }
}

public struct WindowIdentityV2: Codable, Equatable, Hashable, Sendable {
    public var bundleID: String?
    public var appName: String
    public var title: String
    public var role: String?
    public var subrole: String?
    public var pidHint: Int32?
    public var windowIDHint: UInt32?
    public var createdAt: Date?

    public init(
        bundleID: String? = nil,
        appName: String,
        title: String,
        role: String? = nil,
        subrole: String? = nil,
        pidHint: Int32? = nil,
        windowIDHint: UInt32? = nil,
        createdAt: Date? = nil
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.role = role
        self.subrole = subrole
        self.pidHint = pidHint
        self.windowIDHint = windowIDHint
        self.createdAt = createdAt
    }
}

public enum TransientWindowReason: String, Codable, Sendable, Equatable {
    case sheet
    case dialog
    case popover
    case menu
    case openSavePanel
    case unknownTransient
}

public struct TransientWindowState: Codable, Equatable, Sendable {
    public var isActive: Bool
    public var reason: TransientWindowReason?
    public var ownerBundleID: String?
    public var recoverable: Bool
    public var frame: Rect?
    public var detectedAt: Date?

    public init(
        isActive: Bool = false,
        reason: TransientWindowReason? = nil,
        ownerBundleID: String? = nil,
        recoverable: Bool = false,
        frame: Rect? = nil,
        detectedAt: Date? = nil
    ) {
        self.isActive = isActive
        self.reason = reason
        self.ownerBundleID = ownerBundleID
        self.recoverable = recoverable
        self.frame = frame
        self.detectedAt = detectedAt
    }
}

public enum WidthAdjustmentScope: String, Codable, Sendable, Equatable {
    case activeWindow
    case activeRoot
    case allWindows
}

public enum WidthAdjustmentMode: String, Codable, Sendable, Equatable {
    case presetNext
    case presetPrevious
    case nudge
    case explicitRatio
}

public struct WidthAdjustmentIntent: Codable, Equatable, Sendable {
    public var scope: WidthAdjustmentScope
    public var mode: WidthAdjustmentMode
    public var delta: Double?
    public var targetRatio: Double?
    public var createdAt: Date

    public init(
        scope: WidthAdjustmentScope,
        mode: WidthAdjustmentMode,
        delta: Double? = nil,
        targetRatio: Double? = nil,
        createdAt: Date = Date()
    ) {
        self.scope = scope
        self.mode = mode
        self.delta = delta
        self.targetRatio = targetRatio
        self.createdAt = createdAt
    }
}
