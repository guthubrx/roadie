import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon
import RoadieTiler

@Suite
struct PowerUserDesktopCommandTests {
    @Test
    func desktopBackAndForthReturnsToPreviousDesktop() {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100)])
        let store = StageStore(path: tempPath("power-desktop-stages"))
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)
        _ = service.snapshot()
        let commands = DesktopCommandService(service: service, store: store)

        let focusTwo = commands.focus(DesktopID(rawValue: 2))
        let back = commands.backAndForth()

        #expect(focusTwo.changed)
        #expect(back.changed)
        #expect(store.state().currentDesktopID(for: DisplayID(rawValue: "display-main")) == DesktopID(rawValue: 1))
    }

    @Test
    func desktopSummonSwitchesRequestedDesktopToActiveDisplay() {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100)])
        let store = StageStore(path: tempPath("power-desktop-summon"))
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)
        _ = service.snapshot()

        let result = DesktopCommandService(service: service, store: store).summon(DesktopID(rawValue: 3))

        #expect(result.changed)
        #expect(store.state().currentDesktopID(for: DisplayID(rawValue: "display-main")) == DesktopID(rawValue: 3))
    }

    @Test
    func stageMoveToDisplayMovesActiveStageMembership() {
        let displays = [
            powerDisplay("display-main", index: 1, x: 0),
            powerDisplay("display-side", index: 2, x: 1000)
        ]
        let provider = PowerUserProvider(displays: displays, windows: [powerWindow(1, x: 100)])
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("power-stage-move"))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)
        _ = service.snapshot()

        let result = StageCommandService(service: service, store: store).moveActiveStageToDisplay(index: 2)

        var state = store.state()
        #expect(result.changed)
        #expect(state.activeDisplayID == DisplayID(rawValue: "display-side"))
        #expect(state.scope(displayID: DisplayID(rawValue: "display-side")).stages.contains { $0.members.contains { $0.windowID == WindowID(rawValue: 1) } })
    }

    @Test
    func stagePositionCommandsFollowVisibleRailOrder() {
        let display = DisplayID(rawValue: "display-main")
        let windows = [
            powerWindow(1, x: 100),
            powerWindow(2, x: 1200),
            powerWindow(3, x: 1400)
        ]
        let provider = PowerUserProvider(windows: windows)
        provider.focusedID = windows[0].id
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("power-stage-position"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [
                    PersistentStageMember(windowID: windows[0].id, bundleID: windows[0].bundleID, title: windows[0].title, frame: windows[0].frame),
                ]),
                PersistentStage(id: StageID(rawValue: "3"), members: [
                    PersistentStageMember(windowID: windows[1].id, bundleID: windows[1].bundleID, title: windows[1].title, frame: Rect(x: 350, y: 100, width: 300, height: 300)),
                ]),
                PersistentStage(id: StageID(rawValue: "4"), members: [
                    PersistentStageMember(windowID: windows[2].id, bundleID: windows[2].bundleID, title: windows[2].title, frame: Rect(x: 650, y: 100, width: 300, height: 300)),
                ]),
            ]),
        ]))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)
        let commands = StageCommandService(service: service, store: store)

        let switchSecond = commands.switchToPosition(2)
        let reorder = commands.reorder("4", to: 1)
        let switchFirstAfterReorder = commands.switchToPosition(1)

        var state = store.state()
        #expect(switchSecond.changed)
        #expect(reorder.changed)
        #expect(switchFirstAfterReorder.changed)
        #expect(state.scope(displayID: display).activeStageID == StageID(rawValue: "4"))
        #expect(writer.focused.map(\.rawValue).contains(2))
        #expect(writer.focused.map(\.rawValue).contains(3))
    }

    @Test
    func stageSwitchVisibleFollowsNonEmptyRailOrder() {
        let display = DisplayID(rawValue: "display-main")
        let work = powerWindow(1, x: 100)
        let stageSix = powerWindow(2, x: 1200)
        let stageTwo = powerWindow(3, x: 1400)
        let stageSeven = powerWindow(4, x: 1600)
        var nonTileable = powerWindow(5, x: 1800)
        nonTileable.isTileCandidate = false
        let provider = PowerUserProvider(windows: [work, stageSix, stageTwo, stageSeven, nonTileable])
        provider.focusedID = work.id
        let store = StageStore(path: tempPath("power-stage-switch-visible"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "work"), stages: [
                PersistentStage(id: StageID(rawValue: "work"), name: "Work", members: [
                    PersistentStageMember(windowID: work.id, bundleID: work.bundleID, title: work.title, frame: work.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "stale"), name: "Stage stale", members: [
                    PersistentStageMember(windowID: WindowID(rawValue: 999), bundleID: "com.example.missing", title: "Missing", frame: work.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "non-tileable"), name: "Stage non-tileable", members: [
                    PersistentStageMember(windowID: nonTileable.id, bundleID: nonTileable.bundleID, title: nonTileable.title, frame: nonTileable.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "empty"), name: "Stage empty"),
                PersistentStage(id: StageID(rawValue: "six"), name: "Stage 6", members: [
                    PersistentStageMember(windowID: stageSix.id, bundleID: stageSix.bundleID, title: stageSix.title, frame: Rect(x: 350, y: 100, width: 300, height: 300)),
                ]),
                PersistentStage(id: StageID(rawValue: "perso"), name: "Perso"),
                PersistentStage(id: StageID(rawValue: "two"), name: "Stage 2", members: [
                    PersistentStageMember(windowID: stageTwo.id, bundleID: stageTwo.bundleID, title: stageTwo.title, frame: Rect(x: 650, y: 100, width: 300, height: 300)),
                ]),
                PersistentStage(id: StageID(rawValue: "seven"), name: "Stage 7", members: [
                    PersistentStageMember(windowID: stageSeven.id, bundleID: stageSeven.bundleID, title: stageSeven.title, frame: Rect(x: 950, y: 100, width: 300, height: 300)),
                ]),
            ]),
        ]))
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)
        let commands = StageCommandService(service: service, store: store)

        let nextOne = commands.switchVisible(.next)
        let nextTwo = commands.switchVisible(.next)
        let previous = commands.switchVisible(.prev)
        var state = store.state()

        #expect(nextOne.changed)
        #expect(nextTwo.changed)
        #expect(previous.changed)
        #expect(state.scope(displayID: display).activeStageID == StageID(rawValue: "six"))
    }

    @Test
    func stageSwitchPersistsTargetStageBeforeRestoringWindows() {
        let display = DisplayID(rawValue: "display-main")
        let visible = powerWindow(1, x: 100)
        var hidden = powerWindow(2, x: 999)
        hidden.frame = Rect(x: 999, y: 499, width: 400, height: 300)
        let provider = PowerUserProvider(windows: [visible, hidden])
        provider.focusedID = visible.id
        let store = StageStore(path: tempPath("power-stage-switch-order"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [
                    PersistentStageMember(windowID: visible.id, bundleID: visible.bundleID, title: visible.title, frame: visible.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "2"), focusedWindowID: hidden.id, members: [
                    PersistentStageMember(windowID: hidden.id, bundleID: hidden.bundleID, title: hidden.title, frame: Rect(x: 250, y: 50, width: 500, height: 350)),
                ]),
            ]),
        ]))
        let writer = StageSwitchOrderWriter(provider: provider, store: store, observedWindowID: hidden.id)
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)

        let result = StageCommandService(service: service, store: store).switchToPosition(2)

        #expect(result.changed)
        #expect(!writer.activeStagesObservedForTargetFrame.isEmpty)
        #expect(writer.activeStagesObservedForTargetFrame.allSatisfy { $0 == StageID(rawValue: "2") })
    }

    @Test
    func stageSwitchMarksLayoutCommandActivity() {
        let display = DisplayID(rawValue: "display-main")
        let visible = powerWindow(1, x: 100)
        var hidden = powerWindow(2, x: 999)
        hidden.frame = Rect(x: 999, y: 499, width: 400, height: 300)
        let provider = PowerUserProvider(windows: [visible, hidden])
        provider.focusedID = visible.id
        let store = StageStore(path: tempPath("power-stage-switch-command-activity"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [
                    PersistentStageMember(windowID: visible.id, bundleID: visible.bundleID, title: visible.title, frame: visible.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "2"), members: [
                    PersistentStageMember(windowID: hidden.id, bundleID: hidden.bundleID, title: hidden.title, frame: Rect(x: 250, y: 50, width: 500, height: 350)),
                ]),
            ]),
        ]))
        let writer = PowerUserWriter(provider: provider)
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)
        let commandActivity = LayoutCommandActivity(path: tempPath("power-stage-switch-command-activity-lock"), enabled: true)
        commandActivity.reset()

        let result = StageCommandService(service: service, store: store, commandActivity: commandActivity).switchToPosition(2)

        #expect(result.changed)
        #expect(commandActivity.isActive())
        commandActivity.reset()
    }

    @Test
    func stageSwitchToAlreadyActiveStageDoesNotReapplyLayout() {
        let display = DisplayID(rawValue: "display-main")
        let visible = powerWindow(1, x: 100)
        let provider = PowerUserProvider(windows: [visible])
        provider.focusedID = visible.id
        let writer = PowerUserWriter(provider: provider)
        let eventPath = tempPath("power-stage-switch-noop-events")
        let store = StageStore(path: tempPath("power-stage-switch-noop"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [
                    PersistentStageMember(windowID: visible.id, bundleID: visible.bundleID, title: visible.title, frame: visible.frame),
                ]),
            ]),
        ]))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)

        let result = StageCommandService(
            service: service,
            store: store,
            events: EventLog(path: eventPath)
        ).switchTo("1", displayID: display)

        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        #expect(!result.changed)
        #expect(writer.frames.isEmpty)
        #expect(writer.focused.isEmpty)
        #expect(events.contains("\"type\":\"stage_switch_noop\""))
        #expect(!events.contains("\"type\":\"stage_switch\""))
    }

    @Test
    func repeatedStageSwitchToAlreadyActiveHiddenStageRestoresMembers() {
        let display = DisplayID(rawValue: "display-main")
        var hidden = powerWindow(1, x: -20000)
        hidden.frame = Rect(x: -20000, y: 120, width: 400, height: 300)
        let targetFrame = Rect(x: 120, y: 80, width: 500, height: 360)
        let provider = PowerUserProvider(windows: [hidden])
        provider.focusedID = nil
        let writer = PowerUserWriter(provider: provider)
        let eventPath = tempPath("power-stage-switch-reconcile-hidden-active-events")
        let store = StageStore(path: tempPath("power-stage-switch-reconcile-hidden-active"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: hidden.id, members: [
                    PersistentStageMember(windowID: hidden.id, bundleID: hidden.bundleID, title: hidden.title, frame: targetFrame),
                ]),
            ]),
        ]))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)

        let result = StageCommandService(
            service: service,
            store: store,
            events: EventLog(path: eventPath)
        ).switchTo("1", displayID: display)

        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        #expect(result.changed)
        #expect(writer.frames[hidden.id] == targetFrame)
        #expect(writer.focused == [hidden.id])
        #expect(events.contains("\"type\":\"stage_switch_reconcile\""))
        #expect(events.contains("\"reason\":\"active_stage_members_not_visible\""))
        #expect(!events.contains("\"type\":\"stage_switch_noop\""))
    }

    @Test
    func repeatedStageSwitchToAlreadyActiveMissingStageFocusesApplicationWindow() {
        let display = DisplayID(rawValue: "display-main")
        let missing = powerWindow(1, x: 120)
        let provider = PowerUserProvider(windows: [])
        provider.focusedID = nil
        let writer = PowerUserWriter(provider: provider)
        writer.applicationWindowFocusResult = true
        let eventPath = tempPath("power-stage-switch-reconcile-missing-active-events")
        let store = StageStore(path: tempPath("power-stage-switch-reconcile-missing-active"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: missing.id, members: [
                    PersistentStageMember(
                        windowID: missing.id,
                        bundleID: missing.bundleID,
                        title: missing.title,
                        frame: missing.frame,
                        missingSince: Date(timeIntervalSinceNow: -5)
                    ),
                ]),
            ]),
        ]))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)

        let result = StageCommandService(
            service: service,
            store: store,
            events: EventLog(path: eventPath)
        ).switchTo("1", displayID: display)

        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        #expect(result.changed)
        #expect(writer.frames.isEmpty)
        #expect(writer.focusedApplicationWindows == [missing.id])
        #expect(writer.activatedBundleIDs.isEmpty)
        #expect(events.contains("\"type\":\"stage_switch_reconcile\""))
        #expect(events.contains("\"focusedApplicationWindow\":\"true\""))
        #expect(!events.contains("\"type\":\"stage_switch_noop\""))
    }

    @Test
    func stageSwitchToTargetWithOnlyStaleMissingMembersSwitchesAndRecallsApplication() {
        let display = DisplayID(rawValue: "display-main")
        let visible = powerWindow(1, x: 100)
        let missing = powerWindow(2, x: 300)
        let provider = PowerUserProvider(windows: [visible])
        provider.focusedID = visible.id
        let writer = PowerUserWriter(provider: provider)
        let eventPath = tempPath("power-stage-switch-pending-stale-missing-target-events")
        let store = StageStore(path: tempPath("power-stage-switch-pending-stale-missing-target"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: visible.id, members: [
                    PersistentStageMember(windowID: visible.id, bundleID: visible.bundleID, title: visible.title, frame: visible.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "2"), focusedWindowID: missing.id, members: [
                    PersistentStageMember(
                        windowID: missing.id,
                        bundleID: missing.bundleID,
                        title: missing.title,
                        frame: missing.frame,
                        lastSeenAt: Date(timeIntervalSinceNow: -25),
                        missingSince: Date(timeIntervalSinceNow: -25)
                    ),
                ]),
            ]),
        ]))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)

        let result = StageCommandService(
            service: service,
            store: store,
            events: EventLog(path: eventPath)
        ).switchTo("2", displayID: display)

        // SPEC-016 T042 : une stage dont toutes les fenêtres ont disparu reste atteignable.
        // La bascule a lieu, la stage courante est cachée, puis l'application est rappelée.
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        #expect(result.changed)
        #expect(writer.frames[visible.id]?.x == 999)
        #expect(writer.focusedApplicationWindows == [missing.id])
        #expect(writer.activatedBundleIDs == [missing.bundleID])
        #expect(store.state().scopes.first?.activeStageID == StageID(rawValue: "2"))
        #expect(store.state().commandFocusProtection != nil)
        #expect(events.contains("\"type\":\"stage_switch_pending_missing_target\""))
        #expect(events.contains("\"reason\":\"target_stage_members_missing_pending_focus\""))
        #expect(events.contains("\"stateChanged\":\"true\""))
        #expect(!events.contains("\"type\":\"stage_switch_blocked_empty_target\""))
        #expect(!events.contains("\"type\":\"stage_switch\""))
    }

    @Test
    func stageSwitchToRecentlyMissingTargetSwitchesAndRecallsApplication() {
        let display = DisplayID(rawValue: "display-main")
        let visible = powerWindow(1, x: 100)
        let missing = powerWindow(2, x: 300)
        let provider = PowerUserProvider(windows: [visible])
        provider.focusedID = visible.id
        let writer = PowerUserWriter(provider: provider)
        let eventPath = tempPath("power-stage-switch-pending-missing-target-events")
        let store = StageStore(path: tempPath("power-stage-switch-pending-missing-target"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: visible.id, members: [
                    PersistentStageMember(windowID: visible.id, bundleID: visible.bundleID, title: visible.title, frame: visible.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "2"), focusedWindowID: missing.id, members: [
                    PersistentStageMember(
                        windowID: missing.id,
                        bundleID: missing.bundleID,
                        title: missing.title,
                        frame: missing.frame,
                        lastSeenAt: Date(),
                        missingSince: Date()
                    ),
                ]),
            ]),
        ]))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)

        let result = StageCommandService(
            service: service,
            store: store,
            events: EventLog(path: eventPath)
        ).switchTo("2", displayID: display)

        // SPEC-016 T042 : même une absence très courte ne bloque plus la bascule.
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        #expect(result.changed)
        #expect(writer.frames[visible.id]?.x == 999)
        #expect(writer.activatedBundleIDs == [missing.bundleID])
        #expect(store.state().scopes.first?.activeStageID == StageID(rawValue: "2"))
        #expect(events.contains("\"type\":\"stage_switch_pending_missing_target\""))
        #expect(events.contains("\"reason\":\"target_stage_members_missing_pending_focus\""))
        #expect(!events.contains("\"type\":\"stage_switch_blocked_empty_target\""))
        #expect(!events.contains("\"type\":\"stage_switch\""))
    }

    @Test
    func stageSwitchToMissingNativeFullscreenTargetActivatesApplication() {
        let display = DisplayID(rawValue: "display-main")
        let visible = powerWindow(1, x: 100)
        var fullscreen = powerWindow(2, x: 0, y: 0, width: 1000, height: 800)
        fullscreen.bundleID = "org.mozilla.firefox"
        fullscreen.title = "Netflix"
        let provider = PowerUserProvider(windows: [visible])
        provider.focusedID = visible.id
        let writer = PowerUserWriter(provider: provider)
        let eventPath = tempPath("power-stage-switch-missing-native-fullscreen-events")
        let store = StageStore(path: tempPath("power-stage-switch-missing-native-fullscreen"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: visible.id, members: [
                    PersistentStageMember(windowID: visible.id, bundleID: visible.bundleID, title: visible.title, frame: visible.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "2"), focusedWindowID: fullscreen.id, members: [
                    PersistentStageMember(
                        windowID: fullscreen.id,
                        bundleID: fullscreen.bundleID,
                        title: fullscreen.title,
                        frame: fullscreen.frame,
                        presentationState: .nativeFullscreen,
                        lastSeenAt: Date(timeIntervalSinceNow: -10),
                        missingSince: Date(timeIntervalSinceNow: -10)
                    ),
                ]),
            ]),
        ]))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)

        let result = StageCommandService(
            service: service,
            store: store,
            events: EventLog(path: eventPath)
        ).switchTo("2", displayID: display)

        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        #expect(result.changed)
        #expect(writer.frames.isEmpty)
        #expect(writer.activatedBundleIDs == ["org.mozilla.firefox"])
        #expect(store.state().scopes.first?.activeStageID == StageID(rawValue: "2"))
        #expect(events.contains("\"type\":\"stage_switch_pending_missing_target\""))
        #expect(events.contains("\"nativeFullscreenActivation\":\"true\""))
        #expect(!events.contains("\"type\":\"stage_switch\""))
    }

    @Test
    func repeatedStageSwitchToAlreadyActiveMissingNativeFullscreenRetriesActivation() {
        let display = DisplayID(rawValue: "display-main")
        var fullscreen = powerWindow(2, x: 0, y: 0, width: 1000, height: 800)
        fullscreen.bundleID = "org.mozilla.firefox"
        fullscreen.title = "Netflix"
        let provider = PowerUserProvider(windows: [])
        provider.focusedID = nil
        let writer = PowerUserWriter(provider: provider)
        let eventPath = tempPath("power-stage-switch-noop-missing-native-fullscreen-events")
        let store = StageStore(path: tempPath("power-stage-switch-noop-missing-native-fullscreen"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "2"), stages: [
                PersistentStage(id: StageID(rawValue: "2"), focusedWindowID: fullscreen.id, members: [
                    PersistentStageMember(
                        windowID: fullscreen.id,
                        bundleID: fullscreen.bundleID,
                        title: fullscreen.title,
                        frame: fullscreen.frame,
                        presentationState: .nativeFullscreen,
                        lastSeenAt: Date(timeIntervalSinceNow: -10),
                        missingSince: Date(timeIntervalSinceNow: -10)
                    ),
                ]),
            ]),
        ]))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)

        let result = StageCommandService(
            service: service,
            store: store,
            events: EventLog(path: eventPath)
        ).switchTo("2", displayID: display)

        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        #expect(result.changed)
        #expect(writer.activatedBundleIDs == ["org.mozilla.firefox"])
        #expect(events.contains("\"type\":\"stage_switch_noop\""))
        #expect(events.contains("\"nativeFullscreenActivation\":\"true\""))
        #expect(!events.contains("\"type\":\"stage_switch_pending_missing_target\""))
        #expect(!events.contains("\"type\":\"stage_switch\""))
    }

    @Test
    func nativeFullscreenFocusActivatesApplicationWithoutSwitchingStage() {
        let display = DisplayID(rawValue: "display-main")
        var fullscreen = powerWindow(2, x: 0, y: 0, width: 1000, height: 800)
        fullscreen.bundleID = "org.mozilla.firefox"
        fullscreen.title = "Netflix"
        let provider = PowerUserProvider(windows: [])
        let writer = PowerUserWriter(provider: provider)
        let eventPath = tempPath("power-native-fullscreen-focus-events")
        let store = StageStore(path: tempPath("power-native-fullscreen-focus"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: []),
                PersistentStage(id: StageID(rawValue: "2"), focusedWindowID: fullscreen.id, members: [
                    PersistentStageMember(
                        windowID: fullscreen.id,
                        bundleID: fullscreen.bundleID,
                        title: fullscreen.title,
                        frame: fullscreen.frame,
                        presentationState: .nativeFullscreen,
                        missingSince: Date()
                    ),
                ]),
            ]),
        ]))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)

        let result = StageCommandService(
            service: service,
            store: store,
            events: EventLog(path: eventPath)
        ).focusNativeFullscreen(
            windowID: fullscreen.id,
            bundleID: fullscreen.bundleID,
            stageID: StageID(rawValue: "2"),
            displayID: display
        )

        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        #expect(result.changed)
        #expect(writer.activatedBundleIDs == ["org.mozilla.firefox"])
        #expect(store.state().scopes.first?.activeStageID == StageID(rawValue: "1"))
        #expect(events.contains("\"type\":\"stage_native_fullscreen_focus\""))
        #expect(events.contains("\"activatedApplication\":\"true\""))
        #expect(!events.contains("\"type\":\"stage_switch\""))
    }

    @Test
    func nativeFullscreenFocusPrefersExactApplicationWindowOverBundleActivation() {
        let display = DisplayID(rawValue: "display-main")
        var fullscreen = powerWindow(2, x: 0, y: 0, width: 1000, height: 800)
        fullscreen.bundleID = "org.mozilla.firefox"
        fullscreen.title = "Netflix"
        let provider = PowerUserProvider(windows: [])
        let writer = PowerUserWriter(provider: provider)
        writer.applicationWindowFocusResult = true
        let eventPath = tempPath("power-native-fullscreen-exact-focus-events")
        let store = StageStore(path: tempPath("power-native-fullscreen-exact-focus"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: []),
                PersistentStage(id: StageID(rawValue: "2"), focusedWindowID: fullscreen.id, members: [
                    PersistentStageMember(
                        windowID: fullscreen.id,
                        bundleID: fullscreen.bundleID,
                        title: fullscreen.title,
                        frame: fullscreen.frame,
                        presentationState: .nativeFullscreen,
                        missingSince: Date()
                    ),
                ]),
            ]),
        ]))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)

        let result = StageCommandService(
            service: service,
            store: store,
            events: EventLog(path: eventPath)
        ).focusNativeFullscreen(
            windowID: fullscreen.id,
            bundleID: fullscreen.bundleID,
            stageID: StageID(rawValue: "2"),
            displayID: display
        )

        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        #expect(result.changed)
        #expect(writer.focusedApplicationWindows == [fullscreen.id])
        #expect(writer.activatedBundleIDs == [])
        #expect(store.state().scopes.first?.activeStageID == StageID(rawValue: "1"))
        #expect(events.contains("\"focusedApplicationWindow\":\"true\""))
        #expect(events.contains("\"activatedApplication\":\"false\""))
        #expect(!events.contains("\"type\":\"stage_switch\""))
    }

    @Test
    func toggleFullscreenRecordsZoomedIntentWithAppliedFrames() {
        // SPEC-016 T040 : l'intent porte la fenêtre zoomée et les cadres réellement appliqués.
        let left = powerWindow(1, x: 0, y: 0, width: 495, height: 800)
        let right = powerWindow(2, x: 505, y: 0, width: 495, height: 800)
        let provider = PowerUserProvider(windows: [left, right])
        provider.focusedID = left.id
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("power-toggle-fullscreen-intent"))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)
        guard let scope = service.snapshot().windows.first(where: { $0.window.id == left.id })?.scope else {
            Issue.record("scope introuvable")
            return
        }
        let commands = WindowCommandService(service: service, stageStore: store)

        _ = commands.toggleFullscreen()
        let intent = service.effectiveIntentStore.intent(for: scope)

        #expect(intent?.source == .command)
        #expect(intent?.zoomedWindowID == left.id)
        #expect(intent?.placements[left.id] == Rect(x: 0, y: 0, width: 1000, height: 800))
        #expect(intent?.placements[right.id] == writer.frames[right.id])
        #expect(intent?.placements[right.id]?.x == 999)

        _ = commands.toggleFullscreen()
        #expect(service.effectiveIntentStore.intent(for: scope)?.zoomedWindowID == nil)
    }

    @Test
    func stageSwitchDoesNotTreatScreenSizedWindowAsFullscreenWithoutZoomIntent() {
        // SPEC-016 T041 : une fenêtre qui remplit la zone utile n'est pas un plein écran
        // sans marqueur de zoom ni plein écran natif ; ses voisines ne sont pas cachées.
        let display = powerDisplay()
        let displayID = display.id
        let current = powerWindow(1, x: 100, y: 100, width: 500, height: 400)
        let big = powerWindow(2, x: 999, y: 799, width: 1000, height: 800)
        let sibling = powerWindow(3, x: 999, y: 799, width: 300, height: 300)
        let provider = PowerUserProvider(displays: [display], windows: [current, big, sibling])
        provider.focusedID = current.id
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("power-stage-switch-no-size-fullscreen"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: displayID, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: current.id, members: [
                    PersistentStageMember(windowID: current.id, bundleID: current.bundleID, title: current.title, frame: current.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "2"), focusedWindowID: big.id, members: [
                    PersistentStageMember(windowID: big.id, bundleID: big.bundleID, title: big.title, frame: Rect(x: 0, y: 0, width: 1000, height: 800)),
                    PersistentStageMember(windowID: sibling.id, bundleID: sibling.bundleID, title: sibling.title, frame: Rect(x: 100, y: 100, width: 300, height: 300)),
                ]),
            ]),
        ], activeDisplayID: displayID))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)
        let eventPath = tempPath("power-stage-switch-no-size-fullscreen-events")

        _ = StageCommandService(service: service, store: store, events: EventLog(path: eventPath))
            .switchTo("2", displayID: displayID)

        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        #expect(events.contains("\"fullscreenProtected\":\"false\""))
        // Plan unique (T212) : la voisine est posée une fois, à l'écran (pas cachée), sans passer par
        // sa frame mémorisée.
        let siblingWrites = writer.frameHistory[sibling.id] ?? []
        #expect(siblingWrites.count == 1)
        #expect(siblingWrites.allSatisfy { display.visibleFrame.cgRect.contains(CGPoint(x: $0.cgRect.midX, y: $0.cgRect.midY)) })
    }

    @Test
    func stageSwitchPreservesMaximizedWindowAndKeepsSiblingsHidden() {
        let display = powerDisplay()
        let displayID = display.id
        let maximizedFrame = Rect(x: 0, y: 0, width: 1000, height: 800)
        let maximized = powerWindow(1, x: 0, y: 0, width: 495, height: 800)
        let sibling = powerWindow(2, x: 505, y: 0, width: 495, height: 800)
        let otherHidden = powerWindow(3, x: 999, y: 799, width: 300, height: 300)
        let provider = PowerUserProvider(displays: [display], windows: [maximized, sibling, otherHidden])
        provider.focusedID = maximized.id
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("power-stage-switch-preserves-maximized"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: displayID, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), mode: .mutableBsp, focusedWindowID: maximized.id, members: [
                    PersistentStageMember(windowID: maximized.id, bundleID: maximized.bundleID, title: maximized.title, frame: maximized.frame),
                    PersistentStageMember(windowID: sibling.id, bundleID: sibling.bundleID, title: sibling.title, frame: sibling.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "2"), mode: .mutableBsp, focusedWindowID: otherHidden.id, members: [
                    PersistentStageMember(windowID: otherHidden.id, bundleID: otherHidden.bundleID, title: otherHidden.title, frame: Rect(x: 100, y: 100, width: 300, height: 300)),
                ]),
            ]),
        ], activeDisplayID: displayID))
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .mutableBsp, gapsOuter: 0, gapsInner: 10)),
            stageStore: store
        )
        let eventPath = tempPath("power-stage-switch-preserves-maximized-events")
        let commands = StageCommandService(service: service, store: store, events: EventLog(path: eventPath))

        _ = WindowCommandService(service: service, stageStore: store).toggleFullscreen()
        #expect(store.state().scopes.first?.stages.first(where: { $0.id == StageID(rawValue: "1") })?.members.first(where: { $0.windowID == maximized.id })?.frame == maximizedFrame)
        _ = commands.switchTo("2", displayID: displayID)
        #expect(store.state().scopes.first?.stages.first(where: { $0.id == StageID(rawValue: "1") })?.members.first(where: { $0.windowID == maximized.id })?.frame == maximizedFrame)
        _ = commands.switchTo("1", displayID: displayID)

        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        #expect(events.contains("\"fullscreenProtected\":\"true\""))
        #expect(writer.frameHistory[maximized.id]?.last == maximizedFrame)
        #expect(writer.frameHistory[sibling.id]?.last?.x == 999)
        #expect(writer.frameHistory[sibling.id]?.last?.width == sibling.frame.width)
    }

    @Test
    func stageSwitchIgnoresMissingMaximizedMemberWhenRestoringLiveStageMembers() {
        let display = powerDisplay()
        let displayID = display.id
        let current = powerWindow(1, x: 100, y: 100, width: 500, height: 400)
        let first = powerWindow(2, x: 999, y: 799, width: 300, height: 300)
        let second = powerWindow(3, x: 999, y: 799, width: 300, height: 300)
        let staleMaximized = powerWindow(4, x: 0, y: 0, width: 1000, height: 800)
        let firstTarget = Rect(x: 0, y: 0, width: 495, height: 800)
        let secondTarget = Rect(x: 505, y: 0, width: 495, height: 800)
        let provider = PowerUserProvider(displays: [display], windows: [current, first, second])
        provider.focusedID = current.id
        let writer = PowerUserWriter(provider: provider)
        let eventPath = tempPath("power-stage-switch-ignores-missing-maximized-events")
        let store = StageStore(path: tempPath("power-stage-switch-ignores-missing-maximized"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: displayID, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), mode: .bsp, focusedWindowID: current.id, members: [
                    PersistentStageMember(windowID: current.id, bundleID: current.bundleID, title: current.title, frame: current.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "2"), mode: .bsp, focusedWindowID: first.id, members: [
                    PersistentStageMember(windowID: first.id, bundleID: first.bundleID, title: first.title, frame: firstTarget),
                    PersistentStageMember(windowID: second.id, bundleID: second.bundleID, title: second.title, frame: secondTarget),
                    PersistentStageMember(
                        windowID: staleMaximized.id,
                        bundleID: staleMaximized.bundleID,
                        title: staleMaximized.title,
                        frame: staleMaximized.frame,
                        presentationState: .maximized,
                        lastSeenAt: Date(timeIntervalSinceNow: -30),
                        missingSince: Date(timeIntervalSinceNow: -30)
                    ),
                ]),
            ]),
        ], activeDisplayID: displayID))
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .bsp, gapsOuter: 0, gapsInner: 10)),
            stageStore: store
        )

        let result = StageCommandService(
            service: service,
            store: store,
            events: EventLog(path: eventPath)
        ).switchTo("2", displayID: displayID)

        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        #expect(result.changed)
        #expect(writer.frameHistory[first.id]?.first == firstTarget)
        #expect(writer.frameHistory[second.id]?.first == secondTarget)
        #expect(writer.frameHistory[first.id]?.first?.x != 999)
        #expect(writer.frameHistory[second.id]?.first?.x != 999)
        #expect(events.contains("\"type\":\"stage_switch\""))
        #expect(events.contains("\"fullscreenProtected\":\"false\""))
    }

    @Test
    func placingWindowOnAnotherDisplayRelayoutsVisibleSourceStageImmediately() {
        let sourceDisplay = powerDisplay("display-main", index: 1, x: 0)
        let targetDisplay = powerDisplay("display-side", index: 2, x: 1000)
        let remaining = powerWindow(1, x: 0, y: 0, width: 495, height: 800)
        let moved = powerWindow(2, x: 505, y: 0, width: 495, height: 800)
        let target = powerWindow(3, x: 1000, y: 0, width: 1000, height: 800)
        let provider = PowerUserProvider(displays: [sourceDisplay, targetDisplay], windows: [remaining, moved, target])
        provider.focusedID = moved.id
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("power-stage-place-relayout-source"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: sourceDisplay.id, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), mode: .bsp, members: [
                        PersistentStageMember(windowID: remaining.id, bundleID: remaining.bundleID, title: remaining.title, frame: remaining.frame),
                        PersistentStageMember(windowID: moved.id, bundleID: moved.bundleID, title: moved.title, frame: moved.frame),
                    ])
                ]),
                PersistentStageScope(displayID: targetDisplay.id, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), mode: .bsp, members: [
                        PersistentStageMember(windowID: target.id, bundleID: target.bundleID, title: target.title, frame: target.frame),
                    ])
                ])
            ],
            activeDisplayID: targetDisplay.id
        ))
        let eventPath = tempPath("power-stage-place-relayout-source-events")
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(),
            stageStore: store
        )

        let result = StageCommandService(
            service: service,
            store: store,
            events: EventLog(path: eventPath)
        ).place(
            windowID: moved.id,
            displayID: targetDisplay.id,
            orderedWindowIDs: [target.id, moved.id]
        )

        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        #expect(result.changed)
        #expect(writer.frames[remaining.id] == Rect(x: 8, y: 8, width: 984, height: 784))
        #expect(events.contains("\"sourceCommands\":\"1\""))
        #expect(events.contains("\"sourceApplied\":\"1\""))
    }

    // MARK: - Mode arbre (SPEC-017 T093, T094, T095)
    //
    // Les bascules posent les frames finales de l'arbre dans un seul plan (T212) : exactement une
    // écriture par fenêtre, jamais la frame mémorisée du membre, et pas d'attente de commande.

    @Test
    func treeStageSwitchPlacesFinalTreeFramesWithoutRestoringMemorizedFrames() {
        let displayID = DisplayID(rawValue: "display-main")
        let current = powerWindow(1, x: 0, y: 0, width: 1000, height: 800)
        let first = powerWindow(2, x: 999, y: 799, width: 300, height: 300)
        let second = powerWindow(3, x: 999, y: 799, width: 300, height: 300)
        let memorized = Rect(x: 100, y: 100, width: 300, height: 300)
        let provider = PowerUserProvider(windows: [current, first, second])
        provider.focusedID = current.id
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("tree-stage-switch"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: displayID, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), mode: .spatialBsp, focusedWindowID: current.id,
                                members: [treeMember(current)], bspTree: .leaf(current.id)),
                PersistentStage(id: StageID(rawValue: "2"), mode: .spatialBsp, focusedWindowID: first.id, members: [
                    PersistentStageMember(windowID: first.id, bundleID: first.bundleID, title: first.title, frame: memorized),
                    PersistentStageMember(windowID: second.id, bundleID: second.bundleID, title: second.title, frame: memorized),
                ], bspTree: .split(orientation: .vertical, ratio: 0.5, first: .leaf(first.id), second: .leaf(second.id))),
            ]),
        ], activeDisplayID: displayID))
        let service = treeService(provider: provider, writer: writer, store: store, name: "tree-stage-switch")
        let eventPath = tempPath("tree-stage-switch-events")
        let activity = LayoutCommandActivity(path: tempPath("tree-stage-switch-activity"), enabled: true)

        let result = StageCommandService(service: service, store: store, events: EventLog(path: eventPath), commandActivity: activity)
            .switchTo("2", displayID: displayID)

        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        #expect(result.changed)
        #expect(store.state().scopes.first?.activeStageID == StageID(rawValue: "2"))
        #expect(events.contains("\"strategy\":\"tree\""))
        #expect(!activity.isActive())
        expectFinalTreeFrames(writer, [first.id: Rect(x: 0, y: 0, width: 500, height: 800), second.id: Rect(x: 500, y: 0, width: 500, height: 800)])
    }

    @Test
    func treeDesktopSwitchPlacesFinalTreeFramesWithoutRestoringMemorizedFrames() {
        let displayID = DisplayID(rawValue: "display-main")
        let current = powerWindow(1, x: 0, y: 0, width: 1000, height: 800)
        let target = powerWindow(2, x: 999, y: 100, width: 300, height: 300)
        let memorized = Rect(x: 400, y: 100, width: 300, height: 300)
        let provider = PowerUserProvider(windows: [current, target])
        provider.focusedID = current.id
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("tree-desktop-switch"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: displayID, desktopID: DesktopID(rawValue: 1), stages: [
                PersistentStage(id: StageID(rawValue: "1"), mode: .spatialBsp, members: [treeMember(current)], bspTree: .leaf(current.id)),
            ]),
            PersistentStageScope(displayID: displayID, desktopID: DesktopID(rawValue: 2), stages: [
                PersistentStage(id: StageID(rawValue: "1"), mode: .spatialBsp, focusedWindowID: target.id, members: [
                    PersistentStageMember(windowID: target.id, bundleID: target.bundleID, title: target.title, frame: memorized),
                ], bspTree: .leaf(target.id)),
            ]),
        ], activeDisplayID: displayID))
        let service = treeService(provider: provider, writer: writer, store: store, name: "tree-desktop-switch")
        let activity = LayoutCommandActivity(path: tempPath("tree-desktop-switch-activity"), enabled: true)

        let result = DesktopCommandService(service: service, store: store, events: EventLog(path: tempPath("tree-desktop-switch-events")), commandActivity: activity)
            .focus(DesktopID(rawValue: 2))

        #expect(result.changed)
        #expect(store.state().currentDesktopID(for: displayID) == DesktopID(rawValue: 2))
        #expect(!activity.isActive())
        expectFinalTreeFrames(writer, [target.id: Rect(x: 0, y: 0, width: 1000, height: 800)])
    }

    @Test
    func treePlaceOnAnotherDisplayMovesLeafAtRequestedRank() {
        let sourceDisplay = powerDisplay("display-main", index: 1, x: 0)
        let targetDisplay = powerDisplay("display-side", index: 2, x: 1000)
        let remaining = powerWindow(1, x: 0, y: 0, width: 500, height: 800)
        let moved = powerWindow(2, x: 500, y: 0, width: 500, height: 800)
        let target = powerWindow(3, x: 1000, y: 0, width: 1000, height: 800)
        let provider = PowerUserProvider(displays: [sourceDisplay, targetDisplay], windows: [remaining, moved, target])
        provider.focusedID = moved.id
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("tree-place-rank"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: sourceDisplay.id, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), mode: .spatialBsp, members: [remaining, moved].map(treeMember),
                                    bspTree: .split(orientation: .vertical, ratio: 0.5, first: .leaf(remaining.id), second: .leaf(moved.id))),
                ]),
                PersistentStageScope(displayID: targetDisplay.id, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), mode: .spatialBsp, members: [treeMember(target)], bspTree: .leaf(target.id)),
                ]),
            ],
            activeDisplayID: targetDisplay.id
        ))
        let service = treeService(provider: provider, writer: writer, store: store, name: "tree-place-rank")
        let sourceScope = StageScope(displayID: sourceDisplay.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let targetScope = StageScope(displayID: targetDisplay.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))

        // Rang 0 : devant la fenêtre cible ; feuille large, donc coupée en colonnes.
        let result = StageCommandService(service: service, store: store, events: EventLog(path: tempPath("tree-place-rank-events")))
            .place(windowID: moved.id, displayID: targetDisplay.id, orderedWindowIDs: [moved.id, target.id])

        #expect(result.changed)
        #expect(store.state().bspTree(for: sourceScope) == .leaf(remaining.id))
        #expect(store.state().bspTree(for: targetScope) == .split(orientation: .vertical, ratio: 0.5, first: .leaf(moved.id), second: .leaf(target.id)))
        expectFinalTreeFrames(writer, [
            remaining.id: Rect(x: 0, y: 0, width: 1000, height: 800),
            moved.id: Rect(x: 1000, y: 0, width: 500, height: 800),
            target.id: Rect(x: 1500, y: 0, width: 500, height: 800),
        ])
    }

    @Test
    func railDropAtIndexInsertsIntoHiddenTreeStage() {
        let displayID = DisplayID(rawValue: "display-main")
        let dragged = powerWindow(1, x: 0, y: 0, width: 1000, height: 800)
        let first = powerWindow(2, x: 999, y: 799, width: 300, height: 300)
        let second = powerWindow(3, x: 999, y: 799, width: 300, height: 300)
        let provider = PowerUserProvider(windows: [dragged, first, second])
        provider.focusedID = dragged.id
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("tree-rail-drop-index"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: displayID, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), mode: .spatialBsp, members: [treeMember(dragged)], bspTree: .leaf(dragged.id)),
                PersistentStage(id: StageID(rawValue: "2"), mode: .spatialBsp, members: [first, second].map(treeMember),
                                bspTree: .split(orientation: .vertical, ratio: 0.5, first: .leaf(first.id), second: .leaf(second.id))),
            ]),
        ], activeDisplayID: displayID))
        let service = treeService(provider: provider, writer: writer, store: store, name: "tree-rail-drop-index")
        let sourceScope = StageScope(displayID: displayID, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let targetScope = StageScope(displayID: displayID, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "2"))

        // Index 1 : entre 2 et 3, donc devant 3 dans l'arbre (feuille haute de 3 coupée en rangées).
        let result = StageCommandService(service: service, store: store, events: EventLog(path: tempPath("tree-rail-drop-index-events")))
            .assign(windowID: dragged.id, to: "2", displayID: displayID, insertionIndex: 1, focusAssignedWindow: false)

        #expect(result.changed)
        #expect(store.state().bspTree(for: sourceScope)?.contains(dragged.id) != true)
        #expect(store.state().bspTree(for: targetScope) == .split(
            orientation: .vertical, ratio: 0.5, first: .leaf(first.id),
            second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(dragged.id), second: .leaf(second.id))
        ))
    }

    @Test
    func stageSwitchIgnoresStaleFocusFromHiddenPreviousStage() {
        let display = DisplayID(rawValue: "display-main")
        let visible = powerWindow(1, x: 100)
        var hidden = powerWindow(2, x: 999)
        hidden.frame = Rect(x: 999, y: 499, width: 400, height: 300)
        let provider = PowerUserProvider(windows: [visible, hidden])
        provider.focusedID = visible.id
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("power-stage-switch-stale-focus"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), focusedWindowID: visible.id, members: [
                    PersistentStageMember(windowID: visible.id, bundleID: visible.bundleID, title: visible.title, frame: visible.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "2"), focusedWindowID: hidden.id, members: [
                    PersistentStageMember(windowID: hidden.id, bundleID: hidden.bundleID, title: hidden.title, frame: Rect(x: 250, y: 50, width: 500, height: 350)),
                ]),
            ]),
        ]))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)

        let result = StageCommandService(service: service, store: store).switchToPosition(2)
        provider.focusedID = visible.id
        let staleFocusSnapshot = service.snapshot()
        var state = store.state()

        #expect(result.changed)
        #expect(state.scope(displayID: display).activeStageID == StageID(rawValue: "2"))
        #expect(staleFocusSnapshot.state.activeScope(on: display)?.stageID == StageID(rawValue: "2"))
        #expect(writer.focused.last == hidden.id)
    }

    @Test
    func stageAssignPositionUsesVisibleRailOrder() {
        let display = DisplayID(rawValue: "display-main")
        let left = powerWindow(1, x: 100)
        let right = powerWindow(2, x: 1200)
        let provider = PowerUserProvider(windows: [left, right])
        provider.focusedID = left.id
        let store = StageStore(path: tempPath("power-stage-assign-position"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [
                    PersistentStageMember(windowID: left.id, bundleID: left.bundleID, title: left.title, frame: left.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "2")),
                PersistentStage(id: StageID(rawValue: "7"), members: [
                    PersistentStageMember(windowID: right.id, bundleID: right.bundleID, title: right.title, frame: Rect(x: 350, y: 100, width: 300, height: 300)),
                ]),
            ]),
        ]))
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)

        let result = StageCommandService(service: service, store: store).assignPosition(2)
        var state = store.state()
        let scope = state.scope(displayID: display)

        #expect(result.changed)
        #expect(scope.memberIDs(in: StageID(rawValue: "1")).isEmpty)
        #expect(scope.memberIDs(in: StageID(rawValue: "7")).contains(left.id))
    }

    @Test
    func stageAssignPositionCanTargetHiddenEmptyStageSlots() {
        let display = DisplayID(rawValue: "display-main")
        let window = powerWindow(1, x: 100)
        let provider = PowerUserProvider(windows: [window])
        provider.focusedID = window.id
        let store = StageStore(path: tempPath("power-stage-assign-hidden-empty-position"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [
                    PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "2")),
                PersistentStage(id: StageID(rawValue: "3")),
            ]),
        ]))
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)

        let result = StageCommandService(service: service, store: store).assignPosition(2)
        var state = store.state()
        let scope = state.scope(displayID: display)

        #expect(result.changed)
        #expect(scope.memberIDs(in: StageID(rawValue: "1")).isEmpty)
        #expect(scope.memberIDs(in: StageID(rawValue: "2")).contains(window.id))
    }

    @Test
    func stageAssignEmptySkipsNamedEmptyStagesAndCreatesNextStage() {
        let display = DisplayID(rawValue: "display-main")
        let window = powerWindow(1, x: 100)
        let occupied = powerWindow(2, x: 600)
        let provider = PowerUserProvider(windows: [window, occupied])
        provider.focusedID = window.id
        let store = StageStore(path: tempPath("power-stage-assign-empty"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), members: [
                    PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
                ]),
                PersistentStage(id: StageID(rawValue: "2"), name: "Perso"),
                PersistentStage(id: StageID(rawValue: "3")),
                PersistentStage(id: StageID(rawValue: "4"), members: [
                    PersistentStageMember(windowID: occupied.id, bundleID: occupied.bundleID, title: occupied.title, frame: occupied.frame),
                ]),
            ]),
        ]))
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)

        let result = StageCommandService(service: service, store: store).assignEmpty()
        var state = store.state()
        let scope = state.scope(displayID: display)

        #expect(result.changed)
        #expect(scope.memberIDs(in: StageID(rawValue: "1")).isEmpty)
        #expect(scope.memberIDs(in: StageID(rawValue: "2")).isEmpty)
        #expect(scope.memberIDs(in: StageID(rawValue: "3")).isEmpty)
        #expect(scope.memberIDs(in: StageID(rawValue: "5")).contains(window.id))
    }

    @Test
    func desktopAssignRemovesInstancePin() {
        let display = DisplayID(rawValue: "display-main")
        let window = powerWindow(1, x: 100)
        let provider = PowerUserProvider(windows: [window])
        let store = StageStore(path: tempPath("power-desktop-pinned-assign"))
        let home = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), members: [PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame)])
                ]),
                PersistentStageScope(displayID: display, desktopID: DesktopID(rawValue: 2), activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"))
                ])
            ],
            windowPins: [
                PersistentWindowPin(windowID: window.id, homeScope: home, pinScope: .allDesktops, bundleID: window.bundleID, title: window.title, lastFrame: window.frame)
            ],
            activeDisplayID: display
        ))
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)

        let result = DesktopCommandService(service: service, store: store).assign(windowID: window.id, to: DesktopID(rawValue: 2), displayID: display)

        #expect(result.changed)
        #expect(store.state().pin(for: window.id) == nil)
        #expect(store.state().stageScope(for: window.id)?.desktopID == DesktopID(rawValue: 2))
    }

    @Test
    func displaySendRemovesInstancePin() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let side = powerDisplay("display-side", index: 2, x: 1000)
        let window = powerWindow(1, x: 100)
        let home = StageScope(displayID: main.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let provider = PowerUserProvider(displays: [main, side], windows: [window])
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("power-display-pinned-send"))
        store.save(PersistentStageState(
            scopes: [
                PersistentStageScope(displayID: main.id, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"), members: [
                        PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame)
                    ])
                ]),
                PersistentStageScope(displayID: side.id, activeStageID: StageID(rawValue: "1"), stages: [
                    PersistentStage(id: StageID(rawValue: "1"))
                ])
            ],
            windowPins: [
                PersistentWindowPin(windowID: window.id, homeScope: home, pinScope: .allDesktops, bundleID: window.bundleID, title: window.title, lastFrame: window.frame)
            ],
            activeDisplayID: main.id
        ))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)

        let result = WindowCommandService(service: service, stageStore: store).send(windowID: window.id, toDisplayID: side.id, focusMovedWindow: false)

        #expect(result.changed)
        #expect(store.state().pin(for: window.id) == nil)
        #expect(store.state().stageScope(for: window.id)?.displayID == side.id)
    }
}

