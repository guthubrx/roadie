import CoreGraphics
import Foundation
import RoadieCore
import Testing
@testable import RoadieAX

@Suite
struct Spec043WrittenFrameHistoryTests {
    private let start = Date(timeIntervalSince1970: 43_000)
    private let a = CGRect(x: 0, y: 0, width: 800, height: 600)
    private var b: CGRect { a.offsetBy(dx: 300, dy: 0) }

    @Test
    func delayedAAfterBIsAnEchoWithoutChangingTheLatestWrite() {
        let registry = WrittenFrameRegistry()
        registry.record(windowID: 1, requested: a, readBack: a, generation: 1, at: start)
        registry.record(windowID: 1, requested: b, readBack: b, generation: 2, at: start.addingTimeInterval(0.2))
        let latest = registry.entry(for: 1)

        #expect(registry.consumeEcho(windowID: 1, observed: a.offsetBy(dx: 1, dy: -1), now: start.addingTimeInterval(1.4)))
        #expect(registry.entry(for: 1) == latest)
        #expect(registry.classify(windowID: 1, observed: b, now: start.addingTimeInterval(1.4)) == .echo)
    }

    @Test
    func oldReadBackAndAcceptedFramesAreRemembered() {
        let registry = WrittenFrameRegistry()
        let readBack = a.insetBy(dx: 0, dy: -30)
        let accepted = a.offsetBy(dx: 0, dy: 100)
        registry.record(windowID: 1, requested: a, readBack: readBack, generation: 1, at: start)
        registry.accept(windowID: 1, frame: accepted, at: start.addingTimeInterval(0.1))
        registry.record(windowID: 1, requested: b, readBack: b, generation: 2, at: start.addingTimeInterval(0.2))

        #expect(registry.classify(windowID: 1, observed: readBack, now: start.addingTimeInterval(1.4)) == .echo)
        #expect(registry.classify(windowID: 1, observed: accepted, now: start.addingTimeInterval(1.4)) == .echo)
        #expect(registry.entry(for: 1)?.accepted == nil)
    }

    @Test
    func historyExpiresAtOneAndAHalfSecondsWithoutEchoRefresh() {
        let registry = WrittenFrameRegistry()
        registry.record(windowID: 1, requested: a, readBack: nil, generation: 1, at: start)
        registry.record(windowID: 1, requested: b, readBack: nil, generation: 2, at: start.addingTimeInterval(0.2))

        #expect(registry.classify(windowID: 1, observed: a, now: start.addingTimeInterval(1.499)) == .echo)
        #expect(registry.classify(windowID: 1, observed: a, now: start.addingTimeInterval(1.5)) == .external)
        // La dernière écriture garde la compatibilité historique, indépendamment du TTL court.
        #expect(registry.classify(windowID: 1, observed: b, now: start.addingTimeInterval(60)) == .echo)
    }

    @Test
    func acceptedFrameHasItsOwnHistoryDeadline() {
        let registry = WrittenFrameRegistry()
        let accepted = a.offsetBy(dx: 0, dy: 100)
        registry.record(windowID: 1, requested: a, readBack: nil, generation: 1, at: start)
        registry.accept(windowID: 1, frame: accepted, at: start.addingTimeInterval(0.5))
        registry.record(windowID: 1, requested: b, readBack: nil, generation: 2, at: start.addingTimeInterval(0.6))

        #expect(registry.classify(windowID: 1, observed: accepted, now: start.addingTimeInterval(1.999)) == .echo)
        #expect(registry.classify(windowID: 1, observed: accepted, now: start.addingTimeInterval(2)) == .external)
    }

    @Test
    func historyRetainsAtMost32IndividualFramesPerWindow() {
        let registry = WrittenFrameRegistry()
        for index in 0..<33 {
            registry.record(windowID: 1, requested: a.offsetBy(dx: CGFloat(index * 10), dy: 0),
                            readBack: nil, generation: 1, at: start)
        }
        let now = start.addingTimeInterval(1.1)

        #expect(registry.classify(windowID: 1, observed: a, now: now) == .external)
        for index in 1..<33 {
            #expect(registry.classify(windowID: 1, observed: a.offsetBy(dx: CGFloat(index * 10), dy: 0), now: now) == .echo)
        }
        #expect(registry.entry(for: 1)?.writesInGeneration == 33)
        #expect(registry.isOverBudget(windowID: 1, generation: 1))
    }

