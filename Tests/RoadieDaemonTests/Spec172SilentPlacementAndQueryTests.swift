import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

@Suite
struct Spec172SilentPlacementAndQueryTests {
    private let display1 = DisplaySnapshot(
        id: DisplayID(rawValue: "display-builtin-uuid"),
        index: 1,
        name: "Built-in Retina Display",
        frame: Rect(x: 0, y: 0, width: 1728, height: 1117),
        visibleFrame: Rect(x: 0, y: 25, width: 1728, height: 1092),
        isMain: true
    )
    private let display2 = DisplaySnapshot(
        id: DisplayID(rawValue: "display-lg-uuid"),
        index: 2,
        name: "LG HDR 4K",
        frame: Rect(x: 1728, y: 0, width: 2560, height: 1440),
        visibleFrame: Rect(x: 1728, y: 25, width: 2560, height: 1415),
        isMain: false
    )

    private func makeWindow(
        _ id: UInt32,
        app: String = "Google Chrome",
        bundleID: String = "com.google.Chrome",
        title: String = "Revue Visual Test",
        pid: Int32 = 4242,
        x: Double = 1800,
        y: Double = 100
    ) -> WindowSnapshot {
        WindowSnapshot(
            id: WindowID(rawValue: id),
            pid: pid,
            appName: app,
            bundleID: bundleID,
            title: title,
            frame: Rect(x: x, y: y, width: 1200, height: 800),
            isOnScreen: true,
            isTileCandidate: true
        )
    }

