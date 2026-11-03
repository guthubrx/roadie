import AppKit
import Foundation
import RoadieAX
import RoadieCore
import RoadieTiler
import Testing
@testable import RoadieDaemon

@Suite struct Spec151ModifierGeometryTests {
    @Test func modifiersAreExactAndResizeWinsAnIdenticalBinding() {
        var c = TilingConfig()
        #expect(ModifierWindowOperation.resolve(flags: .maskControl, config: c) == .move)
        #expect(ModifierWindowOperation.resolve(flags: [.maskControl, .maskAlternate], config: c) == .resize)
        #expect(ModifierWindowOperation.resolve(flags: [.maskControl, .maskAlternate, .maskAlphaShift], config: c) == .resize)
        #expect(ModifierWindowOperation.resolve(flags: [.maskControl, .maskShift], config: c) == nil)
        c.dragResizeModifier = .control
        #expect(ModifierWindowOperation.resolve(flags: .maskControl, config: c) == .resize)
        c.dragResizeModifier = .disabled; c.dragMoveModifier = .disabled
        #expect(ModifierWindowOperation.resolve(flags: .maskControl, config: c) == nil)
        #expect(ModifierWindowOperation.resolve(flags: [], config: c) == nil)
    }

    @Test func oldConfigurationKeepsDefaultsAndNewChoicesRoundTrip() throws {
        let old = try JSONDecoder().decode(TilingConfig.self, from: Data("{}".utf8))
        #expect(old.dragMoveModifier == .control && old.dragResizeModifier == .controlOption)
        let c = TilingConfig(dragMoveModifier: .optionCommand, dragResizeModifier: .disabled)
        #expect(try JSONDecoder().decode(TilingConfig.self, from: JSONEncoder().encode(c)) == c)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TilingConfig.self, from: Data("{\"drag_move_modifier\":\"invalid\"}".utf8))
        }
        #expect(WindowGestureModifier.controlOption.mask == CGEventFlags([.maskControl, .maskAlternate]).rawValue)
    }

    @Test func resizeKeepsTheOppositeCornerAndHonorsMinimums() {
        let g = ModifierWindowGeometry(frame: CGRect(x: 100, y: 200, width: 400, height: 300),
            origin: CGPoint(x: 130, y: 225), operation: .resize)
        #expect(g.target(at: CGPoint(x: 190, y: 275)) == CGRect(x: 160, y: 250, width: 340, height: 250))
        #expect(g.target(at: CGPoint(x: 1000, y: 1000)) == CGRect(x: 420, y: 420, width: 80, height: 80))
        #expect(g.target(at: CGPoint(x: CGFloat.infinity, y: 0)) == nil)
    }

    @Test func anyContentPointSelectsAnAvailableTilingEdge() throws {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(WindowID(rawValue: 1)), second: .leaf(WindowID(rawValue: 2)))
        let p = try #require(BSPNativeResize(tree: tree, windowID: WindowID(rawValue: 1),
            in: CGRect(x: 0, y: 0, width: 1000, height: 800), knownMinimums: [WindowID(rawValue: 2): CGSize(width: 300, height: 100)]))
        #expect(p.movableEdges == [.right])
        let g = ModifierWindowGeometry(frame: CGRect(x: 0, y: 0, width: 500, height: 800),
            origin: CGPoint(x: 20, y: 20), operation: .resize, available: p.movableEdges)
        #expect(g.target(at: CGPoint(x: 120, y: 500)) == CGRect(x: 0, y: 0, width: 600, height: 800))
        let result = try #require(p.layout(observedFrame: CGRect(x: 0, y: 0, width: 10000, height: 800)))
        #expect(result.frames[WindowID(rawValue: 2)]!.width >= 300)
        #expect(result.frames[WindowID(rawValue: 1)]!.width <= 700)
    }
}

@Suite(.serialized) @MainActor struct Spec151ModifierRuntimeTests {
    private func setup(_ f: Drag143Fixture, input: UserInputActivity) -> ModifierWindowRuntime {
        f.live.invalidate()
        let path = f.configService.state.activePath!
        try! (String(contentsOfFile: path, encoding: .utf8) + "\n[fx]\ndrag_preview='none'\n").write(toFile: path, atomically: true, encoding: .utf8)
        _ = f.configService.reload(path: path)
        return ModifierWindowRuntime(service: f.service, input: input,
            events: EventLog(path: f.directory.appendingPathComponent("modifier.jsonl").path), automaticCadence: false)
    }

