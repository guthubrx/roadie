import Foundation
import Testing
import RoadieCore
import RoadieAX
@testable import RoadieDaemon

@Suite @MainActor struct Spec144RealDropTests {
    private func real(_ f: Drag143Fixture, enabled: Bool, owned: Bool = true) throws {
        let path = try #require(f.configService.state.activePath)
        try "[tiling]\nlive_drag_preview=\(enabled)\n[fx]\ndrop_preview='real'\n".write(toFile: path, atomically: true, encoding: .utf8)
        _ = f.configService.reload(path: path)
        f.live.begin(f.context, sourceGestureOwned: owned)
    }
    @Test(arguments: [false, true]) func realSourceAndNeighborsAreIndependent(neighbors: Bool) async throws {
        let f = try Drag143Fixture(enabled: neighbors); defer { f.clean() }
        try real(f, enabled: neighbors)
        f.live.update(f.candidate())
        #expect(await f.waitFor { f.backend.frame(f.source) == f.target.cgRect })
        if neighbors { #expect(await f.waitFor { f.backend.frame(f.neighbor) == f.target.cgRect }) }
        else { #expect(f.backend.frame(f.neighbor) == f.original(f.neighbor)) }
        #expect(f.store.state() == f.context.persistedStateBeforeSnapshot)
        f.live.finish()
        #expect(await f.waitFor { !f.live.isActive })
        #expect(f.backend.frame(f.source) == f.original(f.source))
        #expect(f.backend.frame(f.neighbor) == f.original(f.neighbor))
    }
    @Test func realSettingCannotWriteNativeSourceWithoutOwnership() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        try real(f, enabled: true, owned: false)
        f.live.update(f.candidate())
        #expect(await f.waitFor { f.backend.frame(f.neighbor) == f.target.cgRect })
        #expect(!f.backend.writes.contains { $0.0 == f.source })
    }
    @Test func leavingDestinationRestoresSourceAndNoOldTargetReturns() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        try real(f, enabled: true)
        f.live.update(f.candidate())
        #expect(await f.waitFor { f.backend.frame(f.source) == f.target.cgRect })
        f.live.update(nil)
        #expect(await f.waitFor { f.backend.frame(f.source) == f.original(f.source) })
        f.live.finish()
        #expect(await f.waitFor { !f.live.isActive })
        #expect(f.backend.frame(f.source) == f.original(f.source))
    }
}

extension Spec144RealDropTests {
    @Test(arguments: ["pin", "closed", "mode"])
    func changedContextPreventsCommitOfRealSource(change: String) async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        try real(f, enabled: true)
        f.live.update(f.candidate())
        #expect(await f.waitFor { f.backend.frame(f.source) == f.target.cgRect })
        f.store.mutate { state in
            if change == "pin" {
                state.windowPins.append(PersistentWindowPin(windowID: f.source, homeScope: f.scope, pinScope: .desktop,
                    bundleID: "app.1", title: "Window 1", lastFrame: f.target))
            } else if change == "closed" {
                state.scopes[0].stages[0].members[0].confirmedClosedAt = Date()
            } else { state.scopes[0].stages[0].mode = .float }
        }
        f.live.update(f.candidate())
        var committed = false
        f.live.finish { committed = true }
        #expect(!f.live.isActive && !committed)
    }
    @Test func changingRealPreviewSettingRestoresSourceWhileKeepingLiveNeighbors() async throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        try real(f, enabled: true)
        f.live.update(f.candidate())
        #expect(await f.waitFor { f.backend.frame(f.source) == f.target.cgRect })
        try f.toggle(true) // Sans clé fx : retour au contour, voisines toujours actives.
        #expect(await f.waitFor { f.backend.frame(f.source) == f.original(f.source) })
        #expect(f.backend.frame(f.neighbor) == f.target.cgRect)
        #expect(f.store.state() == f.context.persistedStateBeforeSnapshot)
    }
}


extension Spec144RealDropTests {
    @Test func anotherDisplayKeepsRealSourceAndRestoresItOnCancel() async throws {
        let f = try Drag143Fixture(enabled: false); defer { f.clean() }
        let other = StageScope(displayID: DisplayID(rawValue: "other"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        f.store.mutate { state in
            state.scopes.append(PersistentStageScope(displayID: other.displayID, activeStageID: other.stageID,
                stages: [PersistentStage(id: other.stageID, mode: .spatialBsp, members: [])]))
        }
        try real(f, enabled: false)
        f.live.update(f.candidate())
        #expect(f.live.showsRealSource)
        #expect(await f.waitFor { f.backend.frame(f.source) == f.target.cgRect })
        var candidate = f.candidate()
        candidate.displayID = other.displayID; candidate.scope = other
        let destination = Rect(x: 2100, y: 50, width: 450, height: 800)
        candidate.frame = destination.cgRect; candidate.placements[f.source] = destination
        f.live.update(candidate)
        #expect(f.live.showsRealSource)
        #expect(await f.waitFor { f.backend.frame(f.source) == destination.cgRect })
        #expect(f.backend.frame(f.neighbor) == f.original(f.neighbor))
        #expect(f.live.isActive)
        f.live.finish()
        #expect(await f.waitFor { !f.live.isActive })
        #expect(f.backend.frame(f.source) == f.original(f.source))
    }
}


extension Spec144RealDropTests {
    @Test func aPinnedOrNativeFullscreenWindowNeverStartsSourceCapture() throws {
        let f = try Drag143Fixture(); defer { f.clean() }
        var snapshot = f.context.snapshot
        let i = try #require(snapshot.windows.firstIndex { $0.window.id == f.source })
        let frame = snapshot.windows[i].window.frame.cgRect
        let point = CGPoint(x: frame.midX, y: frame.minY+12)
        snapshot.windows[i].pin = PersistentWindowPin(windowID: f.source, homeScope: f.scope, pinScope: .desktop,
            bundleID: "app.1", title: "Window 1", lastFrame: Rect(frame))
        #expect(WindowDragReorderController.dragSourceWindow(atAXPoint: point, in: snapshot) == nil)
        snapshot.windows[i].pin = nil
        snapshot.windows[i].window.furniture = WindowFurniture(isResizable: true, isNativeFullscreen: true)
        #expect(WindowDragReorderController.dragSourceWindow(atAXPoint: point, in: snapshot) == nil)
    }
}
