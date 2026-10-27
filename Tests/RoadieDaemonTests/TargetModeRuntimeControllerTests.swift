import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieStages
@testable import RoadieDaemon

@Suite
struct TargetModeRuntimeControllerTests {
    @Test(arguments: [RuleChoice.later, .never]) @MainActor
    func ruleChoiceReportsCorruptMemoryInsteadOfSuccess(_ choice: RuleChoice) throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-rule-choice-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let fixture = RuleChoiceFixture(sandbox: sandbox)
        let invalid = Data("{mémoire abîmée".utf8)
        try invalid.write(to: fixture.memory.url)
        fixture.controller.handle(TargetModeRuntimeCommand(name: "targets.search"))
        let launcher = try #require(fixture.presenter.searchLauncher)

        let result = launcher.ruleChoice(fixture.suggestion, choice)

        #expect(!result.changed)
        #expect(result.error == "rule_choice_not_saved")
        #expect(fixture.notices.messages == ["Impossible d'enregistrer le choix de règle."])
        #expect(try Data(contentsOf: fixture.memory.url) == invalid)
        let journal = try String(contentsOf: fixture.eventURL, encoding: .utf8)
        #expect(journal.contains("launcher.rule_choice_failed"))
        #expect(!journal.contains("\"launcher.rule_choice\""))
    }

    @Test(arguments: [RuleChoice.later, .never]) @MainActor
    func ruleChoicePersistsBeforeReportingSuccess(_ choice: RuleChoice) throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-rule-choice-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let fixture = RuleChoiceFixture(sandbox: sandbox)
        fixture.controller.handle(TargetModeRuntimeCommand(name: "targets.search"))
        let launcher = try #require(fixture.presenter.searchLauncher)
        let before = Date()

        let result = launcher.ruleChoice(fixture.suggestion, choice)

        #expect(result.changed && result.error == nil)
        #expect(fixture.notices.messages.isEmpty)
        let until = try #require(fixture.memory.load().declined[fixture.suggestion.declineKey])
        if choice == .never { #expect(until == .distantFuture) }
        else { #expect(until >= before.addingTimeInterval(23 * 3600) && until <= before.addingTimeInterval(25 * 3600)) }
        let journal = try String(contentsOf: fixture.eventURL, encoding: .utf8)
        #expect(journal.contains("\"launcher.rule_choice\""))
        #expect(!journal.contains("launcher.rule_choice_failed"))
    }

    @Test
    func commandRoundTripsThroughDistributedNotificationPayload() throws {
        let command = TargetModeRuntimeCommand(name: "targets.interactive", arguments: [
            "source": "all",
            "includeAppTargets": "true",
            "duration": "10"
        ])

        let parsed = try #require(TargetModeRuntimeCommand(userInfo: command.userInfo))

        #expect(parsed.name == "targets.interactive")
        #expect(parsed.string("source") == "all")
        #expect(parsed.bool("includeAppTargets"))
        #expect(parsed.double("duration") == 10)
    }

    @Test
    func commandRejectsMissingCommandName() {
        #expect(TargetModeRuntimeCommand(userInfo: ["source": "all"]) == nil)
    }

    @Test
    func gridFocusPickerPrefersTopmostWindowContainingCellCenter() {
        let large = ScopedWindowSnapshot(window: WindowSnapshot(
            id: WindowID(rawValue: 10),
            pid: 100,
            appName: "Large",
            bundleID: "large",
            title: "Large",
            frame: Rect(x: 100, y: 100, width: 500, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        ), scope: nil)
        let small = ScopedWindowSnapshot(window: WindowSnapshot(
            id: WindowID(rawValue: 20),
            pid: 200,
            appName: "Small",
            bundleID: "small",
            title: "Small",
            frame: Rect(x: 140, y: 140, width: 80, height: 80),
            isOnScreen: true,
            isTileCandidate: true
        ), scope: nil)
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [],
            windows: [large, small],
            state: RoadieState()
        )

        let target = GridFocusPicker.targetWindow(intersectingAXFrame: CGRect(x: 120, y: 120, width: 140, height: 140), in: snapshot)

        #expect(target?.window.id == large.window.id)
    }

    @Test
    func gridFocusPickerFallsBackToTopmostIntersectingWindowWhenCenterIsEmpty() {
        let top = ScopedWindowSnapshot(window: WindowSnapshot(
            id: WindowID(rawValue: 30),
            pid: 300,
            appName: "Top",
            bundleID: "top",
            title: "Top",
            frame: Rect(x: 100, y: 100, width: 100, height: 100),
            isOnScreen: true,
            isTileCandidate: true
        ), scope: nil)
        let bottom = ScopedWindowSnapshot(window: WindowSnapshot(
            id: WindowID(rawValue: 40),
            pid: 400,
            appName: "Bottom",
            bundleID: "bottom",
            title: "Bottom",
            frame: Rect(x: 110, y: 110, width: 500, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        ), scope: nil)
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [],
            windows: [top, bottom],
            state: RoadieState()
        )

        let target = GridFocusPicker.targetWindow(intersectingAXFrame: CGRect(x: 90, y: 90, width: 130, height: 60), in: snapshot)

        #expect(target?.window.id == top.window.id)
    }

    @Test
    func labelStylesFollowTheConfiguredFontSize() {
        let letters = TargetOverlayStyle.labels(TargetModeConfig(labelFontSize: 20, searchLabelFontSize: 24))
        let grid = TargetOverlayStyle.grid(TargetGridConfig(labelFontSize: 20))

        #expect(abs(letters.scale - 20.0 / 13.0) < 0.001)
        #expect(abs(grid.scale - 20.0 / 13.0) < 0.001)
        #expect(TargetOverlayStyle.labels(TargetModeConfig()).scale == 1)
    }

    /// SPEC-023 R2 : l'action différée de la boîte part après le nettoyage de la session et la remise à
    /// zéro du contrôleur, un tour de boucle plus tard ; la commande `grid` arrive alors au contrôleur.
    /// La session de recherche exige un tap clavier et des écrans : la séquence est testée par la
    /// fonction qu'elle appelle, avec le vrai contrôleur.
    @Test @MainActor
    func deferredBoxActionRunsAfterTheSessionEndsAndReachesTheController() async throws {
        let eventPath = tempPath("command-box-events")
        defer { try? FileManager.default.removeItem(atPath: eventPath) }
        let provider = PowerUserProvider(windows: [])
        let controller = TargetModeRuntimeController(
            service: SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), config: RoadieConfig()),
            events: EventLog(path: eventPath)
        )
        let steps = StepLog()

        CommandBoxFollowUp.finish(
            cleanup: { steps.entries.append("cleanup") },
            notify: { steps.entries.append("finish") },
            then: {
                steps.entries.append("action")
                controller.handle(TargetModeRuntimeCommand(name: "grid.interactive", arguments: ["scope": "display"]))
            }
        )
        #expect(steps.entries == ["cleanup", "finish"])

        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(steps.entries == ["cleanup", "finish", "action"])
        // Grille désactivée par défaut : la commande est traitée (et refusée), pas ignorée.
        let events = try String(contentsOfFile: eventPath, encoding: .utf8)
        #expect(events.contains("grid.interactive"))
        #expect(events.contains("target_grid_disabled"))
    }

    /// Fusion 022/023 : le présentateur injectable reçoit le style et les actions de la boîte.
    @Test @MainActor
    func searchKeepsCommandBoxAndConfiguredLabelStyle() throws {
        let service = targetModeService(name: "search-command-box", displays: [powerDisplay()], labelFontSize: 20, searchLabelFontSize: 24)
        let presenter = SpyTargetModeOverlayPresenter()
        let controller = TargetModeRuntimeController(service: service, events: EventLog(), presenter: presenter)

        controller.handle(TargetModeRuntimeCommand(name: "targets.search"))

        let style = try #require(presenter.searchStyle)
        #expect(service.effectiveConfig.experimental.targetMode.labelFontSize == 20)
        #expect(style.labelFontSize == 24)
        #expect(abs(style.scale - 24.0 / 13.0) < 0.001)
        #expect(presenter.searchTargets?.isEmpty == false)
        #expect(presenter.searchCommands != nil)
        #expect(presenter.searchRunDeferred != nil)
        #expect(presenter.searchOpenSettings != nil)
    }

    @Test @MainActor
    func openSessionsReceiveOnlyTheirOwnConfiguredFonts() throws {
        let service = targetModeService(name: "live-fonts", displays: [powerDisplay()])
        let presenter = SpyTargetModeOverlayPresenter()
        let session = SpyFontSession()
        presenter.session = session
        let controller = TargetModeRuntimeController(service: service, events: EventLog(), presenter: presenter)
        defer { controller.stop() }
        var config = service.effectiveConfig
        config.experimental.targetMode.labelFontSize = 18
        config.experimental.targetMode.searchLabelFontSize = 24
        config.experimental.targetMode.searchTextFontSize = 32
        config.experimental.targetMode.commandTextFontSize = 40
        config.experimental.targetMode.searchFontFamily = "Helvetica"
        config.experimental.targetMode.commandFontFamily = "Menlo"
        config.experimental.targetGrid.labelFontSize = 28
        for (command, expected) in [("targets.interactive", CGFloat(18)), ("targets.search", CGFloat(24)), ("grid.interactive", CGFloat(28))] {
            controller.handle(TargetModeRuntimeCommand(name: command))
            controller.refreshOverlayStyle(config: config)
            let style = try #require(session.styles.last)
            #expect(style.labelFontSize == expected)
            if command == "targets.search" {
                #expect(style.searchTextFontSize == 32)
                #expect(style.commandTextFontSize == 40)
                #expect(style.searchFontFamily == "Helvetica")
                #expect(style.commandFontFamily == "Menlo")
            }
        }
        controller.stop()
        let count = session.styles.count
        controller.refreshOverlayStyle(config: config)
        #expect(session.styles.count == count)
    }

    // TEST-002 / REL-003 : la lettre validée active la cible de la liste affichée (filtrée), pas
    // celle qui porte la même lettre dans une liste reconstruite sans les options.
    @Test @MainActor
    func interactiveLetterActivatesTargetOfDisplayedFilteredList() throws {
        let service = targetModeService(name: "rel003-filtered", displays: [powerDisplay()])
        let presenter = SpyTargetModeOverlayPresenter()
        let controller = TargetModeRuntimeController(service: service, events: EventLog(), presenter: presenter)

        controller.handle(TargetModeRuntimeCommand(name: "targets.interactive", arguments: [
            "source": "roadie",
            "filter": "firefox",
            "action": "inspect",
        ]))
        let shown = try #require(presenter.interactiveState?.report.targets.first)
        let activate = try #require(presenter.interactiveActivate)
        let unfiltered = TargetHintService(service: service).list(TargetQueryOptions(source: .all))

        #expect(unfiltered.targets.first { $0.label == shown.label }?.id != shown.id)
        #expect(activate(shown.label.lowercased()).target?.id == shown.id)
        #expect(activate("ZZZ").error == "unknown_target")
    }

    // TEST-002 / REL-004 : après une flèche vers l'écran 2, la grille affichée est celle de l'écran 2.
    @Test @MainActor
    func gridFollowsDisplaySelectedByArrows() throws {
        let service = targetModeService(name: "rel004-grid", displays: [
            powerDisplay("display-1", index: 1, x: 0),
            powerDisplay("display-2", index: 2, x: 1000),
        ])
        let presenter = SpyTargetModeOverlayPresenter()
        let controller = TargetModeRuntimeController(service: service, events: EventLog(), presenter: presenter)

        controller.handle(TargetModeRuntimeCommand(name: "grid.interactive", arguments: [
            "display": "1",
            "scope": "display",
        ]))
        let stateProvider = try #require(presenter.gridStateProvider)

        #expect(stateProvider(nil, "").report.targets.first?.scope.displayId == "display-1")
        #expect(stateProvider(1, "").report.targets.first?.scope.displayId == "display-1")
        #expect(stateProvider(2, "").report.targets.first?.scope.displayId == "display-2")
        #expect(stateProvider(2, "").report.targets.first?.frame?.x ?? 0 >= 1000)
    }

    // TEST-002 / REL-004 (contre-revue R1-16) : la lettre validée après une flèche vers l'écran 2 clique
    // au centre de la case affichée sur l'écran 2, puis la session se termine.
    @Test @MainActor
    func gridActivationClicksShownCellOfSelectedDisplayThenFinishes() throws {
        let service = targetModeService(name: "rel004-grid-click", displays: [
            powerDisplay("display-1", index: 1, x: 0),
            powerDisplay("display-2", index: 2, x: 1000),
        ])
        let eventPath = tempPath("rel004-grid-click-events")
        let presenter = SpyTargetModeOverlayPresenter()
        var posted: [CGEvent] = []
        // Événements souris réellement construits par `TargetGridService.perform`, interceptés avant
        // l'envoi au système.
        let controller = TargetModeRuntimeController(
            service: service,
            events: EventLog(path: eventPath),
            presenter: presenter,
            gridPostEvent: { posted.append($0) }
        )

        controller.handle(TargetModeRuntimeCommand(name: "grid.interactive", arguments: [
            "display": "1",
            "scope": "display",
        ]))
        let stateProvider = try #require(presenter.gridStateProvider)
        let activate = try #require(presenter.gridActivate)
        let onFinish = try #require(presenter.gridFinish)
        let shown = try #require(stateProvider(2, "").report.targets.first)
        let shownFrame = try #require(shown.frame).cgRect
        let path = try #require(shown.id.split(separator: "/").last.map(String.init))

        let result = activate(2, path)
        onFinish(result)

        #expect(result.changed)
        #expect(posted.map(\.type) == [.leftMouseDown, .leftMouseUp])
        // La case affichée est arrondie au point entier (`integral`), le clic vise le centre exact :
        // écart inférieur à un point, toujours dans la case affichée.
        #expect(posted.allSatisfy { shownFrame.contains($0.location) })
        #expect(posted.allSatisfy { abs($0.location.x - shownFrame.midX) < 1 && abs($0.location.y - shownFrame.midY) < 1 })
        #expect(posted.allSatisfy { $0.location.x >= 1000 })
        let finished = EventLog(path: eventPath).tail(limit: 5).filter { $0.contains("target_mode.finished") }
        #expect(finished.count == 1)
        #expect(finished.first?.contains("grid.interactive") == true)
    }
}

