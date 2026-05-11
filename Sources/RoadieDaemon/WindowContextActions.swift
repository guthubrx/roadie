import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages

public struct WindowContextActionResult: Equatable, Sendable {
    public var message: String
    public var changed: Bool

    public init(message: String, changed: Bool) {
        self.message = message
        self.changed = changed
    }
}

public struct WindowContextActions {
    private let snapshotService: SnapshotService
    private let stageStore: StageStore
    private let eventLog: EventLog
    private let stageLabelsVisible: () -> Bool

    public init(
        snapshotService: SnapshotService = SnapshotService(),
        stageStore: StageStore = StageStore(),
        eventLog: EventLog = EventLog(),
        stageLabelsVisible: @escaping () -> Bool = {
            let settings = RailSettings.load().stageLabel
            guard settings.enabled else { return false }
            guard settings.visibilitySeconds > 0 else { return true }
            let runtime = RailRuntimeStateStore().load()
            guard let visibleUntil = runtime.stageLabelsVisibleUntil else { return false }
            let fadeEndsAt = visibleUntil + settings.fadeSeconds
            return Date().timeIntervalSince1970 <= fadeEndsAt
        }
    ) {
        self.snapshotService = snapshotService
        self.stageStore = stageStore
        self.eventLog = eventLog
        self.stageLabelsVisible = stageLabelsVisible
    }

    public func destinations(
        for windowID: WindowID,
        in snapshot: DaemonSnapshot,
        settings: TitlebarContextMenuSettings
    ) -> [WindowDestination] {
        guard let entry = snapshot.windows.first(where: { $0.window.id == windowID }),
              let scope = entry.scope
        else { return [] }

        var result: [WindowDestination] = []
        if settings.includeStageDestinations {
            result.append(contentsOf: stageDestinations(in: snapshot, scope: scope))
        }
        if settings.includeDesktopDestinations {
            result.append(contentsOf: desktopDestinations(in: snapshot, scope: scope))
            result.append(contentsOf: desktopStageDestinations(in: snapshot, scope: scope))
        }
        if settings.includeDisplayDestinations {
            result.append(contentsOf: displayDestinations(in: snapshot, scope: scope))
        }
        return result
    }

    public func execute(_ action: WindowContextAction) -> WindowContextActionResult {
        let snapshot = snapshotService.snapshot()
        guard let entry = snapshot.windows.first(where: { $0.window.id == action.windowID }),
              let scope = entry.scope
        else {
            return WindowContextActionResult(message: "window disappeared", changed: false)
        }

        switch action.kind {
        case .pinDesktop:
            return setPin(window: entry.window, sourceScope: scope, pinScope: .desktop, snapshot: snapshot)
        case .pinAllDesktops:
            return setPin(window: entry.window, sourceScope: scope, pinScope: .allDesktops, snapshot: snapshot)
        case .unpin:
            return removePin(window: entry.window, sourceScope: scope, snapshot: snapshot)
        case .stage:
            guard let destination = stageDestinations(in: snapshot, scope: scope).first(where: { $0.id == action.targetID }),
                  destination.isAvailable,
                  !destination.isCurrent
            else {
                return WindowContextActionResult(message: "stage destination unavailable", changed: false)
            }
            let result = StageCommandService(
                service: snapshotService,
                store: stageStore,
                events: eventLog
            ).assign(windowID: action.windowID, to: action.targetID, displayID: scope.displayID, focusAssignedWindow: false)
            return WindowContextActionResult(message: result.message, changed: result.changed)
        case .desktop:
            guard let desktopID = Int(action.targetID).map(DesktopID.init(rawValue:)),
                  let destination = desktopDestinations(in: snapshot, scope: scope).first(where: { $0.id == action.targetID }),
                  destination.isAvailable,
                  !destination.isCurrent
            else {
                return WindowContextActionResult(message: "desktop destination unavailable", changed: false)
            }
            let result = DesktopCommandService(
                service: snapshotService,
                store: stageStore,
                events: eventLog
            ).assign(windowID: action.windowID, to: desktopID, displayID: scope.displayID, follow: false)
            return WindowContextActionResult(message: result.message, changed: result.changed)
        case .desktopStage:
            guard let targetScope = parseDesktopStageID(action.targetID),
                  let destination = desktopStageDestinations(in: snapshot, scope: scope).first(where: { $0.id == action.targetID }),
                  destination.isAvailable,
                  !destination.isCurrent
            else {
                return WindowContextActionResult(message: "desktop/stage destination unavailable", changed: false)
            }
            let result = assign(
                windowID: action.windowID,
                to: targetScope.stageID,
                desktopID: targetScope.desktopID,
                displayID: scope.displayID
            )
            return WindowContextActionResult(message: result.message, changed: result.changed)
        case .display:
            guard let destination = displayDestinations(in: snapshot, scope: scope).first(where: { $0.id == action.targetID }),
                  destination.isAvailable,
                  !destination.isCurrent
            else {
                return WindowContextActionResult(message: "display destination unavailable", changed: false)
            }
            let result = WindowCommandService(
                service: snapshotService,
                stageStore: stageStore,
                events: eventLog
            ).send(windowID: action.windowID, toDisplayID: DisplayID(rawValue: action.targetID), focusMovedWindow: false)
            return WindowContextActionResult(message: result.message, changed: result.changed)
        }
    }

