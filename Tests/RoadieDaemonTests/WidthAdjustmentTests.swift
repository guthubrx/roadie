import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct WidthAdjustmentTests {
    @Test
    func appliesExplicitRatioToActiveWindow() {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100), powerWindow(2, x: 500)])
        let writer = PowerUserWriter(provider: provider)
        // Config explicite pour ne pas dépendre du roadies.toml de la machine : WidthAdjustment
        // ne supporte pas spatial_bsp, et charger la config réelle rendait le test fragile.
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig())
        _ = service.snapshot()

        let result = WidthAdjustmentService(service: service, events: EventLog(path: tempPath("width-events"))).apply(
            WidthAdjustmentIntent(scope: .activeWindow, mode: .explicitRatio, targetRatio: 0.5)
        )

        #expect(result.changed)
        #expect(result.ratio == 0.5)
        #expect(writer.frames[WindowID(rawValue: 1)]?.width == 500)
    }

    @Test
    func rejectsWhenNoTiledWindowExists() {
        let provider = PowerUserProvider(windows: [])
        // Cas vide en bsp, indépendant de la configuration réelle et des stages persistants.
        let service = SnapshotService(
            provider: provider, frameWriter: PowerUserWriter(provider: provider), config: RoadieConfig(),
            stageStore: StageStore(path: tempPath("width-empty-stages"))
        )

        let result = WidthAdjustmentService(service: service, events: EventLog(path: tempPath("width-reject-events"))).apply(
            WidthAdjustmentIntent(scope: .activeWindow, mode: .presetNext)
        )

        #expect(!result.changed)
        #expect(result.message == "width: no active tiled window")
    }
}
