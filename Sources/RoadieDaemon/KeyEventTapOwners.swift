import Foundation

/// Le contexte C est un numéro, jamais une adresse d’objet à déréférencer.
/// Un callback déjà en file après fermeture retrouve nil au lieu d’une session détruite.
final class KeyEventTapOwners: @unchecked Sendable {
    static let shared = KeyEventTapOwners()
    private struct WeakOwner { weak var value: AnyObject? }
    private let lock = NSLock()
    private var nextID: UInt = 0
    private var owners: [UInt: WeakOwner] = [:]

    func register(_ owner: AnyObject) -> UnsafeMutableRawPointer {
        lock.withLock {
            nextID += 1
            owners[nextID] = WeakOwner(value: owner)
            return UnsafeMutableRawPointer(bitPattern: nextID)!
        }
    }

    func owner(for token: UnsafeMutableRawPointer?) -> AnyObject? {
        guard let token else { return nil }
        return lock.withLock {
            let key = UInt(bitPattern: token)
            let value = owners[key]?.value
            if value == nil { owners[key] = nil }
            return value
        }
    }

    func remove(_ token: UnsafeMutableRawPointer) {
        lock.withLock { owners[UInt(bitPattern: token)] = nil }
    }
}
