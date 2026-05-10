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
        guard let display = context.snapshot.displays.first(where: { $0.id == context.scope.displayID }) else {
            return LayoutCommandResult(message: "layout split: no active display", changed: false)
        }
        service.removeLayoutIntent(scope: context.scope)
        let ordered = service.orderedWindowIDs(in: context.scope, from: context.snapshot)
        let placements = linearPlacements(
            ordered,
            in: display.visibleFrame.cgRect,
            horizontal: axis == "horizontal",
            gap: CGFloat(service.innerGap())
        )
        let windowsByID = Dictionary(uniqueKeysWithValues: context.snapshot.windows.compactMap { entry -> (WindowID, WindowSnapshot)? in
            guard entry.scope == context.scope, entry.window.isTileCandidate else { return nil }
            return (entry.window.id, entry.window)
        })
        let commands = ordered.compactMap { id -> ApplyCommand? in
            guard let window = windowsByID[id], let frame = placements[id], !framesAreClose(window.frame.cgRect, frame) else { return nil }
            return ApplyCommand(window: window, frame: Rect(frame.integral))
        }
        let plan = ApplyPlan(commands: commands)
        let result = service.apply(plan)
        persist(scope: context.scope, ordered: ordered, snapshot: context.snapshot, result: result)
        emit(command: "layout.split", changed: result.failed < result.attempted || plan.commands.isEmpty)
        return LayoutCommandResult(
            message: "layout split \(axis): commands=\(plan.commands.count) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
            changed: result.failed < result.attempted || plan.commands.isEmpty
        )
    }

    public func toggleSplit(_ direction: Direction? = nil) -> LayoutCommandResult {
        guard let context = activeContext() else {
            return LayoutCommandResult(message: "layout toggle-split: no active scope", changed: false)
        }
        guard context.stage.mode == .mutableBsp else {
            return LayoutCommandResult(message: "layout toggle-split: requires mutableBsp", changed: false)
        }
        guard let activeID = context.snapshot.focusedWindowID ?? context.stage.focusedWindowID ?? context.stage.windowIDs.last,
              let active = context.snapshot.windows.first(where: { $0.scope == context.scope && $0.window.id == activeID && $0.window.isTileCandidate })?.window
        else {
            return LayoutCommandResult(message: "layout toggle-split: no active window", changed: false)
        }

        let scopedWindows = context.snapshot.windows
            .filter { $0.scope == context.scope && $0.window.isTileCandidate }
            .map(\.window)
        guard let pair = toggleNeighbor(for: active, in: scopedWindows, direction: direction) else {
            return LayoutCommandResult(message: "layout toggle-split: no neighbor", changed: false)
        }

        let pairFrame = active.frame.cgRect.union(pair.window.frame.cgRect)
        let orderedPair = pair.currentHorizontal
            ? [active, pair.window].sorted { $0.frame.cgRect.midX < $1.frame.cgRect.midX }
            : [active, pair.window].sorted { $0.frame.cgRect.midY < $1.frame.cgRect.midY }
        let targetHorizontal = !pair.currentHorizontal
        let placements = linearPlacements(
            orderedPair.map(\.id),
            in: pairFrame,
            horizontal: targetHorizontal,
            gap: CGFloat(service.innerGap())
        )
        let commands = orderedPair.compactMap { window -> ApplyCommand? in
            guard let frame = placements[window.id], !framesAreClose(window.frame.cgRect, frame) else { return nil }
            return ApplyCommand(window: window, frame: Rect(frame.integral))
        }
        let plan = ApplyPlan(commands: commands)
        service.removeLayoutIntent(scope: context.scope)
        let result = service.apply(plan)
        let ordered = service.orderedWindowIDs(in: context.scope, from: context.snapshot)
        persist(scope: context.scope, ordered: ordered, snapshot: context.snapshot, result: result)
        emit(command: "layout.toggle_split", changed: result.failed < result.attempted || plan.commands.isEmpty)
        let axis = targetHorizontal ? "horizontal" : "vertical"
        return LayoutCommandResult(
            message: "layout toggle-split \(axis): commands=\(plan.commands.count) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
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

    private func toggleNeighbor(
        for active: WindowSnapshot,
        in windows: [WindowSnapshot],
        direction: Direction?
    ) -> (window: WindowSnapshot, currentHorizontal: Bool)? {
        let activeFrame = active.frame.cgRect
        let scored = windows.compactMap { candidate -> (window: WindowSnapshot, currentHorizontal: Bool, score: CGFloat)? in
            guard candidate.id != active.id else { return nil }
            let candidateFrame = candidate.frame.cgRect
            if let direction, !isOnSide(candidateFrame, from: activeFrame, direction: direction) {
                return nil
            }

            let horizontalOverlap = overlapLength(activeFrame.minY...activeFrame.maxY, candidateFrame.minY...candidateFrame.maxY)
            let verticalOverlap = overlapLength(activeFrame.minX...activeFrame.maxX, candidateFrame.minX...candidateFrame.maxX)
            let horizontalScore = horizontalOverlap > 1
                ? rangeGap(activeFrame.minX...activeFrame.maxX, candidateFrame.minX...candidateFrame.maxX)
                    + abs(activeFrame.midY - candidateFrame.midY) * 0.1
                    - horizontalOverlap * 0.01
                : CGFloat.infinity
            let verticalScore = verticalOverlap > 1
                ? rangeGap(activeFrame.minY...activeFrame.maxY, candidateFrame.minY...candidateFrame.maxY)
                    + abs(activeFrame.midX - candidateFrame.midX) * 0.1
                    - verticalOverlap * 0.01
                : CGFloat.infinity

            if horizontalScore <= verticalScore, horizontalScore.isFinite {
                return (candidate, true, horizontalScore)
            }
            if verticalScore.isFinite {
                return (candidate, false, verticalScore)
            }
            return nil
        }
        return scored.min { lhs, rhs in
            if abs(lhs.score - rhs.score) > 0.001 { return lhs.score < rhs.score }
            return lhs.window.id.rawValue < rhs.window.id.rawValue
        }.map { ($0.window, $0.currentHorizontal) }
    }

    private func isOnSide(_ candidate: CGRect, from active: CGRect, direction: Direction) -> Bool {
        switch direction {
        case .left: candidate.midX < active.midX
        case .right: candidate.midX > active.midX
        case .up: candidate.midY < active.midY
        case .down: candidate.midY > active.midY
        }
    }

    private func overlapLength(_ lhs: ClosedRange<CGFloat>, _ rhs: ClosedRange<CGFloat>) -> CGFloat {
        max(0, min(lhs.upperBound, rhs.upperBound) - max(lhs.lowerBound, rhs.lowerBound))
    }

    private func rangeGap(_ lhs: ClosedRange<CGFloat>, _ rhs: ClosedRange<CGFloat>) -> CGFloat {
        if lhs.overlaps(rhs) { return 0 }
        if lhs.upperBound < rhs.lowerBound { return rhs.lowerBound - lhs.upperBound }
        return lhs.lowerBound - rhs.upperBound
    }

    private func activeContext() -> (snapshot: DaemonSnapshot, scope: StageScope, stage: RoadieStages.StageState)? {
        let snapshot = service.snapshot()
        if let focusedID = snapshot.focusedWindowID,
           let focused = snapshot.windows.first(where: { entry in
               guard let scope = entry.scope else { return false }
               return entry.window.id == focusedID
                   && entry.window.isTileCandidate
                   && snapshot.state.activeScope(on: scope.displayID) == scope
           })?.scope,
           let stage = snapshot.state.stage(scope: focused) {
            return (snapshot, focused, stage)
        }

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

    private func linearPlacements(_ ordered: [WindowID], in rect: CGRect, horizontal: Bool, gap: CGFloat) -> [WindowID: CGRect] {
        guard !ordered.isEmpty else { return [:] }
        guard ordered.count > 1 else { return [ordered[0]: rect.integral] }

        var result: [WindowID: CGRect] = [:]
        let totalGap = gap * CGFloat(ordered.count - 1)
        if horizontal {
            let usable = max(0, rect.width - totalGap)
            let baseWidth = floor(usable / CGFloat(ordered.count))
            var x = rect.minX
            for (index, id) in ordered.enumerated() {
                let width = index == ordered.count - 1 ? max(0, rect.maxX - x) : baseWidth
                result[id] = CGRect(x: x, y: rect.minY, width: width, height: rect.height).integral
                x += width + gap
            }
            return result
        }

        let usable = max(0, rect.height - totalGap)
        let baseHeight = floor(usable / CGFloat(ordered.count))
        var y = rect.minY
        for (index, id) in ordered.enumerated() {
            let height = index == ordered.count - 1 ? max(0, rect.maxY - y) : baseHeight
            result[id] = CGRect(x: rect.minX, y: y, width: rect.width, height: height).integral
            y += height + gap
        }
        return result
    }

    private func framesAreClose(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 1
            && abs(lhs.minY - rhs.minY) <= 1
            && abs(lhs.width - rhs.width) <= 1
            && abs(lhs.height - rhs.height) <= 1
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
