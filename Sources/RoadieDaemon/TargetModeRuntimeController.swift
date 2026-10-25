import AppKit
import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore

public enum TargetModeRuntimeNotification {
    public static let name = Notification.Name("com.roadie.target-mode.command")
}

public struct TargetModeRuntimeCommand: Equatable, Sendable {
    public var name: String
    public var arguments: [String: String]

    public init(name: String, arguments: [String: String] = [:]) {
        self.name = name
        self.arguments = arguments
    }

    public init?(userInfo: [AnyHashable: Any]?) {
        guard let raw = userInfo?["command"] as? String, !raw.isEmpty else {
            return nil
        }
        var parsed: [String: String] = [:]
        for (key, value) in userInfo ?? [:] {
            guard let key = key as? String, key != "command" else { continue }
            parsed[key] = String(describing: value)
        }
        self.init(name: raw, arguments: parsed)
    }

    public var userInfo: [String: String] {
        var payload = arguments
        payload["command"] = name
        return payload
    }

    public func string(_ key: String) -> String? {
        arguments[key].flatMap { $0.isEmpty ? nil : $0 }
    }

    public func int(_ key: String) -> Int? {
        string(key).flatMap(Int.init)
    }

    public func double(_ key: String) -> Double? {
        string(key).flatMap(Double.init)
    }

    public func bool(_ key: String) -> Bool {
        switch string(key)?.lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }
}

/// Ouverture des overlays du mode cible. Point d'injection des tests (TEST-002) : un espion reçoit
/// la liste affichée et les fermetures d'activation, sans fenêtre ni tap clavier réels.
@MainActor
protocol TargetModeOverlayPresenting {
    func startInteractive(
        _ state: TargetOverlayState,
        duration: TimeInterval,
        style: TargetOverlayStyle,
        activate: @escaping @MainActor (String) -> TargetActionResult,
        onFinish: @escaping @MainActor (TargetActionResult) -> Void
    ) -> TargetOverlaySessionHandle?

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
    ) -> TargetOverlaySessionHandle?

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
    ) -> TargetOverlaySessionHandle?
}

/// Présentation réelle : délègue à `TargetOverlayPresenter`.
struct LiveTargetModeOverlayPresenter: TargetModeOverlayPresenting {
    func startInteractive(
        _ state: TargetOverlayState,
        duration: TimeInterval,
        style: TargetOverlayStyle,
        activate: @escaping @MainActor (String) -> TargetActionResult,
        onFinish: @escaping @MainActor (TargetActionResult) -> Void
    ) -> TargetOverlaySessionHandle? {
        TargetOverlayPresenter.startInteractive(state, duration: duration, style: style, activate: activate, onFinish: onFinish)
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
        TargetOverlayPresenter.startGridInteractive(
            initialPath: initialPath,
            duration: duration,
            config: config,
            displayIndex: displayIndex,
            stateProvider: stateProvider,
            activate: activate,
            focusAt: focusAt,
            displayNeighbor: displayNeighbor,
            onFinish: onFinish
        )
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
        TargetOverlayPresenter.startSearch(
            targets: targets,
            alphabet: alphabet,
            style: style,
            commands: commands,
            runDeferred: runDeferred,
            openSettings: openSettings,
            load: load,
            activate: activate,
            launcher: launcher,
            onFinish: onFinish
        )
    }
}

@MainActor
public final class TargetModeRuntimeController: NSObject {
    private let service: SnapshotService
    private let events: EventLog
    private let presenter: any TargetModeOverlayPresenting
    private var observer: NSObjectProtocol?
    private var currentSession: TargetOverlaySessionHandle?
    private var currentCommand: String?
    private var styleTimer: Timer?
    private var settingsObserver: NSObjectProtocol?
    /// Émission des événements souris de la grille. Point d'injection des tests (TEST-002) : clic
    /// réellement émis par `TargetGridService`, observé sans événement réel.
    private let gridPostEvent: (CGEvent) -> Void

    public convenience init(service: SnapshotService = SnapshotService(), events: EventLog = EventLog()) {
        self.init(service: service, events: events, presenter: LiveTargetModeOverlayPresenter())
    }

    init(
        service: SnapshotService,
        events: EventLog,
        presenter: any TargetModeOverlayPresenting,
        gridPostEvent: @escaping (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }
    ) {
        self.service = service
        self.events = events
        self.presenter = presenter
        self.gridPostEvent = gridPostEvent
    }