@MainActor
private final class StepLog {
    var entries: [String] = []
}

@MainActor
private func targetModeService(name: String, displays: [DisplaySnapshot], labelFontSize: Double = 13, searchLabelFontSize: Double = 13) -> SnapshotService {
    let displayID = displays[0].id
    let stageID = StageID(rawValue: "1")
    let first = powerWindow(1, x: 100, app: "iTerm")
    let second = powerWindow(2, x: 500, app: "Firefox")
    let store = StageStore(path: tempPath(name))
    store.save(PersistentStageState(scopes: [
        PersistentStageScope(displayID: displayID, activeStageID: stageID, stages: [
            PersistentStage(id: stageID, members: [
                PersistentStageMember(windowID: first.id, bundleID: first.bundleID, title: first.title, frame: first.frame),
                PersistentStageMember(windowID: second.id, bundleID: second.bundleID, title: second.title, frame: second.frame),
            ]),
        ]),
    ], activeDisplayID: displayID))
    let provider = PowerUserProvider(displays: displays, windows: [first, second])
    let config = RoadieConfig(experimental: ExperimentalConfig(
        targetMode: TargetModeConfig(overlayEnabled: true, labelFontSize: labelFontSize, searchLabelFontSize: searchLabelFontSize),
        targetGrid: TargetGridConfig(enabled: true)
    ))
    return SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), config: config, stageStore: store)
}