    @Test
    func readBackAndAcceptedFramesShareTheSame32FrameLimit() {
        let registry = WrittenFrameRegistry()
        for index in 0..<16 {
            registry.record(windowID: 1, requested: a.offsetBy(dx: CGFloat(index * 20), dy: 0),
                            readBack: a.offsetBy(dx: CGFloat(index * 20 + 10), dy: 0), generation: 1, at: start)
        }
        registry.accept(windowID: 1, frame: b.offsetBy(dx: 100, dy: 0), at: start)

        #expect(registry.classify(windowID: 1, observed: a, now: start.addingTimeInterval(1.1)) == .external)
        #expect(registry.classify(windowID: 1, observed: a.offsetBy(dx: 10, dy: 0), now: start.addingTimeInterval(1.1)) == .echo)
    }

    @Test
    func forgettingAWindowRemovesHistoryEvenWhenItsIDIsReused() {
        let registry = WrittenFrameRegistry()
        registry.record(windowID: 1, requested: a, readBack: nil, generation: 1, at: start)
        registry.record(windowID: 2, requested: a, readBack: nil, generation: 1, at: start)
        registry.forget(windowID: 1)
        #expect(registry.entry(for: 1) == nil)
        registry.record(windowID: 1, requested: b, readBack: nil, generation: 2, at: start.addingTimeInterval(0.1))

        #expect(registry.classify(windowID: 1, observed: a, now: start.addingTimeInterval(1.2)) == .external)
        #expect(registry.classify(windowID: 2, observed: a, now: start.addingTimeInterval(1.2)) == .echo)
    }

    @Test
    func historicalEchoDoesNotConfirmANewGenerationsRefusal() {
        let registry = WrittenFrameRegistry()
        registry.record(windowID: 1, requested: a, readBack: a, generation: 1, at: start)
        // A est à la fois un ancien cadre et la relecture du nouveau refus : AX ne donne pas
        // de génération. Cette notification ambiguë doit attendre une vraie relecture.
        registry.record(windowID: 1, requested: b, readBack: a, generation: 2, at: start.addingTimeInterval(0.1))
        let latest = registry.entry(for: 1)

        #expect(registry.consumeEcho(windowID: 1, observed: a, now: start.addingTimeInterval(0.2)))
        #expect(registry.entry(for: 1) == latest)
        #expect(registry.pendingRefusals() == [1])
        #expect(registry.confirmRefusal(windowID: 1, observed: a, at: start.addingTimeInterval(0.3), generation: 2))
    }

    @Test
    func delayedRequestedFrameDoesNotClearAnotherGenerationsRefusal() {
        let registry = WrittenFrameRegistry()
        registry.record(windowID: 1, requested: a, readBack: nil, generation: 1, at: start)
        registry.record(windowID: 1, requested: a, readBack: b, generation: 2, at: start.addingTimeInterval(0.1))

        #expect(registry.consumeEcho(windowID: 1, observed: a, now: start.addingTimeInterval(0.2)))
        #expect(registry.entry(for: 1)?.readBack == b)
        #expect(registry.pendingRefusals() == [1])
    }

    @Test
    func generationCheckedFreshObservationRejectsAStaleConfirmation() {
        let registry = WrittenFrameRegistry()
        registry.record(windowID: 1, requested: a, readBack: b, generation: 1, at: start)
        registry.record(windowID: 1, requested: a, readBack: b, generation: 2, at: start.addingTimeInterval(0.1))

        #expect(!registry.confirmRefusal(windowID: 1, observed: b, at: start.addingTimeInterval(0.2), generation: 1))
        #expect(registry.entry(for: 1)?.refusalConfirmedAt == nil)
        #expect(registry.confirmRefusal(windowID: 1, observed: b, at: start.addingTimeInterval(0.2), generation: 2))
    }

    @Test
    func historyDoesNotExtendAppResponseWindowOrResetBudget() {
        let registry = WrittenFrameRegistry()
        registry.record(windowID: 1, requested: a, readBack: nil, generation: 5, at: start)
        registry.record(windowID: 1, requested: b, readBack: nil, generation: 5, at: start.addingTimeInterval(0.1))
        let unknown = a.offsetBy(dx: 0, dy: 300)
        let now = start.addingTimeInterval(1.2)

        #expect(registry.classify(windowID: 1, observed: a, now: now) == .echo)
        #expect(registry.classify(windowID: 1, observed: unknown, now: now) == .external)
        #expect(registry.isOverBudget(windowID: 1, generation: 5))
        #expect(registry.entry(for: 1)?.writtenAt == start.addingTimeInterval(0.1))
    }
}
