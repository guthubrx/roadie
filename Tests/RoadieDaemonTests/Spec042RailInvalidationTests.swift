import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

@Suite struct Spec042RailInvalidationTests {
    @Test func unchangedContentIsReusedButMissingGraceStillExpires() {
        let now = Date(timeIntervalSince1970: 1000)
        let window = WindowID(rawValue: 1)
        let member = PersistentStageMember(windowID: window, bundleID: "test", title: "Test",
            frame: Rect(x: 0, y: 0, width: 100, height: 100), lastSeenAt: now, missingSince: now)
        var scope = PersistentStageScope(displayID: DisplayID(rawValue: "one"),
                                        stages: [PersistentStage(id: StageID(rawValue: "1"), members: [member])])
        var cache = RailDisplayContentCache()
        #expect(cache.content(scope: scope, presentationStates: [:], liveWindowIDs: [], now: now).stages.count == 1)
        #expect(cache.content(scope: scope, presentationStates: [:], liveWindowIDs: [], now: now.addingTimeInterval(14)).stages.count == 1)
        #expect(cache.builds == 1)
        #expect(cache.content(scope: scope, presentationStates: [:], liveWindowIDs: [], now: now.addingTimeInterval(16)).stages.isEmpty)
        #expect(cache.builds == 2)
        scope.stages[0].name = "Travail"
        #expect(cache.content(scope: scope, presentationStates: [:], liveWindowIDs: [], now: now.addingTimeInterval(16)).stages.count == 1)
        #expect(cache.builds == 3)
        cache.prune(keeping: [])
        _ = cache.content(scope: scope, presentationStates: [:], liveWindowIDs: [window], now: now)
        #expect(cache.builds == 4)
    }

    @Test func onlyChangedScreensAreInvalidatedUnlessSettingsChange() {
        let a = DisplayID(rawValue: "a"), b = DisplayID(rawValue: "b")
        let previous = [a: "content:thumbnail-1", b: "content:thumbnail-2"]
        #expect(RailController.changedDisplayIDs(previous: previous, current: previous, settingsChanged: false).isEmpty)
        let updated = [a: "content:thumbnail-3", b: "content:thumbnail-2"]
        #expect(RailController.changedDisplayIDs(previous: previous, current: updated, settingsChanged: false) == [a])
        #expect(RailController.changedDisplayIDs(previous: previous, current: updated, settingsChanged: true) == [a, b])
        #expect(RailController.changedDisplayIDs(previous: previous, current: [a: previous[a]!], settingsChanged: false) == [b])
    }
}
