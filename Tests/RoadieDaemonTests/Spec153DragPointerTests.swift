import AppKit
import RoadieAX
import RoadieCore
import TOMLKit
import Testing
@testable import RoadieDaemon

@Suite struct Spec153DragPolicyTests {
    @Test func oldConfigurationGetsTheChosenDefaults() throws {
        let c = try TOMLDecoder().decode(RoadieConfig.self, from: "[fx]\ndrop_preview='real'\n")
        #expect(c.fx.dropPreview == "real" && c.fx.dragPreview == "content")
        #expect(c.fx.dragPreviewOpacityPercent == 85 && c.fx.dragPreviewScalePercent == 50)
        #expect(try JSONDecoder().decode(EffectsConfig.self, from: JSONEncoder().encode(c.fx)) == c.fx)
    }
    @Test func invalidSettingsAreRejected() {
        for value in ["drag_preview='bad'", "drag_preview_opacity_percent=9", "drag_preview_opacity_percent=101",
                      "drag_preview_scale_percent=24", "drag_preview_scale_percent=101", "drag_preview_opacity_percent=nan"] {
            #expect(throws: (any Error).self) { try TOMLDecoder().decode(RoadieConfig.self, from: "[fx]\n" + value) }
        }
    }
    @Test func scaledCopyKeepsTheGrabPointAndAspectRatioAcrossDisplays() {
        let initial = CGRect(x: -1400, y: 100, width: 1200, height: 600)
        let result = DragPointerPreview.frame(initial: initial, anchor: CGPoint(x: -1100, y: 120),
            point: CGPoint(x: 800, y: 300), scale: 0.5)
        #expect(result == CGRect(x: 650, y: 290, width: 600, height: 300))
        #expect(DragPointerPreview.frame(initial: initial, anchor: initial.origin, point: .zero, scale: 1).size == initial.size)
    }
    @Test func nativeMotionAtTheScreenEdgeNeedsARealMatchingAxis() {
        let initial = CGRect(x: 150, y: 40, width: 673, height: 934)
        let bounds = CGRect(x: 0, y: 32, width: 1512, height: 950)
        #expect(NativeWindowDragEvidence.followsPointer(initial: initial,
            observed: initial.offsetBy(dx: 100, dy: 8), from: CGPoint(x: 250, y: 52), to: CGPoint(x: 350, y: 152), constrainedTo: bounds))
        #expect(!NativeWindowDragEvidence.followsPointer(initial: initial,
            observed: initial.offsetBy(dx: 100, dy: 4), from: CGPoint(x: 250, y: 52), to: CGPoint(x: 350, y: 152), constrainedTo: bounds))
        #expect(!NativeWindowDragEvidence.followsPointer(initial: initial,
            observed: initial, from: CGPoint(x: 250, y: 52), to: CGPoint(x: 350, y: 152), constrainedTo: bounds))
    }
    @Test func nativeEvidenceRejectsResizeAndContentMovement() {
        let initial = CGRect(x: 10, y: 32, width: 800, height: 500)
        let from = CGPoint(x: 110, y: 45), to = CGPoint(x: 210, y: 95)
        #expect(NativeWindowDragEvidence.followsPointer(initial: initial, observed: initial.offsetBy(dx: 100, dy: 50), from: from, to: to))
        #expect(!NativeWindowDragEvidence.followsPointer(initial: initial, observed: initial, from: from, to: to))
        #expect(!NativeWindowDragEvidence.followsPointer(initial: initial, observed: CGRect(x: 110, y: 82, width: 801.1, height: 500), from: from, to: to))
        #expect(!NativeWindowDragEvidence.followsPointer(initial: initial, observed: initial.offsetBy(dx: 100, dy: 10), from: from, to: to))
        #expect(!NativeWindowDragEvidence.followsPointer(initial: initial, observed: initial, from: from, to: CGPoint(x: CGFloat.infinity, y: 1)))
    }
}

