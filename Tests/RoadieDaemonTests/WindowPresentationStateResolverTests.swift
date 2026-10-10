import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon
import RoadieStages

@Suite
struct WindowPresentationStateResolverTests {
    @Test
    func regularWindowIsNormal() {
        let display = powerDisplay()
        let window = powerWindow(1, x: 80, y: 90, width: 500, height: 360)

        let state = WindowPresentationStateResolver.state(for: window, on: display)

        #expect(state == .normal)
    }

    @Test
    func nearVisibleFrameWindowIsMaximized() {
        let display = powerDisplay()
        let window = powerWindow(1, x: 4, y: 6, width: 992, height: 790)

        let state = WindowPresentationStateResolver.state(for: window, on: display)

        #expect(state == .maximized)
    }

    @Test
    func nativeFullscreenTakesPrecedenceOverMaximizedFrame() {
        let display = powerDisplay()
        var window = powerWindow(1, x: 0, y: 0, width: 1000, height: 800)
        window.furniture = WindowFurniture(
            hasCloseButton: true,
            hasFullscreenButton: true,
            fullscreenButtonEnabled: true,
            isNativeFullscreen: true
        )

        let state = WindowPresentationStateResolver.state(for: window, on: display)

        #expect(state == .nativeFullscreen)
    }

