import Foundation
import RoadieCore

public struct MaintenanceTick: Equatable, Codable, Sendable {
    public var commands: Int
    public var applied: Int
    public var clamped: Int
    public var failed: Int
    public var accessibilityDenied: Bool
    public var manualResizeDetected: Bool

    public init(
        commands: Int,
        applied: Int,
        clamped: Int,
        failed: Int,
        accessibilityDenied: Bool = false,
        manualResizeDetected: Bool = false
    ) {
        self.commands = commands
        self.applied = applied
        self.clamped = clamped
        self.failed = failed
        self.accessibilityDenied = accessibilityDenied
        self.manualResizeDetected = manualResizeDetected
    }
}

public final class LayoutMaintainer {
    private let service: SnapshotService
    private let intervalSeconds: TimeInterval
    private var clampedFrames: [UInt32: ClampedFrame] = [:]
    private var lastObservedFrames: [UInt32: Rect]?
    private var priorityWindowIDs: Set<WindowID> = []

    public init(service: SnapshotService = SnapshotService(), intervalSeconds: TimeInterval = 0.5) {
        self.service = service
        self.intervalSeconds = intervalSeconds
    }

    public func tick() -> MaintenanceTick {
        let snapshot = service.snapshot()
        guard snapshot.permissions.accessibilityTrusted else {
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0, accessibilityDenied: true)
        }
        let observedFrames = scopedFrames(in: snapshot)
        let changedWindowIDs = changedWindows(in: observedFrames)
        if !changedWindowIDs.isEmpty {
            priorityWindowIDs = changedWindowIDs
            lastObservedFrames = observedFrames
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0, manualResizeDetected: true)
        }
        lastObservedFrames = observedFrames

        let plan = suppressKnownClamps(in: service.applyPlan(from: snapshot, priorityWindowIDs: priorityWindowIDs))
        guard !plan.commands.isEmpty else {
            return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
        }
        let result = service.apply(plan)
        record(result)
        lastObservedFrames = framesAfterApplying(result, fallback: observedFrames)
        return MaintenanceTick(
            commands: plan.commands.count,
            applied: result.applied,
            clamped: result.clamped,
            failed: result.failed
        )
    }

    public func run(maxTicks: Int? = nil, onTick: (MaintenanceTick) -> Void = { _ in }) {
        var ticks = 0
        while maxTicks == nil || ticks < maxTicks! {
            let result = tick()
            onTick(result)
            ticks += 1
            Thread.sleep(forTimeInterval: intervalSeconds)
        }
    }

    private func suppressKnownClamps(in plan: ApplyPlan) -> ApplyPlan {
        ApplyPlan(commands: plan.commands.filter { command in
            guard let known = clampedFrames[command.window.id.rawValue] else { return true }
            return !known.matches(command: command)
        })
    }

    private func record(_ result: ApplyResult) {
        for item in result.items {
            switch item.status {
            case .clamped:
                if let actual = item.actual {
                    clampedFrames[item.windowID.rawValue] = ClampedFrame(requested: item.requested, actual: actual)
                }
            case .applied:
                clampedFrames.removeValue(forKey: item.windowID.rawValue)
            case .failed:
                break
            }
        }
    }

    private func scopedFrames(in snapshot: DaemonSnapshot) -> [UInt32: Rect] {
        Dictionary(uniqueKeysWithValues: snapshot.windows.compactMap { entry in
            guard entry.scope != nil else { return nil }
            return (entry.window.id.rawValue, entry.window.frame)
        })
    }

    private func framesAfterApplying(_ result: ApplyResult, fallback: [UInt32: Rect]) -> [UInt32: Rect] {
        var frames = fallback
        for item in result.items {
            frames[item.windowID.rawValue] = item.actual ?? item.requested
        }
        return frames
    }

    private func changedWindows(in frames: [UInt32: Rect]) -> Set<WindowID> {
        guard let previous = lastObservedFrames else { return [] }
        var result: Set<WindowID> = []
        for (id, frame) in frames {
            guard let previousFrame = previous[id] else { continue }
            if !frame.isClose(to: previousFrame, positionTolerance: 36, sizeTolerance: 36) {
                result.insert(WindowID(rawValue: id))
            }
        }
        return result
    }
}

private struct ClampedFrame {
    var requested: Rect
    var actual: Rect

    func matches(command: ApplyCommand) -> Bool {
        requested.isClose(to: command.frame)
            && command.window.frame.isClose(to: actual)
    }
}

private extension Rect {
    func isClose(to other: Rect, positionTolerance: Double = 48, sizeTolerance: Double = 48) -> Bool {
        abs(x - other.x) <= positionTolerance
            && abs(y - other.y) <= positionTolerance
            && abs(width - other.width) <= sizeTolerance
            && abs(height - other.height) <= sizeTolerance
    }
}
