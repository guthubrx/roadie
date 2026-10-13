import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon
import RoadieStages

/// Session 022, round 2, lot D : R1-05 (règles de la configuration réellement active après
/// `config reload`), R1-07 (critère `is_floating` des règles de placement).
@Suite
struct Audit022R2LotDTests {
    // MARK: R1-05

    @Test
    func ruleEngineFollowsConfigReloadedFromAnotherFile() throws {
        let files = LotDConfigFiles()
        defer { files.cleanUp() }
        try files.write(rule: "rule-a", to: files.first)
        try files.write(rule: "rule-b", to: files.second)
        let configService = ConfigReloadService(activePath: files.first, eventLog: EventLog(path: files.configEvents))
        let harness = LotDRuleHarness(window: lotDWindow(80, app: "Terminal"), configService: configService)
        defer { harness.cleanUp() }

        _ = harness.maintainer.tick()
        #expect(harness.events().contains("\"ruleID\":\"rule-a\""))

        // `roadie config reload <autre fichier>` passe par le daemon et recharge ce service.
        // Les règles s'appliquent aux fenêtres nouvellement observées : une nouvelle fenêtre arrive.
        #expect(configService.reload(path: files.second).status == .applied)
        harness.provider.windowList.append(lotDWindow(180, app: "Terminal"))
        _ = harness.maintainer.tick()

        #expect(harness.events().contains("\"ruleID\":\"rule-b\""))
    }

    @Test
    func ruleEngineFollowsEditOfActiveConfigFile() throws {
        let files = LotDConfigFiles()
        defer { files.cleanUp() }
        try files.write(rule: "rule-a", to: files.first)
        let configService = ConfigReloadService(activePath: files.first, eventLog: EventLog(path: files.configEvents))
        let harness = LotDRuleHarness(window: lotDWindow(81, app: "Terminal"), configService: configService)
        defer { harness.cleanUp() }

        _ = harness.maintainer.tick()
        try files.write(rule: "rule-edited", to: files.first)
        harness.provider.windowList.append(lotDWindow(181, app: "Terminal"))
        _ = harness.maintainer.tick()

        #expect(harness.events().contains("\"ruleID\":\"rule-edited\""))
    }

    // MARK: R1-07 - classification pure

