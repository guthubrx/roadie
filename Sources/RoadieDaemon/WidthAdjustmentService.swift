import Foundation
import RoadieCore

public struct WidthAdjustmentResult: Codable, Equatable, Sendable {
    public var changed: Bool
    public var message: String
    public var ratio: Double?

    public init(changed: Bool, message: String, ratio: Double? = nil) {
        self.changed = changed
        self.message = message
        self.ratio = ratio
    }
}

public struct WidthAdjustmentService {
    private let service: SnapshotService
    private let config: RoadieConfig
    private let events: EventLog

    public init(
        service: SnapshotService = SnapshotService(),
        config: RoadieConfig = (try? RoadieConfigLoader.load()) ?? RoadieConfig(),
        events: EventLog = EventLog()
    ) {
        self.service = service
        self.config = config
        self.events = events
    }

    public func apply(_ intent: WidthAdjustmentIntent) -> WidthAdjustmentResult {
        let snapshot = service.snapshot()
        events.append(RoadieEvent(type: "layout.width_adjust_requested", details: [
            "mode": intent.mode.rawValue,
            "scope": intent.scope.rawValue
        ]))
        guard let display = snapshot.displays.first,
              let scope = snapshot.state.activeScope(on: display.id),
              let stage = snapshot.state.stage(scope: scope),
              stage.mode == .bsp || stage.mode == .mutableBsp || stage.mode == .masterStack
        else {
            return WidthAdjustmentResult(changed: false, message: "width: unsupported layout")
        }

        let entries = snapshot.windows.filter { $0.scope == scope && $0.window.isTileCandidate }
        guard !entries.isEmpty else {
            return WidthAdjustmentResult(changed: false, message: "width: no active tiled window")
        }

        let currentRatio = entries.first.map { $0.window.frame.width / display.visibleFrame.width } ?? 0.5
        let ratio = targetRatio(from: intent, current: currentRatio)
        let activeID = snapshot.focusedWindowID ?? stage.focusedWindowID ?? entries.first?.window.id
        let targets = intent.scope == .allWindows ? entries : entries.filter { $0.window.id == activeID }
        guard !targets.isEmpty else {
            return WidthAdjustmentResult(changed: false, message: "width: no target window")
        }

        let commands = targets.map { entry in
            var frame = entry.window.frame
            frame.width = display.visibleFrame.width * ratio
            frame.x = max(display.visibleFrame.x, min(frame.x, display.visibleFrame.x + display.visibleFrame.width - frame.width))
            return ApplyCommand(window: entry.window, frame: frame)
        }
        let result = service.apply(ApplyPlan(commands: commands))
        events.append(RoadieEvent(type: result.failed < result.attempted ? "layout.width_adjust_applied" : "layout.width_adjust_rejected", details: [
            "ratio": String(format: "%.4f", ratio),
            "applied": String(result.applied),
            "failed": String(result.failed)
        ]))
        return WidthAdjustmentResult(
            changed: result.failed < result.attempted,
            message: "width: ratio=\(String(format: "%.2f", ratio)) applied=\(result.applied) failed=\(result.failed)",
            ratio: ratio
        )
    }

    private func targetRatio(from intent: WidthAdjustmentIntent, current: Double) -> Double {
        let minRatio = config.widthAdjustment.minimumRatio
        let maxRatio = config.widthAdjustment.maximumRatio
        let raw: Double
        switch intent.mode {
        case .explicitRatio:
            raw = intent.targetRatio ?? current
        case .nudge:
            raw = current + (intent.delta ?? config.widthAdjustment.nudgeStep)
        case .presetNext:
            raw = config.widthAdjustment.presets.first(where: { $0 > current + 0.01 }) ?? config.widthAdjustment.presets.last ?? current
        case .presetPrevious:
            raw = config.widthAdjustment.presets.reversed().first(where: { $0 < current - 0.01 }) ?? config.widthAdjustment.presets.first ?? current
        }
        return min(max(raw, minRatio), maxRatio)
    }
}
