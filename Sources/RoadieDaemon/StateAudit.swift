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
    /// Réparations non écrites (REL-021) : `repaired` vaut alors 0 et `failed` est vrai.
    public var persistenceError: String?

    public init(repaired: Int, audit: StateAuditReport, persistenceError: String? = nil) {
        self.repaired = repaired
        self.audit = audit
        self.persistenceError = persistenceError
    }

    /// Échec du rapport : audit en échec ou réparations non persistées.
    public var failed: Bool {
        audit.failed || persistenceError != nil
    }
}

public struct StateAuditService {
    private let service: SnapshotService
    private let stageStore: StageStore

    /// `stageStore` nil : celui du service (le même fichier en production, isolé en test).
    public init(service: SnapshotService = SnapshotService(), stageStore: StageStore? = nil) {
        self.service = service
        self.stageStore = stageStore ?? service.effectiveStageStore
    }

    public func run() -> StateAuditReport {
        let snapshot = service.snapshot()
        let state = stageStore.state()
        let liveDisplayIDs = Set(snapshot.displays.map(\.id))
        let liveManagedWindowIDs = Set(snapshot.windows.compactMap { entry in
            entry.scope == nil ? nil : entry.window.id
        })
        var checks: [StateAuditCheck] = []

        checks.append(activeDisplayCheck(state: state, liveDisplayIDs: liveDisplayIDs))
        checks.append(staleScopesCheck(state: state, liveDisplayIDs: liveDisplayIDs))
        checks.append(staleDesktopSelectionsCheck(state: state, liveDisplayIDs: liveDisplayIDs))
        checks.append(staleDesktopLabelsCheck(state: state, liveDisplayIDs: liveDisplayIDs))
        checks.append(activeStagesCheck(state: state, liveDisplayIDs: liveDisplayIDs))
        checks.append(focusedMembersCheck(state: state))
        checks.append(duplicateMembershipCheck(state: state))
        let duplicateNames = state.duplicateStageNameCount
        checks.append(StateAuditCheck(level: duplicateNames == 0 ? .ok : .warn, name: "duplicate-stage-names", message: "count=\(duplicateNames)"))
        checks.append(staleMembersCheck(state: state, liveWindowIDs: liveManagedWindowIDs))

        return StateAuditReport(checks: checks)
    }

