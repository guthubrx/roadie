import ApplicationServices
import Foundation
import RoadieCore
import Testing
@testable import RoadieAX

// SPEC-017 T035 : écrivain AX, registre des frames écrites, écho absorbé, sonde de bureau.

/// Écrivain espion : enregistre les appels AX et répond avec des valeurs scriptées.
private final class SpyAXFrameIO: AXFrameIO, @unchecked Sendable {
    var calls: [String] = []
    var enumerations = 0
    var windows: [pid_t: AXApplicationWindows] = [:]
    var enhancedUserInterface = false
    var setErrors: [String: AXError] = [:]
    var readBack = CGRect(x: 0, y: 0, width: 100, height: 100)

    func enumerateWindows(pid: pid_t) -> AXApplicationWindows? {
        enumerations += 1
        return windows[pid]
    }

    func value(of attribute: String, on element: AXUIElement) -> (AXError, CFTypeRef?) {
        calls.append("get \(attribute)")
        return attribute == AXWindowFrameWriter.enhancedUserInterface
            ? (.success, enhancedUserInterface ? kCFBooleanTrue : kCFBooleanFalse)
            : (.attributeUnsupported, nil)
    }

    func values(of attributes: [String], on element: AXUIElement) -> (AXError, [AnyObject]) {
        calls.append("read \(attributes.joined(separator: ","))")
        var origin = readBack.origin
        var size = readBack.size
        return (.success, [AXValueCreate(.cgPoint, &origin)!, AXValueCreate(.cgSize, &size)!])
    }

    func setValue(_ value: CFTypeRef, of attribute: String, on element: AXUIElement) -> AXError {
        if attribute == AXWindowFrameWriter.enhancedUserInterface {
            calls.append("set \(attribute)=\((value as? Bool) == true)")
            return .success
        }
        calls.append("set \(attribute)")
        return setErrors[attribute] ?? .success
    }

    var frameWrites: [String] { calls.filter { $0 == "set AXSize" || $0 == "set AXPosition" } }
}

private final class ManualClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

private func window(_ id: UInt32, pid: pid_t) -> WindowSnapshot {
    WindowSnapshot(
        id: WindowID(rawValue: id), pid: pid, appName: "App", bundleID: "app", title: "w\(id)",
        frame: Rect(x: 0, y: 0, width: 400, height: 300), isOnScreen: true, isTileCandidate: true
    )
}

/// Index AX factice : un élément distinct par fenêtre (éléments application de pid factices).
private func index(pid: pid_t, ids: [UInt32]) -> AXApplicationWindows {
    AXApplicationWindows(pid: pid, entries: ids.map { (id: $0, element: AXUIElementCreateApplication(pid_t($0))) })
}

private struct WriterFixture {
    let io = SpyAXFrameIO()
    let cache = AXWindowIndexCache()
    let frames = WrittenFrameRegistry()
    let clock = ManualClock()

    var writer: AXWindowFrameWriter {
        let clock = clock
        return AXWindowFrameWriter(
            io: io, windowIndex: cache, writtenFrames: frames, registry: AXUnresponsiveApps(), now: { clock.now }
        )
    }
}

@Suite
struct AXWindowFrameWriterTests {
    @Test
    func writesSizeThenPositionThenSizeThenReadsBackOnce() {
        let fixture = WriterFixture()
        fixture.io.windows[50] = index(pid: 50, ids: [501])

        let target = CGRect(x: 10, y: 20, width: 300, height: 200)
        fixture.io.readBack = target
        let result = fixture.writer.setFrames([WindowFrameUpdate(window: window(501, pid: 50), frame: target)])

        #expect(result[WindowID(rawValue: 501)] == target)
        #expect(fixture.io.frameWrites == ["set AXSize", "set AXPosition", "set AXSize"])
        #expect(fixture.io.calls.filter { $0.hasPrefix("read") } == ["read AXPosition,AXSize"])
    }