    private func setPin(
        window: WindowSnapshot,
        sourceScope: StageScope,
        pinScope: WindowPinScope,
        snapshot: DaemonSnapshot
    ) -> WindowContextActionResult {
        var state = stageStore.state()
        let homeScope = snapshot.state.activeScope(on: sourceScope.displayID) ?? sourceScope
        let mutation = state.setPin(window: window, homeScope: homeScope, pinScope: pinScope)
        stageStore.save(state)

        let eventType = mutation.created ? "window.pin_added" : (mutation.scopeChanged ? "window.pin_scope_changed" : "window.pin_added")
        eventLog.append(RoadieEvent(
            type: eventType,
            scope: mutation.pin.homeScope,
            details: pinEventDetails(mutation.pin)
        ))

        let scopeLabel = pinScope == .desktop ? "ce desktop" : "tous les desktops"
        return WindowContextActionResult(message: "pin \(scopeLabel): window=\(window.id.rawValue)", changed: true)
    }

    private func removePin(
        window: WindowSnapshot,
        sourceScope: StageScope,
        snapshot: DaemonSnapshot
    ) -> WindowContextActionResult {
        var state = stageStore.state()
        guard let removed = state.removePin(windowID: window.id) else {
            return WindowContextActionResult(message: "window is not pinned", changed: false)
        }

        let targetScope = snapshot.state.activeScope(on: removed.homeScope.displayID)
        let target = removed.visibility(in: targetScope).shouldBeVisible ? (targetScope ?? sourceScope) : removed.homeScope
        for scopeIndex in state.scopes.indices {
            state.scopes[scopeIndex].remove(windowID: window.id)
        }
        var persistentScope = state.scope(displayID: target.displayID, desktopID: target.desktopID)
        persistentScope.ensureStage(target.stageID)
        persistentScope.assign(window: window, to: target.stageID)
        state.update(persistentScope)
        stageStore.save(state)

        eventLog.append(RoadieEvent(
            type: "window.pin_removed",
            scope: target,
            details: pinEventDetails(removed)
        ))
        return WindowContextActionResult(message: "pin removed: window=\(window.id.rawValue)", changed: true)
    }

    private func pinEventDetails(_ pin: PersistentWindowPin) -> [String: String] {
        [
            "windowID": String(pin.windowID.rawValue),
            "bundleID": pin.bundleID,
            "title": pin.title,
            "pinScope": pin.pinScope.rawValue,
            "displayID": pin.homeScope.displayID.rawValue,
            "desktopID": String(pin.homeScope.desktopID.rawValue),
            "stageID": pin.homeScope.stageID.rawValue
        ]
    }

