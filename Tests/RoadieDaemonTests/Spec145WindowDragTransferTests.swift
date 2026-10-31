import AppKit
import Testing
import RoadieCore
@testable import RoadieDaemon

@Suite @MainActor struct Spec145WindowDragTransferTests {
    @Test func nativeReleaseIsMarkedAndKeepsTheOriginalClickIdentity() throws {
        let event = try #require(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
            mouseCursorPosition: CGPoint(x: 1800, y: 400), mouseButton: .left))
        event.setIntegerValueField(.mouseEventDeltaX, value: 1500)
        event.setIntegerValueField(.mouseEventDeltaY, value: 300)
        #expect(!WindowDragNativeRelease.matches(event))
        let origin = CGPoint(x: 300, y: 100)
        WindowDragNativeRelease.finish(event, at: origin, clickState: 2)
        #expect(event.type == .leftMouseUp && event.location == origin)
        #expect(event.getIntegerValueField(.mouseEventDeltaX) == 0)
        #expect(event.getIntegerValueField(.mouseEventDeltaY) == 0)
        #expect(event.getIntegerValueField(.mouseEventClickState) == 2)
        #expect(WindowDragNativeRelease.matches(event))
        let physical = try #require(CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
            mouseCursorPosition: CGPoint(x: 1800, y: 400), mouseButton: .left))
        #expect(!WindowDragNativeRelease.matches(physical))
    }

    @Test func nativeReleaseDoesNotCloseTheUserGestureOrNotifyItsReleaseHandler() throws {
        let input = UserInputActivity(monitoring: true)
        var releases = 0
        input.observeGestures(target: { _ in (42, CGRect(x: 100, y: 100, width: 600, height: 400)) },
            onRelease: { _ in releases += 1 })
        input.mouseDown(at: CGPoint(x: 300, y: 110))
        input.setCapturedPointerHeld(true)
        let event = try #require(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
            mouseCursorPosition: CGPoint(x: 1800, y: 400), mouseButton: .left))
        WindowDragNativeRelease.finish(event, at: CGPoint(x: 300, y: 110), clickState: 1)
        input.handle(try #require(NSEvent(cgEvent: event)), recordsInput: true)
        #expect(input.currentGesture != nil && input.isCapturedPointerHeld && releases == 0)
        input.setCapturedPointerHeld(false)
        let up = try #require(CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
            mouseCursorPosition: CGPoint(x: 1800, y: 400), mouseButton: .left))
        input.handle(try #require(NSEvent(cgEvent: up)), recordsInput: true)
        #expect(input.currentGesture == nil && releases == 1)
    }

    @Test func capturedPointerKeepsLayoutBlockedWhenMacOSReportsTheNativeButtonReleased() {
        let input = UserInputActivity(monitoring: true)
        let now = Date()
        input.claimExplicitResize()
        input.setCapturedPointerHeld(true)
        #expect(input.blocksLayout(mouseButtonsPressed: false, now: now))
        #expect(input.blocksLayout(mouseButtonsPressed: false, now: now.addingTimeInterval(60)))
        input.setCapturedPointerHeld(false)
        #expect(!input.blocksLayout(mouseButtonsPressed: false, now: now.addingTimeInterval(60)))
    }
}


@Suite @MainActor struct Spec145ParkedWindowAnimationTests {
    @Test func aWindowAlreadyParkedNeverSlidesBackIntoTheScreen() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        let path = try #require(f.configService.state.activePath)
        try "[fx.animations]\nenabled=true\nduration_ms=250\n".write(toFile: path, atomically: true, encoding: .utf8)
        _ = f.configService.reload(path: path)
        f.live.invalidate()
        var source = try #require(f.context.snapshot.windows.first { $0.window.id == f.source }?.window)
        let parked = HiddenWindowPlacement.frame(for: source.frame.cgRect, on: f.backend.screen, among: [f.backend.screen])
        source.frame = Rect(parked)
        source.isOnScreen = true // Le pixel restant sur le bord rend CG isOnScreen=true.
        _ = f.backend.setFrame(parked, of: source)
        let start = f.backend.writes.count
        let runtime = FrameTransitionRuntime(generations: f.generations, isMouseDown: { false })
        defer { runtime.cancel() }
        _ = runtime.schedule(ApplyPlan(commands: [ApplyCommand(window: source, frame: Rect(parked), preservesSize: true)]),
            service: f.service, generation: f.generations.current, action: .stage)
        #expect(await f.waitFor { !runtime.isHoldingLayout })
        let writes = Array(f.backend.writes.dropFirst(start))
        #expect(!writes.isEmpty)
        #expect(writes.allSatisfy { $0.1.minX == parked.minX })
    }
}
