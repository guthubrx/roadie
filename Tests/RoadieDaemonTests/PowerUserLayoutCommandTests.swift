import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct PowerUserLayoutCommandTests {
    @Test
    func layoutFlattenAndSplitReturnCommandResults() {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100), powerWindow(2, x: 500)])
        let writer = PowerUserWriter(provider: provider)
        let service = SnapshotService(provider: provider, frameWriter: writer)
        _ = service.snapshot()
        let commands = LayoutCommandService(service: service)

        let flatten = commands.flatten()
        let split = commands.split("horizontal")

        #expect(flatten.message.contains("layout flatten"))
        #expect(split.message.contains("layout split horizontal"))
    }

    @Test
    func layoutInsertAndZoomParentApplyFrames() {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100), powerWindow(2, x: 500)])
        let writer = PowerUserWriter(provider: provider)
        let service = SnapshotService(provider: provider, frameWriter: writer)
        _ = service.snapshot()
        let commands = LayoutCommandService(service: service)

        let insert = commands.insert(.right)
        let zoom = commands.zoomParent()

        #expect(insert.message.contains("layout insert right"))
        #expect(zoom.message.contains("layout zoom-parent"))
        #expect(!writer.frames.isEmpty)
    }
}