    private func stageDestinations(in snapshot: DaemonSnapshot, scope: StageScope) -> [WindowDestination] {
        let persistent = stageStore.state()
        let showLabels = stageLabelsVisible()
        if let persistentScope = persistent.scopes.first(where: { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID }) {
            var destinations = persistentScope.stages
                .filter { isVisibleDestination($0, includeNamedEmpty: showLabels) }
                .enumerated()
                .map { index, stage in
                    WindowDestination(
                        kind: .stage,
                        id: stage.id.rawValue,
                        label: stageLabel(stage, position: index + 1),
                        isCurrent: stage.id == scope.stageID
                    )
                }
            if let nextEmpty = nextEmptyStageID(in: persistentScope.stages) {
                destinations.append(WindowDestination(
                    kind: .stage,
                    id: nextEmpty.rawValue,
                    label: "Prochaine stage vide",
                    isCurrent: false
                ))
            }
            return destinations
        }

        guard let desktop = snapshot.state.desktop(displayID: scope.displayID, desktopID: scope.desktopID) else { return [] }
        var destinations = desktop.stages.values
            .sorted { $0.id < $1.id }
            .filter { !$0.windowIDs.isEmpty || (showLabels && isCustomStageName($0.name, id: $0.id)) }
            .enumerated()
            .map { index, stage in
                WindowDestination(
                    kind: .stage,
                    id: stage.id.rawValue,
                    label: stageLabel(PersistentStage(id: stage.id, name: stage.name), position: index + 1),
                    isCurrent: stage.id == scope.stageID
                )
            }
        if let nextEmpty = nextEmptyStageID(in: desktop.stages.values.map { PersistentStage(id: $0.id, name: $0.name) }) {
            destinations.append(WindowDestination(
                kind: .stage,
                id: nextEmpty.rawValue,
                label: "Prochaine stage vide",
                isCurrent: false
            ))
        }
        return destinations
    }

    private func desktopDestinations(in snapshot: DaemonSnapshot, scope: StageScope) -> [WindowDestination] {
        let state = stageStore.state()
        let configured = Set(state.scopes.filter { $0.displayID == scope.displayID }.map(\.desktopID))
        let defaults = Set((1...6).map { DesktopID(rawValue: $0) })
        return Array(configured.union(defaults)).sorted().map { desktopID in
            let label = state.label(displayID: scope.displayID, desktopID: desktopID)
                ?? "Desktop \(desktopID.rawValue)"
            return WindowDestination(
                kind: .desktop,
                id: String(desktopID.rawValue),
                label: label,
                isCurrent: desktopID == scope.desktopID
            )
        }
    }

    private func desktopStageDestinations(in snapshot: DaemonSnapshot, scope: StageScope) -> [WindowDestination] {
        let state = stageStore.state()
        let showLabels = stageLabelsVisible()
        return desktopIDs(in: state, displayID: scope.displayID).flatMap { desktopID -> [WindowDestination] in
            let desktopLabel = state.label(displayID: scope.displayID, desktopID: desktopID)
                ?? "Desktop \(desktopID.rawValue)"
            let stageList = stages(in: state, snapshot: snapshot, displayID: scope.displayID, desktopID: desktopID)
            var destinations = stageList
                .filter { isVisibleDestination($0, includeNamedEmpty: showLabels) }
                .enumerated()
                .map { index, stage in
                    WindowDestination(
                        kind: .desktopStage,
                        id: desktopStageID(desktopID: desktopID, stageID: stage.id),
                        label: stageLabel(stage, position: index + 1),
                        isCurrent: desktopID == scope.desktopID && stage.id == scope.stageID,
                        parentID: String(desktopID.rawValue),
                        parentLabel: desktopLabel
                    )
                }
            if let nextEmpty = nextEmptyStageID(in: stageList) {
                destinations.append(WindowDestination(
                    kind: .desktopStage,
                    id: desktopStageID(desktopID: desktopID, stageID: nextEmpty),
                    label: "Prochaine stage vide",
                    isCurrent: false,
                    parentID: String(desktopID.rawValue),
                    parentLabel: desktopLabel
                ))
            }
            return destinations
        }
    }

    private func displayDestinations(in snapshot: DaemonSnapshot, scope: StageScope) -> [WindowDestination] {
        snapshot.displays.sorted { $0.index < $1.index }.map { display in
            WindowDestination(
                kind: .display,
                id: display.id.rawValue,
                label: "Ecran \(display.index) - \(display.name)",
                isCurrent: display.id == scope.displayID
            )
        }
    }

