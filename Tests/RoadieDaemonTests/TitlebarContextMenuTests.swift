import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon
import RoadieStages

@Suite
struct TitlebarContextMenuTests {
    @Test
    func disabledFeatureNeverMarksClickEligible() {
        let snapshot = titlebarSnapshot()
        let hit = TitlebarContextMenuController.hitTest(
            point: CGPoint(x: 220, y: 120),
            snapshot: snapshot,
            settings: TitlebarContextMenuSettings(enabled: false)
        )

        #expect(hit.isEligible == false)
        #expect(hit.reason == .disabled)
    }

    @Test
    func contentClickIsNotTitlebar() {
        let snapshot = titlebarSnapshot()
        let hit = TitlebarContextMenuController.hitTest(
            point: CGPoint(x: 220, y: 240),
            snapshot: snapshot,
            settings: TitlebarContextMenuSettings(enabled: true)
        )

        #expect(hit.isEligible == false)
        #expect(hit.reason == .notTitlebar)
        #expect(hit.windowID == WindowID(rawValue: 1))
    }

    @Test
    func titlebarClickIsEligibleForManagedWindow() {
        let snapshot = titlebarSnapshot()
        let hit = TitlebarContextMenuController.hitTest(
            point: CGPoint(x: 220, y: 120),
            snapshot: snapshot,
            settings: TitlebarContextMenuSettings(enabled: true)
        )

        #expect(hit.isEligible)
        #expect(hit.reason == .eligible)
        #expect(hit.windowID == WindowID(rawValue: 1))
        #expect(hit.scope == StageScope(
            displayID: DisplayID(rawValue: "display-main"),
            desktopID: DesktopID(rawValue: 1),
            stageID: StageID(rawValue: "1")
        ))
    }

    @Test
    func unmanagedAndTransientWindowsAreIgnored() {
        let display = powerDisplay("display-main", index: 1, x: 0)
        let unmanaged = titlebarWindow(10, x: 100)
        let transient = WindowSnapshot(
            id: WindowID(rawValue: 11),
            pid: 11,
            appName: "Panel",
            bundleID: "panel",
            title: "Panel",
            frame: Rect(x: 500, y: 100, width: 300, height: 300),
            isOnScreen: true,
            isTileCandidate: false
        )
        let scope = StageScope(
            displayID: display.id,
            desktopID: DesktopID(rawValue: 1),
            stageID: StageID(rawValue: "1")
        )
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [display],
            windows: [
                ScopedWindowSnapshot(window: unmanaged, scope: nil),
                ScopedWindowSnapshot(window: transient, scope: scope)
            ],
            state: RoadieState()
        )
        let settings = TitlebarContextMenuSettings(enabled: true)

        let unmanagedHit = TitlebarContextMenuController.hitTest(
            point: CGPoint(x: 220, y: 120),
            snapshot: snapshot,
            settings: settings
        )
        let transientHit = TitlebarContextMenuController.hitTest(
            point: CGPoint(x: 620, y: 120),
            snapshot: snapshot,
            settings: settings
        )

        #expect(unmanagedHit.reason == .notManaged)
        #expect(transientHit.reason == .transient)
    }

    @Test
    func heightChangesEligibleBand() {
        let snapshot = titlebarSnapshot()
        let point = CGPoint(x: 220, y: 150)

        let defaultHit = TitlebarContextMenuController.hitTest(
            point: point,
            snapshot: snapshot,
            settings: TitlebarContextMenuSettings(enabled: true)
        )
        let expandedHit = TitlebarContextMenuController.hitTest(
            point: point,
            snapshot: snapshot,
            settings: TitlebarContextMenuSettings(enabled: true, height: 60)
        )

        #expect(defaultHit.reason == .notTitlebar)
        #expect(expandedHit.reason == .eligible)
    }

    @Test
    func edgeExclusionsProtectWindowControls() {
        let snapshot = titlebarSnapshot()
        let settings = TitlebarContextMenuSettings(
            enabled: true,
            leadingExclusion: 120,
            trailingExclusion: 40
        )

        let leftHit = TitlebarContextMenuController.hitTest(
            point: CGPoint(x: 150, y: 120),
            snapshot: snapshot,
            settings: settings
        )
        let rightHit = TitlebarContextMenuController.hitTest(
            point: CGPoint(x: 385, y: 120),
            snapshot: snapshot,
            settings: settings
        )
        let middleHit = TitlebarContextMenuController.hitTest(
            point: CGPoint(x: 240, y: 120),
            snapshot: snapshot,
            settings: settings
        )

        #expect(leftHit.reason == .excludedMargin)
        #expect(rightHit.reason == .excludedMargin)
        #expect(middleHit.reason == .eligible)
    }

    @Test
    func destinationsMarkCurrentContextAndExposeAlternatives() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let side = powerDisplay("display-side", index: 2, x: 1000)
        let window = titlebarWindow(1, x: 100)
        let stageWindow = titlebarWindow(2, x: 500)
        let provider = PowerUserProvider(displays: [main, side], windows: [window, stageWindow])
        let store = titlebarStageStore("titlebar-destinations", scopes: [
            titlebarScope(main.id, active: "1", stages: [
                titlebarStage("1", window),
                titlebarStage("2", stageWindow)
            ]),
            PersistentStageScope(
                displayID: main.id,
                desktopID: DesktopID(rawValue: 2),
                activeStageID: StageID(rawValue: "1"),
                stages: [
                    PersistentStage(id: StageID(rawValue: "1"), name: "Later")
                ]
            ),
            titlebarScope(side.id, active: "1", stages: [
                titlebarStage("1")
            ])
        ], activeDisplayID: main.id)
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)
        let snapshot = service.snapshot()

        let destinations = WindowContextActions(snapshotService: service, stageStore: store, stageLabelsVisible: { true })
            .destinations(for: window.id, in: snapshot, settings: TitlebarContextMenuSettings(enabled: true))

        #expect(destinations.contains { $0.kind == .stage && $0.id == "1" && $0.isCurrent })
        #expect(destinations.contains { $0.kind == .stage && $0.id == "2" && !$0.isCurrent })
        #expect(destinations.contains(WindowDestination(kind: .desktop, id: "1", label: "Desktop 1", isCurrent: true)))
        #expect(destinations.contains(WindowDestination(kind: .desktop, id: "2", label: "Desktop 2", isCurrent: false)))
        #expect(destinations.contains {
            $0.kind == .desktopStage
                && $0.id == "1:2"
                && $0.parentID == "1"
                && !$0.isCurrent
        })
        #expect(destinations.contains {
            $0.kind == .desktopStage
                && $0.id == "2:1"
                && $0.parentID == "2"
                && !$0.isCurrent
        })
        #expect(destinations.contains(WindowDestination(kind: .display, id: main.id.rawValue, label: "Ecran 1 - \(main.name)", isCurrent: true)))
        #expect(destinations.contains(WindowDestination(kind: .display, id: side.id.rawValue, label: "Ecran 2 - \(side.name)", isCurrent: false)))
    }

    @Test
    func generatedStageLabelsUseVisibleOrderInsteadOfTechnicalIDs() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let window = titlebarWindow(1, x: 100)
        let secondWindow = titlebarWindow(2, x: 500)
        let thirdWindow = titlebarWindow(3, x: 900)
        let provider = PowerUserProvider(displays: [main], windows: [window, secondWindow, thirdWindow])
        let store = titlebarStageStore("titlebar-stage-visible-labels", scopes: [
            titlebarScope(main.id, active: "9", stages: [
                PersistentStage(id: StageID(rawValue: "9"), name: "Work", members: [titlebarMember(window)]),
                titlebarStage("4", secondWindow),
                titlebarStage("7", thirdWindow)
            ])
        ], activeDisplayID: main.id)
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)
        let snapshot = service.snapshot()

        let destinations = WindowContextActions(snapshotService: service, stageStore: store, stageLabelsVisible: { true })
            .destinations(for: window.id, in: snapshot, settings: TitlebarContextMenuSettings(enabled: true))

        #expect(destinations.contains(WindowDestination(kind: .stage, id: "9", label: "Work", isCurrent: true)))
        #expect(destinations.contains(WindowDestination(kind: .stage, id: "4", label: "Stage 2", isCurrent: false)))
        #expect(destinations.contains(WindowDestination(kind: .stage, id: "7", label: "Stage 3", isCurrent: false)))
        #expect(destinations.contains {
            $0.kind == .desktopStage
                && $0.id == "1:4"
                && $0.label == "Stage 2"
        })
    }

    @Test
    func hiddenRailStageLabelsExposeNonEmptyStagesAndOneNextEmptyDestination() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let window = titlebarWindow(1, x: 100)
        let secondWindow = titlebarWindow(2, x: 500)
        let provider = PowerUserProvider(displays: [main], windows: [window, secondWindow])
        let store = titlebarStageStore("titlebar-hidden-stage-labels", scopes: [
            titlebarScope(main.id, active: "1", stages: [
                titlebarStage("1", window),
                PersistentStage(id: StageID(rawValue: "2"), name: "Work"),
                titlebarStage("3", secondWindow),
                titlebarStage("4")
            ])
        ], activeDisplayID: main.id)
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)
        let snapshot = service.snapshot()

        let destinations = WindowContextActions(snapshotService: service, stageStore: store, stageLabelsVisible: { false })
            .destinations(for: window.id, in: snapshot, settings: TitlebarContextMenuSettings(enabled: true))

        #expect(destinations.contains { $0.kind == .stage && $0.id == "1" && $0.isCurrent })
        #expect(destinations.contains { $0.kind == .stage && $0.id == "3" && !$0.isCurrent })
        #expect(destinations.contains(WindowDestination(kind: .stage, id: "4", label: "Prochaine stage vide", isCurrent: false)))
        #expect(!destinations.contains { $0.kind == .stage && $0.id == "2" })
        #expect(!destinations.contains { $0.kind == .stage && $0.id == "4" && $0.label != "Prochaine stage vide" })
    }

    @Test
    func desktopStageActionMovesWindowToExactTargetWithoutFollowingFocus() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let window = titlebarWindow(1, x: 100)
        let provider = PowerUserProvider(displays: [main], windows: [window])
        let writer = PowerUserWriter(provider: provider)
        let store = titlebarStageStore("titlebar-desktop-stage-action", scopes: [
            titlebarScope(main.id, active: "1", stages: [
                titlebarStage("1", window)
            ]),
            PersistentStageScope(
                displayID: main.id,
                desktopID: DesktopID(rawValue: 2),
                activeStageID: StageID(rawValue: "1"),
                stages: [
                    titlebarStage("1"),
                    PersistentStage(id: StageID(rawValue: "2"), name: "Later")
                ]
            )
        ], activeDisplayID: main.id)
        let service = SnapshotService(provider: provider, frameWriter: writer, stageStore: store)
        _ = service.snapshot()

        let result = WindowContextActions(snapshotService: service, stageStore: store, stageLabelsVisible: { true }).execute(WindowContextAction(
            windowID: window.id,
            kind: .desktopStage,
            targetID: "2:2",
            sourceScope: nil
        ))

        var state = store.state()
        #expect(result.changed)
        #expect(state.scope(displayID: main.id, desktopID: DesktopID(rawValue: 1)).memberIDs(in: StageID(rawValue: "1")).isEmpty)
        #expect(state.scope(displayID: main.id, desktopID: DesktopID(rawValue: 2)).memberIDs(in: StageID(rawValue: "2")) == [window.id])
        #expect(writer.focused.isEmpty)
    }

    @Test
    func actionWithMissingWindowDoesNotMutateState() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let window = titlebarWindow(1, x: 100)
        let provider = PowerUserProvider(displays: [main], windows: [window])
        let store = titlebarStageStore("titlebar-stale-action", scopes: [
            titlebarScope(main.id, active: "1", stages: [
                titlebarStage("1", window),
                titlebarStage("2")
            ])
        ], activeDisplayID: main.id)
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)
        _ = service.snapshot()
        let before = store.state()

        let result = WindowContextActions(snapshotService: service, stageStore: store, stageLabelsVisible: { true }).execute(WindowContextAction(
            windowID: WindowID(rawValue: 999),
            kind: .stage,
            targetID: "2",
            sourceScope: nil
        ))

        #expect(result.changed == false)
        #expect(ignoringMemberTimestamps(store.state()) == ignoringMemberTimestamps(before))
    }

    @Test
    func pinDesktopActionPersistsPinAndDoesNotMoveWindow() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let window = titlebarWindow(1, x: 100)
        let provider = PowerUserProvider(displays: [main], windows: [window])
        let eventPath = tempPath("titlebar-pin-events")
        let store = titlebarStageStore("titlebar-pin-desktop", scopes: [
            titlebarScope(main.id, active: "1", stages: [titlebarStage("1", window)])
        ], activeDisplayID: main.id)
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)
        _ = service.snapshot()

        let result = WindowContextActions(snapshotService: service, stageStore: store, eventLog: EventLog(path: eventPath)).execute(WindowContextAction(
            windowID: window.id,
            kind: .pinDesktop,
            targetID: WindowContextActionKind.pinDesktop.rawValue,
            sourceScope: nil
        ))

        let pin = store.state().pin(for: window.id)
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
        #expect(result.changed)
        #expect(pin?.pinScope == .desktop)
        #expect(store.state().stageScope(for: window.id)?.stageID == StageID(rawValue: "1"))
        #expect(events.contains("window.pin_added"))
    }

    @Test
    func pinnedActionCanChangeScopeAndUnpin() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let window = titlebarWindow(1, x: 100)
        let provider = PowerUserProvider(displays: [main], windows: [window])
        let store = titlebarStageStore("titlebar-pin-change-unpin", scopes: [
            titlebarScope(main.id, active: "1", stages: [titlebarStage("1", window)])
        ], activeDisplayID: main.id)
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)
        let actions = WindowContextActions(snapshotService: service, stageStore: store, stageLabelsVisible: { true })

        _ = actions.execute(WindowContextAction(windowID: window.id, kind: .pinDesktop, targetID: "pin", sourceScope: nil))
        let changed = actions.execute(WindowContextAction(windowID: window.id, kind: .pinAllDesktops, targetID: "pin", sourceScope: nil))
        let removed = actions.execute(WindowContextAction(windowID: window.id, kind: .unpin, targetID: "unpin", sourceScope: nil))

        #expect(changed.changed)
        #expect(removed.changed)
        #expect(store.state().pin(for: window.id) == nil)
        #expect(store.state().stageScope(for: window.id)?.stageID == StageID(rawValue: "1"))
    }

    @Test
    func movingPinnedWindowToAnotherStageRemovesInstancePin() {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let window = titlebarWindow(1, x: 100)
        let provider = PowerUserProvider(displays: [main], windows: [window])
        let store = titlebarStageStore("titlebar-pin-stage-move", scopes: [
            titlebarScope(main.id, active: "1", stages: [
                titlebarStage("1", window),
                titlebarStage("2")
            ])
        ], activeDisplayID: main.id)
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)
        let actions = WindowContextActions(snapshotService: service, stageStore: store, stageLabelsVisible: { true })

        _ = actions.execute(WindowContextAction(windowID: window.id, kind: .pinDesktop, targetID: "pin", sourceScope: nil))
        let moved = actions.execute(WindowContextAction(windowID: window.id, kind: .stage, targetID: "2", sourceScope: nil))

        #expect(moved.changed)
        #expect(store.state().pin(for: window.id) == nil)
        #expect(store.state().stageScope(for: window.id)?.stageID == StageID(rawValue: "2"))
    }

    @Test
    func affinityActionWritesGeneratedPlacementRule() throws {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let window = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 1,
            appName: "Firefox",
            bundleID: "org.mozilla.firefox",
            title: "Docs",
            frame: Rect(x: 100, y: 100, width: 300, height: 300),
            isOnScreen: true,
            isTileCandidate: true,
            subrole: "AXStandardWindow",
            role: "AXWindow"
        )
        let provider = PowerUserProvider(displays: [main], windows: [window])
        let store = titlebarStageStore("titlebar-affinity-action", scopes: [
            titlebarScope(main.id, active: "web", stages: [
                PersistentStage(id: StageID(rawValue: "web"), name: "Web", members: [titlebarMember(window)])
            ])
        ], activeDisplayID: main.id)
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)
        let rulesPath = tempPath("titlebar-affinity-generated.toml")
        defer { try? FileManager.default.removeItem(atPath: rulesPath) }

        let result = WindowContextActions(
            snapshotService: service,
            stageStore: store,
            affinityService: WindowRuleAffinityService(path: rulesPath),
            stageLabelsVisible: { true }
        ).execute(WindowContextAction(
            windowID: window.id,
            kind: .affinityApp,
            targetID: WindowContextActionKind.affinityApp.rawValue,
            sourceScope: nil
        ))

        let rules = try RoadieConfigLoader.loadRulesFile(from: rulesPath)
        #expect(result.changed)
        #expect(rules.count == 1)
        #expect(rules[0].match.app == "Firefox")
        #expect(rules[0].action.assignDisplay == "display-main")
        #expect(rules[0].action.assignDesktop == "1")
        #expect(rules[0].action.assignStage == "web")
        #expect(rules[0].action.follow == false)
    }

    @Test
    func affinityRemoveDeletesGeneratedAppRulesOnly() throws {
        let main = powerDisplay("display-main", index: 1, x: 0)
        let window = titlebarWindow(1, x: 100)
        let provider = PowerUserProvider(displays: [main], windows: [window])
        let store = titlebarStageStore("titlebar-affinity-remove", scopes: [
            titlebarScope(main.id, active: "1", stages: [titlebarStage("1", window)])
        ], activeDisplayID: main.id)
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)
        let rulesPath = tempPath("titlebar-affinity-remove-generated.toml")
        defer { try? FileManager.default.removeItem(atPath: rulesPath) }
        let affinity = WindowRuleAffinityService(path: rulesPath)
        let actions = WindowContextActions(
            snapshotService: service,
            stageStore: store,
            affinityService: affinity,
            stageLabelsVisible: { true }
        )

        _ = actions.execute(WindowContextAction(windowID: window.id, kind: .affinityApp, targetID: "save", sourceScope: nil))
        let removed = actions.execute(WindowContextAction(windowID: window.id, kind: .removeAffinityApp, targetID: "remove", sourceScope: nil))

        #expect(removed.changed)
        #expect(try RoadieConfigLoader.loadRulesFile(from: rulesPath).isEmpty)
    }
}

