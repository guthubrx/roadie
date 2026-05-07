import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore

public enum Direction: String, Sendable {
    case left
    case right
    case up
    case down
}

public struct WindowCommandResult: Equatable, Sendable {
    public var message: String
    public var changed: Bool

    public init(message: String, changed: Bool) {
        self.message = message
        self.changed = changed
    }
}

public struct WindowCommandService {
    private let service: SnapshotService
    private let stageStore: StageStore
    private let resizeStep: CGFloat

    public init(
        service: SnapshotService = SnapshotService(),
        stageStore: StageStore = StageStore(),
        resizeStep: CGFloat = 80
    ) {
        self.service = service
        self.stageStore = stageStore
        self.resizeStep = resizeStep
    }

    public func focus(_ direction: Direction) -> WindowCommandResult {
        let snapshot = service.snapshot()
        guard let pair = activeAndNeighbor(in: snapshot, direction: direction) else {
            return WindowCommandResult(message: "no neighbor \(direction.rawValue)", changed: false)
        }
        let ok = service.focus(pair.neighbor.window)
        return WindowCommandResult(message: ok ? "focused \(pair.neighbor.window.id)" : "focus failed", changed: ok)
    }

    public func move(_ direction: Direction) -> WindowCommandResult {
        let snapshot = service.snapshot()
        guard let pair = activeAndNeighbor(in: snapshot, direction: direction),
              let scope = pair.active.scope
        else {
            return WindowCommandResult(message: "no neighbor \(direction.rawValue)", changed: false)
        }
        service.removeLayoutIntent(scope: scope)
        let ordered = swappedWindowIDs(
            in: snapshot,
            scope: scope,
            activeID: pair.active.window.id,
            neighborID: pair.neighbor.window.id
        )
        let plan = service.applyPlan(
            from: snapshot,
            scope: scope,
            orderedWindowIDs: ordered
        )
        let result = service.apply(plan)
        if result.attempted > 0 && result.failed < result.attempted {
            persistIntentAfterCommand(
                from: snapshot,
                scope: scope,
                orderedWindowIDs: ordered,
                plan: plan,
                result: result
            )
        }
        _ = service.focus(pair.active.window)
        return WindowCommandResult(
            message: "move \(direction.rawValue): attempted=\(result.attempted) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
            changed: result.attempted > 0 && result.failed < result.attempted
        )
    }

    public func warp(_ direction: Direction) -> WindowCommandResult {
        let snapshot = service.snapshot()
        guard let pair = activeAndNeighbor(in: snapshot, direction: direction),
              let scope = pair.active.scope
        else {
            return WindowCommandResult(message: "no neighbor \(direction.rawValue)", changed: false)
        }
        service.removeLayoutIntent(scope: scope)
        guard let plan = structuralWarpPlan(
            in: snapshot,
            scope: scope,
            active: pair.active.window,
            neighbor: pair.neighbor.window,
            direction: direction
        ) else {
            return WindowCommandResult(message: "warp \(direction.rawValue): no structural change", changed: false)
        }
        let result = service.apply(plan)
        if result.attempted > 0 && result.failed < result.attempted {
            let ordered = service.orderedWindowIDs(in: scope, from: snapshot)
            persistIntentAfterCommand(
                from: snapshot,
                scope: scope,
                orderedWindowIDs: ordered,
                plan: plan,
                result: result
            )
        }
        _ = service.focus(pair.active.window)
        return WindowCommandResult(
            message: "warp \(direction.rawValue): attempted=\(result.attempted) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
            changed: result.attempted > 0 && result.failed < result.attempted
        )
    }

