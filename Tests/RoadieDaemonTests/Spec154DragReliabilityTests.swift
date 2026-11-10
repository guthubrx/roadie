import AppKit
import Testing
import RoadieCore
@testable import RoadieDaemon

@Suite(.serialized) @MainActor struct Spec154DragReliabilityTests {
    @Test func anExistingRoadieZoomDoesNotCancelTheDrag() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        f.live.invalidate()
        f.service.effectiveIntentStore.save(LayoutIntent(scope: f.scope, windowIDs: [f.source],
            placements: [f.source: Rect(f.original(f.source))], source: .command, zoomedWindowID: f.source))
        f.live.begin(f.context, sourceGestureOwned: true, sourceWindowID: f.source, keepSourceAtOrigin: true)
        f.live.update(nil) // Le pointeur quitte sa feuille avant d'atteindre l'autre écran.
        #expect(f.live.isActive)
        var committed = false
        f.live.update(f.candidate())
        f.live.finish { committed = true }
        #expect(await f.waitFor { committed })
    }

    @Test func aZoomCommandDuringTheDragStillCancelsItsDrop() throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        f.live.begin(f.context, sourceGestureOwned: true, sourceWindowID: f.source)
        f.service.effectiveIntentStore.save(LayoutIntent(scope: f.scope, windowIDs: [f.source],
            placements: [f.source: f.target], source: .command, zoomedWindowID: f.source))
        f.live.update(f.candidate())
        var committed = false
        f.live.finish { committed = true }
        #expect(!f.live.isActive && !committed)
    }
    @Test func aDuplicatedAppKitPressIsIgnoredButTheNextClickAtTheSamePointIsAccepted() {
        let rail = RailController()
        #expect(rail.acceptMouseDown(timestamp: 100, at: .zero))
        #expect(!rail.acceptMouseDown(timestamp: 100, at: .zero))
        #expect(rail.acceptMouseDown(timestamp: 100.01, at: .zero))
        #expect(rail.acceptMouseDown(timestamp: 100.01, at: CGPoint(x: 10, y: 20)))
        #expect(rail.acceptMouseDown(timestamp: 0, at: .zero))
        #expect(rail.acceptMouseDown(timestamp: 0, at: .zero))
    }

    @Test func cancellingAnInitiallyZoomedDragRestoresItsFramesAndIntent() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        f.live.invalidate()
        let intent = LayoutIntent(scope: f.scope, windowIDs: [f.source],
            placements: [f.source: Rect(f.original(f.source))], source: .command, zoomedWindowID: f.source)
        f.service.effectiveIntentStore.save(intent)
        f.live.begin(f.context, sourceGestureOwned: true, sourceWindowID: f.source, keepSourceAtOrigin: true)
        f.live.update(f.candidate())
        #expect(await f.waitFor { f.backend.frame(f.neighbor) == f.target.cgRect })
        f.live.finish()
        #expect(await f.waitFor { !f.live.isActive })
        #expect(f.backend.frame(f.neighbor) == f.original(f.neighbor))
        #expect(f.service.effectiveIntentStore.intent(for: f.scope) == intent)
    }

    @Test func replacingTheZoomWithAnotherZoomDuringTheDragRejectsTheDrop() throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        f.live.invalidate()
        f.service.effectiveIntentStore.save(LayoutIntent(scope: f.scope, windowIDs: [f.source],
            placements: [f.source: f.target], source: .command, zoomedWindowID: f.source))
        f.live.begin(f.context, sourceGestureOwned: true, sourceWindowID: f.source)
        f.service.effectiveIntentStore.save(LayoutIntent(scope: f.scope, windowIDs: [f.neighbor],
            placements: [f.neighbor: f.target], source: .command, zoomedWindowID: f.neighbor))
        f.live.update(f.candidate())
        var committed = false
        f.live.finish { committed = true }
        #expect(!f.live.isActive && !committed)
    }

    @Test func updatingFramesOfTheSameZoomDoesNotRejectTheDrop() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        f.live.invalidate()
        var zoom = LayoutIntent(scope: f.scope, windowIDs: [f.source],
            placements: [f.source: Rect(f.original(f.source))], source: .command, zoomedWindowID: f.source)
        f.service.effectiveIntentStore.save(zoom)
        f.live.begin(f.context, sourceGestureOwned: true, sourceWindowID: f.source)
        zoom.placements[f.source] = f.target
        zoom.createdAt = Date()
        f.service.effectiveIntentStore.save(zoom)
        f.live.update(f.candidate())
        var committed = false
        f.live.finish { committed = true }
        #expect(await f.waitFor { committed })
    }

    @Test func removingTheZoomDuringTheDragRejectsTheDrop() throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        f.live.invalidate()
        f.service.effectiveIntentStore.save(LayoutIntent(scope: f.scope, windowIDs: [f.source],
            placements: [f.source: f.target], source: .command, zoomedWindowID: f.source))
        f.live.begin(f.context, sourceGestureOwned: true, sourceWindowID: f.source)
        f.service.effectiveIntentStore.remove(scope: f.scope)
        f.live.update(f.candidate())
        var committed = false
        f.live.finish { committed = true }
        #expect(!f.live.isActive && !committed)
    }

    @Test func aNonZoomIntentUpdateDoesNotCancelTheDrag() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        f.live.begin(f.context, sourceGestureOwned: true, sourceWindowID: f.source)
        f.service.effectiveIntentStore.save(LayoutIntent(scope: f.scope, windowIDs: [f.source],
            placements: [f.source: f.target], source: .command))
        f.live.update(f.candidate())
        var committed = false
        f.live.finish { committed = true }
        #expect(await f.waitFor { committed })
    }

}

