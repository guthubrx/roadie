import Foundation
import CoreGraphics

/// Entrée du cache LRU. `Sendable` car tous les champs sont value types.
public struct ThumbnailEntry: Sendable {
    public let wid: CGWindowID
    public let pngData: Data
    public let size: CGSize
    public let degraded: Bool
    public let capturedAt: Date

    public init(wid: CGWindowID, pngData: Data, size: CGSize,
                degraded: Bool, capturedAt: Date = Date()) {
        self.wid = wid
        self.pngData = pngData
        self.size = size
        self.degraded = degraded
        self.capturedAt = capturedAt
    }
}

/// Cache LRU des vignettes côté daemon.
/// Capacité par défaut : 50 entrées. Eviction de la moins récemment utilisée.
/// Thread-safety : non-actor — à appeler uniquement depuis @MainActor (CommandRouter, WindowCaptureService).
/// Invariants : entries.count <= capacity, accessOrder.count == entries.count.
public final class ThumbnailCache {
    public let capacity: Int
    private var entries: [CGWindowID: ThumbnailEntry] = [:]
    /// Ordre d'accès MRU : le premier élément est le plus récemment utilisé.
    private var accessOrder: [CGWindowID] = []

    public init(capacity: Int = 50) {
        self.capacity = capacity
    }

    /// Retourne l'entrée pour `wid` et la déplace en tête de l'ordre MRU.
    public func get(wid: CGWindowID) -> ThumbnailEntry? {
        guard let entry = entries[wid] else { return nil }
        promoteToFront(wid)
        return entry
    }

    /// Insère ou remplace une entrée. Eviction LRU si capacity atteinte.
    public func put(_ entry: ThumbnailEntry) {
        let wid = entry.wid
        if entries[wid] != nil {
            entries[wid] = entry
            promoteToFront(wid)
            return
        }
        if entries.count == capacity {
            evictLRU()
        }
        entries[wid] = entry
        accessOrder.insert(wid, at: 0)
    }

    /// Retire explicitement une entrée (fenêtre fermée, désabonnement).
    public func evict(wid: CGWindowID) {
        guard entries[wid] != nil else { return }
        entries.removeValue(forKey: wid)
        accessOrder.removeAll { $0 == wid }
    }

    /// Vide le cache entier.
    public func clear() {
        entries.removeAll()
        accessOrder.removeAll()
    }

    public var count: Int { entries.count }

    // MARK: - Private

    private func promoteToFront(_ wid: CGWindowID) {
        accessOrder.removeAll { $0 == wid }
        accessOrder.insert(wid, at: 0)
    }

    /// Retire le moins récemment utilisé (queue = dernière position).
    private func evictLRU() {
        guard let lru = accessOrder.last else { return }
        entries.removeValue(forKey: lru)
        accessOrder.removeLast()
    }
}