    public func resize(_ direction: Direction) -> WindowCommandResult {
        let snapshot = service.snapshot()
        guard let active = activeWindow(in: snapshot),
              let scope = active.scope
        else {
            return WindowCommandResult(message: "no active window", changed: false)
        }
        let frame = resizedFrame(active.window.frame.cgRect, direction: direction)
        service.removeLayoutIntent(scope: scope)
        let resizeResult = service.apply(ApplyPlan(commands: [
            ApplyCommand(window: active.window, frame: Rect(frame)),
        ]))
        guard resizeResult.attempted > 0 && resizeResult.failed < resizeResult.attempted else {
            _ = service.focus(active.window)
            return WindowCommandResult(
                message: "resize \(direction.rawValue): attempted=\(resizeResult.attempted) applied=\(resizeResult.applied) clamped=\(resizeResult.clamped) failed=\(resizeResult.failed)",
                changed: false
            )
        }

        let actualFrame = resizeResult.items.first(where: { $0.windowID == active.window.id })?.actual ?? Rect(frame)
        let updatedSnapshot = snapshotByUpdating(windowID: active.window.id, to: actualFrame, in: snapshot)
        let plan = service.applyPlan(from: updatedSnapshot, priorityWindowIDs: [active.window.id])
        let result = service.apply(plan)
        if result.failed < result.attempted {
            let ordered = service.orderedWindowIDs(in: scope, from: updatedSnapshot)
            persistIntentAfterCommand(
                from: updatedSnapshot,
                scope: scope,
                orderedWindowIDs: ordered,
                plan: plan,
                result: result
            )
        }
        _ = service.focus(active.window)
        return WindowCommandResult(
            message: "resize \(direction.rawValue): direct=\(resizeResult.applied + resizeResult.clamped) layout=\(result.attempted) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
            changed: true
        )
    }

    public func reset() -> WindowCommandResult {
        let snapshot = service.snapshot()
        guard let active = activeWindow(in: snapshot),
              let scope = active.scope,
              let display = snapshot.displays.first(where: { $0.id == scope.displayID })
        else {
            return WindowCommandResult(message: "window reset: no active window", changed: false)
        }

        service.removeLayoutIntent(scope: scope)
        let zoomed = service.reset(active.window)
        Thread.sleep(forTimeInterval: 0.08)

        let visible = display.visibleFrame.cgRect
        let intermediate = centeredFrame(
            CGRect(
                x: active.window.frame.x,
                y: active.window.frame.y,
                width: min(active.window.frame.width, visible.width * 0.6),
                height: min(active.window.frame.height, visible.height * 0.6)
            ),
            in: visible
        )
        _ = service.setFrame(intermediate, of: active.window)
        Thread.sleep(forTimeInterval: 0.08)

        let updatedSnapshot = service.snapshot()
        let result = service.apply(service.applyPlan(from: updatedSnapshot))
        _ = service.focus(active.window)
        return WindowCommandResult(
            message: "window reset: zoom=\(zoomed) attempted=\(result.attempted) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
            changed: result.failed == 0
        )
    }

    public func sendToDisplay(_ displayIndex: Int) -> WindowCommandResult {
        let snapshot = service.snapshot()
        guard let active = activeWindow(in: snapshot) else {
            return WindowCommandResult(message: "no active window", changed: false)
        }
        guard let display = snapshot.displays.first(where: { $0.index == displayIndex }) else {
            return WindowCommandResult(message: "unknown display \(displayIndex)", changed: false)
        }
        let sourceScope = active.scope
        var initialStageState = stageStore.state()
        let targetDesktopID = initialStageState.currentDesktopID(for: display.id)
        let targetActiveStageID = initialStageState.scope(displayID: display.id, desktopID: targetDesktopID).activeStageID
        let targetScopeID = StageScope(
            displayID: display.id,
            desktopID: targetDesktopID,
            stageID: targetActiveStageID
        )
        if sourceScope == targetScopeID {
            return WindowCommandResult(message: "display \(displayIndex): already on target display", changed: false)
        }

        let transferFrame = centeredFrame(active.window.frame.cgRect, in: display.visibleFrame.cgRect)
        guard service.setFrame(transferFrame, of: active.window) != nil else {
            return WindowCommandResult(message: "display \(displayIndex): initial move failed", changed: false)
        }

        var state = stageStore.state()
        for scopeIndex in state.scopes.indices {
            state.scopes[scopeIndex].remove(windowID: active.window.id)
        }
        var targetScope = state.scope(displayID: display.id, desktopID: targetDesktopID)
        let transferredWindow = WindowSnapshot(
            id: active.window.id,
            pid: active.window.pid,
            appName: active.window.appName,
            bundleID: active.window.bundleID,
            title: active.window.title,
            frame: Rect(transferFrame),
            isOnScreen: active.window.isOnScreen,
            isTileCandidate: active.window.isTileCandidate
        )
        targetScope.assign(window: transferredWindow, to: targetScope.activeStageID)
        state.update(targetScope)
        stageStore.save(state)

        if let sourceScope {
            service.removeLayoutIntent(scope: sourceScope)
        }
        service.removeLayoutIntent(scope: targetScopeID)

        let updatedSnapshot = service.snapshot()
        let result = service.apply(service.applyPlan(from: updatedSnapshot))
        if result.attempted > 0 && result.failed < result.attempted {
            persistDisplayTransferIntent(in: service.snapshot(), scopes: [sourceScope, targetScopeID].compactMap { $0 })
        }
        _ = service.focus(active.window)
        return WindowCommandResult(
            message: "display \(displayIndex): attempted=\(result.attempted) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
            changed: result.attempted > 0 && result.failed < result.attempted
        )
    }