    @Test
    func enhancedUserInterfaceIsDisabledOncePerAppAndRestoredEvenOnFailure() {
        let fixture = WriterFixture()
        fixture.io.windows[51] = index(pid: 51, ids: [511, 512])
        fixture.io.enhancedUserInterface = true
        fixture.io.setErrors[kAXPositionAttribute] = .cannotComplete

        let result = fixture.writer.setFrames([
            WindowFrameUpdate(window: window(511, pid: 51), frame: CGRect(x: 0, y: 0, width: 300, height: 200)),
            WindowFrameUpdate(window: window(512, pid: 51), frame: CGRect(x: 300, y: 0, width: 300, height: 200)),
        ])

        let euiCalls = fixture.io.calls.filter { $0.contains(AXWindowFrameWriter.enhancedUserInterface) }
        #expect(euiCalls == [
            "get AXEnhancedUserInterface", "set AXEnhancedUserInterface=false", "set AXEnhancedUserInterface=true",
        ])
        #expect(fixture.io.calls.last == "set AXEnhancedUserInterface=true")
        #expect(result[WindowID(rawValue: 511)] == .some(nil))
        #expect(fixture.frames.entry(for: 511) == nil)
    }

    @Test
    func inactiveEnhancedUserInterfaceIsLeftAlone() {
        let fixture = WriterFixture()
        fixture.io.windows[52] = index(pid: 52, ids: [521])
        _ = fixture.writer.setFrame(CGRect(x: 0, y: 0, width: 300, height: 200), of: window(521, pid: 52))
        #expect(!fixture.io.calls.contains { $0.hasPrefix("set AXEnhancedUserInterface") })
    }

    @Test
    func readFrameDoesAFreshReadWithoutWriting() {
        let fixture = WriterFixture()
        fixture.io.windows[56] = index(pid: 56, ids: [561])
        fixture.io.readBack = CGRect(x: 5, y: 5, width: 640, height: 480)
        let writer: any WindowFrameWriting = fixture.writer
        #expect(writer.readFrame(of: window(561, pid: 56)) == fixture.io.readBack)
        #expect(fixture.io.calls == ["read AXPosition,AXSize"])
    }

    @Test
    func refusedSizeStillMovesTheWindow() {
        let fixture = WriterFixture()
        fixture.io.windows[53] = index(pid: 53, ids: [531])
        fixture.io.setErrors[kAXSizeAttribute] = .attributeUnsupported
        let readBack = CGRect(x: 10, y: 10, width: 500, height: 400)
        fixture.io.readBack = readBack

        let applied = fixture.writer.setFrame(CGRect(x: 10, y: 10, width: 300, height: 200), of: window(531, pid: 53))
        #expect(applied == readBack)
        #expect(fixture.io.frameWrites == ["set AXSize", "set AXPosition", "set AXSize"])
    }

    @Test
    func enumeratesOncePerPidAndBatchThenReusesSnapshotIndex() {
        let fixture = WriterFixture()
        fixture.io.windows[54] = index(pid: 54, ids: [541, 542])
        let updates = [541, 542].map {
            WindowFrameUpdate(window: window($0, pid: 54), frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        }

        _ = fixture.writer.setFrames(updates)
        #expect(fixture.io.enumerations == 1)

        // Index en cache (posé par le snapshot ou le lot précédent) : aucune énumération.
        _ = fixture.writer.setFrames(updates)
        #expect(fixture.io.enumerations == 1)

        // Fenêtre plus récente que l'index : une seule nouvelle énumération pour ce pid.
        fixture.io.windows[54] = index(pid: 54, ids: [541, 542, 543])
        _ = fixture.writer.setFrames(updates + [
            WindowFrameUpdate(window: window(543, pid: 54), frame: CGRect(x: 0, y: 0, width: 200, height: 200)),
        ])
        #expect(fixture.io.enumerations == 2)

        // Élément devenu invalide : l'index du pid est vidé.
        fixture.io.setErrors[kAXSizeAttribute] = .invalidUIElement
        _ = fixture.writer.setFrames(updates)
        #expect(fixture.cache.windows(for: 54) == nil)
    }

    @Test
    func eachWriteIsRecordedWithTheGenerationPassedThroughTheProtocol() {
        let fixture = WriterFixture()
        fixture.io.windows[55] = index(pid: 55, ids: [551])
        let target = CGRect(x: 0, y: 0, width: 300, height: 200)
        let readBack = CGRect(x: 0, y: 0, width: 300, height: 190)
        fixture.io.readBack = readBack

        let writer: any WindowFrameWriting = fixture.writer
        _ = writer.setFrames([WindowFrameUpdate(window: window(551, pid: 55), frame: target)], generation: 7)
        _ = writer.setFrames([WindowFrameUpdate(window: window(551, pid: 55), frame: target)], generation: 7)

        let entry = fixture.frames.entry(for: 551)
        #expect(entry?.requested == target)
        #expect(entry?.readBack == readBack)
        #expect(entry?.generation == 7)
        #expect(entry?.writesInGeneration == 2)
        #expect(entry?.writtenAt == fixture.clock.now)
    }
}

