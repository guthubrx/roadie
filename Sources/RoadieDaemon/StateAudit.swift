import Foundation
import RoadieCore

public enum StateAuditLevel: String, Codable, Sendable {
    case ok
    case warn
    case fail
}

public struct StateAuditCheck: Equatable, Codable, Sendable {
    public var level: StateAuditLevel
    public var name: String
    public var message: String

    public init(level: StateAuditLevel, name: String, message: String) {
        self.level = level
        self.name = name
        self.message = message
    }
}

public struct StateAuditReport: Equatable, Codable, Sendable {
    public var checks: [StateAuditCheck]

    public init(checks: [StateAuditCheck]) {
        self.checks = checks
    }

    public var failed: Bool {
        checks.contains { $0.level == .fail }
    }
}

public struct StateHealReport: Equatable, Codable, Sendable {
    public var repaired: Int
    public var audit: StateAuditReport

    public init(repaired: Int, audit: StateAuditReport) {
        self.repaired = repaired
        self.audit = audit
    }
}

public struct StateAuditService {
    private let service: SnapshotService
    private let stageStore: StageStore

    public init(service: SnapshotService = SnapshotService(), stageStore: StageStore = StageStore()) {
        self.service = service
        self.stageStore = stageStore
    }

    public func run() -> StateAuditReport {
        let snapshot = service.snapshot(followExternalFocus: false, persistState: false)
        let state = stageStore.state()
        let liveDisplayIDs = Set(snapshot.displays.map(\.id))
        let liveTileableWindowIDs = Set(snapshot.windows.compactMap { entry in
            entry.window.isTileCandidate ? entry.window.id : nil
        })
        var checks: [StateAuditCheck] = []

        checks.append(activeDisplayCheck(state: state, liveDisplayIDs: liveDisplayIDs))
        checks.append(staleScopesCheck(state: state, liveDisplayIDs: liveDisplayIDs))
        checks.append(staleDesktopSelectionsCheck(state: state, liveDisplayIDs: liveDisplayIDs))
        checks.append(staleDesktopLabelsCheck(state: state, liveDisplayIDs: liveDisplayIDs))
        checks.append(activeStagesCheck(state: state))
        checks.append(focusedMembersCheck(state: state))
        checks.append(duplicateMembershipCheck(state: state))
        checks.append(staleMembersCheck(state: state, liveWindowIDs: liveTileableWindowIDs))

        return StateAuditReport(checks: checks)
    }

    public func heal() -> StateHealReport {
        let snapshot = service.snapshot()
        var state = stageStore.state()
        let liveDisplayIDs = Set(snapshot.displays.map(\.id))
        let liveTileableWindowIDs = Set(snapshot.windows.compactMap { entry in
            entry.window.isTileCandidate ? entry.window.id : nil
        })
        var repaired = 0

        if let fallbackDisplayID = fallbackDisplayID(in: snapshot, state: state) {
            let beforeScopes = state.scopes.count
            state.migrateDisconnectedDisplays(keeping: liveDisplayIDs, fallbackDisplayID: fallbackDisplayID)
            repaired += max(0, beforeScopes - state.scopes.count)
        }

        let beforeSelections = state.desktopSelections.count
        state.desktopSelections.removeAll { !liveDisplayIDs.contains($0.displayID) }
        repaired += beforeSelections - state.desktopSelections.count

        let beforeLabels = state.desktopLabels.count
        state.desktopLabels.removeAll { !liveDisplayIDs.contains($0.displayID) }
        repaired += beforeLabels - state.desktopLabels.count

        if state.activeDisplayID.map({ !liveDisplayIDs.contains($0) }) != false {
            state.activeDisplayID = fallbackDisplayID(in: snapshot, state: state)
            repaired += state.activeDisplayID == nil ? 0 : 1
        }

        repaired += repairScopes(&state, liveWindowIDs: liveTileableWindowIDs)
        stageStore.save(state)
        return StateHealReport(repaired: repaired, audit: run())
    }

    private func activeDisplayCheck(state: PersistentStageState, liveDisplayIDs: Set<DisplayID>) -> StateAuditCheck {
        guard let activeDisplayID = state.activeDisplayID else {
            return StateAuditCheck(level: .warn, name: "active-display", message: "none")
        }
        let live = liveDisplayIDs.contains(activeDisplayID)
        return StateAuditCheck(
            level: live ? .ok : .fail,
            name: "active-display",
            message: "id=\(activeDisplayID.rawValue) live=\(live)"
        )
    }

    private func staleScopesCheck(state: PersistentStageState, liveDisplayIDs: Set<DisplayID>) -> StateAuditCheck {
        let stale = state.scopes.filter { !liveDisplayIDs.contains($0.displayID) }
        return StateAuditCheck(
            level: stale.isEmpty ? .ok : .fail,
            name: "stale-scopes",
            message: "count=\(stale.count)"
        )
    }