    private func activeAndNeighbor(
        in snapshot: DaemonSnapshot,
        direction: Direction
    ) -> (active: ScopedWindowSnapshot, neighbor: ScopedWindowSnapshot)? {
        guard let active = activeWindow(in: snapshot), let scope = active.scope else { return nil }
        let candidates = snapshot.windows.filter {
            $0.scope == scope && $0.window.id != active.window.id && $0.window.isTileCandidate
        }
        guard let neighbor = candidates.min(by: { lhs, rhs in
            neighborScore(from: active.window.frame.cgRect, to: lhs.window.frame.cgRect, direction: direction)
                < neighborScore(from: active.window.frame.cgRect, to: rhs.window.frame.cgRect, direction: direction)
        }),
        neighborScore(from: active.window.frame.cgRect, to: neighbor.window.frame.cgRect, direction: direction).isFinite
        else { return nil }
        return (active, neighbor)
    }

    private func activeWindow(in snapshot: DaemonSnapshot) -> ScopedWindowSnapshot? {
        if let focusedID = service.focusedWindowID(),
           let focused = snapshot.windows.first(where: { entry in
               guard let scope = entry.scope else { return false }
               return entry.window.id == focusedID
                   && entry.window.isTileCandidate
                   && snapshot.state.activeScope(on: scope.displayID) == scope
           }) {
            return focused
        }

        for display in snapshot.displays {
            guard let scope = snapshot.state.activeScope(on: display.id),
                  let stage = snapshot.state.stage(scope: scope)
            else { continue }
            if let focusedID = stage.focusedWindowID,
               let focused = snapshot.windows.first(where: { $0.window.id == focusedID && $0.scope == scope && $0.window.isTileCandidate }) {
                return focused
            }
            if let lastID = stage.windowIDs.last,
               let last = snapshot.windows.first(where: { $0.window.id == lastID && $0.scope == scope && $0.window.isTileCandidate }) {
                return last
            }
        }

        return snapshot.windows.first { entry in
            guard let scope = entry.scope else { return false }
            return entry.window.isTileCandidate && snapshot.state.activeScope(on: scope.displayID) == scope
        }
    }

