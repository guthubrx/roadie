import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon

/// Session 022, lot B : REL-007 (rôle AX des règles), REL-008 (placement différé retenté),
/// REL-009 (intents de plusieurs écrans), PERF-004 (réparation des voisines inchangée).
@Suite
struct Audit022LotBTests {
    // MARK: REL-007

    @Test
    func rulePlacementMatchesWindowRoleAndSubrole() {
        let harness = LotBRuleHarness(
            window: lotBWindow(70, app: "Terminal", role: "AXWindow", subrole: "AXStandardWindow"),
            rule: WindowRule(
                id: "terminal-dev",
                match: RuleMatch(app: "Terminal", role: "AXWindow", subrole: "AXStandardWindow"),
                action: RuleAction(assignStage: "Dev")
            )
        )
        defer { harness.cleanUp() }

        _ = harness.maintainer.tick()

        #expect(harness.store.state().stageScope(for: WindowID(rawValue: 70))?.stageID == StageID(rawValue: "Dev"))
        #expect(harness.events().contains("\"type\":\"rule.placement_applied\""))
    }

    @Test
    func rulePlacementIgnoresWindowWithAnotherRole() {
        let harness = LotBRuleHarness(
            window: lotBWindow(71, app: "Terminal", role: "AXWindow", subrole: "AXStandardWindow"),
            rule: WindowRule(
                id: "terminal-sheet",
                match: RuleMatch(app: "Terminal", role: "AXSheet"),
                action: RuleAction(assignStage: "Dev")
            )
        )
        defer { harness.cleanUp() }

        _ = harness.maintainer.tick()

        #expect(harness.store.state().stageScope(for: WindowID(rawValue: 71))?.stageID == StageID(rawValue: "1"))
        #expect(!harness.events().contains("\"type\":\"rule.placement_applied\""))
    }

    // MARK: REL-008

