import AppKit
import Foundation

/// Temps passé dans les appels Accessibility, par application, depuis la dernière remise à zéro
/// (SPEC-086). Une passe lente nomme ainsi l'application qui a fait attendre Roadie, au lieu de
/// laisser deviner la cause d'un gel.
public final class AXCallTimings: @unchecked Sendable {
    public static let shared = AXCallTimings()

    private let lock = NSLock()
    private var totals: [pid_t: (seconds: Double, calls: Int)] = [:]

    /// Exécute un appel AX et ajoute sa durée à l'application. O(1).
    func measure<T>(_ pid: pid_t, _ call: () -> T) -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        let result = call()
        let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
        lock.withLock {
            let total = totals[pid] ?? (0, 0)
            totals[pid] = (total.seconds + seconds, total.calls + 1)
        }
        return result
    }

    /// Variante pour un élément dont seul l'élément est connu (écrivain).
    func measure<T>(_ element: AXUIElement, _ call: () -> T) -> T {
        var pid: pid_t = 0
        _ = AXUIElementGetPid(element, &pid)
        return measure(pid, call)
    }

    public func reset() {
        lock.withLock { totals.removeAll() }
    }

    /// Applications ayant cumulé au moins `minimumSeconds`, la plus lente d'abord, au format
    /// « Firefox 2.31s/14 » (durée/appels), puis remise à zéro. O(p log p), p applications.
    public func drainSlowest(minimumSeconds: Double, limit: Int) -> String {
        let slow = lock.withLock {
            defer { totals.removeAll() }
            return totals.filter { $0.value.seconds >= minimumSeconds }
        }
        return slow.sorted { $0.value.seconds > $1.value.seconds }.prefix(limit).map { pid, total in
            let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
            return "\(name) \(String(format: "%.2f", total.seconds))s/\(total.calls)"
        }.joined(separator: ", ")
    }
}
