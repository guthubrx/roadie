import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore

public struct DesktopCommandService {
    private let service: SnapshotService
    private let store: StageStore
    private let events: EventLog
    private let commandActivity: LayoutCommandActivity

    public init(
        service: SnapshotService = SnapshotService(),
        store: StageStore = StageStore(),
        events: EventLog = EventLog(),
        commandActivity: LayoutCommandActivity = .shared
    ) {
        self.service = service
        self.store = store
        self.events = events
        self.commandActivity = commandActivity
    }

    public func list() -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "desktop list: no display", changed: false)
        }
        let state = store.state()
        let current = state.currentDesktopID(for: display.id)
        let ids = desktopIDs(for: display.id, in: state)
        var lines = ["ACTIVE\tID\tLABEL\tSTAGES\tWINDOWS"]
        for id in ids {
            let scopes = state.scopes.filter { $0.displayID == display.id && $0.desktopID == id }
            let stageCount = scopes.flatMap(\.stages).count
            let windowCount = scopes.flatMap(\.stages).flatMap(\.members).count
            let label = state.label(displayID: display.id, desktopID: id) ?? "-"
            lines.append("\(id == current ? "*" : "")\t\(id.rawValue)\t\(label)\t\(stageCount)\t\(windowCount)")
        }
        return StageCommandResult(message: lines.joined(separator: "\n"), changed: false)
    }

    public func current() -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "desktop current: no display", changed: false)
        }
        let state = store.state()
        let current = state.currentDesktopID(for: display.id)
        let label = state.label(displayID: display.id, desktopID: current) ?? "-"
        return StageCommandResult(message: "desktop current \(current.rawValue) \(label)", changed: false)
    }

    public func label(_ desktopID: DesktopID, as label: String) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "desktop label: no display", changed: false)
        }
        let state = store.mutate { state in
            _ = state.scope(displayID: display.id, desktopID: desktopID)
            state.setLabel(label, displayID: display.id, desktopID: desktopID)
            return state
        }
        let visibleLabel = state.label(displayID: display.id, desktopID: desktopID) ?? "-"
        return StageCommandResult(message: "desktop label \(desktopID.rawValue) \(visibleLabel)", changed: true)
    }

    public func focus(_ desktopID: DesktopID) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "desktop focus: no display", changed: false)
        }
        return switchDisplay(display, to: desktopID, snapshot: snapshot)
    }

    public func cycle(_ direction: StageCycleDirection) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "desktop \(direction.rawValue): no display", changed: false)
        }
        let state = store.mutate { state in
            for id in (1...6).map({ DesktopID(rawValue: $0) }) {
                _ = state.scope(displayID: display.id, desktopID: id)
            }
            return state
        }
        let ids = desktopIDs(for: display.id, in: state)
        let current = state.currentDesktopID(for: display.id)
        let index = ids.firstIndex(of: current) ?? 0
        let nextIndex: Int
        switch direction {
        case .next:
            nextIndex = (index + 1) % ids.count
        case .prev:
            nextIndex = (index - 1 + ids.count) % ids.count
        }
        return switchDisplay(display, to: ids[nextIndex], snapshot: snapshot)
    }

    public func last() -> StageCommandResult {
        let snapshot = service.snapshot(followFocus: false)
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "desktop last: no display", changed: false)
        }
        let state = store.state()
        guard let last = state.lastDesktopID(for: display.id) else {
            return StageCommandResult(message: "desktop last: none", changed: false)
        }
        return switchDisplay(display, to: last, snapshot: snapshot)
    }

    public func backAndForth() -> StageCommandResult {
        last()
    }

    public func summon(_ desktopID: DesktopID) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "desktop summon: no display", changed: false)
        }
        return switchDisplay(display, to: desktopID, snapshot: snapshot)
    }

    public func assignActiveWindow(to desktopID: DesktopID, follow: Bool = false) -> StageCommandResult {
        beginLayoutCommand("desktop.assign_active_window")
        defer { finishLayoutCommand("desktop.assign_active_window") }
        let snapshot = service.snapshot()
        guard let active = activeWindow(in: snapshot),
              let displayID = active.scope?.displayID ?? displayID(containing: active.window.frame.center, in: snapshot.displays),
              let display = snapshot.displays.first(where: { $0.id == displayID })
        else {
            return StageCommandResult(message: "window desktop \(desktopID.rawValue): no active window", changed: false)
        }

        let sourceScope = active.scope
        let stageManager = ConfigReloadService.shared.currentConfig().stageManager
        let (targetStageScope, removedPin) = store.mutate { state -> (StageScope, PersistentWindowPin?) in
            var targetScope = state.scope(displayID: displayID, desktopID: desktopID)
            targetScope.applyConfiguredStages(stageManager)
            for scopeIndex in state.scopes.indices {
                state.scopes[scopeIndex].remove(windowID: active.window.id)
            }
            targetScope.assign(window: active.window, to: targetScope.activeStageID)
            state.update(targetScope)
            let targetStageScope = StageScope(displayID: displayID, desktopID: desktopID, stageID: targetScope.activeStageID)
            let removedPin = sourceScope == targetStageScope ? nil : state.removePin(windowID: active.window.id)
            if sourceScope != targetStageScope {
                state.suppressRulePlacement(window: active.window)
            }
            return (targetStageScope, removedPin)
        }

        if let sourceScope {
            service.removeLayoutIntent(scope: sourceScope)
        }
        service.removeLayoutIntent(scope: targetStageScope)

        if follow {
            return switchDisplay(display, to: desktopID, snapshot: snapshot)
        }

        let hidden = service.setFrame(HiddenWindowPlacement.frame(for: active.window.frame.cgRect, on: display, among: snapshot.displays), of: active.window) != nil
        let result = service.apply(service.applyPlan(from: service.snapshot(followFocus: false)))
        events.append(RoadieEvent(
            type: "window_desktop",
            scope: targetStageScope,
            details: [
                "windowID": String(active.window.id.rawValue),
                "follow": String(follow),
                "layout": String(result.attempted),
                "unpinned": String(removedPin != nil),
            ]
        ))
        appendManualPinRemovalEvent(removedPin, targetScope: targetStageScope)
        return StageCommandResult(
            message: "window desktop \(desktopID.rawValue): hidden=\(hidden) layout=\(result.attempted)",
            changed: hidden || result.attempted > 0
        )
    }

    public func assign(
        windowID: WindowID,
        to desktopID: DesktopID,
        displayID: DisplayID,
        follow: Bool = false
    ) -> StageCommandResult {
        beginLayoutCommand("desktop.assign_window")
        defer { finishLayoutCommand("desktop.assign_window") }
        let snapshot = service.snapshot()
        guard let entry = snapshot.windows.first(where: { $0.window.id == windowID }),
              let display = snapshot.displays.first(where: { $0.id == displayID })
        else {
            return StageCommandResult(message: "window desktop \(desktopID.rawValue): window or display unavailable", changed: false)
        }
        guard entry.scope?.desktopID != desktopID || entry.scope?.displayID != displayID else {
            return StageCommandResult(message: "window desktop \(desktopID.rawValue): already on target desktop", changed: false)
        }

        let sourceScope = entry.scope
        let stageManager = ConfigReloadService.shared.currentConfig().stageManager
        let (targetStageScope, removedPin) = store.mutate { state -> (StageScope, PersistentWindowPin?) in
            var targetScope = state.scope(displayID: displayID, desktopID: desktopID)
            targetScope.applyConfiguredStages(stageManager)
            for scopeIndex in state.scopes.indices {
                state.scopes[scopeIndex].remove(windowID: entry.window.id)
            }
            targetScope.assign(window: entry.window, to: targetScope.activeStageID)
            state.update(targetScope)
            let targetStageScope = StageScope(displayID: displayID, desktopID: desktopID, stageID: targetScope.activeStageID)
            let removedPin = state.removePin(windowID: entry.window.id)
            state.suppressRulePlacement(window: entry.window)
            return (targetStageScope, removedPin)
        }

        if let sourceScope {
            service.removeLayoutIntent(scope: sourceScope)
        }
        service.removeLayoutIntent(scope: targetStageScope)

        if follow {
            return switchDisplay(display, to: desktopID, snapshot: snapshot)
        }

        let hidden = service.setFrame(HiddenWindowPlacement.frame(for: entry.window.frame.cgRect, on: display, among: snapshot.displays), of: entry.window) != nil
        let result = service.apply(service.applyPlan(from: service.snapshot(followFocus: false)))
        events.append(RoadieEvent(
            type: "window_desktop",
            scope: targetStageScope,
            details: [
                "windowID": String(entry.window.id.rawValue),
                "follow": String(follow),
                "layout": String(result.attempted),
                "unpinned": String(removedPin != nil),
            ]
        ))
        appendManualPinRemovalEvent(removedPin, targetScope: targetStageScope)
        return StageCommandResult(
            message: "window desktop \(desktopID.rawValue): window=\(windowID.rawValue) hidden=\(hidden) layout=\(result.attempted)",
            changed: hidden || result.attempted > 0
        )
    }

    private func appendManualPinRemovalEvent(_ pin: PersistentWindowPin?, targetScope: StageScope) {
        guard let pin else { return }
        var details = pin.eventDetails
        details["reason"] = "manual_window_move"
        events.append(RoadieEvent(type: "window.pin_removed", scope: targetScope, details: details))
    }

    private func switchDisplay(
        _ display: DisplaySnapshot,
        to desktopID: DesktopID,
        snapshot: DaemonSnapshot
    ) -> StageCommandResult {
        beginLayoutCommand("desktop.switch")
        defer { finishLayoutCommand("desktop.switch") }
        // Préparé hors verrou : config et fenêtres visibles de l'écran (aucune E/S dans `mutate`).
        let stageConfig = ConfigReloadService.shared.currentConfig().stageManager
        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })
        let visibleWindows = windowsByID.values.filter {
            display.frame.cgRect.contains($0.frame.center) && !HiddenWindowPlacement.isHiddenOrLegacyOffscreen($0.frame.cgRect, in: snapshot.displays)
        }

        // Scopes relus et modifiés sous verrou (FR-013) ; le bloc renvoie ce que l'AX fera ensuite.
        let plan = store.mutate { state -> DesktopSwitchPlan? in
            let previousDesktopID = state.currentDesktopID(for: display.id)
            guard previousDesktopID != desktopID else { return nil }
            var previousScope = state.scope(displayID: display.id, desktopID: previousDesktopID)
            var targetScope = state.scope(displayID: display.id, desktopID: desktopID)
            targetScope.applyConfiguredStages(stageConfig)
            for window in visibleWindows {
                previousScope.updateFrame(window: window)
            }
            let previousWindowIDs = Set(previousScope.stages.flatMap { $0.members.map(\.windowID) })
            let targetStage = targetScope.stages.first { $0.id == targetScope.activeStageID }
            let targetWindowIDs = Set(targetStage?.members.map(\.windowID) ?? [])
            let hiddenIDs = previousWindowIDs.subtracting(targetWindowIDs)
            state.update(previousScope)
            state.update(targetScope)
            state.switchDesktop(displayID: display.id, to: desktopID)
            state.protectCommandFocus(
                displayID: display.id,
                desktopID: desktopID,
                stageID: targetScope.activeStageID,
                windowID: targetStage?.focusedWindowID ?? targetStage?.members.last?.windowID,
                staleFocusedWindowID: snapshot.focusedWindowID.flatMap { hiddenIDs.contains($0) ? $0 : nil }
            )
            return DesktopSwitchPlan(
                previousDesktopID: previousDesktopID,
                targetStageID: targetScope.activeStageID,
                hiddenIDs: hiddenIDs,
                targetStage: targetStage
            )
        }
        guard let plan else {
            return StageCommandResult(message: "desktop focus \(desktopID.rawValue): already active", changed: false)
        }
        let targetStage = plan.targetStage
        let targetWindowIDs = Set(targetStage?.members.map(\.windowID) ?? [])

        var applied = 0
        for id in plan.hiddenIDs {
            guard let window = windowsByID[id] else { continue }
            if service.setFrame(HiddenWindowPlacement.frame(for: window.frame.cgRect, on: display, among: snapshot.displays), of: window) != nil {
                applied += 1
            }
        }
        for member in targetStage?.members ?? [] {
            guard let window = windowsByID[member.windowID] else { continue }
            if service.setFrame(member.frame.cgRect, of: window) != nil {
                applied += 1
            }
        }

        let result = service.apply(service.applyPlan(from: service.snapshot(followFocus: false)))
        applied += result.applied + result.clamped
        if let focusedID = targetStage?.focusedWindowID ?? targetStage?.members.last?.windowID,
           let focused = windowsByID[focusedID] {
            _ = service.focus(focused)
        }
        events.append(RoadieEvent(
            type: "desktop_focus",
            scope: StageScope(displayID: display.id, desktopID: desktopID, stageID: plan.targetStageID),
            details: [
                "previousDesktopID": String(plan.previousDesktopID.rawValue),
                "hidden": String(plan.hiddenIDs.count),
                "shown": String(targetWindowIDs.count),
                "applied": String(applied),
                "layout": String(result.attempted)
            ]
        ))

        return StageCommandResult(
            message: "desktop focus \(desktopID.rawValue): hidden=\(plan.hiddenIDs.count) shown=\(targetWindowIDs.count) applied=\(applied) layout=\(result.attempted)",
            changed: true
        )
    }

    private func desktopIDs(for displayID: DisplayID, in state: PersistentStageState) -> [DesktopID] {
        let configured = Set(state.scopes.filter { $0.displayID == displayID }.map(\.desktopID))
        let defaults = Set((1...6).map { DesktopID(rawValue: $0) })
        return Array(configured.union(defaults)).sorted()
    }

    private func activeDisplay(in snapshot: DaemonSnapshot) -> DisplaySnapshot? {
        let state = store.state()
        if let activeDisplayID = state.activeDisplayID,
           let display = snapshot.displays.first(where: { $0.id == activeDisplayID }) {
            return display
        }
        if let focusedID = service.focusedWindowID(),
           let entry = snapshot.windows.first(where: { $0.window.id == focusedID }),
           let displayID = entry.scope?.displayID ?? displayID(containing: entry.window.frame.center, in: snapshot.displays) {
            return snapshot.displays.first { $0.id == displayID }
        }
        return snapshot.displays.first
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
        return snapshot.windows.first { entry in
            guard let scope = entry.scope else { return false }
            return entry.window.isTileCandidate && snapshot.state.activeScope(on: scope.displayID) == scope
        }
    }

    private func displayID(containing point: CGPoint, in displays: [DisplaySnapshot]) -> DisplayID? {
        displays.first { $0.frame.cgRect.contains(point) }?.id
    }

    private func beginLayoutCommand(_ reason: String) {
        commandActivity.markActive(reason: reason)
    }

    private func finishLayoutCommand(_ reason: String) {
        commandActivity.finish(reason: reason)
    }
}

/// Résultat de la transaction de changement de bureau, utilisé par les appels AX qui suivent.
private struct DesktopSwitchPlan {
    var previousDesktopID: DesktopID
    var targetStageID: StageID
    var hiddenIDs: Set<WindowID>
    var targetStage: PersistentStage?
}
