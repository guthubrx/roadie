import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

private final class PointRecorder: @unchecked Sendable {
    private(set) var points: [CGPoint] = []

    func append(_ point: CGPoint) {
        points.append(point)
    }
}

@Suite
struct ConfigTests {
    @Test
    func borderConfigDecodesFromToml() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-config-\(UUID().uuidString).toml")
        try """
        [fx.borders]
        enabled = true
        thickness = 3
        corner_radius = 12
        active_color = "#7AA2F7"
        inactive_color = "#414868"
        pulse_on_focus = true

        [[fx.borders.stage_overrides]]
        stage_id = "2"
        active_color = "#F7768E"
        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let config = try RoadieConfigLoader.load(from: url.path)

        #expect(config.fx.borders.enabled)
        #expect(config.fx.borders.thickness == 3)
        #expect(config.fx.borders.cornerRadius == 12)
        #expect(config.fx.borders.activeColor == "#7AA2F7")
        #expect(config.fx.borders.stageOverrides == [
            BorderStageOverride(stageID: "2", activeColor: "#F7768E")
        ])
    }

    @Test
    func focusConfigDecodesFromToml() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-focus-config-\(UUID().uuidString).toml")
        try """
        [focus]
        stage_follows_focus = false
        assign_follows_focus = true
        focus_follows_mouse = true
        mouse_follows_focus = true
        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let config = try RoadieConfigLoader.load(from: url.path)

        #expect(config.focus.stageFollowsFocus == false)
        #expect(config.focus.assignFollowsFocus)
        #expect(config.focus.focusFollowsMouse)
        #expect(config.focus.mouseFollowsFocus)
    }

    @Test
    func mouseFollowerMovesToWindowCenterOnlyWhenEnabled() {
        let window = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 1,
            appName: "App",
            bundleID: "app",
            title: "Window",
            frame: Rect(x: 10, y: 20, width: 100, height: 60),
            isOnScreen: true,
            isTileCandidate: true
        )
        let recorder = PointRecorder()

        MouseFollower(isEnabled: { false }, move: { recorder.append($0) }).follow(window)
        #expect(recorder.points.isEmpty)

        MouseFollower(isEnabled: { true }, move: { recorder.append($0) }).follow(window)
        #expect(recorder.points == [CGPoint(x: 60, y: 50)])
    }
}
