import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon
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
    func soleTiledWindowCoveringDisplayIsNotMaximized() {
        let display = powerDisplay()
        let window = powerWindow(1, x: 0, y: 0, width: 1000, height: 800)
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [display],
            windows: [ScopedWindowSnapshot(window: window, scope: scope)],
            state: RoadieState()
        )

        let states = WindowPresentationStateResolver().statesByWindowID(in: snapshot)

        #expect(states[window.id] == .normal)
        #expect(WindowPresentationStateResolver.state(for: window, on: display, isOnlyTiledWindowInScope: true) == .normal)
    }

    @Test
    func coveringWindowIsMaximizedWhenStageHasAnotherTiledWindow() {
        let display = powerDisplay()
        let covering = powerWindow(1, x: 0, y: 0, width: 1000, height: 800)
        let other = powerWindow(2, x: 100, y: 100, width: 300, height: 300)
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let otherStage = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "2"))
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [display],
            windows: [
                ScopedWindowSnapshot(window: covering, scope: scope),
                ScopedWindowSnapshot(window: other, scope: scope),
            ],
            state: RoadieState()
        )
        let alone = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [display],
            windows: [
                ScopedWindowSnapshot(window: covering, scope: scope),
                ScopedWindowSnapshot(window: other, scope: otherStage),
            ],
            state: RoadieState()
        )

        #expect(WindowPresentationStateResolver().statesByWindowID(in: snapshot)[covering.id] == .maximized)
        // Une fenêtre d'une autre stage ne compte pas : la fenêtre est seule dans son scope.
        #expect(WindowPresentationStateResolver().statesByWindowID(in: alone)[covering.id] == .normal)
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
        let sibling = powerWindow(2, x: 200, y: 200, width: 300, height: 300)
        let persistentScope = PersistentStageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stages: [
            PersistentStage(id: StageID(rawValue: "1"), members: [
                PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: maximizedFrame),
                PersistentStageMember(windowID: sibling.id, bundleID: sibling.bundleID, title: sibling.title, frame: sibling.frame)
            ])
        ])
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [display],
            windows: [
                ScopedWindowSnapshot(window: window, scope: scope),
                ScopedWindowSnapshot(window: sibling, scope: scope),
            ],
            state: RoadieState()
        )

        let states = RailController.railWindowPresentationStates(in: persistentScope, snapshot: snapshot)

        #expect(states[window.id] == .maximized)
        #expect(states[sibling.id] == .normal)
    }

    @Test
    func railShowsSoleTiledWindowAsNormalEvenWhenItCoversDisplay() {
        let display = powerDisplay()
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let window = powerWindow(1, x: 0, y: 0, width: 1000, height: 800)
        let persistentScope = PersistentStageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stages: [
            PersistentStage(id: StageID(rawValue: "1"), members: [
                PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame)
            ])
        ])
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [display],
            windows: [ScopedWindowSnapshot(window: window, scope: scope)],
            state: RoadieState()
        )

        let states = RailController.railWindowPresentationStates(in: persistentScope, snapshot: snapshot)

        #expect(states[window.id] == .normal)
    }

    @Test
    func railRepresentsMissingNativeFullscreenMember() {
        let display = powerDisplay()
        let windowID = WindowID(rawValue: 42)
        let observedAt = Date()
        let persistentScope = PersistentStageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stages: [
            PersistentStage(id: StageID(rawValue: "1"), members: [
                PersistentStageMember(
                    windowID: windowID,
                    bundleID: "app.fullscreen",
                    title: "Native",
                    frame: display.frame,
                    presentationState: .nativeFullscreen,
                    lastSeenAt: observedAt,
                    missingSince: observedAt
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
        let observedAt = Date()
        let persistentScope = PersistentStageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stages: [
            PersistentStage(id: StageID(rawValue: "1"), members: [
                PersistentStageMember(
                    windowID: windowID,
                    bundleID: "app.normal",
                    title: "Normal",
                    frame: Rect(x: 100, y: 100, width: 300, height: 300),
                    presentationState: .normal,
                    lastSeenAt: observedAt,
                    missingSince: observedAt
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
    func railDropsMissingMaximizedMemberAfterGrace() {
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

        #expect(ids.isEmpty)
        #expect(stage.members.isEmpty)
    }

    @Test
    func railDropsMissingNativeFullscreenMemberAfterFifteenSeconds() {
        let display = powerDisplay()
        let windowID = WindowID(rawValue: 48)
        let referenceDate = Date()
        func scope(missingFor seconds: TimeInterval) -> PersistentStageScope {
            PersistentStageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [
                    PersistentStageMember(
                        windowID: windowID,
                        bundleID: "app.fullscreen",
                        title: "Native",
                        frame: display.frame,
                        presentationState: .nativeFullscreen,
                        lastSeenAt: referenceDate.addingTimeInterval(-seconds),
                        missingSince: referenceDate.addingTimeInterval(-seconds)
                    )
                ])
            ])
        }

        #expect(RailController.railVisibleStageIDs(in: scope(missingFor: 10), liveWindowIDs: [], now: referenceDate) == [StageID(rawValue: "1")])
        #expect(RailController.railVisibleStageIDs(in: scope(missingFor: 20), liveWindowIDs: [], now: referenceDate).isEmpty)
    }

    @Test
    func railContentSignatureIsStableUntilVisibleContentChanges() {
        let display = powerDisplay()
        let first = powerWindow(1, x: 10)
        let second = powerWindow(2, x: 400)
        let scope = PersistentStageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stages: [
            PersistentStage(id: StageID(rawValue: "1"), members: [
                PersistentStageMember(windowID: first.id, bundleID: first.bundleID, title: first.title, frame: first.frame),
                PersistentStageMember(windowID: second.id, bundleID: second.bundleID, title: second.title, frame: second.frame),
            ])
        ])
        let live: Set<WindowID> = [first.id, second.id]

        func signature(live: Set<WindowID>, states: [WindowID: WindowPresentationState] = [:]) -> String {
            RailDisplayContent(scope: scope, presentationStates: states, liveWindowIDs: live).signature
        }

        // Deux cycles identiques : même signature, donc aucune reconstruction des vues.
        #expect(signature(live: live) == signature(live: live))
        // Une fenêtre qui disparaît (hors délai de grâce non atteint, elle reste représentée) ne change rien
        // tant que le contenu visible est identique ; un changement d'état de présentation, si.
        #expect(signature(live: live) != signature(live: live, states: [first.id: .maximized]))
        #expect(signature(live: live) != signature(live: [first.id]))
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
