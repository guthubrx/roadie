import Foundation
import CoreGraphics
import RoadieFXCore

/// Queue thread-safe d'animations actives. Coalescing par (wid, property) :
/// 2 enqueue sur même clé → la nouvelle remplace l'ancienne.
/// Cap à `maxConcurrent` : drop le plus ancien (FIFO) avec log warning.
public actor AnimationQueue {
    private var active: [AnimationKey: Animation] = [:]
    private var insertionOrder: [AnimationKey] = []
    public let maxConcurrent: Int
    public private(set) var paused: Bool = false

    public init(maxConcurrent: Int = 20) {
        self.maxConcurrent = maxConcurrent
    }

    /// Ajoute une animation. Coalesce avec l'existante sur même clé.
    public func enqueue(_ anim: Animation) {
        let k = anim.key
        if active[k] != nil {
            insertionOrder.removeAll { $0 == k }
        }
        active[k] = anim
        insertionOrder.append(k)
        if active.count > maxConcurrent {
            let oldest = insertionOrder.removeFirst()
            active.removeValue(forKey: oldest)
        }
    }

    public func enqueueBatch(_ anims: [Animation]) {
        for a in anims { enqueue(a) }
    }

    public func cancel(wid: CGWindowID) {
        let toRemove = active.keys.filter { $0.wid == wid }
        for k in toRemove {
            active.removeValue(forKey: k)
            insertionOrder.removeAll { $0 == k }
        }
    }

    public func cancelAll() {
        active.removeAll()
        insertionOrder.removeAll()
    }

    public func pause() { paused = true }
    public func resume() { paused = false }

    public var count: Int { active.count }

    /// Tick : pour chaque animation active, calcule la valeur et retourne les
    /// commandes OSAX à émettre. Les animations terminées sont retirées avec un
    /// envoi final de la valeur target.
    public func tick(now: TimeInterval) -> [OSAXCommand] {
        guard !paused else { return [] }
        var commands: [OSAXCommand] = []
        var done: [AnimationKey] = []
        for (k, anim) in active {
            if let value = anim.value(at: now) {
                if let cmd = anim.toCommand(value: value) {
                    commands.append(cmd)
                }
            } else {
                // Terminée : envoi target final
                if let cmd = anim.toCommand(value: anim.to) {
                    commands.append(cmd)
                }
                done.append(k)
            }
        }
        for k in done {
            active.removeValue(forKey: k)
            insertionOrder.removeAll { $0 == k }
        }
        return commands
    }
}
