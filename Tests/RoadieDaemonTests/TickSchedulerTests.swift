import CoreGraphics
import Foundation
import os
import Testing
@testable import RoadieAX
import RoadieCore
@testable import RoadieDaemon

/// Horloge partagée avec `EpisodeContext`, dont l'horloge doit être `@Sendable`.
private final class TestClock: Sendable {
    private let value = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_000))
    var now: Date {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }
}

/// Minuterie manuelle : les actions partent quand l'horloge avance au-delà de leur échéance.
@MainActor
private final class ManualTimer {
    let clock = TestClock()
    private var items: [(id: Int, due: Date, action: @MainActor () -> Void)] = []
    private var nextID = 0

    var armedCount: Int { items.count }

    func schedule(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> () -> Void {
        let id = nextID
        nextID += 1
        items.append((id, clock.now.addingTimeInterval(delay), action))
        return { [weak self] in self?.items.removeAll { $0.id == id } }
    }

    func advance(by seconds: TimeInterval) {
        let target = clock.now.addingTimeInterval(seconds)
        while let next = items.filter({ $0.due <= target }).min(by: { $0.due < $1.due }) {
            items.removeAll { $0.id == next.id }
            clock.now = max(clock.now, next.due)
            next.action()
        }
        clock.now = target
    }
}

@MainActor
private final class Harness {
    let timer = ManualTimer()
    let episodes: EpisodeContext
    var ticks: [(cause: String, at: Date)] = []
    var deadline: Date?
    /// Comme les échéances non soldées par une passe : rendues seulement tant qu'elles sont à venir.
    var deadlineIsFutureOnly = false
    var blocked = false
    var result = MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
    var onTick: () -> Void = {}
    private(set) var scheduler: TickScheduler!

    init(events: EventLog? = nil) {
        let clock = timer.clock
        episodes = EpisodeContext(now: { clock.now })
        scheduler = TickScheduler(
            tick: { [unowned self] cause in
                ticks.append((cause, timer.clock.now))
                onTick()
                return result
            },
            nextDeadline: { [unowned self] now in
                deadlineIsFutureOnly ? deadline.flatMap { $0 > now ? $0 : nil } : deadline
            },
            isBlocked: { [unowned self] in blocked },
            now: { clock.now },
            schedule: { [unowned self] delay, action in timer.schedule(delay, action) },
            episodes: episodes,
            events: events
        )
    }

    var start: Date { Date(timeIntervalSince1970: 1_000) }

    func elapsedMs(_ index: Int) -> Int {
        Int((ticks[index].at.timeIntervalSince(start) * 1000).rounded())
    }
}

@MainActor
@Suite
struct TickSchedulerTests {
    @Test
    func earliestDueTimeWins() {
        let harness = Harness()
        harness.scheduler.request(cause: "AXWindowMoved", delay: .externalChange)
        harness.scheduler.request(cause: "AXWindowCreated", delay: .event)
        harness.timer.advance(by: 1)

        #expect(harness.ticks.count == 1)
        #expect(harness.ticks.first?.cause == "AXWindowMoved")
        #expect(harness.elapsedMs(0) == 15)
    }

    @Test
    func internalDeadlineBeforePendingRequestTicksFirst() {
        let harness = Harness()
        harness.deadline = harness.start.addingTimeInterval(0.020)
        harness.onTick = { harness.deadline = nil }
        harness.scheduler.request(cause: "AXWindowResized", delay: .externalChange)
        harness.timer.advance(by: 1)

        #expect(harness.ticks.map(\.cause) == ["deadline", "AXWindowResized"])
        #expect(harness.elapsedMs(0) == 20)
        #expect(harness.elapsedMs(1) == 30)
    }

    @Test
    func burstWithinCoalescingWindowGivesOnePass() {
        let harness = Harness()
        harness.scheduler.request(cause: "AXWindowCreated")
        harness.timer.advance(by: 0.005)
        harness.scheduler.request(cause: "AXWindowCreated")
        harness.timer.advance(by: 0.005)
        harness.scheduler.request(cause: "AXUIElementDestroyed")
        harness.timer.advance(by: 1)

        #expect(harness.ticks.count == 1)
        #expect(harness.ticks.first?.cause == "AXWindowCreated")
    }