    public func start() {
        // Index des applications prêt avant la première ouverture de la barre (SPEC-073).
        LauncherAppCatalog.shared.refresh()
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: TargetModeRuntimeNotification.name,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let command = TargetModeRuntimeCommand(userInfo: notification.userInfo)
            Task { @MainActor in
                self?.handle(command)
            }
        }
        events.append(RoadieEvent(type: "target_mode.runtime_started"))
    }

    /// Raccourci global du mode recherche (SPEC-021).
    public func requestSearch() {
        handle(TargetModeRuntimeCommand(name: "targets.search"))
    }

    /// Raccourci des verbes de la fenêtre active (SPEC-075).
    public func requestActions() {
        handle(TargetModeRuntimeCommand(name: "targets.actions"))
    }

    public func stop() {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observer = nil
        stopStyleUpdates()
        currentSession?.cancel()
        currentSession = nil
        events.append(RoadieEvent(type: "target_mode.runtime_stopped"))
    }

    /// Interne : les tests vérifient les commandes et les actions différées sans notification distribuée.
    func handle(_ command: TargetModeRuntimeCommand?) {
        guard let command else {
            events.append(RoadieEvent(type: "target_mode.command_rejected", details: ["reason": "invalid_payload"]))
            return
        }
        // Raccourci de recherche maintenu ou répété : la recherche ouverte reste ouverte.
        if command.name == "targets.search", currentCommand == "targets.search", currentSession != nil {
            return
        }
        currentSession?.cancel()
        currentSession = nil
        currentCommand = command.name
        switch command.name {
        case "targets.interactive":
            startTargetsInteractive(command)
        case "targets.search", "targets.actions":
            startTargetsSearch(command)
        case "grid.interactive":
            startGridInteractive(command)
        default:
            events.append(RoadieEvent(type: "target_mode.command_rejected", details: [
                "command": command.name,
                "reason": "unknown_command"
            ]))
        }
        startStyleUpdatesIfNeeded()
    }

    /// Relit la configuration existante et actualise les sessions déjà ouvertes, sans effacer la saisie.
    func refreshOverlayStyle(config suppliedConfig: RoadieConfig? = nil) {
        guard let currentSession, let currentCommand else { return }
        let config = suppliedConfig ?? service.effectiveConfig
        let style: TargetOverlayStyle
        switch currentCommand {
        case "targets.search", "targets.actions": style = .search(config.experimental.targetMode)
        case "grid.interactive": style = .grid(config.experimental.targetGrid)
        default: style = .labels(config.experimental.targetMode)
        }
        currentSession.updateStyle(style)
    }

    private func startStyleUpdatesIfNeeded() {
        stopStyleUpdates()
        guard currentSession != nil else { return }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .roadieSettingsDidChange, object: nil, queue: .main
        ) { [weak self] notification in
            let path = notification.userInfo?["configPath"] as? String
            Task { @MainActor in
                let activePath = ConfigReloadService.shared.state.activePath ?? RoadieConfigLoader.defaultConfigPath()
                guard let self, let path,
                      URL(fileURLWithPath: path).resolvingSymlinksInPath()
                        == URL(fileURLWithPath: activePath).resolvingSymlinksInPath() else { return }
                self.refreshOverlayStyle()
            }
        }
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshOverlayStyle() }
        }
        styleTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopStyleUpdates() {
        styleTimer?.invalidate()
        styleTimer = nil
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        settingsObserver = nil
    }

    private func startTargetsInteractive(_ command: TargetModeRuntimeCommand) {
        let config = service.effectiveConfig.experimental.targetMode
        guard config.overlayEnabled else {
            finish(TargetActionResult(changed: false, message: "target_overlay_disabled", error: "target_overlay_disabled"), command: command.name)
            return
        }
        let options = TargetQueryOptions(
            source: command.string("source").flatMap(TargetSource.init(rawValue:)) ?? .roadie,
            filter: command.string("filter"),
            maxResults: command.int("max") ?? 120,
            includeHidden: command.bool("includeHidden"),
            includeAppTargets: command.bool("includeAppTargets")
        )
        let action = command.string("action").flatMap(TargetActionVerb.init(rawValue:))
        let targets = TargetHintService(service: service)
        let overlay = targets.overlayState(options: options, labelsOnly: true, visible: true)
        let duration = command.double("duration") ?? config.overlayDurationSeconds

        events.append(RoadieEvent(type: "target_mode.targets_started", details: [
            "source": options.source.rawValue,
            "targetCount": String(overlay.report.targets.count),
            "duration": String(format: "%.2f", duration)
        ]))
        currentSession = presenter.startInteractive(
            overlay,
            duration: duration,
            style: .labels(config),
            activate: { label in
                // REL-003 : la lettre désigne une cible de la liste affichée (source, filtre, cibles
                // d'app). Activer cette cible conservée, sans relire ni réétiqueter une autre liste.
                guard let selected = overlay.report.targets.first(where: {
                    $0.label.caseInsensitiveCompare(label) == .orderedSame
                }) else {
                    return TargetActionResult(changed: false, message: "unknown_target: \(label)", error: "unknown_target")
                }
                return targets.activate(target: selected, action: action)
            },
            onFinish: { [weak self] result in
                self?.finish(result, command: command.name)
            }
        )
    }

    /// Mode recherche (SPEC-021) : toutes sources, cibles d'app incluses ; activation de la cible figée.
    private func startTargetsSearch(_ command: TargetModeRuntimeCommand) {
        let config = service.effectiveConfig.experimental.targetMode
        guard config.overlayEnabled else {
            finish(TargetActionResult(changed: false, message: "target_overlay_disabled", error: "target_overlay_disabled"), command: command.name)
            return
        }
        // Barre immédiate (FR-009) : cibles Roadie tout de suite, puis toutes les fenêtres visibles, lues
        // en arrière-plan, chacune affichée dès qu'elle est lue. 2 s par fenêtre au moins : la barre
        // n'attend plus la plus lente, une page chargée peut donc être lue en entier.
        var appTargets = service.effectiveConfig.experimental.appTargets
        appTargets.scope = "visible_windows"
        appTargets.timeoutMs = max(appTargets.timeoutMs, 2000)
        let scanConfig = appTargets
        let targets = TargetHintService(service: service, appTargetsConfig: appTargets)
        let roadieTargets = targets.list(TargetQueryOptions(source: .roadie, maxResults: TargetSearchModel.maxTargets)).targets
        let events = events
        events.append(RoadieEvent(type: "target_mode.search_started", details: [
            "targetCount": String(roadieTargets.count)
        ]))
        // Mode commande (SPEC-023) : l'action différée et la fenêtre de réglages partent après la fin
        // de la session et la remise à zéro de `currentSession` (research R2).
        let commands = SlashCommandRunner()
        // Capslock + Maj + F (SPEC-075) : les verbes de la fenêtre au premier plan, si Roadie la connaît.
        var initialSubject: LauncherSubject?
        if command.name == "targets.actions" {
            let focused = service.snapshot(followFocus: false).focusedWindowID
            initialSubject = focused.flatMap { id in roadieTargets.first { $0.id == "window:\(id.rawValue)" } }.map(LauncherSubject.target)
            events.append(RoadieEvent(type: "target_mode.actions_started", details: [
                "focusedWindowID": focused.map { String($0.rawValue) } ?? "none",
                "subject": initialSubject == nil ? "none" : "window"]))
        }
        currentSession = presenter.startSearch(
            targets: roadieTargets,
            alphabet: appTargets.hintCharacters,
            style: .search(config),
            commands: commands,
            runDeferred: { argv in commands.runDeferred(argv) },
            openSettings: { category in SettingsWindowController.shared.show(category: category) },
            load: { deliver, done in
                DispatchQueue.global(qos: .userInitiated).async {
                    let scan = LiveAppTargetProvider().scanVisibleWindows(config: scanConfig) { window in
                        DispatchQueue.main.async {
                            events.append(RoadieEvent(type: "targets.app_scan", details: window.stats.eventDetails))
                            MainActor.assumeIsolated { deliver(window.targets, window.order) }
                        }
                    }
                    DispatchQueue.main.async {
                        for stats in scan.skipped {
                            events.append(RoadieEvent(type: "targets.app_scan", details: stats.eventDetails))
                        }
                        MainActor.assumeIsolated { done() }
                    }
                }
            },
            activate: { target, verb in
                targets.activate(target: target, action: verb)
            },
            launcher: launcherContext(initialSubject: initialSubject),
            onFinish: { [weak self] result in
                self?.finish(result, command: command.name)
            }
        )
    }

    /// Lanceur de la barre (SPEC-073) : index des applications gardé en mémoire et rafraîchi à chaque
    /// ouverture, état des applications ouvertes, classement appris lu une fois par session.
    private func launcherContext(initialSubject: LauncherSubject? = nil) -> LauncherSearchContext {
        let catalog = LauncherAppCatalog.shared
        let rankingStore = LauncherRankingStore()
        let state = service.effectiveStageStore.state()
        let running = Set(NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }.compactMap(\.bundleIdentifier))
        let snapshot = service.snapshot(followFocus: false)
        let names = WindowSwitcherService.stageLabels(in: state, liveWindowIDs: Set(snapshot.windows.map(\.window.id)))
        let homeDisplay = state.activeDisplayID ?? snapshot.displays.first?.id ?? DisplayID(rawValue: "none")
        let homeDesktop = state.currentDesktopID(for: homeDisplay)
        let activeStage = state.scopes.first { $0.displayID == homeDisplay && $0.desktopID == homeDesktop }
            .map { StageScope(displayID: homeDisplay, desktopID: homeDesktop, stageID: $0.activeStageID) }
        let affinity = WindowRuleAffinityService(eventLog: events)
        let webSearchURL = service.effectiveConfig.experimental.targetMode.webSearchURL
        var context = LauncherSearchContext(
            apps: catalog.current,
            details: LauncherPlacement.details(runningBundleIDs: running, state: state, stageNames: names),
            ranking: rankingStore.load(),
            refreshApps: { done in catalog.refresh(done: done) },
            launch: { [weak self] app in self?.launch(app) ?? TargetActionResult(changed: false, message: "launcher_unavailable") },
            recordVisit: { key, query in rankingStore.recordVisit(key, query: query) },
            destinations: LauncherPlacement.destinations(state: state, displays: snapshot.displays, stageNames: names),
            newStageHome: (homeDisplay, homeDesktop),
            perform: { [weak self] action in
                self?.perform(action) ?? TargetActionResult(changed: false, message: "launcher_unavailable")
            }
        )
        context.activeStage = activeStage
        context.initialSubject = initialSubject
        context.tiling = { id in
            guard let entry = snapshot.windows.first(where: { $0.window.id == id }) else { return nil }
            return LauncherTilingState(pinned: entry.pin != nil, tiled: entry.window.isTileCandidate && entry.pin == nil,
                                       rule: affinity.tilingChoice(for: entry.window))
        }
        context.webSearch = { [events] text in
            guard let url = LauncherWeb.searchURL(webSearchURL, query: text) else {
                return TargetActionResult(changed: false, message: "launcher web: invalid url", error: "web_search_url")
            }
            NSWorkspace.shared.open(url)
            events.append(RoadieEvent(type: "launcher.web_search", details: ["host": url.host ?? ""]))
            return TargetActionResult(changed: true, message: "launcher web: \(url.host ?? "")")
        }
        return context
    }

    // MARK: - Verbes du lanceur (SPEC-074)

    /// Exécute un verbe. Les effets qui attendent une application ou une fenêtre partent en tâche ;
    /// le résultat rendu décrit ce qui a été demandé. Chaque issue est journalisée.
    private func perform(_ action: LauncherAction) -> TargetActionResult {
        let label = "launcher \(action.verb.rawValue)"
        switch action.subject {
        case .app(let app):
            switch action.verb {
            case .open:
                return launch(app)
            case .newWindow:
                openWindow(app, into: nil)
            case .openIn:
                guard let scope = action.destination.flatMap(stageScope) else { return refused(label, "destination") }
                openWindow(app, into: scope)
            case .gatherIn:
                guard let scope = action.destination.flatMap(stageScope) else { return refused(label, "destination") }
                gather(app, into: scope)
            case .hide:
                NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).forEach { $0.hide() }
            case .quit:
                NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).forEach { $0.terminate() }
            case .bringHere:
                bringHere(app, into: action.destination.flatMap(stageScope) ?? activeStageScope())
            default:
                return refused(label, "verb")
            }
            return TargetActionResult(changed: true, message: "\(label): \(app.bundleID)")
        case .target(let target):
            let result = perform(action.verb, on: target, destination: action.destination, label: label)
            // ⌘ Retour : Roadie va à la fenêtre envoyée dans sa nouvelle stage.
            if action.follow, result.changed, let id = target.scope.windowId { focus(WindowID(rawValue: id)) }
            return result
        }
    }

    /// Stage active du bureau affiché de l'écran actif. O(S).
    private func activeStageScope() -> StageScope? {
        let state = service.effectiveStageStore.state()
        guard let display = state.activeDisplayID ?? service.snapshot(followFocus: false).displays.first?.id else { return nil }
        let desktop = state.currentDesktopID(for: display)
        return state.scopes.first { $0.displayID == display && $0.desktopID == desktop }
            .map { StageScope(displayID: display, desktopID: desktop, stageID: $0.activeStageID) }
    }

    /// Met la fenêtre devant, dans sa stage et son bureau.
    private func focus(_ window: WindowID) {
        let switcher = WindowSwitcherService(service: service)
        Task { @MainActor in
            if let entry = await switcher.load().entries.first(where: { $0.id == window }) { _ = switcher.activate(entry) }
        }
    }

    /// ⌥ Retour sur une application : sa fenêtre préférée rejoint la stage active et passe devant ;
    /// fermée, elle s'ouvre (la stage active reçoit les nouvelles fenêtres). La stage affichée ne change pas.
    private func bringHere(_ app: LauncherApp, into scope: StageScope?) {
        guard let scope else { _ = launch(app); return }
        let service = service
        let events = events
        let switcher = WindowSwitcherService(service: service)
        Task { @MainActor in
            let loaded = await switcher.load()
            guard let entry = LauncherPlacement.preferredWindow(loaded.entries.filter { $0.window.bundleID == app.bundleID },
                                                                state: loaded.persisted) else {
                _ = self.launch(app)
                return
            }
            if entry.scope != scope {
                _ = WindowContextActions(snapshotService: service, stageStore: service.effectiveStageStore, eventLog: events)
                    .assign(windowID: entry.id, to: scope.stageID, desktopID: scope.desktopID, displayID: scope.displayID)
            }
            events.append(RoadieEvent(type: "launcher.brought", details: ["bundleID": app.bundleID, "stage": scope.description]))
            if let placed = await switcher.load().entries.first(where: { $0.id == entry.id }) { _ = switcher.activate(placed) }
        }
    }

    private func perform(_ verb: LauncherVerb, on target: RoadieTarget, destination: LauncherDestination?, label: String) -> TargetActionResult {
        let store = service.effectiveStageStore
        let scope = target.scope
        switch (target.kind, verb) {
        case (.window, .sendTo):
            guard let window = scope.windowId.map(WindowID.init(rawValue:)), let destination else { return refused(label, "window") }
            let message: String
            switch destination.kind {
            case .stage, .newStage:
                guard let stage = stageScope(for: destination) else { return refused(label, "destination") }
                message = WindowContextActions(snapshotService: service, stageStore: store, eventLog: events)
                    .assign(windowID: window, to: stage.stageID, desktopID: stage.desktopID, displayID: stage.displayID).message
            case .desktop(let display, let desktop):
                message = DesktopCommandService(service: service, store: store, events: events)
                    .assign(windowID: window, to: desktop, displayID: display).message
            case .display(let display):
                message = WindowCommandService(service: service, stageStore: store, events: events)
                    .send(windowID: window, toDisplayID: display, focusMovedWindow: false).message
            }
            return TargetActionResult(changed: true, message: message)
        case (.window, .bringHere):
            guard let window = scope.windowId.map(WindowID.init(rawValue:)),
                  let here = destination.flatMap(stageScope) ?? activeStageScope() else { return refused(label, "window") }
            let result = WindowContextActions(snapshotService: service, stageStore: store, eventLog: events)
                .assign(windowID: window, to: here.stageID, desktopID: here.desktopID, displayID: here.displayID)
            focus(window)
            return TargetActionResult(changed: result.changed, message: result.message)
        case (.window, .float), (.window, .tileWindow):
            guard let window = scope.windowId.map(WindowID.init(rawValue:)) else { return refused(label, "window") }
            let result = WindowContextActions(snapshotService: service, stageStore: store, eventLog: events).toggleFloating(windowID: window)
            return TargetActionResult(changed: result.changed, message: result.message)
        case (.window, .floatAlways), (.window, .tileAlways), (.window, .clearTilingRule):
            guard let id = scope.windowId.map(WindowID.init(rawValue:)),
                  let entry = service.snapshot(followFocus: false).windows.first(where: { $0.window.id == id }) else {
                return refused(label, "window")
            }
            let choice: WindowTilingChoice? = verb == .floatAlways ? .float : verb == .tileAlways ? .tile : nil
            let result = WindowRuleAffinityService(eventLog: events).saveTiling(choice, window: entry.window)
            return TargetActionResult(changed: result.changed, message: result.message)
        case (.window, .fullscreen), (.window, .minimize), (.window, .close):
            guard let window = scope.windowId.map(WindowID.init(rawValue:)) else { return refused(label, "window") }
            let switcherAction: WindowSwitcherAction = verb == .fullscreen ? .fullscreen : verb == .minimize ? .minimize : .close
            let switcher = WindowSwitcherService(service: service)
            let events = events
            Task { @MainActor in
                guard let entry = await switcher.load().entries.first(where: { $0.id == window }) else { return }
                let result = switcher.perform(switcherAction, on: entry)
                events.append(RoadieEvent(type: "launcher.window", details: ["verb": verb.rawValue, "message": result.message]))
            }
            return TargetActionResult(changed: true, message: label)
        case (.stage, .moveTo):
            guard let displayID = scope.displayId.map(DisplayID.init(rawValue:)), let desktop = scope.desktopId.map(DesktopID.init(rawValue:)),
                  let stage = scope.stageId.map(StageID.init(rawValue:)), let destination else { return refused(label, "stage") }
            let (targetDisplay, targetDesktop): (DisplayID, DesktopID)
            switch destination.kind {
            case .desktop(let display, let number): (targetDisplay, targetDesktop) = (display, number)
            case .display(let display): (targetDisplay, targetDesktop) = (display, store.state().currentDesktopID(for: display))
            default: return refused(label, "destination")
            }
            let result = StageCommandService(service: service, store: store, events: events)
                .moveStage(stage, displayID: displayID, from: desktop, to: targetDesktop, before: nil, targetDisplay: targetDisplay)
            return TargetActionResult(changed: result.changed, message: result.message)
        case (.desktop, .moveTo):
            guard let displayID = scope.displayId.map(DisplayID.init(rawValue:)), let desktop = scope.desktopId.map(DesktopID.init(rawValue:)),
                  case .display(let targetDisplay)? = destination?.kind else { return refused(label, "desktop") }
            // En dernier sur l'autre écran : après son plus grand numéro connu.
            let state = store.state()
            let last = state.scopes.filter { $0.displayID == targetDisplay }.map(\.desktopID.rawValue).max() ?? 0
            let result = DesktopCommandService(service: service, store: store, events: events)
                .move(desktop, from: displayID, toDisplay: targetDisplay, position: DesktopID(rawValue: max(last, state.currentDesktopID(for: targetDisplay).rawValue) + 1))
            return TargetActionResult(changed: result.changed, message: result.message)
        default:
            return refused(label, "verb")
        }
    }

    private func refused(_ label: String, _ reason: String) -> TargetActionResult {
        events.append(RoadieEvent(type: "launcher.refused", details: ["action": label, "reason": reason]))
        return TargetActionResult(changed: false, message: "\(label): \(reason) unavailable", error: reason)
    }

    /// Stage visée par une destination ; une « Nouvelle stage » est créée dans son bureau. O(S).
    private func stageScope(for destination: LauncherDestination) -> StageScope? {
        switch destination.kind {
        case .stage(let scope):
            return scope
        case .newStage(let name, let display, let desktop):
            let (result, scope) = StageCommandService(service: service, store: service.effectiveStageStore, events: events)
                .createStage(named: name, displayID: display, desktopID: desktop)
            events.append(RoadieEvent(type: "launcher.stage_created", details: ["message": result.message]))
            return scope
        case .desktop, .display:
            return nil
        }
    }

    /// Nouvelle fenêtre de l'application, rangée dans `scope` si demandé (intention de placement F5).
    /// Application ouverte avec des fenêtres : ⌘N après activation ; sinon macOS l'ouvre ou la rouvre.
    /// La première fenêtre inconnue de ce paquet apparue en 10 s rejoint la stage, une seule fois, puis
    /// Roadie y va. Sans nouvelle fenêtre dans ce délai : rien n'est déplacé.
    private func openWindow(_ app: LauncherApp, into scope: StageScope?) {
        let service = service
        let events = events
        let switcher = WindowSwitcherService(service: service)
        Task { @MainActor in
            let known = Set(await switcher.load().entries.filter { $0.window.bundleID == app.bundleID }.map(\.id))
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first
            if let running, !known.isEmpty {
                running.activate()
                try? await Task.sleep(for: .milliseconds(300))
                Self.postNewWindowShortcut(to: running.processIdentifier)
            } else {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                _ = try? await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: configuration)
            }
            guard let scope else { return }
            for _ in 0..<50 {
                try? await Task.sleep(for: .milliseconds(200))
                let entries = await switcher.load().entries
                guard let fresh = entries.first(where: { $0.window.bundleID == app.bundleID && !known.contains($0.id) }) else { continue }
                let result = WindowContextActions(snapshotService: service, stageStore: service.effectiveStageStore, eventLog: events)
                    .assign(windowID: fresh.id, to: scope.stageID, desktopID: scope.desktopID, displayID: scope.displayID)
                events.append(RoadieEvent(type: "launcher.placed", details: [
                    "bundleID": app.bundleID, "windowID": String(fresh.id.rawValue), "stage": scope.description, "message": result.message]))
                if let placed = await switcher.load().entries.first(where: { $0.id == fresh.id }) { _ = switcher.activate(placed) }
                return
            }
            events.append(RoadieEvent(type: "launcher.placement_expired", details: ["bundleID": app.bundleID, "stage": scope.description]))
        }
    }

    /// Toutes les fenêtres gérées de l'application rejoignent la stage, puis Roadie y va.
    private func gather(_ app: LauncherApp, into scope: StageScope) {
        let service = service
        let events = events
        let switcher = WindowSwitcherService(service: service)
        Task { @MainActor in
            let windows = await switcher.load().entries.filter { $0.window.bundleID == app.bundleID && $0.scope != scope }
            let actions = WindowContextActions(snapshotService: service, stageStore: service.effectiveStageStore, eventLog: events)
            for window in windows {
                _ = actions.assign(windowID: window.id, to: scope.stageID, desktopID: scope.desktopID, displayID: scope.displayID)
            }
            events.append(RoadieEvent(type: "launcher.gathered", details: [
                "bundleID": app.bundleID, "windows": String(windows.count), "stage": scope.description]))
            if let first = windows.first, let placed = await switcher.load().entries.first(where: { $0.id == first.id }) {
                _ = switcher.activate(placed)
            }
        }
    }

    /// ⌘N envoyé à l'application seule, jamais à celle qui a le focus par erreur.
    private static func postNewWindowShortcut(to pid: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 45, keyDown: down) else { continue }
            event.flags = .maskCommand
            event.postToPid(pid)
        }
    }

    /// Application déjà ouverte avec une fenêtre gérée : Roadie y va, dans sa stage et son bureau.
    /// Sinon macOS l'ouvre (ou la rouvre) ; sa nouvelle fenêtre suit la règle de placement des nouvelles
    /// fenêtres (stage active de l'écran actif) ou une règle `assign_stage`.
    private func launch(_ app: LauncherApp) -> TargetActionResult {
        let switcher = WindowSwitcherService(service: service)
        let events = events
        Task { @MainActor in
            let loaded = await switcher.load()
            let windows = loaded.entries.filter { $0.window.bundleID == app.bundleID }
            if let entry = LauncherPlacement.preferredWindow(windows, state: loaded.persisted) {
                let result = switcher.activate(entry)
                events.append(RoadieEvent(type: "launcher.focus", details: [
                    "bundleID": app.bundleID, "windowID": String(entry.id.rawValue), "message": result.message]))
                if result.outcome != .failed { return }
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: configuration) { _, error in
                events.append(RoadieEvent(type: "launcher.open", details: [
                    "bundleID": app.bundleID, "error": error.map { String(describing: $0) } ?? ""]))
            }
        }
        return TargetActionResult(changed: true, message: "launcher: \(app.bundleID)")
    }

    private func startGridInteractive(_ command: TargetModeRuntimeCommand) {
        let config = service.effectiveConfig.experimental.targetGrid
        guard config.enabled else {
            finish(TargetActionResult(changed: false, message: "target_grid_disabled", error: "target_grid_disabled"), command: command.name)
            return
        }
        guard config.overlayEnabled else {
            finish(TargetActionResult(changed: false, message: "target_grid_overlay_disabled", error: "target_grid_overlay_disabled"), command: command.name)
            return
        }

        let targetModeConfig = service.effectiveConfig.experimental.targetMode
        let grid = TargetGridService(service: service, postEvent: gridPostEvent)
        let displayIndex = command.int("display")
        let initialPath = command.string("path") ?? ""
        let scope = command.string("scope").flatMap(TargetGridScope.init(rawValue:)) ?? config.defaultScope
        let frozenRoot = grid.root(displayIndex: displayIndex, scope: scope)
        let duration = command.double("duration") ?? targetModeConfig.overlayDurationSeconds

        events.append(RoadieEvent(type: "target_mode.grid_started", details: [
            "display": displayIndex.map(String.init) ?? "current",
            "scope": scope.rawValue,
            "resolvedScope": frozenRoot?.scope.rawValue ?? "none",
            "rootDisplay": frozenRoot.map { String($0.display.index) } ?? "none",
            "path": initialPath,
            "duration": String(format: "%.2f", duration)
        ]))
        // REL-004 : racine figée tant que l'écran choisi reste le sien ; après une flèche vers un autre
        // écran, grille de cet écran entier. Affichage et clic lisent la même racine.
        let rootFor: @MainActor (Int?) -> TargetGridRoot? = { selectedDisplayIndex in
            guard let frozenRoot else { return nil }
            guard let selectedDisplayIndex, selectedDisplayIndex != frozenRoot.display.index else { return frozenRoot }
            return grid.root(displayIndex: selectedDisplayIndex, scope: .display)
        }
        currentSession = presenter.startGridInteractive(
            initialPath: initialPath,
            duration: duration,
            config: config,
            displayIndex: displayIndex,
            stateProvider: { selectedDisplayIndex, parentPath in
                if let root = rootFor(selectedDisplayIndex) {
                    return TargetOverlayState(
                        visible: true,
                        labelsOnly: true,
                        report: grid.targets(root: root, parentPath: parentPath)
                    )
                }
                return TargetOverlayState(
                    visible: true,
                    labelsOnly: true,
                    report: grid.targets(displayIndex: selectedDisplayIndex, parentPath: parentPath, scope: scope)
                )
            },
            activate: { selectedDisplayIndex, selectedPath in
                if let root = rootFor(selectedDisplayIndex) {
                    return grid.perform(.click, path: selectedPath, root: root)
                }
                return grid.perform(.click, path: selectedPath, displayIndex: selectedDisplayIndex, scope: scope)
            },
            focusAt: { [weak self] frame in
                guard scope == .display else { return }
                self?.focusGridWindow(in: frame)
            },
            displayNeighbor: { [weak self] selectedDisplayIndex, direction in
                self?.gridDisplayNeighbor(from: selectedDisplayIndex, direction: direction)
            },
            onFinish: { [weak self] result in
                self?.finish(result, command: command.name)
            }
        )
    }

    private func focusGridWindow(in frame: CGRect) {
        let snapshot = service.snapshot(followFocus: false)
        guard let target = GridFocusPicker.targetWindow(intersectingAXFrame: frame, in: snapshot) else {
            events.append(RoadieEvent(type: "target_mode.grid_focus_skipped", details: [
                "reason": "no_window_under_point",
                "x": String(format: "%.1f", frame.minX),
                "y": String(format: "%.1f", frame.minY),
                "w": String(format: "%.1f", frame.width),
                "h": String(format: "%.1f", frame.height),
            ]))
            return
        }
        guard target.window.id != snapshot.focusedWindowID else {
            events.append(RoadieEvent(type: "target_mode.grid_focus_skipped", details: [
                "reason": "already_focused",
                "windowID": String(target.window.id.rawValue),
                "app": target.window.appName,
            ]))
            return
        }
        if service.focus(target.window) {
            events.append(RoadieEvent(type: "target_mode.grid_focus_followed", details: [
                "windowID": String(target.window.id.rawValue),
                "app": target.window.appName,
            ]))
        } else {
            events.append(RoadieEvent(type: "target_mode.grid_focus_skipped", details: [
                "reason": "focus_failed",
                "windowID": String(target.window.id.rawValue),
                "app": target.window.appName,
            ]))
        }
    }

    private func gridDisplayNeighbor(from displayIndex: Int?, direction: TargetGridArrowDirection) -> Int? {
        let snapshot = service.snapshot(followFocus: false)
        guard let source = gridDisplay(displayIndex: displayIndex, in: snapshot.displays),
              let target = DisplayTopology.neighbor(from: source, direction: direction.windowDirection, in: snapshot.displays)
        else { return nil }
        events.append(RoadieEvent(type: "target_mode.grid_display_changed", details: [
            "from": String(source.index),
            "to": String(target.index),
            "direction": direction.eventValue
        ]))
        return target.index
    }

    private func gridDisplay(displayIndex: Int?, in displays: [DisplaySnapshot]) -> DisplaySnapshot? {
        if let displayIndex, let display = displays.first(where: { $0.index == displayIndex }) {
            return display
        }
        let state = service.effectiveStageStore.state()
        if let activeDisplayID = state.activeDisplayID,
           let display = displays.first(where: { $0.id == activeDisplayID }) {
            return display
        }
        return displays.first(where: \.isMain) ?? displays.first
    }

    private func finish(_ result: TargetActionResult, command: String) {
        stopStyleUpdates()
        currentSession = nil
        currentCommand = nil
        events.append(RoadieEvent(type: "target_mode.finished", details: [
            "command": command,
            "changed": String(result.changed),
            "message": result.message,
            "error": result.error ?? ""
        ]))
    }
}

enum GridFocusPicker {
    static func targetWindow(intersectingAXFrame frame: CGRect, in snapshot: DaemonSnapshot) -> ScopedWindowSnapshot? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let candidates = snapshot.windows.filter { entry in
            let windowFrame = entry.window.frame.cgRect
            return entry.window.isOnScreen
                && isFocusableWindow(entry.window)
                && windowFrame.intersection(frame).area > 16
        }
        return candidates.first { $0.window.frame.cgRect.contains(center) }
            ?? candidates.first
    }

    private static func isFocusableWindow(_ window: WindowSnapshot) -> Bool {
        window.frame.width >= 80
            && window.frame.height >= 50
            && window.appName != "Window Server"
            && !window.bundleID.hasPrefix("com.apple.WindowManager")
    }
}

private extension TargetGridArrowDirection {
    var windowDirection: Direction {
        switch self {
        case .left: return .left
        case .right: return .right
        case .up: return .up
        case .down: return .down
        }
    }

    var eventValue: String {
        switch self {
        case .left: return "left"
        case .right: return "right"
        case .up: return "up"
        case .down: return "down"
        }
    }
}

private extension CGRect {
    var area: CGFloat {
        isNull || isEmpty ? 0 : width * height
    }
}
