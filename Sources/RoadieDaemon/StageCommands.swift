import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore
import RoadieTiler

public struct StageCommandResult: Equatable, Sendable {
    public var message: String
    public var changed: Bool

    public init(message: String, changed: Bool) {
        self.message = message
        self.changed = changed
    }
}

public enum StageDisplayMoveTarget: Equatable, Sendable {
    case index(Int)
    case direction(Direction)
    case displayID(DisplayID)
}

public enum StageDisplayMoveStatus: String, Equatable, Sendable {
    case moved
    case noopCurrentDisplay
    case invalidTarget
    case noActiveStage
    case partialFailure
}

public struct StageCommandService {
    private let service: SnapshotService
    private let store: StageStore
    private let events: EventLog
    private let config: RoadieConfig

    public init(
        service: SnapshotService = SnapshotService(),
        store: StageStore = StageStore(),
        events: EventLog = EventLog(),
        config: RoadieConfig = (try? RoadieConfigLoader.load()) ?? RoadieConfig()
    ) {
        self.service = service
        self.store = store
        self.events = events
        self.config = config
    }

    public func assign(_ rawStageID: String) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let active = activeWindow(in: snapshot),
              let displayID = active.scope?.displayID ?? displayID(containing: active.window.frame.center, in: snapshot.displays)
        else {
            return StageCommandResult(message: "stage assign: no active window", changed: false)
        }

        let stageID = StageID(rawValue: rawStageID)
        var state = store.state()
        var scope = activeScope(displayID: displayID, in: &state)
        scope.assign(window: active.window, to: stageID)
        state.update(scope)
        store.save(state)

