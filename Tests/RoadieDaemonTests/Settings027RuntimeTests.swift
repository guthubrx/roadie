import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages
import Testing
@testable import RoadieDaemon

@MainActor
@Suite
struct Settings027RuntimeTests {
    @Test
    func notificationCoalescesLayoutRequestsAndIgnoresFonts() async throws {
        let fixture = try RuntimeConfigFixture("[tiling]\ngaps_outer = 6\n")
        defer { fixture.clean() }
        let timer = SettingsRuntimeTimer()
        var causes: [String] = []
        let scheduler = TickScheduler(
            tick: { causes.append($0); return MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0) },
            nextDeadline: { _ in nil }, isBlocked: { false },
            now: { timer.now }, schedule: timer.schedule, events: nil
        )
        let center = NotificationCenter()
        var requested = 0
        let controller = SettingsLiveApplyController(
            configService: fixture.service, notificationCenter: center,
            onLayoutChange: { _ in requested += 1; scheduler.request(cause: "command:settings") }
        )
        controller.start()
        defer { controller.stop() }
        try fixture.replace("[tiling]\ngaps_outer = 7\n")
        center.post(name: .roadieSettingsDidChange, object: nil, userInfo: [
            "configPath": fixture.path, "settingID": "tiling.gaps_outer"
        ])
        for _ in 0..<100 where requested == 0 { await Task.yield() }
        #expect(requested == 1)
        try fixture.replace("[tiling]\ngaps_outer = 8\n")
        controller.applyChange(configPath: fixture.path, settingID: "tiling.gaps_outer")
        #expect(requested == 2)
        #expect(causes.isEmpty)
        timer.advance(by: 0.016)
        #expect(causes == ["command:settings"])