private final class StageSwitchOrderWriter: WindowFrameWriting, @unchecked Sendable {
    let provider: PowerUserProvider
    let store: StageStore
    let observedWindowID: WindowID
    private(set) var activeStagesObservedForTargetFrame: [StageID] = []

    init(provider: PowerUserProvider, store: StageStore, observedWindowID: WindowID) {
        self.provider = provider
        self.store = store
        self.observedWindowID = observedWindowID
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        if window.id == observedWindowID {
            let activeStageID = store.state().scopes
                .first { $0.displayID == DisplayID(rawValue: "display-main") }?
                .activeStageID
            if let activeStageID {
                activeStagesObservedForTargetFrame.append(activeStageID)
            }
        }
        let rect = Rect(frame)
        provider.snapshots = provider.snapshots.map {
            guard $0.id == window.id else { return $0 }
            var updated = $0
            updated.frame = rect
            return updated
        }
        return frame
    }

    func focus(_ window: WindowSnapshot) -> Bool {
        provider.focusedID = window.id
        return true
    }

    func reset(_ window: WindowSnapshot) -> Bool { true }
    func toggleZoom(_ window: WindowSnapshot) -> Bool { true }
    func toggleNativeFullscreen(_ window: WindowSnapshot) -> Bool { true }
}

/// SPEC-016 T207 : l'état est relu et modifié dans la transaction, avant les appels AX ; une
/// modification concurrente faite pendant l'AX n'est pas écrasée par une copie périmée.
@Suite
struct CommandStateTransactionTests {
    private let display = DisplayID(rawValue: "display-main")
    private let stage1 = StageID(rawValue: "1")