        if scope.activeStageID != stageID {
            guard let display = snapshot.displays.first(where: { $0.id == displayID }) else {
                return StageCommandResult(message: "stage assign: unknown display", changed: false)
            }
            _ = service.setFrame(hiddenFrame(for: active.window.frame.cgRect, on: display, among: snapshot.displays), of: active.window)
        }
        events.append(RoadieEvent(
            type: "stage_assign",
            scope: StageScope(displayID: displayID, desktopID: scope.desktopID, stageID: stageID),
            details: ["windowID": String(active.window.id.rawValue)]
        ))
        return StageCommandResult(message: "stage assign \(stageID.rawValue): \(active.window.id)", changed: true)
    }

    public func assignPosition(_ position: Int) -> StageCommandResult {
        guard position > 0 else {
            return StageCommandResult(message: "stage assign-position: requires a positive position", changed: false)
        }
        let snapshot = service.snapshot()
        guard let active = activeWindow(in: snapshot),
              let displayID = active.scope?.displayID ?? displayID(containing: active.window.frame.center, in: snapshot.displays)
        else {
            return StageCommandResult(message: "stage assign-position: no active window", changed: false)
        }

        var state = store.state()
        let scope = activeScope(displayID: displayID, in: &state)
        guard let stageID = stageID(atVisiblePosition: position, in: scope) else {
            return StageCommandResult(message: "stage assign-position \(position): not found", changed: false)
        }
        return assign(stageID.rawValue)
    }

    public func assign(
        windowID: WindowID,
        to rawStageID: String,
        displayID: DisplayID,
        focusAssignedWindow: Bool = true
    ) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = snapshot.displays.first(where: { $0.id == displayID }) else {
            return StageCommandResult(message: "stage assign: unknown display", changed: false)
        }

        let stageID = StageID(rawValue: rawStageID)
        var state = store.state()
        var scope = activeScope(displayID: displayID, in: &state)
        guard let window = snapshot.windows.first(where: { $0.window.id == windowID })?.window else {
            scope.remove(windowID: windowID)
            state.update(scope)
            store.save(state)
            return StageCommandResult(message: "stage assign \(stageID.rawValue): stale window pruned", changed: true)
        }

        for scopeIndex in state.scopes.indices {
            state.scopes[scopeIndex].remove(windowID: windowID)
        }
        scope = activeScope(displayID: displayID, in: &state)
        scope.assign(window: window, to: stageID)
        state.update(scope)
        store.save(state)

        if scope.activeStageID != stageID {
            _ = service.setFrame(hiddenFrame(for: window.frame.cgRect, on: display, among: snapshot.displays), of: window)
        }

        let activeScope = StageScope(displayID: displayID, desktopID: scope.desktopID, stageID: scope.activeStageID)
        let layoutResult = service.apply(service.applyPlan(from: service.snapshot()))
        if focusAssignedWindow, scope.activeStageID == stageID {
            _ = service.focus(window)
        }
        events.append(RoadieEvent(
            type: "stage_assign_window",
            scope: activeScope,
            details: [
                "stageID": stageID.rawValue,
                "windowID": String(windowID.rawValue),
                "layout": String(layoutResult.attempted)
            ]
        ))
        return StageCommandResult(
            message: "stage assign \(stageID.rawValue): window=\(windowID.rawValue) layout=\(layoutResult.attempted)",
            changed: true
        )
    }

    public func list() -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "stage list: no display", changed: false)
        }
        var state = store.state()
        let scope = activeScope(displayID: display.id, in: &state)
        state.update(scope)
        store.save(state)

        var lines = ["ACTIVE\tID\tMODE\tWINDOWS\tNAME"]
        for stage in scope.stages {
            let active = stage.id == scope.activeStageID ? "*" : ""
            lines.append("\(active)\t\(stage.id.rawValue)\t\(stage.mode.rawValue)\t\(stage.members.count)\t\(stage.name)")
        }
        return StageCommandResult(message: lines.joined(separator: "\n"), changed: false)
    }

    public func create(_ rawStageID: String, name: String? = nil) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "stage create: no display", changed: false)
        }
        let stageID = StageID(rawValue: rawStageID)
        var state = store.state()
        var scope = activeScope(displayID: display.id, in: &state)
        guard scope.createStage(stageID, name: name) else {
            return StageCommandResult(message: "stage create \(stageID.rawValue): already exists", changed: false)
        }
        state.update(scope)
        store.save(state)
        return StageCommandResult(message: "stage create \(stageID.rawValue): \(name ?? "Stage \(stageID.rawValue)")", changed: true)
    }

    public func rename(_ rawStageID: String, to name: String) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "stage rename: no display", changed: false)
        }
        let stageID = StageID(rawValue: rawStageID)
        var state = store.state()
        var scope = activeScope(displayID: display.id, in: &state)
        guard scope.renameStage(stageID, to: name) else {
            return StageCommandResult(message: "stage rename \(stageID.rawValue): not found", changed: false)
        }
        state.update(scope)
        store.save(state)
        return StageCommandResult(message: "stage rename \(stageID.rawValue): \(name)", changed: true)
    }

    public func reorder(_ rawStageID: String, to position: Int) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "stage reorder: no display", changed: false)
        }
        return reorder(rawStageID, to: position, displayID: display.id)
    }

    public func reorder(_ rawStageID: String, to position: Int, displayID: DisplayID) -> StageCommandResult {
        let stageID = StageID(rawValue: rawStageID)
        var state = store.state()
        var scope = activeScope(displayID: displayID, in: &state)
        guard scope.reorderStage(stageID, to: position) else {
            return StageCommandResult(message: "stage reorder \(stageID.rawValue): not found", changed: false)
        }
        state.update(scope)
        store.save(state)
        return StageCommandResult(message: "stage reorder \(stageID.rawValue): position=\(position)", changed: true)
    }

    public func delete(_ rawStageID: String) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "stage delete: no display", changed: false)
        }
        let stageID = StageID(rawValue: rawStageID)
        var state = store.state()
        var scope = activeScope(displayID: display.id, in: &state)
        guard scope.deleteEmptyInactiveStage(stageID) else {
            return StageCommandResult(message: "stage delete \(stageID.rawValue): must exist, be inactive, and be empty", changed: false)
        }
        state.update(scope)
        store.save(state)
        return StageCommandResult(message: "stage delete \(stageID.rawValue)", changed: true)
    }

    public func switchTo(_ rawStageID: String) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "stage switch: no display", changed: false)
        }
        let stageID = StageID(rawValue: rawStageID)
        return switchDisplay(display, to: stageID, snapshot: snapshot)
    }

    public func switchTo(_ rawStageID: String, displayID: DisplayID) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = snapshot.displays.first(where: { $0.id == displayID }) else {
            return StageCommandResult(message: "stage switch: unknown display", changed: false)
        }
        return switchDisplay(display, to: StageID(rawValue: rawStageID), snapshot: snapshot)
    }

    public func switchToPosition(_ position: Int) -> StageCommandResult {
        guard position > 0 else {
            return StageCommandResult(message: "stage switch-position: requires a positive position", changed: false)
        }
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "stage switch-position: no display", changed: false)
        }
        var state = store.state()
        let scope = activeScope(displayID: display.id, in: &state)
        guard let stageID = stageID(atVisiblePosition: position, in: scope) else {
            return StageCommandResult(message: "stage switch-position \(position): not found", changed: false)
        }
        return switchDisplay(display, to: stageID, snapshot: snapshot)
    }

    public func summon(windowID: WindowID, displayID: DisplayID) -> StageCommandResult {
        var state = store.state()
        let scope = activeScope(displayID: displayID, in: &state)
        return assign(windowID: windowID, to: scope.activeStageID.rawValue, displayID: displayID)
    }

    public func moveActiveStageToDisplay(index displayIndex: Int, followFocus: Bool? = nil) -> StageCommandResult {
        moveActiveStageToDisplay(.index(displayIndex), followFocus: followFocus)
    }

    public func moveActiveStageToDisplay(direction: Direction, followFocus: Bool? = nil) -> StageCommandResult {
        moveActiveStageToDisplay(.direction(direction), followFocus: followFocus)
    }

    public func moveActiveStageToDisplay(_ target: StageDisplayMoveTarget, followFocus: Bool? = nil) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let sourceDisplay = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "stage move-to-display: no active display", changed: false)
        }
        var state = store.state()
        let sourceScope = activeScope(displayID: sourceDisplay.id, in: &state)
        return moveStageToDisplay(
            stageID: sourceScope.activeStageID,
            sourceDisplayID: sourceDisplay.id,
            target: target,
            followFocus: followFocus,
            source: "cli"
        )
    }

    public func moveStageToDisplay(
        stageID: StageID,
        sourceDisplayID: DisplayID,
        targetDisplayID: DisplayID,
        followFocus: Bool? = nil,
        source: String = "rail"
    ) -> StageCommandResult {
        moveStageToDisplay(
            stageID: stageID,
            sourceDisplayID: sourceDisplayID,
            target: .displayID(targetDisplayID),
            followFocus: followFocus,
            source: source
        )
    }

    public func moveStageToDisplay(
        stageID: StageID,
        sourceDisplayID: DisplayID,
        target: StageDisplayMoveTarget,
        followFocus: Bool? = nil,
        source: String = "cli"
    ) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let sourceDisplay = snapshot.displays.first(where: { $0.id == sourceDisplayID }),
              let targetDisplay = resolveStageMoveTarget(target, from: sourceDisplay, in: snapshot.displays)
        else {
            return stageMoveResult(
                status: .invalidTarget,
                stageID: stageID,
                sourceDisplayID: sourceDisplayID,
                targetDisplay: nil,
                followFocus: followFocus ?? config.focus.stageMoveFollowsFocus,
                movedWindowCount: 0,
                failedWindowCount: 0,
                source: source
            )
        }
        guard sourceDisplay.id != targetDisplay.id else {
            return stageMoveResult(
                status: .noopCurrentDisplay,
                stageID: stageID,
                sourceDisplayID: sourceDisplay.id,
                targetDisplay: targetDisplay,
                followFocus: followFocus ?? config.focus.stageMoveFollowsFocus,
                movedWindowCount: 0,
                failedWindowCount: 0,
                source: source
            )
        }

        var state = store.state()
        var sourceScope = activeScope(displayID: sourceDisplayID, in: &state)
        var targetScope = activeScope(displayID: targetDisplay.id, in: &state)
        guard let movingStageIndex = sourceScope.stages.firstIndex(where: { $0.id == stageID }) else {
            return stageMoveResult(
                status: .noActiveStage,
                stageID: stageID,
                sourceDisplayID: sourceDisplayID,
                targetDisplay: targetDisplay,
                followFocus: followFocus ?? config.focus.stageMoveFollowsFocus,
                movedWindowCount: 0,
                failedWindowCount: 0,
                source: source
            )
        }
        var movingStage = sourceScope.stages.remove(at: movingStageIndex)
        let requestedStageID = movingStage.id
        let sourceWasActive = sourceScope.activeStageID == requestedStageID
        let targetConflict = targetScope.stages.first { $0.id == movingStage.id }
        if let targetConflict,
           !targetConflict.members.isEmpty || !targetConflict.groups.isEmpty {
            movingStage.id = nextAvailableStageID(preferred: movingStage.id, in: targetScope)
        } else if targetConflict != nil {
            targetScope.stages.removeAll { $0.id == movingStage.id }
        }
        let effectiveFollow = followFocus ?? config.focus.stageMoveFollowsFocus
        targetScope.stages.append(movingStage)
        if effectiveFollow {
            targetScope.activeStageID = movingStage.id
        } else if targetScope.activeStageID == movingStage.id {
            targetScope.activeStageID = targetScope.stages.first { $0.id != movingStage.id }?.id
                ?? nextAvailableStageID(preferred: StageID(rawValue: "1"), in: targetScope)
            targetScope.ensureStage(targetScope.activeStageID)
        }
        if sourceScope.stages.isEmpty {
            sourceScope.ensureStage(StageID(rawValue: "1"))
        }
        if sourceWasActive {
            sourceScope.activeStageID = sourceScope.stages.first?.id ?? StageID(rawValue: "1")
        }
        state.update(sourceScope)
        state.update(targetScope)
        state.focusDisplay(effectiveFollow ? targetDisplay.id : sourceDisplay.id)
        store.save(state)

        let targetScopeID = StageScope(displayID: targetDisplay.id, desktopID: targetScope.desktopID, stageID: movingStage.id)
        var applied = 0
        var failed = 0
        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })
        for member in movingStage.members {
            guard let window = windowsByID[member.windowID] else {
                failed += 1
                continue
            }
            if service.setFrame(centeredFrame(member.frame.cgRect, in: targetDisplay.visibleFrame.cgRect), of: window) != nil {
                applied += 1
            } else {
                failed += 1
            }
        }
        service.removeLayoutIntent(scope: StageScope(displayID: sourceDisplay.id, desktopID: sourceScope.desktopID, stageID: requestedStageID))
        service.removeLayoutIntent(scope: targetScopeID)
        let result = service.apply(service.applyPlan(from: service.snapshot()))
        failed += result.failed
        events.append(RoadieEvent(
            type: "stage_move_display",
            scope: targetScopeID,
            details: [
                "status": failed == 0 ? StageDisplayMoveStatus.moved.rawValue : StageDisplayMoveStatus.partialFailure.rawValue,
                "source": source,
                "stageID": movingStage.id.rawValue,
                "requestedStageID": requestedStageID.rawValue,
                "sourceDisplayID": sourceDisplay.id.rawValue,
                "targetDisplayID": targetDisplay.id.rawValue,
                "targetDisplayIndex": String(targetDisplay.index),
                "followFocus": String(effectiveFollow),
                "movedWindowCount": String(movingStage.members.count),
                "failedWindowCount": String(failed),
                "applied": String(applied + result.applied + result.clamped)
            ]
        ))
        return stageMoveResult(
            status: failed == 0 ? .moved : .partialFailure,
            stageID: movingStage.id,
            sourceDisplayID: sourceDisplay.id,
            targetDisplay: targetDisplay,
            followFocus: effectiveFollow,
            movedWindowCount: movingStage.members.count,
            failedWindowCount: failed,
            source: source,
            requestedStageID: requestedStageID
        )
    }

    public func place(
        windowID: WindowID,
        displayID: DisplayID,
        orderedWindowIDs: [WindowID],
        placements providedPlacements: [WindowID: Rect] = [:]
    ) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let window = snapshot.windows.first(where: { $0.window.id == windowID })?.window else {
            return StageCommandResult(message: "stage place: unknown window \(windowID.rawValue)", changed: false)
        }

        var state = store.state()
        for scopeIndex in state.scopes.indices {
            state.scopes[scopeIndex].remove(windowID: windowID)
        }
        var persistentScope = activeScope(displayID: displayID, in: &state)
        let stageID = persistentScope.activeStageID
        persistentScope.assign(window: window, to: stageID)
        persistentScope.orderMembers(orderedWindowIDs, in: stageID)
        state.update(persistentScope)
        store.save(state)

        let scope = StageScope(displayID: displayID, desktopID: persistentScope.desktopID, stageID: stageID)
        service.removeLayoutIntent(scope: scope)
        let updated = service.snapshot()
        let ordered = normalizedOrder(orderedWindowIDs, windowID: windowID, in: updated, scope: scope)
        let layout = layoutPlan(from: updated, scope: scope, ordered: ordered, providedPlacements: providedPlacements)
        let applyPlan = applyPlan(from: updated, scope: scope, ordered: ordered, layout: layout)
        let result = service.apply(applyPlan)
        persistCommandIntent(scope: scope, orderedWindowIDs: ordered, layout: layout, result: result)
        _ = service.focus(window)
        events.append(RoadieEvent(
            type: "stage_place_window",
            scope: scope,
            details: [
                "windowID": String(windowID.rawValue),
                "commands": String(applyPlan.commands.count),
                "applied": String(result.applied),
                "clamped": String(result.clamped),
                "failed": String(result.failed)
            ]
        ))
        return StageCommandResult(
            message: "stage place: window=\(windowID.rawValue) commands=\(applyPlan.commands.count) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
            changed: result.failed < result.attempted || applyPlan.commands.isEmpty
        )
    }

    public func cycle(_ direction: StageCycleDirection) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "stage \(direction.rawValue): no display", changed: false)
        }
        var state = store.state()
        var scope = activeScope(displayID: display.id, in: &state)
        for id in (1...6).map({ StageID(rawValue: String($0)) }) {
            scope.ensureStage(id)
        }
        let ordered = scope.stages.map(\.id)
        let currentIndex = ordered.firstIndex(of: scope.activeStageID) ?? 0
        let nextIndex: Int
        switch direction {
        case .next:
            nextIndex = (currentIndex + 1) % ordered.count
        case .prev:
            nextIndex = (currentIndex - 1 + ordered.count) % ordered.count
        }
        state.update(scope)
        store.save(state)
        return switchDisplay(display, to: ordered[nextIndex], snapshot: snapshot)
    }

    public func setMode(_ mode: WindowManagementMode) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "mode \(mode.rawValue): no display", changed: false)
        }
        var state = store.state()
        var scope = activeScope(displayID: display.id, in: &state)
        let stageID = scope.activeStageID
        scope.setMode(mode, for: stageID)
        state.update(scope)
        store.save(state)

        let activeScope = StageScope(displayID: display.id, desktopID: scope.desktopID, stageID: stageID)
        service.removeLayoutIntent(scope: activeScope)
        let result = service.apply(service.applyPlan(from: service.snapshot()))
        events.append(RoadieEvent(
            type: "stage_mode",
            scope: activeScope,
            details: ["mode": mode.rawValue, "layout": String(result.attempted)]
        ))
        return StageCommandResult(
            message: "mode \(mode.rawValue): stage=\(stageID.rawValue) layout=\(result.attempted)",
            changed: true
        )
    }

    private func switchDisplay(
        _ display: DisplaySnapshot,
        to stageID: StageID,
        snapshot: DaemonSnapshot
    ) -> StageCommandResult {
        var state = store.state()
        var scope = activeScope(displayID: display.id, in: &state)
        let previousID = scope.activeStageID
        scope.ensureStage(stageID)
        state.focusDisplay(display.id)

        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })
        for window in windowsByID.values where display.frame.cgRect.contains(window.frame.center) && !isHidden(window.frame.cgRect) {
            scope.updateFrame(window: window)
        }

        let previousMembers = Set(scope.memberIDs(in: previousID))
        let targetMembers = Set(scope.memberIDs(in: stageID))
        var applied = 0

        for id in previousMembers.subtracting(targetMembers) {
            guard let window = windowsByID[id] else { continue }
            if service.setFrame(hiddenFrame(for: window.frame.cgRect, on: display, among: snapshot.displays), of: window) != nil {
                applied += 1
            }
        }

        let targetStage = scope.stages.first(where: { $0.id == stageID })
        for member in targetStage?.members ?? [] {
            guard let window = windowsByID[member.windowID] else { continue }
            if service.setFrame(member.frame.cgRect, of: window) != nil {
                applied += 1
            }
        }

        scope.activeStageID = stageID
        state.update(scope)
        store.save(state)

        let layoutResult = service.apply(service.applyPlan(from: service.snapshot()))
        applied += layoutResult.applied + layoutResult.clamped
        if let focusedID = targetStage?.focusedWindowID ?? targetStage?.members.last?.windowID,
           let focusedWindow = windowsByID[focusedID] {
            _ = service.focus(focusedWindow)
        }
        events.append(RoadieEvent(
            type: "stage_switch",
            scope: StageScope(displayID: display.id, desktopID: scope.desktopID, stageID: stageID),
            details: [
                "previousStageID": previousID.rawValue,
                "hidden": String(previousMembers.subtracting(targetMembers).count),
                "shown": String(targetMembers.count),
                "applied": String(applied),
                "layout": String(layoutResult.attempted)
            ]
        ))

        return StageCommandResult(
            message: "stage switch \(stageID.rawValue): hidden=\(previousMembers.subtracting(targetMembers).count) shown=\(targetMembers.count) applied=\(applied) layout=\(layoutResult.attempted)",
            changed: previousID != stageID || applied > 0 || layoutResult.attempted > 0
        )
    }

    private func resolveStageMoveTarget(
        _ target: StageDisplayMoveTarget,
        from sourceDisplay: DisplaySnapshot,
        in displays: [DisplaySnapshot]
    ) -> DisplaySnapshot? {
        switch target {
        case .index(let index):
            guard index > 0 else { return nil }
            return displays.first { $0.index == index }
        case .direction(let direction):
            return DisplayTopology.neighbor(from: sourceDisplay, direction: direction, in: displays)
        case .displayID(let displayID):
            return displays.first { $0.id == displayID }
        }
    }

    private func nextAvailableStageID(preferred: StageID, in scope: PersistentStageScope) -> StageID {
        let used = Set(scope.stages.map(\.id.rawValue))
        if !used.contains(preferred.rawValue) {
            return preferred
        }
        for value in 1...99 where !used.contains(String(value)) {
            return StageID(rawValue: String(value))
        }
        return StageID(rawValue: "\(preferred.rawValue)-\(UUID().uuidString.prefix(8))")
    }

    private func stageMoveResult(
        status: StageDisplayMoveStatus,
        stageID: StageID,
        sourceDisplayID: DisplayID,
        targetDisplay: DisplaySnapshot?,
        followFocus: Bool,
        movedWindowCount: Int,
        failedWindowCount: Int,
        source: String,
        requestedStageID: StageID? = nil
    ) -> StageCommandResult {
        let target = targetDisplay.map { "\($0.index)" } ?? "unknown"
        let requested = requestedStageID.map { $0 == stageID ? "" : " requested=\($0.rawValue)" } ?? ""
        let message: String
        switch status {
        case .moved:
            message = "stage move-to-display: moved stage=\(stageID.rawValue)\(requested) target=\(target) follow=\(followFocus) windows=\(movedWindowCount) failed=\(failedWindowCount)"
        case .partialFailure:
            message = "stage move-to-display: partial stage=\(stageID.rawValue)\(requested) target=\(target) follow=\(followFocus) windows=\(movedWindowCount) failed=\(failedWindowCount)"
        case .noopCurrentDisplay:
            message = "stage move-to-display: target is current display"
        case .invalidTarget:
            message = "stage move-to-display: invalid target=\(target)"
        case .noActiveStage:
            message = "stage move-to-display: no stage \(stageID.rawValue)"
        }
        if status != .moved && status != .partialFailure {
            events.append(RoadieEvent(type: "stage_move_display", details: [
                "status": status.rawValue,
                "source": source,
                "stageID": stageID.rawValue,
                "sourceDisplayID": sourceDisplayID.rawValue,
                "targetDisplayID": targetDisplay?.id.rawValue ?? "",
                "followFocus": String(followFocus),
                "movedWindowCount": String(movedWindowCount),
                "failedWindowCount": String(failedWindowCount)
            ]))
        }
        return StageCommandResult(message: message, changed: status == .moved || status == .partialFailure)
    }

    private func activeWindow(in snapshot: DaemonSnapshot) -> ScopedWindowSnapshot? {
        if let focusedID = snapshot.focusedWindowID,
           let focused = snapshot.windows.first(where: { entry in
               guard let scope = entry.scope else { return false }
               return entry.window.id == focusedID
                   && entry.window.isTileCandidate
                   && snapshot.state.activeScope(on: scope.displayID) == scope
           }) {
            return focused
        }
        return snapshot.windows.first { entry in
            guard let scope = entry.scope else { return false }
            return entry.window.isTileCandidate && snapshot.state.activeScope(on: scope.displayID) == scope
        }
    }

    private func normalizedOrder(
        _ orderedWindowIDs: [WindowID],
        windowID: WindowID,
        in snapshot: DaemonSnapshot,
        scope: StageScope
    ) -> [WindowID] {
        let scopedIDs = snapshot.windows.compactMap { entry in
            entry.scope == scope && entry.window.isTileCandidate ? entry.window.id : nil
        }
        var seen: Set<WindowID> = []
        var result: [WindowID] = []
        for id in orderedWindowIDs where scopedIDs.contains(id) || id == windowID {
            guard !seen.contains(id) else { continue }
            result.append(id)
            seen.insert(id)
        }
        for id in scopedIDs where !seen.contains(id) {
            result.append(id)
            seen.insert(id)
        }
        return result
    }

    private func persistCommandIntent(
        scope: StageScope,
        orderedWindowIDs: [WindowID],
        layout: LayoutPlan,
        result: ApplyResult
    ) {
        var placements = Dictionary(uniqueKeysWithValues: layout.placements.map { ($0.key, Rect($0.value)) })
        for item in result.items {
            placements[item.windowID] = item.actual ?? item.requested
        }
        guard Set(placements.keys) == Set(orderedWindowIDs) else { return }
        service.saveLayoutIntent(scope: scope, windowIDs: orderedWindowIDs, placements: placements, source: .command)
    }

    private func layoutPlan(
        from snapshot: DaemonSnapshot,
        scope: StageScope,
        ordered: [WindowID],
        providedPlacements: [WindowID: Rect]
    ) -> LayoutPlan {
        guard Set(providedPlacements.keys) == Set(ordered) else {
            return service.layoutPlan(from: snapshot, scope: scope, orderedWindowIDs: ordered, priorityWindowIDs: Set(ordered))
        }
        return LayoutPlan(placements: Dictionary(uniqueKeysWithValues: providedPlacements.map { ($0.key, $0.value.cgRect) }))
    }

    private func applyPlan(
        from snapshot: DaemonSnapshot,
        scope: StageScope,
        ordered: [WindowID],
        layout: LayoutPlan
    ) -> ApplyPlan {
        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })
        let currentFrames = Dictionary(uniqueKeysWithValues: snapshot.windows.compactMap { entry -> (WindowID, CGRect)? in
            guard entry.scope == scope, entry.window.isTileCandidate else { return nil }
            return (entry.window.id, entry.window.frame.cgRect)
        })
        let current = LayoutPlan(placements: currentFrames)
        let commands = LayoutDiff.commands(previous: current, next: layout).compactMap { command -> ApplyCommand? in
            guard ordered.contains(command.windowID),
                  let window = windowsByID[command.windowID]
            else { return nil }
            return ApplyCommand(window: window, frame: Rect(command.frame))
        }
        return ApplyPlan(commands: commands)
    }

    private func activeScope(displayID: DisplayID, in state: inout PersistentStageState) -> PersistentStageScope {
        state.scope(displayID: displayID, desktopID: state.currentDesktopID(for: displayID))
    }

    private func stageID(atVisiblePosition position: Int, in scope: PersistentStageScope) -> StageID? {
        let visible = scope.stages.filter { !$0.members.isEmpty }.map(\.id)
        let ordered = visible.isEmpty ? scope.stages.map(\.id) : visible
        let index = position - 1
        guard ordered.indices.contains(index) else { return nil }
        return ordered[index]
    }

    private func activeDisplay(in snapshot: DaemonSnapshot) -> DisplaySnapshot? {
        let state = store.state()
        if let activeDisplayID = state.activeDisplayID,
           let display = snapshot.displays.first(where: { $0.id == activeDisplayID }) {
            return display
        }
        if let active = activeWindow(in: snapshot),
           let displayID = active.scope?.displayID ?? displayID(containing: active.window.frame.center, in: snapshot.displays) {
            return snapshot.displays.first { $0.id == displayID }
        }
        return snapshot.displays.first
    }

    private func displayID(containing point: CGPoint, in displays: [DisplaySnapshot]) -> DisplayID? {
        displays.first { $0.frame.cgRect.contains(point) }?.id
    }

    private func hiddenFrame(for frame: CGRect, on display: DisplaySnapshot, among displays: [DisplaySnapshot]) -> CGRect {
        let corner = optimalHideCorner(for: display, among: displays)
        let visible = display.visibleFrame.cgRect
        switch corner {
        case .bottomLeft:
            return CGRect(
                x: visible.minX + 1 - frame.width,
                y: visible.maxY - 1,
                width: frame.width,
                height: frame.height
            ).integral
        case .bottomRight:
            return CGRect(
                x: visible.maxX - 1,
                y: visible.maxY - 1,
                width: frame.width,
                height: frame.height
            ).integral
        }
    }

    private func optimalHideCorner(for display: DisplaySnapshot, among displays: [DisplaySnapshot]) -> HideCorner {
        let frame = display.frame.cgRect
        let xOffset = frame.width * 0.1
        let yOffset = frame.height * 0.1
        let bottomLeft = CGPoint(x: frame.minX, y: frame.maxY)
        let bottomRight = CGPoint(x: frame.maxX, y: frame.maxY)

        let leftScore = overlapScore(points: [
            CGPoint(x: bottomLeft.x - 2, y: bottomLeft.y - yOffset),
            CGPoint(x: bottomLeft.x + xOffset, y: bottomLeft.y + 2),
            CGPoint(x: bottomLeft.x - 2, y: bottomLeft.y + 2),
        ], displays: displays)
        let rightScore = overlapScore(points: [
            CGPoint(x: bottomRight.x + 2, y: bottomRight.y - yOffset),
            CGPoint(x: bottomRight.x - xOffset, y: bottomRight.y + 2),
            CGPoint(x: bottomRight.x + 2, y: bottomRight.y + 2),
        ], displays: displays)
        return leftScore < rightScore ? .bottomLeft : .bottomRight
    }

    private func overlapScore(points: [CGPoint], displays: [DisplaySnapshot]) -> Int {
        points.enumerated().reduce(0) { score, item in
            let weight = item.offset == 2 ? 10 : 1
            let overlaps = displays.filter { $0.frame.cgRect.contains(item.element) }.count
            return score + weight * overlaps
        }
    }

    private func centeredFrame(_ frame: CGRect, in container: CGRect) -> CGRect {
        CGRect(
            x: container.midX - frame.width / 2,
            y: container.midY - frame.height / 2,
            width: frame.width,
            height: frame.height
        ).integral
    }

    private func isHidden(_ frame: CGRect) -> Bool {
        frame.maxX < -1000 || frame.minX < -10000
    }
}

public enum StageCycleDirection: String, Sendable {
    case prev
    case next
}

private enum HideCorner {
    case bottomLeft
    case bottomRight
}
