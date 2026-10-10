import ApplicationServices
import Foundation
import Testing
@testable import RoadieAX

/// Horloge manuelle pour piloter la mise de côté et l'âge des fenêtres sans attendre.
private final class ManualClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@Suite
struct AXUnresponsiveAppsTests {
    @Test
    func cannotCompleteSetsAppAsideThenResumesAfterFiveSeconds() {
        let clock = ManualClock()
        let registry = AXUnresponsiveApps(now: { clock.now })

        #expect(registry.noteResult(.cannotComplete, pid: 42))
        #expect(registry.isQuarantined(42))
        #expect(!registry.isQuarantined(43))

        clock.advance(4.9)
        #expect(registry.isQuarantined(42))
        clock.advance(0.2)
        #expect(!registry.isQuarantined(42))
    }

    @Test
    func otherErrorsDoNotSetAppAside() {
        let registry = AXUnresponsiveApps(now: { Date() })
        for error in [AXError.success, .failure, .attributeUnsupported, .noValue, .invalidUIElement] {
            #expect(!registry.noteResult(error, pid: 7))
        }
        #expect(!registry.isQuarantined(7))
    }
}

@Suite
struct AXAttributeCacheTests {
    private func attributes(fullscreen: Bool = false, focused: Bool = false, subrole: String = "AXStandardWindow") -> AXWindowAttributes {
        AXWindowAttributes(
            stable: AXStableWindowAttributes(role: "AXWindow", subrole: subrole, hasCloseButton: true),
            volatile: AXVolatileWindowAttributes(isFocused: focused, isNativeFullscreen: fullscreen)
        )
    }

    @Test
    func windowYoungerThan500msIsNotCached() {
        let clock = ManualClock()
        let cache = AXAttributeCache(now: { clock.now })

        cache.record(attributes(), for: 1, stableIsFresh: true)
        #expect(cache.stableAttributes(for: 1, ttl: 600) == nil)

        clock.advance(0.6)
        cache.record(attributes(), for: 1, stableIsFresh: true)
        #expect(cache.stableAttributes(for: 1, ttl: 600)?.subrole == "AXStandardWindow")
    }

    @Test
    func cacheHoldsOnlyStablePartAndLastKnownFollowsLatestState() {
        let clock = ManualClock()
        let cache = AXAttributeCache(now: { clock.now })
        cache.record(attributes(fullscreen: false), for: 1, stableIsFresh: true)
        clock.advance(1)
        cache.record(attributes(fullscreen: false), for: 1, stableIsFresh: true)

        // L'état change : seule la dernière lecture complète le reflète, le cache reste stable.
        cache.record(attributes(fullscreen: true, focused: true), for: 1, stableIsFresh: false)
        #expect(cache.lastKnown(for: 1)?.volatile.isNativeFullscreen == true)
        #expect(cache.lastKnown(for: 1)?.furniture.isFocused == true)
        #expect(cache.stableAttributes(for: 1, ttl: 600) == attributes().stable)
    }

    @Test
    func staleReadDoesNotReplaceCachedStableAttributes() {
        let clock = ManualClock()
        let cache = AXAttributeCache(now: { clock.now })
        cache.record(attributes(), for: 1, stableIsFresh: true)
        clock.advance(1)
        cache.record(attributes(), for: 1, stableIsFresh: true)

        // Une partie stable qui n'a pas été relue (repli dernier état) n'entre pas en cache.
        cache.invalidate()
        cache.record(attributes(subrole: "AXDialog"), for: 1, stableIsFresh: false)
        #expect(cache.stableAttributes(for: 1, ttl: 600) == nil)
    }

    @Test
    func invalidateDropsStablePartButKeepsLastKnownState() {
        let clock = ManualClock()
        let cache = AXAttributeCache(now: { clock.now })
        cache.record(attributes(), for: 1, stableIsFresh: true)
        clock.advance(1)
        cache.record(attributes(fullscreen: true), for: 1, stableIsFresh: true)

        cache.invalidate()
        #expect(cache.stableAttributes(for: 1, ttl: 600) == nil)
        #expect(cache.lastKnown(for: 1)?.volatile.isNativeFullscreen == true)

        // L'âge de la fenêtre est conservé : la lecture suivante revient en cache.
        cache.record(attributes(), for: 1, stableIsFresh: true)
        #expect(cache.stableAttributes(for: 1, ttl: 600) != nil)
    }

    @Test
    func expiredEntryIsReadAgain() {
        let clock = ManualClock()
        let cache = AXAttributeCache(now: { clock.now })
        cache.record(attributes(), for: 1, stableIsFresh: true)
        clock.advance(1)
        cache.record(attributes(), for: 1, stableIsFresh: true)

        clock.advance(11)
        #expect(cache.stableAttributes(for: 1, ttl: 10) == nil)
    }

    @Test
    func retainForgetsClosedWindows() {
        let cache = AXAttributeCache(now: { Date() })
        cache.record(attributes(), for: 1, stableIsFresh: true)
        cache.record(attributes(), for: 2, stableIsFresh: true)

        cache.retain(only: [2])
        #expect(cache.lastKnown(for: 1) == nil)
        #expect(cache.lastKnown(for: 2) != nil)
    }
}

@Suite
struct AXVolatileReadingTests {
    @Test
    func unreadableAttributeKeepsLastKnownValueButFalseIsKept() {
        let last = AXVolatileWindowAttributes(isFocused: true, isMain: true, isModal: false, isNativeFullscreen: true)
        let reading = AXVolatileReading(isFocused: false, isMain: nil, isModal: nil, isNativeFullscreen: nil)

        let resolved = reading.resolved(lastKnown: last)
        #expect(resolved.isFocused == false)
        #expect(resolved.isMain == true)
        #expect(resolved.isNativeFullscreen == true)
        #expect(reading.resolved(lastKnown: nil) == AXVolatileWindowAttributes())
    }

    @Test
    func embeddedErrorsDistinguishAbsentFromUnreadable() {
        func errorValue(_ error: AXError) -> AnyObject {
            var error = error
            return AXValueCreate(.axError, &error)!
        }
        #expect(AXReadValue.flag(kCFBooleanTrue) == true)
        #expect(AXReadValue.flag(kCFBooleanFalse) == false)
        #expect(AXReadValue.flag(errorValue(.attributeUnsupported)) == false)
        #expect(AXReadValue.flag(errorValue(.noValue)) == false)
        #expect(AXReadValue.flag(errorValue(.cannotComplete)) == nil)
        #expect(AXReadValue.flag(errorValue(.failure)) == nil)
        #expect(AXReadValue.embeddedError("AXWindow" as NSString) == nil)
    }

    @Test
    func embeddedCannotCompleteSetsAppAside() {
        func errorValue(_ error: AXError) -> AnyObject {
            var error = error
            return AXValueCreate(.axError, &error)!
        }
        let registry = AXUnresponsiveApps()
        // Absent, illisible ou valeur normale : pas de mise de côté.
        let harmless: [AnyObject] = [kCFBooleanTrue, errorValue(.noValue), errorValue(.failure)]
        #expect(!AXReadValue.noteEmbeddedErrors(in: harmless, pid: 7, registry: registry))
        #expect(!registry.isQuarantined(7))
        // Un .cannotComplete intégré met l'application de côté.
        let frozen: [AnyObject] = [kCFBooleanTrue, errorValue(.cannotComplete)]
        #expect(AXReadValue.noteEmbeddedErrors(in: frozen, pid: 7, registry: registry))
        #expect(registry.isQuarantined(7))
        #expect(!registry.isQuarantined(8))
    }
}
