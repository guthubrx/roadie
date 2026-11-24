import ApplicationServices
import Foundation
import Testing
@testable import RoadieAX

@Suite struct Spec042CacheGenerationTests {
    @Test func olderSweepCannotOverwriteOrPruneNewerAttributes() {
        let cache = AXAttributeCache()
        let old = cache.beginSnapshot()
        let current = cache.beginSnapshot()
        let attributes = AXWindowAttributes(stable: AXStableWindowAttributes(role: "AXWindow"), volatile: .init(isFocused: true))
        cache.record(attributes, for: 1, pid: 50, stableIsFresh: true, generation: current)
        cache.record(.init(stable: .init(), volatile: .init()), for: 1, pid: 50, stableIsFresh: true, generation: old)
        cache.retain(only: [], generation: old)
        #expect(cache.lastKnown(for: 1) == attributes)
        cache.invalidate(pid: 50)
        cache.record(attributes, for: 2, pid: 50, stableIsFresh: true, generation: current)
        #expect(cache.lastKnown(for: 2) == nil)
    }

    @Test func olderIndexCannotUndoNewerSweepInvalidationOrWriterEnumeration() {
        let cache = AXWindowIndexCache()
        let a = AXApplicationWindows(pid: 50, entries: [(id: 1, element: AXUIElementCreateApplication(501))])
        let b = AXApplicationWindows(pid: 50, entries: [(id: 2, element: AXUIElementCreateApplication(502))])
        let old = cache.beginSnapshot()
        let current = cache.beginSnapshot()
        cache.replaceAll(with: [b], generation: current)
        cache.replaceAll(with: [a], generation: old)
        #expect(cache.windows(for: 50)?.element(id: 2) != nil)
        cache.invalidate(pid: 50)
        cache.replaceAll(with: [a], generation: current)
        #expect(cache.windows(for: 50) == nil)
        let next = cache.beginSnapshot()
        cache.store(b)
        cache.replaceAll(with: [a], generation: next)
        #expect(cache.windows(for: 50)?.element(id: 2) != nil)
    }

    @Test func lotHPerPIDInvalidationDoesNotDiscardOtherPIDsDuringScan() {
        let attrCache = AXAttributeCache()
        let attrs = AXWindowAttributes(stable: AXStableWindowAttributes(role: "AXWindow"), volatile: .init())
        let scanAttr = attrCache.beginSnapshot()
        attrCache.invalidate(pid: 50)
        attrCache.record(attrs, for: 1, pid: 50, stableIsFresh: true, generation: scanAttr)
        attrCache.record(attrs, for: 2, pid: 60, stableIsFresh: true, generation: scanAttr)
        #expect(attrCache.lastKnown(for: 1) == nil)
        #expect(attrCache.lastKnown(for: 2) == attrs)

        let scanVolatile = attrCache.beginSnapshot()
        attrCache.invalidateVolatile(pid: 50)
        attrCache.record(attrs, for: 1, pid: 50, stableIsFresh: false, generation: scanVolatile)
        attrCache.record(attrs, for: 3, pid: 60, stableIsFresh: false, generation: scanVolatile)
        #expect(attrCache.lastKnown(for: 1) == nil)
        #expect(attrCache.lastKnown(for: 3) == attrs)

        let indexCache = AXWindowIndexCache()
        let pid50 = AXApplicationWindows(pid: 50, entries: [(id: 1, element: AXUIElementCreateApplication(501))])
        let pid60 = AXApplicationWindows(pid: 60, entries: [(id: 2, element: AXUIElementCreateApplication(601))])
        let scanIdx = indexCache.beginSnapshot()
        indexCache.invalidate(pid: 50)
        indexCache.replaceAll(with: [pid50, pid60], generation: scanIdx)
        #expect(indexCache.windows(for: 50) == nil)
        #expect(indexCache.windows(for: 60)?.element(id: 2) != nil)
    }
}