/// Présentation espionne : conserve la liste affichée et les fermetures, sans overlay réel.
@MainActor
private final class SpyTargetModeOverlayPresenter: TargetModeOverlayPresenting {
    var session: SpyFontSession?
    var interactiveState: TargetOverlayState?
    var interactiveActivate: (@MainActor (String) -> TargetActionResult)?
    var gridStateProvider: (@MainActor (Int?, String) -> TargetOverlayState)?
    var gridActivate: (@MainActor (Int?, String) -> TargetActionResult)?
    var gridFinish: (@MainActor (TargetActionResult) -> Void)?
    var searchStyle: TargetOverlayStyle?
    var searchTargets: [RoadieTarget]?
    var searchCommands: SlashCommandRunner?
    var searchRunDeferred: (@MainActor ([String]) -> Void)?
    var searchOpenSettings: (@MainActor (SettingCategory?) -> Void)?
    var searchLauncher: LauncherSearchContext?

    func startInteractive(
        _ state: TargetOverlayState,
        duration: TimeInterval,
        style: TargetOverlayStyle,
        activate: @escaping @MainActor (String) -> TargetActionResult,
        onFinish: @escaping @MainActor (TargetActionResult) -> Void
    ) -> TargetOverlaySessionHandle? {
        interactiveState = state
        interactiveActivate = activate
        return session
    }