    private func renameStage(_ store: StageStore, desktop: Int, to name: String) {
        store.mutate { state in
            var scope = state.scope(displayID: display, desktopID: DesktopID(rawValue: desktop))
            guard let index = scope.stages.firstIndex(where: { $0.id == stage1 }) else { return }
            scope.stages[index].name = name
            state.update(scope)
        }
    }

    private func stageName(_ store: StageStore, desktop: Int) -> String? {
        store.state().scopes
            .first { $0.displayID == display && $0.desktopID == DesktopID(rawValue: desktop) }?
            .stages.first { $0.id == stage1 }?.name
    }

    @Test
    func desktopSwitchKeepsConcurrentChangeMadeDuringAX() {
        let first = powerWindow(1, x: 100)
        var second = powerWindow(2, x: 999)
        second.frame = Rect(x: 999, y: 100, width: 300, height: 300)
        let provider = PowerUserProvider(windows: [first, second])
        let writer = ScriptedFrameWriter(provider: provider)
        let store = StageStore(path: tempPath("transaction-desktop"))
        defer { try? FileManager.default.removeItem(at: store.fileURL) }
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stages: [
                PersistentStage(id: stage1, members: [
                    PersistentStageMember(windowID: first.id, bundleID: first.bundleID, title: first.title, frame: first.frame),
                ]),
            ]),
            PersistentStageScope(displayID: display, desktopID: DesktopID(rawValue: 2), stages: [
                PersistentStage(id: stage1, members: [
                    PersistentStageMember(windowID: second.id, bundleID: second.bundleID, title: second.title, frame: Rect(x: 400, y: 100, width: 300, height: 300)),
                ]),
            ]),
        ], activeDisplayID: display))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)
        var fired = false
        writer.beforeSetFrame = { _ in
            guard !fired else { return }
            fired = true
            renameStage(store, desktop: 1, to: "renamed-during-ax")
        }

        let result = DesktopCommandService(service: service, store: store).focus(DesktopID(rawValue: 2))

        #expect(result.changed)
        #expect(fired)
        #expect(store.state().currentDesktopID(for: display) == DesktopID(rawValue: 2))
        #expect(stageName(store, desktop: 1) == "renamed-during-ax")
    }

    @Test
    func bookmarkFocusKeepsConcurrentChangeMadeDuringAX() {
        let first = powerWindow(1, x: 100)
        var second = powerWindow(2, x: 999)
        second.frame = Rect(x: 999, y: 100, width: 300, height: 300)
        let provider = PowerUserProvider(windows: [first, second])
        let writer = ScriptedFrameWriter(provider: provider)
        let store = StageStore(path: tempPath("transaction-bookmark"))
        defer { try? FileManager.default.removeItem(at: store.fileURL) }
        let stage2 = StageID(rawValue: "2")
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, activeStageID: stage1, stages: [
                PersistentStage(id: stage1, members: [
                    PersistentStageMember(windowID: first.id, bundleID: first.bundleID, title: first.title, frame: first.frame),
                ]),
                PersistentStage(id: stage2, members: [
                    PersistentStageMember(windowID: second.id, bundleID: second.bundleID, title: second.title, frame: Rect(x: 400, y: 100, width: 300, height: 300)),
                ]),
            ]),
        ], windowBookmarks: [
            PersistentWindowBookmark(
                name: "work",
                windowID: second.id,
                scope: StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: stage2),
                bundleID: second.bundleID,
                title: second.title,
                frame: second.frame
            ),
        ], activeDisplayID: display))
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)
        var fired = false
        writer.beforeSetFrame = { _ in
            guard !fired else { return }
            fired = true
            renameStage(store, desktop: 1, to: "renamed-during-ax")
        }

        let result = WindowBookmarkCommandService(service: service, store: store).focus("work")

        #expect(result.changed)
        #expect(fired)
        #expect(store.state().scopes.first { $0.displayID == display }?.activeStageID == stage2)
        #expect(stageName(store, desktop: 1) == "renamed-during-ax")
    }
}

