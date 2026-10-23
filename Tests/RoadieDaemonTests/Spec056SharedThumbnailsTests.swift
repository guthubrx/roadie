import AppKit
import RoadieCore
import Testing
@testable import RoadieDaemon

@MainActor
struct Spec056SharedThumbnailsTests {
    @Test func closingOneConsumerPreservesTheOtherConsumersImage() throws {
        let cache = RailThumbnailStore()
        let id = WindowID(rawValue: 901)
        let member = PersistentStageMember(windowID: id, bundleID: "com.apple.finder", title: "Fixture",
                                           frame: Rect(x: 0, y: 0, width: 300, height: 200))
        cache.prune(keeping: [id], owner: "rail")
        let icon = try #require(cache.images(for: [member])[id])
        cache.prune(keeping: [id], owner: "switcher")

        cache.prune(keeping: [], owner: "rail")
        #expect(cache.cachedImage(for: id) === icon)
        cache.prune(keeping: [id], owner: "rail")
        cache.prune(keeping: [], owner: "switcher")
        #expect(cache.cachedImage(for: id) === icon)

        cache.prune(keeping: [], owner: "rail")
        #expect(cache.cachedImage(for: id) == nil)
    }
}
