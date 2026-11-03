import AppKit
import Foundation
import RoadieAX
import RoadieCore
import Testing
@testable import RoadieDaemon

@Suite struct Spec152StageDirectionTests {
    @Test func stageOrderAndExplicitNavigationDecideTheMotion() {
        let order = ["9", "2", "6"].map { StageID(rawValue: $0) }
        #expect(StageCommandService.transitionDirection(from: order[0], to: order[1], ordered: order) == .down)
        #expect(StageCommandService.transitionDirection(from: order[2], to: order[0], ordered: order) == .up)
        #expect(StageCommandService.transitionDirection(from: order[2], to: order[0], ordered: order, navigation: .next) == .down)
        #expect(StageCommandService.transitionDirection(from: order[0], to: order[2], ordered: order, navigation: .prev) == .up)
        #expect(StageCommandService.transitionDirection(from: order[0], to: order[0], ordered: order, navigation: .next) == nil)
        #expect(StageCommandService.transitionDirection(from: .init(rawValue: "absent"), to: order[0], ordered: order) == nil)
    }
}

@Suite(.serialized) @MainActor struct Spec152FrameMotionTests {
    @Test(arguments: [Direction.up, .down])
    func parkedWindowAndLeavingWindowMoveInTheNavigationDirection(_ direction: Direction) async throws {
        let f = try Drag143Fixture(); defer { f.clean() }; f.live.invalidate()
        let path = try #require(f.configService.state.activePath)
        try "[fx.animations]\nenabled=true\nduration_ms=300\ncurve='linear'\n".write(toFile: path, atomically: true, encoding: .utf8)
        _ = f.configService.reload(path: path)
        _ = f.service.sharedSnapshot(followFocus: false)
        let runtime = FrameTransitionRuntime(generations: f.generations, isMouseDown: { false })
        defer { runtime.cancel() }
        var incoming = f.context.snapshot.windows[0].window
        let leaving = f.context.snapshot.windows[1].window
        incoming.frame = Rect(HiddenWindowPlacement.frame(for: incoming.frame.cgRect, on: f.backend.screen, among: [f.backend.screen]))
        incoming.isOnScreen = true // Le pixel de parking reste déclaré visible par WindowServer.
        let parking = Rect(HiddenWindowPlacement.frame(for: leaving.frame.cgRect, on: f.backend.screen, among: [f.backend.screen]))
        let plan = ApplyPlan(commands: [ApplyCommand(window: incoming, frame: f.target),
            ApplyCommand(window: leaving, frame: parking, preservesSize: true)])
        #expect(runtime.schedule(plan, service: f.service, generation: f.generations.current,
                                 action: .stage, transitionDirection: direction)?.deferred == 2)
        #expect(await f.waitFor { !runtime.isHoldingLayout })
        let enteringFrames = f.backend.writes.filter { $0.0 == incoming.id }.map(\.1)
        let leavingFrames = f.backend.writes.filter { $0.0 == leaving.id }.map(\.1)
        let first = try #require(enteringFrames.first)
        #expect(abs(first.minX - f.target.x) <= 1)
        #expect(direction == .up ? first.minY > f.target.y + 5 : first.minY < f.target.y - 5)
        let outgoing = try #require(leavingFrames.first)
        #expect(direction == .up ? outgoing.minY < leaving.frame.y - 1 : outgoing.minY > leaving.frame.y + 1)
        #expect(leavingFrames.allSatisfy { $0.size == leaving.frame.cgRect.size })
        #expect(enteringFrames.last == f.target.cgRect && leavingFrames.last == parking.cgRect)
    }

    @Test func switchingStagePassesTheDirectionThroughThePlacementPipeline() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }; f.live.invalidate()
        let path = try #require(f.configService.state.activePath)
        try "[fx.animations]\nenabled=true\nduration_ms=300\ncurve='linear'\n".write(toFile: path, atomically: true, encoding: .utf8)
        _ = f.configService.reload(path: path)
        let source = f.context.snapshot.windows[0].window
        let incoming = f.context.snapshot.windows[1].window
        let second = StageID(rawValue: "second")
        try f.store.mutateChecked { state in
            var stage = state.scopes[0].stages[0]
            stage.mode = .float; stage.members = stage.members.filter { $0.windowID == source.id }; stage.bspTree = nil
            var target = stage; target.id = second
            target.members = [PersistentStageMember(windowID: incoming.id, bundleID: incoming.bundleID,
                title: incoming.title, frame: incoming.frame)]
            state.scopes[0].stages = [stage, target]
        }
        _ = f.backend.setFrame(HiddenWindowPlacement.frame(for: incoming.frame.cgRect, on: f.backend.screen, among: [f.backend.screen]), of: incoming)
        let before = f.backend.writes.count
        FrameTransitionRuntime.shared.start()
        defer { FrameTransitionRuntime.shared.stop() }
        let result = StageCommandService(service: f.service, store: f.store).switchTo(second.rawValue)
        #expect(result.changed)
        #expect(await f.waitFor { !FrameTransitionRuntime.shared.isHoldingLayout })
        let frames = f.backend.writes.dropFirst(before).filter { $0.0 == incoming.id }.map(\.1)
        let first = try #require(frames.first)
        #expect(abs(first.minX - incoming.frame.x) <= 1)
        #expect(first.minY < incoming.frame.y - 5) // Next : arrivée depuis le haut, mouvement descendant.
        #expect(frames.last == incoming.frame.cgRect)
    }

    @Test func hidingAnAlreadyParkedWindowNeverBringsItBackOnScreen() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }; f.live.invalidate()
        let path = try #require(f.configService.state.activePath)
        try "[fx.animations]\nenabled=true\nduration_ms=80\n".write(toFile: path, atomically: true, encoding: .utf8)
        _ = f.configService.reload(path: path)
        _ = f.service.sharedSnapshot(followFocus: false)
        let runtime = FrameTransitionRuntime(generations: f.generations, isMouseDown: { false })
        defer { runtime.cancel() }
        var window = f.context.snapshot.windows[0].window
        window.frame = Rect(HiddenWindowPlacement.frame(for: window.frame.cgRect, on: f.backend.screen, among: [f.backend.screen]))
        let plan = ApplyPlan(commands: [ApplyCommand(window: window, frame: window.frame, preservesSize: true)])
        _ = runtime.schedule(plan, service: f.service, generation: f.generations.current, action: .stage, transitionDirection: .up)
        #expect(await f.waitFor { !runtime.isHoldingLayout })
        #expect(!f.backend.writes.isEmpty)
        #expect(f.backend.writes.allSatisfy { $0.1 == window.frame.cgRect })
    }

    @Test func disabledAnimationsApplyOnlyTheFinalPlacement() throws {
        let f = try Drag143Fixture(); defer { f.clean() }; f.live.invalidate()
        let path = try #require(f.configService.state.activePath)
        try "[fx.animations]\nenabled=false\n".write(toFile: path, atomically: true, encoding: .utf8)
        _ = f.configService.reload(path: path)
        let window = f.context.snapshot.windows[0].window
        let result = f.service.apply(ApplyPlan(commands: [ApplyCommand(window: window, frame: f.target)]), transitionDirection: .up)
        #expect(result.applied == 1 && result.deferred == 0)
        #expect(f.backend.writes.map(\.1) == [f.target.cgRect])
    }
}
