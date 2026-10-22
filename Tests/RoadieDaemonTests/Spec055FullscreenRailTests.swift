import Foundation
import RoadieAX
import RoadieCore
import Testing
@testable import RoadieDaemon

@Suite
struct Spec055FullscreenRailTests {
    @Test(arguments: [1, 2], [false, true])
    func explicitFullscreenHidesOnlyItsDisplayAndRestoresWithoutNativeFullscreen(count: Int, alreadyFillsDisplay: Bool) throws {
        let display = powerDisplay()
        let other = powerDisplay("other055", index: 2, x: 1000)
        var window = powerWindow(1, x: 150, width: 400)
        if alreadyFillsDisplay { window.frame = display.visibleFrame }
        let siblings = count == 2 ? [powerWindow(2, x: 600, width: 350)] : []
        let provider = PowerUserProvider(displays: [display, other], windows: [window] + siblings + [powerWindow(3, x: 1100)])
        let writer = PowerUserWriter(provider: provider)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("fullscreen055-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StageStore(path: directory.appendingPathComponent("state.json").path)
        let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store)
        let initial = service.snapshot()
        let scope = try #require(initial.windows.first { $0.window.id == window.id }?.scope)
        let commands = WindowCommandService(service: service, stageStore: store)
        #expect(commands.toggleFullscreen().changed)
        let intent = service.commandLayoutIntent(scope: scope)
        #expect(intent?.zoomedWindowID == window.id)
        #expect(intent?.zoomReservesRail == false)
        #expect(writer.frames[window.id] == display.visibleFrame)
        #expect(writer.nativeFullscreen.isEmpty)
        func hidden(_ snapshot: DaemonSnapshot, hideOnMaximized: Bool = false) -> Set<DisplayID> {
            let zoom = RailController.railZoomWindowIDs(in: snapshot, intentForScope: service.commandLayoutIntent)
            return RailController.railHiddenDisplayIDs(in: snapshot, hideOnMaximized: hideOnMaximized,
                railAwareZoomWindowIDs: zoom.reservingRail, fullscreenWindowIDs: zoom.fullscreen)
        }
        let full = service.snapshot()
        #expect(hidden(full) == [display.id])
        #expect(hidden(full, hideOnMaximized: true) == [display.id])
        // Le mode prime sur la géométrie et reste caché si l'application ajuste sa taille.
        var adjusted = full
        if let index = adjusted.windows.firstIndex(where: { $0.window.id == window.id }) {
            adjusted.windows[index].window.frame = Rect(x: 20, y: 20, width: 800, height: 600)
        }
        #expect(hidden(adjusted) == [display.id])
        var anotherStage = full
        let otherStageID = StageID(rawValue: "other-stage")
        try anotherStage.state.createStage(id: otherStageID, name: "Other", in: scope.displayID, desktopID: scope.desktopID)
        try anotherStage.state.switchStage(otherStageID, in: scope.displayID, desktopID: scope.desktopID)
        #expect(hidden(anotherStage).isEmpty)
        var missing = full
        missing.windows.removeAll { $0.window.id == window.id }
        #expect(hidden(missing).isEmpty)
        #expect(commands.toggleFullscreen().changed)
        #expect(service.commandLayoutIntent(scope: scope)?.zoomedWindowID == nil)
        #expect(hidden(service.snapshot()).isEmpty)
        #expect(writer.nativeFullscreen.isEmpty)
        #expect(commands.toggleMaximize().changed)
        #expect(hidden(service.snapshot(), hideOnMaximized: true).isEmpty)
    }
}
