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
        now = 0.041; scene.pulse(applied: false)
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

    @Test func aLateTargetCannotStartAnAnimationAfterItsDeadline() async {
        var now = 0.0, submissions = 0, captures = 0
        var pending: CheckedContinuation<CGImage?, Never>?
        let image = image()
        let scene = StageSceneTransition(context: context(), direction: .down, policy: MotionPolicy(),
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
        pending?.resume(returning: image)
        await Task.yield()
        #expect(scene.phase == .finished && submissions == 1 && captures == 2)
    }

    @Test func theNormalTransitionUsesTwoCapturesAndOnePlacement() async {
        var submissions = 0, captures = 0
        let image = image()
        let scene = StageSceneTransition(context: context(), direction: .up,
            policy: MotionPolicy(duration: 0.03), events: EventLog(), valid: { true },
            submit: { submissions += 1 }, presents: false, capture: { _ in captures += 1; return image })
        scene.start()
        #expect(await wait { scene.phase == .applying })
        scene.pulse(applied: true)
        #expect(await wait { scene.phase == .finished })
        #expect(captures == 2 && submissions == 1)
    }
}