@Suite
struct WrittenFrameRegistryTests {
    private let requested = CGRect(x: 0, y: 0, width: 800, height: 600)
    private let start = Date(timeIntervalSince1970: 2_000)

    @Test
    func classifiesEchoAppResponseAndExternalChange() {
        let registry = WrittenFrameRegistry()
        let readBack = CGRect(x: 0, y: 0, width: 800, height: 583)
        registry.record(windowID: 1, requested: requested, readBack: readBack, generation: 1, at: start)

        // Écho : frame demandée ou relue, à frameMatch près, sans limite de temps.
        #expect(registry.classify(windowID: 1, observed: requested.offsetBy(dx: 2, dy: -1), now: start) == .echo)
        #expect(registry.classify(windowID: 1, observed: readBack, now: start.addingTimeInterval(60)) == .echo)
        // Réponse de l'application : différente, moins de 1 s après l'écriture.
        let other = CGRect(x: 0, y: 0, width: 760, height: 600)
        #expect(registry.classify(windowID: 1, observed: other, now: start.addingTimeInterval(0.5)) == .appResponse)
        // Changement externe : au-delà, ou sans écriture connue.
        #expect(registry.classify(windowID: 1, observed: other, now: start.addingTimeInterval(1.5)) == .external)
        #expect(registry.classify(windowID: 2, observed: other, now: start) == .external)
    }

    @Test
    func echoComparesOnlyTheLastWrite() {
        let registry = WrittenFrameRegistry()
        registry.record(windowID: 1, requested: requested, readBack: requested, generation: 1, at: start)
        let moved = requested.offsetBy(dx: 400, dy: 0)
        registry.record(windowID: 1, requested: moved, readBack: moved, generation: 2, at: start.addingTimeInterval(5))

        #expect(registry.classify(windowID: 1, observed: moved, now: start.addingTimeInterval(10)) == .echo)
        #expect(registry.classify(windowID: 1, observed: requested, now: start.addingTimeInterval(10)) == .external)
    }

    @Test
    func acceptedFrameIsTiedToTheGenerationAndDroppedByANewOne() {
        let registry = WrittenFrameRegistry()
        let accepted = CGRect(x: 0, y: 0, width: 900, height: 600)
        registry.record(windowID: 1, requested: requested, readBack: requested, generation: 1, at: start)
        registry.accept(windowID: 1, frame: accepted)
        registry.record(windowID: 1, requested: requested, readBack: requested, generation: 1, at: start)

        #expect(registry.entry(for: 1)?.accepted == accepted)
        #expect(registry.entry(for: 1)?.writesInGeneration == 2)
        #expect(registry.classify(windowID: 1, observed: accepted, now: start.addingTimeInterval(30)) == .echo)

        registry.record(windowID: 1, requested: requested, readBack: requested, generation: 2, at: start)
        #expect(registry.entry(for: 1)?.accepted == nil)
        #expect(registry.entry(for: 1)?.writesInGeneration == 1)
        #expect(registry.classify(windowID: 1, observed: accepted, now: start.addingTimeInterval(30)) == .external)
    }

