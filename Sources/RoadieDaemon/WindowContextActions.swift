import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages

public struct WindowContextActionResult: CommandResult, Equatable, Sendable {
    public var message: String
    public var changed: Bool
    /// Statut explicite (REL-042). Sans valeur donnée : `.changed` si `changed`, sinon nil
    /// (statut non posé, code de sortie lu dans le message).
    public var outcome: CommandOutcome?

    public init(message: String, changed: Bool, outcome: CommandOutcome? = nil) {
        self.message = message
        self.changed = changed
        self.outcome = outcome ?? (changed ? .changed : nil)
    }
}

public struct WindowContextActions {
    private let snapshotService: SnapshotService
    private let stageStore: StageStore
    private let eventLog: EventLog
    private let affinityService: WindowRuleAffinityService

    public init(
        snapshotService: SnapshotService = SnapshotService(),
        stageStore: StageStore = StageStore(),
        eventLog: EventLog = EventLog(),
        affinityService: WindowRuleAffinityService = WindowRuleAffinityService(),
        // Conservé pour la compatibilité des appelants ; le fondu ne filtre plus les destinations.
        stageLabelsVisible: @escaping () -> Bool = { true }
    ) {
        self.snapshotService = snapshotService
        self.stageStore = stageStore
        self.eventLog = eventLog
        self.affinityService = affinityService
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
            return WindowContextActionResult(message: "window disappeared", changed: false, outcome: .noOp)
        }

