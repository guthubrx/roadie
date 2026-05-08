import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

@Suite
struct WindowIdentityTests {
    @Test
    func scoringRewardsStableAttributes() {
        let service = WindowIdentityService()
        let saved = WindowIdentityV2(bundleID: "app.term", appName: "Terminal", title: "shell", role: "AXWindow")
        let live = WindowIdentityV2(bundleID: "app.term", appName: "Terminal", title: "shell", role: "AXWindow")

        #expect(service.score(saved: saved, live: live) >= 0.9)
    }

    @Test
    func matchingRejectsAmbiguousCandidates() {
        let saved = RestoreWindowState(
            identity: WindowIdentityV2(bundleID: "app.term", appName: "Terminal", title: "shell"),
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            visibleFrame: powerDisplay().visibleFrame
        )
        let live = [
            powerWindow(10, x: 0, app: "Terminal"),
            powerWindow(11, x: 300, app: "Terminal")
        ].map { window -> WindowSnapshot in
            var updated = window
            updated.bundleID = "app.term"
            updated.title = "shell"
            return updated
        }

        let matches = WindowIdentityService().match(saved: [saved], live: live)

        #expect(matches.first?.accepted == false)
        #expect(matches.first?.reason == "ambiguous")
    }
}