    /// L'ancienne règle des 200 ms abandonnait l'événement suivant (`main.swift`, avant SPEC-017).
    @Test
    func noEventIsDroppedWithin200Milliseconds() {
        let harness = Harness()
        harness.scheduler.request(cause: "AXWindowCreated")
        harness.timer.advance(by: 0.050)
        harness.scheduler.request(cause: "AXWindowMiniaturized")
        harness.timer.advance(by: 0.050)
        harness.scheduler.request(cause: "AXWindowMoved", delay: .externalChange)
        harness.timer.advance(by: 1)

        #expect(harness.ticks.map(\.cause) == ["AXWindowCreated", "AXWindowMiniaturized", "AXWindowMoved"])
        #expect((0..<3).map(harness.elapsedMs) == [15, 65, 130])
    }

    @Test
    func passRunsAtArmedDeadlineThenStops() {
        let harness = Harness()
        harness.onTick = {
            harness.deadline = harness.ticks.count == 1 ? harness.timer.clock.now.addingTimeInterval(0.3) : nil
        }
        harness.scheduler.request(cause: "AXWindowCreated")
        harness.timer.advance(by: 5)

        #expect(harness.ticks.map(\.cause) == ["AXWindowCreated", "deadline"])
        #expect(harness.elapsedMs(1) == 315)
        #expect(harness.timer.armedCount == 0)
    }

    /// A1 : une passe qui a agi ne déclenche pas de passe de suite.
    @Test
    func noFollowUpPassWhenPassActed() {
        let harness = Harness()
        harness.result = MaintenanceTick(commands: 3, applied: 3, clamped: 0, failed: 0)
        harness.scheduler.request(cause: "AXWindowCreated")
        harness.timer.advance(by: 5)

        #expect(harness.ticks.count == 1)
        #expect(harness.timer.armedCount == 0)
    }

    @Test
    func noPassWhileButtonPressedThenOnePassOnRelease() {
        let harness = Harness()
        harness.blocked = true
        harness.scheduler.request(cause: "AXWindowMoved", delay: .externalChange)
        harness.timer.advance(by: 0.5)
        harness.scheduler.request(cause: "AXWindowResized", delay: .externalChange)
        harness.timer.advance(by: 0.5)

        #expect(harness.ticks.isEmpty)
        #expect(harness.timer.armedCount == 0)

        harness.blocked = false
        harness.scheduler.buttonsReleased(gestureEnded: true)
        harness.timer.advance(by: 0.010)
        #expect(harness.ticks.isEmpty)
        harness.timer.advance(by: 1)

        #expect(harness.ticks.map(\.cause) == ["AXWindowMoved"])
        #expect(harness.elapsedMs(0) == 1_015)
    }

    @Test
    func gestureEndAloneRequestsOnePass() {
        let harness = Harness()
        harness.scheduler.buttonsReleased(gestureEnded: true)
        harness.timer.advance(by: 1)

        #expect(harness.ticks.map(\.cause) == ["drag"])
    }

    @Test
    func releaseWithoutGestureNorPendingRequestDoesNothing() {
        let harness = Harness()
        harness.scheduler.buttonsReleased(gestureEnded: false)
        harness.timer.advance(by: 1)

        #expect(harness.ticks.isEmpty)
    }

    /// Un écho de nos écritures est absorbé par l'observateur AX (A1) : aucune demande, aucune passe.
    @Test
    func echoSchedulesNothing() {
        let harness = Harness()
        let registry = WrittenFrameRegistry()
        let frame = CGRect(x: 0, y: 0, width: 500, height: 400)
        registry.record(windowID: 7, requested: frame, readBack: frame, generation: 1, at: harness.timer.clock.now)
        let observer = AXWindowEventObserver(writtenFrames: registry, mouseButtonsPressed: { false }) { event in
            harness.scheduler.request(cause: event.name, delay: .externalChange)
        }
        observer.dispatch(
            AXWindowEvent(name: "AXWindowMoved", pid: 42, windowID: 7),
            observedFrame: frame.offsetBy(dx: 1, dy: 0),
            now: harness.timer.clock.now.addingTimeInterval(0.05)
        )
        harness.timer.advance(by: 1)

        #expect(harness.ticks.isEmpty)
        #expect(harness.timer.armedCount == 0)
    }

