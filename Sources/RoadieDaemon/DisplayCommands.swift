import Foundation
import RoadieAX
import RoadieCore

public struct DisplayCommandService {
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

    public func focus(index: Int) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = snapshot.displays.first(where: { $0.index == index }) else {
            return .failure("display focus \(index): unknown display")
        }
        return focus(display, in: snapshot, label: "\(index)")
    }

    public func focus(_ direction: Direction) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let activeDisplay = activeDisplay(in: snapshot) else {
            return .noChange("display focus \(direction.rawValue): no active display")
        }
        guard let target = DisplayTopology.neighbor(from: activeDisplay, direction: direction, in: snapshot.displays) else {
            return .noChange("display focus \(direction.rawValue): no display")
        }
        return focus(target, in: snapshot, label: direction.rawValue)
    }

    /// Échange la stage active de l'écran source (ou actif) avec celle d'un autre écran (SPEC-157).
    /// Sans cible : échange avec l'autre écran (2 écrans) ou l'écran suivant par index (>2 écrans).
    public func swapDefault(sourceDisplayID: DisplayID? = nil) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard snapshot.displays.count >= 2 else {
            return .noChange("display swap: requires at least 2 displays")
        }
        guard let source = resolvedDisplay(id: sourceDisplayID, in: snapshot) else {
            return .noChange("display swap: no active display")
        }
        let ordered = snapshot.displays.sorted { $0.index < $1.index }
        let target: DisplaySnapshot?
        if ordered.count == 2 {
            target = ordered.first { $0.id != source.id }
        } else if let idx = ordered.firstIndex(where: { $0.id == source.id }) {
            target = ordered[(idx + 1) % ordered.count]
        } else {
            target = ordered.first { $0.id != source.id }
        }
        guard let target, target.id != source.id else {
            return .noChange("display swap: no other display")
        }
        return swap(source: source, target: target, in: snapshot, label: "default")
    }

    public func swap(index: Int, sourceDisplayID: DisplayID? = nil) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard snapshot.displays.count >= 2 else {
            return .noChange("display swap \(index): requires at least 2 displays")
        }
        guard let source = resolvedDisplay(id: sourceDisplayID, in: snapshot) else {
            return .noChange("display swap \(index): no active display")
        }
        guard let target = snapshot.displays.first(where: { $0.index == index }) else {
            return .failure("display swap \(index): unknown display")
        }
        guard target.id != source.id else {
            return .noChange("display swap \(index): same display")
        }
        return swap(source: source, target: target, in: snapshot, label: "\(index)")
    }

    public func swap(_ direction: Direction, sourceDisplayID: DisplayID? = nil) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard snapshot.displays.count >= 2 else {
            return .noChange("display swap \(direction.rawValue): requires at least 2 displays")
        }
        guard let source = resolvedDisplay(id: sourceDisplayID, in: snapshot) else {
            return .noChange("display swap \(direction.rawValue): no active display")
        }
        guard let target = DisplayTopology.neighbor(from: source, direction: direction, in: snapshot.displays) else {
            return .noChange("display swap \(direction.rawValue): no display")
        }
        return swap(source: source, target: target, in: snapshot, label: direction.rawValue)
    }

    public func swap(targetDisplayID: DisplayID, sourceDisplayID: DisplayID? = nil) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard snapshot.displays.count >= 2 else {
            return .noChange("display swap: requires at least 2 displays")
        }
        guard let source = resolvedDisplay(id: sourceDisplayID, in: snapshot) else {
            return .noChange("display swap: no active display")
        }
        guard let target = snapshot.displays.first(where: { $0.id == targetDisplayID }) else {
            return .failure("display swap: unknown target display")
        }
        guard target.id != source.id else {
            return .noChange("display swap: same display")
        }
        return swap(source: source, target: target, in: snapshot, label: targetDisplayID.rawValue)
    }

    private struct SwapTransaction {
        var stageOnSource: PersistentStage
        var stageOnTarget: PersistentStage
        var oldSourceScope: StageScope
        var oldTargetScope: StageScope
        var newSourceScope: StageScope
        var newTargetScope: StageScope
    }

    private func swap(
        source: DisplaySnapshot,
        target: DisplaySnapshot,
        in snapshot: DaemonSnapshot,
        label: String
    ) -> StageCommandResult {
        let generation = PlacementGeneration.shared.next()
        commandActivity.markActive(reason: "display.swap")
        defer { commandActivity.finish(reason: "display.swap") }

        let transaction: SwapTransaction?
        do {
            transaction = try service.commitStageTransfer(in: store, { state -> SwapTransaction? in
                let sourceDesktop = state.currentDesktopID(for: source.id)
                let targetDesktop = state.currentDesktopID(for: target.id)
                var scopeA = state.scope(displayID: source.id, desktopID: sourceDesktop)
                var scopeB = state.scope(displayID: target.id, desktopID: targetDesktop)
                scopeA.ensureStage(scopeA.activeStageID)
                scopeB.ensureStage(scopeB.activeStageID)

                guard let idxA = scopeA.stages.firstIndex(where: { $0.id == scopeA.activeStageID }),
                      let idxB = scopeB.stages.firstIndex(where: { $0.id == scopeB.activeStageID })
                else { return nil }

                var stageA = scopeA.stages.remove(at: idxA)
                var stageB = scopeB.stages.remove(at: idxB)
                let oldSourceScope = StageScope(displayID: source.id, desktopID: sourceDesktop, stageID: stageA.id)
                let oldTargetScope = StageScope(displayID: target.id, desktopID: targetDesktop, stageID: stageB.id)

                Self.resetParking(&stageA)
                Self.resetParking(&stageB)

                Self.insertTransferredStage(&stageB, at: idxA, into: &scopeA)
                scopeA.activeStageID = stageB.id

                Self.insertTransferredStage(&stageA, at: idxB, into: &scopeB)
                scopeB.activeStageID = stageA.id

                state.update(scopeA)
                state.update(scopeB)

                let newSourceScope = StageScope(displayID: source.id, desktopID: sourceDesktop, stageID: stageB.id)
                let newTargetScope = StageScope(displayID: target.id, desktopID: targetDesktop, stageID: stageA.id)
                for member in stageB.members {
                    state.updatePinHomeScope(windowID: member.windowID, to: newSourceScope)
                }
                for member in stageA.members {
                    state.updatePinHomeScope(windowID: member.windowID, to: newTargetScope)
                }
                state.focusDisplay(source.id)

                return SwapTransaction(
                    stageOnSource: stageB,
                    stageOnTarget: stageA,
                    oldSourceScope: oldSourceScope,
                    oldTargetScope: oldTargetScope,
                    newSourceScope: newSourceScope,
                    newTargetScope: newTargetScope
                )
            }, clearingIntentsOf: { tx in
                guard let tx else { return [] }
                return Array(Set([tx.oldSourceScope, tx.oldTargetScope, tx.newSourceScope, tx.newTargetScope]))
            })
        } catch {
            return .persistenceFailure("display swap \(label)", error)
        }

        guard let transaction else {
            return .failure("display swap \(label): missing active stage")
        }

        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })
        var placement = CommandPlacement(layoutScopes: nil)
        var moved = 0
        for member in transaction.stageOnSource.members where windowsByID[member.windowID] != nil {
            placement.restoring[member.windowID] = Self.centeredFrame(member.frame.cgRect, in: source.visibleFrame.cgRect)
            moved += 1
        }
        for member in transaction.stageOnTarget.members where windowsByID[member.windowID] != nil {
            placement.restoring[member.windowID] = Self.centeredFrame(member.frame.cgRect, in: target.visibleFrame.cgRect)
            moved += 1
        }
        let applyResult = service.applyCommandPlacement(placement, cause: "display.swap", generation: generation, events: events).result

        events.append(RoadieEvent(type: "display_swap", details: [
            "sourceDisplayID": source.id.rawValue,
            "targetDisplayID": target.id.rawValue,
            "sourceStageID": transaction.stageOnSource.id.rawValue,
            "targetStageID": transaction.stageOnTarget.id.rawValue,
            "movedWindows": String(moved),
            "failed": String(applyResult.failed)
        ]))

        return StageCommandResult(
            message: "display swap \(label): \(source.name) <-> \(target.name) moved=\(moved) failed=\(applyResult.failed)",
            changed: true,
            outcome: .changed
        )
    }

    private static func resetParking(_ stage: inout PersistentStage) {
        stage.parkingState = .native
        stage.origin = nil
        stage.hostDisplayID = nil
        stage.restoredAt = nil
    }

    private static func insertTransferredStage(
        _ stage: inout PersistentStage,
        at preferredIndex: Int,
        into scope: inout PersistentStageScope
    ) {
        let automaticallyNamed = !StagePresentationOrder.isNamed(stage)
        if let conflict = scope.stages.first(where: { $0.id == stage.id }) {
            let nontrivial = !conflict.members.isEmpty || !conflict.groups.isEmpty
                || StagePresentationOrder.isNamed(conflict)
                || conflict.mode != stage.mode || conflict.bspTree != nil
            if nontrivial {
                stage.id = nextAvailableStageID(preferred: stage.id, in: scope)
            } else {
                scope.stages.removeAll { $0.id == stage.id }
            }
        }
        if automaticallyNamed {
            stage.name = "Stage \(stage.id.rawValue)"
        }
        scope.stages.insert(stage, at: min(preferredIndex, scope.stages.count))
    }

    private static func nextAvailableStageID(preferred: StageID, in scope: PersistentStageScope) -> StageID {
        let used = Set(scope.stages.map(\.id.rawValue))
        if !used.contains(preferred.rawValue) {
            return preferred
        }
        for value in 1...99 where !used.contains(String(value)) {
            return StageID(rawValue: String(value))
        }
        return StageID(rawValue: "\(preferred.rawValue)-\(UUID().uuidString.prefix(8))")
    }

    private static func centeredFrame(_ frame: CGRect, in container: CGRect) -> CGRect {
        CGRect(
            x: container.midX - frame.width / 2,
            y: container.midY - frame.height / 2,
            width: frame.width,
            height: frame.height
        ).integral
    }

    private func resolvedDisplay(id: DisplayID?, in snapshot: DaemonSnapshot) -> DisplaySnapshot? {
        if let id {
            return snapshot.displays.first { $0.id == id }
        }
        return activeDisplay(in: snapshot)
    }

    private func focus(_ display: DisplaySnapshot, in snapshot: DaemonSnapshot, label: String) -> StageCommandResult {
        let transaction: (DesktopID, PersistentStageScope)
        do {
            transaction = try store.mutateChecked { state in
                state.focusDisplay(display.id)
                let desktopID = state.currentDesktopID(for: display.id)
                let scope = state.scope(displayID: display.id, desktopID: desktopID)
                state.update(scope)
                return (desktopID, scope)
            }
        } catch {
            return .persistenceFailure("display focus \(label)", error)
        }
        let (desktopID, scope) = transaction

        let activeScope = StageScope(displayID: display.id, desktopID: desktopID, stageID: scope.activeStageID)
        let focusedID = scope.stages.first { $0.id == scope.activeStageID }?.focusedWindowID
            ?? scope.memberIDs(in: scope.activeStageID).last
        let focused = focusedID.flatMap { id in
            snapshot.windows.first { $0.window.id == id && $0.scope == activeScope }?.window
        }
        let focusedResult = focused.map { service.focus($0) } ?? false
        events.append(RoadieEvent(type: "display_focus", details: [
            "displayIndex": String(display.index),
            "displayID": display.id.rawValue,
            "displayName": display.name,
            "focused": String(focusedResult)
        ]))

        return StageCommandResult(
            message: "display focus \(label): \(display.name) focused=\(focusedResult)",
            changed: true,
            outcome: .changed
        )
    }

    private func activeDisplay(in snapshot: DaemonSnapshot) -> DisplaySnapshot? {
        if let focusedID = service.focusedWindowID(),
           let focused = snapshot.windows.first(where: { $0.window.id == focusedID }),
           let displayID = focused.scope?.displayID,
           let display = snapshot.displays.first(where: { $0.id == displayID }) {
            return display
        }
        let state = store.state()
        if let activeDisplayID = state.activeDisplayID,
           let display = snapshot.displays.first(where: { $0.id == activeDisplayID }) {
            return display
        }
        return snapshot.displays.first(where: \.isMain) ?? snapshot.displays.first
    }
}