    @Test
    func deferredPlacementIsRetriedWhenTargetDisplayAppears() {
        let main = lotBDisplay("display-main", name: "Main", x: 0)
        let external = lotBDisplay("display-external", name: "External", x: 1000)
        let window = lotBWindow(72, app: "Word", frame: Rect(x: 100, y: 100, width: 400, height: 300))
        let clock = LotBClock()
        let harness = LotBRuleHarness(
            displays: [main],
            window: window,
            rule: WindowRule(
                id: "word-external",
                match: RuleMatch(app: "Word"),
                action: RuleAction(assignDisplay: "External", assignStage: "Docs")
            ),
            now: { clock.now }
        )
        defer { harness.cleanUp() }

        _ = harness.maintainer.tick()
        #expect(harness.store.state().stageScope(for: window.id)?.displayID == main.id)
        #expect(harness.events().contains("\"type\":\"rule.placement_deferred\""))

        // Écran branché : une passe de stabilisation, puis la passe suivante après le délai.
        harness.provider.displayList = [main, external]
        clock.advance(by: 0.5)
        _ = harness.maintainer.tick()
        clock.advance(by: LayoutTolerance.displayTopologySettle + 0.5)
        _ = harness.maintainer.tick()

        #expect(harness.store.state().stageScope(for: window.id) == StageScope(
            displayID: external.id,
            desktopID: DesktopID(rawValue: 1),
            stageID: StageID(rawValue: "Docs")
        ))
        #expect(harness.events().contains("\"type\":\"rule.placement_applied\""))
    }

    @Test
    func placedRuleIsNotReappliedAfterDeferredRetry() {
        let main = lotBDisplay("display-main", name: "Main", x: 0)
        let external = lotBDisplay("display-external", name: "External", x: 1000)
        let window = lotBWindow(73, app: "Word", frame: Rect(x: 100, y: 100, width: 400, height: 300))
        let clock = LotBClock()
        let harness = LotBRuleHarness(
            displays: [main],
            window: window,
            rule: WindowRule(
                id: "word-external",
                match: RuleMatch(app: "Word"),
                action: RuleAction(assignDisplay: "External", assignStage: "Docs")
            ),
            now: { clock.now }
        )
        defer { harness.cleanUp() }

        _ = harness.maintainer.tick()
        harness.provider.displayList = [main, external]
        clock.advance(by: 0.5)
        _ = harness.maintainer.tick()
        clock.advance(by: LayoutTolerance.displayTopologySettle + 0.5)
        _ = harness.maintainer.tick()

        // Déplacement manuel après le placement : la règle ne le défait pas.
        harness.store.mutate { state in
            for index in state.scopes.indices {
                state.scopes[index].remove(windowID: window.id)
            }
            var scope = state.scope(displayID: main.id)
            scope.assign(window: window, to: StageID(rawValue: "1"))
            state.update(scope)
        }
        clock.advance(by: 0.5)
        _ = harness.maintainer.tick()

        #expect(harness.store.state().stageScope(for: window.id)?.displayID == main.id)
    }

    // MARK: REL-009

    @Test
    func layoutIntentsAreSavedForEveryDisplayWrittenInTheSamePass() {
        let displayA = lotBDisplay("display-a", name: "A", x: 0)
        let displayB = lotBDisplay("display-b", name: "B", x: 1000)
        let windows = [
            lotBWindow(1, app: "A1", frame: Rect(x: 10, y: 10, width: 300, height: 300)),
            lotBWindow(2, app: "A2", frame: Rect(x: 60, y: 60, width: 300, height: 300)),
            lotBWindow(3, app: "B1", frame: Rect(x: 1010, y: 10, width: 300, height: 300)),
            lotBWindow(4, app: "B2", frame: Rect(x: 1060, y: 60, width: 300, height: 300)),
        ]
        let stagePath = lotBTempPath("audit022-b-intents-stages")
        let intentPath = lotBTempPath("audit022-b-intents")
        let eventPath = lotBTempPath("audit022-b-intents-events")
        defer {
            for path in [stagePath, intentPath, eventPath] { try? FileManager.default.removeItem(atPath: path) }
        }
        let scopeA = StageScope(displayID: displayA.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let scopeB = StageScope(displayID: displayB.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [
            lotBScope(displayA.id, mode: .bsp, windows: Array(windows[0...1])),
            lotBScope(displayB.id, mode: .bsp, windows: Array(windows[2...3])),
        ], activeDisplayID: displayA.id))
        let intentStore = LayoutIntentStore(path: intentPath)
        let provider = LotBProvider(displays: [displayA, displayB], windows: windows)
        let service = SnapshotService(
            provider: provider,
            frameWriter: LotBRecordingWriter(),
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .bsp, gapsOuter: 0, gapsInner: 10)),
            intentStore: intentStore,
            stageStore: stageStore
        )
        let maintainer = LayoutMaintainer(service: service, events: EventLog(path: eventPath), store: stageStore)

        let tick = maintainer.tick()

        #expect(tick.applied == 4)
        #expect(intentStore.intent(for: scopeA).map { Set($0.placements.keys) } == [WindowID(rawValue: 1), WindowID(rawValue: 2)])
        #expect(intentStore.intent(for: scopeB).map { Set($0.placements.keys) } == [WindowID(rawValue: 3), WindowID(rawValue: 4)])
    }

    // MARK: PERF-004

    /// Fige les cadres demandés par la réparation des voisines (stage bsp de 5 fenêtres, la
    /// deuxième refuse de rétrécir). Valeurs relevées avant le correctif.
    @Test
    func clampedSiblingRepairKeepsRequestedFrames() {
        let display = DisplaySnapshot(
            id: DisplayID(rawValue: "display-a"),
            index: 1,
            name: "A",
            frame: Rect(x: 0, y: 0, width: 2048, height: 1280),
            visibleFrame: Rect(x: 0, y: 0, width: 2048, height: 1280),
            isMain: true
        )
        let windows = (1...5).map { id in
            lotBWindow(UInt32(id), app: "App\(id)", frame: Rect(x: Double(id * 40), y: Double(id * 30), width: 600, height: 500))
        }
        let writer = LotBRecordingWriter(actualFrames: [
            WindowID(rawValue: 2): Rect(x: 0, y: 0, width: 1400, height: 1280),
        ])
        let stagePath = lotBTempPath("audit022-b-repair-stages")
        let intentPath = lotBTempPath("audit022-b-repair-intents")
        let eventPath = lotBTempPath("audit022-b-repair-events")
        defer {
            for path in [stagePath, intentPath, eventPath] { try? FileManager.default.removeItem(atPath: path) }
        }
        let stageStore = StageStore(path: stagePath)
        stageStore.save(PersistentStageState(scopes: [lotBScope(display.id, mode: .bsp, windows: windows)], activeDisplayID: display.id))
        let service = SnapshotService(
            provider: LotBProvider(displays: [display], windows: windows),
            frameWriter: writer,
            config: RoadieConfig(tiling: TilingConfig(defaultStrategy: .bsp, gapsOuter: 0, gapsInner: 10)),
            intentStore: LayoutIntentStore(path: intentPath),
            stageStore: stageStore
        )
        let maintainer = LayoutMaintainer(service: service, events: EventLog(path: eventPath), store: stageStore)

        _ = maintainer.tick()
        let events = (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""

        #expect(events.contains("\"type\":\"layout_clamped_scope_repaired\""))
        #expect(writer.requestOrder == LotBExpected.repairRequestOrder)
        #expect(writer.requestedFrames == LotBExpected.repairRequestedFrames)
    }
}