    @Test
    func floatingClassificationCoversEveryWindowKind() throws {
        let display = DisplayID(rawValue: "display-main")
        let bsp = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "tiled"))
        let float = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "free"))
        var state = RoadieState()
        try state.createStage(id: bsp.stageID, name: "Tiled", mode: .bsp, in: display, desktopID: bsp.desktopID)
        try state.createStage(id: float.stageID, name: "Free", mode: .float, in: display, desktopID: float.desktopID)
        let tiled = lotDWindow(90, app: "Terminal")
        var unmanaged = lotDWindow(91, app: "Finder")
        unmanaged.isTileCandidate = false
        let pin = PersistentWindowPin(
            windowID: tiled.id, homeScope: bsp, pinScope: .desktop,
            bundleID: tiled.bundleID, title: tiled.title, lastFrame: tiled.frame
        )

        // Membre d'une stage en mosaïque : non flottant.
        #expect(LayoutMaintainer.ruleFloatingState(of: ScopedWindowSnapshot(window: tiled, scope: bsp), in: state) == false)
        // Stage en mode float : flottant.
        #expect(LayoutMaintainer.ruleFloatingState(of: ScopedWindowSnapshot(window: tiled, scope: float), in: state) == true)
        // Fenêtre épinglée : hors de la mosaïque, flottante.
        #expect(LayoutMaintainer.ruleFloatingState(of: ScopedWindowSnapshot(window: tiled, scope: bsp, pin: pin), in: state) == true)
        // Non gérée par le tiling (floating_bundles, règle `floating`, popup) : flottante.
        #expect(LayoutMaintainer.ruleFloatingState(of: ScopedWindowSnapshot(window: unmanaged, scope: nil), in: state) == true)
        // Membre en attente de son écran débranché : état inconnu, aucune valeur ne correspond.
        #expect(LayoutMaintainer.ruleFloatingState(of: ScopedWindowSnapshot(window: tiled, scope: nil), in: state) == nil)
    }

    // MARK: R1-07 - règles de placement

    @Test
    func isFloatingFalseRuleMatchesTiledWindow() {
        let harness = LotDRuleHarness(
            window: lotDWindow(82, app: "Terminal"),
            rule: lotDPlacementRule(isFloating: false)
        )
        defer { harness.cleanUp() }

        _ = harness.maintainer.tick()

        #expect(harness.store.state().stageScope(for: WindowID(rawValue: 82))?.stageID == StageID(rawValue: "Dev"))
        #expect(harness.events().contains("\"type\":\"rule.placement_applied\""))
    }

    @Test
    func isFloatingTrueRuleIgnoresTiledWindow() {
        let harness = LotDRuleHarness(
            window: lotDWindow(83, app: "Terminal"),
            rule: lotDPlacementRule(isFloating: true)
        )
        defer { harness.cleanUp() }

        _ = harness.maintainer.tick()

        #expect(harness.store.state().stageScope(for: WindowID(rawValue: 83))?.stageID == StageID(rawValue: "1"))
        #expect(!harness.events().contains("\"type\":\"rule.placement_applied\""))
    }

    @Test
    func isFloatingTrueRuleMatchesWindowOfFloatStage() {
        let window = lotDWindow(84, app: "Terminal")
        let harness = LotDRuleHarness(
            window: window,
            rule: lotDPlacementRule(isFloating: true),
            stageMode: .float
        )
        defer { harness.cleanUp() }

        _ = harness.maintainer.tick()

        #expect(harness.store.state().stageScope(for: window.id)?.stageID == StageID(rawValue: "Dev"))
        #expect(harness.events().contains("\"type\":\"rule.placement_applied\""))
    }

    @Test
    func isFloatingFalseRuleIgnoresWindowOfFloatStage() {
        let window = lotDWindow(85, app: "Terminal")
        let harness = LotDRuleHarness(
            window: window,
            rule: lotDPlacementRule(isFloating: false),
            stageMode: .float
        )
        defer { harness.cleanUp() }

        _ = harness.maintainer.tick()

        #expect(harness.store.state().stageScope(for: window.id)?.stageID == StageID(rawValue: "1"))
        #expect(!harness.events().contains("\"type\":\"rule.placement_applied\""))
    }

    @Test(arguments: [true, false])
    func isFloatingRuleNeverMovesWindowWaitingForUnpluggedDisplay(isFloating: Bool) {
        let main = lotDDisplay("display-main")
        let unplugged = DisplayID(rawValue: "display-unplugged")
        let window = lotDWindow(86, app: "Terminal")
        let harness = LotDRuleHarness(
            displays: [main],
            window: window,
            rule: lotDPlacementRule(isFloating: isFloating),
            persistedScopes: [
                PersistentStageScope(displayID: main.id),
                lotDScope(unplugged, mode: .bsp, windows: [window]),
            ]
        )
        defer { harness.cleanUp() }

        _ = harness.maintainer.tick()

        // Le membre garde sa stage sur l'écran débranché (scope nil transitoire, FR-037).
        #expect(harness.store.state().stageScope(for: window.id)?.displayID == unplugged)
        #expect(!harness.events().contains("\"type\":\"rule.placement_applied\""))
    }
}

// MARK: - Outils