    /// A12, A20 : l'épisode ouvert par l'événement reste ouvert à travers les échéances qu'il arme,
    /// même au-delà de la fermeture après 1 s de calme.
    @Test
    func episodeStaysOpenAcrossArmedDeadlines() {
        let harness = Harness()
        var episodesSeen: [String?] = []
        harness.onTick = {
            episodesSeen.append(harness.episodes.current)
            harness.deadline = harness.ticks.count < 3 ? harness.timer.clock.now.addingTimeInterval(0.8) : nil
        }
        harness.scheduler.request(cause: "AXWindowDeminiaturized")
        let opened = harness.episodes.current
        harness.timer.advance(by: 5)

        #expect(opened != nil)
        #expect(harness.ticks.count == 3)
        #expect(episodesSeen == [opened, opened, opened])
    }

    @Test
    func externalChangeExtendsOpenEpisodeAndEventOpensNewOne() {
        let harness = Harness()
        harness.scheduler.request(cause: "AXWindowCreated")
        let first = harness.episodes.current
        harness.timer.advance(by: 0.2)
        harness.scheduler.request(cause: "AXWindowResized", delay: .externalChange)
        #expect(harness.episodes.current == first)
        harness.timer.advance(by: 0.2)
        harness.scheduler.request(cause: "AXWindowCreated")

        #expect(harness.episodes.current != first)
    }

    @Test
    func safetyNetPassesImmediatelyWithoutEpisode() {
        let harness = Harness()
        harness.scheduler.request(cause: "periodic", delay: .safetyNet)
        harness.timer.advance(by: 0.001)

        #expect(harness.ticks.map(\.cause) == ["periodic"])
        #expect(harness.episodes.current == nil)
    }

    @Test
    func eventReplacesPendingSafetyNetCause() {
        let harness = Harness()
        harness.blocked = true
        harness.scheduler.request(cause: "periodic", delay: .safetyNet)
        harness.scheduler.request(cause: "AXWindowCreated")
        harness.blocked = false
        harness.scheduler.request(cause: "display_change")
        harness.timer.advance(by: 1)

        #expect(harness.ticks.map(\.cause) == ["AXWindowCreated"])
    }

    /// T211 : l'échéance armée part même si le maintainer ne la rend plus une fois échue.
    @Test
    func armedDeadlineFiresWhenNoLongerReported() {
        let harness = Harness()
        harness.deadlineIsFutureOnly = true
        harness.deadline = harness.start.addingTimeInterval(0.2)
        harness.onTick = { harness.deadline = nil }
        harness.scheduler.rearm()
        harness.timer.advance(by: 1)

        #expect(harness.ticks.map(\.cause) == ["deadline"])
        #expect(harness.elapsedMs(0) == 200)
    }

    /// T211 : une échéance réelle déjà passée part au plancher de 15 ms, une seule fois.
    @Test
    func pastRealDeadlineRunsOnceAtFloor() {
        let harness = Harness()
        harness.deadline = harness.start.addingTimeInterval(-0.5)
        harness.onTick = { harness.deadline = nil }
        harness.scheduler.rearm()
        harness.timer.advance(by: 1)

        #expect(harness.ticks.map(\.cause) == ["deadline"])
        #expect(harness.elapsedMs(0) == 15)
    }

    /// T221 : `live_tick` sépare le délai demandé, la retenue par un bouton enfoncé et le retard
    /// d'exécution après l'échéance.
    @Test
    func liveTickSplitsLatency() throws {
        let path = "\(NSTemporaryDirectory())roadie-live-tick-\(UUID().uuidString).jsonl"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let harness = Harness(events: EventLog(path: path))
        harness.blocked = true
        harness.scheduler.request(cause: "ax:AXWindowMoved", delay: .externalChange)
        harness.timer.advance(by: 0.5)
        harness.blocked = false
        harness.scheduler.buttonsReleased(gestureEnded: true)
        harness.timer.advance(by: 1)

        let line = try String(contentsOfFile: path, encoding: .utf8)
        #expect(line.contains("\"requestedDelayMs\":\"30.0\""))
        #expect(line.contains("\"dueLagMs\":\"0.0\""))
        #expect(line.contains("\"heldByGestureMs\":\"485.0\""))
        #expect(line.contains("\"latencyMs\":\"515.0\""))
    }

