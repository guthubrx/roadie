import XCTest
import CoreGraphics
@testable import RoadieCore

final class ThumbnailCacheTests: XCTestCase {

    private func makeEntry(wid: CGWindowID) -> ThumbnailEntry {
        ThumbnailEntry(wid: wid, pngData: Data([0, 1, 2]),
                       size: CGSize(width: 320, height: 200),
                       degraded: false, capturedAt: Date())
    }

    // MARK: - put / get

    func testPutGet() {
        let cache = ThumbnailCache()
        let entry = makeEntry(wid: 1)
        cache.put(entry)
        let got = cache.get(wid: 1)
        XCTAssertNotNil(got)
        XCTAssertEqual(got?.wid, 1)
    }

    func testGetMissReturnsNil() {
        let cache = ThumbnailCache()
        XCTAssertNil(cache.get(wid: 99))
    }

    func testPutReplaces() {
        let cache = ThumbnailCache()
        cache.put(makeEntry(wid: 1))
        let updated = ThumbnailEntry(wid: 1, pngData: Data([9, 8]),
                                      size: CGSize(width: 160, height: 100),
                                      degraded: true)
        cache.put(updated)
        XCTAssertEqual(cache.count, 1)
        XCTAssertEqual(cache.get(wid: 1)?.degraded, true)
    }

    // MARK: - accessOrder MRU

    func testAccessOrderMRU() {
        let cache = ThumbnailCache(capacity: 10)
        for i in 1...5 { cache.put(makeEntry(wid: CGWindowID(i))) }
        // Accède à wid=2 → doit être en tête
        _ = cache.get(wid: 2)
        // Insère nouvelle entrée jusqu'au seuil de capacity
        // Vérifie juste que count reste stable ici
        XCTAssertEqual(cache.count, 5)
        // Accède à wid=2 de nouveau → toujours présent
        XCTAssertNotNil(cache.get(wid: 2))
    }

    // MARK: - Eviction LRU à capacity=3

    func testEvictionLRU() {
        let cache = ThumbnailCache(capacity: 3)
        cache.put(makeEntry(wid: 1)) // accessOrder: [1]
        cache.put(makeEntry(wid: 2)) // accessOrder: [2, 1]
        cache.put(makeEntry(wid: 3)) // accessOrder: [3, 2, 1]
        XCTAssertEqual(cache.count, 3)

        // Accès à wid=1 le promeut en tête → accessOrder: [1, 3, 2]
        _ = cache.get(wid: 1)

        // Insertion wid=4 → eviction LRU = wid=2 (queue)
        cache.put(makeEntry(wid: 4))
        XCTAssertEqual(cache.count, 3)
        XCTAssertNil(cache.get(wid: 2), "wid=2 devait être évincé (LRU)")
        XCTAssertNotNil(cache.get(wid: 1))
        XCTAssertNotNil(cache.get(wid: 3))
        XCTAssertNotNil(cache.get(wid: 4))
    }

    func testEvictionAt50() {
        let cache = ThumbnailCache(capacity: 50)
        for i in 1...50 { cache.put(makeEntry(wid: CGWindowID(i))) }
        XCTAssertEqual(cache.count, 50)
        // Insertion du 51ème → eviction du 1er (LRU, jamais ré-accédé)
        cache.put(makeEntry(wid: 51))
        XCTAssertEqual(cache.count, 50)
        XCTAssertNil(cache.get(wid: 1), "wid=1 devait être évincé")
        XCTAssertNotNil(cache.get(wid: 51))
    }

    // MARK: - evict explicite

    func testEvictExplicit() {
        let cache = ThumbnailCache()
        cache.put(makeEntry(wid: 5))
        XCTAssertEqual(cache.count, 1)
        cache.evict(wid: 5)
        XCTAssertEqual(cache.count, 0)
        XCTAssertNil(cache.get(wid: 5))
    }

    func testEvictMissingIsNoOp() {
        let cache = ThumbnailCache()
        cache.evict(wid: 999) // ne doit pas crasher
        XCTAssertEqual(cache.count, 0)
    }

    // MARK: - clear

    func testClear() {
        let cache = ThumbnailCache()
        for i in 1...5 { cache.put(makeEntry(wid: CGWindowID(i))) }
        cache.clear()
        XCTAssertEqual(cache.count, 0)
        XCTAssertNil(cache.get(wid: 1))
    }
}
