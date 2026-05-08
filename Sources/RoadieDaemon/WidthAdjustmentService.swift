import Foundation
import RoadieCore

public struct WidthAdjustmentResult: Codable, Equatable, Sendable {
    public var changed: Bool
    public var message: String
    public var ratio: Double?
}

public struct WidthAdjustmentService {
    private let service: SnapshotService
    private let config: RoadieConfig
    private let events: EventLog

    public init(service: SnapshotService = SnapshotService(), config: RoadieConfig = (try? RoadieConfigLoader.load()) ?? RoadieConfig(), events: EventLog = EventLog()) {
        self.service = service
        self.config = config
        self.events = events
    }

    public func apply(_ intent: WidthAdjustmentIntent) -> WidthAdjustmentResult {
        let snapshot = service.snapshot()
        events.append(event("layout.width_adjust_requested", payload: [
            "mode": .string(intent.mode.rawValue),
            "scope": .string(intent.scope.rawValue)
        ]))
        guard let display = snapshot.displays.first,
              let scope = snapshot.state.activeScope(on: display.id),
              let stage = snapshot.state.stage(scope: scope),
              stage.mode == .bsp || stage.mode == .masterStack
        else {
            events.append(event("layout.width_adjust_rejected", payload: ["reason": .string("unsupported_layout")]))
            return WidthAdjustmentResult(changed: false, message: "width: unsupported layout", ratio: nil)
        }
        let entries = snapshot.windows.filter { $0.scope == scope && $0.window.isTileCandidate }
        guard !entries.isEmpty else {
            events.append(event("layout.width_adjust_rejected", payload: ["reason": .string("no_active_tiled_window")]))
            return WidthAdjustmentResult(changed: false, message: "width: no active tiled window", ratio: nil)
        }
        let currentRatio = entries.first.map { $0.window.frame.width / display.visibleFrame.width } ?? 0.5
        let ratio = targetRatio(from: intent, current: currentRatio)
        let activeID = snapshot.focusedWindowID ?? stage.focusedWindowID ?? entries.first?.window.id
        let targets = intent.scope == .allWindows ? entries : entries.filter { $0.window.id == activeID }
        guard !targets.isEmpty else {
            events.append(event("layout.width_adjust_rejected", payload: ["reason": .string("no_target_window")]))
            return WidthAdjustmentResult(changed: false, message: "width: no target window", ratio: nil)
        }
        let commands = targets.map { entry in
            var frame = entry.window.frame
            frame.width = display.visibleFrame.width * ratio
            frame.x = max(display.visibleFrame.x, min(frame.x, display.visibleFrame.x + display.visibleFrame.width - frame.width))
            return ApplyCommand(window: entry.window, frame: frame)
        }
        let result = service.apply(ApplyPlan(commands: commands))
        var placements = Dictionary(uniqueKeysWithValues: entries.map { ($0.window.id, $0.window.frame) })
        for item in result.items where item.status != .failed {
            placements[item.windowID] = item.actual ?? item.requested
        }
        service.saveWidthAdjustmentIntent(scope: scope, windowIDs: stage.windowIDs, placements: placements, intent: intent)
        events.append(event(
            result.failed < result.attempted ? "layout.width_adjust_applied" : "layout.width_adjust_rejected",
            payload: ["ratio": .double(ratio), "applied": .int(result.applied), "failed": .int(result.failed)]
        ))
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

    private func event(_ type: String, payload: [String: AutomationPayload]) -> RoadieEventEnvelope {
        RoadieEventEnvelope(
            id: "width_\(UUID().uuidString)",
            type: type,
            scope: .layout,
            subject: AutomationSubject(kind: "layout", id: "width"),
            cause: .command,
            payload: payload
        )
    }
}
