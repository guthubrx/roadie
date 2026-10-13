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
        stage_move_follows_focus = false
        focus_follows_mouse = true
        mouse_follows_focus = true
        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let config = try RoadieConfigLoader.load(from: url.path)

        #expect(config.focus.stageFollowsFocus == false)
        #expect(config.focus.assignFollowsFocus)
        #expect(config.focus.stageMoveFollowsFocus == false)
        #expect(config.focus.focusFollowsMouse)
        #expect(config.focus.mouseFollowsFocus)
    }

    @Test
    func focusStageMoveFollowDefaultsToTrue() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-focus-stage-move-default-\(UUID().uuidString).toml")
        try """
        [focus]
        stage_follows_focus = false
        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let config = try RoadieConfigLoader.load(from: url.path)

        #expect(config.focus.stageMoveFollowsFocus)
    }

    @Test
    func windowPlacementConfigDecodesFromToml() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-window-placement-\(UUID().uuidString).toml")
        try """
        [window_placement]
        new_apps_target = "mouse"
        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let config = try RoadieConfigLoader.load(from: url.path)

        #expect(config.windowPlacement.newAppsTarget == "mouse")
    }

    @Test
    func windowPlacementDefaultsToMacOS() {
        let config = RoadieConfig()

        #expect(config.windowPlacement.newAppsTarget == "macos")
    }

    @Test
    func generatedRulesAreMergedWithUserConfig() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-generated-rules-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("roadies.toml")
        try """
        [focus]
        stage_follows_focus = false
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let generatedURL = URL(fileURLWithPath: RoadieConfigLoader.generatedRulesPath(for: configURL.path))
        try """
        [[rules]]
        id = "affinity-app-firefox"
        priority = 9000

        [rules.match]
        app = "Firefox"

        [rules.action]
        assign_display = "display-main"
        assign_desktop = "1"
        assign_stage = "web"
        follow = false
        """.write(to: generatedURL, atomically: true, encoding: .utf8)

        let config = try RoadieConfigLoader.load(from: configURL.path)
        let report = RoadieConfigLoader.validate(path: configURL.path)

        #expect(config.focus.stageFollowsFocus == false)
        #expect(config.rules.count == 1)
        #expect(config.rules.first?.id == "affinity-app-firefox")
        #expect(config.rules.first?.action.assignDisplay == "display-main")
        #expect(report.hasErrors == false)
    }

    @Test
    func generatedRulesValidationReportsGeneratedFileErrors() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-generated-rules-error-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("roadies.toml")
        try "[focus]\nstage_follows_focus = false\n".write(to: configURL, atomically: true, encoding: .utf8)
        let generatedURL = URL(fileURLWithPath: RoadieConfigLoader.generatedRulesPath(for: configURL.path))
        try """
        [[rules]]
        id = 42
        """.write(to: generatedURL, atomically: true, encoding: .utf8)

        let report = RoadieConfigLoader.validate(path: configURL.path)

        #expect(report.hasErrors)
        #expect(report.items.contains { $0.path == generatedURL.path })
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
        hide_on_maximized = true

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

        [fx.rail.stage_labels]
        enabled = true
        color = "stage"
        font_size = 12
        font_family = "Avenir Next"
        weight = "bold"
        alignment = "left"
        opacity = 0.66
        offset_x = 4
        offset_y = -5
        placement = "above"
        z_order = "below"
        visibility_seconds = 5
        fade_seconds = 0.4

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
        #expect(settings.hideOnMaximized == true)
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
        #expect(settings.stageLabel.enabled == true)
        #expect(settings.stageLabel.color == "stage")
        #expect(settings.stageLabel.fontSize == 12)
        #expect(settings.stageLabel.fontFamily == "Avenir Next")
        #expect(settings.stageLabel.weight == "bold")
        #expect(settings.stageLabel.alignment == "left")
        #expect(settings.stageLabel.opacity == 0.66)
        #expect(settings.stageLabel.offsetX == 4)
        #expect(settings.stageLabel.offsetY == -5)
        #expect(settings.stageLabel.placement == "above")
        #expect(settings.stageLabel.zOrder == "below")
        #expect(settings.stageLabel.visibilitySeconds == 5)
        #expect(settings.stageLabel.fadeSeconds == 0.4)
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
    func railSettingsHideOnMaximizedDefaultsToNativeFullscreenOnly() {
        #expect(RailSettings.load(raw: "").hideOnMaximized == false)
        #expect(RailSettings.load(raw: "[fx.rail]\nhide_on_maximized = \"nope\"").hideOnMaximized == false)
        #expect(RailSettings.load(raw: "[fx.rail]\nhide_on_maximized = true").hideOnMaximized == true)
    }

    /// FR-023 : la config du rail n'est relue que si le fichier change (audit PERF-001).
    @Test
    func railSettingsFileIsReparsedOnlyWhenItChanges() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-rail-settings-\(UUID().uuidString).toml").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        try "[fx.rail]\nwidth = 200\n".write(toFile: path, atomically: true, encoding: .utf8)

        // Illisible dès la première lecture : valeurs par défaut, sans les garder en cache.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
        let unreadable = RailSettings.load(path: path).width
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        #expect(unreadable == 150 || getuid() == 0)
        #expect(RailSettings.load(path: path).width == 200)

        // Fichier illisible mais signature inchangée (chmod ne touche ni mtime ni taille) :
        // la valeur vient du cache, sans relecture.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
        #expect(RailSettings.load(path: path).width == 200)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)

        try "[fx.rail]\nwidth = 250\n".write(toFile: path, atomically: true, encoding: .utf8)
        #expect(RailSettings.load(path: path).width == 250)
    }

    @Test
    func railRuntimeStateKeepsBackwardCompatiblePinnedDefault() throws {
        let data = #"{"visibleWidths":{"display-a":8}}"#.data(using: .utf8)!

        let state = try JSONDecoder().decode(RailRuntimeState.self, from: data)

        #expect(state.visibleWidths["display-a"] == 8)
        #expect(state.isPinned == false)
        #expect(state.stageLabelsVisibleUntil == nil)
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
    func titlebarContextMenuDefaultsAreSafe() {
        let config = RoadieConfig()

        #expect(config.experimental.titlebarContextMenu.enabled == false)
        #expect(config.experimental.titlebarContextMenu.height == 36)
        #expect(config.experimental.titlebarContextMenu.leadingExclusion == 84)
        #expect(config.experimental.titlebarContextMenu.trailingExclusion == 16)
        #expect(config.experimental.titlebarContextMenu.managedWindowsOnly)
        #expect(config.experimental.titlebarContextMenu.tileCandidatesOnly)
        #expect(config.experimental.titlebarContextMenu.includeStageDestinations)
        #expect(config.experimental.titlebarContextMenu.includeDesktopDestinations)
        #expect(config.experimental.titlebarContextMenu.includeDisplayDestinations)
    }

    @Test
    func titlebarContextMenuConfigDecodesFromToml() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-titlebar-config-\(UUID().uuidString).toml")
        try """
        [experimental.titlebar_context_menu]
        enabled = true
        height = 44
        leading_exclusion = 90
        trailing_exclusion = 22
        managed_windows_only = false
        tile_candidates_only = false
        include_stage_destinations = true
        include_desktop_destinations = false
        include_display_destinations = true
        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let config = try RoadieConfigLoader.load(from: url.path)
        let titlebar = config.experimental.titlebarContextMenu

        #expect(titlebar.enabled)
        #expect(titlebar.height == 44)
        #expect(titlebar.leadingExclusion == 90)
        #expect(titlebar.trailingExclusion == 22)
        #expect(titlebar.managedWindowsOnly == false)
        #expect(titlebar.tileCandidatesOnly == false)
        #expect(titlebar.includeStageDestinations)
        #expect(titlebar.includeDesktopDestinations == false)
        #expect(titlebar.includeDisplayDestinations)
    }

    @Test
    func titlebarContextMenuValidationReportsUnsafeValues() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-titlebar-invalid-\(UUID().uuidString).toml")
        try """
        [experimental.titlebar_context_menu]
        enabled = true
        height = 8
        leading_exclusion = 300
        trailing_exclusion = -1
        include_stage_destinations = false
        include_desktop_destinations = false
        include_display_destinations = false
        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let report = RoadieConfigLoader.validate(path: url.path)

        #expect(report.hasErrors)
        #expect(report.items.contains(ConfigValidationItem(
            level: .error,
            path: "experimental.titlebar_context_menu.height",
            message: "must be between 12 and 96"
        )))
        #expect(report.items.contains(ConfigValidationItem(
            level: .error,
            path: "experimental.titlebar_context_menu.leading_exclusion",
            message: "must be between 0 and 240"
        )))
        #expect(report.items.contains(ConfigValidationItem(
            level: .error,
            path: "experimental.titlebar_context_menu.trailing_exclusion",
            message: "must be between 0 and 240"
        )))
        #expect(report.items.contains(ConfigValidationItem(
            level: .warning,
            path: "experimental.titlebar_context_menu",
            message: "all destination families are disabled; menu will not be shown"
        )))
    }

    @Test
    func targetModeDefaultsKeepRiskyFeaturesDisabled() {
        let config = RoadieConfig()
        let targetMode = config.experimental.targetMode
        let grid = config.experimental.targetGrid
        let record = config.experimental.targetRecord
        let appTargets = config.experimental.appTargets

        #expect(targetMode.enabled)
        #expect(targetMode.pickerEnabled)
        #expect(targetMode.overlayEnabled == false)
        #expect(targetMode.overlayLabelsOnly)
        #expect(targetMode.overlayDurationSeconds == 3)
        #expect(targetMode.appMouseActionsEnabled == false)
        #expect(targetMode.scrollModeEnabled == false)
        #expect(appTargets.axBoostEnabled == false)
        #expect(appTargets.maxDepth == 12)
        #expect(grid.enabled == false)
        #expect(grid.overlayEnabled)
        #expect(grid.overlayDrawGrid)
        #expect(grid.overlayFillColor == "#4DABF7")
        #expect(grid.overlayFillOpacity == 0.10)
        #expect(grid.overlayBorderColor == "#4DABF7")
        #expect(grid.overlayBorderOpacity == 0.55)
        #expect(grid.overlayLabelColor == "#FFFFFF")
        #expect(grid.rows == 3)
        #expect(grid.columns == 3)
        #expect(grid.maxDepth == 3)
        #expect(grid.hintCharacters == "azeqsdwxc")
        #expect(grid.defaultScope == .display)
        #expect(record.enabled == false)
        #expect(record.replayEnabled == false)
        #expect(record.includeAXContext)
        #expect(record.recordTextInput == false)
    }

    @Test
    func targetModeConfigDecodesFromToml() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-target-mode-config-\(UUID().uuidString).toml")
        try """
        [experimental.target_mode]
        enabled = true
        picker_enabled = false
        overlay_enabled = true
        overlay_labels_only = false
        overlay_duration_seconds = 5.5
        app_mouse_actions_enabled = true
        scroll_mode_enabled = true

        [experimental.app_targets]
        enabled = true
        ax_boost_enabled = true
        max_depth = 18
        additional_boost_bundle_ids = ["org.mozilla.firefox"]

        [experimental.target_grid]
        enabled = true
        mode = "auto_click"
        overlay_enabled = false
        overlay_draw_grid = false
        overlay_fill_color = "#123456"
        overlay_fill_opacity = 0.25
        overlay_border_color = "#654321"
        overlay_border_opacity = 0.75
        overlay_label_color = "#ABCDEF"
        overlay_label_background_opacity = 0.33
        rows = 4
        columns = 5
        max_depth = 4
        hint_characters = "abcdefghijklmnopqrst"
        confirm_action_key = "Space"
        reset_key = "R"
        back_key = "Backspace"
        exit_key = "Escape"
        arrow_navigation_enabled = false
        arrow_edge_behavior = "wrap"
        action_delay_ms = 12
        wake_mouse_pixels = 2
        mouse_follow_grid = true
        focus_follow_grid = true
        label_placement = "center"
        default_scope = "focused_window"

        [experimental.target_record]
        enabled = true
        replay_enabled = true
        default_duration_seconds = 7
        max_events = 333
        include_mouse_moves = true
        record_text_input = true
        indicator = "both"
        navrail_bottom_offset = 64
        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let config = try RoadieConfigLoader.load(from: url.path)
        let targetMode = config.experimental.targetMode
        let appTargets = config.experimental.appTargets
        let grid = config.experimental.targetGrid
        let record = config.experimental.targetRecord

        #expect(targetMode.enabled)
        #expect(targetMode.pickerEnabled == false)
        #expect(targetMode.overlayEnabled)
        #expect(targetMode.overlayLabelsOnly == false)
        #expect(targetMode.overlayDurationSeconds == 5.5)
        #expect(targetMode.appMouseActionsEnabled)
        #expect(targetMode.scrollModeEnabled)
        #expect(appTargets.enabled)
        #expect(appTargets.axBoostEnabled)
        #expect(appTargets.maxDepth == 18)
        #expect(appTargets.additionalBoostBundleIDs == ["org.mozilla.firefox"])
        #expect(grid.enabled)
        #expect(grid.mode == .autoClick)
        #expect(grid.overlayEnabled == false)
        #expect(grid.overlayDrawGrid == false)
        #expect(grid.overlayFillColor == "#123456")
        #expect(grid.overlayFillOpacity == 0.25)
        #expect(grid.overlayBorderColor == "#654321")
        #expect(grid.overlayBorderOpacity == 0.75)
        #expect(grid.overlayLabelColor == "#ABCDEF")
        #expect(grid.overlayLabelBackgroundOpacity == 0.33)
        #expect(grid.rows == 4)
        #expect(grid.columns == 5)
        #expect(grid.maxDepth == 4)
        #expect(grid.hintCharacters == "abcdefghijklmnopqrst")
        #expect(grid.confirmActionKey == "space")
        #expect(grid.resetKey == "r")
        #expect(grid.backKey == "backspace")
        #expect(grid.exitKey == "escape")
        #expect(grid.arrowNavigationEnabled == false)
        #expect(grid.arrowEdgeBehavior == .wrap)
        #expect(grid.actionDelayMs == 12)
        #expect(grid.wakeMousePixels == 2)
        #expect(grid.mouseFollowGrid)
        #expect(grid.focusFollowGrid)
        #expect(grid.labelPlacement == .center)
        #expect(grid.defaultScope == .focusedWindow)
        #expect(record.enabled)
        #expect(record.indicator == .both)
        #expect(record.navrailBottomOffset == 64)
        #expect(record.replayEnabled)
        #expect(record.defaultDurationSeconds == 7)
        #expect(record.maxEvents == 333)
        #expect(record.includeMouseMoves)
        #expect(record.recordTextInput)
    }

    @Test
    func targetModeValidationReportsUnsafeValues() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-target-mode-invalid-\(UUID().uuidString).toml")
        try """
        [experimental.target_mode]
        enabled = false
        picker_enabled = true
        overlay_enabled = true
        overlay_duration_seconds = 90
        app_mouse_actions_enabled = true
        scroll_mode_enabled = true
        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let report = RoadieConfigLoader.validate(path: url.path)

        #expect(report.hasErrors)
        #expect(report.items.contains(ConfigValidationItem(
            level: .error,
            path: "experimental.target_mode.overlay_duration_seconds",
            message: "must be between 0.2 and 30"
        )))
        #expect(report.items.contains(ConfigValidationItem(
            level: .warning,
            path: "experimental.target_mode",
            message: "target mode is disabled; sub-features will be ignored"
        )))
    }

    // MARK: - SPEC-021 : raccourci du mode recherche

    @Test
    func searchHotkeyDefaultsToHyperFAndAcceptsAliases() throws {
        #expect(TargetModeConfig().searchHotkey == "command+control+alt+f")
        #expect(TargetModeConfig(searchHotkey: "Hyper + F").searchHotkey == "command+control+alt+f")
        #expect(TargetModeConfig(searchHotkey: "ctrl+option+space").searchHotkey == "control+alt+space")
        #expect(TargetModeConfig(searchHotkey: "").searchHotkey == "")
        let parts = TargetModeConfig.hotkeyParts("command+control+alt+f")
        #expect(parts?.modifiers == ["command", "control", "alt"])
        #expect(parts?.key == "f")
        #expect(TargetModeConfig.hotkeyParts("f") == nil)
        #expect(TargetModeConfig.hotkeyParts("command+f+g") == nil)
    }

    @Test
    func searchHotkeyValidationRejectsAKeyWithoutModifier() throws {
        let invalid = try validate("""
        [experimental.target_mode]
        search_hotkey = "f"
        """)
        let valid = try validate("""
        [experimental.target_mode]
        search_hotkey = "cmd+alt+ctrl+f"
        """)
        #expect(invalid.items.contains { $0.path == "experimental.target_mode.search_hotkey" && $0.level == .error })
        #expect(!valid.items.contains { $0.path.hasPrefix("experimental.target_mode.search_hotkey") })
    }

    // MARK: - Validation SPEC-016 (clés inconnues, messages lisibles, tables fx.rail.*)

    private func validate(_ toml: String) throws -> ConfigValidationReport {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-validate-\(UUID().uuidString).toml")
        try toml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return RoadieConfigLoader.validate(path: url.path)
    }

    @Test
    func validationSuggestsClosestKnownKeyForTypos() throws {
        let report = try validate("""
        [tiling]
        gaps_inr = 4

        [fx.borderz]
        enabled = true
        """)

        #expect(!report.hasErrors)
        let key = report.items.first { $0.path == "tiling.gaps_inr" }
        #expect(key?.level == .warning)
        #expect(key?.message.contains("gaps_inner") == true)
        let table = report.items.first { $0.path == "fx.borderz" }
        #expect(table?.message.contains("fx.borders") == true)
    }

    @Test
    func validationDoesNotSuggestWhenNothingIsClose() throws {
        let report = try validate("""
        [tiling]
        completely_unrelated_option = 1
        """)

        let item = report.items.first { $0.path == "tiling.completely_unrelated_option" }
        #expect(item?.level == .warning)
        #expect(item?.message.contains("vouliez-vous dire") == false)
    }

    @Test
    func validationTranslatesDecodeErrors() throws {
        let wrongType = try validate("""
        [focus]
        stage_follows_focus = "yes"
        """)
        #expect(wrongType.hasErrors)
        #expect(wrongType.items.first?.message == "focus.stage_follows_focus : attendu booléen, reçu texte")

        let missingKey = try validate("""
        [[rules]]
        priority = 3
        """)
        #expect(missingKey.hasErrors)
        #expect(missingKey.items.first?.message == "rules[0].id : clé obligatoire absente (attendu texte)")
    }

    @Test
    func validationAcceptsEveryRailTableWithoutWarning() throws {
        let report = try validate("""
        [fx.rail]
        renderer = "stacked-previews"
        width = 150
        background_color = "#000000"
        background_opacity = 0
        auto_hide = false
        edge_hit_width = 8
        edge_magnetism_width = 24
        animation_ms = 160
        hide_delay_ms = 350
        layout_mode = "overlay"
        dynamic_left_gap = false
        empty_click_hide_active = false
        empty_click_safety_margin = 12
        hide_on_maximized = true

        [fx.rail.layout]
        header_position = "top"
        stages_position = "center"
        spacing = 13
        top_padding = 50
        bottom_padding = 16

        [fx.rail.header]
        enabled = true
        title_template = "{display}"

        [fx.rail.header.display]
        enabled = true
        template = "{display}"
        font_size = 13

        [fx.rail.header.desktop]
        enabled = true
        template = "Desktop {desktop}"

        [fx.rail.stage_labels]
        enabled = true
        placement = "below"

        [fx.rail.stages]
        position = "center"
        gap = 13

        [fx.rail.preview]
        width = 160

        [fx.rail.stacked]
        offset_x = 60

        [fx.rail.parallax]
        rotation = 35

        [[fx.rail.preview.stage_overrides]]
        stage_id = "2"
        active_color = "#6BE675"
        """)

        #expect(report.items == [ConfigValidationItem(level: .ok, path: report.items.first?.path ?? "", message: "config is valid")])
    }

    @Test
    func validationFlagsKeysThatHaveNoEffect() throws {
        let report = try validate("""
        [desktops]
        count = 5

        [stage_manager]
        enabled = true
        hide_strategy = "corner"
        default_stage = "1"

        [fx.rail.header]
        enabled = true
        height = 60
        width = 200
        """)

        #expect(!report.hasErrors)
        for path in ["desktops.count", "stage_manager.enabled", "stage_manager.hide_strategy", "fx.rail.header.height", "fx.rail.header.width"] {
            let item = report.items.first { $0.path == path }
            #expect(item?.level == .warning)
            #expect(item?.message.hasPrefix("clé sans effet") == true)
        }
        #expect(report.items.contains { $0.path == "stage_manager.default_stage" } == false)
        #expect(report.items.contains { $0.path == "fx.rail.header.enabled" } == false)
    }

    @Test
    func shippedExampleConfigIsValidWithoutWarning() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let example = repoRoot.appendingPathComponent("examples/roadies.toml").path

        let report = RoadieConfigLoader.validate(path: example)

        #expect(report.items.allSatisfy { $0.level == .ok }, "\(report.items)")
        #expect(report.items.isEmpty == false)
    }

    // MARK: - SPEC-023 : taille des étiquettes et lecture des clés connues

    @Test
    func labelFontSizeDefaultsToThirteenAndIsClampedAtDecoding() throws {
        #expect(TargetModeConfig().labelFontSize == 13)
        #expect(TargetGridConfig().labelFontSize == 13)
        #expect(TargetModeConfig(labelFontSize: 5).labelFontSize == 8)
        #expect(TargetModeConfig(labelFontSize: 99).labelFontSize == 48)
        #expect(TargetGridConfig(labelFontSize: 5).labelFontSize == 8)
        #expect(TargetGridConfig(labelFontSize: 99).labelFontSize == 48)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-label-font-\(UUID().uuidString).toml")
        try """
        [experimental.target_mode]
        label_font_size = 5

        [experimental.target_grid]
        label_font_size = 99
        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let config = try RoadieConfigLoader.load(from: url.path)
        #expect(config.experimental.targetMode.labelFontSize == 8)
        #expect(config.experimental.targetGrid.labelFontSize == 48)

        let defaults = try RoadieConfigLoader.load(from: "/nonexistent/roadie-\(UUID().uuidString).toml")
        #expect(defaults.experimental.targetMode.labelFontSize == 13)
        #expect(defaults.experimental.targetGrid.labelFontSize == 13)

        // Le clamp suffit : une valeur hors plage ne produit ni erreur ni avertissement de validation (T032).
        let report = try validate("""
        [experimental.target_mode]
        label_font_size = 5

        [experimental.target_grid]
        label_font_size = 99
        """)
        #expect(report.items.allSatisfy { $0.level == .ok }, "\(report.items)")
    }

    @Test
    func labelFontSizeAcceptsIntegerAndFloatAndIsNotFlaggedUnknown() throws {
        let report = try validate("""
        [experimental.target_mode]
        label_font_size = 20

        [experimental.target_grid]
        label_font_size = 18.5
        """)
        #expect(report.items.allSatisfy { $0.level == .ok }, "\(report.items)")
        #expect(!report.items.contains { $0.message.contains("clé inconnue") })
    }

    @Test
    func labelFontSizeAsStringIsReportedAsTypeError() throws {
        let report = try validate("""
        [experimental.target_mode]
        label_font_size = "grand"
        """)
        #expect(report.hasErrors)
    }

    @Test
    func knownScalarKeysExposeScalarsOnly() {
        let known = RoadieConfigLoader.knownScalarKeys()
        let grid = known["experimental.target_grid"] ?? []
        #expect(grid.contains("rows"))
        #expect(grid.contains("label_font_size"))
        #expect(known["experimental.target_mode"]?.contains("label_font_size") == true)
        #expect(known["tiling"]?.contains("display_overrides") == false)
        #expect(known["tiling"]?.contains("gaps_inner") == true)
        #expect(known["rules"] == nil)
        #expect(known["tiling.display_overrides"] == nil)
    }

    @Test
    func ineffectiveKeysAndEditDistanceAreExposed() {
        #expect(RoadieConfigLoader.ineffectiveKeys()["desktops"]?.contains("count") == true)
        #expect(RoadieConfigLoader.editDistance("stage", "stagee") == 1)
        #expect(RoadieConfigLoader.editDistance("", "abc") == 3)
        #expect(RoadieConfigLoader.editDistance("rows", "rows") == 0)
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
