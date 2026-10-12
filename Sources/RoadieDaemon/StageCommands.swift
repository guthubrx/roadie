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
    private let commandActivity: LayoutCommandActivity

    public init(
        service: SnapshotService = SnapshotService(),
        store: StageStore? = nil,
        events: EventLog = EventLog(),
        config: RoadieConfig? = nil,
        commandActivity: LayoutCommandActivity = .shared
    ) {
        self.service = service
        self.store = store ?? service.effectiveStageStore
        self.events = events
        self.config = config ?? service.effectiveConfig
        self.commandActivity = commandActivity
    }

    public func assign(_ rawStageID: String) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let active = activeWindow(in: snapshot),
              let displayID = active.scope?.displayID ?? displayID(containing: active.window.frame.center, in: snapshot.displays)
        else {
            return StageCommandResult(message: "stage assign: no active window", changed: false)
        }

        return assign(
            windowID: active.window.id,
            to: rawStageID,
            displayID: displayID,
            focusAssignedWindow: true,
            eventType: "stage_assign",
            commandReason: "stage.assign"
        )
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
        guard let stageID = stageID(atAssignablePosition: position, in: scope) else {
            return StageCommandResult(message: "stage assign-position \(position): not found", changed: false)
        }
        return assign(stageID.rawValue)
    }

    public func assignEmpty() -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let active = activeWindow(in: snapshot),
              let displayID = active.scope?.displayID ?? displayID(containing: active.window.frame.center, in: snapshot.displays)
        else {
            return StageCommandResult(message: "stage assign-empty: no active window", changed: false)
        }

        var state = store.state()
        let scope = activeScope(displayID: displayID, in: &state)
        let stageID = nextEmptyStageID(in: scope)
        return assign(stageID.rawValue)
    }

    public func assign(
        windowID: WindowID,
        to rawStageID: String,
        displayID: DisplayID,
        insertionIndex: Int? = nil,
        focusAssignedWindow: Bool = true
    ) -> StageCommandResult {
        assign(
            windowID: windowID,
            to: rawStageID,
            displayID: displayID,
            insertionIndex: insertionIndex,
            focusAssignedWindow: focusAssignedWindow,
            eventType: "stage_assign_window",
            commandReason: "stage.assign_window"
        )
    }

    private func assign(
        windowID: WindowID,
        to rawStageID: String,
        displayID: DisplayID,
        insertionIndex: Int? = nil,
        focusAssignedWindow: Bool,
        eventType: String,
        commandReason: String
    ) -> StageCommandResult {
        beginLayoutCommand(commandReason)
        defer { finishLayoutCommand(commandReason) }
        let generation = PlacementGeneration.shared.next()
        let snapshot = service.snapshot()
        guard let display = snapshot.displays.first(where: { $0.id == displayID }) else {
            return StageCommandResult(message: "stage assign: unknown display", changed: false)
        }

        let stageID = StageID(rawValue: rawStageID)
        guard let entry = snapshot.windows.first(where: { $0.window.id == windowID }) else {
            store.mutate { state in
                var scope = activeScope(displayID: displayID, in: &state)
                scope.remove(windowID: windowID)
                state.update(scope)
            }
            return StageCommandResult(message: "stage assign \(stageID.rawValue): stale window pruned", changed: true)
        }
        let window = entry.window
        // Dépôt par le navrail à un rang donné (T093) : géométrie de l'arbre cible lue avant la transaction.
        var current = store.state()
        let rankedScope = StageScope(displayID: displayID, desktopID: activeScope(displayID: displayID, in: &current).desktopID, stageID: stageID)
        let rankedGeometry = insertionIndex == nil
            ? nil
            : service.commandTreeGeometry(for: rankedScope, tree: current.bspTree(for: rankedScope) ?? .empty, in: snapshot)

        let (scope, removedPin) = store.mutate { state -> (PersistentStageScope, PersistentWindowPin?) in
            for scopeIndex in state.scopes.indices {
                state.scopes[scopeIndex].remove(windowID: windowID)
            }
            var scope = activeScope(displayID: displayID, in: &state)
            let targetScope = StageScope(displayID: displayID, desktopID: scope.desktopID, stageID: stageID)
            let pin = entry.scope == targetScope ? nil : state.removePin(windowID: windowID)
            if entry.scope != targetScope {
                state.suppressRulePlacement(window: window)
            }
            scope.assign(
                window: window,
                to: stageID,
                insertionIndex: insertionIndex,
                focusWindow: focusAssignedWindow,
                defaultMode: config.tiling.defaultStrategy
            )
            state.update(scope)
            // Stage cible à arbre : la fenêtre entre dans l'arbre au rang demandé (après `update`,
            // qui remplace le scope entier).
            if insertionIndex != nil, scope.stages.first(where: { $0.id == stageID })?.mode.usesTreeEngine == true {
                if let sourceScope = entry.scope, sourceScope != targetScope, let sourceTree = state.bspTree(for: sourceScope) {
                    state.setBSPTree(sourceTree.removing(windowID), for: sourceScope)
                }
                state.setBSPTree(
                    insertingRanked(
                        windowID,
                        in: scope.memberIDs(in: stageID),
                        into: state.bspTree(for: targetScope) ?? .empty,
                        geometry: rankedGeometry,
                        fallback: display.visibleFrame.cgRect
                    ),
                    for: targetScope
                )
            }
            return (scope, pin)
        }
        let targetScope = StageScope(displayID: displayID, desktopID: scope.desktopID, stageID: stageID)

        var visibilityRepairFrame: CGRect?
        // Plan unique (A15, T212) : fenêtre masquée ou rendue visible, scope d'origine et stage
        // active disposés dans une seule écriture groupée.
        var placement = CommandPlacement()
        if scope.activeStageID != stageID, focusAssignedWindow {
            let switchResult = switchDisplay(
                display,
                to: stageID,
                snapshot: service.snapshot(followFocus: false),
                generation: generation
            )
            var details = [
                "stageID": stageID.rawValue,
                "windowID": String(windowID.rawValue),
                "layout": "0",
                "focusAssignedWindow": String(focusAssignedWindow),
                "focusFollowed": "true",
                "switchChanged": String(switchResult.changed),
                "unpinned": String(removedPin != nil),
            ]
            if let insertionIndex {
                details["insertionIndex"] = String(insertionIndex)
            }
            events.append(RoadieEvent(type: eventType, scope: targetScope, details: details))
            appendManualPinRemovalEvent(removedPin, targetScope: targetScope)
            return StageCommandResult(
                message: "stage assign \(stageID.rawValue): window=\(windowID.rawValue) followed=true",
                changed: true
            )
        } else if scope.activeStageID != stageID {
            store.mutate { state in
                state.protectCommandFocus(
                    displayID: displayID,
                    desktopID: scope.desktopID,
                    stageID: scope.activeStageID,
                    windowID: scope.stages.first(where: { $0.id == scope.activeStageID })?.focusedWindowID,
                    staleFocusedWindowID: windowID,
                    duration: 3.0
                )
            }
            placement.hiding[windowID] = HiddenWindowPlacement.frame(for: window.frame.cgRect, on: display, among: snapshot.displays)
        } else if let frame = visibleFrame(for: window.frame.cgRect, on: display) {
            visibilityRepairFrame = frame
            placement.restoring[windowID] = frame
        }

        let layoutScope = StageScope(displayID: displayID, desktopID: scope.desktopID, stageID: scope.activeStageID)
        placement.layoutScopes = Set([layoutScope, entry.scope].compactMap { $0 })
        let layoutResult = service.applyCommandPlacement(placement, cause: commandReason, generation: generation, events: events).result
        if focusAssignedWindow, scope.activeStageID == stageID {
            _ = service.focus(window)
        }
        var details = [
            "stageID": stageID.rawValue,
            "windowID": String(windowID.rawValue),
            "layout": String(layoutResult.attempted),
            "focusAssignedWindow": String(focusAssignedWindow),
            "unpinned": String(removedPin != nil),
        ]
        if let visibilityRepairFrame {
            details["visibilityRepair"] = "true"
            details["visibilityRepairFrame"] = "\(Rect(visibilityRepairFrame))"
        }
        if let insertionIndex {
            details["insertionIndex"] = String(insertionIndex)
        }
        events.append(RoadieEvent(type: eventType, scope: layoutScope, details: details))
        appendManualPinRemovalEvent(removedPin, targetScope: targetScope)
        return StageCommandResult(
            message: "stage assign \(stageID.rawValue): window=\(windowID.rawValue) layout=\(layoutResult.attempted)",
            changed: true
        )
    }

    private func appendManualPinRemovalEvent(_ pin: PersistentWindowPin?, targetScope: StageScope) {
        guard let pin else { return }
        var details = pin.eventDetails
        details["reason"] = "manual_window_move"
        events.append(RoadieEvent(type: "window.pin_removed", scope: targetScope, details: details))
    }

    public func list() -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "stage list: no display", changed: false)
        }
        // Lecture seule : pas de verrou exclusif ni d'écriture (FR-013).
        var state = store.state()
        let scope = activeScope(displayID: display.id, in: &state)

        var lines = ["ACTIVE\tID\tMODE\tWINDOWS\tNAME"]
        for stage in scope.stages where isSelectableStage(stage) {
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
        let created = store.mutate { state -> Bool in
            var scope = activeScope(displayID: display.id, in: &state)
            guard scope.createStage(stageID, name: name, mode: config.tiling.defaultStrategy) else { return false }
            state.update(scope)
            return true
        }
        guard created else {
            return StageCommandResult(message: "stage create \(stageID.rawValue): already exists", changed: false)
        }
        return StageCommandResult(message: "stage create \(stageID.rawValue): \(name ?? "Stage \(stageID.rawValue)")", changed: true)
    }

    public func rename(_ rawStageID: String, to name: String) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "stage rename: no display", changed: false)
        }
        return rename(rawStageID, to: name, displayID: display.id)
    }

    public func rename(_ rawStageID: String, to name: String, displayID: DisplayID) -> StageCommandResult {
        let stageID = StageID(rawValue: rawStageID)
        let renamed = store.mutate { state -> Bool in
            var scope = activeScope(displayID: displayID, in: &state)
            guard scope.renameStage(stageID, to: name) else { return false }
            state.update(scope)
            return true
        }
        guard renamed else {
            return StageCommandResult(message: "stage rename \(stageID.rawValue): not found", changed: false)
        }
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
        let reordered = store.mutate { state -> Bool in
            var scope = activeScope(displayID: displayID, in: &state)
            guard scope.reorderStage(stageID, to: position) else { return false }
            state.update(scope)
            return true
        }
        guard reordered else {
            return StageCommandResult(message: "stage reorder \(stageID.rawValue): not found", changed: false)
        }
        return StageCommandResult(message: "stage reorder \(stageID.rawValue): position=\(position)", changed: true)
    }

    public func delete(_ rawStageID: String) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "stage delete: no display", changed: false)
        }
        let stageID = StageID(rawValue: rawStageID)
        let deleted = store.mutate { state -> Bool in
            var scope = activeScope(displayID: display.id, in: &state)
            guard scope.deleteEmptyInactiveStage(stageID) else { return false }
            state.update(scope)
            return true
        }
        guard deleted else {
            return StageCommandResult(message: "stage delete \(stageID.rawValue): must exist, be inactive, and be empty", changed: false)
        }
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
        guard let stageID = stageID(atVisiblePosition: position, in: scope, liveWindowIDs: liveWindowIDs(in: snapshot)) else {
            return StageCommandResult(message: "stage switch-position \(position): not found", changed: false)
        }
        return switchDisplay(display, to: stageID, snapshot: snapshot)
    }

    public func summon(windowID: WindowID, displayID: DisplayID) -> StageCommandResult {
        var state = store.state()
        let scope = activeScope(displayID: displayID, in: &state)
        return assign(windowID: windowID, to: scope.activeStageID.rawValue, displayID: displayID)
    }

    public func focusNativeFullscreen(
        windowID: WindowID,
        bundleID: String,
        stageID: StageID,
        displayID: DisplayID
    ) -> StageCommandResult {
        let startedAt = Date()
        let snapshot = service.snapshot(followFocus: false)
        let focusedLiveWindow = snapshot.windows
            .first { $0.window.id == windowID }
            .map { service.focus($0.window) } ?? false
        var state = store.state()
        let member = state
            .scope(displayID: displayID)
            .stages
            .first { $0.id == stageID }?
            .members
            .first { $0.windowID == windowID }
        let focusedApplicationWindow = focusedLiveWindow ? false : service.focusApplicationWindow(
            bundleID: bundleID,
            windowID: windowID,
            title: member?.title ?? "",
            frame: member?.frame ?? Rect(x: 0, y: 0, width: 0, height: 0)
        )
        let activatedApplication = (focusedLiveWindow || focusedApplicationWindow) ? false : service.activateApplication(bundleID: bundleID)
        events.append(RoadieEvent(type: "stage_native_fullscreen_focus", scope: StageScope(
            displayID: displayID,
            desktopID: store.state().currentDesktopID(for: displayID),
            stageID: stageID
        ), details: [
            "windowID": String(windowID.rawValue),
            "bundleID": bundleID,
            "focusedLiveWindow": String(focusedLiveWindow),
            "focusedApplicationWindow": String(focusedApplicationWindow),
            "activatedApplication": String(activatedApplication),
            "durationMs": formatMs(elapsedMs(since: startedAt))
        ]))
        return StageCommandResult(
            message: "native fullscreen focus: window=\(windowID.rawValue) focused=\(focusedLiveWindow || focusedApplicationWindow) activated=\(activatedApplication)",
            changed: focusedLiveWindow || focusedApplicationWindow || activatedApplication
        )
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
        beginLayoutCommand("stage.move_display")
        defer { finishLayoutCommand("stage.move_display") }
        let generation = PlacementGeneration.shared.next()
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

        let effectiveFollow = followFocus ?? config.focus.stageMoveFollowsFocus
        let move = store.mutate { state -> (movingStage: PersistentStage, requestedStageID: StageID, sourceDesktopID: DesktopID, targetScopeID: StageScope)? in
            var sourceScope = activeScope(displayID: sourceDisplayID, in: &state)
            var targetScope = activeScope(displayID: targetDisplay.id, in: &state)
            guard let movingStageIndex = sourceScope.stages.firstIndex(where: { $0.id == stageID }) else { return nil }
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
            let targetScopeID = StageScope(displayID: targetDisplay.id, desktopID: targetScope.desktopID, stageID: movingStage.id)
            for member in movingStage.members {
                state.updatePinHomeScope(windowID: member.windowID, to: targetScopeID)
            }
            state.focusDisplay(effectiveFollow ? targetDisplay.id : sourceDisplay.id)
            return (movingStage, requestedStageID, sourceScope.desktopID, targetScopeID)
        }
        guard let move else {
            return stageMoveResult(
                status: .noActiveStage,
                stageID: stageID,
                sourceDisplayID: sourceDisplayID,
                targetDisplay: targetDisplay,
                followFocus: effectiveFollow,
                movedWindowCount: 0,
                failedWindowCount: 0,
                source: source
            )
        }
        let movingStage = move.movingStage
        let requestedStageID = move.requestedStageID
        let targetScopeID = move.targetScopeID

        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })
        // Plan unique (A15, T212) : membres transférés et disposition des deux écrans en une écriture.
        var placement = CommandPlacement(layoutScopes: nil)
        for member in movingStage.members where windowsByID[member.windowID] != nil {
            placement.restoring[member.windowID] = centeredFrame(member.frame.cgRect, in: targetDisplay.visibleFrame.cgRect)
        }
        var failed = movingStage.members.count - placement.restoring.count
        service.removeLayoutIntent(scope: StageScope(displayID: sourceDisplay.id, desktopID: move.sourceDesktopID, stageID: requestedStageID))
        service.removeLayoutIntent(scope: targetScopeID)
        let result = service.applyCommandPlacement(placement, cause: "stage.move_display", generation: generation, events: events).result
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
                "applied": String(result.applied + result.clamped)
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

    /// `treeMutation` : mutation de l'arbre cible d'un dépôt glissé (échange ou insertion du côté
    /// visé). Sans elle, une stage à arbre reçoit la fenêtre au rang demandé dans `orderedWindowIDs`.
    public func place(
        windowID: WindowID,
        displayID: DisplayID,
        orderedWindowIDs: [WindowID],
        placements providedPlacements: [WindowID: Rect] = [:],
        treeMutation: ((BSPTree) -> BSPTree)? = nil
    ) -> StageCommandResult {
        if activeStageMode(displayID: displayID).usesTreeEngine {
            return placeInTree(windowID: windowID, displayID: displayID, orderedWindowIDs: orderedWindowIDs, treeMutation: treeMutation)
        }
        beginLayoutCommand("stage.place_window")
        defer { finishLayoutCommand("stage.place_window") }
        let generation = PlacementGeneration.shared.next()
        let snapshot = service.snapshot()
        guard let sourceEntry = snapshot.windows.first(where: { $0.window.id == windowID }) else {
            return StageCommandResult(message: "stage place: unknown window \(windowID.rawValue)", changed: false)
        }
        let window = sourceEntry.window
        let sourceScope = sourceEntry.scope

        let scope = store.mutate { state -> StageScope in
            for scopeIndex in state.scopes.indices {
                state.scopes[scopeIndex].remove(windowID: windowID)
            }
            var persistentScope = activeScope(displayID: displayID, in: &state)
            let stageID = persistentScope.activeStageID
            persistentScope.assign(window: window, to: stageID)
            persistentScope.orderMembers(orderedWindowIDs, in: stageID)
            state.update(persistentScope)
            return StageScope(displayID: displayID, desktopID: persistentScope.desktopID, stageID: stageID)
        }
        service.removeLayoutIntent(scope: scope)
        if let sourceScope, sourceScope != scope {
            service.removeLayoutIntent(scope: sourceScope)
        }
        let updated = service.snapshot(followFocus: false)
        let sourceRelayout = relayoutActiveSourceScopes(
            [sourceScope].compactMap { $0 },
            excluding: scope,
            from: updated,
            generation: generation
        )
        let ordered = normalizedOrder(orderedWindowIDs, windowID: windowID, in: updated, scope: scope)
        let layout = layoutPlan(from: updated, scope: scope, ordered: ordered, providedPlacements: providedPlacements)
        let applyPlan = applyPlan(from: updated, scope: scope, ordered: ordered, layout: layout)
        let result = service.apply(applyPlan, generation: generation)
        let isolated = isolateInfeasibleClampedScope(
            scope,
            result: result,
            snapshot: updated,
            keepWindowID: windowID,
            generation: generation
        )
        persistCommandIntent(scope: scope, orderedWindowIDs: ordered, layout: layout, result: result)
        _ = service.focus(window)
        events.append(RoadieEvent(
            type: "stage_place_window",
            scope: scope,
            details: [
                "windowID": String(windowID.rawValue),
                "commands": String(applyPlan.commands.count + isolated),
                "applied": String(result.applied + isolated),
                "clamped": String(result.clamped),
                "failed": String(result.failed),
                "sourceCommands": String(sourceRelayout.plan.commands.count),
                "sourceApplied": String(sourceRelayout.result.applied),
                "sourceClamped": String(sourceRelayout.result.clamped),
                "sourceFailed": String(sourceRelayout.result.failed)
            ]
        ))
        return StageCommandResult(
            message: "stage place: window=\(windowID.rawValue) commands=\(applyPlan.commands.count + sourceRelayout.plan.commands.count + isolated) applied=\(result.applied + sourceRelayout.result.applied + isolated) clamped=\(result.clamped + sourceRelayout.result.clamped) failed=\(result.failed + sourceRelayout.result.failed)",
            changed: result.failed < result.attempted
                || sourceRelayout.result.failed < sourceRelayout.result.attempted
                || applyPlan.commands.isEmpty
        )
    }

    /// `stage_place_window` vers une stage à arbre (SPEC-017 R12, T093). Une transaction retire la
    /// fenêtre de toutes les stages et de l'arbre de sa stage d'origine, l'ajoute à la stage active
    /// de l'écran et mute l'arbre de celle-ci (`treeMutation`, sinon insertion au rang demandé).
    /// Puis un seul plan pour les scopes d'origine et cible, appliqué en une écriture groupée dans la
    /// génération de la commande (T212, T213), sans l'attente globale de `LayoutCommandActivity`.
    // O(w + n²) - w = fenêtres du snapshot, n = feuilles de l'arbre cible (borné).
    private func placeInTree(
        windowID: WindowID,
        displayID: DisplayID,
        orderedWindowIDs: [WindowID],
        treeMutation: ((BSPTree) -> BSPTree)?
    ) -> StageCommandResult {
        let generation = PlacementGeneration.shared.next()
        let snapshot = service.snapshot()
        guard let sourceEntry = snapshot.windows.first(where: { $0.window.id == windowID }),
              let display = snapshot.displays.first(where: { $0.id == displayID })
        else {
            return StageCommandResult(message: "stage place: unknown window \(windowID.rawValue)", changed: false)
        }
        let window = sourceEntry.window
        let sourceScope = sourceEntry.scope
        var current = store.state()
        let currentScope = activeScope(displayID: displayID, in: &current)
        let plannedScope = StageScope(displayID: displayID, desktopID: currentScope.desktopID, stageID: currentScope.activeStageID)
        let geometry = service.commandTreeGeometry(for: plannedScope, tree: current.bspTree(for: plannedScope) ?? .empty, in: snapshot)
        let scope = store.mutate { state -> StageScope in
            state.remove(windowID: windowID)
            var persistentScope = activeScope(displayID: displayID, in: &state)
            let stageID = persistentScope.activeStageID
            persistentScope.assign(window: window, to: stageID)
            persistentScope.orderMembers(orderedWindowIDs, in: stageID)
            state.update(persistentScope)
            let scope = StageScope(displayID: displayID, desktopID: persistentScope.desktopID, stageID: stageID)
            // Arbres mis à jour après `update`, qui remplace le scope entier.
            if let sourceScope, sourceScope != scope, let sourceTree = state.bspTree(for: sourceScope) {
                state.setBSPTree(sourceTree.removing(windowID), for: sourceScope)
            }
            let tree = state.bspTree(for: scope) ?? .empty
            state.setBSPTree(
                treeMutation?(tree) ?? insertingRanked(windowID, in: orderedWindowIDs, into: tree, geometry: geometry, fallback: display.visibleFrame.cgRect),
                for: scope
            )
            return scope
        }
        service.removeLayoutIntent(scope: scope)
        if let sourceScope, sourceScope != scope {
            service.removeLayoutIntent(scope: sourceScope)
        }
        // Plan unique (A15, T212) : scope d'origine et scope cible disposés dans une seule écriture
        // groupée, puis le focus.
        let (plan, result) = service.applyCommandPlacement(
            CommandPlacement(layoutScopes: Set([scope, sourceScope].compactMap { $0 })),
            cause: "stage.place_window",
            generation: generation,
            events: events
        )
        _ = service.focus(window)
        events.append(RoadieEvent(
            type: "stage_place_window",
            scope: scope,
            details: [
                "windowID": String(windowID.rawValue),
                "strategy": "tree",
                "treeMutation": String(treeMutation != nil),
                "commands": String(plan.commands.count),
                "applied": String(result.applied),
                "clamped": String(result.clamped),
                "failed": String(result.failed)
            ]
        ))
        return StageCommandResult(
            message: "stage place: window=\(windowID.rawValue) tree commands=\(plan.commands.count) applied=\(result.applied) failed=\(result.failed)",
            changed: true
        )
    }

    /// Insère `windowID` dans `tree` au rang qu'elle occupe dans `ordered` (index demandé par le
    /// navrail ou par un dépôt sans cible, T093) : devant la fenêtre suivante présente dans l'arbre,
    /// sinon derrière la précédente. Coupe selon la forme de la feuille visée (R3).
    // O(n²) au pire - n = feuilles, borné.
    private func insertingRanked(
        _ windowID: WindowID,
        in ordered: [WindowID],
        into tree: BSPTree,
        geometry: CommandTreeGeometry?,
        fallback container: CGRect
    ) -> BSPTree {
        let rest = tree.removing(windowID)
        let index = ordered.firstIndex(of: windowID)
        let next = index.flatMap { ordered[($0 + 1)...].first { rest.contains($0) } }
        let previous = index.flatMap { ordered[..<$0].last { rest.contains($0) } }
        return rest.inserting(
            windowID,
            at: next ?? previous,
            side: next == nil ? .right : .left,
            in: geometry?.container ?? container,
            innerGap: geometry?.innerGap ?? 0,
            excluding: geometry?.absent ?? []
        )
    }

    /// Mode de la stage active d'un écran, lu sans transaction (état en cache).
    private func activeStageMode(displayID: DisplayID) -> WindowManagementMode {
        var state = store.state()
        let scope = activeScope(displayID: displayID, in: &state)
        return scope.stages.first { $0.id == scope.activeStageID }?.mode ?? config.tiling.defaultStrategy
    }

    public func cycle(_ direction: StageCycleDirection) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "stage \(direction.rawValue): no display", changed: false)
        }
        let nextStageID = store.mutate { state -> StageID in
            var scope = activeScope(displayID: display.id, in: &state)
            for id in (1...6).map({ StageID(rawValue: String($0)) }) {
                scope.ensureStage(id, mode: config.tiling.defaultStrategy)
            }
            let ordered = selectableStageIDs(in: scope)
            let currentIndex = ordered.firstIndex(of: scope.activeStageID) ?? 0
            let nextIndex: Int
            switch direction {
            case .next:
                nextIndex = (currentIndex + 1) % ordered.count
            case .prev:
                nextIndex = (currentIndex - 1 + ordered.count) % ordered.count
            }
            state.update(scope)
            return ordered[nextIndex]
        }
        return switchDisplay(display, to: nextStageID, snapshot: snapshot)
    }

    public func switchVisible(_ direction: StageCycleDirection) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "stage switch-visible \(direction.rawValue): no display", changed: false)
        }
        var state = store.state()
        let scope = activeScope(displayID: display.id, in: &state)
        let ordered = visibleStageIDs(in: scope, liveWindowIDs: liveWindowIDs(in: snapshot))
        guard !ordered.isEmpty else {
            return StageCommandResult(message: "stage switch-visible \(direction.rawValue): no visible stage", changed: false)
        }
        let currentIndex = ordered.firstIndex(of: scope.activeStageID)
        let nextIndex: Int
        switch direction {
        case .next:
            nextIndex = currentIndex.map { ($0 + 1) % ordered.count } ?? 0
        case .prev:
            nextIndex = currentIndex.map { ($0 - 1 + ordered.count) % ordered.count } ?? (ordered.count - 1)
        }
        return switchDisplay(display, to: ordered[nextIndex], snapshot: snapshot)
    }

    public func setMode(_ mode: WindowManagementMode) -> StageCommandResult {
        let generation = PlacementGeneration.shared.next()
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "mode \(mode.rawValue): no display", changed: false)
        }
        // Seul l'écran de la commande est soustrait au maintien (FR-040).
        let commandScopes = Set([snapshot.state.activeScope(on: display.id)].compactMap { $0 })
        beginLayoutCommand("stage.mode", scopes: commandScopes)
        defer { finishLayoutCommand("stage.mode", scopes: commandScopes) }
        let modeScope = store.mutate { state -> StageScope in
            var scope = activeScope(displayID: display.id, in: &state)
            let stageID = scope.activeStageID
            scope.setMode(mode, for: stageID)
            state.update(scope)
            return StageScope(displayID: display.id, desktopID: scope.desktopID, stageID: stageID)
        }
        let stageID = modeScope.stageID
        service.removeLayoutIntent(scope: modeScope)
        let result = service.apply(service.applyPlan(from: service.snapshot(followFocus: false), generation: generation), generation: generation)
        events.append(RoadieEvent(
            type: "stage_mode",
            scope: modeScope,
            details: ["mode": mode.rawValue, "layout": String(result.attempted)]
        ))
        return StageCommandResult(
            message: "mode \(mode.rawValue): stage=\(stageID.rawValue) layout=\(result.attempted)",
            changed: true
        )
    }

    /// Résultat de la transaction de bascule : ce que les étapes AX suivantes doivent savoir.
    private struct StageSwitchTransition {
        var desktopID: DesktopID
        var previousID: StageID
        var activeDisplayChanged: Bool
        var targetMembers: Set<WindowID>
        var targetStage: PersistentStage?
        var targetFocusedWindowID: WindowID?
        var hiddenWindowIDs: Set<WindowID>
        var targetMissing: Bool
        var nativeFullscreenMember: PersistentStageMember?
    }

    /// `generation` : celle de la commande, ouverte à son entrée et passée à toutes ses écritures
    /// (A13, T213) ; une nouvelle si la bascule est la commande elle-même.
    private func switchDisplay(
        _ display: DisplaySnapshot,
        to stageID: StageID,
        snapshot: DaemonSnapshot,
        generation: UInt64 = PlacementGeneration.shared.next()
    ) -> StageCommandResult {
        let startedAt = Date()
        // Lecture pour décider du cas « déjà active » ; les écritures passent par `mutate`.
        var state = store.state()
        let scope = activeScope(displayID: display.id, in: &state)
        let previousID = scope.activeStageID
        // Écran et bureau de la bascule : seuls eux sont soustraits au maintien (FR-040).
        let switchScope = StageScope(displayID: display.id, desktopID: scope.desktopID, stageID: stageID)
        if previousID == stageID {
            let activeDisplayChanged = state.activeDisplayID != display.id
            let targetStage = scope.stages.first { $0.id == stageID }
            let targetMembers = targetStage?.members ?? []
            let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })
            let liveWindowIDs = Set(windowsByID.keys)
            let nativeFullscreenMember = targetMembers
                .first { $0.presentationState == .nativeFullscreen && !liveWindowIDs.contains($0.windowID) }
            let activatedNativeFullscreen = nativeFullscreenMember.map {
                service.activateApplication(bundleID: $0.bundleID)
            } ?? false
            if nativeFullscreenMember == nil {
                let visibleTargetMemberIDs = targetMembers.compactMap { member -> WindowID? in
                    guard let window = windowsByID[member.windowID],
                          !HiddenWindowPlacement.isHiddenOrLegacyOffscreen(window.frame.cgRect, in: snapshot.displays),
                          display.frame.cgRect.intersects(window.frame.cgRect)
                    else { return nil }
                    return member.windowID
                }
                if !targetMembers.isEmpty && visibleTargetMemberIDs.isEmpty {
                    beginLayoutCommand("stage.switch.reconcile", scopes: [switchScope])
                    defer { finishLayoutCommand("stage.switch.reconcile", scopes: [switchScope]) }

                    let targetLiveMemberIDs = targetMembers.compactMap { member -> WindowID? in
                        windowsByID[member.windowID] == nil ? nil : member.windowID
                    }
                    let targetFocusedWindowID = targetStage?.focusedWindowID.flatMap { windowsByID[$0] == nil ? nil : $0 }
                        ?? targetLiveMemberIDs.last
                        ?? targetStage?.focusedWindowID
                        ?? targetMembers.last?.windowID
                    let persistStartedAt = Date()
                    store.mutate { state in
                        _ = activeScope(displayID: display.id, in: &state)
                        state.focusDisplay(display.id)
                        state.protectCommandFocus(
                            displayID: display.id,
                            desktopID: scope.desktopID,
                            stageID: stageID,
                            windowID: targetFocusedWindowID,
                            staleFocusedWindowID: snapshot.focusedWindowID,
                            duration: 3.0
                        )
                    }
                    let persistMs = elapsedMs(since: persistStartedAt)

                    let applied: Int
                    if targetStage?.mode.usesTreeEngine == true {
                        // Mode arbre (A11) : frames finales de l'arbre, pas les frames mémorisées.
                        let tick = service.applyTreeScope(switchScope, cause: "stage.switch.reconcile", generation: generation)
                        applied = tick.applied + tick.clamped
                    } else {
                        let restoring = Dictionary(uniqueKeysWithValues: targetMembers.compactMap { member in
                            windowsByID[member.windowID] == nil ? nil : (member.windowID, member.frame.cgRect)
                        })
                        let result = service.applyCommandPlacement(
                            CommandPlacement(restoring: restoring),
                            snapshot: snapshot,
                            cause: "stage.switch.reconcile",
                            generation: generation,
                            events: events
                        ).result
                        applied = result.applied + result.clamped
                    }
                    var focusedWindow = false
                    if let focusedID = targetFocusedWindowID,
                       let window = windowsByID[focusedID] {
                        focusedWindow = service.focus(window)
                    }
                    var focusedApplicationWindow = false
                    var activatedApplication = false
                    if !focusedWindow,
                       let member = targetMembers.first(where: { $0.windowID == targetFocusedWindowID }) ?? targetMembers.last {
                        focusedApplicationWindow = service.focusApplicationWindow(
                            bundleID: member.bundleID,
                            windowID: member.windowID,
                            title: member.title,
                            frame: member.frame
                        )
                        if !focusedApplicationWindow {
                            activatedApplication = service.activateApplication(bundleID: member.bundleID)
                        }
                    }
                    events.append(RoadieEvent(
                        type: "stage_switch_reconcile",
                        scope: StageScope(displayID: display.id, desktopID: scope.desktopID, stageID: stageID),
                        details: [
                            "previousStageID": previousID.rawValue,
                            "reason": "active_stage_members_not_visible",
                            "targetMembers": String(targetMembers.count),
                            "liveTargetMembers": String(targetLiveMemberIDs.count),
                            "visibleTargetMembers": String(visibleTargetMemberIDs.count),
                            "applied": String(applied),
                            "focusedWindow": String(focusedWindow),
                            "focusedApplicationWindow": String(focusedApplicationWindow),
                            "activatedApplication": String(activatedApplication),
                            "activeDisplayChanged": String(activeDisplayChanged),
                            "persistMs": formatMs(persistMs),
                            "durationMs": formatMs(elapsedMs(since: startedAt))
                        ]
                    ))
                    return StageCommandResult(
                        message: "stage switch \(stageID.rawValue): reconciled active stage",
                        changed: true
                    )
                }
            }
            if activeDisplayChanged {
                store.mutate { $0.focusDisplay(display.id) }
            }
            events.append(RoadieEvent(
                type: "stage_switch_noop",
                scope: StageScope(displayID: display.id, desktopID: scope.desktopID, stageID: stageID),
                details: [
                    "previousStageID": previousID.rawValue,
                    "activeDisplayChanged": String(activeDisplayChanged),
                    "nativeFullscreenActivation": String(activatedNativeFullscreen),
                    "durationMs": formatMs(elapsedMs(since: startedAt))
                ]
            ))
            return StageCommandResult(
                message: "stage switch \(stageID.rawValue): already active",
                changed: activeDisplayChanged || activatedNativeFullscreen
            )
        }

        // Stage cible à arbre : application immédiate, sans l'attente de `LayoutCommandActivity` (R12).
        let targetUsesTree = (scope.stages.first { $0.id == stageID }?.mode ?? config.tiling.defaultStrategy).usesTreeEngine
        if !targetUsesTree { beginLayoutCommand("stage.switch", scopes: [switchScope]) }
        defer { if !targetUsesTree { finishLayoutCommand("stage.switch", scopes: [switchScope]) } }
        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })
        // Préparé hors verrou : fenêtres visibles de l'écran. O(w * d), w = fenêtres, d = écrans.
        let visibleWindows = windowsByID.values.filter {
            display.frame.cgRect.contains($0.frame.center)
                && !HiddenWindowPlacement.isHiddenOrLegacyOffscreen($0.frame.cgRect, in: snapshot.displays)
        }

        let persistStartedAt = Date()
        // Transaction : relit l'état frais, bascule la stage active et protège le focus.
        // Ni AX ni événement dans le bloc (verrou d'état tenu).
        let transition = store.mutate { state -> StageSwitchTransition in
            var scope = activeScope(displayID: display.id, in: &state)
            let activeDisplayChanged = state.activeDisplayID != display.id
            let previousID = scope.activeStageID
            scope.ensureStage(stageID, mode: config.tiling.defaultStrategy)
            state.focusDisplay(display.id)
            // O(v * M), v = fenêtres visibles, M = membres de l'écran (recherche du membre par fenêtre).
            for window in visibleWindows {
                scope.updateFrame(window: window)
            }

            let previousMembers = Set(scope.memberIDs(in: previousID))
            let targetMembers = Set(scope.memberIDs(in: stageID))
            let targetStage = scope.stages.first(where: { $0.id == stageID })
            let targetLiveMemberIDs = targetStage?.members.compactMap { member -> WindowID? in
                windowsByID[member.windowID] == nil ? nil : member.windowID
            } ?? []
            let targetFocusedWindowID = targetStage?.focusedWindowID.flatMap { windowsByID[$0] == nil ? nil : $0 }
                ?? targetLiveMemberIDs.last
                ?? targetStage?.focusedWindowID
                ?? targetStage?.members.last?.windowID
            let hiddenWindowIDs = previousMembers.subtracting(targetMembers)
            // Toutes les fenêtres de la stage cible ont disparu (application absente, autre
            // Space, absence courte) : la bascule a lieu quand même, puis on tente de faire
            // revenir l'application. Sans cela, la stage resterait inatteignable pendant la
            // grâce des membres absents.
            let targetMissing = !targetMembers.isEmpty && targetLiveMemberIDs.isEmpty
            let nativeFullscreenMember = targetMissing
                ? targetStage?.members.first { $0.presentationState == .nativeFullscreen }
                : nil
            scope.activeStageID = stageID
            state.update(scope)
            state.protectCommandFocus(
                displayID: display.id,
                desktopID: scope.desktopID,
                stageID: stageID,
                windowID: targetFocusedWindowID,
                staleFocusedWindowID: nativeFullscreenMember == nil
                    ? snapshot.focusedWindowID.flatMap { hiddenWindowIDs.contains($0) ? $0 : nil }
                    : nil,
                duration: 3.0
            )
            return StageSwitchTransition(
                desktopID: scope.desktopID,
                previousID: previousID,
                activeDisplayChanged: activeDisplayChanged,
                targetMembers: targetMembers,
                targetStage: targetStage,
                targetFocusedWindowID: targetFocusedWindowID,
                hiddenWindowIDs: hiddenWindowIDs,
                targetMissing: targetMissing,
                nativeFullscreenMember: nativeFullscreenMember
            )
        }
        let persistMs = elapsedMs(since: persistStartedAt)
        let targetScope = StageScope(displayID: display.id, desktopID: transition.desktopID, stageID: stageID)

        if transition.targetMissing {
            var hidden = 0
            var focusedApplicationWindow = false
            var activatedApplication = false
            if let nativeFullscreenMember = transition.nativeFullscreenMember {
                // La fenêtre vit dans son propre Space : activer l'application suffit.
                activatedApplication = service.activateApplication(bundleID: nativeFullscreenMember.bundleID)
            } else {
                let hiding = hiddenFrames(transition.hiddenWindowIDs, windowsByID: windowsByID, display: display, displays: snapshot.displays)
                let result = service.applyCommandPlacement(
                    CommandPlacement(hiding: hiding),
                    snapshot: snapshot,
                    cause: "stage.switch.missing_target",
                    generation: generation,
                    events: events
                ).result
                hidden = result.applied + result.clamped
                if let focusMember = preferredMissingFocusMember(in: transition.targetStage) {
                    focusedApplicationWindow = service.focusApplicationWindow(
                        bundleID: focusMember.bundleID,
                        windowID: focusMember.windowID,
                        title: focusMember.title,
                        frame: focusMember.frame
                    )
                    if !focusedApplicationWindow {
                        activatedApplication = service.activateApplication(bundleID: focusMember.bundleID)
                    }
                }
            }
            events.append(RoadieEvent(
                type: "stage_switch_pending_missing_target",
                scope: targetScope,
                details: [
                    "previousStageID": transition.previousID.rawValue,
                    "targetMembers": transition.targetMembers.map { String($0.rawValue) }.sorted().joined(separator: ","),
                    "reason": transition.nativeFullscreenMember == nil
                        ? "target_stage_members_missing_pending_focus"
                        : "target_stage_members_missing_pending_reconcile",
                    "stateChanged": "true",
                    "hidden": String(hidden),
                    "focusedApplicationWindow": String(focusedApplicationWindow),
                    "activatedApplication": String(activatedApplication),
                    "nativeFullscreenActivation": String(transition.nativeFullscreenMember != nil && activatedApplication),
                    "activeDisplayChanged": String(transition.activeDisplayChanged),
                    "persistMs": formatMs(persistMs),
                    "durationMs": formatMs(elapsedMs(since: startedAt))
                ]
            ))
            return StageCommandResult(
                message: "stage switch \(stageID.rawValue): pending missing target",
                changed: true
            )
        }
        let fullscreenMemberID = targetFullscreenMemberID(
            in: transition.targetStage,
            scope: targetScope,
            windowsByID: windowsByID,
            preferredWindowID: transition.targetFocusedWindowID
        )

        // Plan unique (A15, T212) : masquage de la stage quittée et disposition de la stage cible
        // dans une seule écriture groupée, puis le focus.
        var placement = CommandPlacement(hiding: hiddenFrames(transition.hiddenWindowIDs, windowsByID: windowsByID, display: display, displays: snapshot.displays))
        if targetUsesTree, fullscreenMemberID == nil {
            // Mode arbre (A11, T094) : frames finales de l'arbre, sans restaurer les frames mémorisées.
            placement.layoutScopes = [targetScope]
        } else {
            for member in transition.targetStage?.members ?? [] {
                guard let window = windowsByID[member.windowID] else { continue }
                if fullscreenMemberID == nil || member.windowID == fullscreenMemberID {
                    if member.windowID == fullscreenMemberID,
                       service.commandLayoutIntent(scope: targetScope)?.zoomReservesRail == true {
                        if let frame = service.maximizedFrame(on: display) {
                            placement.restoring[member.windowID] = frame
                        }
                    } else {
                        placement.restoring[member.windowID] = member.frame.cgRect
                    }
                } else {
                    placement.hiding[member.windowID] = HiddenWindowPlacement.frame(for: window.frame.cgRect, on: display, among: snapshot.displays)
                }
            }
            // Membre plein écran protégé : la stage cible garde ses frames, sans disposition.
            placement.layoutScopes = fullscreenMemberID == nil ? [targetScope] : []
        }
        let layoutStartedAt = Date()
        let (layoutPlan, layoutResult) = service.applyCommandPlacement(placement, cause: "stage.switch", generation: generation, events: events)
        let applied = layoutResult.applied + layoutResult.clamped
        let layoutAttempted = layoutPlan.commands.count
        let layoutMs = elapsedMs(since: layoutStartedAt)
        let focusStartedAt = Date()
        if let focusedID = transition.targetFocusedWindowID,
           let focusedWindow = windowsByID[focusedID] {
            _ = service.focus(focusedWindow)
        }
        let focusMs = elapsedMs(since: focusStartedAt)
        let totalMs = elapsedMs(since: startedAt)
        events.append(RoadieEvent(
            type: "stage_switch",
            scope: targetScope,
            details: [
                "previousStageID": transition.previousID.rawValue,
                "hidden": String(transition.hiddenWindowIDs.count),
                "shown": String(transition.targetMembers.count),
                "applied": String(applied),
                "layout": String(layoutAttempted),
                "strategy": targetUsesTree && fullscreenMemberID == nil ? "tree" : "restore",
                "fullscreenProtected": String(fullscreenMemberID != nil),
                "durationMs": formatMs(totalMs),
                "persistMs": formatMs(persistMs),
                "layoutMs": formatMs(layoutMs),
                "focusMs": formatMs(focusMs)
            ]
        ))

        return StageCommandResult(
            message: "stage switch \(stageID.rawValue): hidden=\(transition.hiddenWindowIDs.count) shown=\(transition.targetMembers.count) applied=\(applied) layout=\(layoutAttempted)",
            changed: transition.previousID != stageID || applied > 0 || layoutAttempted > 0
        )
    }

    // Plein écran = signalé par macOS (`isNativeFullscreen`) ou zoom posé par `toggleFullscreen`
    // dans l'intent de la stage cible. La taille seule ne compte plus (FR-001).
    // O(m) - m = nombre de membres de la stage.
    private func targetFullscreenMemberID(
        in stage: PersistentStage?,
        scope: StageScope,
        windowsByID: [WindowID: WindowSnapshot],
        preferredWindowID: WindowID?
    ) -> WindowID? {
        guard let stage else { return nil }
        let zoomedWindowID = service.commandLayoutIntent(scope: scope)?.zoomedWindowID
        let fullscreenIDs = stage.members.compactMap { member -> WindowID? in
            guard let window = windowsByID[member.windowID] else { return nil }
            if window.furniture?.isNativeFullscreen == true || member.windowID == zoomedWindowID {
                return member.windowID
            }
            return nil
        }
        if let preferredWindowID, fullscreenIDs.contains(preferredWindowID) {
            return preferredWindowID
        }
        return fullscreenIDs.first
    }

    private func preferredMissingFocusMember(in stage: PersistentStage?) -> PersistentStageMember? {
        guard let stage else { return nil }
        let candidates = stage.members.filter { member in
            !member.bundleID.isEmpty && member.presentationState != .maximized
        }
        if let focusedWindowID = stage.focusedWindowID,
           let member = candidates.first(where: { $0.windowID == focusedWindowID }) {
            return member
        }
        return candidates.max { lhs, rhs in
            (lhs.lastSeenAt ?? .distantPast) < (rhs.lastSeenAt ?? .distantPast)
        }
    }

    /// Frames de masquage des fenêtres `ids` vivantes, sur l'écran de la commande. O(k).
    private func hiddenFrames(
        _ ids: Set<WindowID>,
        windowsByID: [WindowID: WindowSnapshot],
        display: DisplaySnapshot,
        displays: [DisplaySnapshot]
    ) -> [WindowID: CGRect] {
        Dictionary(uniqueKeysWithValues: ids.compactMap { id in
            windowsByID[id].map { (id, HiddenWindowPlacement.frame(for: $0.frame.cgRect, on: display, among: displays)) }
        })
    }

    private func elapsedMs(since start: Date) -> Double {
        Date().timeIntervalSince(start) * 1000
    }

    /// Sans `scopes`, la commande suspend tout le maintien ; avec, seulement ces scopes (FR-040).
    private func beginLayoutCommand(_ reason: String, scopes: Set<StageScope> = []) {
        commandActivity.markActive(reason: reason, scopes: scopes)
    }

    private func finishLayoutCommand(_ reason: String, scopes: Set<StageScope> = []) {
        commandActivity.finish(reason: reason, scopes: scopes)
    }

    private func formatMs(_ value: Double) -> String {
        String(format: "%.1f", value)
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

    private func relayoutActiveSourceScopes(
        _ scopes: [StageScope],
        excluding excludedScope: StageScope,
        from snapshot: DaemonSnapshot,
        generation: UInt64
    ) -> (plan: ApplyPlan, result: ApplyResult) {
        let activeScopes = Set(scopes.filter { scope in
            scope != excludedScope && snapshot.state.activeScope(on: scope.displayID) == scope
        })
        guard !activeScopes.isEmpty else {
            return (ApplyPlan(commands: []), ApplyResult.empty)
        }

        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0) })
        let plan = ApplyPlan(commands: service.applyPlan(from: snapshot).commands.filter { command in
            guard let scope = windowsByID[command.window.id]?.scope else { return false }
            return activeScopes.contains(scope)
        })
        let result = service.apply(plan, generation: generation)
        if result.failed == 0 && result.clamped == 0 {
            let refreshed = service.snapshot(followFocus: false)
            for scope in activeScopes {
                _ = service.saveCurrentLayoutIntentIfValid(scope: scope, from: refreshed)
            }
        }
        return (plan, result)
    }

    private func activeScope(displayID: DisplayID, in state: inout PersistentStageState) -> PersistentStageScope {
        state.scope(
            displayID: displayID,
            desktopID: state.currentDesktopID(for: displayID),
            defaultMode: config.tiling.defaultStrategy
        )
    }

    private func stageID(atVisiblePosition position: Int, in scope: PersistentStageScope, liveWindowIDs: Set<WindowID>) -> StageID? {
        let visible = visibleStageIDs(in: scope, liveWindowIDs: liveWindowIDs)
        let ordered = visible.isEmpty ? selectableStageIDs(in: scope) : visible
        let index = position - 1
        guard ordered.indices.contains(index) else { return nil }
        return ordered[index]
    }

    private func stageID(atAssignablePosition position: Int, in scope: PersistentStageScope) -> StageID? {
        let candidates = scope.stages.filter(isSelectableStage)
        let visible = candidates.filter { !$0.members.isEmpty }.map(\.id)
        let remaining = candidates.map(\.id).filter { !visible.contains($0) }
        let ordered = visible + remaining
        let index = position - 1
        guard ordered.indices.contains(index) else { return nil }
        return ordered[index]
    }

    private func visibleStageIDs(in scope: PersistentStageScope, liveWindowIDs: Set<WindowID>) -> [StageID] {
        scope.stages
            .filter { stage in
                isSelectableStage(stage)
                    && stage.members.contains { liveWindowIDs.contains($0.windowID) }
            }
            .map(\.id)
    }

    private func selectableStageIDs(in scope: PersistentStageScope) -> [StageID] {
        let ids = scope.stages.filter(isSelectableStage).map(\.id)
        return ids.isEmpty ? scope.stages.map(\.id) : ids
    }

    private func isSelectableStage(_ stage: PersistentStage) -> Bool {
        stage.parkingState != .parked || !stage.members.isEmpty
    }

    private func liveWindowIDs(in snapshot: DaemonSnapshot) -> Set<WindowID> {
        Set(snapshot.windows.compactMap { $0.window.isTileCandidate ? $0.window.id : nil })
    }

    private func nextEmptyStageID(in scope: PersistentStageScope) -> StageID {
        if let empty = scope.stages.first(where: { isSelectableStage($0) && $0.members.isEmpty && !isCustomStageName($0.name, id: $0.id) }) {
            return empty.id
        }
        return nextGeneratedStageID(in: scope)
    }

    private func nextGeneratedStageID(in scope: PersistentStageScope) -> StageID {
        let numericIDs = scope.stages.compactMap { Int($0.id.rawValue) }
        let next = (numericIDs.max() ?? scope.stages.count) + 1
        return StageID(rawValue: String(next))
    }

    private func isCustomStageName(_ name: String, id: StageID) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed != "Stage \(id.rawValue)"
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

    private func isolateInfeasibleClampedScope(
        _ scope: StageScope,
        result: ApplyResult,
        snapshot: DaemonSnapshot,
        keepWindowID: WindowID,
        generation: UInt64
    ) -> Int {
        let clampedItems = result.items.filter { $0.status == .clamped && $0.actual != nil }
        guard clampedItems.count >= 2,
              let display = snapshot.displays.first(where: { $0.id == scope.displayID })
        else { return 0 }

        let entries = snapshot.windows.filter { entry in
            entry.scope == scope
                && entry.window.isTileCandidate
                && entry.window.isOnScreen
                && !HiddenWindowPlacement.isHiddenOrLegacyOffscreen(entry.window.frame.cgRect, in: snapshot.displays)
        }
        guard entries.count > 1 else { return 0 }

        // Faisabilité : implémentation unique du tiler (tailles minimales révélées par les refus).
        var minimumSizes = Dictionary(uniqueKeysWithValues: entries.map {
            ($0.window.id, CGSize(width: LayoutTolerance.minimumTileSide, height: LayoutTolerance.minimumTileSide))
        })
        for item in clampedItems {
            if let actual = item.actual, minimumSizes[item.windowID] != nil {
                minimumSizes[item.windowID] = LayoutMaintainer.minimumSize(requested: item.requested, actual: actual)
            }
        }
        guard LayoutMaintainer.minimumSizeArrangement(
            entries.compactMap { minimumSizes[$0.window.id] },
            in: display.visibleFrame.cgRect,
            innerGap: CGFloat(config.tiling.gapsInner)
        ) == nil else { return 0 }

        var applied = 0
        var hiddenIDs: [String] = []
        for entry in entries where entry.window.id != keepWindowID {
            let frame = HiddenWindowPlacement.frame(for: entry.window.frame.cgRect, on: display, among: snapshot.displays)
            if service.setFrame(frame, of: entry.window, generation: generation) != nil {
                applied += 1
                hiddenIDs.append(String(entry.window.id.rawValue))
            }
        }
        guard !hiddenIDs.isEmpty else { return 0 }
        events.append(RoadieEvent(type: "layout_infeasible_scope_isolated", scope: scope, details: [
            "keptWindowID": String(keepWindowID.rawValue),
            "hiddenWindowIDs": hiddenIDs.sorted().joined(separator: ","),
            "reason": "stage_command_clamped_minimums_exceed_visible_frame"
        ]))
        return applied
    }

    private func visibleFrame(for frame: CGRect, on display: DisplaySnapshot) -> CGRect? {
        let visible = display.visibleFrame.cgRect
        let overlap = frame.intersection(visible)
        let minimumVisibleWidth = min(
            LayoutTolerance.usableVisibleWidthMaximum,
            max(LayoutTolerance.usableVisibleMinimum, frame.width * LayoutTolerance.usableVisibleFraction)
        )
        let minimumVisibleHeight = min(
            LayoutTolerance.usableVisibleHeightMaximum,
            max(LayoutTolerance.usableVisibleMinimum, frame.height * LayoutTolerance.usableVisibleFraction)
        )
        let frameCenter = CGPoint(x: frame.midX, y: frame.midY)
        let isUsable = visible.contains(frameCenter)
            && overlap.width >= minimumVisibleWidth
            && overlap.height >= minimumVisibleHeight
        guard !isUsable else { return nil }

        let width = min(frame.width, visible.width)
        let height = min(frame.height, visible.height)
        return CGRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        ).integral
    }

    private func centeredFrame(_ frame: CGRect, in container: CGRect) -> CGRect {
        CGRect(
            x: container.midX - frame.width / 2,
            y: container.midY - frame.height / 2,
            width: frame.width,
            height: frame.height
        ).integral
    }
}

public enum StageCycleDirection: String, Sendable {
    case prev
    case next
}
