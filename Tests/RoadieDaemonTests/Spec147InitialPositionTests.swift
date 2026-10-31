import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

@Suite @MainActor struct Spec147InitialPositionFlowTests {
    @Test func initialPositionOrderReachesWriterWithoutChangingKnownNeighbor() async throws {
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
        let updates = f.backend.frameUpdates
        #expect(updates.contains { $0.window.id == f.source && $0.positionsBeforeResizing })
        #expect(updates.filter { $0.window.id == f.neighbor }.allSatisfy { !$0.positionsBeforeResizing })
        let writes = f.backend.writes
        #expect(!writes.filter { $0.0 == f.source }.isEmpty)
        #expect(writes.filter { $0.0 == f.source }.allSatisfy { $0.1 == f.target.cgRect })
        #expect(writes.contains { $0.0 == f.neighbor && $0.1 != f.target.cgRect })
        #expect(f.backend.frame(f.source) == f.target.cgRect)
        #expect(f.backend.frame(f.neighbor) == f.target.cgRect)
    }
}

extension Spec147InitialPositionFlowTests {
    @Test func initialOrderAlsoAppliesWithoutAnAnimationOwner() throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        f.live.invalidate()
        let source = try #require(f.context.snapshot.windows.first { $0.window.id == f.source }?.window)
        _ = f.service.apply(ApplyPlan(commands: [ApplyCommand(window: source, frame: f.target)]),
                            generation: f.generations.current, immediateWindowIDs: [f.source])
        #expect(f.backend.frameUpdates.contains { $0.window.id == f.source && $0.positionsBeforeResizing })
    }
    @Test func oldCommandsDecodeAndTheNewOrderSurvivesRoundTrip() throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        let source = try #require(f.context.snapshot.windows.first { $0.window.id == f.source }?.window)
        let command = ApplyCommand(window: source, frame: f.target, positionsBeforeResizing: true)
        let data = try JSONEncoder().encode(command)
        #expect(try JSONDecoder().decode(ApplyCommand.self, from: data).positionsBeforeResizing)
        var old = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old.removeValue(forKey: "positionsBeforeResizing")
        #expect(try !JSONDecoder().decode(ApplyCommand.self,
            from: JSONSerialization.data(withJSONObject: old)).positionsBeforeResizing)
    }
}
