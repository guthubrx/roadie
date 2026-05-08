import Testing
import RoadieControlCenter
import RoadieCore

@Suite
struct ControlCenterStateRenderingTests {
    @Test
    func menuModelIncludesStatusAndActions() {
        let state = ControlCenterState(
            daemonStatus: .degraded,
            configStatus: .reloadFailed,
            activeDesktop: "1",
            activeStage: "dev",
            windowCount: 2,
            lastError: "config.reload_failed"
        )

        let model = ControlCenterMenuModel(state: state)
        let titles = model.items.map(\.title)

        #expect(titles.contains("Roadie: degraded"))
        #expect(titles.contains("Config: reloadFailed"))
        #expect(titles.contains("Windows: 2"))
        #expect(model.items.contains { $0.action == .reloadConfig })
        #expect(model.items.contains { $0.action == .quitSafely })
    }

    @Test
    func settingsModelReflectsConfig() {
        let config = RoadieConfig(
            configReload: ConfigReloadConfig(keepPreviousOnError: true),
            restoreSafety: RestoreSafetyConfig(enabled: true),
            transientWindows: TransientWindowsConfig(enabled: true),
            widthAdjustment: WidthAdjustmentConfig(presets: [0.4, 0.8])
        )

        let model = SettingsWindowModel(config: config, configPath: "/tmp/roadies.toml")

        #expect(model.configPath == "/tmp/roadies.toml")
        #expect(model.safeReloadEnabled)
        #expect(model.restoreSafetyEnabled)
        #expect(model.transientWindowsEnabled)
        #expect(model.widthPresets == [0.4, 0.8])
    }
}