    /// `isProcessAlive` : preuve de fermeture d'un membre absent du relevé (injectable en test).
    public func heal(isProcessAlive: (Int32) -> Bool = ProcessLiveness.isAlive) -> StateHealReport {
        // Snapshot (AX) hors verrou, réparation sur l'état relu sous verrou (SPEC-016 FR-013).
        let snapshot = service.snapshot()
        let liveDisplayIDs = Set(snapshot.displays.map(\.id))
        let liveManagedWindowIDs = Set(snapshot.windows.compactMap { entry in
            entry.scope == nil ? nil : entry.window.id
        })
        // Écriture contrôlée (REL-021) : une réparation non écrite n'est pas comptée.
        do {
            let repaired = try stageStore.mutateChecked { state -> Int in
                var repaired = 0
                if state.activeDisplayID.map({ !liveDisplayIDs.contains($0) }) != false {
                    state.activeDisplayID = fallbackDisplayID(in: snapshot, state: state)
                    repaired += state.activeDisplayID == nil ? 0 : 1
                }
                repaired += repairScopes(&state, liveWindowIDs: liveManagedWindowIDs, isProcessAlive: isProcessAlive)
                // Après le retrait des membres fermés : une copie vidée redevient anonyme (SPEC-067).
                repaired += state.makeStageNamesUnique(liveDisplays: liveDisplayIDs)
                return repaired
            }
            return StateHealReport(repaired: repaired, audit: run())
        } catch {
            return StateHealReport(
                repaired: 0,
                audit: run(),
                persistenceError: JSONPersistence.commandFailureMessage("state heal", error)
            )
        }
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
            level: stale.isEmpty ? .ok : .warn,
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

    private func activeStagesCheck(state: PersistentStageState, liveDisplayIDs: Set<DisplayID>) -> StateAuditCheck {
        let broken = state.scopes.filter { scope in
            !scope.stages.contains { $0.id == scope.activeStageID }
        }
        let liveBroken = broken.filter { liveDisplayIDs.contains($0.displayID) }
        let level: StateAuditLevel
        if !liveBroken.isEmpty {
            level = .fail
        } else if !broken.isEmpty {
            level = .warn
        } else {
            level = .ok
        }
        return StateAuditCheck(
            level: level,
            name: "active-stages",
            message: "missing=\(broken.count) liveMissing=\(liveBroken.count)"
        )
    }

    // Complexite : O(stages) avec lookup Set O(1) par stage.
    // n borne en pratique : ~4 displays * ~10 stages = ~40 stages.
    private func focusedMembersCheck(state: PersistentStageState) -> StateAuditCheck {
        let stages = state.scopes.flatMap(\.stages)
        let missing = stages.reduce(into: 0) { acc, stage in
            guard let focused = stage.focusedWindowID else { return }
            let memberIDs = Set(stage.members.lazy.map(\.windowID))
            if !memberIDs.contains(focused) { acc += 1 }
        }
        return StateAuditCheck(
            level: missing == 0 ? .ok : .warn,
            name: "focused-members",
            message: "missing=\(missing)"
        )
    }

    // Complexite : O(total_members) (parcours unique via flatMap).
    private func duplicateMembershipCheck(state: PersistentStageState) -> StateAuditCheck {
        var owners: [WindowID: Int] = [:]
        for member in state.scopes.lazy.flatMap(\.stages).flatMap(\.members) {
            owners[member.windowID, default: 0] += 1
        }
        let duplicates = owners.values.lazy.filter { $0 > 1 }.count
        return StateAuditCheck(
            level: duplicates == 0 ? .ok : .fail,
            name: "duplicate-membership",
            message: "windows=\(duplicates)"
        )
    }

    // Complexite : O(total_members) avec lookup Set O(1) par membre.
    private func staleMembersCheck(state: PersistentStageState, liveWindowIDs: Set<WindowID>) -> StateAuditCheck {
        let stale = state.scopes.lazy.flatMap(\.stages).flatMap(\.members)
            .reduce(into: 0) { acc, member in
                if !liveWindowIDs.contains(member.windowID) { acc += 1 }
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

    /// Un membre absent du relevé n'est retiré que sur preuve de fermeture : pid connu et mort.
    /// Le relevé ne liste que les fenêtres à l'écran ; une fenêtre réduite, sur un autre Space,
    /// d'une application qui ne répond pas ou d'un écran débranché y manque sans être fermée.
    /// Sans pid connu (anciens fichiers), la grâce du snapshot (30 min) s'en charge (REL-002).
    /// La déduplication s'applique à tous les membres, visibles ou non.
    /// Complexite : O(total_members) avec lookup Set O(1) par membre.
    private func repairScopes(
        _ state: inout PersistentStageState,
        liveWindowIDs: Set<WindowID>,
        isProcessAlive: (Int32) -> Bool
    ) -> Int {
        var repaired = 0
        var seenWindowIDs: Set<WindowID> = []

        for scopeIndex in state.scopes.indices {
            if state.scopes[scopeIndex].stages.isEmpty {
                state.scopes[scopeIndex].stages.append(PersistentStage(id: StageID(rawValue: "1")))
                repaired += 1
            }

            if !state.scopes[scopeIndex].stages.contains(where: { $0.id == state.scopes[scopeIndex].activeStageID }) {
                state.scopes[scopeIndex].activeStageID = selectableStage(in: state.scopes[scopeIndex])?.id ?? StageID(rawValue: "1")
                repaired += 1
            }

            for stageIndex in state.scopes[scopeIndex].stages.indices {
                let beforeCount = state.scopes[scopeIndex].stages[stageIndex].members.count
                state.scopes[scopeIndex].stages[stageIndex].members.removeAll { member in
                    if !liveWindowIDs.contains(member.windowID),
                       let pid = member.pid, !isProcessAlive(pid) {
                        return true
                    }
                    return !seenWindowIDs.insert(member.windowID).inserted
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

    private func selectableStage(in scope: PersistentStageScope) -> PersistentStage? {
        scope.stages.first { $0.parkingState != .parked || !$0.members.isEmpty }
            ?? scope.stages.first
    }
}