private func treeService(provider: PowerUserProvider, writer: PowerUserWriter, store: StageStore, name: String) -> SnapshotService {
    SnapshotService(
        provider: provider,
        frameWriter: writer,
        config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .spatialBsp, gapsOuter: 0, gapsInner: 0)),
        intentStore: LayoutIntentStore(path: tempPath("\(name)-intents")),
        stageStore: store,
        events: EventLog(path: tempPath("\(name)-service-events"))
    )
}

/// Une seule application (FR-012, T204) : exactement une écriture par fenêtre attendue, à sa frame
/// d'arbre (donc jamais une frame mémorisée restaurée avant recalcul), et aucune autre fenêtre
/// écrite plus d'une fois. Échoue si rien n'est écrit.
private func expectFinalTreeFrames(
    _ writer: PowerUserWriter,
    _ expected: [WindowID: Rect],
    sourceLocation: SourceLocation = #_sourceLocation
) {
    for (id, frame) in expected {
        #expect(writer.frameHistory[id] == [frame], "fenêtre \(id.rawValue)", sourceLocation: sourceLocation)
    }
    for (id, history) in writer.frameHistory {
        #expect(history.count <= 1, "fenêtre \(id.rawValue) : \(history)", sourceLocation: sourceLocation)
    }
}


@Suite
struct NavrailMaximizationTests {
    @Test(arguments: [WindowManagementMode.spatialBsp, .mutableBsp, .bsp, .masterStack, .float])
    func reservedZoomRestoresLayoutAndSurvivesModeChanges(mode: WindowManagementMode) throws {
        let windows = [powerWindow(201, x: 150, y: 0, width: 300, height: 800),
                       powerWindow(202, x: 460, y: 0, width: 540, height: 800)]
        let provider = PowerUserProvider(windows: windows)
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("spec019-layout"))
        let service = SnapshotService(provider: provider, frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: mode, gapsOuter: 0, gapsOuterLeft: 150, gapsInner: 10)),
            railSettings: RailSettings.load(raw: ""), stageStore: store)
        let before = service.snapshot()
        _ = service.apply(service.applyPlan(from: before))
        if mode.usesTreeEngine {
            _ = WindowCommandService(service: service, stageStore: store).resize(.right)
        } else if mode.isTiled {
            provider.snapshots[0].frame = Rect(x: 150, y: 0, width: 250, height: 800)
            provider.snapshots[1].frame = Rect(x: 410, y: 0, width: 590, height: 800)
        }
        let initial = service.snapshot()
        let scope = try #require(initial.windows.first(where: { $0.window.id == windows[0].id })?.scope)
        let original = Dictionary(uniqueKeysWithValues: provider.snapshots.map { ($0.id, $0.frame) })
        if !mode.usesTreeEngine && mode.isTiled {
            service.effectiveIntentStore.save(LayoutIntent(scope: scope, windowIDs: windows.reversed().map(\.id), placements: original, source: .command))
        }
        let commands = WindowCommandService(service: service, stageStore: store)
        #expect(commands.toggleMaximize().changed)
        #expect(writer.frames[windows[0].id] == Rect(x: 150, y: 0, width: 850, height: 800))
        let saved = try #require(service.effectiveIntentStore.intent(for: scope))
        #expect(saved.zoomReservesRail == true)
        #expect(saved.restorePlacements == original)
        let savedOrder = saved.windowIDs
        #expect(commands.toggleFullscreen().changed)
        #expect(service.effectiveIntentStore.intent(for: scope)?.windowIDs == savedOrder)
        #expect(writer.frames[windows[0].id] == Rect(x: 0, y: 0, width: 1000, height: 800))
        #expect(service.effectiveIntentStore.intent(for: scope)?.restorePlacements == original)
        #expect(commands.toggleMaximize().changed)
        #expect(writer.frames[windows[0].id]?.x == 150)
        #expect(commands.toggleMaximize().changed)
        #expect(service.effectiveIntentStore.intent(for: scope)?.zoomedWindowID == nil)
        for window in provider.snapshots {
            #expect(window.frame == original[window.id], "Restaurer \(mode) : \(window.id)")
        }
    }

    @Test
    func displayMarginsAndChangedVisibleAreaBoundTheMaximizedFrame() {
        let display = DisplaySnapshot(id: DisplayID(rawValue: "upper-left"), index: 2, name: "Upper Left",
            frame: Rect(x: -1920, y: -200, width: 1920, height: 1080),
            visibleFrame: Rect(x: -1920, y: -178, width: 1920, height: 1056), isMain: false)
        let config = RoadieConfig(tiling: TilingConfig(gapsOuter: 8, gapsOuterLeft: 150,
            displayOverrides: [DisplayTilingOverride(displayName: display.name, gapsOuterLeft: 220)],
            smartGapsSolo: true, smartGapsSoloSides: [.top, .right]))
        let service = SnapshotService(provider: PowerUserProvider(displays: [display], windows: []),
            config: config, railSettings: .load(raw: ""), stageStore: StageStore(path: tempPath("spec019-display-gap")))
        #expect(service.maximizedFrame(on: display) == CGRect(x: -1700, y: -178, width: 1700, height: 1048))
        var smaller = display
        smaller.visibleFrame = Rect(x: -1600, y: 40, width: 1600, height: 900)
        #expect(service.maximizedFrame(on: smaller) == CGRect(x: -1380, y: 40, width: 1380, height: 892))
    }

    @Test(arguments: ["resize", "overlay"])
    func hiddenRailAndSmartGapsKeepFullReservation(layoutMode: String) throws {
        let window = powerWindow(211, x: -950, y: 0, width: 300, height: 800)
        let display = powerDisplay("left-screen", index: 1, x: -1000)
        let provider = PowerUserProvider(displays: [display], windows: [window])
        let runtime = RailRuntimeStateStore(path: tempPath("spec019-rail"))
        runtime.setVisibleWidth(8, for: display.id)
        var rail = RailSettings.load(raw: "")
        rail.autoHide = true
        rail.layoutMode = layoutMode
        rail.dynamicLeftGap = true
        rail.width = 180
        rail.hideOnMaximized = true
        let store = StageStore(path: tempPath("spec019-autohide"))
        let writer = PowerUserWriter(provider: provider)
        let service = SnapshotService(provider: provider, frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsOuterLeft: 150, smartGapsSolo: true)),
            railSettings: rail, railRuntimeStateStore: runtime, stageStore: store)
        let commands = WindowCommandService(service: service, stageStore: store)
        #expect(commands.toggleMaximize().changed)
        #expect(writer.frames[window.id] == Rect(x: -820, y: 0, width: 820, height: 800))
        _ = runtime.setPinned(true)
        runtime.setVisibleWidth(180, for: display.id)
        let snapshot = service.snapshot()
        #expect(service.maximizedFrame(on: display) == CGRect(x: -820, y: 0, width: 820, height: 800))
        #expect(RailController.railHiddenDisplayIDs(in: snapshot, hideOnMaximized: true).isEmpty)
        #expect(commands.toggleMaximize().changed)
        #expect(service.effectiveIntentStore.intent(for: try #require(snapshot.windows.first?.scope))?.zoomedWindowID == nil)
    }

    @Test
    func reservedZoomReflowsAfterRestartAndWiderRail() throws {
        let windows = [powerWindow(221, x: 150), powerWindow(222, x: 550)]
        let provider = PowerUserProvider(windows: windows)
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("spec019-restart"))
        let intents = LayoutIntentStore(path: tempPath("spec019-intents"))
        let config = RoadieConfig(tiling: TilingConfig(defaultStrategy: .spatialBsp, gapsOuter: 0, gapsOuterLeft: 150))
        let service = SnapshotService(provider: provider, frameWriter: writer, config: config, railSettings: .load(raw: ""), intentStore: intents, stageStore: store)
        #expect(WindowCommandService(service: service, stageStore: store).toggleMaximize().changed)
        var rail = RailSettings.load(raw: ""); rail.width = 230
        let restarted = SnapshotService(provider: provider, frameWriter: writer, config: config, railSettings: rail, intentStore: intents, stageStore: store)
        let snapshot = restarted.snapshot()
        let scope = try #require(snapshot.windows.first(where: { $0.window.id == windows[0].id })?.scope)
        let plan = restarted.applyPlan(from: snapshot)
        #expect(plan.commands.first(where: { $0.window.id == windows[0].id })?.frame == Rect(x: 230, y: 0, width: 770, height: 800))
        let maintainer = LayoutMaintainer(service: restarted, mouseButtonsPressed: { false }, spaceProbe: { _ in false })
        _ = maintainer.tick()
        #expect(writer.frames[windows[0].id] == Rect(x: 230, y: 0, width: 770, height: 800))
        #expect(intents.intent(for: scope)?.zoomReservesRail == true)
    }


    @Test(arguments: [WindowManagementMode.spatialBsp, .bsp, .float])
    func reservedZoomSurvivesStageSwitchAndHiddenSiblingFocusRestores(mode: WindowManagementMode) throws {
        let display = powerDisplay()
        let active = powerWindow(281, x: 150, y: 0, width: 350, height: 800)
        let sibling = powerWindow(282, x: 510, y: 0, width: 490, height: 800)
        let other = powerWindow(283, x: 999, y: 799, width: 300, height: 300)
        let provider = PowerUserProvider(windows: [active, sibling, other])
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("spec019-stage-focus"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), mode: mode, focusedWindowID: active.id, members: [
                    PersistentStageMember(windowID: active.id, bundleID: active.bundleID, title: active.title, frame: active.frame),
                    PersistentStageMember(windowID: sibling.id, bundleID: sibling.bundleID, title: sibling.title, frame: sibling.frame)]),
                PersistentStage(id: StageID(rawValue: "2"), mode: mode, focusedWindowID: other.id, members: [
                    PersistentStageMember(windowID: other.id, bundleID: other.bundleID, title: other.title,
                                          frame: Rect(x: 150, y: 100, width: 300, height: 300))])])], activeDisplayID: display.id))
        let service = SnapshotService(provider: provider, frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: mode, gapsOuter: 0, gapsOuterLeft: 150, gapsInner: 10)),
            railSettings: .load(raw: ""), stageStore: store)
        _ = service.apply(service.applyPlan(from: service.snapshot()))
        let original = Dictionary(uniqueKeysWithValues: provider.snapshots.filter { $0.id != other.id }.map { ($0.id, $0.frame) })
        let scope = try #require(service.snapshot().windows.first(where: { $0.window.id == active.id })?.scope)
        if mode == .bsp {
            service.effectiveIntentStore.save(LayoutIntent(scope: scope, windowIDs: [active.id, sibling.id], placements: original, source: .command))
        }
        #expect(WindowCommandService(service: service, stageStore: store).toggleMaximize().changed)
        let stages = StageCommandService(service: service, store: store)
        #expect(stages.switchTo("2", displayID: display.id).changed)
        #expect(stages.switchTo("1", displayID: display.id).changed)
        #expect(writer.frames[active.id] == Rect(x: 150, y: 0, width: 850, height: 800))
        #expect(service.effectiveIntentStore.intent(for: scope)?.zoomReservesRail == true)
        provider.focusedID = sibling.id
        let maintainer = LayoutMaintainer(service: service, mouseButtonsPressed: { false }, spaceProbe: { _ in false })
        _ = maintainer.tick()
        #expect(service.effectiveIntentStore.intent(for: scope)?.zoomedWindowID == nil)
        #expect(provider.snapshots.first(where: { $0.id == active.id })?.frame == original[active.id])
        #expect(provider.snapshots.first(where: { $0.id == sibling.id })?.frame == original[sibling.id])
    }

    @Test
    func explicitTargetDoesNotDependOnFocusOrAffectOtherDisplay() throws {
        let left = powerDisplay()
        let right = powerDisplay("right-screen", index: 2, x: 1000)
        let windows = [powerWindow(231, x: 150), powerWindow(232, x: 550), powerWindow(233, x: 1100)]
        let provider = PowerUserProvider(displays: [left, right], windows: windows)
        provider.focusedID = windows[0].id
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("spec019-target"))
        let service = SnapshotService(provider: provider, frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0)), railSettings: .load(raw: ""), stageStore: store)
        #expect(WindowCommandService(service: service, stageStore: store).toggleMaximize(windowID: windows[1].id).changed)
        #expect(writer.frames[windows[1].id] == Rect(x: 150, y: 0, width: 850, height: 800))
        #expect(writer.frames[windows[2].id] == nil)
        #expect(provider.focusedID == windows[1].id)
    }

    @Test(arguments: [WindowManagementMode.float, .bsp, .masterStack, .spatialBsp])
    func windowOpenedDuringZoomIsVisibleAfterRestoration(mode: WindowManagementMode) throws {
        let active = powerWindow(291, x: 150)
        let sibling = powerWindow(292, x: 550)
        let newcomer = powerWindow(293, x: 420, y: 180, width: 300, height: 300)
        let provider = PowerUserProvider(windows: [active, sibling])
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("spec019-new-float"))
        let service = SnapshotService(provider: provider, frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: mode, gapsOuter: 0)),
            railSettings: .load(raw: ""), stageStore: store)
        let commands = WindowCommandService(service: service, stageStore: store)
        #expect(commands.toggleMaximize().changed)
        provider.snapshots.append(newcomer)
        let maintainer = LayoutMaintainer(service: service, mouseButtonsPressed: { false }, spaceProbe: { _ in false })
        _ = maintainer.tick()
        #expect(writer.frames[newcomer.id]?.x == 999)
        let capturedScope = try #require(service.snapshot().windows.first(where: { $0.window.id == active.id })?.scope)
        let captured = try #require(service.effectiveIntentStore.intent(for: capturedScope))
        #expect(captured.zoomedWindowID == active.id)
        #expect(captured.zoomReservesRail == true)
        #expect(captured.restorePlacements?[newcomer.id] == newcomer.frame)
        let replay = service.applyPlan(from: service.snapshot())
        if let pending = replay.commands.first(where: { $0.window.id == newcomer.id }) {
            #expect(!powerDisplay().visibleFrame.cgRect.contains(CGPoint(x: pending.frame.cgRect.midX, y: pending.frame.cgRect.midY)))
        }
        let toggleResult = commands.toggleMaximize()
        #expect(toggleResult.message.contains("off"))
        #expect(toggleResult.changed)
        let restored = try #require(provider.snapshots.first(where: { $0.id == newcomer.id }))
        #expect(powerDisplay().visibleFrame.cgRect.contains(restored.frame.cgRect))
        if mode == .float { #expect(restored.frame == newcomer.frame) }
    }

    @Test
    func closingFloatZoomTargetRestoresRemainingWindowsWithoutFocus() throws {
        let active = powerWindow(301, x: 150)
        let sibling = powerWindow(302, x: 550)
        let provider = PowerUserProvider(windows: [active, sibling])
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("spec019-close-float"))
        let service = SnapshotService(provider: provider, frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .float, gapsOuter: 0)),
            railSettings: .load(raw: ""), stageStore: store)
        let scope = try #require(service.snapshot().windows.first?.scope)
        #expect(WindowCommandService(service: service, stageStore: store).toggleMaximize().changed)
        provider.snapshots.removeAll { $0.id == active.id }
        provider.focusedID = nil
        let maintainer = LayoutMaintainer(service: service, mouseButtonsPressed: { false }, spaceProbe: { _ in false })
        _ = maintainer.tick()
        #expect(service.effectiveIntentStore.intent(for: scope)?.zoomedWindowID == nil)
        #expect(provider.snapshots.first?.frame == sibling.frame)
    }

    @Test
    func olderIntentDecodesAndReservedIntentRoundTrips() throws {
        let scope = StageScope(displayID: powerDisplay().id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let id = WindowID(rawValue: 241)
        let original = [id: Rect(x: 150, y: 0, width: 850, height: 800)]
        let old = LayoutIntent(scope: scope, windowIDs: [id], placements: original, source: .command, zoomedWindowID: id)
        let encoder = JSONEncoder(); let decoder = JSONDecoder()
        let bytes = try encoder.encode(old)
        #expect(!String(decoding: bytes, as: UTF8.self).contains("zoomReservesRail"))
        let decoded = try decoder.decode(LayoutIntent.self, from: bytes)
        #expect(decoded.zoomReservesRail == nil)
        #expect(decoded.restorePlacements == nil)
        let reserved = LayoutIntent(scope: scope, windowIDs: [id], placements: original, source: .command,
                                    zoomedWindowID: id, zoomReservesRail: true, restorePlacements: original)
        #expect(try decoder.decode(LayoutIntent.self, from: encoder.encode(reserved)) == reserved)
    }

    @Test
    func nativeFullscreenStartedDuringReservedZoomIsNeverResized() throws {
        let active = powerWindow(311, x: 150)
        let sibling = powerWindow(312, x: 550)
        let provider = PowerUserProvider(windows: [active, sibling])
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("spec019-native-transition"))
        let service = SnapshotService(provider: provider, frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .float, gapsOuter: 0)),
            railSettings: .load(raw: ""), stageStore: store)
        let commands = WindowCommandService(service: service, stageStore: store)
        #expect(commands.toggleMaximize().changed)
        let framesBefore = writer.frameHistory
        provider.snapshots[0].furniture = WindowFurniture(isNativeFullscreen: true)
        #expect(!commands.toggleMaximize().changed)
        #expect(writer.frameHistory == framesBefore)
    }

    @Test(arguments: [true, false])
    func nativeFullscreenAndEmptyContainerAreRefused(native: Bool) {
        var window = powerWindow(251, x: 100)
        var furniture = WindowFurniture(isNativeFullscreen: native)
        if !native { furniture.isResizable = false }
        window.furniture = furniture
        let provider = PowerUserProvider(windows: [window])
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: tempPath("spec019-native"))
        let service = SnapshotService(provider: provider, frameWriter: writer, railSettings: .load(raw: ""), stageStore: store)
        #expect(!WindowCommandService(service: service, stageStore: store).toggleMaximize().changed)
        #expect(writer.frames.isEmpty)
        var rail = RailSettings.load(raw: ""); rail.width = 1000
        let narrow = SnapshotService(provider: provider, frameWriter: writer, railSettings: rail, stageStore: store)
        #expect(narrow.maximizedFrame(on: powerDisplay()) == nil)
    }
}
