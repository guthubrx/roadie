import AppKit
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

@Suite(.serialized) @MainActor struct Spec152SceneTransitionTests {
    private func context() -> StageSceneContext {
        let display = DisplaySnapshot(id: DisplayID(rawValue: "fixture"), index: 1, name: "Fictif",
            frame: Rect(x: 0, y: 0, width: 800, height: 600),
            visibleFrame: Rect(x: 0, y: 32, width: 800, height: 568), isMain: true)
        return StageSceneContext(display: display, frame: display.visibleFrame.cgRect, stationary: [])
    }
    private func image() -> CGImage {
        CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }
    private func wait(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(3))
        }
        return predicate()
    }

    @Test func aSourceThatNeverReturnsDoesNotDelayPlacementOrReappear() async {
        var now = 0.0, submissions = 0
        var pending: CheckedContinuation<CGImage?, Never>?
        let scene = StageSceneTransition(context: context(), direction: .up, policy: MotionPolicy(),
            events: EventLog(), valid: { true }, submit: { submissions += 1 }, presents: false, clock: { now },
            capture: { _ in await withCheckedContinuation { pending = $0 } })
        scene.start()
        #expect(await wait { pending != nil })
        now = 0.121; scene.pulse(applied: false)
        #expect(scene.phase == .finished && submissions == 1)
        pending?.resume(returning: image())
        await Task.yield()
        scene.pulse(applied: true)
        #expect(scene.phase == .finished && submissions == 1)
    }

    @Test func anUnavailableCapturePlacesDirectlyOnlyOnce() async {
        var submissions = 0
        let scene = StageSceneTransition(context: context(), direction: .down, policy: MotionPolicy(),
            events: EventLog(), valid: { true }, submit: { submissions += 1 }, presents: false,
            capture: { _ in nil })
        scene.start()
        #expect(await wait { scene.phase == .finished })
        scene.pulse(applied: true)
        #expect(submissions == 1)
    }

    @Test func aCancelledPreparationCannotApplyAnOldStage() async {
        var submissions = 0, valid = true
        var pending: CheckedContinuation<CGImage?, Never>?
        let scene = StageSceneTransition(context: context(), direction: .up, policy: MotionPolicy(),
            events: EventLog(), valid: { valid }, submit: { submissions += 1 }, presents: false,
            capture: { _ in await withCheckedContinuation { pending = $0 } })
        scene.start()
        #expect(await wait { pending != nil })
        valid = false; scene.pulse(applied: false)
        pending?.resume(returning: image())
        await Task.yield()
        #expect(scene.phase == .finished && submissions == 0)
    }

    @Test func aSlowWriterRevealsTheRealWindowsWithoutSubmittingAgain() async {
        var now = 0.0, submissions = 0, captures = 0
        let image = image()
        let scene = StageSceneTransition(context: context(), direction: .down, policy: MotionPolicy(),
            events: EventLog(), valid: { true }, submit: { submissions += 1 }, presents: false, clock: { now },
            capture: { _ in captures += 1; return image })
        scene.start()
        #expect(await wait { scene.phase == .applying })
        now = 0.201; scene.pulse(applied: false)
        #expect(scene.phase == .finished && submissions == 1 && captures == 1)
    }

    @Test func aLateTargetKeepsTheOutgoingAnimationWithoutRestartingIt() async {
        var now = 0.0, submissions = 0, captures = 0
        var pending: CheckedContinuation<CGImage?, Never>?
        let image = image()
        let scene = StageSceneTransition(context: context(), direction: .down, policy: MotionPolicy(duration: 0.1),
            events: EventLog(), valid: { true }, submit: { submissions += 1 }, presents: false, clock: { now },
            capture: { _ in
                captures += 1
                if captures == 1 { return image }
                return await withCheckedContinuation { pending = $0 }
            })
        scene.start()
        #expect(await wait { scene.phase == .applying })
        scene.pulse(applied: true)
        #expect(await wait { pending != nil })
        now = 0.201; scene.pulse(applied: true)
        #expect(scene.phase == .animating)
        pending?.resume(returning: image)
        await Task.yield()
        #expect(await wait { scene.phase == .finished })
        #expect(submissions == 1 && captures == 2)
    }

    @Test func targetCaptureHasItsOwnBudgetAfterTheWriterFinishes() async {
        var now = 0.0, captures = 0
        var pending: CheckedContinuation<CGImage?, Never>?
        let image = image()
        let scene = StageSceneTransition(context: context(), direction: .up, policy: MotionPolicy(duration: 0.15),
            events: EventLog(), valid: { true }, submit: {}, presents: false, clock: { now },
            capture: { _ in
                captures += 1
                if captures == 1 { return image }
                return await withCheckedContinuation { pending = $0 }
            })
        scene.start()
        #expect(await wait { scene.phase == .applying })
        now = 0.19; scene.pulse(applied: true)
        #expect(await wait { pending != nil })
        now = 0.27
        pending?.resume(returning: image)
        #expect(await wait { scene.phase == .animating || scene.phase == .finished })
        #expect(scene.phase == .animating)
        scene.cancel()
    }

    @Test func theNormalTransitionUsesTwoCapturesAndOnePlacement() async {
        var submissions = 0, captures = 0
        let image = image()
        let scene = StageSceneTransition(context: context(), direction: .up,
            policy: MotionPolicy(duration: 0.1), events: EventLog(), valid: { true },
            submit: { submissions += 1 }, presents: false, capture: { _ in captures += 1; return image })
        scene.start()
        #expect(await wait { scene.phase == .applying })
        scene.pulse(applied: true)
        #expect(await wait { scene.phase == .finished })
        #expect(captures == 2 && submissions == 1)
    }
    @Test func theRuntimePlacesOnceUnderTheScene() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }; f.live.invalidate()
        let path = try #require(f.configService.state.activePath)
        try "[fx.animations]\nenabled=true\nduration_ms=160\n".write(toFile: path, atomically: true, encoding: .utf8)
        _ = f.configService.reload(path: path)
        var captures = 0
        let image = image()
        let runtime = FrameTransitionRuntime(generations: f.generations, presentsScenes: false,
            sceneCapture: { _ in captures += 1; return image }, isMouseDown: { false })
        defer { runtime.cancel() }
        let window = f.context.snapshot.windows[0].window
        let result = runtime.schedule(ApplyPlan(commands: [ApplyCommand(window: window, frame: f.target)]),
            service: f.service, generation: f.generations.current, action: .stage,
            transitionDirection: .up, stageScene: context())
        #expect(result?.deferred == 1)
        var focused = 0
        #expect(runtime.deferStageFocus(generation: f.generations.current) { focused += 1 })
        #expect(focused == 0)
        #expect(await f.waitFor { runtime.isAnimatingScene })
        #expect(focused == 0)
        #expect(f.backend.writes.count == 1 && f.backend.frame(window.id) == f.target.cgRect)
        #expect(await f.waitFor { !runtime.isHoldingLayout })
        #expect(captures == 2 && f.backend.writes.count == 1 && focused == 1)
    }

    @Test func retargetingAnAnimatedSceneNeverRestoresItsOldTarget() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }; f.live.invalidate()
        let path = try #require(f.configService.state.activePath)
        try "[fx.animations]\nenabled=true\nduration_ms=300\n".write(toFile: path, atomically: true, encoding: .utf8)
        _ = f.configService.reload(path: path)
        let image = image()
        let runtime = FrameTransitionRuntime(generations: f.generations, presentsScenes: false,
            sceneCapture: { _ in image }, isMouseDown: { false })
        defer { runtime.cancel() }
        var window = f.context.snapshot.windows[0].window
        _ = runtime.schedule(ApplyPlan(commands: [ApplyCommand(window: window, frame: f.target)]),
            service: f.service, generation: f.generations.current, action: .stage,
            transitionDirection: .up, stageScene: context())
        #expect(await f.waitFor { runtime.isAnimatingScene })
        let before = f.backend.writes.count
        window.frame = Rect(try #require(f.backend.frame(window.id)))
        let target = Rect(x: 80, y: 90, width: 400, height: 500)
        _ = runtime.schedule(ApplyPlan(commands: [ApplyCommand(window: window, frame: target)]),
            service: f.service, generation: f.generations.next(), action: .stage,
            transitionDirection: .down, stageScene: context())
        #expect(await f.waitFor { !runtime.isHoldingLayout })
        #expect(!runtime.isAnimatingScene)
        #expect(f.backend.frame(window.id) == target.cgRect)
        #expect(f.backend.writes.dropFirst(before).allSatisfy { $0.1 == target.cgRect })
    }

    @Test func overlappingStationaryWindowsLeaveOneContinuousHole() {
        let base = context()
        let scene = StageSceneContext(display: base.display, frame: base.frame, stationary: [
            CGRect(x: 100, y: 100, width: 200, height: 200),
            CGRect(x: 200, y: 200, width: 200, height: 200)])
        let mask = scene.maskPath()
        #expect(!mask.contains(CGPoint(x: 250, y: base.frame.maxY - 250)))
        #expect(!mask.contains(CGPoint(x: 150, y: base.frame.maxY - 150)))
        #expect(!mask.contains(CGPoint(x: 350, y: base.frame.maxY - 350)))
        #expect(mask.contains(CGPoint(x: 20, y: 20)))
    }

    @Test func cancellingBeforeTheTaskStartsDoesNotLaunchAnObsoleteCapture() async {
        var captures = 0, submissions = 0
        let scene = StageSceneTransition(context: context(), direction: .up, policy: MotionPolicy(),
            events: EventLog(), valid: { true }, submit: { submissions += 1 }, presents: false,
            capture: { _ in captures += 1; return nil })
        scene.start(); scene.cancel()
        await Task.yield()
        #expect(scene.phase == .finished && captures == 0 && submissions == 0)
    }

}