@Suite @MainActor struct Spec154PointerOcclusionTests {
    @Test func notificationCenterBackdropDoesNotBlockTitleOrResize() throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        var snapshot = f.context.snapshot, backdrop = snapshot.windows[0]
        backdrop.window.id = WindowID(rawValue: 999)
        backdrop.window.bundleID = "com.apple.notificationcenterui"
        backdrop.window.frame = snapshot.displays[0].frame
        backdrop.window.isTileCandidate = false; backdrop.window.subrole = nil; backdrop.scope = nil
        snapshot.windows.insert(backdrop, at: 0)
        let frame = f.original(f.source), point = CGPoint(x: frame.midX, y: frame.minY + 12)
        #expect(WindowDragReorderController.dragSourceWindow(atAXPoint: point, in: snapshot)?.window.id == f.source)
        #expect(FocusFollowsMousePicker.gestureTargetWindow(at: point, in: snapshot)?.window.id == f.source)
        #expect(FocusFollowsMousePicker.targetWindow(at: point, in: snapshot)?.window.id == f.source)
    }

    @Test(arguments: [false, true]) func aRealNotificationPanelStillBlocksTheWindowBehindIt(identified: Bool) throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        var snapshot = f.context.snapshot, panel = snapshot.windows[0]
        let frame = f.original(f.source), point = CGPoint(x: frame.midX, y: frame.minY + 12)
        panel.window.id = WindowID(rawValue: 999); panel.window.bundleID = "com.apple.notificationcenterui"
        panel.window.frame = Rect(CGRect(x: point.x - 50, y: point.y - 10, width: 100, height: 100))
        panel.window.isTileCandidate = false; panel.window.subrole = identified ? "AXSystemDialog" : nil; panel.scope = nil
        if identified { panel.window.frame = snapshot.displays[0].frame }
        snapshot.windows.insert(panel, at: 0)
        #expect(WindowDragReorderController.dragSourceWindow(atAXPoint: point, in: snapshot) == nil)
        #expect(FocusFollowsMousePicker.gestureTargetWindow(at: point, in: snapshot) == nil)
        #expect(FocusFollowsMousePicker.targetWindow(at: point, in: snapshot) == nil)
    }
}

@Suite(.serialized) @MainActor struct Spec154ModifierDisplayTests {
    @Test(arguments: [false, true]) func focusMetadataDoesNotCancelButGeometryChangesDo(geometryChanged: Bool) throws {
        let f = try Drag143Fixture(); defer { f.clean() }; f.live.invalidate()
        let latest = f.service.sharedSnapshot()
        var press = latest
        if geometryChanged { press.displays[0].frame.x += 10 }
        else { press.displays[0].isMain.toggle() }
        let source = try #require(press.windows.first { $0.window.id == f.source })
        let point = CGPoint(x: source.window.frame.x + 50, y: source.window.frame.y + 50)
        let runtime = ModifierWindowRuntime(service: f.service, input: UserInputActivity(), automaticCadence: false)
        defer { runtime.cancelImmediately(reason: "test") }
        #expect(runtime.begin(source: source, snapshot: press, at: point, operation: .resize))
        runtime.flush()
        #expect(runtime.isActive == !geometryChanged)
    }
}