    @Test
    func railUsesPersistedMemberFrameForParkedMaximizedWindow() {
        let display = powerDisplay()
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let parkedFrame = Rect(x: 1200, y: 799, width: 300, height: 300)
        let maximizedFrame = Rect(x: 0, y: 0, width: 1000, height: 800)
        let window = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 1,
            appName: "Terminal",
            bundleID: "terminal",
            title: "Terminal",
            frame: parkedFrame,
            isOnScreen: true,
            isTileCandidate: true
        )
        let persistentScope = PersistentStageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stages: [
            PersistentStage(id: StageID(rawValue: "1"), members: [
                PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: maximizedFrame)
            ])
        ])
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [display],
            windows: [ScopedWindowSnapshot(window: window, scope: scope)],
            state: RoadieState()
        )

        let states = RailController.railWindowPresentationStates(in: persistentScope, snapshot: snapshot)

        #expect(states[window.id] == .maximized)
    }

    @Test
    func railRepresentsMissingNativeFullscreenMember() {
        let display = powerDisplay()
        let windowID = WindowID(rawValue: 42)
        let persistentScope = PersistentStageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stages: [
            PersistentStage(id: StageID(rawValue: "1"), members: [
                PersistentStageMember(
                    windowID: windowID,
                    bundleID: "app.fullscreen",
                    title: "Native",
                    frame: display.frame,
                    presentationState: .nativeFullscreen,
                    missingSince: Date()
                )
            ])
        ])
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [display],
            windows: [],
            state: RoadieState()
        )

        let ids = RailController.railVisibleStageIDs(in: persistentScope, liveWindowIDs: [])
        let stage = RailController.railDisplayStage(persistentScope.stages[0], liveWindowIDs: [])
        let states = RailController.railWindowPresentationStates(in: persistentScope, snapshot: snapshot)

        #expect(ids == [StageID(rawValue: "1")])
        #expect(stage.members.map(\.windowID) == [windowID])
        #expect(states[windowID] == .nativeFullscreen)
    }

    @Test
    func railDoesNotRepresentMissingNormalMember() {
        let display = powerDisplay()
        let windowID = WindowID(rawValue: 43)
        let staleMissingSince = Date(timeIntervalSinceNow: -60)
        let persistentScope = PersistentStageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stages: [
            PersistentStage(id: StageID(rawValue: "1"), members: [
                PersistentStageMember(
                    windowID: windowID,
                    bundleID: "app.normal",
                    title: "Normal",
                    frame: Rect(x: 100, y: 100, width: 300, height: 300),
                    presentationState: .normal,
                    missingSince: staleMissingSince
                )
            ])
        ])

        let ids = RailController.railVisibleStageIDs(in: persistentScope, liveWindowIDs: [])
        let stage = RailController.railDisplayStage(persistentScope.stages[0], liveWindowIDs: [])

        #expect(ids.isEmpty)
        #expect(stage.members.isEmpty)
    }

    @Test
    func railKeepsRecentlyMissingNormalMemberDuringStageSwitch() {
        let display = powerDisplay()
        let windowID = WindowID(rawValue: 45)
        let persistentScope = PersistentStageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stages: [
            PersistentStage(id: StageID(rawValue: "1"), members: [
                PersistentStageMember(
                    windowID: windowID,
                    bundleID: "app.normal",
                    title: "Normal",
                    frame: Rect(x: 100, y: 100, width: 300, height: 300),
                    presentationState: .normal,
                    missingSince: Date()
                )
            ])
        ])

        let ids = RailController.railVisibleStageIDs(in: persistentScope, liveWindowIDs: [])
        let stage = RailController.railDisplayStage(persistentScope.stages[0], liveWindowIDs: [])

        #expect(ids == [StageID(rawValue: "1")])
        #expect(stage.members.map(\.windowID) == [windowID])
    }

    @Test
    func railDoesNotKeepStaleMissingNormalMemberDuringFullscreen() {
        let display = powerDisplay()
        let windowID = WindowID(rawValue: 46)
        let staleMissingSince = Date(timeIntervalSinceNow: -120)
        let persistentScope = PersistentStageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stages: [
            PersistentStage(id: StageID(rawValue: "1"), members: [
                PersistentStageMember(
                    windowID: windowID,
                    bundleID: "app.normal",
                    title: "Normal",
                    frame: Rect(x: 100, y: 100, width: 300, height: 300),
                    presentationState: .normal,
                    missingSince: staleMissingSince
                )
            ])
        ])

        let ids = RailController.railVisibleStageIDs(in: persistentScope, liveWindowIDs: [])
        let stage = RailController.railDisplayStage(persistentScope.stages[0], liveWindowIDs: [])

        #expect(ids.isEmpty)
        #expect(stage.members.isEmpty)
    }

    @Test
    func railRepresentsMissingMaximizedMember() {
        let display = powerDisplay()
        let windowID = WindowID(rawValue: 47)
        let persistentScope = PersistentStageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stages: [
            PersistentStage(id: StageID(rawValue: "1"), members: [
                PersistentStageMember(
                    windowID: windowID,
                    bundleID: "app.maximized",
                    title: "Maximized",
                    frame: display.visibleFrame,
                    presentationState: .maximized,
                    missingSince: Date(timeIntervalSinceNow: -120)
                )
            ])
        ])

        let ids = RailController.railVisibleStageIDs(in: persistentScope, liveWindowIDs: [])
        let stage = RailController.railDisplayStage(persistentScope.stages[0], liveWindowIDs: [])

        #expect(ids == [StageID(rawValue: "1")])
        #expect(stage.members.map(\.windowID) == [windowID])
    }

    @Test
    func snapshotPersistsNativeFullscreenPresentationState() {
        let display = powerDisplay()
        var window = powerWindow(44, x: 0, y: 0, width: 1000, height: 800)
        window.furniture = WindowFurniture(
            hasCloseButton: true,
            hasFullscreenButton: true,
            fullscreenButtonEnabled: true,
            isNativeFullscreen: true
        )
        let provider = PowerUserProvider(displays: [display], windows: [window])
        let store = StageStore(path: tempPath("native-fullscreen-presentation-persisted"))
        let service = SnapshotService(provider: provider, stageStore: store)

        _ = service.snapshot()

        let member = store.state().scopes.first?.stages.first?.members.first
        #expect(member?.windowID == window.id)
        #expect(member?.presentationState == .nativeFullscreen)
    }
}
