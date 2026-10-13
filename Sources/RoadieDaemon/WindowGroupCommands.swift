import Foundation
import RoadieAX
import RoadieCore
import RoadieStages

public struct WindowGroupCommandResult: Equatable, Sendable {
    public var message: String
    public var changed: Bool
}

public struct WindowGroupCommandService {
    private let service: SnapshotService
    private let store: StageStore
    private let events: EventLog

    public init(service: SnapshotService = SnapshotService(), store: StageStore = StageStore(), events: EventLog = EventLog()) {
        self.service = service
        self.store = store
        self.events = events
    }

    public func list() -> WindowGroupCommandResult {
        let state = store.state()
        var lines = ["SCOPE\tGROUP\tACTIVE\tMEMBERS"]
        for scope in state.scopes {
            for stage in scope.stages {
                let scopeID = StageScope(displayID: scope.displayID, desktopID: scope.desktopID, stageID: stage.id)
                for group in stage.groups {
                    lines.append("\(scopeID.description)\t\(group.id)\t\(group.activeWindowID?.description ?? "-")\t\(group.windowIDs.map(\.description).joined(separator: ","))")
                }
            }
        }
        return WindowGroupCommandResult(message: lines.joined(separator: "\n"), changed: false)
    }

    public func create(id: String, windowIDs: [WindowID]) -> WindowGroupCommandResult {
        mutateGroup(id: id, createIfMissing: true) { group in
            for windowID in windowIDs {
                group.add(windowID)
            }
        }
    }

    public func add(windowID: WindowID, to id: String) -> WindowGroupCommandResult {
        mutateGroup(id: id, createIfMissing: true) { $0.add(windowID) }
    }

    public func remove(windowID: WindowID, from id: String) -> WindowGroupCommandResult {
        mutateGroup(id: id, createIfMissing: false) { $0.remove(windowID) }
    }

    public func focus(windowID: WindowID, in id: String) -> WindowGroupCommandResult {
        mutateGroup(id: id, createIfMissing: false) { _ = $0.focus(windowID) }
    }

    public func dissolve(id: String) -> WindowGroupCommandResult {
        let removed: Bool
        do {
            removed = try store.mutateChecked { state in
                var removed = false
                for scopeIndex in state.scopes.indices {
                    for stageIndex in state.scopes[scopeIndex].stages.indices {
                        let before = state.scopes[scopeIndex].stages[stageIndex].groups.count
                        state.scopes[scopeIndex].stages[stageIndex].groups.removeAll { $0.id == id }
                        removed = removed || state.scopes[scopeIndex].stages[stageIndex].groups.count != before
                    }
                }
                return removed
            }
        } catch {
            return persistenceFailure("group dissolve \(id)", error)
        }
        if removed {
            events.append(RoadieEvent(type: "window.ungrouped", details: ["groupID": id]))
        }
        return WindowGroupCommandResult(message: removed ? "group dissolve \(id)" : "group dissolve \(id): not found", changed: removed)
    }

    private enum GroupMutation {
        case failed(String)
        case applied(StageScope, WindowGroup)
    }

    private func mutateGroup(id: String, createIfMissing: Bool, mutate: (inout WindowGroup) -> Void) -> WindowGroupCommandResult {
        let snapshot = service.snapshot()
        // Snapshot pris hors transaction ; la modification relit l'état sous verrou (FR-013).
        let outcome: GroupMutation
        do {
            outcome = try store.mutateChecked { state -> GroupMutation in
                guard let scopeID = activeScope(in: snapshot, state: &state) else {
                    return .failed("group \(id): no active scope")
                }
                // `scope(displayID:)` peut créer le scope : en cas d'échec, l'état d'origine est
                // remis pour que la transaction n'écrive rien.
                let original = state
                var scope = state.scope(displayID: scopeID.displayID, desktopID: scopeID.desktopID)
                guard let stageIndex = scope.stages.firstIndex(where: { $0.id == scopeID.stageID }) else {
                    state = original
                    return .failed("group \(id): no active stage")
                }
                var group = scope.stages[stageIndex].groups.first { $0.id == id } ?? WindowGroup(id: id)
                if group.windowIDs.isEmpty && !createIfMissing && !scope.stages[stageIndex].groups.contains(where: { $0.id == id }) {
                    state = original
                    return .failed("group \(id): not found")
                }
                mutate(&group)
                scope.stages[stageIndex].groups.removeAll { $0.id == id }
                if group.windowIDs.count >= 2 || createIfMissing {
                    scope.stages[stageIndex].groups.append(group)
                }
                state.update(scope)
                return .applied(scopeID, group)
            }
        } catch {
            return persistenceFailure("group \(id)", error)
        }
        let scopeID: StageScope
        let group: WindowGroup
        switch outcome {
        case .failed(let message):
            return WindowGroupCommandResult(message: message, changed: false)
        case .applied(let appliedScope, let appliedGroup):
            scopeID = appliedScope
            group = appliedGroup
        }
        events.append(RoadieEvent(
            type: createIfMissing ? "window.grouped" : "window.ungrouped",
            scope: scopeID,
            details: ["groupID": id, "members": group.windowIDs.map(\.description).joined(separator: ",")]
        ))
        return WindowGroupCommandResult(message: "group \(id): members=\(group.windowIDs.map(\.description).joined(separator: ","))", changed: true)
    }

    /// État du groupe non persisté (REL-021) : aucun événement ; « failed » donne au CLI un code
    /// de sortie non nul.
    private func persistenceFailure(_ command: String, _ error: Error) -> WindowGroupCommandResult {
        WindowGroupCommandResult(message: JSONPersistence.commandFailureMessage(command, error), changed: false)
    }

    private func activeScope(in snapshot: DaemonSnapshot, state: inout PersistentStageState) -> StageScope? {
        if let activeDisplayID = state.activeDisplayID,
           let scope = snapshot.state.activeScope(on: activeDisplayID) {
            return scope
        }
        guard let display = snapshot.displays.first else { return nil }
        return snapshot.state.activeScope(on: display.id)
    }
}
