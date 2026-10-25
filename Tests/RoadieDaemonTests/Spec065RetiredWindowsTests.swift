import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

struct Spec065RetiredWindowsTests {
    private let retired = WindowID(rawValue: 781)
    private let otherDesktop = WindowID(rawValue: 782)
    private let hiddenApp = WindowID(rawValue: 783)
    private let minimized = WindowID(rawValue: 784)

    @Test func unlistedWindowWithoutDesktopIsRetired() {
        let states = [
            retired: WindowSwitcherAXState(visibilityKnown: false, isListed: false),
            otherDesktop: WindowSwitcherAXState(visibilityKnown: false, isListed: false),
            hiddenApp: WindowSwitcherAXState(isHidden: true, visibilityKnown: false, isListed: false),
            minimized: WindowSwitcherAXState(isMinimized: true)
        ]
        var asked: Set<WindowID> = []
        let result = WindowSwitcherService.retiredWindows(states) { ids in
            asked = ids
            return [retired, hiddenApp, minimized]
        }
        #expect(result == [retired])
        #expect(asked == [retired, otherDesktop])
    }

    @Test func nothingIsRetiredWithoutSkyLightAnswer() {
        let states = [retired: WindowSwitcherAXState(visibilityKnown: false, isListed: false)]
        #expect(WindowSwitcherService.retiredWindows(states) { _ in nil }.isEmpty)
    }

    @Test func listedWindowsSkipTheDesktopQuery() {
        var queried = false
        let states = [minimized: WindowSwitcherAXState(isMinimized: true)]
        let result = WindowSwitcherService.retiredWindows(states) { _ in queried = true; return [minimized] }
        #expect(result.isEmpty)
        #expect(!queried)
    }
}
