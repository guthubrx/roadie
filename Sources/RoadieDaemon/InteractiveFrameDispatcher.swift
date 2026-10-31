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
    }
    private let service: SnapshotService
    let permit: InteractiveWritePermit
    private let completed: @MainActor (ApplyResult) -> Void
    private var active: [Int32: Set<WindowID>] = [:]
    private var pending: [Int32: Batch] = [:]

    init(service: SnapshotService, permit: InteractiveWritePermit,
         completed: @escaping @MainActor (ApplyResult) -> Void) {
        self.service = service
        self.permit = permit
        self.completed = completed
    }

    var isIdle: Bool { active.isEmpty && pending.isEmpty }
    /// Index O(1) : une fenêtre déjà juste doit néanmoins être remise à sa place
    /// si un ancien lot actif ou en attente risque encore de la déplacer.
    func mayChange(_ window: WindowSnapshot) -> Bool {
        active[window.pid]?.contains(window.id) == true
            || pending[window.pid]?.windowIDs.contains(window.id) == true
    }

    /// Remplace les anciens lots, y compris quand une fenêtre revient à son cadre initial.
    func submit(_ commands: [ApplyCommand], generation: UInt64) {
        guard permit.isCurrent else { invalidate(); return }
        let groups = Dictionary(grouping: commands, by: { $0.window.pid })
        pending = groups.mapValues { Batch(plan: ApplyPlan(commands: $0), generation: generation,
                                          windowIDs: Set($0.map { $0.window.id })) }
        for pid in Array(pending.keys) where active[pid] == nil { start(pid) }
    }

    func invalidate() {
        permit.invalidate()
        pending.removeAll()
    }

    private func start(_ pid: Int32) {
        guard permit.isCurrent, active[pid] == nil, let batch = pending.removeValue(forKey: pid) else { return }
        active[pid] = batch.windowIDs
        let service = service, permit = permit
        let work = Task.detached(priority: .userInitiated) {
            service.apply(batch.plan, generation: batch.generation, isCurrent: { permit.isCurrent }, publish: false,
                          respectLastingRefusals: true)
        }
        Task { [weak self] in
            let result = await work.value
            guard let self else { return }
            self.active.removeValue(forKey: pid)
            if permit.isCurrent {
                self.service.publishInteractive(result, commands: batch.plan.commands)
                self.completed(result)
                self.start(pid)
            } else {
                self.pending.removeAll()
            }
        }
    }
}
