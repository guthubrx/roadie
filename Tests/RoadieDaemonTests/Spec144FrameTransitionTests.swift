import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

@Suite @MainActor struct Spec144FrameTransitionTests {
    @Test func queuedWorkIsNotReportedAsAppliedAndEndsAtRealFrame() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        let path = try #require(f.configService.state.activePath)
        try "[fx.animations]\nenabled=true\nduration_ms=50\n".write(toFile: path, atomically: true, encoding: .utf8)
        _ = f.configService.reload(path: path)
        f.live.invalidate()
        let runtime = FrameTransitionRuntime(generations: f.generations, isMouseDown: { false })
        defer { runtime.cancel() }
        let source = try #require(f.context.snapshot.windows.first { $0.window.id == f.source }?.window)
        let plan = ApplyPlan(commands: [ApplyCommand(window: source, frame: f.target)])
        let result = try #require(runtime.schedule(plan, service: f.service, generation: f.generations.current, action: .move))
        #expect(result.applied == 0 && result.failed == 0 && result.deferred == 1)
        #expect(result.items.first?.actual == nil)
        #expect(await f.waitFor { !runtime.isHoldingLayout })
        #expect(f.backend.frame(f.source) == f.target.cgRect)
    }
    @Test func cancellationRevokesAllFurtherAnimationWrites() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        let path = try #require(f.configService.state.activePath)
        try "[fx.animations]\nenabled=true\nduration_ms=500\n".write(toFile: path, atomically: true, encoding: .utf8)
        _ = f.configService.reload(path: path)
        f.live.invalidate()
        let runtime = FrameTransitionRuntime(generations: f.generations, isMouseDown: { false })
        let source = try #require(f.context.snapshot.windows.first { $0.window.id == f.source }?.window)
        _ = runtime.schedule(ApplyPlan(commands: [ApplyCommand(window: source, frame: f.target)]),
                             service: f.service, generation: f.generations.current, action: .move)
        runtime.cancel()
        try? await Task.sleep(for: .milliseconds(80))
        let count = f.backend.writes.count
        try? await Task.sleep(for: .milliseconds(80))
        #expect(f.backend.writes.count == count && !runtime.isHoldingLayout)
    }
}

extension Spec144FrameTransitionTests {
    @Test func slowAppDoesNotBlockNeighborAndExternalGenerationCancelsQueuedFinal() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        let path = try #require(f.configService.state.activePath)
        try "[fx.animations]\nenabled=true\nduration_ms=50\n".write(toFile: path, atomically: true, encoding: .utf8)
        _ = f.configService.reload(path: path)
        f.live.invalidate()
        let source = try #require(f.context.snapshot.windows.first { $0.window.id == f.source }?.window)
        let neighbor = try #require(f.context.snapshot.windows.first { $0.window.id == f.neighbor }?.window)
        f.backend.blockedPID = source.pid
        let runtime = FrameTransitionRuntime(generations: f.generations, isMouseDown: { false })
        defer { runtime.cancel(); f.backend.gate.signal() }
        let result = runtime.schedule(ApplyPlan(commands: [ApplyCommand(window: source, frame: f.target),
                                                          ApplyCommand(window: neighbor, frame: f.target)]),
                                      service: f.service, generation: f.generations.current, action: .move)
        #expect(result?.deferred == 2)
        #expect(await f.waitFor { f.backend.frame(f.neighbor) == f.target.cgRect })
        #expect(f.backend.frame(f.source) == f.original(f.source))
        _ = f.generations.next()
        runtime.cancel()
        f.backend.gate.signal()
        try? await Task.sleep(for: .milliseconds(50))
        let count = f.backend.writes.count
        try? await Task.sleep(for: .milliseconds(80))
        #expect(f.backend.writes.count == count)
        #expect(!runtime.isHoldingLayout)
    }
}

