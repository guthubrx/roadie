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
    func controlSafetyConfigDecodesFromToml() throws {
        let url = try #require(Bundle.module.url(forResource: "control-safety-valid", withExtension: "toml"))

        let config = try RoadieConfigLoader.load(from: url.path)

        #expect(config.controlCenter.enabled)
        #expect(config.controlCenter.showMenuBar)
        #expect(config.configReload.debounceMS == 250)
        #expect(config.configReload.keepPreviousOnError)
        #expect(config.restoreSafety.restoreOnExit)
        #expect(config.restoreSafety.snapshotPath == "~/.local/state/roadies/restore.json")
        #expect(config.transientWindows.pauseTiling)
        #expect(config.layoutPersistence.version == 2)
        #expect(config.layoutPersistence.minimumMatchScore == 0.75)
        #expect(config.widthAdjustment.presets == [0.5, 0.67, 0.8, 1.0])
        #expect(config.widthAdjustment.nudgeStep == 0.05)
    }

    @Test
    func controlSafetyConfigValidationRejectsInvalidRanges() throws {
        let url = try #require(Bundle.module.url(forResource: "control-safety-invalid", withExtension: "toml"))

        let report = RoadieConfigLoader.validate(path: url.path)

        #expect(report.hasErrors)
        #expect(report.items.contains { $0.level == .error })
    }

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
    func displayTilingOverridesDecodeFromToml() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-display-gap-config-\(UUID().uuidString).toml")
        try """
        [tiling]
        gaps_outer = 8
        gaps_outer_left = 150

        [[tiling.display_overrides]]
        display_name = "LG HDR 4K"
        gaps_outer_left = 180

        [[tiling.display_overrides]]
        display_id = "builtin-uuid"
        gaps_outer_left = 140
        gaps_outer_bottom = 48
        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let config = try RoadieConfigLoader.load(from: url.path)

        #expect(config.tiling.gapsOuter == 8)
        #expect(config.tiling.gapsOuterLeft == 150)
        #expect(config.tiling.displayOverrides.count == 2)
        #expect(config.tiling.displayOverrides[0].displayName == "LG HDR 4K")
        #expect(config.tiling.displayOverrides[0].gapsOuterLeft == 180)
        #expect(config.tiling.displayOverrides[1].displayID == "builtin-uuid")
        #expect(config.tiling.displayOverrides[1].gapsOuterBottom == 48)
    }

    @Test
    func railSettingsDecodeRendererGeometryAndStageAccents() {
        let settings = RailSettings.load(raw: """
        [fx.rail]
        renderer = "parallax-45"
        width = 150
        background_color = "#101820"
        background_opacity = 0.35
        auto_hide = true
        edge_hit_width = 10
        edge_magnetism_width = 32
        animation_ms = 120
        hide_delay_ms = 250
        layout_mode = "resize"
        dynamic_left_gap = true
        empty_click_hide_active = false
        empty_click_safety_margin = 24

        [fx.rail.layout]
        header_position = "top"
        stages_position = "bottom"
        spacing = 17
        top_padding = 18
        bottom_padding = 9

        [fx.rail.header.display]
        enabled = true
        template = "{display}"
        color = "#FFFFFFFF"
        font_size = 14
        font_family = "Avenir Next"
        weight = "semibold"
        alignment = "center"
        opacity = 0.8
        offset_x = 2
        offset_y = 3

        [fx.rail.header.desktop]
        enabled = true
        template = "Bureau {desktop}"
        color = "#FFFFFF88"
        font_size = 11
        font_family = "Avenir Next"
        weight = "regular"
        alignment = "right"
        opacity = 0.6
        offset_x = -2
        offset_y = -3

        [fx.rail.stages]
        position = "bottom"
        alignment = "center"
        gap = 19

        [fx.rail.preview]
        width = 160
        height = 104
        leading_padding = 8
        trailing_padding = 16
        vertical_padding = 20

        [fx.rail.parallax]
        rotation = 35
        offset_x = 25
        offset_y = 18
        scale_per_layer = 0.08
        opacity_per_layer = 0.20
        darken_per_layer = 0.15
        width = 120
        height = 78
        leading_padding = 4
        trailing_padding = 8
        vertical_padding = 12

        [[fx.rail.preview.stage_overrides]]
        stage_id = "2"
        active_color = "#6BE675"
        """)

        #expect(settings.renderer == "parallax-45")
        #expect(settings.width == 150)
        #expect(settings.backgroundColor == "#101820")
        #expect(settings.backgroundOpacity == 0.35)
        #expect(settings.autoHide == true)
        #expect(settings.edgeHitWidth == 10)
        #expect(settings.edgeMagnetismWidth == 32)
        #expect(settings.animationMS == 120)
        #expect(settings.hideDelayMS == 250)
        #expect(settings.layoutMode == "resize")
        #expect(settings.dynamicLeftGap == true)
        #expect(settings.emptyClickHideActive == false)
        #expect(settings.emptyClickSafetyMargin == 24)
        #expect(settings.layout.headerPosition == "top")
        #expect(settings.layout.stagesPosition == "bottom")
        #expect(settings.layout.spacing == 17)
        #expect(settings.layout.topPadding == 18)
        #expect(settings.layout.bottomPadding == 9)
        #expect(settings.displayLabel.enabled == true)
        #expect(settings.displayLabel.template == "{display}")
        #expect(settings.displayLabel.color == "#FFFFFFFF")
        #expect(settings.displayLabel.fontSize == 14)
        #expect(settings.displayLabel.fontFamily == "Avenir Next")
        #expect(settings.displayLabel.weight == "semibold")
        #expect(settings.displayLabel.alignment == "center")
        #expect(settings.displayLabel.opacity == 0.8)
        #expect(settings.displayLabel.offsetX == 2)
        #expect(settings.displayLabel.offsetY == 3)
        #expect(settings.desktopLabel.template == "Bureau {desktop}")
        #expect(settings.desktopLabel.color == "#FFFFFF88")
        #expect(settings.desktopLabel.fontSize == 11)
        #expect(settings.desktopLabel.weight == "regular")
        #expect(settings.desktopLabel.alignment == "right")
        #expect(settings.desktopLabel.opacity == 0.6)
        #expect(settings.desktopLabel.offsetX == -2)
        #expect(settings.desktopLabel.offsetY == -3)
        #expect(settings.stages.position == "bottom")
        #expect(settings.stages.alignment == "center")
        #expect(settings.stages.gap == 19)
        #expect(settings.preview.width == 160)
        #expect(settings.parallax.rotation == 35)
        #expect(settings.parallax.width == 120)
        #expect(settings.parallax.leadingPadding == 4)
        #expect(settings.stageAccents == ["2": "#6BE675"])
    }

    @Test
    func railSettingsDefaultsCenterStagesAndReserveHeaderTopPadding() {
        let settings = RailSettings.load(raw: "")

        #expect(settings.layout.stagesPosition == "center")
        #expect(settings.stages.position == "center")
        #expect(settings.layout.topPadding == 50)
    }

    @Test
    func railRuntimeStateKeepsBackwardCompatiblePinnedDefault() throws {
        let data = #"{"visibleWidths":{"display-a":8}}"#.data(using: .utf8)!

        let state = try JSONDecoder().decode(RailRuntimeState.self, from: data)

        #expect(state.visibleWidths["display-a"] == 8)
        #expect(state.isPinned == false)
    }

    @Test
    func configValidationReportsUnsupportedTablesAsWarnings() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-unsupported-config-\(UUID().uuidString).toml")
        try """
        [tiling]
        default_strategy = "bsp"

        [mouse]
        modifier = "cmd"
        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let report = RoadieConfigLoader.validate(path: url.path)

        #expect(!report.hasErrors)
        #expect(report.items.contains(ConfigValidationItem(
            level: .warning,
            path: "mouse",
            message: "known but not fully supported yet"
        )))
    }

    @Test
    func configValidationReportsDecodeErrors() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-invalid-config-\(UUID().uuidString).toml")
        try """
        [tiling]
        gaps_inner = "not-a-number"
        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let report = RoadieConfigLoader.validate(path: url.path)

        #expect(report.hasErrors)
        #expect(report.items.first?.level == .error)
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
