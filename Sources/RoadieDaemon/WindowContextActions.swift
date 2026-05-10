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

    public init(
        snapshotService: SnapshotService = SnapshotService(),
        stageStore: StageStore = StageStore(),
        eventLog: EventLog = EventLog()
    ) {
        self.snapshotService = snapshotService
        self.stageStore = stageStore
        self.eventLog = eventLog
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

    private func stageDestinations(in snapshot: DaemonSnapshot, scope: StageScope) -> [WindowDestination] {
        let persistent = stageStore.state()
        if let persistentScope = persistent.scopes.first(where: { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID }) {
            return persistentScope.stages
                .sorted { $0.id < $1.id }
                .map { stage in
                    let name = stage.name.isEmpty ? "Stage \(stage.id.rawValue)" : stage.name
                    return WindowDestination(
                        kind: .stage,
                        id: stage.id.rawValue,
                        label: name,
                        isCurrent: stage.id == scope.stageID
                    )
                }
        }

        guard let desktop = snapshot.state.desktop(displayID: scope.displayID, desktopID: scope.desktopID) else { return [] }
        return desktop.stages.values
            .sorted { $0.id < $1.id }
            .map { stage in
                let name = stage.name.isEmpty ? "Stage \(stage.id.rawValue)" : stage.name
                return WindowDestination(
                    kind: .stage,
                    id: stage.id.rawValue,
                    label: name,
                    isCurrent: stage.id == scope.stageID
                )
            }
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
        return desktopIDs(in: state, displayID: scope.displayID).flatMap { desktopID -> [WindowDestination] in
            let desktopLabel = state.label(displayID: scope.displayID, desktopID: desktopID)
                ?? "Desktop \(desktopID.rawValue)"
            return stages(in: state, snapshot: snapshot, displayID: scope.displayID, desktopID: desktopID)
                .map { stage in
                    WindowDestination(
                        kind: .desktopStage,
                        id: desktopStageID(desktopID: desktopID, stageID: stage.id),
                        label: stage.name.isEmpty ? "Stage \(stage.id.rawValue)" : stage.name,
                        isCurrent: desktopID == scope.desktopID && stage.id == scope.stageID,
                        parentID: String(desktopID.rawValue),
                        parentLabel: desktopLabel
                    )
                }
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
        stageStore.save(state)

        let targetStageScope = StageScope(displayID: displayID, desktopID: desktopID, stageID: stageID)
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
            return scope.stages.sorted { $0.id < $1.id }
        }
        if let desktop = snapshot.state.desktop(displayID: displayID, desktopID: desktopID) {
            return desktop.stages.values
                .sorted { $0.id < $1.id }
                .map { PersistentStage(id: $0.id, name: $0.name) }
        }
        return [PersistentStage(id: StageID(rawValue: "1"))]
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
