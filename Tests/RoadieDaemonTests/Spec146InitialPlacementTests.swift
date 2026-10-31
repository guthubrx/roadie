import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

@Suite @MainActor struct Spec146InitialPlacementTests {
    @Test func newWindowGoesStraightToItsTargetWhileKnownNeighborStillAnimates() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        let path = try #require(f.configService.state.activePath)
        try "[fx.animations]\nenabled=true\nduration_ms=300\n".write(toFile: path, atomically: true, encoding: .utf8)
        _ = f.configService.reload(path: path)
        f.live.invalidate()
        let source = try #require(f.context.snapshot.windows.first { $0.window.id == f.source }?.window)
        let neighbor = try #require(f.context.snapshot.windows.first { $0.window.id == f.neighbor }?.window)
        let runtime = FrameTransitionRuntime(generations: f.generations, isMouseDown: { false })
        defer { runtime.cancel() }
        _ = runtime.schedule(ApplyPlan(commands: [ApplyCommand(window: source, frame: f.target),
                                                  ApplyCommand(window: neighbor, frame: f.target)]),
                             service: f.service, generation: f.generations.current, action: .move,
                             immediateWindowIDs: [f.source])
        #expect(await f.waitFor { !runtime.isHoldingLayout })
        let writes = f.backend.writes
        #expect(!writes.filter { $0.0 == f.source }.isEmpty)
        #expect(writes.filter { $0.0 == f.source }.allSatisfy { $0.1 == f.target.cgRect })
        #expect(writes.contains { $0.0 == f.neighbor && $0.1 != f.target.cgRect })
        #expect(f.backend.frame(f.source) == f.target.cgRect)
        #expect(f.backend.frame(f.neighbor) == f.target.cgRect)
    }
}