    @Test
    func echoOfTheReadBackConfirmsAPendingRefusal() {
        let registry = WrittenFrameRegistry()
        let clamped = CGRect(x: 0, y: 0, width: 800, height: 650)
        registry.record(windowID: 1, requested: requested, readBack: clamped, generation: 3, at: start)
        registry.record(windowID: 2, requested: requested, readBack: requested, generation: 3, at: start)
        #expect(registry.pendingRefusals() == [1])

        // Une observation différente de la relecture ne confirme rien.
        #expect(!registry.confirmRefusal(windowID: 1, observed: requested.insetBy(dx: 50, dy: 50), at: start))
        let confirmedAt = start.addingTimeInterval(0.1)
        #expect(registry.confirmRefusal(windowID: 1, observed: clamped, at: confirmedAt))
        #expect(registry.entry(for: 1)?.refusalConfirmedAt == confirmedAt)
        #expect(registry.pendingRefusals().isEmpty)

        // Une nouvelle écriture attend sa propre confirmation.
        registry.record(windowID: 1, requested: requested, readBack: clamped, generation: 3, at: start)
        #expect(registry.pendingRefusals() == [1])
        // L'application finit par accepter la frame demandée : plus de refus en attente.
        #expect(!registry.confirmRefusal(windowID: 1, observed: requested, at: confirmedAt))
        #expect(registry.pendingRefusals().isEmpty)
    }

    @Test
    func forgetDropsTheWindow() {
        let registry = WrittenFrameRegistry()
        registry.record(windowID: 1, requested: requested, readBack: nil, generation: 0, at: start)
        registry.forget(windowID: 1)
        #expect(registry.entry(for: 1) == nil)
    }
}

@Suite
@MainActor
struct AXWindowEventObserverDispatchTests {
    @Test
    func echoMoveIsAbsorbedButExternalMoveAndOtherEventsAreForwarded() {
        let registry = WrittenFrameRegistry()
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let now = Date()
        registry.record(windowID: 7, requested: frame, readBack: frame, generation: 1, at: now.addingTimeInterval(-5))
        var received: [AXWindowEvent] = []
        let observer = AXWindowEventObserver(writtenFrames: registry) { received.append($0) }

        let moved = AXWindowEvent(name: kAXWindowMovedNotification as String, pid: 3, windowID: 7)
        let resized = AXWindowEvent(name: kAXWindowResizedNotification as String, pid: 3, windowID: 7)
        observer.dispatch(moved, observedFrame: frame.offsetBy(dx: 1, dy: 0), now: now)
        observer.dispatch(resized, observedFrame: frame, now: now)
        #expect(received.isEmpty)

        observer.dispatch(moved, observedFrame: frame.offsetBy(dx: 300, dy: 0), now: now)
        observer.dispatch(moved, observedFrame: nil, now: now)
        let created = AXWindowEvent(name: kAXWindowCreatedNotification as String, pid: 3, windowID: 7)
        observer.dispatch(created, observedFrame: frame, now: now)
        #expect(received.count == 3)
        #expect(received.last == created)
    }

    @Test
    func absorbedEchoOfTheReadBackConfirmsTheRefusal() {
        let registry = WrittenFrameRegistry()
        let requested = CGRect(x: 0, y: 0, width: 800, height: 600)
        let clamped = CGRect(x: 0, y: 0, width: 800, height: 650)
        let now = Date()
        registry.record(windowID: 8, requested: requested, readBack: clamped, generation: 1, at: now)
        var received: [AXWindowEvent] = []
        let observer = AXWindowEventObserver(writtenFrames: registry) { received.append($0) }

        let resized = AXWindowEvent(name: kAXWindowResizedNotification as String, pid: 3, windowID: 8)
        observer.dispatch(resized, observedFrame: clamped, now: now.addingTimeInterval(0.05))
        #expect(received.isEmpty)
        #expect(registry.entry(for: 8)?.refusalConfirmedAt != nil)
    }

    @Test
    func legacyCallbackReceivesNamesOnly() {
        var names: [String] = []
        let observer = AXWindowEventObserver(onWindowEvent: { names.append($0) })
        observer.dispatch(AXWindowEvent(name: "AXWindowCreated", pid: 1, windowID: nil), observedFrame: nil, now: Date())
        #expect(names == ["AXWindowCreated"])
    }
}

