import Foundation

public enum PerformanceInteractionType: String, Codable, CaseIterable, Sendable {
    case stageSwitch = "stage_switch"
    case desktopSwitch = "desktop_switch"
    case displayFocus = "display_focus"
    case directionalFocus = "directional_focus"
    case altTabActivation = "alt_tab_activation"
    case borderRefresh = "border_refresh"
    case railAction = "rail_action"
    case layoutTick = "layout_tick"
}

public enum PerformanceInteractionResult: String, Codable, Sendable {
    case success
    case partial
    case noOp = "no_op"
    case failed
}

public enum PerformanceInteractionSource: String, Codable, Sendable {
    case cli
    case btt
    case rail
    case focusObserver = "focus_observer"
    case maintainer
    case system
}

public enum PerformanceStepName: String, Codable, CaseIterable, Sendable {
    case snapshot
    case stateUpdate = "state_update"
    case hidePrevious = "hide_previous"
    case restoreTarget = "restore_target"
    case layoutApply = "layout_apply"
    case focus
    case secondaryWork = "secondary_work"
    case total
}

public enum PerformanceStepStatus: String, Codable, Sendable {
    case success
    case skipped
    case failed
}

public struct PerformanceTargetContext: Equatable, Codable, Sendable {
    public var displayID: String?
    public var desktopID: Int?
    public var stageID: String?
    public var windowID: UInt32?
    public var sourceDisplayID: String?
    public var sourceDesktopID: Int?
    public var sourceStageID: String?

    public init(
        displayID: String? = nil,
        desktopID: Int? = nil,
        stageID: String? = nil,
        windowID: UInt32? = nil,
        sourceDisplayID: String? = nil,
        sourceDesktopID: Int? = nil,
        sourceStageID: String? = nil
    ) {
        self.displayID = displayID
        self.desktopID = desktopID
        self.stageID = stageID
        self.windowID = windowID
        self.sourceDisplayID = sourceDisplayID
        self.sourceDesktopID = sourceDesktopID
        self.sourceStageID = sourceStageID
    }
}

public struct PerformanceStep: Equatable, Codable, Sendable {
    public var name: PerformanceStepName
    public var startedAt: Date
    public var durationMs: Double
    public var count: Int?
    public var status: PerformanceStepStatus

    public init(
        name: PerformanceStepName,
        startedAt: Date = Date(),
        durationMs: Double,
        count: Int? = nil,
        status: PerformanceStepStatus = .success
    ) {
        self.name = name
        self.startedAt = startedAt
        self.durationMs = max(0, durationMs)
        self.count = count
        self.status = status
    }
}

public struct PerformanceThreshold: Equatable, Codable, Sendable {
    public var interactionType: PerformanceInteractionType
    public var limitMs: Double
    public var percentileTarget: Int
    public var enabled: Bool

    public init(
        interactionType: PerformanceInteractionType,
        limitMs: Double,
        percentileTarget: Int,
        enabled: Bool = true
    ) {
        self.interactionType = interactionType
        self.limitMs = max(1, limitMs)
        self.percentileTarget = percentileTarget
        self.enabled = enabled
    }
}

public struct PerformanceThresholdBreach: Equatable, Codable, Sendable {
    public var interactionID: String
    public var interactionType: PerformanceInteractionType
    public var durationMs: Double
    public var limitMs: Double
    public var dominantStep: PerformanceStepName?
    public var message: String

    public init(
        interactionID: String,
        interactionType: PerformanceInteractionType,
        durationMs: Double,
        limitMs: Double,
        dominantStep: PerformanceStepName?,
        message: String
    ) {
        self.interactionID = interactionID
        self.interactionType = interactionType
        self.durationMs = durationMs
        self.limitMs = limitMs
        self.dominantStep = dominantStep
        self.message = message
    }
}

public struct PerformanceInteraction: Equatable, Codable, Sendable, Identifiable {
    public var id: String
    public var type: PerformanceInteractionType
    public var startedAt: Date
    public var completedAt: Date?
    public var durationMs: Double
    public var result: PerformanceInteractionResult
    public var targetContext: PerformanceTargetContext
    public var source: PerformanceInteractionSource
    public var steps: [PerformanceStep]
    public var thresholdBreach: PerformanceThresholdBreach?
    public var skippedFrameMoves: Int