@Suite(.serialized) @MainActor struct Spec153DragPointerTests {
    private func image() -> CGImage {
        CGContext(data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }
    private func wait(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<100 { if predicate() { return true }; try? await Task.sleep(for: .milliseconds(3)) }
        return predicate()
    }
    private func configure(_ f: Drag143Fixture, pointer: String = "content", destination: String = "real") throws {
        let path = try #require(f.configService.state.activePath)
        try "[tiling]\nlive_drag_preview=true\n[fx]\ndrag_preview='\(pointer)'\ndrop_preview='\(destination)'\n".write(toFile: path, atomically: true, encoding: .utf8)
        _ = f.configService.reload(path: path)
    }
    @Test func aDuplicatedAppKitPressPreparesOneGestureButTheNextClickStillWorks() throws {
        let f = try Drag143Fixture(); defer { f.clean() }; f.live.invalidate()
        let path = f.directory.appendingPathComponent("native-press.jsonl")
        let preview = DropPreviewController(engine: DropPreviewEngine(service: f.service))
        let controller = WindowDragReorderController(preview: preview,
            events: EventLog(path: path.path), pointerPreview: DragPointerPreview(presents: false, capture: { _ in nil }))
        defer { controller.cancelPendingDrag() }
        let source = f.original(f.source)
        let point = RoadieScreenCoordinate.axRectToNS(CGRect(x: source.minX + 50, y: source.minY + 12, width: 0, height: 0)).origin
        controller.handleMouseDown(at: point)
        #expect(controller.hasActiveDrag)
        controller.handleMouseDown(at: point)
        func preparations() throws -> Int {
            try String(contentsOf: path, encoding: .utf8).split(separator: "\n").filter { $0.contains("drag.real_prepare") }.count
        }
        #expect(try preparations() == 1)
        controller.handleMouseUp(at: point)
        controller.handleMouseDown(at: point)
        #expect(try preparations() == 2 && controller.hasActiveDrag)
    }
    @Test func copyCapturesOnceAndOnlyChangesItsPosition() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        var captures = 0
        let preview = DragPointerPreview(presents: false, capture: { _ in captures += 1; return image() })
        let source = f.context.snapshot.windows[0].window, start = source.frame.cgRect.origin
        preview.prepare(window: source, anchor: start, config: EffectsConfig())
        preview.show(at: start)
        #expect(await wait { preview.isReady })
        for i in 0..<100 { preview.update(at: CGPoint(x: start.x + Double(i), y: start.y)) }
        #expect(captures == 1 && preview.visibleFrame?.width == source.frame.width / 2)
        #expect(preview.visibleFrame?.minX == start.x + 99)
        preview.end(); #expect(preview.visibleFrame == nil && !preview.isReady)
    }
    @Test func aCaptureDeadlineReleasesTheGestureAndIgnoresTheLateImage() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        var pending: CheckedContinuation<CGImage?, Never>?, notifications = 0
        let preview = DragPointerPreview(presents: false, captureTimeout: .milliseconds(25),
            capture: { _ in await withCheckedContinuation { pending = $0 } })
        preview.onPrepared = { notifications += 1 }
        preview.prepare(window: f.context.snapshot.windows[0].window, anchor: .zero, config: EffectsConfig())
        preview.show(at: .zero)
        #expect(await wait { pending != nil })
        #expect(await wait { preview.failed })
        #expect(notifications == 1 && preview.visibleFrame == nil)
        pending?.resume(returning: image()); await Task.yield()
        #expect(preview.failed && !preview.isReady && notifications == 1)
        preview.end()
    }
    @Test(arguments: [false, true]) func releaseHidesTheCopyBeforeAnOutstandingWriteFinishes(cancelled: Bool) async throws {
        let f = try Drag143Fixture(); defer { f.clean() }; f.live.invalidate(); try configure(f)
        let runtime = ModifierWindowRuntime(service: f.service, input: UserInputActivity(), automaticCadence: false)
        runtime.pointerPreview = DragPointerPreview(presents: false, capture: { _ in image() })
        defer { runtime.cancelImmediately(reason: "test") }
        let source = f.context.snapshot.windows[0], point = CGPoint(x: source.window.frame.x + 50, y: source.window.frame.y + 50)
        f.backend.blockedPID = source.window.pid
        #expect(runtime.begin(source: source, snapshot: f.context.snapshot, at: point, operation: .move))
        #expect(await wait { runtime.pointerPreview.isReady })
        let target = f.original(f.neighbor)
        runtime.update(at: CGPoint(x: target.maxX - 15, y: target.midY)); runtime.flush()
        #expect(await f.waitFor { !f.backend.frameUpdates.isEmpty })
        #expect(runtime.pointerPreview.visibleFrame != nil)
        runtime.end(cancelled: cancelled)
        #expect(runtime.isActive && runtime.pointerPreview.visibleFrame == nil)
        f.backend.blockedPID = nil; f.backend.gate.signal()
        #expect(await f.waitFor { !runtime.isActive })
    }
    @Test func lateCaptureCannotReopenACancelledCopy() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        var continuation: CheckedContinuation<CGImage?, Never>?
        let preview = DragPointerPreview(presents: false, capture: { _ in await withCheckedContinuation { continuation = $0 } })
        preview.prepare(window: f.context.snapshot.windows[0].window, anchor: .zero, config: EffectsConfig())
        preview.show(at: .zero)
        #expect(await wait { continuation != nil })
        preview.end(); continuation?.resume(returning: image())
        await Task.yield(); #expect(!preview.isReady && preview.visibleFrame == nil)
    }
    @Test func anOldCaptureDoesNotReplaceTheNextGesture() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        var calls = 0, first: CheckedContinuation<CGImage?, Never>?
        let preview = DragPointerPreview(presents: false, capture: { _ in
            calls += 1
            if calls == 1 { return await withCheckedContinuation { first = $0 } }
            return nil
        })
        let window = f.context.snapshot.windows[0].window
        preview.prepare(window: window, anchor: .zero, config: EffectsConfig())
        #expect(await wait { first != nil })
        preview.prepare(window: window, anchor: .zero, config: EffectsConfig())
        #expect(await wait { preview.failed })
        first?.resume(returning: image()); await Task.yield()
        #expect(preview.failed && !preview.isReady)
    }
    @Test func outlineAndNoneDoNotCapture() {
        var captures = 0
        let preview = DragPointerPreview(presents: false, capture: { _ in captures += 1; return nil })
        for style in ["outline", "none"] {
            var config = EffectsConfig(); config.dragPreview = style
            preview.prepare(window: powerWindow(1, x: 0), anchor: .zero, config: config)
            preview.show(at: .zero)
            #expect(preview.isReady && (preview.visibleFrame != nil) == (style == "outline"))
        }
        #expect(captures == 0); preview.end()
    }
    @Test func modifierMoveWaitsForInitialImageBeforeWriting() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }; f.live.invalidate(); try configure(f)
        let runtime = ModifierWindowRuntime(service: f.service, input: UserInputActivity(), automaticCadence: false)
        var pending: CheckedContinuation<CGImage?, Never>?
        runtime.pointerPreview = DragPointerPreview(presents: false, capture: { _ in await withCheckedContinuation { pending = $0 } })
        defer { runtime.cancelImmediately(reason: "test") }
        let source = f.context.snapshot.windows[0], point = CGPoint(x: source.window.frame.x + 50, y: source.window.frame.y + 50)
        #expect(runtime.begin(source: source, snapshot: f.context.snapshot, at: point, operation: .move))
        #expect(await wait { pending != nil })
        let target = f.original(f.neighbor)
        runtime.update(at: CGPoint(x: target.maxX - 15, y: target.midY)); runtime.flush()
        #expect(f.backend.writes.isEmpty)
        pending?.resume(returning: image())
        #expect(await f.waitFor { !f.backend.writes.isEmpty })
        #expect(runtime.pointerPreview.visibleFrame != nil)
        runtime.end(cancelled: true)
        #expect(await f.waitFor { !runtime.isActive })
        #expect(runtime.pointerPreview.visibleFrame == nil)
        #expect(f.backend.frame(f.source) == f.original(f.source))
    }
    @Test func missingCaptureKeepsTheActualSourceMoving() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }; f.live.invalidate(); try configure(f)
        let runtime = ModifierWindowRuntime(service: f.service, input: UserInputActivity(), automaticCadence: false)
        runtime.pointerPreview = DragPointerPreview(presents: false, capture: { _ in nil })
        defer { runtime.cancelImmediately(reason: "test") }
        let source = f.context.snapshot.windows[0], point = CGPoint(x: source.window.frame.x + 50, y: source.window.frame.y + 50)
        #expect(runtime.begin(source: source, snapshot: f.context.snapshot, at: point, operation: .move))
        #expect(await wait { runtime.pointerPreview.failed })
        runtime.update(at: CGPoint(x: point.x + 80, y: point.y + 40)); runtime.flush()
        #expect(await f.waitFor { f.backend.frame(f.source) == f.original(f.source).offsetBy(dx: 80, dy: 40) })
    }
    @Test func lateNativeAdoptionRestoresSourceInOutlineMode() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }; try configure(f, destination: "contour")
        let source = f.context.snapshot.windows[0].window, observed = source.frame.cgRect.offsetBy(dx: 100, dy: 40)
        _ = f.backend.setFrame(observed, of: source)
        f.live.begin(f.context, sourceGestureOwned: true, sourceWindowID: f.source, sourceObservedFrame: Rect(observed), keepSourceAtOrigin: true)
        f.live.update(f.candidate())
        #expect(await f.waitFor { f.backend.frame(f.source) == f.original(f.source) })
        f.live.finish(); #expect(await f.waitFor { !f.live.isActive })
    }
}