    func startGridInteractive(
        initialPath: String,
        duration: TimeInterval,
        config: TargetGridConfig,
        displayIndex: Int?,
        stateProvider: @escaping @MainActor (Int?, String) -> TargetOverlayState,
        activate: @escaping @MainActor (Int?, String) -> TargetActionResult,
        focusAt: @escaping @MainActor (CGRect) -> Void,
        displayNeighbor: @escaping @MainActor (Int?, TargetGridArrowDirection) -> Int?,
        onFinish: @escaping @MainActor (TargetActionResult) -> Void
    ) -> TargetOverlaySessionHandle? {
        gridStateProvider = stateProvider
        gridActivate = activate
        gridFinish = onFinish
        return session
    }

    func startSearch(
        targets: [RoadieTarget],
        alphabet: String,
        style: TargetOverlayStyle,
        commands: SlashCommandRunner,
        runDeferred: @escaping @MainActor ([String]) -> Void,
        openSettings: @escaping @MainActor (SettingCategory?) -> Void,
        load: (
            _ deliver: @escaping @MainActor @Sendable ([RoadieTarget], Int) -> Void,
            _ done: @escaping @MainActor @Sendable () -> Void
        ) -> Void,
        activate: @escaping @MainActor (RoadieTarget, TargetActionVerb) -> TargetActionResult,
        launcher: LauncherSearchContext,
        onFinish: @escaping @MainActor (TargetActionResult) -> Void
    ) -> TargetOverlaySessionHandle? {
        searchStyle = style
        searchTargets = targets
        searchCommands = commands
        searchRunDeferred = runDeferred
        searchOpenSettings = openSettings
        searchLauncher = launcher
        return session
    }
}