    public init(
        id: String = "perf_\(UUID().uuidString)",
        type: PerformanceInteractionType,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        durationMs: Double = 0,
        result: PerformanceInteractionResult = .success,
        targetContext: PerformanceTargetContext = PerformanceTargetContext(),
        source: PerformanceInteractionSource = .cli,
        steps: [PerformanceStep] = [],
        thresholdBreach: PerformanceThresholdBreach? = nil,
        skippedFrameMoves: Int = 0
    ) {
        self.id = id
        self.type = type
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationMs = max(0, durationMs)
        self.result = result
        self.targetContext = targetContext
        self.source = source
        self.steps = steps
        self.thresholdBreach = thresholdBreach
        self.skippedFrameMoves = max(0, skippedFrameMoves)
    }
}

public struct PerformanceSummary: Equatable, Codable, Sendable {
    public var type: PerformanceInteractionType
    public var count: Int
    public var medianMs: Double
    public var p95Ms: Double
    public var slowCount: Int

    public init(type: PerformanceInteractionType, count: Int, medianMs: Double, p95Ms: Double, slowCount: Int) {
        self.type = type
        self.count = count
        self.medianMs = medianMs
        self.p95Ms = p95Ms
        self.slowCount = slowCount
    }
}

public struct PerformanceRetention: Equatable, Codable, Sendable {
    public var storagePath: String
    public var maxInteractions: Int
    public var rotation: String

    public init(storagePath: String, maxInteractions: Int = 100, rotation: String = "fifo") {
        self.storagePath = storagePath
        self.maxInteractions = max(1, maxInteractions)
        self.rotation = rotation
    }
}

public struct FrameEquivalencePolicy: Equatable, Codable, Sendable {
    public var defaultTolerancePoints: Double
    public var unit: String

    public init(defaultTolerancePoints: Double = 2, unit: String = "macos_point") {
        self.defaultTolerancePoints = max(0, defaultTolerancePoints)
        self.unit = unit
    }
}

public struct PerformanceSnapshot: Equatable, Codable, Sendable {
    public var generatedAt: Date
    public var retention: PerformanceRetention
    public var recentInteractions: [PerformanceInteraction]
    public var summaryByType: [PerformanceSummary]
    public var slowestRecent: [PerformanceInteraction]
    public var thresholdBreaches: [PerformanceThresholdBreach]
    public var thresholds: [PerformanceThreshold]
    public var frameEquivalence: FrameEquivalencePolicy

    public init(
        generatedAt: Date = Date(),
        retention: PerformanceRetention,
        recentInteractions: [PerformanceInteraction] = [],
        summaryByType: [PerformanceSummary] = [],
        slowestRecent: [PerformanceInteraction] = [],
        thresholdBreaches: [PerformanceThresholdBreach] = [],
        thresholds: [PerformanceThreshold] = [],
        frameEquivalence: FrameEquivalencePolicy = FrameEquivalencePolicy()
    ) {
        self.generatedAt = generatedAt
        self.retention = retention
        self.recentInteractions = recentInteractions
        self.summaryByType = summaryByType
        self.slowestRecent = slowestRecent
        self.thresholdBreaches = thresholdBreaches
        self.thresholds = thresholds
        self.frameEquivalence = frameEquivalence
    }
}

public extension Array where Element == PerformanceInteraction {
    func performanceSummaries(thresholds: [PerformanceThreshold]) -> [PerformanceSummary] {
        let thresholdsByType = Dictionary(uniqueKeysWithValues: thresholds.map { ($0.interactionType, $0) })
        return Dictionary(grouping: self, by: \.type).map { type, interactions in
            let durations = interactions.map(\.durationMs).sorted()
            let threshold = thresholdsByType[type]
            let slowCount = interactions.filter { interaction in
                if interaction.thresholdBreach != nil { return true }
                guard let threshold, threshold.enabled else { return false }
                return interaction.durationMs > threshold.limitMs
            }.count
            return PerformanceSummary(
                type: type,
                count: interactions.count,
                medianMs: durations.percentile(50),
                p95Ms: durations.percentile(95),
                slowCount: slowCount
            )
        }.sorted { $0.type.rawValue < $1.type.rawValue }
    }
}

private extension Array where Element == Double {
    func percentile(_ percentile: Double) -> Double {
        guard !isEmpty else { return 0 }
        let clamped = Swift.min(100, Swift.max(0, percentile))
        let index = Int((clamped / 100 * Double(count - 1)).rounded())
        return self[Swift.min(Swift.max(0, index), count - 1)]
    }
}