    private func structuralWarpPlan(
        in snapshot: DaemonSnapshot,
        scope: StageScope,
        active: WindowSnapshot,
        neighbor: WindowSnapshot,
        direction: Direction
    ) -> ApplyPlan? {
        guard let display = snapshot.displays.first(where: { $0.id == scope.displayID }) else { return nil }
        let scopedWindows = snapshot.windows
            .filter { $0.scope == scope && $0.window.isTileCandidate }
            .map(\.window)
        guard scopedWindows.count > 2 else {
            return service.applyPlan(
                from: snapshot,
                scope: scope,
                orderedWindowIDs: swappedWindowIDs(
                    in: snapshot,
                    scope: scope,
                    activeID: active.id,
                    neighborID: neighbor.id
                )
            )
        }

        let horizontal = direction == .left || direction == .right
        var targetGroup = scopedWindows
            .filter { isOnTargetSide($0.frame.cgRect, from: active.frame.cgRect, direction: direction) }
            .map(\.id)
        var sourceGroup = scopedWindows
            .filter { !isOnTargetSide($0.frame.cgRect, from: active.frame.cgRect, direction: direction) }
            .map(\.id)

        guard targetGroup.contains(neighbor.id), sourceGroup.contains(active.id) else { return nil }
        sourceGroup.removeAll { $0 == active.id }
        targetGroup.removeAll { $0 == active.id }

        if horizontal {
            insert(active.id, into: &targetGroup, sortedByYUsing: scopedWindows)
        } else {
            insert(active.id, into: &targetGroup, sortedByXUsing: scopedWindows)
        }
        guard !targetGroup.isEmpty, !sourceGroup.isEmpty else { return nil }

        let container = display.visibleFrame.cgRect
        let gap = CGFloat(service.innerGap())
        let targetFirst: Bool
        switch direction {
        case .left, .up: targetFirst = true
        case .right, .down: targetFirst = false
        }
        let firstGroup = targetFirst ? targetGroup : sourceGroup
        let secondGroup = targetFirst ? sourceGroup : targetGroup
        let rects = split(container, horizontally: horizontal, gap: gap, firstCount: firstGroup.count, secondCount: secondGroup.count)

        var placements: [WindowID: CGRect] = [:]
        placements.merge(planGroup(firstGroup, in: rects.first, horizontal: !horizontal, gap: gap)) { lhs, _ in lhs }
        placements.merge(planGroup(secondGroup, in: rects.second, horizontal: !horizontal, gap: gap)) { lhs, _ in lhs }

        let windowsByID = Dictionary(uniqueKeysWithValues: scopedWindows.map { ($0.id, $0) })
        let commands = placements.keys.sorted().compactMap { id -> ApplyCommand? in
            guard let window = windowsByID[id], let frame = placements[id], !framesAreClose(window.frame.cgRect, frame) else { return nil }
            return ApplyCommand(window: window, frame: Rect(frame.integral))
        }
        return commands.isEmpty ? nil : ApplyPlan(commands: commands)
    }

    private func persistIntentAfterCommand(
        from snapshot: DaemonSnapshot,
        scope: StageScope,
        orderedWindowIDs: [WindowID],
        plan: ApplyPlan,
        result: ApplyResult
    ) {
        var placements = Dictionary(uniqueKeysWithValues: snapshot.windows.compactMap { entry -> (WindowID, Rect)? in
            guard entry.scope == scope, entry.window.isTileCandidate else { return nil }
            return (entry.window.id, entry.window.frame)
        })
        for item in result.items {
            if item.status != .failed {
                placements[item.windowID] = item.actual ?? item.requested
            }
        }
        for command in plan.commands {
            if placements[command.window.id] == nil {
                placements[command.window.id] = command.frame
            }
        }
        guard Set(placements.keys) == Set(orderedWindowIDs) else { return }
        service.saveLayoutIntent(
            scope: scope,
            windowIDs: orderedWindowIDs.sorted(),
            placements: placements,
            source: .command
        )
    }

    private func snapshotByUpdating(windowID: WindowID, to frame: Rect, in snapshot: DaemonSnapshot) -> DaemonSnapshot {
        DaemonSnapshot(
            permissions: snapshot.permissions,
            displays: snapshot.displays,
            windows: snapshot.windows.map { entry in
                guard entry.window.id == windowID else { return entry }
                var window = entry.window
                window.frame = frame
                return ScopedWindowSnapshot(window: window, scope: entry.scope)
            },
            state: snapshot.state
        )
    }

    private func persistDisplayTransferIntent(in snapshot: DaemonSnapshot, scopes: [StageScope]) {
        let uniqueScopes = Set(scopes)
        for scope in uniqueScopes {
            guard let stage = snapshot.state.stage(scope: scope),
                  !stage.windowIDs.isEmpty
            else { continue }

            var placements: [WindowID: Rect] = [:]
            for entry in snapshot.windows where entry.scope == scope && entry.window.isTileCandidate {
                placements[entry.window.id] = entry.window.frame
            }
            guard Set(placements.keys) == Set(stage.windowIDs) else { continue }
            service.saveLayoutIntent(
                scope: scope,
                windowIDs: stage.windowIDs,
                placements: placements,
                source: .command
            )
        }
    }

    private func swappedWindowIDs(
        in snapshot: DaemonSnapshot,
        scope: StageScope,
        activeID: WindowID,
        neighborID: WindowID
    ) -> [WindowID] {
        service.orderedWindowIDs(in: scope, from: snapshot).map { id in
            if id == activeID { return neighborID }
            if id == neighborID { return activeID }
            return id
        }
    }