extension Spec144FrameTransitionTests {
    @Test func pressingMouseCancelsTransitionBeforeNextGestureStarts() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        let path = try #require(f.configService.state.activePath)
        try "[fx.animations]\nenabled=true\nduration_ms=500\n".write(toFile: path, atomically: true, encoding: .utf8)
        _ = f.configService.reload(path: path)
        f.live.invalidate()
        let runtime = FrameTransitionRuntime(generations: f.generations, isMouseDown: { false })
        defer { runtime.cancel() }
        let source = try #require(f.context.snapshot.windows.first { $0.window.id == f.source }?.window)
        _ = runtime.schedule(ApplyPlan(commands: [ApplyCommand(window: source, frame: f.target)]),
                             service: f.service, generation: f.generations.current, action: .move)
        #expect(await f.waitFor { !f.backend.writes.isEmpty })
        let input = UserInputActivity(monitoring: true)
        input.observeGestures(target: { _ in nil }, onPress: { runtime.cancel() }, onRelease: { _ in })
        input.mouseDown(at: .zero)
        #expect(!runtime.isHoldingLayout)
        try? await Task.sleep(for: .milliseconds(60))
        let count = f.backend.writes.count
        try? await Task.sleep(for: .milliseconds(80))
        #expect(f.backend.writes.count == count)
        #expect(f.backend.frame(f.source) != f.target.cgRect)
    }

    @Test func localCommandWithoutRunningAnimationOwnerStillWritesSynchronously() throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        let path = try #require(f.configService.state.activePath)
        try "[fx.animations]\nenabled=true\n".write(toFile: path, atomically: true, encoding: .utf8)
        _ = f.configService.reload(path: path)
        f.live.invalidate()
        let source = try #require(f.context.snapshot.windows.first { $0.window.id == f.source }?.window)
        // Le runtime partagé n'est activé que par le composant écrivain, jamais par une CLI locale.
        #expect(!FrameTransitionRuntime.shared.acceptsCommands)
        let result = f.service.apply(ApplyPlan(commands: [ApplyCommand(window: source, frame: f.target)]))
        #expect(result.deferred == 0 && result.applied == 1)
        #expect(f.backend.frame(f.source) == f.target.cgRect)
    }
}

extension Spec144FrameTransitionTests {
    @Test func newGenerationRetargetsWithoutApplyingTheOldFinalTarget() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        let path = try #require(f.configService.state.activePath)
        try "[fx.animations]\nenabled=true\nprofile='expressive'\n".write(toFile: path, atomically: true, encoding: .utf8)
        _ = f.configService.reload(path: path)
        f.live.invalidate()
        var window = try #require(f.context.snapshot.windows.first { $0.window.id == f.source }?.window)
        let runtime = FrameTransitionRuntime(generations: f.generations, isMouseDown: { false })
        defer { runtime.cancel() }
        _ = runtime.schedule(ApplyPlan(commands: [ApplyCommand(window: window, frame: f.target)]),
                             service: f.service, generation: f.generations.current, action: .move)
        #expect(await f.waitFor { !f.backend.writes.isEmpty })
        window.frame = Rect(try #require(f.backend.frame(f.source)))
        let before = f.backend.writes.count
        let next = Rect(x: 50, y: 80, width: 400, height: 700)
        let generation = f.generations.next()
        _ = runtime.schedule(ApplyPlan(commands: [ApplyCommand(window: window, frame: next)]),
                             service: f.service, generation: generation, action: .move)
        #expect(await f.waitFor { !runtime.isHoldingLayout })
        #expect(f.backend.frame(f.source) == next.cgRect)
        #expect(!f.backend.writes.dropFirst(before).contains { $0.1 == f.target.cgRect })
    }
}


extension Spec144FrameTransitionTests {
    @Test func aHeldMouseButtonPreventsStartingAnAnimation() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        let path = try #require(f.configService.state.activePath)
        try "[fx.animations]\nenabled=true\nduration_ms=50\n".write(toFile: path, atomically: true, encoding: .utf8)
        _ = f.configService.reload(path: path)
        f.live.invalidate()
        let source = try #require(f.context.snapshot.windows.first { $0.window.id == f.source }?.window)
        let plan = ApplyPlan(commands: [ApplyCommand(window: source, frame: f.target)])
        var pressed = true
        let runtime = FrameTransitionRuntime(generations: f.generations, isMouseDown: { pressed })
        defer { runtime.cancel() }
        #expect(runtime.schedule(plan, service: f.service, generation: f.generations.current, action: .move) == nil)
        #expect(f.backend.writes.isEmpty)
        pressed = false
        #expect(runtime.schedule(plan, service: f.service, generation: f.generations.current, action: .move)?.deferred == 1)
        #expect(await f.waitFor { !runtime.isHoldingLayout })
        #expect(f.backend.frame(f.source) == f.target.cgRect)
    }
}