private func titlebarSnapshot() -> DaemonSnapshot {
    let display = powerDisplay("display-main", index: 1, x: 0)
    let window = titlebarWindow(1, x: 100)
    let provider = PowerUserProvider(displays: [display], windows: [window])
    let store = titlebarStageStore("titlebar-snapshot", scopes: [
        titlebarScope(display.id, active: "1", stages: [titlebarStage("1", window)])
    ], activeDisplayID: display.id)
    return SnapshotService(
        provider: provider,
        frameWriter: PowerUserWriter(provider: provider),
        stageStore: store
    ).snapshot()
}

private func titlebarWindow(_ id: UInt32, x: Double) -> WindowSnapshot {
    powerWindow(id, x: x, y: 100, width: 300, height: 300, app: "Titlebar")
}

private func titlebarStageStore(
    _ name: String,
    scopes: [PersistentStageScope],
    activeDisplayID: DisplayID
) -> StageStore {
    let store = StageStore(path: tempPath(name))
    store.save(PersistentStageState(scopes: scopes, activeDisplayID: activeDisplayID))
    return store
}

private func titlebarScope(
    _ displayID: DisplayID,
    active rawActiveID: String,
    stages: [PersistentStage]
) -> PersistentStageScope {
    PersistentStageScope(
        displayID: displayID,
        activeStageID: StageID(rawValue: rawActiveID),
        stages: stages
    )
}

private func titlebarStage(_ rawID: String, _ windows: WindowSnapshot...) -> PersistentStage {
    PersistentStage(
        id: StageID(rawValue: rawID),
        members: windows.map(titlebarMember)
    )
}

private func titlebarMember(_ window: WindowSnapshot) -> PersistentStageMember {
    PersistentStageMember(
        windowID: window.id,
        bundleID: window.bundleID,
        title: window.title,
        frame: window.frame
    )
}

private func ignoringMemberTimestamps(_ state: PersistentStageState) -> PersistentStageState {
    var copy = state
    for scopeIndex in copy.scopes.indices {
        for stageIndex in copy.scopes[scopeIndex].stages.indices {
            for memberIndex in copy.scopes[scopeIndex].stages[stageIndex].members.indices {
                copy.scopes[scopeIndex].stages[stageIndex].members[memberIndex].lastSeenAt = nil
                copy.scopes[scopeIndex].stages[stageIndex].members[memberIndex].missingSince = nil
            }
        }
    }
    return copy
}