    @Test func resizeWritesSourceAndNeighborsButSavesOnlyAtRelease() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        let input = UserInputActivity(), runtime = setup(f, input: input)
        defer { runtime.cancelImmediately(reason: "test") }
        let entry = f.context.snapshot.windows[0], original = f.original(f.source)
        let point = CGPoint(x: original.midX, y: original.midY), before = f.store.state().bspTree(for: f.scope)
        #expect(runtime.begin(source: entry, snapshot: f.context.snapshot, at: point, operation: .resize))
        runtime.update(at: CGPoint(x: point.x + 100, y: point.y)); runtime.flush()
        #expect(await f.waitFor { (f.backend.frame(f.source)?.width ?? 0) > original.width + 20 && f.backend.writes.contains { $0.0 == f.neighbor } })
        #expect(f.store.state().bspTree(for: f.scope) == before)
        runtime.end()
        #expect(await f.waitFor { !runtime.isActive })
        #expect(f.store.state().bspTree(for: f.scope) != before)
        #expect(!input.isCapturedPointerHeld && input.takeGesture() == nil)
    }

    @Test func escapeRestoresEveryTouchedFrameAndTheTree() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        let runtime = setup(f, input: UserInputActivity()); defer { runtime.cancelImmediately(reason: "test") }
        let entry = f.context.snapshot.windows[0], point = CGPoint(x: entry.window.frame.cgRect.midX, y: entry.window.frame.cgRect.midY)
        let before = f.store.state().bspTree(for: f.scope)
        #expect(runtime.begin(source: entry, snapshot: f.context.snapshot, at: point, operation: .resize))
        runtime.update(at: CGPoint(x: point.x + 100, y: point.y)); runtime.flush()
        #expect(await f.waitFor { !f.backend.writes.isEmpty })
        runtime.end(cancelled: true)
        #expect(await f.waitFor { !runtime.isActive })
        for e in f.context.snapshot.windows { #expect(f.backend.frame(e.window.id) == e.window.frame.cgRect) }
        #expect(f.store.state().bspTree(for: f.scope) == before)
    }

    @Test func aNewGenerationNeverRestoresAnObsoleteLayout() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        let input = UserInputActivity(), runtime = setup(f, input: input); defer { runtime.cancelImmediately(reason: "test") }
        let entry = f.context.snapshot.windows[0], point = CGPoint(x: entry.window.frame.cgRect.midX, y: entry.window.frame.cgRect.midY)
        #expect(runtime.begin(source: entry, snapshot: f.context.snapshot, at: point, operation: .resize))
        runtime.update(at: CGPoint(x: point.x + 100, y: point.y)); runtime.flush()
        #expect(await f.waitFor { !f.backend.writes.isEmpty })
        _ = PlacementGeneration.shared.next()
        let external = CGRect(x: 300, y: 200, width: 350, height: 250)
        _ = f.backend.setFrame(external, of: entry.window)
        runtime.flush()
        #expect(!runtime.isActive && !input.isCapturedPointerHeld)
        #expect(f.backend.frame(f.source) == external)
    }

    @Test func floatingMoveKeepsItsFrameWithoutMovingNeighbors() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        let input = UserInputActivity(), runtime = setup(f, input: input); defer { runtime.cancelImmediately(reason: "test") }
        var snapshot = f.context.snapshot, entry = snapshot.windows[0]
        let pin = PersistentWindowPin(windowID: f.source, homeScope: f.scope, pinScope: .stage,
            bundleID: entry.window.bundleID, title: entry.window.title, lastFrame: entry.window.frame)
        try f.store.mutateChecked { $0.windowPins.append(pin) }
        entry.pin = pin; snapshot.windows[0] = entry
        let point = CGPoint(x: entry.window.frame.cgRect.midX, y: entry.window.frame.cgRect.midY)
        let desired = entry.window.frame.cgRect.offsetBy(dx: 90, dy: 55)
        #expect(runtime.begin(source: entry, snapshot: snapshot, at: point, operation: .move))
        runtime.update(at: CGPoint(x: point.x + 90, y: point.y + 55)); runtime.end()
        #expect(await f.waitFor { !runtime.isActive })
        #expect(f.backend.frame(f.source) == desired)
        #expect(f.backend.writes.allSatisfy { $0.0 == f.source })
        #expect(f.store.state().windowPins.first?.lastFrame.cgRect == desired)
    }

    @Test func deferredDropPersistsWithoutAnySynchronousFrameWrite() throws {
        let f = try Drag143Fixture(); defer { f.clean() }; f.live.invalidate()
        let old = f.store.state().bspTree(for: f.scope)
        let result = StageCommandService(service: f.service, store: f.store, events: EventLog(path: f.directory.appendingPathComponent("drop.jsonl").path))
            .place(windowID: f.source, displayID: f.scope.displayID, orderedWindowIDs: [f.neighbor, f.source, f.third],
                treeMutation: { $0.swapping(f.source, f.neighbor) }, deferGeometryUsing: f.context.snapshot)
        #expect(result.changed)
        #expect(f.backend.writes.isEmpty)
        #expect(f.store.state().bspTree(for: f.scope) != old)
    }

    @Test func aRejectedDropDoesNotWriteStateOrFrames() throws {
        let f = try Drag143Fixture(); defer { f.clean() }; f.live.invalidate()
        let old = try Data(contentsOf: f.store.fileURL)
        let result = StageCommandService(service: f.service, store: f.store, events: EventLog(path: f.directory.appendingPathComponent("drop.jsonl").path))
            .place(windowID: f.source, displayID: f.scope.displayID, orderedWindowIDs: [f.neighbor, f.source, f.third],
                deferGeometryUsing: f.context.snapshot, validating: { _ in false })
        #expect(!result.changed)
        #expect(f.backend.writes.isEmpty)
        #expect(try Data(contentsOf: f.store.fileURL) == old)
    }

    @Test func aModifiedClickIsReplayedOnceWithoutStartingADrag() throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        let input = UserInputActivity(), runtime = setup(f, input: input)
        var replayed: [CGEvent] = []
        let controller = ModifierWindowGestureController(service: f.service, runtime: runtime, input: input,
            replay: { replayed.append($0) }, snapshotProvider: { f.context.snapshot })
        defer { controller.stop() }
        let frame = f.original(f.source), point = CGPoint(x: frame.midX, y: frame.midY)
        let originalSource = try #require(CGEventSource(stateID: .privateState))
        originalSource.userData = 151209
        func event(_ type: CGEventType, x: CGFloat = 0) throws -> CGEvent {
            let e = try #require(CGEvent(mouseEventSource: originalSource, mouseType: type,
                mouseCursorPosition: CGPoint(x: point.x + x, y: point.y), mouseButton: .left))
            e.flags = .maskControl; return e
        }
        #expect(controller.handle(.leftMouseDown, event: try event(.leftMouseDown)))
        #expect(controller.handle(.leftMouseDragged, event: try event(.leftMouseDragged, x: 3)))
        #expect(controller.handle(.leftMouseUp, event: try event(.leftMouseUp, x: 3)))
        #expect(!runtime.isActive && !input.isCapturedPointerHeld)
        #expect(replayed.map(\.type) == [.leftMouseDown, .leftMouseUp])
        #expect(replayed.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == ModifierWindowGestureController.replayMarker && $0.flags.contains(.maskControl) })
        #expect(replayed.allSatisfy { CGEventSource(event: $0)?.userData == ModifierWindowGestureController.replayMarker })
        #expect(originalSource.userData == 151209)
        #expect(!controller.handle(.leftMouseDown, event: replayed[0]))
        #expect(f.backend.writes.isEmpty)
    }

    @Test func renewingTheCacheDoesNotLoseAModifiedClick() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        let input = UserInputActivity(), runtime = setup(f, input: input)
        var available = true, replayed: [CGEvent] = []
        let controller = ModifierWindowGestureController(service: f.service, runtime: runtime, input: input,
            replay: { replayed.append($0) }, snapshotProvider: { available ? f.context.snapshot : nil })
        defer { controller.stop() }
        let frame = f.original(f.source), point = CGPoint(x: frame.midX, y: frame.midY)
        func event(_ type: CGEventType) throws -> CGEvent {
            let e = try #require(CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left))
            e.flags = .maskControl; return e
        }
        #expect(controller.handle(.leftMouseDown, event: try event(.leftMouseDown)))
        available = false
        #expect(controller.handle(.leftMouseUp, event: try event(.leftMouseUp)))
        #expect(await f.waitFor { replayed.count == 2 })
        #expect(replayed.map(\.type) == [.leftMouseDown, .leftMouseUp])
    }

    @Test func theNextDragWaitsForThePreviousDropToSave() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        let input = UserInputActivity(), runtime = setup(f, input: input)
        let controller = ModifierWindowGestureController(service: f.service, runtime: runtime, input: input,
            snapshotProvider: { f.context.snapshot })
        defer { controller.stop() }
        let entry = f.context.snapshot.windows[0], frame = f.original(f.source)
        let point = CGPoint(x: frame.midX, y: frame.midY)
        f.backend.blockedPID = entry.window.pid
        #expect(runtime.begin(source: entry, snapshot: f.context.snapshot, at: point, operation: .resize))
        runtime.update(at: CGPoint(x: point.x + 100, y: point.y)); runtime.end()
        #expect(runtime.isEnding)
        func event(_ type: CGEventType, dx: CGFloat) throws -> CGEvent {
            let e = try #require(CGEvent(mouseEventSource: nil, mouseType: type,
                mouseCursorPosition: CGPoint(x: point.x + dx, y: point.y), mouseButton: .left))
            e.flags = [.maskControl, .maskAlternate]; return e
        }
        #expect(controller.handle(.leftMouseDown, event: try event(.leftMouseDown, dx: 0)))
        #expect(controller.handle(.leftMouseDragged, event: try event(.leftMouseDragged, dx: 80)))
        #expect(controller.handle(.leftMouseUp, event: try event(.leftMouseUp, dx: 80)))
        await Task.yield()
        #expect(runtime.isEnding)
        f.backend.blockedPID = nil; f.backend.gate.signal()
        #expect(await f.waitFor { !runtime.isActive && (f.backend.frame(f.source)?.width ?? 0) > frame.width + 150 })
        #expect(f.store.state().bspTree(for: f.scope) != f.context.persistedStateBeforeSnapshot.bspTree(for: f.scope))
    }

    @Test func notificationCenterBackdropDoesNotHideTheApplication() throws {
        let f = try Drag143Fixture(); defer { f.clean() }; f.live.invalidate()
        var snapshot = f.context.snapshot, backdrop = snapshot.windows[0]
        backdrop.window.id = WindowID(rawValue: 999); backdrop.window.bundleID = "com.apple.notificationcenterui"
        backdrop.window.frame = snapshot.displays[0].frame
        backdrop.window.isTileCandidate = false; backdrop.window.subrole = nil; backdrop.scope = nil
        snapshot.windows.insert(backdrop, at: 0)
        let frame = f.original(f.source), point = CGPoint(x: frame.midX, y: frame.midY)
        #expect(ModifierWindowRuntime.target(at: point, snapshot: snapshot)?.window.id == f.source)
        snapshot.windows[0].window.frame = Rect(CGRect(x: point.x - 50, y: point.y - 50, width: 100, height: 100))
        #expect(ModifierWindowRuntime.target(at: point, snapshot: snapshot) == nil)
    }

    @Test func frontmostIneligibleSurfaceProtectsTheWindowBehindIt() throws {
        let f = try Drag143Fixture(); defer { f.clean() }; f.live.invalidate()
        var snapshot = f.context.snapshot, panel = snapshot.windows[0]
        panel.window.id = WindowID(rawValue: 999); panel.window.isTileCandidate = false
        panel.window.subrole = "AXSystemDialog"; panel.scope = nil
        snapshot.windows.insert(panel, at: 0)
        let frame = panel.window.frame.cgRect
        #expect(ModifierWindowRuntime.target(at: CGPoint(x: frame.midX, y: frame.midY), snapshot: snapshot) == nil)
    }

    @Test func releasingModifiersBeforeTheButtonStillCommitsTheResize() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        let input = UserInputActivity(), runtime = setup(f, input: input)
        var replayed = 0
        let controller = ModifierWindowGestureController(service: f.service, runtime: runtime, input: input,
            replay: { _ in replayed += 1 }, snapshotProvider: { f.context.snapshot })
        defer { controller.stop() }
        let frame = f.original(f.source), point = CGPoint(x: frame.midX, y: frame.midY)
        let before = f.store.state().bspTree(for: f.scope)
        func event(_ type: CGEventType, dx: CGFloat, flags: CGEventFlags) throws -> CGEvent {
            let e = try #require(CGEvent(mouseEventSource: nil, mouseType: type,
                mouseCursorPosition: CGPoint(x: point.x + dx, y: point.y), mouseButton: .left)); e.flags = flags; return e
        }
        #expect(controller.handle(.leftMouseDown, event: try event(.leftMouseDown, dx: 0, flags: [.maskControl, .maskAlternate])))
        #expect(controller.handle(.leftMouseDragged, event: try event(.leftMouseDragged, dx: 100, flags: [.maskControl, .maskAlternate])))
        #expect(controller.handle(.leftMouseUp, event: try event(.leftMouseUp, dx: 100, flags: [])))
        #expect(await f.waitFor { !runtime.isActive && !input.isCapturedPointerHeld && !f.backend.writes.isEmpty })
        #expect(f.store.state().bspTree(for: f.scope) != before)
        #expect(replayed == 0)
    }

    @Test func escapeDrainsTheMouseSequenceWithoutReplayingAClick() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        let input = UserInputActivity(), runtime = setup(f, input: input)
        var replayed = 0
        let controller = ModifierWindowGestureController(service: f.service, runtime: runtime, input: input,
            replay: { _ in replayed += 1 }, snapshotProvider: { f.context.snapshot })
        defer { controller.stop() }
        let frame = f.original(f.source), point = CGPoint(x: frame.midX, y: frame.midY)
        func event(_ type: CGEventType, dx: CGFloat) throws -> CGEvent {
            let e = try #require(CGEvent(mouseEventSource: nil, mouseType: type,
                mouseCursorPosition: CGPoint(x: point.x + dx, y: point.y), mouseButton: .left)); e.flags = [.maskControl, .maskAlternate]; return e
        }
        #expect(controller.handle(.leftMouseDown, event: try event(.leftMouseDown, dx: 0)))
        #expect(controller.handle(.leftMouseDragged, event: try event(.leftMouseDragged, dx: 90)))
        #expect(await f.waitFor { runtime.isActive })
        runtime.flush()
        #expect(await f.waitFor { !f.backend.writes.isEmpty })
        let escape = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true))
        #expect(controller.handle(.keyDown, event: escape))
        #expect(controller.handle(.leftMouseUp, event: try event(.leftMouseUp, dx: 90)))
        #expect(await f.waitFor { !runtime.isActive && !input.isCapturedPointerHeld })
        #expect(f.backend.frame(f.source) == frame)
        #expect(replayed == 0)
    }

    @Test func twoDisabledBindingsNeverReserveTheMouse() throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        let path = f.directory.appendingPathComponent("disabled.toml").path
        try "[tiling]\ndrag_move_modifier = \"\"\ndrag_resize_modifier = \"\"\n".write(toFile: path, atomically: true, encoding: .utf8)
        _ = f.configService.reload(path: path)
        let input = UserInputActivity(), runtime = setup(f, input: input)
        let controller = ModifierWindowGestureController(service: f.service, runtime: runtime, input: input, snapshotProvider: { f.context.snapshot })
        defer { controller.stop() }
        let frame = f.original(f.source)
        let down = try #require(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
            mouseCursorPosition: CGPoint(x: frame.midX, y: frame.midY), mouseButton: .left))
        down.flags = [.maskControl, .maskAlternate]
        #expect(!controller.handle(.leftMouseDown, event: down))
        #expect(!input.isCapturedPointerHeld && !runtime.isActive)
    }

    @Test func aLostReleaseDoesNotKeepTheLayoutLocked() throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        let input = UserInputActivity(), runtime = setup(f, input: input)
        var pressed = true, now = Date()
        let controller = ModifierWindowGestureController(service: f.service, runtime: runtime, input: input,
            replay: { _ in Issue.record("Une séquence incomplète ne doit pas inventer un clic") },
            snapshotProvider: { f.context.snapshot }, clock: { now }, physicalLeftPressed: { pressed })
        defer { controller.stop() }
        let frame = f.original(f.source)
        let down = try #require(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
            mouseCursorPosition: CGPoint(x: frame.midX, y: frame.midY), mouseButton: .left))
        down.flags = .maskControl
        #expect(controller.handle(.leftMouseDown, event: down))
        #expect(input.isCapturedPointerHeld)
        now = now.addingTimeInterval(2)
        controller.checkPhysicalRelease()
        #expect(input.isCapturedPointerHeld)
        pressed = false
        controller.checkPhysicalRelease()
        #expect(!input.isCapturedPointerHeld && !runtime.isActive)
    }
}