private enum LotBExpected {
    /// Plan initial (1 à 5), puis réparation des seules voisines dans l'ordre de la stage.
    static let repairRequestOrder: [WindowID] = [1, 2, 3, 4, 5, 1, 3, 4, 5].map { WindowID(rawValue: $0) }
    static let repairRequestedFrames: [WindowID: Rect] = [
        WindowID(rawValue: 1): Rect(x: 1410, y: 0, width: 314, height: 635),
        WindowID(rawValue: 2): Rect(x: 0, y: 645, width: 1019, height: 635),
        WindowID(rawValue: 3): Rect(x: 1734, y: 0, width: 314, height: 635),
        WindowID(rawValue: 4): Rect(x: 1410, y: 645, width: 314, height: 635),
        WindowID(rawValue: 5): Rect(x: 1734, y: 645, width: 314, height: 635),
    ]
}

// MARK: - Outils

private final class LotBClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000_000)
    func advance(by seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

private final class LotBProvider: SystemSnapshotProviding, @unchecked Sendable {
    var displayList: [DisplaySnapshot]
    var windowList: [WindowSnapshot]

    init(displays: [DisplaySnapshot], windows: [WindowSnapshot]) {
        self.displayList = displays
        self.windowList = windows
    }

    func permissions(prompt: Bool) -> PermissionSnapshot { PermissionSnapshot(accessibilityTrusted: true) }
    func displays() -> [DisplaySnapshot] { displayList }
    func windows() -> [WindowSnapshot] { windowList }
}

private final class LotBRecordingWriter: WindowFrameWriting, @unchecked Sendable {
    private let actualFrames: [WindowID: Rect]
    private(set) var requestedFrames: [WindowID: Rect] = [:]
    private(set) var requestOrder: [WindowID] = []

    init(actualFrames: [WindowID: Rect] = [:]) {
        self.actualFrames = actualFrames
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        requestedFrames[window.id] = Rect(frame)
        requestOrder.append(window.id)
        return actualFrames[window.id]?.cgRect ?? frame
    }

    func focus(_ window: WindowSnapshot) -> Bool { true }
}

private struct LotBRuleHarness {
    let provider: LotBProvider
    let store: StageStore
    let maintainer: LayoutMaintainer
    let stagePath: String
    let eventPath: String

    init(
        displays: [DisplaySnapshot] = [lotBDisplay("display-main", name: "Main", x: 0)],
        window: WindowSnapshot,
        rule: WindowRule,
        now: @escaping () -> Date = Date.init
    ) {
        stagePath = lotBTempPath("audit022-b-rule-stages")
        eventPath = lotBTempPath("audit022-b-rule-events")
        store = StageStore(path: stagePath)
        store.save(PersistentStageState(scopes: displays.map { PersistentStageScope(displayID: $0.id) }))
        provider = LotBProvider(displays: displays, windows: [window])
        let service = SnapshotService(provider: provider, frameWriter: LotBRecordingWriter(), stageStore: store)
        maintainer = LayoutMaintainer(
            service: service,
            events: EventLog(path: eventPath),
            ruleEngine: WindowRuleEngine(rules: [rule]),
            store: store,
            now: now
        )
    }

    func events() -> String {
        (try? String(contentsOfFile: eventPath, encoding: .utf8)) ?? ""
    }

    func cleanUp() {
        try? FileManager.default.removeItem(atPath: stagePath)
        try? FileManager.default.removeItem(atPath: eventPath)
    }
}

private func lotBTempPath(_ name: String) -> String {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).json").path
}

private func lotBDisplay(_ id: String, name: String, x: Double) -> DisplaySnapshot {
    DisplaySnapshot(
        id: DisplayID(rawValue: id),
        index: x == 0 ? 1 : 2,
        name: name,
        frame: Rect(x: x, y: 0, width: 1000, height: 500),
        visibleFrame: Rect(x: x, y: 0, width: 1000, height: 500),
        isMain: x == 0
    )
}

private func lotBWindow(
    _ id: UInt32,
    app: String,
    frame: Rect = Rect(x: 100, y: 100, width: 400, height: 300),
    role: String? = nil,
    subrole: String? = nil
) -> WindowSnapshot {
    WindowSnapshot(
        id: WindowID(rawValue: id),
        pid: Int32(id + 100),
        appName: app,
        bundleID: "com.example.\(app.lowercased())",
        title: app,
        frame: frame,
        isOnScreen: true,
        isTileCandidate: true,
        subrole: subrole,
        role: role
    )
}

private func lotBScope(_ displayID: DisplayID, mode: WindowManagementMode, windows: [WindowSnapshot]) -> PersistentStageScope {
    PersistentStageScope(displayID: displayID, activeStageID: StageID(rawValue: "1"), stages: [
        PersistentStage(id: StageID(rawValue: "1"), mode: mode, members: windows.map {
            PersistentStageMember(windowID: $0.id, bundleID: $0.bundleID, title: $0.title, frame: $0.frame)
        }),
    ])
}