    @Test
    func queryStageSnapshotsExposeRailPositionAndIsActivePerDisplay() throws {
        let store = StageStore(path: tempPath("spec172-query-stages"))
        defer { try? FileManager.default.removeItem(at: store.fileURL) }

        let d1Stage8Win = makeWindow(101, app: "Notes", bundleID: "com.apple.Notes", title: "Work", x: 100)
        let d1Stage1Win = makeWindow(102, app: "Finder", bundleID: "com.apple.finder", title: "Docs", x: 120)
        let d2Stage3Win = makeWindow(201, app: "Terminal", bundleID: "com.apple.Terminal", title: "Code", x: 1850)

        // Sur l'écran 1, la stage nommée "Work" (id=8) est en position 1 du rail (inactive),
        // et la stage id=1 est en position 2 (active). Sur l'écran 2, stage id=3 est active.
        let scope1 = PersistentStageScope(
            displayID: display1.id,
            activeStageID: StageID(rawValue: "1"),
            stages: [
                PersistentStage(id: StageID(rawValue: "8"), name: "Work", members: [
                    PersistentStageMember(windowID: d1Stage8Win.id, bundleID: d1Stage8Win.bundleID, title: d1Stage8Win.title, frame: d1Stage8Win.frame)
                ]),
                PersistentStage(id: StageID(rawValue: "1"), name: "Stage 1", members: [
                    PersistentStageMember(windowID: d1Stage1Win.id, bundleID: d1Stage1Win.bundleID, title: d1Stage1Win.title, frame: d1Stage1Win.frame)
                ])
            ]
        )
        let scope2 = PersistentStageScope(
            displayID: display2.id,
            activeStageID: StageID(rawValue: "3"),
            stages: [
                PersistentStage(id: StageID(rawValue: "3"), name: "Dev", members: [
                    PersistentStageMember(windowID: d2Stage3Win.id, bundleID: d2Stage3Win.bundleID, title: d2Stage3Win.title, frame: d2Stage3Win.frame)
                ])
            ]
        )
        store.save(PersistentStageState(scopes: [scope1, scope2], activeDisplayID: display2.id))

        let provider = PowerUserProvider(displays: [display1, display2], windows: [d1Stage8Win, d1Stage1Win, d2Stage3Win])
        provider.focusedID = d2Stage3Win.id
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), config: RoadieConfig(), stageStore: store)
        let daemonSnapshot = service.snapshot(followFocus: false)

        let automation = AutomationSnapshotService(stageStore: store).snapshot(from: daemonSnapshot)
        let d1Stages = automation.stages.filter { $0.displayId == display1.id.rawValue }
        #expect(d1Stages.map(\.id) == ["8", "1"])
        #expect(d1Stages.map(\.position) == [1, 2])
        #expect(d1Stages.map(\.isActive) == [false, true])

        let d2Stages = automation.stages.filter { $0.displayId == display2.id.rawValue }
        let d2Stage3 = try #require(d2Stages.first { $0.id == "3" })
        #expect(d2Stage3.position == 1)
        #expect(d2Stage3.isActive == true)
        #expect(d2Stages.filter { $0.id != "3" }.allSatisfy { !$0.isActive })

        // Rétrocompatibilité JSON : un snapshot hérité sans position/isActive décode sans erreur.
        let legacyJSON = """
        {"id":"stage-old","desktopId":"desktop-1","displayId":"display-1","name":"Old","mode":"bsp","windowIds":[]}
        """.data(using: .utf8)!
        let decodedLegacy = try JSONDecoder().decode(AutomationStageSnapshot.self, from: legacyJSON)
        #expect(decodedLegacy.position == nil)
        #expect(decodedLegacy.isActive == false)
    }

    @Test
    func stageAssignWithExplicitWindowDisplayAndNoFollowDoesNotSwitchActiveStages() throws {
        let store = StageStore(path: tempPath("spec172-stage-assign-silent"))
        defer { try? FileManager.default.removeItem(at: store.fileURL) }

        let d1InactiveWin = makeWindow(101, app: "Notes", bundleID: "com.apple.Notes", title: "Bg", x: 100)
        let d1ActiveWin = makeWindow(102, app: "Mail", bundleID: "com.apple.mail", title: "Inbox", x: 120)
        let d2UserWin = makeWindow(201, app: "Terminal", bundleID: "com.apple.Terminal", title: "Work", x: 1850)
        let chromeWin = makeWindow(202, app: "Google Chrome", bundleID: "com.google.Chrome", title: "Playwright", x: 1900)

        let scope1 = PersistentStageScope(
            displayID: display1.id,
            activeStageID: StageID(rawValue: "1"),
            stages: [
                PersistentStage(id: StageID(rawValue: "8"), name: "Work", members: [
                    PersistentStageMember(windowID: d1InactiveWin.id, bundleID: d1InactiveWin.bundleID, title: d1InactiveWin.title, frame: d1InactiveWin.frame)
                ]),
                PersistentStage(id: StageID(rawValue: "1"), name: "Stage 1", members: [
                    PersistentStageMember(windowID: d1ActiveWin.id, bundleID: d1ActiveWin.bundleID, title: d1ActiveWin.title, frame: d1ActiveWin.frame)
                ])
            ]
        )
        let scope2 = PersistentStageScope(
            displayID: display2.id,
            activeStageID: StageID(rawValue: "2"),
            stages: [
                PersistentStage(id: StageID(rawValue: "2"), name: "Main", focusedWindowID: d2UserWin.id, members: [
                    PersistentStageMember(windowID: d2UserWin.id, bundleID: d2UserWin.bundleID, title: d2UserWin.title, frame: d2UserWin.frame),
                    PersistentStageMember(windowID: chromeWin.id, bundleID: chromeWin.bundleID, title: chromeWin.title, frame: chromeWin.frame)
                ])
            ]
        )
        store.save(PersistentStageState(scopes: [scope1, scope2], activeDisplayID: display2.id))

        let provider = PowerUserProvider(displays: [display1, display2], windows: [d1InactiveWin, d1ActiveWin, d2UserWin, chromeWin])
        provider.focusedID = d2UserWin.id
        let snapshots = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), config: RoadieConfig(), stageStore: store)

        // Assigner Chrome (202) vers l'écran 1, stage id=8 (inactive) sans suivre.
        let result = StageCommandService(service: snapshots, store: store, config: RoadieConfig())
            .assign("8", windowID: chromeWin.id, displaySelector: "1", follow: false)
        #expect(result.changed)
        #expect(result.outcome != .failed)

        let postState = store.state()
        let postScope1 = try #require(postState.scopes.first { $0.displayID == display1.id })
        let postScope2 = try #require(postState.scopes.first { $0.displayID == display2.id })

        // La fenêtre Chrome est dans la stage 8 de l'écran 1, SANS création de stage 8 sur l'écran 2,
        // et SANS basculer la stage active de l'écran 1 ni de l'écran 2.
        #expect(postScope1.stages.first { $0.id == StageID(rawValue: "8") }?.members.contains { $0.windowID == chromeWin.id } == true)
        #expect(postScope1.activeStageID == StageID(rawValue: "1"))
        #expect(postScope2.activeStageID == StageID(rawValue: "2"))
        #expect(!postScope2.stages.contains { $0.id == StageID(rawValue: "8") })
        #expect(postState.activeDisplayID == display2.id)
        #expect(provider.focusedID == d2UserWin.id)
    }

    @Test
    func stageAssignPositionTargetsExplicitDisplayByRailPositionSilently() throws {
        let store = StageStore(path: tempPath("spec172-stage-assign-pos-silent"))
        defer { try? FileManager.default.removeItem(at: store.fileURL) }

        let d1Pos1Win = makeWindow(101, app: "Notes", bundleID: "com.apple.Notes", title: "Slot1", x: 100)
        let d1Pos2Win = makeWindow(102, app: "Mail", bundleID: "com.apple.mail", title: "Slot2", x: 120)
        let d2Chrome = makeWindow(202, app: "Google Chrome", bundleID: "com.google.Chrome", title: "Test", x: 1900)

        let scope1 = PersistentStageScope(
            displayID: display1.id,
            activeStageID: StageID(rawValue: "1"),
            stages: [
                PersistentStage(id: StageID(rawValue: "8"), name: "Tests", members: [
                    PersistentStageMember(windowID: d1Pos1Win.id, bundleID: d1Pos1Win.bundleID, title: d1Pos1Win.title, frame: d1Pos1Win.frame)
                ]),
                PersistentStage(id: StageID(rawValue: "1"), name: "Stage 1", members: [
                    PersistentStageMember(windowID: d1Pos2Win.id, bundleID: d1Pos2Win.bundleID, title: d1Pos2Win.title, frame: d1Pos2Win.frame)
                ])
            ]
        )
        let scope2 = PersistentStageScope(
            displayID: display2.id,
            activeStageID: StageID(rawValue: "2"),
            stages: [
                PersistentStage(id: StageID(rawValue: "2"), name: "Main", members: [
                    PersistentStageMember(windowID: d2Chrome.id, bundleID: d2Chrome.bundleID, title: d2Chrome.title, frame: d2Chrome.frame)
                ])
            ]
        )
        store.save(PersistentStageState(scopes: [scope1, scope2], activeDisplayID: display2.id))

        let provider = PowerUserProvider(displays: [display1, display2], windows: [d1Pos1Win, d1Pos2Win, d2Chrome])
        let snapshots = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), config: RoadieConfig(), stageStore: store)

        // Position 1 sur "Built-in Retina Display" résout vers la stage id=8 ("Tests").
        let result = StageCommandService(service: snapshots, store: store, config: RoadieConfig())
            .assignPosition(1, windowID: d2Chrome.id, displaySelector: "Built-in Retina Display", follow: false)
        #expect(result.changed)
        let postScope1 = try #require(store.state().scopes.first { $0.displayID == display1.id })
        #expect(postScope1.stages.first { $0.id == StageID(rawValue: "8") }?.members.contains { $0.windowID == d2Chrome.id } == true)
        #expect(postScope1.activeStageID == StageID(rawValue: "1"))
    }

    @Test
    func windowDisplayWithExplicitWindowAndNoFollowTransfersCleanly() throws {
        let store = StageStore(path: tempPath("spec172-window-display"))
        defer { try? FileManager.default.removeItem(at: store.fileURL) }

        let d2User = makeWindow(201, app: "Terminal", bundleID: "com.apple.Terminal", title: "Shell", x: 1850)
        let d2Chrome = makeWindow(202, app: "Google Chrome", bundleID: "com.google.Chrome", title: "Fresh", x: 1900)

        let scope1 = PersistentStageScope(displayID: display1.id, activeStageID: StageID(rawValue: "1"), stages: [
            PersistentStage(id: StageID(rawValue: "1"), name: "Stage 1", members: [])
        ])
        let scope2 = PersistentStageScope(displayID: display2.id, activeStageID: StageID(rawValue: "1"), stages: [
            PersistentStage(id: StageID(rawValue: "1"), name: "Stage 1", focusedWindowID: d2User.id, members: [
                PersistentStageMember(windowID: d2User.id, bundleID: d2User.bundleID, title: d2User.title, frame: d2User.frame),
                PersistentStageMember(windowID: d2Chrome.id, bundleID: d2Chrome.bundleID, title: d2Chrome.title, frame: d2Chrome.frame)
            ])
        ])
        store.save(PersistentStageState(scopes: [scope1, scope2], activeDisplayID: display2.id))

        let provider = PowerUserProvider(displays: [display1, display2], windows: [d2User, d2Chrome])
        provider.focusedID = d2User.id
        let snapshots = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), config: RoadieConfig(), stageStore: store)

        let result = WindowCommandService(service: snapshots)
            .sendToDisplay("display-builtin-uuid", windowID: d2Chrome.id, follow: false)
        #expect(result.changed)
        #expect(result.outcome != .failed)

        let postState = store.state()
        let postScope1 = try #require(postState.scopes.first { $0.displayID == display1.id })
        #expect(postScope1.stages.first { $0.id == StageID(rawValue: "1") }?.members.contains { $0.windowID == d2Chrome.id } == true)
        #expect(postState.activeDisplayID == display2.id)
        #expect(provider.focusedID == d2User.id)
    }

    @Test
    func oneShotRulePlacesNewWindowIntoInactiveStageSilentlyAndConsumesOnce() throws {
        let store = StageStore(path: tempPath("spec172-oneshot-maintainer"))
        defer { try? FileManager.default.removeItem(at: store.fileURL) }

        let d1InactiveWin = makeWindow(101, app: "Notes", bundleID: "com.apple.Notes", title: "Slot1", x: 100)
        let d1ActiveWin = makeWindow(102, app: "Mail", bundleID: "com.apple.mail", title: "Slot2", x: 120)
        let d2UserWin = makeWindow(201, app: "Terminal", bundleID: "com.apple.Terminal", title: "Editor", x: 1850)
        let newChrome = makeWindow(303, app: "Google Chrome", bundleID: "com.google.Chrome", title: "Revue E2E - Page", pid: 9090, x: 1900)

        let scope1 = PersistentStageScope(
            displayID: display1.id,
            activeStageID: StageID(rawValue: "1"),
            stages: [
                PersistentStage(id: StageID(rawValue: "8"), name: "Tests", members: [
                    PersistentStageMember(windowID: d1InactiveWin.id, bundleID: d1InactiveWin.bundleID, title: d1InactiveWin.title, frame: d1InactiveWin.frame)
                ]),
                PersistentStage(id: StageID(rawValue: "1"), name: "Stage 1", members: [
                    PersistentStageMember(windowID: d1ActiveWin.id, bundleID: d1ActiveWin.bundleID, title: d1ActiveWin.title, frame: d1ActiveWin.frame)
                ])
            ]
        )
        let scope2 = PersistentStageScope(
            displayID: display2.id,
            activeStageID: StageID(rawValue: "2"),
            stages: [
                PersistentStage(id: StageID(rawValue: "2"), name: "Main", focusedWindowID: d2UserWin.id, members: [
                    PersistentStageMember(windowID: d2UserWin.id, bundleID: d2UserWin.bundleID, title: d2UserWin.title, frame: d2UserWin.frame)
                ])
            ]
        )
        store.save(PersistentStageState(scopes: [scope1, scope2], activeDisplayID: display2.id))

        let oneShotStore = OneShotWindowRulesStore()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let rule = OneShotWindowRule(
            app: "Google Chrome",
            titlePrefix: "Revue E2E",
            display: "1",
            stagePosition: 1,
            follow: false,
            createdAt: t0,
            ttlSeconds: 30
        )
        #expect(oneShotStore.add(rule, now: t0))

        // Chrome vient tout juste de s'ouvrir sur l'écran 2 et de prendre le focus macOS.
        let provider = PowerUserProvider(displays: [display1, display2], windows: [d1InactiveWin, d1ActiveWin, d2UserWin, newChrome])
        provider.focusedID = newChrome.id
        let snapshots = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), config: RoadieConfig(), stageStore: store)
        let events = EventLog()
        let maintainer = LayoutMaintainer(
            service: snapshots,
            events: events,
            ruleEngine: nil, // Même sans aucune règle permanente dans roadies.toml !
            store: store,
            oneShotRules: oneShotStore,
            now: { t0.addingTimeInterval(1) }
        )

        _ = maintainer.tick(cause: "ax:created")

        // 1. La règle ponctuelle a été consommée (single-shot).
        #expect(oneShotStore.list(now: t0.addingTimeInterval(2)).isEmpty)

        // 2. Chrome a été rangé dans la stage 8 (position 1 de l'écran 1), qui reste INACTIVE.
        let postState = store.state()
        let postScope1 = try #require(postState.scopes.first { $0.displayID == display1.id })
        #expect(postScope1.stages.first { $0.id == StageID(rawValue: "8") }?.members.contains { $0.windowID == newChrome.id } == true)
        #expect(postScope1.activeStageID == StageID(rawValue: "1"))

        // 3. L'écran 2 reste actif et le focus a été rendu à la fenêtre précédente de François (d2UserWin).
        #expect(postState.activeDisplayID == display2.id)
        #expect(provider.focusedID == d2UserWin.id)
    }

    @Test
    @MainActor
    func cliRouterHandlesAddOnceListOnceClearOnceAndNewStageWindowFlags() throws {
        let store = StageStore(path: tempPath("spec172-cli-router"))
        defer { try? FileManager.default.removeItem(at: store.fileURL) }

        let d1Win = makeWindow(101, app: "Notes", bundleID: "com.apple.Notes", title: "Slot1", x: 100)
        let d2Win = makeWindow(201, app: "Terminal", bundleID: "com.apple.Terminal", title: "Work", x: 1850)
        let d2Chrome = makeWindow(202, app: "Google Chrome", bundleID: "com.google.Chrome", title: "Playwright", x: 1900)
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display1.id, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "8"), name: "Tests", members: [
                    PersistentStageMember(windowID: d1Win.id, bundleID: d1Win.bundleID, title: d1Win.title, frame: d1Win.frame)
                ]),
                PersistentStage(id: StageID(rawValue: "1"), name: "Stage 1", members: [])
            ]),
            PersistentStageScope(displayID: display2.id, activeStageID: StageID(rawValue: "2"), stages: [
                PersistentStage(id: StageID(rawValue: "2"), name: "Main", focusedWindowID: d2Win.id, members: [
                    PersistentStageMember(windowID: d2Win.id, bundleID: d2Win.bundleID, title: d2Win.title, frame: d2Win.frame),
                    PersistentStageMember(windowID: d2Chrome.id, bundleID: d2Chrome.bundleID, title: d2Chrome.title, frame: d2Chrome.frame)
                ])
            ])
        ], activeDisplayID: display2.id))

        let provider = PowerUserProvider(displays: [display1, display2], windows: [d1Win, d2Win, d2Chrome])
        provider.focusedID = d2Win.id
        let snapshots = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), config: RoadieConfig(), stageStore: store)
        let oneShotStore = OneShotWindowRulesStore()
        let router = CLICommandRouter(makeService: { _ in snapshots }, oneShotRules: oneShotStore)

        // 1. rules add-once -> list-once -> clear-once
        let addResp = router.run([
            "rules", "add-once",
            "--app", "Google Chrome",
            "--display", "1",
            "--stage-position", "1",
            "--no-follow",
            "--ttl", "25",
            "--json"
        ])
        #expect(addResp.exitCode == 0)
        #expect(oneShotStore.list().count == 1)

        let listResp = router.run(["rules", "list-once", "--json"])
        #expect(listResp.exitCode == 0)
        #expect(listResp.stdout.contains("Google Chrome"))

        let clearResp = router.run(["rules", "clear-once"])
        #expect(clearResp.exitCode == 0)
        #expect(clearResp.stdout.contains("removed=1"))
        #expect(oneShotStore.list().isEmpty)

        // 2. stage assign --window 202 --display 1 --stage-position 1 --no-follow
        let assignResp = router.run([
            "stage", "assign",
            "--window", "202",
            "--display", "1",
            "--stage-position", "1",
            "--no-follow"
        ])
        #expect(assignResp.exitCode == 0)
        let postScope1 = try #require(store.state().scopes.first { $0.displayID == display1.id })
        #expect(postScope1.stages.first { $0.id == StageID(rawValue: "8") }?.members.contains { $0.windowID == d2Chrome.id } == true)
        #expect(postScope1.activeStageID == StageID(rawValue: "1"))

        // 3. window display 2 --window 202 --no-follow
        let winDispResp = router.run(["window", "display", "2", "--window", "202", "--no-follow"])
        #expect(winDispResp.exitCode == 0)

        // 4. Flags conflictuels rejetés avec code 64
        let conflictResp = router.run(["stage", "assign", "8", "--follow", "--no-follow"])
        #expect(conflictResp.exitCode == 64)
    }
}