        switch action.kind {
        case .maximize:
            let result = WindowCommandService(
                service: snapshotService,
                stageStore: stageStore,
                events: eventLog
            ).toggleMaximize(windowID: action.windowID)
            return WindowContextActionResult(message: result.message, changed: result.changed, outcome: result.outcome)
        case .affinityApp:
            return saveAffinity(kind: .app, window: entry.window, scope: scope, snapshot: snapshot)
        case .affinityAppTitle:
            return saveAffinity(kind: .appTitle, window: entry.window, scope: scope, snapshot: snapshot)
        case .removeAffinityApp:
            let result = affinityService.removeAppAffinity(window: entry.window, scope: scope)
            return WindowContextActionResult(message: result.message, changed: result.changed)
        case .floatAlways, .tileAlways, .clearTiling:
            let choice: WindowTilingChoice? = action.kind == .floatAlways ? .float : action.kind == .tileAlways ? .tile : nil
            let result = affinityService.saveTiling(choice, window: entry.window)
            return WindowContextActionResult(message: result.message, changed: result.changed)
        case .floatStage:
            return setPin(window: entry.window, sourceScope: scope, pinScope: .stage, snapshot: snapshot)
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
                return WindowContextActionResult(message: "stage destination unavailable", changed: false, outcome: .failed)
            }
            let result = StageCommandService(
                service: snapshotService,
                store: stageStore,
                events: eventLog
            ).assign(windowID: action.windowID, to: action.targetID, displayID: scope.displayID, focusAssignedWindow: false)
            return WindowContextActionResult(message: result.message, changed: result.changed, outcome: result.outcome)
        case .desktop:
            guard let desktopID = Int(action.targetID).map(DesktopID.init(rawValue:)),
                  let destination = desktopDestinations(in: snapshot, scope: scope).first(where: { $0.id == action.targetID }),
                  destination.isAvailable,
                  !destination.isCurrent
            else {
                return WindowContextActionResult(message: "desktop destination unavailable", changed: false, outcome: .failed)
            }
            let result = DesktopCommandService(
                service: snapshotService,
                store: stageStore,
                events: eventLog
            ).assign(windowID: action.windowID, to: desktopID, displayID: scope.displayID, follow: false)
            return WindowContextActionResult(message: result.message, changed: result.changed, outcome: result.outcome)
        case .desktopStage:
            guard let targetScope = parseDesktopStageID(action.targetID),
                  let destination = desktopStageDestinations(in: snapshot, scope: scope).first(where: { $0.id == action.targetID }),
                  destination.isAvailable,
                  !destination.isCurrent
            else {
                return WindowContextActionResult(message: "desktop/stage destination unavailable", changed: false, outcome: .failed)
            }
            let result = assign(
                windowID: action.windowID,
                to: targetScope.stageID,
                desktopID: targetScope.desktopID,
                displayID: scope.displayID
            )
            return WindowContextActionResult(message: result.message, changed: result.changed, outcome: result.outcome)
        case .display:
            guard let destination = displayDestinations(in: snapshot, scope: scope).first(where: { $0.id == action.targetID }),
                  destination.isAvailable,
                  !destination.isCurrent
            else {
                return WindowContextActionResult(message: "display destination unavailable", changed: false, outcome: .failed)
            }
            let result = WindowCommandService(
                service: snapshotService,
                stageStore: stageStore,
                events: eventLog
            ).send(windowID: action.windowID, toDisplayID: DisplayID(rawValue: action.targetID), focusMovedWindow: false)
            return WindowContextActionResult(message: result.message, changed: result.changed, outcome: result.outcome)
        }
    }

    /// `roadie toggle floating` (SPEC-047) : une fenêtre épinglée, quelle que soit sa portée,
    /// revient au tuilage ; sinon elle flotte dans sa stage. Sans fenêtre désignée, vise la
    /// fenêtre active. Complexité : O(w + p), w fenêtres du relevé, p épinglages.
    public func toggleFloating(windowID: WindowID?) -> WindowContextActionResult {
        let snapshot = snapshotService.snapshot()
        guard let targetID = windowID ?? snapshot.focusedWindowID,
              let entry = snapshot.windows.first(where: { $0.window.id == targetID }),
              let scope = entry.scope
        else {
            return WindowContextActionResult(message: "toggle floating: no managed window", changed: false, outcome: .noOp)
        }
        if entry.pin != nil {
            return removePin(window: entry.window, sourceScope: scope, snapshot: snapshot)
        }
        guard entry.window.isTileCandidate else {
            return WindowContextActionResult(message: "toggle floating: window is not tiled", changed: false, outcome: .noOp)
        }
        return setPin(window: entry.window, sourceScope: scope, pinScope: .stage, snapshot: snapshot)
    }

    private func saveAffinity(
        kind: WindowRuleAffinityKind,
        window: WindowSnapshot,
        scope: StageScope,
        snapshot: DaemonSnapshot
    ) -> WindowContextActionResult {
        guard let display = snapshot.displays.first(where: { $0.id == scope.displayID }) else {
            return WindowContextActionResult(message: "affinite non creee: ecran introuvable", changed: false, outcome: .noOp)
        }
        let result = affinityService.saveAffinity(kind: kind, window: window, scope: scope, display: display)
        return WindowContextActionResult(message: result.message, changed: result.changed)
    }

    private func setPin(
        window: WindowSnapshot,
        sourceScope: StageScope,
        pinScope: WindowPinScope,
        snapshot: DaemonSnapshot
    ) -> WindowContextActionResult {
        let homeScope = snapshot.state.activeScope(on: sourceScope.displayID) ?? sourceScope
        let mutation: PinMutation
        do {
            mutation = try stageStore.mutateChecked { state in
                state.setPin(window: window, homeScope: homeScope, pinScope: pinScope)
            }
        } catch {
            return .persistenceFailure("pin", error)
        }

        let eventType = mutation.created ? "window.pin_added" : (mutation.scopeChanged ? "window.pin_scope_changed" : "window.pin_added")
        eventLog.append(RoadieEvent(
            type: eventType,
            scope: mutation.pin.homeScope,
            details: mutation.pin.eventDetails
        ))

        let scopeLabel: String
        switch pinScope {
        case .stage: scopeLabel = "cette stage (flottante)"
        case .desktop: scopeLabel = "ce desktop"
        case .allDesktops: scopeLabel = "tous les desktops"
        }
        return WindowContextActionResult(message: "pin \(scopeLabel): window=\(window.id.rawValue)", changed: true)
    }

    private func removePin(
        window: WindowSnapshot,
        sourceScope: StageScope,
        snapshot: DaemonSnapshot
    ) -> WindowContextActionResult {
        let removal: (pin: PersistentWindowPin, target: StageScope)?
        do {
            removal = try stageStore.mutateChecked { state -> (pin: PersistentWindowPin, target: StageScope)? in
                guard let removed = state.removePin(windowID: window.id) else { return nil }
                let targetScope = snapshot.state.activeScope(on: removed.homeScope.displayID)
                let target = removed.visibility(in: targetScope).shouldBeVisible ? (targetScope ?? sourceScope) : removed.homeScope
                for scopeIndex in state.scopes.indices {
                    state.scopes[scopeIndex].remove(windowID: window.id)
                }
                var persistentScope = state.scope(displayID: target.displayID, desktopID: target.desktopID)
                persistentScope.ensureStage(target.stageID)
                persistentScope.assign(window: window, to: target.stageID)
                state.update(persistentScope)
                return (removed, target)
            }
        } catch {
            return .persistenceFailure("unpin", error)
        }
        guard let (removed, target) = removal else {
            return WindowContextActionResult(message: "window is not pinned", changed: false, outcome: .noOp)
        }

        eventLog.append(RoadieEvent(
            type: "window.pin_removed",
            scope: target,
            details: removed.eventDetails
        ))
        return WindowContextActionResult(message: "pin removed: window=\(window.id.rawValue)", changed: true)
    }

    private func stageDestinations(in snapshot: DaemonSnapshot, scope: StageScope) -> [WindowDestination] {
        let persistent = stageStore.state()
        let stageList = stages(in: persistent, snapshot: snapshot, displayID: scope.displayID, desktopID: scope.desktopID)
        let persistentScope = PersistentStageScope(displayID: scope.displayID, desktopID: scope.desktopID, stages: stageList)
        let order = StagePresentationOrder(scope: persistentScope, liveWindowIDs: liveWindowIDs(in: snapshot))
        var destinations = order.visibleStages.enumerated().map { index, stage in
                WindowDestination(
                    kind: .stage,
                    id: stage.id.rawValue,
                    label: stageLabel(stage, position: index + 1),
                    isCurrent: stage.id == scope.stageID
                )
            }
        if let nextEmpty = nextEmptyStageID(in: stageList) {
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
        return desktopIDs(in: state, displayID: scope.displayID).flatMap { desktopID -> [WindowDestination] in
            let desktopLabel = state.label(displayID: scope.displayID, desktopID: desktopID)
                ?? "Desktop \(desktopID.rawValue)"
            let stageList = stages(in: state, snapshot: snapshot, displayID: scope.displayID, desktopID: desktopID)
            let represented: [PersistentStage]
            if desktopID == state.currentDesktopID(for: scope.displayID) {
                let targetScope = PersistentStageScope(displayID: scope.displayID, desktopID: desktopID, stages: stageList)
                represented = StagePresentationOrder(scope: targetScope, liveWindowIDs: liveWindowIDs(in: snapshot)).visibleStages
            } else {
                // Les fenêtres des autres Spaces ne sont pas toutes dans le relevé vivant.
                represented = stageList.filter {
                    !$0.members.isEmpty || ($0.parkingState != .parked && StagePresentationOrder.isNamed($0))
                }
            }
            var destinations = represented
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

    /// Aussi utilisé par la vue d'ensemble (SPEC-067) pour une fenêtre déposée sur une stage.
    func assign(
        windowID: WindowID,
        to stageID: StageID,
        desktopID: DesktopID,
        displayID: DisplayID
    ) -> StageCommandResult {
        // Génération ouverte à l'entrée de la commande (A13, T223).
        let generation = PlacementGeneration.shared.next()
        let snapshot = snapshotService.snapshot()
        guard let display = snapshot.displays.first(where: { $0.id == displayID }) else {
            return StageCommandResult(message: "desktop/stage assign: unknown display", changed: false, outcome: .failed)
        }
        guard let window = snapshot.windows.first(where: { $0.window.id == windowID })?.window else {
            do {
                try stageStore.mutateChecked { state in
                    for scopeIndex in state.scopes.indices {
                        state.scopes[scopeIndex].remove(windowID: windowID)
                    }
                }
            } catch {
                return .persistenceFailure("desktop/stage assign", error)
            }
            return StageCommandResult(message: "desktop/stage assign: stale window pruned", changed: true)
        }

        // Config lue hors transaction : le verrou d'état reste tenu le moins longtemps possible.
        let stageManagerConfig = ConfigReloadService.shared.currentConfig().stageManager
        let targetStageScope = StageScope(displayID: displayID, desktopID: desktopID, stageID: stageID)
        let sourceScope = snapshot.windows.first(where: { $0.window.id == windowID })?.scope
        let targetIsVisible: Bool
        do {
            // Affectation écrite puis intent cible retiré ; si ce retrait échoue, l'affectation
            // revient (REL-021) : le refus annoncé ne laisse rien.
            targetIsVisible = try snapshotService.commitStageTransfer(in: stageStore, { state -> Bool in
                for scopeIndex in state.scopes.indices {
                    state.scopes[scopeIndex].remove(windowID: windowID)
                }
                var targetScope = state.scope(displayID: displayID, desktopID: desktopID)
                targetScope.applyConfiguredStages(stageManagerConfig, takenNames: state.namedStageKeys(excludingDisplay: displayID, desktop: desktopID))
                targetScope.ensureStage(stageID)
                targetScope.assign(window: window, to: stageID)
                state.update(targetScope)
                state.updatePinHomeScope(windowID: windowID, to: targetStageScope)
                return state.currentDesktopID(for: displayID) == desktopID && targetScope.activeStageID == stageID
            }, clearingIntentsOf: { _ in [targetStageScope] })
        } catch {
            return .persistenceFailure("desktop/stage assign \(desktopID.rawValue)/\(stageID.rawValue)", error)
        }
        // Plan unique (A15, T223) : masquage (si la cible n'est pas affichée) et disposition des
        // scopes touchés en une écriture groupée. Une cible affichée est posée par la disposition.
        var placement = CommandPlacement(layoutScopes: Set([sourceScope, targetStageScope].compactMap { $0 }))
        if !targetIsVisible {
            placement.hiding[windowID] = HiddenWindowPlacement.frame(for: window.frame.cgRect, on: display, among: snapshot.displays)
        }
        let result = snapshotService.applyCommandPlacement(placement, cause: "window.assign", generation: generation, events: eventLog).result
        // SPEC-081 : déplacement noté pour l'annulation et les règles proposées (rien si même stage).
        LauncherMemoryStore().record(window: window, from: sourceScope, to: targetStageScope)
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
        StagePresentationOrder.menuLabel(stage, position: position)
    }

    private func liveWindowIDs(in snapshot: DaemonSnapshot) -> Set<WindowID> {
        snapshotService.railWindowIDs(in: snapshot)
    }

    private func nextEmptyStageID(in stages: [PersistentStage]) -> StageID? {
        if let empty = stages.first(where: { $0.parkingState != .parked && $0.members.isEmpty && !StagePresentationOrder.isNamed($0) }) {
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

}