    /// Une échéance interne déjà passée (erreur du maintainer) ne fait pas tourner la boucle à vide.
    @Test
    func pastInternalDeadlineIsFloored() {
        let harness = Harness()
        harness.deadline = harness.start.addingTimeInterval(-1)
        harness.scheduler.request(cause: "AXWindowCreated")
        harness.timer.advance(by: 0.1)

        #expect(harness.ticks.count <= 7)
    }
}

@MainActor
@Suite
struct UserInputGestureTests {
    @Test
    func clickWithoutTargetProducesNoGesture() {
        let input = UserInputActivity()
        var releases: [Bool] = []
        input.observeGestures(target: { _ in nil }, onRelease: { releases.append($0) })

        input.mouseDown(at: CGPoint(x: 10, y: 10))
        #expect(input.currentGesture?.windowID == nil)
        #expect(input.currentGesture != nil)
        input.mouseUp(leftButton: true)

        #expect(input.currentGesture == nil)
        #expect(input.takeGesture() == nil)
        #expect(releases == [false])
    }

    @Test
    func gestureOnManagedWindowIsConsumedOnce() {
        let input = UserInputActivity()
        let frame = CGRect(x: 0, y: 0, width: 500, height: 400)
        var releases: [Bool] = []
        input.observeGestures(target: { _ in (7, frame) }, onRelease: { releases.append($0) })
        let down = Date(timeIntervalSince1970: 100)

        input.mouseDown(at: CGPoint(x: 10, y: 10), now: down)
        #expect(input.currentGesture == GestureSession(windowID: 7, startFrame: frame, startedAt: down))
        input.mouseUp(leftButton: true, now: down.addingTimeInterval(0.4))

        #expect(releases == [true])
        #expect(input.takeGesture() == GestureSession(windowID: 7, startFrame: frame, startedAt: down, endedAt: down.addingTimeInterval(0.4)))
        #expect(input.takeGesture() == nil)
    }

    @Test
    func otherButtonReleaseKeepsLeftSessionOpen() {
        let input = UserInputActivity()
        var releases: [Bool] = []
        input.observeGestures(target: { _ in (7, .zero) }, onRelease: { releases.append($0) })

        input.mouseDown(at: .zero)
        input.mouseUp(leftButton: false)

        #expect(input.currentGesture?.windowID == 7)
        #expect(releases == [false])
    }

    @Test
    func unconsumedGestureOnSameWindowKeepsFirstStartFrame() {
        let input = UserInputActivity()
        var frame = CGRect(x: 0, y: 0, width: 500, height: 400)
        input.observeGestures(target: { _ in (7, frame) }, onRelease: { _ in })
        let first = Date(timeIntervalSince1970: 100)

        input.mouseDown(at: .zero, now: first)
        input.mouseUp(leftButton: true, now: first.addingTimeInterval(0.2))
        frame.size.width = 600
        input.mouseDown(at: .zero, now: first.addingTimeInterval(0.3))
        input.mouseUp(leftButton: true, now: first.addingTimeInterval(0.5))

        let gesture = input.takeGesture()
        #expect(gesture?.startFrame?.width == 500)
        #expect(gesture?.startedAt == first)
        #expect(gesture?.endedAt == first.addingTimeInterval(0.5))
    }

    @Test
    func sessionWithoutObserverHasNoTarget() {
        let input = UserInputActivity()
        input.mouseDown(at: .zero)
        input.mouseUp(leftButton: true)

        #expect(input.takeGesture() == nil)
    }
}

@Suite
struct WindowDragReleaseGraceTests {
    private func tempPath(_ name: String) -> String {
        "\(NSTemporaryDirectory())roadie-\(name)-\(UUID().uuidString)"
    }

    /// A11 : en mode à arbre, le relâchement compte tout de suite ; les autres modes gardent la grâce.
    @Test
    func releaseGraceIsIgnoredForTreeModesAcrossInstances() {
        let path = tempPath("drag-grace")
        let producer = WindowDragActivity(path: path)
        let consumer = WindowDragActivity(path: path)
        let now = Date(timeIntervalSince1970: 100)

        producer.markActive(windowID: WindowID(rawValue: 1), now: now)
        #expect(consumer.isActive(now: now, includingReleaseGrace: false))

        producer.finish(now: now.addingTimeInterval(0.1))
        #expect(consumer.isActive(now: now.addingTimeInterval(0.2)))
        #expect(!consumer.isActive(now: now.addingTimeInterval(0.2), includingReleaseGrace: false))
        producer.reset()
    }
}