    private func staleDesktopSelectionsCheck(state: PersistentStageState, liveDisplayIDs: Set<DisplayID>) -> StateAuditCheck {
        let stale = state.desktopSelections.filter { !liveDisplayIDs.contains($0.displayID) }
        return StateAuditCheck(
            level: stale.isEmpty ? .ok : .warn,
            name: "stale-desktop-selections",
            message: "count=\(stale.count)"
        )
    }

    private func staleDesktopLabelsCheck(state: PersistentStageState, liveDisplayIDs: Set<DisplayID>) -> StateAuditCheck {
        let stale = state.desktopLabels.filter { !liveDisplayIDs.contains($0.displayID) }
        return StateAuditCheck(
            level: stale.isEmpty ? .ok : .warn,
            name: "stale-desktop-labels",
            message: "count=\(stale.count)"
        )
    }

    private func activeStagesCheck(state: PersistentStageState) -> StateAuditCheck {
        let broken = state.scopes.filter { scope in
            !scope.stages.contains { $0.id == scope.activeStageID }
        }
        return StateAuditCheck(
            level: broken.isEmpty ? .ok : .fail,
            name: "active-stages",
            message: "missing=\(broken.count)"
        )
    }

    private func focusedMembersCheck(state: PersistentStageState) -> StateAuditCheck {
        var missing = 0
        for scope in state.scopes {
            for stage in scope.stages {
                guard let focusedWindowID = stage.focusedWindowID else { continue }
                if !stage.members.contains(where: { $0.windowID == focusedWindowID }) {
                    missing += 1
                }
            }
        }
        return StateAuditCheck(
            level: missing == 0 ? .ok : .warn,
            name: "focused-members",
            message: "missing=\(missing)"
        )
    }

    private func duplicateMembershipCheck(state: PersistentStageState) -> StateAuditCheck {
        var owners: [WindowID: Int] = [:]
        for scope in state.scopes {
            for stage in scope.stages {
                for member in stage.members {
                    owners[member.windowID, default: 0] += 1
                }
            }
        }
        let duplicates = owners.values.filter { $0 > 1 }.count
        return StateAuditCheck(
            level: duplicates == 0 ? .ok : .fail,
            name: "duplicate-membership",
            message: "windows=\(duplicates)"
        )
    }

    private func staleMembersCheck(state: PersistentStageState, liveWindowIDs: Set<WindowID>) -> StateAuditCheck {
        var stale = 0
        for scope in state.scopes {
            for stage in scope.stages {
                stale += stage.members.filter { !liveWindowIDs.contains($0.windowID) }.count
            }
        }
        return StateAuditCheck(
            level: stale == 0 ? .ok : .warn,
            name: "stale-members",
            message: "count=\(stale)"
        )
    }

    private func fallbackDisplayID(in snapshot: DaemonSnapshot, state: PersistentStageState) -> DisplayID? {
        let liveDisplayIDs = Set(snapshot.displays.map(\.id))
        if let activeDisplayID = state.activeDisplayID,
           liveDisplayIDs.contains(activeDisplayID) {
            return activeDisplayID
        }
        if let focusedWindowID = snapshot.focusedWindowID,
           let focused = snapshot.windows.first(where: { $0.window.id == focusedWindowID }),
           let displayID = focused.scope?.displayID ?? snapshot.displays.first(where: { $0.frame.cgRect.contains(focused.window.frame.center) })?.id {
            return displayID
        }
        return snapshot.displays.first(where: \.isMain)?.id ?? snapshot.displays.first?.id
    }

    private func repairScopes(_ state: inout PersistentStageState, liveWindowIDs: Set<WindowID>) -> Int {
        var repaired = 0
        var seenWindowIDs: Set<WindowID> = []

        for scopeIndex in state.scopes.indices {
            if state.scopes[scopeIndex].stages.isEmpty {
                state.scopes[scopeIndex].stages.append(PersistentStage(id: StageID(rawValue: "1")))
                repaired += 1
            }

            if !state.scopes[scopeIndex].stages.contains(where: { $0.id == state.scopes[scopeIndex].activeStageID }) {
                state.scopes[scopeIndex].activeStageID = state.scopes[scopeIndex].stages.first?.id ?? StageID(rawValue: "1")
                repaired += 1
            }

            for stageIndex in state.scopes[scopeIndex].stages.indices {
                let beforeCount = state.scopes[scopeIndex].stages[stageIndex].members.count
                state.scopes[scopeIndex].stages[stageIndex].members.removeAll { member in
                    if !liveWindowIDs.contains(member.windowID) {
                        return true
                    }
                    if seenWindowIDs.contains(member.windowID) {
                        return true
                    }
                    seenWindowIDs.insert(member.windowID)
                    return false
                }
                repaired += beforeCount - state.scopes[scopeIndex].stages[stageIndex].members.count

                if let focusedWindowID = state.scopes[scopeIndex].stages[stageIndex].focusedWindowID,
                   !state.scopes[scopeIndex].stages[stageIndex].members.contains(where: { $0.windowID == focusedWindowID }) {
                    state.scopes[scopeIndex].stages[stageIndex].focusedWindowID = state.scopes[scopeIndex].stages[stageIndex].members.last?.windowID
                    repaired += 1
                }
            }
        }

        return repaired
    }
}