        try fixture.replace("[tiling]\ngaps_outer = 8\n[interface]\nsettings_text_font_size = 24\n")
        controller.applyChange(configPath: fixture.path, settingID: "*")
        timer.advance(by: 1)
        #expect(requested == 2)
        #expect(causes.count == 1)
    }

    @Test(arguments: [
        (WindowManagementMode.bsp, false, 0.0), (.bsp, true, 0.0),
        (.spatialBsp, false, 0.0), (.spatialBsp, true, 0.0),
        (.bsp, false, 0.25), (.bsp, true, 0.25),
        (.spatialBsp, false, 0.25), (.spatialBsp, true, 0.25)
    ])
    func marginChangeProducesNewFramesImmediatelyWithOverridePriority(parameters: (WindowManagementMode, Bool, Double)) throws {
        let (mode, hasOverride, fraction) = parameters
        func text(gap: Double) -> String {
            """
            [tiling]
            default_strategy = "\(mode.rawValue)"
            gaps_outer = \(gap)
            gaps_inner = 10
            [fx.rail]
            auto_hide = false
            """ + (hasOverride ? "\n[[tiling.display_overrides]]\ndisplay_id = \"display-main\"\ngaps_outer_left = 120\n" : "")
        }
        let fixture = try RuntimeConfigFixture(text(gap: 6 + fraction))
        defer { fixture.clean() }
        let display = powerDisplay()
        let windows = [powerWindow(1, x: 100), powerWindow(2, x: 500)]
        let provider = PowerUserProvider(displays: [display], windows: windows)
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: fixture.directory.appendingPathComponent("stages.json").path)
        let intents = LayoutIntentStore(path: fixture.directory.appendingPathComponent("intents.json").path)
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        store.save(PersistentStageState(scopes: [PersistentStageScope(
            displayID: display.id, activeStageID: scope.stageID, stages: [PersistentStage(
                id: scope.stageID, mode: mode,
                members: windows.map { PersistentStageMember(windowID: $0.id, bundleID: $0.bundleID, title: $0.title, frame: $0.frame) }
            )]
        )], activeDisplayID: display.id))
        let service = SnapshotService(
            provider: provider, frameWriter: writer, intentStore: intents, stageStore: store,
            events: fixture.events, frameRegistry: WrittenFrameRegistry(), configService: fixture.service
        )
        let maintainer = LayoutMaintainer(
            service: service, events: fixture.events, store: store,
            mouseButtonsPressed: { false }, configService: fixture.service
        )
        _ = maintainer.tick(cause: "command:startup")
        let before = writer.frameHistory.values.reduce(0) { $0 + $1.count }
        // Un intent de commande valide protège normalement sa géométrie. La petite variation
        // de marge doit malgré cela remplacer le plan, sans événement AX ou filet périodique.
        let placements = Dictionary(uniqueKeysWithValues: provider.snapshots.map { ($0.id, $0.frame) })
        intents.save(LayoutIntent(scope: scope, windowIDs: windows.map(\.id), placements: placements, source: .command))
        let timer = SettingsRuntimeTimer()
        var result: MaintenanceTick?
        let scheduler = TickScheduler(
            tick: { result = maintainer.tick(cause: $0); return result! },
            nextDeadline: { _ in nil }, isBlocked: { false },
            now: { timer.now }, schedule: timer.schedule, events: nil
        )
        let controller = SettingsLiveApplyController(configService: fixture.service, onLayoutChange: {
            maintainer.configurationChanged(invalidateLayoutIntents: $0)
            scheduler.request(cause: "command:settings")
        })
        try fixture.replace(text(gap: 7 + fraction))
        #expect(fixture.service.activeConfig.tiling.gapsOuter == 7 + fraction)
        controller.applyChange(configPath: fixture.path, settingID: "tiling.gaps_outer")
        #expect(result == nil)
        timer.advance(by: 0.016)
        #expect((result?.applied ?? 0) > 0)
        #expect(writer.frameHistory.values.reduce(0) { $0 + $1.count } > before)
        let changedFrames = try #require(writer.frames[windows[0].id])
        #expect(changedFrames.x == (hasOverride ? 120 : 7))
        #expect(changedFrames.y == 7)
        #expect(changedFrames.height == 786)
        // La passe suivante revient à la tolérance AX ordinaire : un pixel de bruit
        // ne doit pas refaire l'application explicite ni provoquer une lutte avec l'app.
        let writtenAfterChange = writer.frameHistory.values.reduce(0) { $0 + $1.count }
        provider.snapshots[0].frame.x += 1
        let ordinary = maintainer.tick(cause: "ax:AXWindowMoved")
        #expect(ordinary.commands == 0)
        #expect(writer.frameHistory.values.reduce(0) { $0 + $1.count } == writtenAfterChange)
    }

    @Test
    func reservedZoomRetainsModeAndRecomputesOnePointMarginAfterGesture() throws {
        func text(gap: Int) -> String { "[tiling]\ngaps_outer = \(gap)\n[fx.rail]\nauto_hide = false\nwidth = 150\n" }
        let fixture = try RuntimeConfigFixture(text(gap: 6))
        defer { fixture.clean() }
        let display = powerDisplay()
        let window = powerWindow(1, x: 150, y: 6, width: 844, height: 788)
        let provider = PowerUserProvider(displays: [display], windows: [window])
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: fixture.directory.appendingPathComponent("stages.json").path)
        let intents = LayoutIntentStore(path: fixture.directory.appendingPathComponent("intents.json").path)
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        store.save(PersistentStageState(scopes: [PersistentStageScope(
            displayID: display.id, activeStageID: scope.stageID, stages: [PersistentStage(
                id: scope.stageID, mode: .spatialBsp,
                members: [PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame)]
            )]
        )], activeDisplayID: display.id))
        let restoration = [window.id: Rect(x: 200, y: 200, width: 300, height: 300)]
        intents.save(LayoutIntent(
            scope: scope, windowIDs: [window.id], placements: [window.id: window.frame],
            source: .command, zoomedWindowID: window.id, zoomReservesRail: true, restorePlacements: restoration
        ))
        let service = SnapshotService(
            provider: provider, frameWriter: writer, intentStore: intents, stageStore: store,
            events: fixture.events, frameRegistry: WrittenFrameRegistry(), configService: fixture.service
        )
        var mousePressed = false
        let maintainer = LayoutMaintainer(
            service: service, events: fixture.events, store: store,
            mouseButtonsPressed: { mousePressed }, configService: fixture.service
        )
        _ = maintainer.tick(cause: "command:startup")
        let controller = SettingsLiveApplyController(configService: fixture.service, onLayoutChange: {
            maintainer.configurationChanged(invalidateLayoutIntents: $0)
        })
        try fixture.replace(text(gap: 7))
        controller.applyChange(configPath: fixture.path, settingID: "tiling.gaps_outer")
        mousePressed = true
        #expect(maintainer.tick(cause: "command:settings").commands == 0)
        mousePressed = false
        #expect(maintainer.tick(cause: "drag").applied == 1)
        #expect(writer.frames[window.id] == Rect(x: 150, y: 7, width: 843, height: 786))
        let zoom = try #require(intents.intent(for: scope))
        #expect(zoom.zoomedWindowID == window.id)
        #expect(zoom.zoomReservesRail == true)
        #expect(zoom.restorePlacements == restoration)
        #expect(store.state().bspTree(for: scope) != nil)
        #expect(maintainer.tick(cause: "safety").commands == 0)
    }

    @Test(arguments: [
        (WindowManagementMode.bsp, Settings027WriteBehavior.ignoreFirst), (.spatialBsp, .ignoreFirst),
        (.bsp, .ignoreAlways), (.spatialBsp, .ignoreAlways),
        (.bsp, .animation), (.spatialBsp, .animation),
        (.bsp, .unknownFirst), (.spatialBsp, .unknownFirst), (.spatialBsp, .knownClamp)
    ])
    func onePointSettingsWriteUsesBoundedRetryAndRealFrameProof(parameters: (WindowManagementMode, Settings027WriteBehavior)) throws {
        let (mode, behavior) = parameters
        func text(gap: Int) -> String { "[tiling]\ndefault_strategy = \"\(mode.rawValue)\"\ngaps_outer = \(gap)\n[fx.rail]\nauto_hide = false\n" }
        let fixture = try RuntimeConfigFixture(text(gap: 6))
        defer { fixture.clean() }
        let display = powerDisplay()
        let oldFrame = Rect(x: 6, y: 6, width: 988, height: 788)
        let targetFrame = Rect(x: 7, y: 7, width: 986, height: 786)
        let window = powerWindow(1, x: oldFrame.x, y: oldFrame.y, width: oldFrame.width, height: oldFrame.height)
        let provider = PowerUserProvider(displays: [display], windows: [window])
        let writer = SettingsPrecisionWriter(provider: provider, behavior: behavior)
        let store = StageStore(path: fixture.directory.appendingPathComponent("stages.json").path)
        let intents = LayoutIntentStore(path: fixture.directory.appendingPathComponent("intents.json").path)
        let registry = WrittenFrameRegistry()
        let service = SnapshotService(
            provider: provider, frameWriter: writer, intentStore: intents, stageStore: store,
            events: fixture.events, frameRegistry: registry, configService: fixture.service
        )
        var date = Date(timeIntervalSince1970: 1_000)
        let maintainer = LayoutMaintainer(
            service: service, events: fixture.events, store: store, mouseButtonsPressed: { false },
            writtenFrames: registry,
            readFrame: { candidate in provider.snapshots.first(where: { $0.id == candidate.id })?.frame.cgRect },
            configService: fixture.service, now: { date }
        )
        #expect(maintainer.tick(cause: "command:startup").commands == 0)
        let controller = SettingsLiveApplyController(
            configService: fixture.service, stageStore: store, events: fixture.events,
            onLayoutChange: { maintainer.configurationChanged(invalidateLayoutIntents: $0) }
        )
        try fixture.replace(text(gap: 7))
        controller.applyChange(configPath: fixture.path, settingID: "tiling.gaps_outer")
        let first = maintainer.tick(cause: "command:settings")
        #expect(writer.requested == [targetFrame])
        if behavior == .knownClamp {
            #expect(first.clamped == 1)
            #expect(registry.entry(for: window.id.rawValue)?.hasRefusal == true)
        } else {
            #expect(provider.snapshots[0].frame == oldFrame)
        }
        if behavior == .animation {
            // L'application a terminé son animation après la relecture de la première écriture.
            provider.snapshots[0].frame = targetFrame
        }
        let deadline = try #require(maintainer.nextDeadline(now: date))
        #expect(deadline == date.addingTimeInterval(LayoutTolerance.refusalConfirmDelay))
        date = deadline
        // Pas de filet périodique : la reprise est armée par nextDeadline et TickScheduler.
        _ = maintainer.tick(cause: "deadline")
        let expectedAttempts = (behavior == .animation || behavior == .knownClamp) ? 1 : 2
        #expect(writer.requested.count == expectedAttempts)
        if behavior == .ignoreAlways {
            #expect(provider.snapshots[0].frame == oldFrame)
        } else if behavior != .knownClamp {
            #expect(provider.snapshots[0].frame == targetFrame)
        }
        for _ in 0..<20 {
            date = date.addingTimeInterval(LayoutTolerance.refusalConfirmDelay)
            _ = maintainer.tick(cause: "safety")
        }
        #expect(writer.requested.count == expectedAttempts)
        #expect(writer.requested.count <= LayoutTolerance.writeBudgetPerGeneration)
    }

    @Test
    func precisionWaitsForFailedDriftBackoffBeforeApplyingOnePointTarget() throws {
        func text(gap: Int) -> String { "[tiling]\ndefault_strategy = \"bsp\"\ngaps_outer = \(gap)\n[fx.rail]\nauto_hide = false\n" }
        let fixture = try RuntimeConfigFixture(text(gap: 6))
        defer { fixture.clean() }
        let left = powerDisplay("left", index: 1, x: 0)
        let right = powerDisplay("right", index: 2, x: 1000)
        let window = powerWindow(91, x: 1003, y: 6, width: 988, height: 788)
        let provider = PowerUserProvider(displays: [left, right], windows: [window])
        let writer = SettingsPrecisionWriter(provider: provider, behavior: .unknownFirst)
        let registry = WrittenFrameRegistry()
        let store = StageStore(path: fixture.directory.appendingPathComponent("stages.json").path)
        let intents = LayoutIntentStore(path: fixture.directory.appendingPathComponent("intents.json").path)
        let stageID = StageID(rawValue: "1")
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: left.id, stages: [PersistentStage(
                id: stageID, members: [PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame)]
            )]),
            PersistentStageScope(displayID: right.id, stages: [PersistentStage(id: stageID)])
        ]))
        let service = SnapshotService(
            provider: provider, frameWriter: writer, intentStore: intents, stageStore: store,
            events: fixture.events, frameRegistry: registry, configService: fixture.service
        )
        var date = Date(timeIntervalSince1970: 1000)
        let maintainer = LayoutMaintainer(
            service: service, events: fixture.events, store: store, mouseButtonsPressed: { false },
            writtenFrames: registry, configService: fixture.service, now: { date }
        )
        #expect(maintainer.tick(cause: "command:startup").failed == 1)
        #expect(writer.requested.count == 1)
        // Trois points restent dans la garde de dérive (4 points). Le cadre est maintenant
        // celui des anciennes marges : le nouveau pas d'un point exigera encore sa précision.
        provider.snapshots[0].frame.x = 1006
        let controller = SettingsLiveApplyController(
            configService: fixture.service, stageStore: store, events: fixture.events,
            onLayoutChange: { maintainer.configurationChanged(invalidateLayoutIntents: $0) }
        )
        try fixture.replace(text(gap: 7))
        controller.applyChange(configPath: fixture.path, settingID: "tiling.gaps_outer")
        for elapsed in [0.1, 1.0, 2.9] {
            date = Date(timeIntervalSince1970: 1000 + elapsed)
            #expect(maintainer.tick(cause: "safety").commands == 0)
        }
        #expect(writer.requested.count == 1)
        #expect(maintainer.nextDeadline(now: date) == Date(timeIntervalSince1970: 1003))
        date = Date(timeIntervalSince1970: 1003)
        #expect(maintainer.tick(cause: "deadline").applied == 1)
        #expect(writer.requested.count == 2)
        #expect(provider.snapshots[0].frame == Rect(x: 1007, y: 7, width: 986, height: 786))
        #expect(maintainer.tick(cause: "safety").commands == 0)
    }

    @Test
    func inactiveScopeKeepsIntentAndResumesItsSingleRetryOnReactivation() throws {
        func text(gap: Int) -> String { "[tiling]\ndefault_strategy = \"bsp\"\ngaps_outer = \(gap)\n[fx.rail]\nauto_hide = false\n" }
        let fixture = try RuntimeConfigFixture(text(gap: 6))
        defer { fixture.clean() }
        let display = powerDisplay()
        let old = Rect(x: 6, y: 6, width: 988, height: 788)
        let target = Rect(x: 7, y: 7, width: 986, height: 786)
        let a = powerWindow(1, x: old.x, y: old.y, width: old.width, height: old.height)
        var b = powerWindow(2, x: old.x, y: old.y, width: old.width, height: old.height)
        let hidden = Rect(HiddenWindowPlacement.frame(for: old.cgRect, on: display, among: [display]))
        b.frame = hidden
        let provider = PowerUserProvider(displays: [display], windows: [a, b])
        let writer = SettingsPrecisionWriter(provider: provider, behavior: .ignoreFirst)
        let registry = WrittenFrameRegistry()
        let store = StageStore(path: fixture.directory.appendingPathComponent("stages.json").path)
        let intents = LayoutIntentStore(path: fixture.directory.appendingPathComponent("intents.json").path)
        let scopeA = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let scopeB = StageScope(displayID: display.id, desktopID: scopeA.desktopID, stageID: StageID(rawValue: "2"))
        store.save(PersistentStageState(scopes: [PersistentStageScope(
            displayID: display.id, activeStageID: scopeA.stageID, stages: [
                PersistentStage(id: scopeA.stageID, members: [PersistentStageMember(windowID: a.id, bundleID: a.bundleID, title: a.title, frame: old)]),
                PersistentStage(id: scopeB.stageID, members: [PersistentStageMember(windowID: b.id, bundleID: b.bundleID, title: b.title, frame: old)])
            ]
        )]))
        let service = SnapshotService(
            provider: provider, frameWriter: writer, intentStore: intents, stageStore: store,
            events: fixture.events, frameRegistry: registry, configService: fixture.service
        )
        var date = Date(timeIntervalSince1970: 1000)
        let maintainer = LayoutMaintainer(
            service: service, events: fixture.events, store: store, mouseButtonsPressed: { false },
            writtenFrames: registry, configService: fixture.service, now: { date }
        )
        #expect(maintainer.tick(cause: "command:startup").commands == 0)
        let controller = SettingsLiveApplyController(
            configService: fixture.service, stageStore: store, events: fixture.events,
            onLayoutChange: { maintainer.configurationChanged(invalidateLayoutIntents: $0) }
        )
        try fixture.replace(text(gap: 7))
        controller.applyChange(configPath: fixture.path, settingID: "tiling.gaps_outer")
        #expect(maintainer.tick(cause: "command:settings").commands == 1)
        let savedIntent = try #require(intents.intent(for: scopeA))
        store.mutate { state in
            var scope = state.scope(displayID: display.id)
            scope.activeStageID = scopeB.stageID
            state.update(scope)
        }
        provider.focusedID = b.id
        provider.snapshots[0].frame = hidden
        provider.snapshots[1].frame = target
        for elapsed in [0.05, 0.15, 0.3, 1.0] {
            date = Date(timeIntervalSince1970: 1000 + elapsed)
            _ = maintainer.tick(cause: "safety")
            #expect(intents.intent(for: scopeA) == savedIntent)
        }
        #expect(writer.requested.count == 1)
        store.mutate { state in
            var scope = state.scope(displayID: display.id)
            scope.activeStageID = scopeA.stageID
            state.update(scope)
        }
        provider.focusedID = a.id
        provider.snapshots[0].frame = old
        provider.snapshots[1].frame = hidden
        date = Date(timeIntervalSince1970: 1001.1)
        _ = maintainer.tick(cause: "command:stage.switch")
        #expect(provider.snapshots[0].frame == target)
        #expect(writer.requested.count == 2)
        for _ in 0..<20 {
            date = date.addingTimeInterval(0.1)
            _ = maintainer.tick(cause: "safety")
        }
        #expect(writer.requested.count == 2)
    }

    @Test(arguments: [
        (WindowManagementMode.bsp, false), (.spatialBsp, false),
        (.bsp, true), (.spatialBsp, true)
    ])
    func retryDeadlineSleepsWhileScopeIsEmptyOrZoomedAndResumes(parameters: (WindowManagementMode, Bool)) throws {
        let (mode, zoomed) = parameters
        func text(gap: Int) -> String { "[tiling]\ndefault_strategy = \"\(mode.rawValue)\"\ngaps_outer = \(gap)\n[fx.rail]\nauto_hide = false\n" }
        let fixture = try RuntimeConfigFixture(text(gap: 6))
        defer { fixture.clean() }
        let display = powerDisplay()
        let old = Rect(x: 6, y: 6, width: 988, height: 788)
        let target = Rect(x: 7, y: 7, width: 986, height: 786)
        let window = powerWindow(1, x: old.x, y: old.y, width: old.width, height: old.height)
        let provider = PowerUserProvider(displays: [display], windows: [window])
        let writer = SettingsPrecisionWriter(provider: provider, behavior: .ignoreFirst)
        let registry = WrittenFrameRegistry()
        let store = StageStore(path: fixture.directory.appendingPathComponent("stages.json").path)
        let intents = LayoutIntentStore(path: fixture.directory.appendingPathComponent("intents.json").path)
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let service = SnapshotService(
            provider: provider, frameWriter: writer, intentStore: intents, stageStore: store,
            events: fixture.events, frameRegistry: registry, configService: fixture.service
        )
        var date = Date(timeIntervalSince1970: 1000)
        let maintainer = LayoutMaintainer(
            service: service, events: fixture.events, store: store, mouseButtonsPressed: { false },
            writtenFrames: registry, configService: fixture.service, now: { date }
        )
        #expect(maintainer.tick(cause: "command:startup").commands == 0)
        let controller = SettingsLiveApplyController(
            configService: fixture.service, stageStore: store, events: fixture.events,
            onLayoutChange: { maintainer.configurationChanged(invalidateLayoutIntents: $0) }
        )
        try fixture.replace(text(gap: 7))
        controller.applyChange(configPath: fixture.path, settingID: "tiling.gaps_outer")
        #expect(maintainer.tick(cause: "command:settings").commands == 1)
        #expect(maintainer.nextDeadline(now: date) == date.addingTimeInterval(0.1))
        let fullscreen = Rect(display.frame.cgRect)
        if zoomed {
            provider.snapshots[0].frame = fullscreen
            intents.save(LayoutIntent(
                scope: scope, windowIDs: [window.id], placements: [window.id: fullscreen],
                source: .command, zoomedWindowID: window.id, restorePlacements: [window.id: old]
            ))
        } else {
            // La fermeture laisse le stage actif sans fenêtre pendant une seconde.
            provider.snapshots = []
        }
        var staleDeadlines: [Date] = []
        for step in 0..<70 {
            date = Date(timeIntervalSince1970: 1000.05 + Double(step) * 0.015)
            _ = maintainer.tick(cause: "safety")
            if let deadline = maintainer.nextDeadline(now: date), deadline <= date {
                staleDeadlines.append(deadline)
            }
        }
        #expect(staleDeadlines.isEmpty, "mode=\(mode.rawValue) zoomed=\(zoomed) stale=\(staleDeadlines)")
        #expect(writer.requested.count == 1)
        if zoomed { service.removeLayoutIntent(scope: scope) }
        provider.snapshots = [window]
        date = date.addingTimeInterval(0.1)
        _ = maintainer.tick(cause: zoomed ? "command:zoom.exit" : "ax:AXWindowCreated")
        #expect(writer.requested.count == 2)
        #expect(provider.snapshots[0].frame == target)
        for _ in 0..<20 {
            date = date.addingTimeInterval(0.1)
            _ = maintainer.tick(cause: "safety")
        }
        #expect(writer.requested.count == 2)
    }

    @Test(arguments: [false, true])
    func commandBudgetAndQueuedGenerationKeepSettingsPrecisionPending(currentGenerationIsExhausted: Bool) throws {
        let fixture = try RuntimeConfigFixture("[tiling]\ndefault_strategy = \"spatialBsp\"\ngaps_outer = 6\n[fx.rail]\nauto_hide = false\n")
        defer { fixture.clean() }
        let window = powerWindow(1, x: 6, y: 6, width: 988, height: 788)
        let provider = PowerUserProvider(windows: [window])
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: fixture.directory.appendingPathComponent("stages.json").path)
        let registry = WrittenFrameRegistry()
        let generations = PlacementGeneration()
        let service = SnapshotService(
            provider: provider, frameWriter: writer, stageStore: store, events: fixture.events,
            frameRegistry: registry, configService: fixture.service
        )
        let maintainer = LayoutMaintainer(
            service: service, events: fixture.events, store: store,
            writtenFrames: registry, generations: generations,
            readFrame: { candidate in provider.snapshots.first(where: { $0.id == candidate.id })?.frame.cgRect },
            configService: fixture.service
        )
        _ = maintainer.tick(cause: "command:startup")
        let oldGeneration = generations.current
        for _ in 0..<2 {
            registry.record(windowID: window.id.rawValue, requested: window.frame.cgRect,
                            readBack: window.frame.cgRect, generation: oldGeneration, at: Date())
        }
        let controller = SettingsLiveApplyController(
            configService: fixture.service, stageStore: store, events: fixture.events,
            onLayoutChange: { maintainer.configurationChanged(invalidateLayoutIntents: $0) }
        )
        try fixture.replace("[tiling]\ndefault_strategy = \"spatialBsp\"\ngaps_outer = 7\n[fx.rail]\nauto_hide = false\n")
        controller.applyChange(configPath: fixture.path, settingID: "tiling.gaps_outer")
        let settingsGeneration = generations.current
        if currentGenerationIsExhausted {
            for _ in 0..<2 {
                registry.record(windowID: window.id.rawValue, requested: window.frame.cgRect,
                                readBack: window.frame.cgRect, generation: settingsGeneration, at: Date())
            }
        }
        let scope = StageScope(displayID: powerDisplay().id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        maintainer.noteTreeScopeApplied(TreeScopeApplication(
            scope: scope, generation: currentGenerationIsExhausted ? settingsGeneration : oldGeneration,
            windowIDs: [window.id], appliedAt: Date()
        ))
        if currentGenerationIsExhausted {
            #expect(maintainer.tick(cause: "deadline").commands == 0)
            #expect(writer.frames[window.id] == nil)
            // Le budget ne doit pas être contourné. Un événement externe légitime ouvre
            // ensuite une génération neuve ; la précision retenue applique alors le pas1.
            #expect(maintainer.tick(cause: "ax:AXWindowCreated").applied == 1)
            #expect(generations.current > settingsGeneration)
        } else {
            #expect(maintainer.tick(cause: "deadline").applied == 1)
            #expect(generations.current == settingsGeneration)
        }
        #expect(registry.entry(for: window.id.rawValue)?.generation == generations.current)
        #expect(provider.snapshots[0].frame == Rect(x: 7, y: 7, width: 986, height: 786))
    }

    @Test
    func settingsChangePreservesManualResizeDebounceAndAppliesAfterItsDeadline() throws {
        let fixture = try RuntimeConfigFixture("[tiling]\ndefault_strategy = \"bsp\"\ngaps_outer = 6\n[fx.rail]\nauto_hide = false\n")
        defer { fixture.clean() }
        let display = powerDisplay()
        let window = powerWindow(1, x: 6, y: 6, width: 988, height: 788)
        let provider = PowerUserProvider(displays: [display], windows: [window])
        let writer = PowerUserWriter(provider: provider)
        let store = StageStore(path: fixture.directory.appendingPathComponent("stages.json").path)
        let intents = LayoutIntentStore(path: fixture.directory.appendingPathComponent("intents.json").path)
        let service = SnapshotService(
            provider: provider, frameWriter: writer, intentStore: intents, stageStore: store,
            events: fixture.events, configService: fixture.service
        )
        var date = Date(timeIntervalSince1970: 1_000)
        let maintainer = LayoutMaintainer(
            service: service, events: fixture.events, store: store,
            mouseButtonsPressed: { false }, configService: fixture.service, now: { date }
        )
        _ = maintainer.tick(cause: "command:startup")
        let scope = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        intents.remove(scope: scope)
        provider.snapshots[0].frame.width = 900
        let resized = maintainer.tick(cause: "ax:AXWindowResized")
        #expect(resized.manualResizeDetected)
        #expect(resized.commands == 0)
        let controller = SettingsLiveApplyController(
            configService: fixture.service, stageStore: store, events: fixture.events,
            onLayoutChange: { maintainer.configurationChanged(invalidateLayoutIntents: $0) }
        )
        try fixture.replace("[tiling]\ndefault_strategy = \"bsp\"\ngaps_outer = 7\n[fx.rail]\nauto_hide = false\n")
        controller.applyChange(configPath: fixture.path, settingID: "tiling.gaps_outer")
        date = date.addingTimeInterval(0.1)
        #expect(maintainer.tick(cause: "command:settings").commands == 0)
        date = date.addingTimeInterval(0.24)
        #expect(maintainer.tick(cause: "safety").commands == 0)
        date = date.addingTimeInterval(0.02)
        #expect(maintainer.tick(cause: "deadline:manual_resize").applied == 1)
        #expect(writer.frames[window.id] == Rect(x: 7, y: 7, width: 986, height: 786))
        #expect(maintainer.tick(cause: "safety").commands == 0)
    }

    @Test
    func activePathSupportsSymlinkAndRejectsOtherFileOrInvalidConfig() throws {
        let fixture = try RuntimeConfigFixture("[tiling]\ngaps_inner = 10\n")
        defer { fixture.clean() }
        var requests = 0
        let controller = SettingsLiveApplyController(configService: fixture.service, onLayoutChange: { _ in requests += 1 })
        let link = fixture.directory.appendingPathComponent("alias.toml")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: fixture.path))
        try fixture.replace("[tiling]\ngaps_inner = 12\n")
        controller.applyChange(configPath: fixture.directory.appendingPathComponent("other.toml").path, settingID: "*")
        #expect(requests == 0)
        controller.applyChange(configPath: link.path, settingID: "tiling.gaps_inner")
        #expect(requests == 1)
        controller.applyChange(configPath: link.path, settingID: "tiling.gaps_inner")
        #expect(requests == 1)
        try "[tiling]\ngaps_inner = \"invalid\"\n".write(toFile: fixture.path, atomically: true, encoding: .utf8)
        #expect(fixture.service.reload(path: fixture.path).status == .failedKeepingPrevious)
        controller.applyChange(configPath: fixture.path, settingID: "*")
        #expect(requests == 1)
    }

    @Test
    func desktopsAndBorderChangesApplyWhileRailFontsDoNotRetile() throws {
        let fixture = try RuntimeConfigFixture("[desktops]\ncount = 10\n")
        defer { fixture.clean() }
        var requests: [Bool] = []
        var borders = 0
        let controller = SettingsLiveApplyController(
            configService: fixture.service,
            onLayoutChange: { requests.append($0) }, onBorderChange: { borders += 1 }
        )
        try fixture.replace("[desktops]\ncount = 4\n[fx.borders]\nthickness = 3\n")
        controller.applyChange(configPath: fixture.path, settingID: "*")
        #expect(requests == [false])
        #expect(borders == 1)
        try fixture.replace("[desktops]\ncount = 4\n[fx.borders]\nthickness = 3\n[fx.rail.stage_labels]\nfont_size = 24\n")
        controller.applyChange(configPath: fixture.path, settingID: "fx.rail.stage_labels.font_size")
        #expect(requests == [false])
        #expect(borders == 1)
        try fixture.replace("[desktops]\ncount = 4\n[fx.borders]\nthickness = 3\n[fx.rail]\nwidth = 220\n")
        controller.applyChange(configPath: fixture.path, settingID: "fx.rail.width")
        #expect(requests == [false, true])
    }

    @Test
    func geometryInvalidationKeepsZoomAndPersistentState() throws {
        let fixture = try RuntimeConfigFixture("")
        defer { fixture.clean() }
        let store = StageStore(path: fixture.directory.appendingPathComponent("stages.json").path)
        let intents = LayoutIntentStore(path: fixture.directory.appendingPathComponent("intents.json").path)
        let scope = StageScope(displayID: DisplayID(rawValue: "screen"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let zoomScope = StageScope(displayID: scope.displayID, desktopID: scope.desktopID, stageID: StageID(rawValue: "2"))
        let id = WindowID(rawValue: 1)
        let frame = Rect(x: 0, y: 0, width: 100, height: 100)
        intents.save(LayoutIntent(scope: scope, windowIDs: [id], placements: [id: frame]))
        let zoom = LayoutIntent(scope: zoomScope, windowIDs: [id], placements: [id: frame], zoomedWindowID: id, restorePlacements: [id: frame])
        intents.save(zoom)
        let previousState = store.state()
        let service = SnapshotService(intentStore: intents, stageStore: store, configService: fixture.service)
        let maintainer = LayoutMaintainer(service: service, events: fixture.events, store: store, configService: fixture.service)
        maintainer.configurationChanged(invalidateLayoutIntents: false)
        #expect(intents.intent(for: scope) != nil)
        maintainer.configurationChanged(invalidateLayoutIntents: true)
        #expect(intents.intent(for: scope) == nil)
        #expect(intents.intent(for: zoomScope) == zoom)
        #expect(store.state() == previousState)
    }
}

enum Settings027WriteBehavior: Equatable { case ignoreFirst, ignoreAlways, animation, unknownFirst, knownClamp }

private final class SettingsPrecisionWriter: WindowFrameWriting, @unchecked Sendable {
    let provider: PowerUserProvider
    let behavior: Settings027WriteBehavior
    private(set) var requested: [Rect] = []

    init(provider: PowerUserProvider, behavior: Settings027WriteBehavior) {
        self.provider = provider
        self.behavior = behavior
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        requested.append(Rect(frame))
        if behavior == .unknownFirst, requested.count == 1 { return nil }
        if behavior == .ignoreAlways || (behavior != .knownClamp && requested.count == 1) {
            return provider.snapshots.first(where: { $0.id == window.id })?.frame.cgRect
        }
        var actual = frame
        if behavior == .knownClamp { actual.size.width += 30 }
        for index in provider.snapshots.indices where provider.snapshots[index].id == window.id {
            provider.snapshots[index].frame = Rect(actual)
        }
        return actual
    }
}

private struct RuntimeConfigFixture {
    let directory: URL
    let path: String
    let service: ConfigReloadService
    let events: EventLog

    init(_ text: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-settings-runtime-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        path = directory.appendingPathComponent("roadies.toml").path
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        events = EventLog(path: directory.appendingPathComponent("events.jsonl").path)
        service = ConfigReloadService(activeConfig: try RoadieConfigLoader.load(from: path), activePath: path, eventLog: events)
    }

    func replace(_ text: String) throws {
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        #expect(service.reload(path: path).status == .applied)
    }

    func clean() { try? FileManager.default.removeItem(at: directory) }
}

@MainActor
private final class SettingsRuntimeTimer {
    var now = Date(timeIntervalSince1970: 1_000)
    private var pending: [(id: UUID, due: Date, action: @MainActor () -> Void)] = []

    func schedule(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> () -> Void {
        let id = UUID()
        pending.append((id, now.addingTimeInterval(delay), action))
        return { [weak self] in self?.pending.removeAll { $0.id == id } }
    }

    func advance(by seconds: TimeInterval) {
        let target = now.addingTimeInterval(seconds)
        while let next = pending.filter({ $0.due <= target }).min(by: { $0.due < $1.due }) {
            pending.removeAll { $0.id == next.id }
            now = max(now, next.due)
            next.action()
        }
        now = target
    }
}
