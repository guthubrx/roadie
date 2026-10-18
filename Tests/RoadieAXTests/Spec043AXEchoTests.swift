import ApplicationServices
import Foundation
import Testing
@testable import RoadieAX

@Suite
@MainActor
struct Spec043AXEchoTests {
    private let start = Date(timeIntervalSince1970: 43_000)
    private let a = CGRect(x: 0, y: 0, width: 800, height: 600)
    private var b: CGRect { a.offsetBy(dx: 300, dy: 0) }

    @Test(arguments: [kAXWindowMovedNotification as String, kAXWindowResizedNotification as String])
    func delayedEchoIsAbsorbedAfterTheNextWrite(notification: String) {
        let registry = WrittenFrameRegistry()
        registry.record(windowID: 1, requested: a, readBack: a, generation: 1, at: start)
        registry.record(windowID: 1, requested: b, readBack: b, generation: 2, at: start.addingTimeInterval(0.1))
        var received: [AXWindowEvent] = []
        let observer = AXWindowEventObserver(writtenFrames: registry, mouseButtonsPressed: { false }) { received.append($0) }

        observer.dispatch(event(notification), observedFrame: a, now: start.addingTimeInterval(1.4))
        #expect(received.isEmpty)
        observer.dispatch(event(notification), observedFrame: a, now: start.addingTimeInterval(1.5))
        #expect(received == [event(notification)])
    }

    @Test(arguments: [kAXWindowMovedNotification as String, kAXWindowResizedNotification as String])
    func mousePressForwardsAHistoricalFrameWithoutChangingRegistry(notification: String) {
        let registry = WrittenFrameRegistry()
        registry.record(windowID: 1, requested: a, readBack: a, generation: 1, at: start)
        registry.record(windowID: 1, requested: b, readBack: b, generation: 2, at: start.addingTimeInterval(0.1))
        let latest = registry.entry(for: 1)
        var pressed = true
        var received: [AXWindowEvent] = []
        let observer = AXWindowEventObserver(writtenFrames: registry, mouseButtonsPressed: { pressed }) { received.append($0) }

        observer.dispatch(event(notification), observedFrame: a, now: start.addingTimeInterval(0.2))
        #expect(received == [event(notification)])
        #expect(registry.entry(for: 1) == latest)
        // Après relâchement, le registre retrouve son rôle d'absorption. Le maintainer possède
        // la session de geste ; l'observateur n'a modifié ni génération ni géométrie.
        pressed = false
        observer.dispatch(event(notification), observedFrame: a, now: start.addingTimeInterval(0.3))
        #expect(received.count == 1)
        #expect(registry.entry(for: 1) == latest)
    }

    @Test
    func mousePressAlsoForwardsTheCurrentReadBackWithoutConfirmingRefusal() {
        let registry = WrittenFrameRegistry()
        registry.record(windowID: 1, requested: a, readBack: b, generation: 2, at: start)
        var pressed = true
        var received: [AXWindowEvent] = []
        let observer = AXWindowEventObserver(writtenFrames: registry, mouseButtonsPressed: { pressed }) { received.append($0) }
        let resized = event(kAXWindowResizedNotification as String)

        observer.dispatch(resized, observedFrame: b, now: start.addingTimeInterval(0.1))
        #expect(received == [resized])
        #expect(registry.entry(for: 1)?.refusalConfirmedAt == nil)
        pressed = false
        observer.dispatch(resized, observedFrame: b, now: start.addingTimeInterval(0.2))
        #expect(received.count == 1)
        #expect(registry.entry(for: 1)?.refusalConfirmedAt == start.addingTimeInterval(0.2))
    }

    @Test
    func mousePressForwardsCurrentRequestedFrameAndUnreadableGeometry() {
        let registry = WrittenFrameRegistry()
        registry.record(windowID: 1, requested: a, readBack: a, generation: 1, at: start)
        var received: [AXWindowEvent] = []
        let observer = AXWindowEventObserver(writtenFrames: registry, mouseButtonsPressed: { true }) { received.append($0) }
        let moved = event(kAXWindowMovedNotification as String)

        observer.dispatch(moved, observedFrame: a, now: start.addingTimeInterval(0.1))
        observer.dispatch(moved, observedFrame: nil, now: start.addingTimeInterval(0.2))
        #expect(received == [moved, moved])
        #expect(registry.entry(for: 1)?.writesInGeneration == 1)
    }

    @Test
    func oldGenerationEchoCannotConfirmTheNewRefusal() {
        let registry = WrittenFrameRegistry()
        registry.record(windowID: 1, requested: a, readBack: nil, generation: 1, at: start)
        registry.record(windowID: 1, requested: b, readBack: a, generation: 2, at: start.addingTimeInterval(0.1))
        var received: [AXWindowEvent] = []
        let observer = AXWindowEventObserver(writtenFrames: registry, mouseButtonsPressed: { false }) { received.append($0) }

        observer.dispatch(event(kAXWindowResizedNotification as String), observedFrame: a, now: start.addingTimeInterval(0.2))
        #expect(received.isEmpty)
        #expect(registry.entry(for: 1)?.refusalConfirmedAt == nil)
        #expect(registry.pendingRefusals() == [1])
    }

    @Test
    func destructionForgetsHistoryBeforeForwardingTheEvent() {
        let registry = WrittenFrameRegistry()
        registry.record(windowID: 1, requested: a, readBack: nil, generation: 1, at: start)
        registry.record(windowID: 1, requested: b, readBack: nil, generation: 2, at: start.addingTimeInterval(0.1))
        var received: [AXWindowEvent] = []
        let observer = AXWindowEventObserver(writtenFrames: registry, mouseButtonsPressed: { false }) {
            #expect(registry.entry(for: 1) == nil)
            received.append($0)
        }
        let destroyed = event(kAXUIElementDestroyedNotification as String)

        observer.dispatch(destroyed, observedFrame: nil, now: start.addingTimeInterval(0.2))
        #expect(received == [destroyed])
        registry.record(windowID: 1, requested: b, readBack: nil, generation: 3, at: start.addingTimeInterval(0.3))
        #expect(registry.classify(windowID: 1, observed: a, now: start.addingTimeInterval(1.4)) == .external)
    }

    @Test
    func appResponseIsForwardedWithoutConfirmingARefusal() {
        let registry = WrittenFrameRegistry()
        registry.record(windowID: 1, requested: a, readBack: b, generation: 1, at: start)
        var received: [AXWindowEvent] = []
        let observer = AXWindowEventObserver(writtenFrames: registry, mouseButtonsPressed: { false }) { received.append($0) }
        let resized = event(kAXWindowResizedNotification as String)

        observer.dispatch(resized, observedFrame: a.offsetBy(dx: 0, dy: 100), now: start.addingTimeInterval(0.2))
        #expect(received == [resized])
        #expect(registry.entry(for: 1)?.refusalConfirmedAt == nil)
    }

    private func event(_ name: String) -> AXWindowEvent {
        AXWindowEvent(name: name, pid: 43, windowID: 1)
    }
}