@Suite
struct AXCacheInvalidationTests {
    @Test
    func attributeCacheIsInvalidatedPerPid() {
        let clock = ManualClock()
        let cache = AXAttributeCache(now: { clock.now })
        let attributes = AXWindowAttributes(
            stable: AXStableWindowAttributes(role: "AXWindow", subrole: "AXStandardWindow"),
            volatile: AXVolatileWindowAttributes()
        )
        for _ in 0..<2 {
            cache.record(attributes, for: 1, pid: 10, stableIsFresh: true)
            cache.record(attributes, for: 2, pid: 11, stableIsFresh: true)
            clock.advance(1)
        }
        cache.invalidate(pid: 10)
        #expect(cache.stableAttributes(for: 1, ttl: 600) == nil)
        #expect(cache.stableAttributes(for: 2, ttl: 600) != nil)
    }

    @Test
    func windowIndexReplaceAllDropsAbsentApplications() {
        let cache = AXWindowIndexCache()
        cache.store(index(pid: 60, ids: [601]))
        cache.replaceAll(with: [index(pid: 61, ids: [611])])
        #expect(cache.windows(for: 60) == nil)
        #expect(cache.windows(for: 61)?.element(id: 611) != nil)
        cache.invalidate(pid: 61)
        #expect(cache.windows(for: 61) == nil)
    }
}

@Suite
struct SpaceProbeTests {
    private let uuid = "AAAAAAAA-0000-4000-8000-000000000001"

    @Test
    func parsesCurrentSpaceOfEachDisplay() {
        let other = "11111111-2222-3333-4444-555555555555"
        let twoDisplays: [[String: Any]] = [
            ["Display Identifier": other, "Current Space": ["type": 0, "ManagedSpaceID": 3]],
            ["Display Identifier": uuid, "Current Space": ["type": 4, "ManagedSpaceID": 9]],
        ]
        // Deux écrans : bureau utilisateur sur l'un, plein écran sur l'autre.
        #expect(SpaceProbe.parse(twoDisplays, displayUUID: other, mainDisplayUUID: nil) == true)
        #expect(SpaceProbe.parse(twoDisplays, displayUUID: uuid, mainDisplayUUID: nil) == false)
        #expect(SpaceProbe.parse(twoDisplays, displayUUID: uuid.lowercased(), mainDisplayUUID: nil) == false)
        // Écran introuvable.
        #expect(SpaceProbe.parse(twoDisplays, displayUUID: "MISSING", mainDisplayUUID: nil) == nil)
    }

    @Test
    func mainIdentifierDesignatesOnlyTheMainDisplay() {
        let main: [[String: Any]] = [["Display Identifier": "Main", "Current Space": ["type": 0]]]
        #expect(SpaceProbe.parse(main, displayUUID: uuid, mainDisplayUUID: uuid) == true)
        #expect(SpaceProbe.parse(main, displayUUID: uuid, mainDisplayUUID: "OTHER") == nil)
        #expect(SpaceProbe.parse(main, displayUUID: uuid, mainDisplayUUID: nil) == nil)
    }

    @Test
    func incompleteDataGivesNil() {
        let cases: [[[String: Any]]] = [
            [],
            [["Display Identifier": uuid]],
            [["Display Identifier": uuid, "Current Space": "not a dictionary"]],
            [["Display Identifier": uuid, "Current Space": ["ManagedSpaceID": 3]]],
            [["Display Identifier": uuid, "Current Space": ["type": "0"]]],
            [["Current Space": ["type": 0]]],
        ]
        for displays in cases {
            #expect(SpaceProbe.parse(displays, displayUUID: uuid, mainDisplayUUID: uuid) == nil)
        }
    }

    @Test
    func liveProbeAnswersOrReturnsNilWithoutCrashing() {
        // Écran principal réel : une valeur si SkyLight expose le symbole, nil sinon.
        let uuid = CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID()).map {
            CFUUIDCreateString(nil, $0.takeRetainedValue()) as String
        } ?? uuid
        let answer = SpaceProbe.isUserSpaceActive(displayUUID: uuid)
        #expect(answer == true || answer == false || answer == nil)
    }
}
