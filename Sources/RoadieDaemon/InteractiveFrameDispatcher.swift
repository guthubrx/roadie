import Foundation
import RoadieAX
import RoadieCore

/// Permission commune à une session native. Une commande externe ou une annulation
/// révoque aussi les lots déjà partis, entre deux attributs AX. O(1) sous verrou.
final class InteractiveWritePermit: @unchecked Sendable {
    private let lock = NSLock()
    private var valid = true
    private var expected: UInt64
    private let generations: PlacementGeneration

    init(generations: PlacementGeneration) {
        self.generations = generations
        expected = generations.current
    }

    var isCurrent: Bool { lock.withLock { valid && expected == generations.current } }
    func advance() -> UInt64 {
        lock.withLock {
            expected = generations.next()
            return expected
        }
    }
    func invalidate() { lock.withLock { valid = false } }
}

/// Une opération active et un dernier lot par PID, via le writer commun. L'attente
/// d'une application ne retient pas les autres. O(n) par lot, mémoire O(w + p).
@MainActor
final class InteractiveFrameDispatcher {
    private struct Batch {
        let plan: ApplyPlan
        let generation: UInt64
        let windowIDs: Set<WindowID>
        let intermediate: Bool
    }
    private let service: SnapshotService
    let permit: InteractiveWritePermit
    private let completed: @MainActor (ApplyResult, UInt64) -> Void
    private let allowIntermediateStart: (@MainActor (Int32, TimeInterval) -> Bool)?
    private var active: [Int32: Set<WindowID>] = [:]
    private var pending: [Int32: Batch] = [:]
    private var lastWriteDurations: [Int32: TimeInterval] = [:]

    init(service: SnapshotService, permit: InteractiveWritePermit,
         allowIntermediateStart: (@MainActor (Int32, TimeInterval) -> Bool)? = nil,
         completed: @escaping @MainActor (ApplyResult, UInt64) -> Void) {
        self.service = service
        self.permit = permit
        self.allowIntermediateStart = allowIntermediateStart
        self.completed = completed
    }

    var isIdle: Bool { active.isEmpty && pending.isEmpty }
    func lastWriteDuration(for pid: Int32) -> TimeInterval { lastWriteDurations[pid] ?? 0 }
    /// Index O(1) : une fenêtre déjà juste doit néanmoins être remise à sa place
    /// si un ancien lot actif ou en attente risque encore de la déplacer.
    func mayChange(_ window: WindowSnapshot) -> Bool {
        active[window.pid]?.contains(window.id) == true
            || pending[window.pid]?.windowIDs.contains(window.id) == true
    }

    /// Remplace les anciens lots, y compris quand une fenêtre revient à son cadre initial.
    func submit(_ commands: [ApplyCommand], generation: UInt64, intermediate: Bool = false) {
        guard permit.isCurrent else { invalidate(); return }
        let groups = Dictionary(grouping: commands, by: { $0.window.pid })
        for (pid, group) in groups {
            if intermediate, let existing = pending[pid], !existing.intermediate { continue }
            pending[pid] = Batch(plan: ApplyPlan(commands: group), generation: generation,
                                 windowIDs: Set(group.map { $0.window.id }), intermediate: intermediate)
        }
        for pid in Array(pending.keys) where active[pid] == nil { start(pid) }
    }

    func invalidate() {
        permit.invalidate()
        pending.removeAll()
    }

    private func start(_ pid: Int32) {
        guard permit.isCurrent, active[pid] == nil, let batch = pending.removeValue(forKey: pid) else { return }
        if batch.intermediate, let allow = allowIntermediateStart, !allow(pid, lastWriteDurations[pid] ?? 0) {
            return
        }
        active[pid] = batch.windowIDs
        let service = service, permit = permit
        let work = Task.detached(priority: .userInitiated) { () -> (ApplyResult, TimeInterval) in
            let started = ProcessInfo.processInfo.systemUptime
            let result = service.apply(batch.plan, generation: batch.generation, isCurrent: { permit.isCurrent }, publish: false,
                                       respectLastingRefusals: true, intermediate: batch.intermediate)
            return (result, max(0, ProcessInfo.processInfo.systemUptime - started))
        }
        Task { [weak self] in
            let (result, elapsed) = await work.value
            guard let self else { return }
            self.active.removeValue(forKey: pid)
            if permit.isCurrent {
                self.lastWriteDurations[pid] = elapsed
                self.service.publishInteractive(result, commands: batch.plan.commands)
                self.completed(result, batch.generation)
                self.start(pid)
            } else {
                self.pending.removeAll()
            }
        }
    }
}