@MainActor
private final class RuleChoiceNotices {
    var messages: [String] = []
}

@MainActor
private struct RuleChoiceFixture {
    let controller: TargetModeRuntimeController
    let presenter: SpyTargetModeOverlayPresenter
    let memory: LauncherMemoryStore
    let eventURL: URL
    let notices: RuleChoiceNotices
    let suggestion: RuleSuggestion

    init(sandbox: URL) {
        let display = powerDisplay()
        let stageID = StageID(rawValue: "1")
        let stage = StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: stageID)
        let store = StageStore(path: sandbox.appendingPathComponent("stages.json").path)
        store.save(PersistentStageState(scopes: [PersistentStageScope(displayID: display.id, activeStageID: stageID,
            stages: [PersistentStage(id: stageID, name: "Perso")])], activeDisplayID: display.id))
        let provider = PowerUserProvider(displays: [display], windows: [])
        let config = RoadieConfig(experimental: ExperimentalConfig(targetMode: TargetModeConfig(overlayEnabled: true)))
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), config: config, stageStore: store)
        let presenter = SpyTargetModeOverlayPresenter()
        let memory = LauncherMemoryStore(path: sandbox.appendingPathComponent("memory.json").path)
        let eventURL = sandbox.appendingPathComponent("events.jsonl")
        let notices = RuleChoiceNotices()
        self.controller = TargetModeRuntimeController(service: service, events: EventLog(path: eventURL.path), presenter: presenter,
                                                      memoryStore: memory, notifyRuleChoiceFailure: { notices.messages.append($0) })
        self.presenter = presenter
        self.memory = memory
        self.eventURL = eventURL
        self.notices = notices
        self.suggestion = RuleSuggestion(bundleID: "exemple", appName: "Exemple", stage: stage, stageTitle: "Perso", count: 3,
                                         declineKey: "exemple|stage:perso")
    }
}

@MainActor
private final class SpyFontSession: TargetOverlaySessionHandle {
    var styles: [TargetOverlayStyle] = []
    func cancel() {}
    func updateStyle(_ style: TargetOverlayStyle) { styles.append(style) }
}
