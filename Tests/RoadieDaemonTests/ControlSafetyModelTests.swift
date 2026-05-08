import Foundation
import Testing
import RoadieCore

@Suite
struct ControlSafetyModelTests {
    @Test
    func controlCenterStateRoundTripsJSON() throws {
        let state = ControlCenterState(
            daemonStatus: .running,
            configPath: "~/.config/roadies/roadies.toml",
            configStatus: .valid,
            activeDesktop: "1",
            activeStage: "dev",
            windowCount: 3
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ControlCenterState.self, from: data)

        #expect(decoded == state)
        #expect(decoded.actions.canReloadConfig)
    }

    @Test
    func restoreSnapshotRoundTripsWindowIdentity() throws {
        let identity = WindowIdentityV2(
            bundleID: "com.apple.Terminal",
            appName: "Terminal",
            title: "dev",
            role: "AXWindow",
            subrole: "AXStandardWindow",
            windowIDHint: 42
        )
        let window = RestoreWindowState(
            windowID: 42,
            identity: identity,
            frame: Rect(x: 0, y: 0, width: 800, height: 600),
            visibleFrame: Rect(x: 10, y: 10, width: 800, height: 600)
        )
        let snapshot = RestoreSafetySnapshot(daemonPID: 1234, windows: [window])

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(RestoreSafetySnapshot.self, from: data)

        #expect(decoded.windows.first?.identity == identity)
        #expect(decoded.windows.first?.wasManaged == true)
    }

    @Test
    func widthAdjustmentIntentCapturesRequest() {
        let intent = WidthAdjustmentIntent(scope: .activeRoot, mode: .nudge, delta: 0.05)

        #expect(intent.scope == .activeRoot)
        #expect(intent.mode == .nudge)
        #expect(intent.delta == 0.05)
    }
}
