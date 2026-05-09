import Foundation
import RoadieCore

public struct PerformanceRecorder: Sendable {
    public struct Session: Sendable {
        public let id: String
        public let type: PerformanceInteractionType
        public let source: PerformanceInteractionSource
        public let startedAt: Date
        public let targetContext: PerformanceTargetContext

        public init(
            id: String = "perf_\(UUID().uuidString)",
            type: PerformanceInteractionType,
            source: PerformanceInteractionSource,
            startedAt: Date,
            targetContext: PerformanceTargetContext
        ) {
            self.id = id
            self.type = type
            self.source = source
            self.startedAt = startedAt
            self.targetContext = targetContext
        }
    }

    private let store: PerformanceStore
    private let events: EventLog
    private let config: PerformanceConfig
    private let now: @Sendable () -> Date

    public init(
        store: PerformanceStore = PerformanceStore(),
        events: EventLog = EventLog(),
        config: PerformanceConfig = (try? RoadieConfigLoader.load().performance) ?? PerformanceConfig(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.events = events
        self.config = config
        self.now = now
    }

    public func start(
        _ type: PerformanceInteractionType,
        source: PerformanceInteractionSource = .cli,
        targetContext: PerformanceTargetContext = PerformanceTargetContext()
    ) -> Session {
        Session(type: type, source: source, startedAt: now(), targetContext: targetContext)
    }

    @discardableResult
    public func record(
        _ type: PerformanceInteractionType,
        source: PerformanceInteractionSource = .cli,
        targetContext: PerformanceTargetContext = PerformanceTargetContext(),
        result: PerformanceInteractionResult = .success,
        steps: [PerformanceStep] = [],
        skippedFrameMoves: Int = 0,
        durationMs explicitDurationMs: Double? = nil
    ) -> PerformanceInteraction {
        let started = now()
        let completed = now()
        let durationMs = explicitDurationMs ?? max(0, completed.timeIntervalSince(started) * 1000)
        return complete(
            Session(type: type, source: source, startedAt: started, targetContext: targetContext),
            result: result,
            steps: steps,
            skippedFrameMoves: skippedFrameMoves,
            completedAt: completed,
            durationMs: durationMs
        )
    }

    @discardableResult
    public func complete(
        _ session: Session,
        result: PerformanceInteractionResult = .success,
        steps: [PerformanceStep],
        skippedFrameMoves: Int = 0,
        completedAt: Date? = nil,
        durationMs explicitDurationMs: Double? = nil
    ) -> PerformanceInteraction {
        let completed = completedAt ?? now()
        let totalDuration = explicitDurationMs ?? max(0, completed.timeIntervalSince(session.startedAt) * 1000)
        var finalSteps = steps
        if !finalSteps.contains(where: { $0.name == .total }) {
            finalSteps.append(PerformanceStep(
                name: .total,
                startedAt: session.startedAt,
                durationMs: totalDuration,
                status: result == .failed ? .failed : .success
            ))
        }
        let breach = thresholdBreach(
            id: session.id,
            type: session.type,
            durationMs: totalDuration,
            steps: finalSteps
        )
        let interaction = PerformanceInteraction(
            id: session.id,
            type: session.type,
            startedAt: session.startedAt,
            completedAt: completed,
            durationMs: totalDuration,
            result: result,
            targetContext: session.targetContext,
            source: session.source,
            steps: finalSteps,
            thresholdBreach: breach,
            skippedFrameMoves: skippedFrameMoves
        )
        guard config.enabled else { return interaction }
        store.append(interaction)
        publish(interaction)
        if breach != nil {
            publishBreach(interaction)
        }
        return interaction
    }

    private func thresholdBreach(
        id: String,
        type: PerformanceInteractionType,
        durationMs: Double,
        steps: [PerformanceStep]
    ) -> PerformanceThresholdBreach? {
        guard let threshold = config.thresholds.first(where: { $0.interactionType == type && $0.enabled }),
              durationMs > threshold.limitMs
        else { return nil }
        let dominant = steps
            .filter { $0.name != .total }
            .max { $0.durationMs < $1.durationMs }?
            .name
        return PerformanceThresholdBreach(
            interactionID: id,
            interactionType: type,
            durationMs: durationMs,
            limitMs: threshold.limitMs,
            dominantStep: dominant,
            message: "\(type.rawValue) took \(Int(durationMs))ms over \(Int(threshold.limitMs))ms"
        )
    }

    private func publish(_ interaction: PerformanceInteraction) {
        events.append(RoadieEventEnvelope(
            id: "perf_\(UUID().uuidString)",
            type: "performance.interaction_completed",
            scope: .performance,
            subject: AutomationSubject(kind: "performance", id: interaction.id),
            cause: .system,
            payload: payload(for: interaction)
        ))
    }

    private func publishBreach(_ interaction: PerformanceInteraction) {
        events.append(RoadieEventEnvelope(
            id: "perf_\(UUID().uuidString)",
            type: "performance.threshold_breached",
            scope: .performance,
            subject: AutomationSubject(kind: "performance", id: interaction.id),
            cause: .system,
            payload: payload(for: interaction)
        ))
    }

    private func payload(for interaction: PerformanceInteraction) -> [String: AutomationPayload] {
        var payload: [String: AutomationPayload] = [
            "id": .string(interaction.id),
            "type": .string(interaction.type.rawValue),
            "source": .string(interaction.source.rawValue),
            "result": .string(interaction.result.rawValue),
            "duration_ms": .double(interaction.durationMs),
            "skipped_frame_moves": .int(interaction.skippedFrameMoves)
        ]
        if let breach = interaction.thresholdBreach {
            payload["threshold_breach"] = .object([
                "limit_ms": .double(breach.limitMs),
                "dominant_step": breach.dominantStep.map { .string($0.rawValue) } ?? .null,
                "message": .string(breach.message)
            ])
        }
        payload["target"] = .object(targetPayload(for: interaction.targetContext))
        payload["steps"] = .array(interaction.steps.map { step in
            .object([
                "name": .string(step.name.rawValue),
                "duration_ms": .double(step.durationMs),
                "status": .string(step.status.rawValue),
                "count": step.count.map { .int($0) } ?? .null
            ])
        })
        return payload
    }

    private func targetPayload(for context: PerformanceTargetContext) -> [String: AutomationPayload] {
        [
            "display_id": context.displayID.map { .string($0) } ?? .null,
            "desktop_id": context.desktopID.map { .int($0) } ?? .null,
            "stage_id": context.stageID.map { .string($0) } ?? .null,
            "window_id": context.windowID.map { .int(Int($0)) } ?? .null,
            "source_display_id": context.sourceDisplayID.map { .string($0) } ?? .null,
            "source_desktop_id": context.sourceDesktopID.map { .int($0) } ?? .null,
            "source_stage_id": context.sourceStageID.map { .string($0) } ?? .null
        ]
    }
}