    private func isOnTargetSide(_ candidate: CGRect, from active: CGRect, direction: Direction) -> Bool {
        switch direction {
        case .left: candidate.midX < active.midX
        case .right: candidate.midX > active.midX
        case .up: candidate.midY < active.midY
        case .down: candidate.midY > active.midY
        }
    }

    private func insert(_ id: WindowID, into group: inout [WindowID], sortedByYUsing windows: [WindowSnapshot]) {
        group.append(id)
        let frames = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.frame.cgRect) })
        group.sort { lhs, rhs in (frames[lhs]?.midY ?? 0) < (frames[rhs]?.midY ?? 0) }
    }

    private func insert(_ id: WindowID, into group: inout [WindowID], sortedByXUsing windows: [WindowSnapshot]) {
        group.append(id)
        let frames = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.frame.cgRect) })
        group.sort { lhs, rhs in (frames[lhs]?.midX ?? 0) < (frames[rhs]?.midX ?? 0) }
    }

    private func split(
        _ rect: CGRect,
        horizontally: Bool,
        gap: CGFloat,
        firstCount: Int,
        secondCount: Int
    ) -> (first: CGRect, second: CGRect) {
        let total = CGFloat(firstCount + secondCount)
        let ratio = total > 0 ? CGFloat(firstCount) / total : 0.5
        if horizontally {
            let usable = max(0, rect.width - gap)
            let firstWidth = floor(usable * ratio)
            return (
                CGRect(x: rect.minX, y: rect.minY, width: firstWidth, height: rect.height),
                CGRect(x: rect.minX + firstWidth + gap, y: rect.minY, width: usable - firstWidth, height: rect.height)
            )
        }

        let usable = max(0, rect.height - gap)
        let firstHeight = floor(usable * ratio)
        return (
            CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: firstHeight),
            CGRect(x: rect.minX, y: rect.minY + firstHeight + gap, width: rect.width, height: usable - firstHeight)
        )
    }

    private func planGroup(_ windowIDs: [WindowID], in rect: CGRect, horizontal: Bool, gap: CGFloat) -> [WindowID: CGRect] {
        guard let first = windowIDs.first else { return [:] }
        guard windowIDs.count > 1 else { return [first: rect.integral] }

        let parts = split(rect, horizontally: horizontal, gap: gap, firstCount: 1, secondCount: windowIDs.count - 1)
        var placements = [first: parts.first.integral]
        placements.merge(planGroup(Array(windowIDs.dropFirst()), in: parts.second, horizontal: !horizontal, gap: gap)) { lhs, _ in lhs }
        return placements
    }

    private func framesAreClose(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 1
            && abs(lhs.minY - rhs.minY) <= 1
            && abs(lhs.width - rhs.width) <= 1
            && abs(lhs.height - rhs.height) <= 1
    }

    private func neighborScore(from active: CGRect, to candidate: CGRect, direction: Direction) -> CGFloat {
        let dx = candidate.midX - active.midX
        let dy = candidate.midY - active.midY
        switch direction {
        case .left where dx < -1:
            return abs(dx) + abs(dy) * 0.35
        case .right where dx > 1:
            return abs(dx) + abs(dy) * 0.35
        case .up where dy < -1:
            return abs(dy) + abs(dx) * 0.35
        case .down where dy > 1:
            return abs(dy) + abs(dx) * 0.35
        default:
            return .infinity
        }
    }

    private func resizedFrame(_ frame: CGRect, direction: Direction) -> CGRect {
        switch direction {
        case .left:
            return CGRect(x: frame.minX - resizeStep, y: frame.minY, width: frame.width + resizeStep, height: frame.height)
        case .right:
            return CGRect(x: frame.minX, y: frame.minY, width: frame.width + resizeStep, height: frame.height)
        case .up:
            return CGRect(x: frame.minX, y: frame.minY - resizeStep, width: frame.width, height: frame.height + resizeStep)
        case .down:
            return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height + resizeStep)
        }
    }

    private func centeredFrame(_ frame: CGRect, in container: CGRect) -> CGRect {
        let width = min(frame.width, container.width)
        let height = min(frame.height, container.height)
        return CGRect(
            x: container.midX - width / 2,
            y: container.midY - height / 2,
            width: width,
            height: height
        ).integral
    }

}