    private func assign(
        windowID: WindowID,
        to stageID: StageID,
        desktopID: DesktopID,
        displayID: DisplayID
    ) -> StageCommandResult {
        let snapshot = snapshotService.snapshot()
        guard let display = snapshot.displays.first(where: { $0.id == displayID }) else {
            return StageCommandResult(message: "desktop/stage assign: unknown display", changed: false)
        }
        var state = stageStore.state()
        guard let window = snapshot.windows.first(where: { $0.window.id == windowID })?.window else {
            for scopeIndex in state.scopes.indices {
                state.scopes[scopeIndex].remove(windowID: windowID)
            }
            stageStore.save(state)
            return StageCommandResult(message: "desktop/stage assign: stale window pruned", changed: true)
        }

        for scopeIndex in state.scopes.indices {
            state.scopes[scopeIndex].remove(windowID: windowID)
        }
        var targetScope = state.scope(displayID: displayID, desktopID: desktopID)
        targetScope.applyConfiguredStages((try? RoadieConfigLoader.load())?.stageManager ?? StageManagerConfig())
        targetScope.ensureStage(stageID)
        targetScope.assign(window: window, to: stageID)
        state.update(targetScope)
        let targetStageScope = StageScope(displayID: displayID, desktopID: desktopID, stageID: stageID)
        state.updatePinHomeScope(windowID: windowID, to: targetStageScope)
        stageStore.save(state)

        snapshotService.removeLayoutIntent(scope: targetStageScope)
        _ = snapshotService.setFrame(hiddenFrame(for: window.frame.cgRect, on: display, among: snapshot.displays), of: window)
        let result = snapshotService.apply(snapshotService.applyPlan(from: snapshotService.snapshot()))
        eventLog.append(RoadieEvent(
            type: "stage_assign_window",
            scope: targetStageScope,
            details: [
                "stageID": stageID.rawValue,
                "desktopID": String(desktopID.rawValue),
                "windowID": String(windowID.rawValue),
                "layout": String(result.attempted),
                "focus": "false"
            ]
        ))
        return StageCommandResult(
            message: "desktop/stage assign \(desktopID.rawValue)/\(stageID.rawValue): window=\(windowID.rawValue) layout=\(result.attempted)",
            changed: true
        )
    }

    private func desktopIDs(in state: PersistentStageState, displayID: DisplayID) -> [DesktopID] {
        let configured = Set(state.scopes.filter { $0.displayID == displayID }.map(\.desktopID))
        let defaults = Set((1...6).map { DesktopID(rawValue: $0) })
        return Array(configured.union(defaults)).sorted()
    }

    private func stages(
        in state: PersistentStageState,
        snapshot: DaemonSnapshot,
        displayID: DisplayID,
        desktopID: DesktopID
    ) -> [PersistentStage] {
        if let scope = state.scopes.first(where: { $0.displayID == displayID && $0.desktopID == desktopID }) {
            return scope.stages
        }
        if let desktop = snapshot.state.desktop(displayID: displayID, desktopID: desktopID) {
            return desktop.stages.values
                .sorted { $0.id < $1.id }
                .map { stage in
                    PersistentStage(
                        id: stage.id,
                        name: stage.name,
                        members: stage.windowIDs.map {
                            PersistentStageMember(windowID: $0, bundleID: "", title: "", frame: Rect(x: 0, y: 0, width: 0, height: 0))
                        }
                    )
                }
        }
        return [PersistentStage(id: StageID(rawValue: "1"))]
    }

    private func stageLabel(_ stage: PersistentStage, position: Int) -> String {
        let trimmed = stage.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let generatedName = "Stage \(stage.id.rawValue)"
        return trimmed.isEmpty || trimmed == generatedName ? "Stage \(position)" : trimmed
    }

    private func isVisibleDestination(_ stage: PersistentStage, includeNamedEmpty: Bool) -> Bool {
        !stage.members.isEmpty || (includeNamedEmpty && isCustomStageName(stage.name, id: stage.id))
    }

    private func isCustomStageName(_ name: String, id: StageID) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "Stage \(id.rawValue)"
    }

    private func nextEmptyStageID(in stages: [PersistentStage]) -> StageID? {
        if let empty = stages.first(where: { $0.members.isEmpty && !isCustomStageName($0.name, id: $0.id) }) {
            return empty.id
        }
        let used = Set(stages.map(\.id.rawValue))
        for index in 1...99 where !used.contains(String(index)) {
            return StageID(rawValue: String(index))
        }
        return StageID(rawValue: UUID().uuidString)
    }

    private func desktopStageID(desktopID: DesktopID, stageID: StageID) -> String {
        "\(desktopID.rawValue):\(stageID.rawValue)"
    }

    private func parseDesktopStageID(_ raw: String) -> (desktopID: DesktopID, stageID: StageID)? {
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let desktop = Int(parts[0]) else { return nil }
        return (DesktopID(rawValue: desktop), StageID(rawValue: parts[1]))
    }

    private func hiddenFrame(for frame: CGRect, on display: DisplaySnapshot, among displays: [DisplaySnapshot]) -> CGRect {
        let visible = display.visibleFrame.cgRect
        return CGRect(x: visible.maxX - 1, y: visible.maxY - 1, width: frame.width, height: frame.height).integral
    }
}