private struct LotDConfigFiles {
    let directory: URL
    var first: String { directory.appendingPathComponent("first/roadie.toml").path }
    var second: String { directory.appendingPathComponent("second/roadie.toml").path }
    var configEvents: String { directory.appendingPathComponent("config-events.jsonl").path }

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("audit022-r2-d-config-\(UUID().uuidString)")
    }

    func write(rule id: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let toml = """
        [[rules]]
        id = "\(id)"

        [rules.match]
        app = "Terminal"

        [rules.action]
        scratchpad = "\(id)"
        """
        try toml.write(to: url, atomically: false, encoding: .utf8)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct LotDRuleHarness {
    let provider: LotDProvider
    let store: StageStore
    let maintainer: LayoutMaintainer
    let paths: [String]

    /// `rule` fourni : moteur figé ; sinon moteur relu dans `configService`.
    init(
        displays: [DisplaySnapshot] = [lotDDisplay("display-main")],
        window: WindowSnapshot,
        rule: WindowRule? = nil,
        configService: ConfigReloadService? = nil,
        stageMode: WindowManagementMode = .bsp,
        persistedScopes: [PersistentStageScope]? = nil
    ) {
        let stagePath = lotDTempPath("audit022-r2-d-stages")
        let intentPath = lotDTempPath("audit022-r2-d-intents")
        let eventPath = lotDTempPath("audit022-r2-d-events")
        paths = [stagePath, intentPath, eventPath]
        store = StageStore(path: stagePath)
        store.save(PersistentStageState(scopes: persistedScopes ?? displays.map {
            lotDScope($0.id, mode: stageMode, windows: [window])
        }))
        provider = LotDProvider(displays: displays, windows: [window])
        let service = SnapshotService(
            provider: provider,
            frameWriter: LotDWriter(),
            config: RoadieConfig(),
            intentStore: LayoutIntentStore(path: intentPath),
            stageStore: store
        )
        maintainer = LayoutMaintainer(
            service: service,
            events: EventLog(path: eventPath),
            ruleEngine: rule.map { WindowRuleEngine(rules: [$0]) },
            store: store,
            configService: configService ?? ConfigReloadService(activeConfig: RoadieConfig())
        )
    }

    func events() -> String {
        (try? String(contentsOfFile: paths[2], encoding: .utf8)) ?? ""
    }

    func cleanUp() {
        paths.forEach { try? FileManager.default.removeItem(atPath: $0) }
    }
}

private final class LotDProvider: SystemSnapshotProviding, @unchecked Sendable {
    let displayList: [DisplaySnapshot]
    var windowList: [WindowSnapshot]

    init(displays: [DisplaySnapshot], windows: [WindowSnapshot]) {
        self.displayList = displays
        self.windowList = windows
    }

    func permissions(prompt: Bool) -> PermissionSnapshot { PermissionSnapshot(accessibilityTrusted: true) }
    func displays() -> [DisplaySnapshot] { displayList }
    func windows() -> [WindowSnapshot] { windowList }
}

private final class LotDWriter: WindowFrameWriting, @unchecked Sendable {
    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? { frame }
    func focus(_ window: WindowSnapshot) -> Bool { true }
}

private func lotDTempPath(_ name: String) -> String {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).json").path
}

private func lotDDisplay(_ id: String) -> DisplaySnapshot {
    DisplaySnapshot(
        id: DisplayID(rawValue: id),
        index: 1,
        name: "Main",
        frame: Rect(x: 0, y: 0, width: 1000, height: 500),
        visibleFrame: Rect(x: 0, y: 0, width: 1000, height: 500),
        isMain: true
    )
}

private func lotDWindow(_ id: UInt32, app: String) -> WindowSnapshot {
    WindowSnapshot(
        id: WindowID(rawValue: id),
        pid: Int32(id + 100),
        appName: app,
        bundleID: "com.example.\(app.lowercased())",
        title: app,
        frame: Rect(x: 100, y: 100, width: 400, height: 300),
        isOnScreen: true,
        isTileCandidate: true
    )
}

private func lotDPlacementRule(isFloating: Bool) -> WindowRule {
    WindowRule(
        id: "terminal-floating-\(isFloating)",
        match: RuleMatch(app: "Terminal", isFloating: isFloating),
        action: RuleAction(assignStage: "Dev")
    )
}

private func lotDScope(_ displayID: DisplayID, mode: WindowManagementMode, windows: [WindowSnapshot]) -> PersistentStageScope {
    PersistentStageScope(displayID: displayID, activeStageID: StageID(rawValue: "1"), stages: [
        PersistentStage(id: StageID(rawValue: "1"), mode: mode, members: windows.map {
            PersistentStageMember(windowID: $0.id, bundleID: $0.bundleID, title: $0.title, frame: $0.frame)
        }),
    ])
}
