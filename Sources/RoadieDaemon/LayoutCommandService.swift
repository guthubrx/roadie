import Foundation
import RoadieAX
import RoadieCore
import RoadieStages

public struct LayoutCommandResult: Equatable, Sendable {
    public var message: String
    public var changed: Bool

    public init(message: String, changed: Bool) {
        self.message = message
        self.changed = changed
    }
}

public struct LayoutCommandService {
    private let service: SnapshotService
    private let events: EventLog

    public init(service: SnapshotService = SnapshotService(), events: EventLog = EventLog()) {
        self.service = service
        self.events = events
    }

    public func flatten() -> LayoutCommandResult {
        guard let context = activeContext() else {
            return LayoutCommandResult(message: "layout flatten: no active scope", changed: false)
        }
        service.removeLayoutIntent(scope: context.scope)
        let ordered = service.orderedWindowIDs(in: context.scope, from: context.snapshot)
        let plan = service.applyPlan(from: context.snapshot, scope: context.scope, orderedWindowIDs: ordered)
        let result = service.apply(plan)
        emit(command: "layout.flatten", changed: result.failed < result.attempted || plan.commands.isEmpty)
        return LayoutCommandResult(
            message: "layout flatten: commands=\(plan.commands.count) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
            changed: result.failed < result.attempted || plan.commands.isEmpty
        )
    }

    public func split(_ axis: String) -> LayoutCommandResult {
        guard axis == "horizontal" || axis == "vertical" else {
            return LayoutCommandResult(message: "layout split: requires horizontal|vertical", changed: false)
        }
        guard let context = activeContext() else {
            return LayoutCommandResult(message: "layout split: no active scope", changed: false)
        }
        service.removeLayoutIntent(scope: context.scope)
        let ordered = service.orderedWindowIDs(in: context.scope, from: context.snapshot)
        let plan = service.applyPlan(from: context.snapshot, scope: context.scope, orderedWindowIDs: ordered)
        let result = service.apply(plan)
        emit(command: "layout.split", changed: result.failed < result.attempted || plan.commands.isEmpty)
        return LayoutCommandResult(
            message: "layout split \(axis): commands=\(plan.commands.count) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
            changed: result.failed < result.attempted || plan.commands.isEmpty
        )
    }

    public func insert(_ direction: Direction) -> LayoutCommandResult {
        guard let context = activeContext(),
              let activeID = context.snapshot.focusedWindowID ?? context.stage.focusedWindowID ?? context.stage.windowIDs.last
        else {
            return LayoutCommandResult(message: "layout insert: no active window", changed: false)
        }
        var ordered = service.orderedWindowIDs(in: context.scope, from: context.snapshot)
        ordered.removeAll { $0 == activeID }
        switch direction {
        case .left, .up:
            ordered.insert(activeID, at: 0)
        case .right, .down:
            ordered.append(activeID)
        }
        let plan = service.applyPlan(from: context.snapshot, scope: context.scope, orderedWindowIDs: ordered)
        let result = service.apply(plan)
        persist(scope: context.scope, ordered: ordered, snapshot: context.snapshot, result: result)
        emit(command: "layout.insert", changed: result.failed < result.attempted || plan.commands.isEmpty)
        return LayoutCommandResult(
            message: "layout insert \(direction.rawValue): commands=\(plan.commands.count) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
            changed: result.failed < result.attempted || plan.commands.isEmpty
        )
    }

    public func zoomParent() -> LayoutCommandResult {
        guard let context = activeContext(),
              let activeID = context.snapshot.focusedWindowID ?? context.stage.focusedWindowID ?? context.stage.windowIDs.last,
              let entry = context.snapshot.windows.first(where: { $0.window.id == activeID }),
              let display = context.snapshot.displays.first(where: { $0.id == context.scope.displayID })
        else {
            return LayoutCommandResult(message: "layout zoom-parent: no active window", changed: false)
        }
        let plan = ApplyPlan(commands: [ApplyCommand(window: entry.window, frame: display.visibleFrame)])
        let result = service.apply(plan)
        service.saveLayoutIntent(
            scope: context.scope,
            windowIDs: [activeID],
            placements: [activeID: result.items.first?.actual ?? display.visibleFrame],
            source: .command
        )
        emit(command: "layout.zoom-parent", changed: result.failed < result.attempted)
        return LayoutCommandResult(
            message: "layout zoom-parent: applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
            changed: result.failed < result.attempted
        )
    }

    public func join(with direction: Direction) -> LayoutCommandResult {
        insert(direction)
    }

    private func activeContext() -> (snapshot: DaemonSnapshot, scope: StageScope, stage: RoadieStages.StageState)? {
        let snapshot = service.snapshot()
        for display in snapshot.displays {
            guard let scope = snapshot.state.activeScope(on: display.id),
                  let stage = snapshot.state.stage(scope: scope)
            else { continue }
            return (snapshot, scope, stage)
        }
        return nil
    }

    private func persist(scope: StageScope, ordered: [WindowID], snapshot: DaemonSnapshot, result: ApplyResult) {
        var placements = Dictionary(uniqueKeysWithValues: snapshot.windows.compactMap { entry -> (WindowID, Rect)? in
            guard entry.scope == scope else { return nil }
            return (entry.window.id, entry.window.frame)
        })
        for item in result.items where item.status != .failed {
            placements[item.windowID] = item.actual ?? item.requested
        }
        service.saveLayoutIntent(scope: scope, windowIDs: ordered, placements: placements, source: .command)
    }

    private func emit(command: String, changed: Bool) {
        events.append(RoadieEventEnvelope(
            id: "cmd_\(UUID().uuidString)",
            type: changed ? "command.applied" : "command.failed",
            scope: .command,
            subject: AutomationSubject(kind: "command", id: command),
            cause: .command,
            payload: ["command": .string(command)]
        ))
    }
}
