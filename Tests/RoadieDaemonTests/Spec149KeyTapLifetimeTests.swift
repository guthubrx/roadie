import Foundation
import Testing
@testable import RoadieDaemon

@Suite struct Spec149KeyTapLifetimeTests {
    @Test func closingATapMakesEveryLateLookupHarmless() {
        let registry = KeyEventTapOwners()
        let owner = NSObject()
        let token = registry.register(owner)
        #expect(registry.owner(for: token) === owner)
        registry.remove(token)
        #expect(registry.owner(for: token) == nil)
        #expect(registry.owner(for: UnsafeMutableRawPointer(bitPattern: UInt.max)) == nil)
        #expect(registry.owner(for: nil) == nil)
    }

    @Test func aTapNeverKeepsAnAbandonedSessionAlive() {
        let registry = KeyEventTapOwners()
        weak var released: NSObject?
        let token: UnsafeMutableRawPointer
        do {
            let owner = NSObject()
            released = owner
            token = registry.register(owner)
        }
        #expect(released == nil)
        #expect(registry.owner(for: token) == nil)
    }

    @Test func lateCallbacksCannotTargetTheNextSession() {
        let registry = KeyEventTapOwners()
        let old = NSObject(), new = NSObject()
        let previous = registry.register(old)
        registry.remove(previous)
        let current = registry.register(new)
        #expect(previous != current)
        #expect(registry.owner(for: previous) == nil)
        #expect(registry.owner(for: current) === new)
        registry.remove(current)
    }
}
