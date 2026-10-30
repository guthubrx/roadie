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
    private let memoryStore: LauncherMemoryStore
    private let notifyRuleChoiceFailure: (String) -> Void
    private let ruleAffinity: WindowRuleAffinityService
    private var observer: NSObjectProtocol?
    private var currentSession: TargetOverlaySessionHandle?
    private var currentCommand: String?
    /// Grille d'un workflow à montrer à la prochaine ouverture de la barre (SPEC-092).
    private var pendingGrid: AlfredGridView?
    /// Barre ouverte sur une grille : son entrée et la fonction qui lui envoie les tuiles (session 095).
    private var openGrid: (id: String, update: @MainActor (AlfredGridView) -> Void)?
    /// Application au premier plan à l'ouverture de la barre, rendue au clavier après Échap (session 097).
    private var escapeFocus: LauncherFocusSnapshot?
    /// Derniers documents et onglets ouverts lus pour la barre (session 123).
    private var lastOpenItems: (at: Date, items: [LauncherOpenItem])?
    private var styleTimer: Timer?
    /// Aperçu actif du lanceur (SPEC-078) : cadres relevés avant, stage de départ si une bascule a eu lieu.
    private struct ActivePreview {
        let request: LauncherPreviewRequest
        var saved: [WindowID: Rect] = [:]
        let returnTo: StageScope?
    }
    private var activePreview: ActivePreview?
    private var previewLease: Timer?
    /// Change à chaque début ou fin : une étape asynchrone d'un aperçu dépassé s'arrête.
    private var previewToken = 0
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
        gridPostEvent: @escaping (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) },
        memoryStore: LauncherMemoryStore = LauncherMemoryStore(),
        notifyRuleChoiceFailure: ((String) -> Void)? = nil,
        ruleAffinity: WindowRuleAffinityService? = nil
    ) {
        self.service = service
        self.events = events
        self.presenter = presenter
        self.gridPostEvent = gridPostEvent
        self.memoryStore = memoryStore
        self.ruleAffinity = ruleAffinity ?? WindowRuleAffinityService(eventLog: events)
        self.notifyRuleChoiceFailure = notifyRuleChoiceFailure ?? { message in
            let effects = AlfredLiveEffects(events: events, webSearchURL: "", reopen: { _ in })
            Task { await effects.notify(title: "Roadie", text: message) }
        }
    }

    public func start() {
        // Index des applications prêt avant la première ouverture de la barre (SPEC-073), et leurs icônes
        // réduites en fond à la taille des lignes (session 123).
        let rowIcon = LauncherRowMetrics(fontSize: TargetOverlayStyle.launcher(service.effectiveConfig.experimental.targetMode).commandTextFontSize).icon
        LauncherAppCatalog.shared.refresh { apps in LauncherIconRaster.prewarm(paths: apps.map(\.path), side: rowIcon) }
        let barConfig = service.effectiveConfig.experimental.targetMode
        LauncherRecentFiles.shared.refresh(extraTypes: barConfig.fileTypes, excluded: barConfig.fileExcludedFolders)
        // Premier dessin de la barre fait hors écran : polices et moteur de dessin prêts avant la première ouverture.
        let style = TargetOverlayStyle.launcher(service.effectiveConfig.experimental.targetMode)
        DispatchQueue.main.async { SearchBarRenderer.warmUp(style: style) }
        // Panneaux des Réglages Système lus en fond (session 123) : la première ouverture n'attend plus.
        DispatchQueue.global(qos: .utility).async { _ = LauncherSettingTargetsCache.shared.systemPanes() }
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
        // Session 108 : raccourcis BTT laissés en pause par un arrêt barre ouverte.
        LauncherBTTPause.shared.restoreAtStart()
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
        // `roadie launch` (SPEC-077) : aucune barre, la session ouverte n'est pas touchée.
        if command.name == "launcher.launch" {
            launch(command)
            return
        }
        // `roadie project …` (SPEC-080) : de même.
        switch command.name {
        case "project.save":
            let result = saveProject(named: command.string("name"))
            events.append(RoadieEvent(type: "project.command", details: ["command": "save", "message": result.message]))
            return
        case "project.open":
            let result = command.string("name").map(openProject) ?? refused("project open", "name")
            events.append(RoadieEvent(type: "project.command", details: ["command": "open", "message": result.message]))
            return
        case "launcher.undo":
            _ = undoLastMove()
            return
        case "workflow.run", "workflow.trigger":
            runWorkflowCommand(command)
            return
        case "workflow.alfred":
            // Ordre donné à Alfred par un script, traduit (SPEC-093 FR-004, FR-007).
            let order = command.string("order") ?? ""
            events.append(RoadieEvent(type: "launcher.alfred_call", details: ["order": order, "workflow": command.string("id") ?? ""]))
            if order == "search" {
                reopenSearch(command.string("text") ?? "")
            } else if order == "trigger" {
                var arguments = ["id": command.string("id") ?? "", "trigger": command.string("trigger") ?? ""]
                if let argument = command.string("argument") { arguments["argument"] = argument }
                runWorkflowCommand(TargetModeRuntimeCommand(name: "workflow.trigger", arguments: arguments))
            }
            return
        case "launcher.open_items":
            // Diagnostic SPEC-082 : comptes par application et par sorte, sans titre ni adresse.
            let service = service
            let events = events
            let tabs = command.bool("tabs")
            Task { @MainActor in
                let entries = await WindowSwitcherService(service: service).load().entries
                let items = await Self.openItems(entries, stageTitle: { _ in nil }, tabs: tabs)
                var counts: [String: Int] = [:]
                for item in items { counts["\(item.kind.rawValue):\(item.bundleID)", default: 0] += 1 }
                events.append(RoadieEvent(type: "launcher.open_items", details: counts.mapValues(String.init)))
            }
            return
        case "project.delete":
            do {
                let deleted = try command.string("name").map { try StageProjectStore().delete($0) } ?? false
                events.append(RoadieEvent(type: "project.command", details: ["command": "delete", "deleted": String(deleted)]))
            } catch {
                events.append(RoadieEvent(type: "project.delete_failed", details: ["reason": "persistence"]))
                let effects = AlfredLiveEffects(events: events, webSearchURL: "", reopen: { _ in })
                Task { await effects.notify(title: "Roadie", text: tr("Impossible de supprimer le projet.", "Could not delete the project.")) }
            }
            return
        default:
            break
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
        case "targets.search", "targets.actions": style = .launcher(config.experimental.targetMode)
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
        let clock = LauncherOpenClock.begin()
        // Focus clavier rendu après Échap (session 097) : lu avant que le panneau prenne le clavier.
        escapeFocus = NSWorkspace.shared.frontmostApplication
            .flatMap { $0.processIdentifier == getpid() ? nil : LauncherFocusSnapshot.capture($0) }
        // Touches de la barre prioritaires sur BTT (session 108) : ses raccourcis en conflit se mettent en pause.
        clock.mark("focus_capture")
        LauncherBTTPause.shared.barOpened(pauseKeys: config.bttPauseKeys)
        clock.mark("btt_pause")
        // Barre immédiate (FR-009) : cibles Roadie tout de suite, puis toutes les fenêtres visibles, lues
        // en arrière-plan, chacune affichée dès qu'elle est lue. 2 s par fenêtre au moins : la barre
        // n'attend plus la plus lente, une page chargée peut donc être lue en entier.
        var appTargets = service.effectiveConfig.experimental.appTargets
        appTargets.scope = "visible_windows"
        appTargets.timeoutMs = max(appTargets.timeoutMs, 2000)
        let scanConfig = appTargets
        let targets = TargetHintService(service: service, appTargetsConfig: appTargets)
        // Un seul relevé des fenêtres pour les cibles et le contexte de la barre (session 123).
        let snapshot = service.snapshot(followFocus: false)
        clock.mark("snapshot")
        let roadieTargets = targets.list(TargetQueryOptions(source: .roadie, maxResults: TargetSearchModel.maxTargets), snapshot: snapshot).targets
        clock.mark("roadie_targets")
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
            // Fenêtre active réelle (session 098) : celle du snapshot sans suivi du focus est la fenêtre
            // retenue pour la stage du premier écran, pas forcément celle de l'application au premier plan.
            let focused = service.focusedWindowID() ?? WindowSwitcherFocusHistory.shared.recentIDs.first
            let window = focused.flatMap { id in roadieTargets.first { $0.id == "window:\(id.rawValue)" } }.map(LauncherSubject.target)
            // Session 131 : un texte sélectionné passe avant la fenêtre (actions universelles d'Alfred).
            initialSubject = LauncherText.initialSubject(selection: Self.axSelectedText(), window: window)
            let kind: String = switch initialSubject { case .text?: "text"; case nil: "none"; default: "window" }
            events.append(RoadieEvent(type: "target_mode.actions_started", details: [
                "focusedWindowID": focused.map { String($0.rawValue) } ?? "none", "subject": kind]))
        }
        currentSession = presenter.startSearch(
            targets: roadieTargets,
            alphabet: appTargets.hintCharacters,
            style: .launcher(config),
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
            activate: { [weak self] target, verb in
                // Fenêtre Roadie : son bureau et sa stage s'affichent, comme dans le sélecteur (SPEC-084) ;
                // le seul focus activait l'application sans montrer une fenêtre d'un autre bureau.
                if verb == .focus, target.kind == .window, target.source == .roadie, let id = target.scope.windowId, let self {
                    self.focus(WindowID(rawValue: id))
                    return TargetActionResult(changed: true, message: "launcher: window \(id)", target: target)
                }
                return targets.activate(target: target, action: verb)
            },
            launcher: launcherContext(initialSubject: initialSubject, targets: roadieTargets, initialQuery: command.string("query"), snapshot: snapshot),
            onFinish: { [weak self] result in
                if let self { clock.finish(events: self.events) }
                self?.finish(result, command: command.name)
            }
        )
        clock.mark("session_start")
        // Premier tour libre du fil principal : la fenêtre peut être dessinée à l'écran.
        DispatchQueue.main.async { MainActor.assumeIsolated { clock.mark("main_free") } }
    }

    /// Lanceur de la barre (SPEC-073) : index des applications gardé en mémoire et rafraîchi à chaque
    /// ouverture, état des applications ouvertes, classement appris lu une fois par session.
    /// Écran de la barre (session 102) : `main` le premier écran, `active` celui qui contient le plus de la
    /// fenêtre active ; nil (écran du pointeur) pour `mouse` ou sans fenêtre active. O(e).
    nonisolated static func barScreen(_ setting: String, focused: CGRect?, screens: [CGRect]) -> CGRect? {
        switch setting {
        case "main": return screens.first
        case "active":
            guard let focused else { return nil }
            return screens.max { $0.intersection(focused).width * $0.intersection(focused).height
                < $1.intersection(focused).width * $1.intersection(focused).height }
                .flatMap { $0.intersects(focused) ? $0 : nil }
        default: return nil
        }
    }

    private func launcherContext(initialSubject: LauncherSubject? = nil, targets: [RoadieTarget] = [], initialQuery: String? = nil,
                                 snapshot provided: DaemonSnapshot? = nil) -> LauncherSearchContext {
        let catalog = LauncherAppCatalog.shared
        catalog.setExtraRoots(service.effectiveConfig.experimental.targetMode.appSearchPaths)
        let rankingStore = LauncherRankingStore()
        let state = service.effectiveStageStore.state()
        let running = Set(NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }.compactMap(\.bundleIdentifier))
        let snapshot = provided ?? service.snapshot(followFocus: false)
        LauncherOpenClock.current?.mark("context_snapshot")
        let names = WindowSwitcherService.stageLabels(in: state, liveWindowIDs: Set(snapshot.windows.map(\.window.id)))
        let homeDisplay = state.activeDisplayID ?? snapshot.displays.first?.id ?? DisplayID(rawValue: "none")
        let homeDesktop = state.currentDesktopID(for: homeDisplay)
        let activeStage = state.scopes.first { $0.displayID == homeDisplay && $0.desktopID == homeDesktop }
            .map { StageScope(displayID: homeDisplay, desktopID: homeDesktop, stageID: $0.activeStageID) }
        let affinity = WindowRuleAffinityService(eventLog: events)
        let rankingContext = activeStage.map { scope in
            LauncherSearchContext.rankingContext(scope, stage: state.scopes.first { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID }?
                .stages.first { $0.id == scope.stageID })
        }
        let webSearchURL = service.effectiveConfig.experimental.targetMode.webSearchURL
        // Apprentissage coupé (session 105) : classement vide, aucune visite enregistrée.
        let learns = service.effectiveConfig.experimental.targetMode.learningEnabled
        var context = LauncherSearchContext(
            apps: catalog.current,
            details: LauncherPlacement.details(runningBundleIDs: running, state: state, stageNames: names),
            ranking: learns ? rankingStore.load() : LauncherRanking(),
            refreshApps: { done in catalog.refresh(done: done) },
            launch: { [weak self] app in self?.launch(app) ?? TargetActionResult(changed: false, message: "launcher_unavailable") },
            recordVisit: { key, query in if learns { rankingStore.recordVisit(key, query: query, context: rankingContext) } },
            destinations: LauncherPlacement.destinations(state: state, displays: snapshot.displays, stageNames: names),
            newStageHome: (homeDisplay, homeDesktop),
            perform: { [weak self] action in
                self?.perform(action) ?? TargetActionResult(changed: false, message: "launcher_unavailable")
            }
        )
        context.activeStage = activeStage
        context.shownStages = Set(snapshot.displays.compactMap { display in
            let desktop = state.currentDesktopID(for: display.id)
            return state.scopes.first { $0.displayID == display.id && $0.desktopID == desktop }
                .map { StageScope(displayID: display.id, desktopID: desktop, stageID: $0.activeStageID) }
        })
        context.rankingContext = rankingContext
        // Session 131 : menus de l'application au premier plan, relus à chaque ouverture.
        LauncherMenuSearch.shared.reset()
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            context.frontApplication = (front.processIdentifier, front.localizedName ?? "")
        }
        context.pickModifier = LauncherPickModifier(config: service.effectiveConfig.experimental.targetMode.pickModifier)
        let modes = service.effectiveConfig.experimental.targetMode
        context.returnEffects = [.command: LauncherReturnEffect(config: modes.returnCommand, modifier: .command),
                                 .option: LauncherReturnEffect(config: modes.returnOption, modifier: .option),
                                 .control: LauncherReturnEffect(config: modes.returnControl, modifier: .control)]
        context.initialSubject = initialSubject
        context.tiling = { id in
            guard let entry = snapshot.windows.first(where: { $0.window.id == id }) else { return nil }
            return LauncherTilingState(pinned: entry.pin != nil, tiled: entry.window.isTileCandidate && entry.pin == nil,
                                       rule: affinity.tilingChoice(for: entry.window))
        }
        context.preview = { [weak self] request, done in self?.preview(request, ghost: done) ?? done(nil) }
        let aliasStore = LauncherAliasStore()
        context.aliases = aliasStore.load()
        context.projects = StageProjectStore().load().projects.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        // Liste de la barre vide (SPEC-081).
        let now = Date()
        let memory = memoryStore.load()
        let rules = service.effectiveConfig.rules
        let stageInfo: (StageScope) -> (key: String, title: String)? = { scope in
            guard let stage = state.scopes.first(where: { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID })?
                .stages.first(where: { $0.id == scope.stageID }) else { return nil }
            return (LauncherSearchContext.rankingContext(scope, stage: stage), names[scope] ?? stage.name)
        }
        let suggestions = memory.suggestions(at: now, identity: stageInfo, hasRule: { appName, scope in
            rules.contains { $0.enabled && $0.match.app == appName && $0.action.assignStage == scope.stageID.rawValue
                && $0.action.assignDesktop == String(scope.desktopID.rawValue) }
        })
        context.pendingRules = suggestions.count
        var idle: [LauncherList.Row] = []
        if let first = suggestions.first {
            idle += [.header(tr("Règle proposée", "Suggested rule")), .rule(first, .create), .rule(first, .later), .rule(first, .never)]
        }
        let windowTargets = Dictionary(targets.filter { $0.kind == .window }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Fenêtre active lue dans l'application au premier plan (session 098) : `snapshot.focusedWindowID`
        // désignait la fenêtre retenue pour la stage du premier écran (iTerm2 sur l'autre écran).
        LauncherOpenClock.current?.mark("idle_rows")
        let focused = service.focusedWindowID()
        LauncherOpenClock.current?.mark("focused_window")
        let recentIDs = WindowSwitcherFocusHistory.shared.recentIDs
        let previous = Self.previousWindow(recent: recentIDs, focused: focused, targets: windowTargets)
        events.append(RoadieEvent(type: "launcher.idle_back", details: [
            "focused": focused.map { String($0.rawValue) } ?? "none",
            "recent": recentIDs.prefix(3).map { String($0.rawValue) }.joined(separator: ","),
            "previous": previous?.id ?? "none"]))
        if let previous { idle += [.header(tr("Revenir", "Go back")), .target(previous)] }
        let batchMoves = memory.undoableBatch(at: now, currentScope: { id in snapshot.windows.first { $0.window.id == id }?.scope })
        if batchMoves.count > 1, let move = batchMoves.last, let from = move.from, let info = stageInfo(from) {
            // Envoi groupé (SPEC-091) : une ligne pour tout le lot.
            let target = RoadieTarget(id: "window:\(move.windowID.rawValue)", kind: .window, title: move.appName, source: .roadie,
                                      scope: TargetScopeSnapshot(scope: move.to, windowId: move.windowID), actions: [.focus])
            let action = LauncherAction(subject: .target(target), verb: .sendTo,
                                        destination: LauncherDestination(kind: .stage(from), title: info.title, detail: ""))
            idle += [.header(tr("Annuler", "Undo")), .action("undo-batch", action,
                                                 tr("Remettre les \(batchMoves.count) fenêtres à leur place", "Put the \(batchMoves.count) windows back"),
                                                 tr("envoi groupé", "sent together") + " \(ClosedWindow.ago(move.at, now: now))")]
        } else if let move = memory.undoable(at: now, currentScope: { id in snapshot.windows.first { $0.window.id == id }?.scope }),
           let from = move.from, let info = stageInfo(from) {
            let target = windowTargets["window:\(move.windowID.rawValue)"]
                ?? RoadieTarget(id: "window:\(move.windowID.rawValue)", kind: .window, title: move.appName, source: .roadie,
                                scope: TargetScopeSnapshot(scope: move.to, windowId: move.windowID), actions: [.focus])
            let action = LauncherAction(subject: .target(target), verb: .sendTo,
                                        destination: LauncherDestination(kind: .stage(from), title: info.title, detail: ""))
            idle += [.header(tr("Annuler", "Undo")), .action("undo", action, tr("Remettre \(move.appName) dans \(info.title)", "Put \(move.appName) back in \(info.title)"),
                                                 tr("déplacée", "moved") + " \(ClosedWindow.ago(move.at, now: now))")]
        }
        let closedRows = ClosedWindow.recent(in: state, at: now).compactMap { closed -> LauncherList.Row? in
            guard let app = catalog.current.first(where: { $0.bundleID == closed.bundleID }) ?? Self.app(bundleID: closed.bundleID),
                  let info = stageInfo(closed.stage) else { return nil }
            let action = LauncherAction(subject: .app(app), verb: .openIn,
                                        destination: LauncherDestination(kind: .stage(closed.stage), title: info.title, detail: ""))
            return .action("closed:\(closed.bundleID):\(closed.title)", action,
                           tr("Rouvrir", "Reopen") + " \(app.name)" + (closed.title.isEmpty ? "" : " · \(closed.title)"),
                           tr("fermée", "closed") + " \(ClosedWindow.ago(closed.closedAt, now: now)) · \(info.title)")
        }
        if !closedRows.isEmpty { idle += [.header(tr("Fermées récemment", "Recently closed"))] + closedRows }
        let targetModeConfig = service.effectiveConfig.experimental.targetMode
        if targetModeConfig.idleFrequentEnabled, let rankingContext {
            let ranking = context.ranking
            let focusedBundle = snapshot.windows.first { $0.window.id == focused }?.window.bundleID
            let habits = ranking.entries.filter { $0.key.hasPrefix("app:") && $0.value.contexts?[rankingContext] != nil }
                .sorted { ranking.frecency($0.key, at: now, context: rankingContext) > ranking.frecency($1.key, at: now, context: rankingContext) }
                .compactMap { entry in catalog.current.first { $0.rankingKey == entry.key } }
                .filter { $0.bundleID != focusedBundle }
                .prefix(targetModeConfig.idleFrequentCount)
            if !habits.isEmpty { idle += [.header(tr("Souvent ici", "Often here"))] + habits.map { .app($0, detail: tr("souvent dans cette stage", "often in this stage")) } }
        }
        let recent = targetModeConfig.idleRecentSearchesEnabled
            ? LauncherHistoryStore().load().recent(targetModeConfig.idleRecentSearchesCount) : []
        if !recent.isEmpty { idle += [.header(tr("Recherches récentes", "Recent searches"))] + recent.map(LauncherList.Row.history) }
        context.idleRows = idle
        // Documents et onglets de l'ouverture précédente montrés tout de suite (moins d'une minute), puis
        // remplacés par la lecture du moment, qui interroge chaque application et navigateur (session 123).
        let previousItems = lastOpenItems.flatMap { now.timeIntervalSince($0.at) < 60 ? $0.items : nil }
        context.loadOpenItems = { [service, weak self] done in
            if let previousItems { done(previousItems) }
            Task { @MainActor in
                LauncherOpenClock.current?.mark("open_items_begin")
                let entries = await WindowSwitcherService(service: service).load().entries
                LauncherOpenClock.current?.mark("open_items_entries")
                let items = await Self.openItems(entries, stageTitle: { scope in scope.flatMap { names[$0] } })
                self?.lastOpenItems = (Date(), items)
                LauncherOpenClock.current?.mark("open_items_fresh")
                done(items)
            }
        }
        context.activateOpenItem = { [weak self] item in
            self?.activate(item) ?? TargetActionResult(changed: false, message: "launcher_unavailable")
        }
        context.ruleChoice = { [weak self] suggestion, choice in
            self?.chooseRule(suggestion, choice) ?? TargetActionResult(changed: false, message: "launcher_unavailable")
        }
        context.aliasAction = { alias in alias.action(state: state, activeStage: activeStage, home: (homeDisplay, homeDesktop)) }
        context.stageName = { scope in
            state.scopes.first { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID }?
                .stages.first { $0.id == scope.stageID }
                .flatMap { StagePresentationOrder.isNamed($0) ? $0.name : nil }
        }
        context.saveAlias = { [events] alias, name in
            do {
                let previous = try aliasStore.save(alias, as: name)
                events.append(RoadieEvent(type: "launcher.alias_saved", details: ["replaced": String(previous != nil)]))
                return .success(previous)
            } catch {
                events.append(RoadieEvent(type: "launcher.alias_save_failed", details: ["reason": "persistence"]))
                return .failure(error)
            }
        }
        context.endPreview = { [weak self] commit in self?.endPreview(commit: commit) }
        context.performBatch = { [weak self] actions in self?.performBatch(actions) ?? TargetActionResult(changed: false, message: "launcher_unavailable") }
        context.undo = { [weak self] in self?.undoLastMove() ?? TargetActionResult(changed: false, message: "launcher_unavailable") }
        context.initialQuery = initialQuery
        LauncherOpenClock.current?.mark("stores")
        workflowContext(&context, webSearchURL: webSearchURL)
        LauncherOpenClock.current?.mark("workflows")
        context.workflowGrid = pendingGrid
        let viewStore = LauncherViewStore()
        context.viewBook = viewStore.load()
        context.saveViews = { book in viewStore.save(book) }
        context.viewCycleKey = service.effectiveConfig.experimental.targetMode.viewCycleHotkey
        context.barKeys = service.effectiveConfig.experimental.targetMode.barKeys
        // Place et écran de la barre (session 102).
        let barConfig = service.effectiveConfig.experimental.targetMode
        let positionStore = LauncherPositionStore()
        context.defaultBarPlacement = SearchBarPlacement(setting: barConfig.barPosition)
        context.barPlacement = (barConfig.barSavePosition ? positionStore.load() : nil) ?? context.defaultBarPlacement
        let focusedFrame = snapshot.focusedWindowID.flatMap { id in snapshot.windows.first { $0.window.id == id } }
            .map { RoadieScreenCoordinate.axRectToNS($0.window.frame.cgRect) }
        context.barScreenFrame = Self.barScreen(barConfig.barScreen, focused: focusedFrame, screens: NSScreen.screens.map(\.frame))
        let savesPosition = barConfig.barSavePosition
        context.savePlacement = { placement in if savesPosition || placement == nil { positionStore.save(placement) } }
        context.terminalApp = barConfig.terminalApp
        context.calcOpensCalculator = barConfig.calcOpensCalculator
        context.learnsVerbOrder = barConfig.learnVerbOrder
        if barConfig.settingsInSearch {
            context.settingTargets = LauncherSettingTargets.roadie() + LauncherSettingTargetsCache.shared.systemPanes()
        }
        context.fileKeywords = LauncherFileKeywords(content: barConfig.contentSearchKeyword, tag: barConfig.tagSearchKeyword,
                                                    open: barConfig.openKeyword, find: barConfig.findKeyword)
        context.fileTypes = barConfig.fileTypes
        context.fileExcluded = barConfig.fileExcludedFolders
        context.calcLocale = LauncherCalculator.locale(barConfig.calcDecimal)
        context.calcGrouping = barConfig.calcGrouping
        context.pathSort = barConfig.pathSort
        // Session 131 : raccourcis de l'app Raccourcis, lus en fond pour les prochaines ouvertures.
        LauncherAppleShortcuts.shared.refresh()
        context.systemCommands = LauncherSystemCommand.all(confirmQuitAll: barConfig.confirmQuitAll) + LauncherAppleShortcuts.shared.commands
        if barConfig.webHistoryDays > 0 {
            let browsers = barConfig.bookmarkBrowsers, days = barConfig.webHistoryDays
            context.loadHistory = { done in
                DispatchQueue.global(qos: .userInitiated).async {
                    let pages = LauncherWebHistoryStore.shared.loadIndex(browsers: browsers, days: days)
                    DispatchQueue.main.async { MainActor.assumeIsolated { done(pages) } }
                }
            }
        }
        if barConfig.bookmarksEnabled {
            let browsers = barConfig.bookmarkBrowsers
            context.loadBookmarks = { done in
                DispatchQueue.global(qos: .userInitiated).async {
                    let bookmarks = LauncherBookmarkStore.shared.loadIndex(browsers: browsers)
                    DispatchQueue.main.async { MainActor.assumeIsolated { done(bookmarks) } }
                }
            }
        }
        if let grid = pendingGrid {
            let id = grid.entry.id
            context.subscribeGrid = { [weak self] update in self?.openGrid = (id, update) }
        }
        pendingGrid = nil
        // Web et historique (SPEC-090) : la dernière saisie revient sous 5 minutes, sélectionnée.
        let targetMode = service.effectiveConfig.experimental.targetMode
        context.webSearches = targetMode.webSearches ?? WebSearch.defaults
        context.webSearchTemplate = webSearchURL
        context.fallbackSearches = targetMode.fallbackSearches
        let historyStore = LauncherHistoryStore()
        let history = historyStore.load()
        context.recordQuery = { query in historyStore.record(query) }
        if initialQuery == nil, initialSubject == nil, context.workflowGrid == nil, let resumed = history.resumable(at: now) {
            context.initialQuery = resumed
            context.restoredQuery = true
        }
        LauncherOpenClock.current?.mark("context")
        context.webSearch = { [events, weak self] text in
            guard let url = LauncherWeb.searchURL(webSearchURL, query: text) else {
                return TargetActionResult(changed: false, message: "launcher web: invalid url", error: "web_search_url")
            }
            NSWorkspace.shared.open(url)
            self?.followBrowser(url)
            events.append(RoadieEvent(type: "launcher.web_search", details: ["host": url.host ?? ""]))
            return TargetActionResult(changed: true, message: "launcher web: \(url.host ?? "")")
        }
        return context
    }

    // MARK: - Workflows (SPEC-088)

    /// Workflows de la barre : index relu s'il a changé, Script Filter lancé en fond, schéma exécuté
    /// après la fermeture avec les vrais effets. Le journal ne garde ni saisie ni résultat (FR-011).
    private func workflowContext(_ context: inout LauncherSearchContext, webSearchURL: String) {
        let config = service.effectiveConfig.experimental.targetMode
        guard config.workflowsEnabled else { return }
        let workflows = AlfredWorkflowIndex.shared.workflows(alfred: config.alfredWorkflows)
        let byID = Dictionary(workflows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let events = events
        context.workflowEntries = AlfredWorkflowIndex.entries(workflows)
        context.workflowTriggers = AlfredWorkflowIndex.triggers(workflows)
        context.runScriptFilter = { entry, argument, done in
            guard let workflow = byID[entry.workflowID], let object = workflow.objects[entry.objectUID],
                  let script = entry.kind == .fileFilter ? AlfredFileFilter.script(object, argument: argument) : AlfredScript(object: object) else {
                DispatchQueue.main.async { MainActor.assumeIsolated { done(nil, "script absent") } }
                return nil
            }
            // Cache demandé par le script (session 120) : même entrée, même saisie, réponse encore valable.
            let cacheKey = "\(entry.id)\u{1F}\(argument)"
            if let cached = AlfredScriptFilterCache.shared.response(for: cacheKey) {
                DispatchQueue.main.async { MainActor.assumeIsolated { done(cached, nil) } }
                return nil
            }
            let started = Date()
            let arguments = argument.isEmpty && object.bool("argumenttreatemptyqueryasnil") ? [] : [argument]
            return AlfredScriptRunner.start(script, query: argument, arguments: arguments, workflow: workflow,
                                            variables: workflow.configuredVariables, keyword: entry.keyword) { result in
                let response = entry.kind == .fileFilter ? AlfredFileFilter.response(result.text)
                    : result.output.isEmpty ? nil : AlfredScriptFilterResponse.parse(result.output)
                if let response, !result.cancelled { AlfredScriptFilterCache.shared.store(response, for: cacheKey) }
                events.append(RoadieEvent(type: "launcher.workflow_filter", details: [
                    "workflow": workflow.bundleID.isEmpty ? workflow.id : workflow.bundleID,
                    "ms": String(Int(Date().timeIntervalSince(started) * 1000)), "status": String(result.status),
                    "items": String(response?.items.count ?? -1), "cancelled": String(result.cancelled), "timedOut": String(result.timedOut)]))
                guard !result.cancelled else { return }
                let error = result.failure ?? (result.timedOut ? tr("délai dépassé", "timed out") : nil)
                DispatchQueue.main.async { MainActor.assumeIsolated { done(response, error) } }
            }
        }
        context.runWorkflow = { [weak self] entry, arg, variables, modifiers in
            guard let workflow = byID[entry.workflowID] else {
                return TargetActionResult(changed: false, message: "launcher workflow: absent", error: "workflow")
            }
            let effects = Self.liveEffects(self, events: events, webSearchURL: webSearchURL)
            Task.detached {
                _ = await AlfredWorkflowEngine(effects: effects, workflows: workflows)
                    .run(workflow, from: entry.objectUID, arg: arg, variables: variables, modifiers: modifiers)
            }
            return TargetActionResult(changed: true, message: "launcher workflow: \(workflow.bundleID.isEmpty ? workflow.id : workflow.bundleID)")
        }
    }

    /// `roadie workflow run|trigger` (SPEC-089 FR-001, FR-002) : workflow trouvé par dossier ou
    /// identifiant ; objet par `uid` ou déclencheur externe par son nom. Argument donné, sinon celui
    /// d'un raccourci (sélection, presse-papiers, texte). Journal sans argument.
    private func runWorkflowCommand(_ command: TargetModeRuntimeCommand) {
        let config = service.effectiveConfig.experimental.targetMode
        let workflows = AlfredWorkflowIndex.shared.workflows(alfred: config.alfredWorkflows)
        let events = events
        guard let id = command.string("id"), let workflow = workflows.first(where: { $0.id == id || $0.bundleID == id }) else {
            events.append(RoadieEvent(type: "launcher.workflow_command", details: ["outcome": "workflow_not_found"]))
            return
        }
        let uid = command.name == "workflow.trigger"
            ? AlfredWorkflowEngine.externalTrigger(command.string("trigger") ?? "", in: workflow)?.uid : command.string("object")
        guard let uid, let object = workflow.objects[uid] else {
            events.append(RoadieEvent(type: "launcher.workflow_command", details: ["outcome": "object_not_found", "workflow": workflow.id]))
            return
        }
        let variables = command.string("variables").flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] } ?? [:]
        let argument = command.string("argument")
        let webSearchURL = config.webSearchURL
        Task { @MainActor [weak self] in
            let arg: [String] = if let argument { [argument] }
                else if object.type == "trigger.hotkey" { await Self.hotkeyArgument(object) }
                else if object.type == "trigger.remote" { AlfredWorkflowEngine.remoteArgument(object) } else { [] }
            let effects = Self.liveEffects(self, events: events, webSearchURL: webSearchURL)
            let engine = AlfredWorkflowEngine(effects: effects, workflows: workflows)
            _ = await engine.start(workflow, at: uid, arg: arg, variables: variables)
        }
    }

    /// Argument d'un raccourci d'Alfred (research R2 de la 089) : 0 sélection, 1 presse-papiers,
    /// 2 presse-papiers de recherche, 3 texte fixe, autre : aucun.
    private static func hotkeyArgument(_ object: AlfredObject) async -> [String] {
        switch object.int("argument") ?? 0 {
        case 0: return [await selectedText() ?? ""]
        case 1: return [NSPasteboard.general.string(forType: .string) ?? ""]
        case 2: return [NSPasteboard(name: .find).string(forType: .string) ?? ""]
        case 3: return [object.string("argumenttext") ?? ""]
        default: return []
        }
    }

    /// Texte sélectionné de l'élément actif, par l'accessibilité seule et en 0,3 s au plus : l'ouverture de la barre
    /// n'attend pas un ⌘C simulé (session 131). O(1) appels AX.
    private static func axSelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.3)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.3)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// Texte choisi dans l'application au premier plan : attribut AX, sinon ⌘C simulé avec le
    /// presse-papiers remis comme avant.
    private static func selectedText() async -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success,
               let text = value as? String, !text.isEmpty { return text }
        }
        let board = NSPasteboard.general
        // Tout le contenu est gardé (images, fichiers…), pas seulement le texte (audit V15 087-091, F1).
        let previous = PasteboardSnapshot(board), count = board.changeCount
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: down) else { continue }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard board.changeCount != count else { return nil }
        let text = board.string(forType: .string)
        previous.restore(to: board)
        return text
    }

    /// Barre rouverte sur un texte (Show Alfred, Script Filter atteint par un schéma).
    private func reopenSearch(_ text: String) {
        handle(TargetModeRuntimeCommand(name: "targets.search", arguments: ["query": text]))
    }

    /// Barre rouverte en grille (SPEC-092) : la vue attend la prochaine ouverture. Tuiles d'une grille
    /// déjà ouverte sur son texte d'attente : envoyées à cette barre, jamais rouverte si elle est fermée
    /// (session 095).
    private func presentGrid(_ view: AlfredGridView) {
        if !view.isWaiting, let open = openGrid, open.id == view.entry.id {
            openGrid = nil
            open.update(view)
            events.append(RoadieEvent(type: "launcher.workflow_grid", details: ["workflow": view.entry.workflowID, "items": String(view.items.count), "update": "true"]))
            return
        }
        pendingGrid = view
        events.append(RoadieEvent(type: "launcher.workflow_grid", details: ["workflow": view.entry.workflowID, "items": String(view.items.count)]))
        // Une barre encore ouverte garderait sa liste (recherche répétée) : elle laisse la place à la grille.
        currentSession?.cancel()
        currentSession = nil
        handle(TargetModeRuntimeCommand(name: "targets.search"))
    }

    /// Effets réels d'un workflow lancé depuis la barre, une commande ou une vue : barre rouverte, grille,
    /// vues Texte, Image et PDF, navigateur suivi. `owner` faible : un effet après l'arrêt de Roadie ne fait rien.
    private nonisolated static func liveEffects(_ owner: TargetModeRuntimeController?, events: EventLog, webSearchURL: String) -> AlfredLiveEffects {
        AlfredLiveEffects(events: events, webSearchURL: webSearchURL, reopen: { [weak owner] text in owner?.reopenSearch(text) },
                          presentGrid: { [weak owner] view in owner?.presentGrid(view) },
                          presentText: { [weak owner] view in owner?.presentText(view) },
                          presentMedia: { [weak owner] view in owner?.presentMedia(view) },
                          follow: { [weak owner] url in owner?.followBrowser(url) })
    }

    /// Vue Image ou PDF d'un workflow (session 118) : fenêtre d'aperçu ; Retour envoie le chemin à la suite.
    private func presentMedia(_ view: AlfredMediaView) {
        let config = service.effectiveConfig.experimental.targetMode
        let workflows = AlfredWorkflowIndex.shared.workflows(alfred: config.alfredWorkflows)
        guard let workflow = workflows.first(where: { $0.id == view.workflowID }) else { return }
        let events = events, webSearchURL = config.webSearchURL
        events.append(RoadieEvent(type: "launcher.workflow_media", details: ["workflow": workflow.bundleID.isEmpty ? workflow.id : workflow.bundleID,
                                                                              "kind": view.kind.rawValue]))
        WorkflowMediaPanel.show(view) { [weak self] path, modifiers in
            let effects = Self.liveEffects(self, events: events, webSearchURL: webSearchURL)
            Task.detached {
                _ = await AlfredWorkflowEngine(effects: effects, workflows: workflows)
                    .run(workflow, from: view.objectUID, arg: [path], variables: view.variables, modifiers: modifiers)
            }
        }
    }

    /// Vue Texte d'un workflow (session 117) : fenêtre ; son script relancé par la saisie, puis la suite du
    /// schéma depuis la brique avec le texte et les touches tenues. Journal sans texte.
    private func presentText(_ view: AlfredTextView) {
        let config = service.effectiveConfig.experimental.targetMode
        let workflows = AlfredWorkflowIndex.shared.workflows(alfred: config.alfredWorkflows)
        guard let workflow = workflows.first(where: { $0.id == view.workflowID }) else { return }
        let events = events, webSearchURL = config.webSearchURL
        events.append(RoadieEvent(type: "launcher.workflow_text", details: ["workflow": workflow.bundleID.isEmpty ? workflow.id : workflow.bundleID,
                                                                             "behaviour": String(view.behaviour.rawValue)]))
        let plain = (workflow.connections[view.objectUID] ?? []).contains { $0.modifiers == 0 }
        var runScript: WorkflowTextPanel.RunScript?
        if let file = view.scriptFile {
            runScript = { input, variables, done in
                _ = AlfredScriptRunner.start(AlfredScript(language: 8, source: "", file: file), query: input, arguments: [input],
                                             workflow: workflow, variables: variables, keyword: "") { result in
                    guard !result.cancelled else { return }
                    let failure: String? = result.failure ?? (result.timedOut ? tr("délai dépassé", "timed out") : nil)
                    let response: AlfredTextResponse? = failure == nil ? AlfredTextResponse.parse(result.text) : nil
                    DispatchQueue.main.async { MainActor.assumeIsolated { done(response, failure) } }
                }
            }
        }
        WorkflowTextPanel.show(view, plainContinues: plain, runScript: runScript) { [weak self] text, modifiers, variables in
            let effects = Self.liveEffects(self, events: events, webSearchURL: webSearchURL)
            Task.detached {
                _ = await AlfredWorkflowEngine(effects: effects, workflows: workflows)
                    .run(workflow, from: view.objectUID, arg: [text], variables: variables, modifiers: modifiers)
            }
        }
    }

    // MARK: - Verbes du lanceur (SPEC-074)

    /// Exécute un verbe. Les effets qui attendent une application ou une fenêtre partent en tâche ;
    /// le résultat rendu décrit ce qui a été demandé. Chaque issue est journalisée.
    private func perform(_ action: LauncherAction) -> TargetActionResult {
        let label = "launcher \(action.verb.rawValue)"
        if action.position != nil { position(after: action) }
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
            case .forceQuit:
                NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).forEach { $0.forceTerminate() }
            case .bringHere:
                bringHere(app, into: action.destination.flatMap(stageScope) ?? activeStageScope())
            case .recentDocuments:
                // Document récent (session 116) : ouvert avec cette application, même si une autre est celle par défaut.
                guard case .document(let path)? = action.destination?.kind else { return refused(label, "destination") }
                NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: URL(fileURLWithPath: app.path),
                                        configuration: NSWorkspace.OpenConfiguration())
            case .relaunch:
                relaunch(app)
            case .pinApp:
                LauncherAppsPins().toggle(app.bundleID)
            case .quitOthers:
                // Session 131 : comme « Tout quitter » (session 105), sauf l'application choisie.
                let keep = Set(NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).map(\.processIdentifier))
                let apps = NSWorkspace.shared.runningApplications
                let pids = Set(LauncherSystemCommand.quitAllTargets(apps.map { ($0.bundleIdentifier, $0.activationPolicy == .regular, $0.processIdentifier) },
                                                                    ownPID: ProcessInfo.processInfo.processIdentifier)).subtracting(keep)
                apps.filter { pids.contains($0.processIdentifier) }.forEach { $0.terminate() }
            default:
                return refused(label, "verb")
            }
            return TargetActionResult(changed: true, message: "\(label): \(app.bundleID)")
        case .file(let file):
            return performFile(action, file: file, label: label)
        case .url(let url):
            return performURL(action, url: url, label: label)
        case .text(let text):
            return performText(action.verb, text: text, label: label)
        case .openItem(let item):
            return performOpenItem(action.verb, item: item, label: label)
        case .project(let name):
            switch action.verb {
            case .reopenProject: return openProject(named: name)
            case .deleteProject:
                do {
                    let deleted = try StageProjectStore().delete(name)
                    return TargetActionResult(changed: deleted, message: "project delete: \(deleted)")
                } catch {
                    return TargetActionResult(changed: false, message: tr("Projet non supprimé", "Project not deleted"), error: "project_not_deleted")
                }
            default: return refused(label, "verb")
            }
        case .target(let target):
            let result = perform(action.verb, on: target, destination: action.destination, label: label)
            // ⌘ Retour : Roadie va à la fenêtre envoyée dans sa nouvelle stage.
            if action.follow, result.changed, let id = target.scope.windowId { focus(WindowID(rawValue: id)) }
            return result
        }
    }

    // MARK: - Adresses (SPEC-090)

    /// Navigateurs Chromium : `--new-window` est transmis à l'instance ouverte (research R2).
    private static let chromiumBrowsers: Set<String> = ["com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac",
                                                        "company.thebrowser.Browser", "com.vivaldi.Vivaldi"]

    /// Ouvrir (navigateur par défaut), ouvrir dans une stage ou ici (nouvelle fenêtre placée), copier.
    private func performURL(_ action: LauncherAction, url: URL, label: String) -> TargetActionResult {
        switch action.verb {
        case .open:
            NSWorkspace.shared.open(url)
            followBrowser(url)
        case .openIn, .bringHere:
            guard let scope = action.verb == .openIn ? action.destination.flatMap(stageScope) : action.destination.flatMap(stageScope) ?? activeStageScope()
            else { return refused(label, "destination") }
            openURLWindow(url, into: scope)
        case .copyPath:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        case .emailText:
            guard let mail = LauncherText.mailURL(body: url.absoluteString) else { return refused(label, "email") }
            NSWorkspace.shared.open(mail)
        case .largeType:
            LargeTypePanel.show(url.absoluteString)
        default:
            return refused(label, "verb")
        }
        events.append(RoadieEvent(type: "launcher.url", details: ["verb": action.verb.rawValue, "host": url.host ?? ""]))
        return TargetActionResult(changed: true, message: "\(label): \(url.host ?? "")")
    }

    /// Après l'ouverture d'une adresse : Roadie va à la fenêtre du navigateur qui l'a reçue, dans sa stage
    /// (session 094). Le navigateur passe au premier plan ; sa fenêtre active est celle de l'onglet. Sans
    /// elle (lecture AX impossible), la fenêtre préférée de l'application, comme pour la lancer. O(w).
    private func followBrowser(_ url: URL) {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: url), let bundle = Bundle(url: app)?.bundleIdentifier else { return }
        let service = service
        let events = events
        let switcher = WindowSwitcherService(service: service)
        Task { @MainActor in
            // Laisser le navigateur prendre l'adresse et passer devant (délais choisis, non mesurés) ;
            // un second essai si aucune fenêtre n'est encore lisible (session 095).
            for (attempt, delay) in [450, 700].enumerated() {
                try? await Task.sleep(for: .milliseconds(delay))
                let loaded = await switcher.load()
                let windows = loaded.entries.filter { $0.window.bundleID == bundle }
                let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
                let active = frontmost == bundle ? service.focusedWindowID() : nil
                guard let entry = windows.first(where: { $0.id == active }) ?? LauncherPlacement.preferredWindow(windows, state: loaded.persisted) else {
                    events.append(RoadieEvent(type: "launcher.follow_browser", details: [
                        "bundleID": bundle, "outcome": "no_window", "attempt": String(attempt + 1), "entries": String(loaded.entries.count),
                        "snapshot": String(loaded.snapshot != nil), "frontmost": frontmost]))
                    continue
                }
                let result = switcher.activate(entry)
                // Trace du focus clavier après l'activation : la fenêtre de l'onglet doit l'avoir.
                try? await Task.sleep(for: .milliseconds(300))
                let after = service.focusedWindowID()
                events.append(RoadieEvent(type: "launcher.follow_browser", details: [
                    "bundleID": bundle, "outcome": "activated", "attempt": String(attempt + 1), "windowID": String(entry.id.rawValue),
                    "tabWindow": String(entry.id == active), "frontmost": frontmost,
                    "focusAfter": after.map { String($0.rawValue) } ?? "", "keyboardFocus": String(after == entry.id),
                    "message": result.message]))
                return
            }
        }
    }

    /// Nouvelle fenêtre du navigateur par défaut avec l'adresse, puis placée dans la stage (R2) :
    /// Chromium `--new-window`, Safari par AppleScript, les autres ⌘N puis l'adresse (un onglet vide
    /// peut rester, limite notée).
    private func openURLWindow(_ url: URL, into scope: StageScope) {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: url), let bundle = Bundle(url: app)?.bundleIdentifier else {
            NSWorkspace.shared.open(url)
            return
        }
        let service = service
        let events = events
        let switcher = WindowSwitcherService(service: service)
        Task { @MainActor in
            let known = Set(await switcher.load().entries.filter { $0.window.bundleID == bundle }.map(\.id))
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
            if Self.chromiumBrowsers.contains(bundle) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-na", app.path, "--args", "--new-window", url.absoluteString]
                try? process.run()
            } else if bundle == "com.apple.Safari" {
                _ = await LauncherBrowsers.run("tell application id \"com.apple.Safari\"\nactivate\nmake new document with properties {URL:\"\(url.absoluteString.applescriptEscaped)\"}\nend tell", timeout: 5)
            } else if let running, !known.isEmpty {
                running.activate()
                try? await Task.sleep(for: .milliseconds(300))
                Self.postNewWindowShortcut(to: running.processIdentifier)
                try? await Task.sleep(for: .milliseconds(500))
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.open(url)
            }
            await Self.placeNewWindow(bundleID: bundle, known: known, into: scope, service: service, events: events)
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
            case .document, .folder, .application, .tag:
                return refused(label, "destination")
            }
            return TargetActionResult(changed: true, message: message)
        case (.window, .focus):
            // Phrase avec position (« terminal gauche ») : aller à la fenêtre, puis la position.
            guard let window = scope.windowId.map(WindowID.init(rawValue:)) else { return refused(label, "window") }
            focus(window)
            return TargetActionResult(changed: true, message: label)
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
        case (.stage, .saveProject):
            guard let display = scope.displayId, let desktop = scope.desktopId, let stage = scope.stageId else { return refused(label, "stage") }
            let state = service.effectiveStageStore.state()
            let key = StageScope(displayID: DisplayID(rawValue: display), desktopID: DesktopID(rawValue: desktop), stageID: StageID(rawValue: stage))
            guard let named = state.scopes.first(where: { $0.displayID == key.displayID && $0.desktopID == key.desktopID })?
                .stages.first(where: { $0.id == key.stageID }), StagePresentationOrder.isNamed(named) else { return refused(label, "anonymous") }
            return saveProject(named: named.name)
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
        case .desktop, .display, .document, .folder, .application, .tag:
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
            await Self.placeNewWindow(bundleID: app.bundleID, known: known, into: scope, service: service, events: events)
        }
    }

    /// Première fenêtre inconnue de ce paquet apparue en 10 s : elle rejoint la stage, une seule fois, puis
    /// Roadie y va (intention de placement F5). Sans nouvelle fenêtre dans ce délai : rien n'est déplacé.
    @discardableResult
    private static func placeNewWindow(bundleID: String, known: Set<WindowID>, into scope: StageScope,
                                       service: SnapshotService, events: EventLog) async -> WindowID? {
        let switcher = WindowSwitcherService(service: service)
        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(200))
            let entries = await switcher.load().entries
            guard let fresh = entries.first(where: { $0.window.bundleID == bundleID && !known.contains($0.id) }) else { continue }
            let result = WindowContextActions(snapshotService: service, stageStore: service.effectiveStageStore, eventLog: events)
                .assign(windowID: fresh.id, to: scope.stageID, desktopID: scope.desktopID, displayID: scope.displayID)
            events.append(RoadieEvent(type: "launcher.placed", details: [
                "bundleID": bundleID, "windowID": String(fresh.id.rawValue), "stage": scope.description, "message": result.message]))
            if let placed = await switcher.load().entries.first(where: { $0.id == fresh.id }) { _ = switcher.activate(placed) }
            return fresh.id
        }
        events.append(RoadieEvent(type: "launcher.placement_expired", details: ["bundleID": bundleID, "stage": scope.description]))
        return nil
    }

    // MARK: - Projets (SPEC-080)

    /// Garde la stage nommée `name` (défaut : stage active) comme projet : fenêtres vivantes, document ou
    /// adresse lus par l'accessibilité, forme de la disposition. Une stage anonyme est refusée.
    private func saveProject(named name: String?) -> TargetActionResult {
        let state = service.effectiveStageStore.state()
        guard let scope = name.map({ LauncherSearchContext.stage(for: "stage:\(LauncherMatch.fold($0))", in: state) }) ?? activeStageScope(),
              let stage = state.scopes.first(where: { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID })?
                .stages.first(where: { $0.id == scope.stageID }) else { return refused("project save", "stage") }
        guard StagePresentationOrder.isNamed(stage) else { return refused("project save", "anonymous") }
        let service = service
        let events = events
        Task { @MainActor in
            let entries = await WindowSwitcherService(service: service).load().entries.filter { $0.scope == scope }
            let windows = await Self.projectWindows(entries)
            let project = StageProject.capture(name: stage.name, members: stage.members.map(\.windowID), windows: windows,
                                               tree: stage.bspTree, at: Date())
            do {
                try StageProjectStore().save(project)
                events.append(RoadieEvent(type: "project.saved", details: [
                    "windows": String(project.windows.count),
                    "documents": String(project.windows.filter { $0.document != nil || $0.url != nil }.count),
                    "tree": String(project.tree != nil)]))
            } catch {
                events.append(RoadieEvent(type: "project.save_failed", details: ["reason": "persistence"]))
                let effects = AlfredLiveEffects(events: events, webSearchURL: "", reopen: { _ in })
                await effects.notify(title: "Roadie", text: tr("Impossible d'enregistrer le projet « \(stage.name) ».", "Could not save the project “\(stage.name)”."))
            }
        }
        return TargetActionResult(changed: false, message: "project save scheduled: \(stage.name)")
    }

    /// De quoi rouvrir chaque fenêtre : application, document ou adresse, lus hors du fil principal. O(w).
    private static func projectWindows(_ entries: [WindowSwitcherEntry]) async -> [WindowID: ProjectWindow] {
        let groups = Dictionary(grouping: entries, by: \.window.pid)
        return await Task.detached(priority: .userInitiated) {
            var result: [WindowID: ProjectWindow] = [:]
            for (pid, group) in groups {
                guard let appPath = NSRunningApplication(processIdentifier: pid)?.bundleURL?.path else { continue }
                let elements = axWindowElements(pid: pid)
                for entry in group {
                    let read = elements[CGWindowID(entry.id.rawValue)].map(axDocumentRead)
                    result[entry.id] = ProjectWindow(bundleID: entry.window.bundleID, appPath: appPath, document: read?.path,
                                                     url: read?.web?.absoluteString, title: entry.window.title)
                }
            }
            return result
        }.value
    }

    /// Stage du projet vivante : Roadie y va. Sinon la stage (vide, ou créée sur le bureau affiché de
    /// l'écran actif) reçoit chaque fenêtre à son tour, puis la disposition gardée si toutes sont revenues.
    private func openProject(named name: String) -> TargetActionResult {
        guard let project = StageProjectStore().load().project(named: name) else { return refused("project open", "unknown") }
        let service = service
        let events = events
        let store = service.effectiveStageStore
        Task { @MainActor in
            let switcher = WindowSwitcherService(service: service)
            let context = "stage:\(LauncherMatch.fold(project.name))"
            if let scope = LauncherSearchContext.stage(for: context, in: store.state()),
               let entry = await switcher.load().entries.first(where: { $0.scope == scope }) {
                _ = switcher.activate(entry)
                events.append(RoadieEvent(type: "project.opened", details: ["outcome": "shown"]))
                return
            }
            var scope = LauncherSearchContext.stage(for: context, in: store.state())
            if scope == nil, let home = self.activeStageScope() {
                scope = StageCommandService(service: service, store: store, events: events)
                    .createStage(named: project.name, displayID: home.displayID, desktopID: home.desktopID).1
            }
            guard let scope else {
                events.append(RoadieEvent(type: "project.opened", details: ["outcome": "no_stage"]))
                return
            }
            if store.state().currentDesktopID(for: scope.displayID) == scope.desktopID {
                _ = StageCommandService(service: service, store: store, events: events).switchTo(scope.stageID.rawValue, displayID: scope.displayID)
            }
            var reopened: [WindowID] = []
            for window in project.windows {
                let known = Set(await switcher.load().entries.filter { $0.window.bundleID == window.bundleID }.map(\.id))
                await Self.reopen(window)
                if let placed = await Self.placeNewWindow(bundleID: window.bundleID, known: known, into: scope, service: service, events: events) {
                    reopened.append(placed)
                }
            }
            let tree = project.tree(for: reopened)
            if let tree { store.mutate { $0.setBSPTree(tree, for: scope) } }
            events.append(RoadieEvent(type: "project.opened", details: [
                "outcome": "reopened", "windows": String(project.windows.count), "reopened": String(reopened.count), "tree": String(tree != nil)]))
        }
        return TargetActionResult(changed: true, message: "project open: \(project.name)")
    }

    /// Document ou adresse avec leur application ; sinon une nouvelle fenêtre de l'application.
    private static func reopen(_ window: ProjectWindow) async {
        let appURL = URL(fileURLWithPath: window.appPath)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let item: URL? = window.document.flatMap { FileManager.default.fileExists(atPath: $0) ? URL(fileURLWithPath: $0) : nil }
            ?? window.url.flatMap(URL.init(string:))
        if let item {
            _ = try? await NSWorkspace.shared.open([item], withApplicationAt: appURL, configuration: configuration)
            return
        }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: window.bundleID).first {
            running.activate()
            try? await Task.sleep(for: .milliseconds(300))
            postNewWindowShortcut(to: running.processIdentifier)
        } else {
            _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        }
    }

    // MARK: - Documents et onglets (SPEC-082)

    /// Documents (fichier lu par l'accessibilité) de chaque fenêtre gérée, puis onglets des navigateurs
    /// scriptables déjà ouverts (AppleScript, 2 s au plus chacun). Rien n'est journalisé. O(w + t).
    private static func openItems(_ entries: [WindowSwitcherEntry], stageTitle: @escaping @Sendable (StageScope?) -> String?,
                                  tabs: Bool = true) async -> [LauncherOpenItem] {
        let groups = Dictionary(grouping: entries, by: \.window.pid)
        var items: [LauncherOpenItem] = await Task.detached(priority: .userInitiated) {
            var found: [LauncherOpenItem] = []
            for (pid, group) in groups {
                guard let bundle = group.first?.window.bundleID, !LauncherBrowsers.all.contains(bundle) else { continue }
                let elements = axWindowElements(pid: pid)
                for entry in group {
                    guard let element = elements[CGWindowID(entry.id.rawValue)], let path = axDocumentRead(element).path else { continue }
                    let folder = LauncherList.shortPath((path as NSString).deletingLastPathComponent)
                    let stage = stageTitle(entry.scope).map { " · \($0)" } ?? ""
                    found.append(LauncherOpenItem(kind: .document, windowID: entry.id, bundleID: bundle, appName: entry.window.appName,
                                                  title: (path as NSString).lastPathComponent, detail: "\(entry.window.appName) · \(folder)\(stage)",
                                                  url: nil, browserWindow: nil, tabIndex: nil))
                }
            }
            return found
        }.value
        for bundle in tabs ? LauncherBrowsers.all : [] {
            guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first,
                  let script = LauncherBrowsers.listScript(bundleID: bundle),
                  let output = await LauncherBrowsers.run(script) else { continue }
            let windows = entries.filter { $0.window.bundleID == bundle }
            let frames = windows.map { ($0.id, $0.window.frame.cgRect) }
            let appName = running.localizedName ?? bundle
            for tab in LauncherBrowsers.parse(output) {
                let id = LauncherBrowsers.window(matching: tab.bounds, among: frames)
                let stage = stageTitle(windows.first { $0.id == id }?.scope).map { " · \($0)" } ?? ""
                let host = URL(string: tab.url)?.host ?? tab.url
                items.append(LauncherOpenItem(kind: .tab, windowID: id, bundleID: bundle, appName: appName, title: tab.title,
                                              detail: "\(host) · \(appName)\(stage)", url: tab.url, browserWindow: tab.window, tabIndex: tab.index))
            }
        }
        // Firefox (session 104) : sa session enregistrée, profils ouverts depuis son lancement.
        for bundle in tabs ? LauncherBookmarkBrowsers.bundleIDs("firefox") : [] {
            guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { continue }
            let since = running.launchDate ?? .distantPast
            let found = await Task.detached(priority: .userInitiated) { FirefoxSession.openTabs(since: since) }.value
            let windows = entries.filter { $0.window.bundleID == bundle }
            let frames = windows.map { ($0.id, $0.window.frame.cgRect) }
            let appName = running.localizedName ?? "Firefox"
            // Fenêtre de chaque fenêtre de la session : même cadre, sinon titre de son onglet actif.
            var byWindow: [String: WindowID] = [:]
            for tab in found where tab.isActive {
                let id = LauncherBrowsers.window(matching: tab.bounds, among: frames)
                    ?? windows.first { $0.window.title == tab.title || $0.window.title.hasPrefix(tab.title + " ") }?.id
                if let id { byWindow["\(tab.profile)#\(tab.window)"] = id }
            }
            for tab in found {
                let id = byWindow["\(tab.profile)#\(tab.window)"]
                let stage = stageTitle(windows.first { $0.id == id }?.scope).map { " · \($0)" } ?? ""
                let host = URL(string: tab.url)?.host ?? tab.url
                let profile = tab.profile.isEmpty ? "" : " · \(tab.profile)"
                items.append(LauncherOpenItem(kind: .tab, windowID: id, bundleID: bundle, appName: appName, title: tab.title,
                                              detail: "\(host) · \(appName)\(profile)\(stage)", url: tab.url,
                                              browserWindow: tab.window, tabIndex: tab.index))
            }
            break
        }
        return items
    }

    /// Onglet : sélectionné dans le navigateur, puis sa fenêtre devant, dans sa stage. Document : sa fenêtre.
    private func activate(_ item: LauncherOpenItem) -> TargetActionResult {
        let events = events
        Task { @MainActor in
            if item.kind == .tab, LauncherBookmarkBrowsers.bundleIDs("firefox").contains(item.bundleID),
               let pid = NSRunningApplication.runningApplications(withBundleIdentifier: item.bundleID).first?.processIdentifier {
                // Firefox : l'onglet est pressé par l'accessibilité, dans sa fenêtre si elle est connue.
                let windowID = item.windowID, title = item.title
                let pressed = await Task.detached(priority: .userInitiated) { () -> Bool in
                    let elements = axWindowElements(pid: pid)
                    let known = windowID.flatMap { elements[CGWindowID($0.rawValue)] }
                    return FirefoxTabSelector.select(title: title, in: known.map { [$0] } ?? Array(elements.values))
                }.value
                events.append(RoadieEvent(type: "launcher.firefox_tab", details: ["pressed": String(pressed), "window": String(windowID != nil)]))
            } else if item.kind == .tab, let window = item.browserWindow, let tab = item.tabIndex {
                _ = await LauncherBrowsers.run(LauncherBrowsers.activateScript(bundleID: item.bundleID, window: window, tab: tab))
            }
            if let id = item.windowID {
                self.focus(id)
            } else {
                NSRunningApplication.runningApplications(withBundleIdentifier: item.bundleID).first?.activate()
            }
            events.append(RoadieEvent(type: "launcher.open_item", details: ["kind": item.kind.rawValue, "window": String(item.windowID != nil)]))
        }
        return TargetActionResult(changed: true, message: "launcher open item: \(item.kind.rawValue)")
    }

    // MARK: - Mémoire (SPEC-081)

    /// Application d'un identifiant, hors catalogue (utilitaire rare). O(1).
    private static func app(bundleID: String) -> LauncherApp? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return LauncherApp(bundleID: bundleID, path: url.path, name: name, alternateNames: [])
    }

    /// Créer écrit l'affinité « Toujours ouvrir cette app ici » (fichier généré, relu avant écriture) ;
    /// Plus tard reporte d'un jour ; Jamais retire la proposition pour cette application et cette stage.
    private func chooseRule(_ suggestion: RuleSuggestion, _ choice: RuleChoice) -> TargetActionResult {
        let now = Date()
        if choice != .create {
            do {
                try memoryStore.updateChecked { $0.decline(suggestion, choice, at: now) }
            } catch {
                return failedRuleChoice(choice, reason: "persistence", error: "rule_choice_not_saved",
                                        message: tr("Impossible d'enregistrer le choix de règle.", "Could not save the rule choice."))
            }
        }
        events.append(RoadieEvent(type: "launcher.rule_choice", details: ["choice": choice.rawValue, "bundleID": suggestion.bundleID]))
        guard choice == .create else { return TargetActionResult(changed: true, message: "rule suggestion: \(choice.rawValue)") }
        let snapshot = service.snapshot(followFocus: false)
        guard let display = snapshot.displays.first(where: { $0.id == suggestion.stage.displayID }) else {
            return failedRuleChoice(choice, reason: "display", error: "display",
                                    message: tr("Impossible de créer la règle : écran indisponible.", "Could not create the rule: display unavailable."))
        }
        let window = snapshot.windows.first { $0.window.bundleID == suggestion.bundleID }?.window
            ?? WindowSnapshot(id: WindowID(rawValue: 1), pid: 0, appName: suggestion.appName, bundleID: suggestion.bundleID, title: "",
                              frame: Rect(x: 0, y: 0, width: 1, height: 1), isOnScreen: false, isTileCandidate: true)
        let result = ruleAffinity.saveAffinity(kind: .app, window: window, scope: suggestion.stage, display: display)
        guard result.changed else {
            return failedRuleChoice(choice, reason: "affinity", error: "rule_create_not_saved",
                                    message: tr("Impossible de créer la règle.", "Could not create the rule."))
        }
        memoryStore.update { $0.decline(suggestion, choice, at: now) }
        return TargetActionResult(changed: true, message: result.message)
    }

    private func failedRuleChoice(_ choice: RuleChoice, reason: String, error: String, message: String) -> TargetActionResult {
        events.append(RoadieEvent(type: "launcher.rule_choice_failed", details: ["choice": choice.rawValue, "reason": reason]))
        notifyRuleChoiceFailure(message)
        return TargetActionResult(changed: false, message: message, error: error)
    }

    /// `roadie undo` et la ligne Annuler : la fenêtre du dernier déplacement revient dans sa stage
    /// d'origine (10 minutes au plus, si elle n'a pas bougé depuis).
    /// Annule le dernier déplacement, ou tout le dernier envoi groupé encore en place (SPEC-091 FR-006).
    private func undoLastMove() -> TargetActionResult {
        let snapshot = service.snapshot(followFocus: false)
        let moves = memoryStore.load().undoableBatch(at: Date(), currentScope: { id in snapshot.windows.first { $0.window.id == id }?.scope })
        guard !moves.isEmpty else { return refused("launcher undo", "nothing") }
        let actions = WindowContextActions(snapshotService: service, stageStore: service.effectiveStageStore, eventLog: events)
        var changed = 0
        for move in moves {
            guard let from = move.from else { continue }
            if actions.assign(windowID: move.windowID, to: from.stageID, desktopID: from.desktopID, displayID: from.displayID).changed { changed += 1 }
        }
        events.append(RoadieEvent(type: "launcher.undo", details: ["changed": String(changed), "moves": String(moves.count)]))
        return TargetActionResult(changed: changed > 0, message: "launcher undo: \(changed) sur \(moves.count)")
    }

    /// Lot de la sélection multiple (SPEC-091 FR-005) : nouvelle stage créée une fois puis visée par tous,
    /// un objet après l'autre (un échec n'arrête pas les suivants), copie et Finder en une fois ; Roadie va
    /// à la dernière fenêtre envoyée ; déplacements marqués d'un même lot pour l'annulation. O(s).
    private func performBatch(_ actions: [LauncherAction]) -> TargetActionResult {
        guard let first = actions.first else { return refused("launcher batch", "empty") }
        let start = Date()
        var resolved = actions
        if case .newStage? = first.destination?.kind, let destination = first.destination, let scope = stageScope(for: destination) {
            let created = LauncherDestination(kind: .stage(scope), title: destination.title, detail: destination.detail)
            resolved = actions.map { LauncherAction(subject: $0.subject, verb: $0.verb, destination: created) }
        }
        let files: [String] = resolved.compactMap { if case .file(let file) = $0.subject { file.path } else { nil } }
        switch first.verb {
        case .copyPath:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(files.joined(separator: "\n"), forType: .string)
            return TargetActionResult(changed: true, message: "launcher batch: \(files.count) " + tr("chemins copiés", "paths copied"))
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting(files.map { URL(fileURLWithPath: $0) })
            return TargetActionResult(changed: true, message: "launcher batch: \(files.count) " + tr("dans le Finder", "in Finder"))
        case .copyFile, .copyTo, .moveFileTo, .copyReplace, .moveReplace, .openWith, .email, .trash, .makeAlias, .addTag:
            // Session 131 : un seul presse-papiers, un seul message, une seule notification pour tout le lot.
            return performFileAction(first.verb, paths: files, destination: first.destination, label: "launcher batch")
        default:
            break
        }
        var done = 0
        var windows: [WindowID] = []
        for action in resolved {
            if perform(action).changed { done += 1 }
            if case .target(let target) = action.subject, let id = target.scope.windowId { windows.append(WindowID(rawValue: id)) }
        }
        if windows.count > 1 {
            let batch = UUID().uuidString
            memoryStore.update { $0.mark(batch: batch, windows: Set(windows), since: start) }
        }
        if first.verb == .sendTo, case .stage? = resolved.first?.destination?.kind, let last = windows.last { focus(last) }
        events.append(RoadieEvent(type: "launcher.batch", details: ["verb": first.verb.rawValue, "done": String(done), "count": String(resolved.count)]))
        return TargetActionResult(changed: done > 0, message: "launcher batch: \(done) sur \(resolved.count)")
    }

    // MARK: - Position (SPEC-079)

    /// Après l'action, la fenêtre attendue (son application, dans la stage visée s'il y en a une, ou la
    /// fenêtre elle-même) reçoit le focus : elle va alors à gauche, à droite, en plein écran ou flotte.
    /// 20 s au plus (une application lancée à froid met plusieurs secondes) ; sinon rien ne bouge. O(w) par relevé.
    private func position(after action: LauncherAction) {
        guard let position = action.position else { return }
        let target: StageScope? = switch action.destination?.kind {
        case .stage(let scope)?: scope
        default: nil
        }
        // Une fenêtre que Roadie ne tuile pas (taille fixe, panneau) n'a pas de stage : sa seule application suffit.
        let inTarget: (ScopedWindowSnapshot) -> Bool = { target == nil || $0.scope == nil || $0.scope == target }
        let expected: (ScopedWindowSnapshot) -> Bool
        switch action.subject {
        case .app(let app):
            expected = { $0.window.bundleID == app.bundleID && inTarget($0) }
        case .file(let file):
            let bundle = NSWorkspace.shared.urlForApplication(toOpen: URL(fileURLWithPath: file.path)).flatMap { Bundle(url: $0)?.bundleIdentifier }
            expected = { $0.window.bundleID == bundle && inTarget($0) }
        case .target(let window):
            let id = window.scope.windowId
            expected = { $0.window.id.rawValue == id }
        case .url(let url):
            let bundle = NSWorkspace.shared.urlForApplication(toOpen: url).flatMap { Bundle(url: $0)?.bundleIdentifier }
            expected = { $0.window.bundleID == bundle && inTarget($0) }
        case .project, .text, .openItem:
            return
        }
        let service = service
        let events = events
        Task { @MainActor in
            let start = Date()
            var seen = "none"
            var checked: WindowID?
            var checkedAt = Date.distantPast
            while Date().timeIntervalSince(start) < 20 {
                try? await Task.sleep(for: .milliseconds(300))
                // Focus lu en direct (le focus d'un relevé sans suivi peut être ancien). Relevé sans effet de
                // bord quand le focus change, et au moins toutes les 1,2 s : la fenêtre au focus peut
                // n'arriver dans sa stage qu'un peu après.
                guard let focused = service.focusedWindowID(),
                      focused != checked || Date().timeIntervalSince(checkedAt) >= 1.2 else { continue }
                checked = focused
                checkedAt = Date()
                let snapshot = service.snapshot(followFocus: false)
                let entry = snapshot.windows.first { $0.window.id == focused }
                seen = entry.map { "\($0.window.id.rawValue) \($0.window.bundleID) \($0.scope?.description ?? "sans stage")" }
                    ?? "focus \(focused.rawValue)"
                guard let entry, expected(entry) else { continue }
                let message: String = switch position {
                case .left: WindowCommandService(service: service, stageStore: service.effectiveStageStore, events: events).warp(.left).message
                case .right: WindowCommandService(service: service, stageStore: service.effectiveStageStore, events: events).warp(.right).message
                case .full: WindowCommandService(service: service, stageStore: service.effectiveStageStore, events: events).toggleMaximize(windowID: focused).message
                case .float: WindowContextActions(snapshotService: service, stageStore: service.effectiveStageStore, eventLog: events)
                    .toggleFloating(windowID: focused).message
                }
                events.append(RoadieEvent(type: "launcher.position", details: ["position": position.rawValue, "message": message]))
                return
            }
            events.append(RoadieEvent(type: "launcher.position_expired", details: [
                "position": position.rawValue, "lastSeen": seen, "target": target?.description ?? "aucune"]))
        }
    }

    // MARK: - Aperçu actif (SPEC-078)

    /// Pose l'aperçu : la stage visée (affichée, ou basculée si elle est cachée sur le bureau affiché),
    /// la disposition suspendue, chaque fenêtre écrite à sa future place, puis le fantôme rendu. Un
    /// autre bureau ne donne pas d'aperçu. O(n log n) pour le plan, une écriture par fenêtre.
    private func preview(_ request: LauncherPreviewRequest?, ghost: @escaping @MainActor (LauncherGhost?) -> Void) {
        if let request, activePreview?.request == request { return }
        endPreview(commit: false)
        guard let request else { ghost(nil); return }
        let store = service.effectiveStageStore
        let state = store.state()
        guard state.currentDesktopID(for: request.stage.displayID) == request.stage.desktopID,
              let desk = state.scopes.first(where: { $0.displayID == request.stage.displayID && $0.desktopID == request.stage.desktopID }) else {
            ghost(nil)
            return
        }
        let returnTo: StageScope? = desk.activeStageID == request.stage.stageID ? nil
            : StageScope(displayID: desk.displayID, desktopID: desk.desktopID, stageID: desk.activeStageID)
        if returnTo != nil {
            _ = StageCommandService(service: service, store: store, events: events).switchTo(request.stage.stageID.rawValue, displayID: request.stage.displayID)
        }
        activePreview = ActivePreview(request: request, returnTo: returnTo)
        previewToken += 1
        let token = previewToken
        Task { @MainActor in
            // Stage basculée : la passe suivante montre ses fenêtres avant que l'aperçu ne se pose.
            if returnTo != nil { try? await Task.sleep(for: .milliseconds(300)) }
            guard self.previewToken == token, self.activePreview != nil else { return }
            LayoutPreviewHold.shared.hold()
            self.previewLease?.invalidate()
            let lease = Timer(timeInterval: 0.5, repeats: true) { _ in LayoutPreviewHold.shared.hold() }
            RunLoop.main.add(lease, forMode: .common)
            self.previewLease = lease
            let snapshot = self.service.snapshot(followFocus: false)
            let phantom = SnapshotService.previewPhantomID
            let placements = self.service.previewPlacements(scope: request.stage, incoming: request.incoming ?? phantom, in: snapshot)
            let windows = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })
            var saved: [WindowID: Rect] = [:]
            var commands: [ApplyCommand] = []
            for (id, frame) in placements where id != phantom {
                guard let window = windows[id] else { continue }
                saved[id] = window.frame
                commands.append(ApplyCommand(window: window, frame: Rect(frame)))
            }
            self.activePreview?.saved = saved
            _ = self.service.apply(ApplyPlan(commands: commands))
            self.events.append(RoadieEvent(type: "launcher.preview", details: [
                "stage": request.stage.description, "windows": String(commands.count),
                "phantom": String(request.incoming == nil), "switched": String(returnTo != nil)]))
            guard request.incoming == nil, let frame = placements[phantom] else { ghost(nil); return }
            ghost(LauncherGhost(frame: RoadieScreenCoordinate.axRectToNS(frame),
                                icon: request.appPath.map { NSWorkspace.shared.icon(forFile: $0) }))
        }
    }

    /// Fin de l'aperçu. Sans validation : chaque fenêtre reprend le cadre relevé avant, la stage de
    /// départ revient. Puis la disposition reprend.
    private func endPreview(commit: Bool) {
        previewToken += 1
        previewLease?.invalidate()
        previewLease = nil
        guard let preview = activePreview else { return }
        activePreview = nil
        if !commit {
            let windows = Dictionary(uniqueKeysWithValues: service.snapshot(followFocus: false).windows.map { ($0.window.id, $0.window) })
            let commands = preview.saved.compactMap { id, frame in windows[id].map { ApplyCommand(window: $0, frame: frame) } }
            _ = service.apply(ApplyPlan(commands: commands))
            if let back = preview.returnTo {
                _ = StageCommandService(service: service, store: service.effectiveStageStore, events: events)
                    .switchTo(back.stageID.rawValue, displayID: back.displayID)
            }
        }
        LayoutPreviewHold.shared.release()
        events.append(RoadieEvent(type: "launcher.preview_end", details: ["commit": String(commit), "restored": String(commit ? 0 : preview.saved.count)]))
    }

    // MARK: - Fichiers (SPEC-077)

    /// `roadie launch CHEMIN [--stage NOM | --new-stage]` : comme Retour dans la barre, ou comme « Ouvrir
    /// dans… » avec une destination. Une stage inconnue refuse sans rien ouvrir.
    private func launch(_ command: TargetModeRuntimeCommand) {
        guard let path = command.string("path") else { return }
        let state = service.effectiveStageStore.state()
        var destination: LauncherDestination?
        if let name = command.string("stage") {
            guard let scope = LauncherSearchContext.stage(for: "stage:\(LauncherMatch.fold(name))", in: state) else {
                _ = refused("launcher launch", "stage")
                return
            }
            destination = LauncherDestination(kind: .stage(scope), title: name, detail: "")
        } else if command.bool("here") {
            guard let scope = activeStageScope() else { _ = refused("launcher launch", "stage"); return }
            destination = LauncherDestination(kind: .stage(scope), title: tr("Stage active", "Active stage"), detail: "")
        } else if command.bool("newStage") {
            let display = state.activeDisplayID ?? service.snapshot(followFocus: false).displays.first?.id ?? DisplayID(rawValue: "none")
            destination = LauncherDestination(kind: .newStage(name: nil, display, state.currentDesktopID(for: display)), title: tr("Nouvelle stage", "New stage"), detail: "")
        }
        let url = URL(fileURLWithPath: path)
        let subject: LauncherSubject
        if url.pathExtension == "app", let bundle = Bundle(url: url), let id = bundle.bundleIdentifier {
            let name = FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
            subject = .app(LauncherApp(bundleID: id, path: path, name: name, alternateNames: []))
        } else {
            var isFolder: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isFolder)
            subject = .file(LauncherFile(path: path, name: url.lastPathComponent, isFolder: isFolder.boolValue, lastUsed: nil))
        }
        var action = LauncherAction(subject: subject, verb: destination == nil ? .open : .openIn, destination: destination)
        if command.bool("here"), let destination { action = LauncherAction(subject: subject, verb: .bringHere, destination: destination) }
        action.position = command.string("position").flatMap(LauncherPosition.init(rawValue:))
        if command.bool("previewOnly") {
            // Diagnostic SPEC-078 : la disposition future 2 s, puis tout revient ; rien n'est ouvert.
            guard let request = LauncherPreviewRequest.of(action) else { _ = refused("launcher launch", "preview"); return }
            preview(request) { _ in }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                self.endPreview(commit: false)
            }
            return
        }
        let result = perform(action)
        events.append(RoadieEvent(type: "launcher.launch", details: ["changed": String(result.changed), "message": result.message]))
    }

    /// Fichier : aller à la fenêtre qui l'affiche déjà, sinon l'ouvrir dans la stage voulue ; Finder,
    /// Quick Look et copie du chemin. Aucun chemin n'est journalisé.
    private func performFile(_ action: LauncherAction, file: LauncherFile, label: String) -> TargetActionResult {
        let url = URL(fileURLWithPath: file.path)
        switch action.verb {
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .quickLook:
            // `qlmanage -p` montre l'aperçu dans son propre processus, sans activer Roadie (research R4).
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
            process.arguments = ["-p", file.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
        case .copyPath:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(file.path, forType: .string)
        case .open, .openIn, .bringHere:
            let explicit: StageScope? = switch action.verb {
            case .openIn: action.destination.flatMap(stageScope)
            case .bringHere: action.destination.flatMap(stageScope) ?? activeStageScope()
            default: nil
            }
            if action.verb == .openIn, explicit == nil { return refused(label, "destination") }
            openFile(file, verb: action.verb, into: explicit)
        case .copyFile, .copyTo, .moveFileTo, .copyReplace, .moveReplace, .openWith, .email, .trash, .makeAlias, .info, .addTag,
             .browse, .terminalHere, .packageContents:
            return performFileAction(action.verb, paths: [file.path], destination: action.destination, label: label)
        default:
            return refused(label, "verb")
        }
        return TargetActionResult(changed: true, message: "\(label): file")
    }

    // MARK: - Actions d'Alfred sur fichiers, textes, onglets (session 131)

    /// Verbes de fichier d'Alfred, sur un ou plusieurs chemins (sélection multiple). Un échec est notifié avec sa
    /// raison ; le journal ne garde que le verbe et les nombres. O(s).
    func performFileAction(_ verb: LauncherVerb, paths: [String], destination: LauncherDestination?, label: String) -> TargetActionResult {
        let urls = paths.map { URL(fileURLWithPath: $0) }
        var report = LauncherFileOperations.Report(done: paths)
        switch verb {
        case .copyFile:
            LauncherFileOperations.copyToPasteboard(paths)
        case .copyTo, .moveFileTo, .copyReplace, .moveReplace:
            guard case .folder(let folder)? = destination?.kind else { return refused(label, "destination") }
            report = LauncherFileOperations.transfer(paths, to: folder, move: [.moveFileTo, .moveReplace].contains(verb),
                                                     replace: [.copyReplace, .moveReplace].contains(verb))
        case .openWith:
            guard case .application(let app)? = destination?.kind else { return refused(label, "destination") }
            NSWorkspace.shared.open(urls, withApplicationAt: URL(fileURLWithPath: app), configuration: NSWorkspace.OpenConfiguration())
        case .email:
            guard let service = NSSharingService(named: .composeEmail), service.canPerform(withItems: urls) else { return refused(label, "email") }
            service.perform(withItems: urls)
        case .trash:
            report = LauncherFileOperations.trashItems(paths)
        case .makeAlias:
            report = LauncherFileOperations.Report()
            for path in paths {
                do { report.done.append(try LauncherFileOperations.makeAlias(path)) } catch { report.failures[path] = error.localizedDescription }
            }
            // Retour visible (essai du 29 octobre 2026) : les alias créés sont montrés sélectionnés dans le Finder.
            if !report.done.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(report.done.map { URL(fileURLWithPath: $0) }) }
        case .info:
            guard let path = paths.first else { return refused(label, "file") }
            showInfo(path)
        case .addTag:
            guard case .tag(let tag)? = destination?.kind else { return refused(label, "destination") }
            report = LauncherFileOperations.toggleTag(tag, on: paths)
        case .browse:
            guard let path = paths.first else { return refused(label, "file") }
            let folder = (path as NSString).abbreviatingWithTildeInPath
            reopenSearch(folder.hasSuffix("/") ? folder : folder + "/")
        case .terminalHere:
            guard let path = paths.first else { return refused(label, "file") }
            let effects = Self.liveEffects(self, events: events, webSearchURL: "")
            Task { await effects.terminal(folder: path) }
        case .packageContents:
            guard let path = paths.first else { return refused(label, "file") }
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
        default:
            return refused(label, "verb")
        }
        events.append(RoadieEvent(type: "launcher.file_action", details: [
            "verb": verb.rawValue, "count": String(paths.count), "done": String(report.done.count), "failed": String(report.failures.count)]))
        guard report.failures.isEmpty else {
            let reasons = Set(report.failures.values).sorted().joined(separator: ", ")
            notifyFailure(verb.title + tr(" : échec (", ": failed (") + reasons + ")")
            return TargetActionResult(changed: !report.done.isEmpty, message: "\(label): \(report.failures.count) failed", error: "file_action_failed")
        }
        return TargetActionResult(changed: true, message: "\(label): \(report.done.count)")
    }

    /// Fiche d'un élément dans la vue Texte : un tableau Markdown, chaque valeur sélectionnable. O(octets) pour l'empreinte.
    private func showInfo(_ path: String) {
        let name = (path as NSString).lastPathComponent
        Task.detached(priority: .userInitiated) {
            let markdown: String
            if let info = try? LauncherFileOperations.info(path) {
                let rows = info.lines.map { "| \($0.label) | `\($0.value)` |" }.joined(separator: "\n")
                markdown = "# \(name)\n\n| | |\n|---|---|\n\(rows)\n"
            } else {
                markdown = "# \(name)\n\n" + tr("Informations illisibles.", "Information unavailable.")
            }
            await MainActor.run {
                var view = AlfredTextView(workflowID: "roadie.info", objectUID: "info", title: name,
                                          folder: (path as NSString).deletingLastPathComponent)
                view.behaviour = .markdown
                view.chunks = [markdown]
                WorkflowTextPanel.show(view, plainContinues: false, runScript: nil) { _, _, _ in }
            }
        }
    }

    /// Verbes d'un texte (tapé ou sélectionné). « Extraire les adresses » est traité par la barre, qui reste ouverte.
    private func performText(_ verb: LauncherVerb, text: String, label: String) -> TargetActionResult {
        switch verb {
        case .copyText:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .webSearch:
            let template = service.effectiveConfig.experimental.targetMode.webSearchURL
            guard let url = LauncherWeb.searchURL(template, query: text) else { return refused(label, "web") }
            NSWorkspace.shared.open(url)
            followBrowser(url)
        case .emailText:
            guard let url = LauncherText.mailURL(body: text) else { return refused(label, "email") }
            NSWorkspace.shared.open(url)
        case .largeType:
            LargeTypePanel.show(text)
        default:
            return refused(label, "verb")
        }
        events.append(RoadieEvent(type: "launcher.text", details: ["verb": verb.rawValue, "length": String(text.count)]))
        return TargetActionResult(changed: true, message: "\(label): text")
    }

    /// Verbes d'un onglet ouvert : y aller, le fermer, copier son adresse, l'ouvrir dans une nouvelle fenêtre.
    private func performOpenItem(_ verb: LauncherVerb, item: LauncherOpenItem, label: String) -> TargetActionResult {
        switch verb {
        case .open:
            return activate(item)
        case .copyURL:
            guard let url = item.url else { return refused(label, "url") }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url, forType: .string)
        case .closeTab, .newWindowTab:
            guard item.kind == .tab else { return refused(label, "tab") }
            let close = verb == .closeTab
            Task { @MainActor in
                let done = await LauncherTabActions.perform(close ? .close : .newWindow, on: item)
                if !done { self.notifyFailure(verb.title + tr(" : échec", ": failed")) }
            }
        default:
            return refused(label, "verb")
        }
        events.append(RoadieEvent(type: "launcher.tab", details: ["verb": verb.rawValue, "bundleID": item.bundleID]))
        return TargetActionResult(changed: true, message: "\(label): \(item.bundleID)")
    }

    /// Relance : quitter, puis rouvrir une fois le processus terminé (5 s au plus). O(1).
    private func relaunch(_ app: LauncherApp) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
        running.forEach { $0.terminate() }
        Task { @MainActor in
            for _ in 0..<50 where running.contains(where: { !$0.isTerminated }) { try? await Task.sleep(for: .milliseconds(100)) }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: configuration)
        }
    }

    /// Échec d'un verbe signalé par une notification (comme les commandes système, session 129).
    private func notifyFailure(_ text: String) {
        Task { _ = await LauncherBrowsers.run("display notification \"\(text.applescriptEscaped)\" with title \"Roadie\"", timeout: 3) }
    }

    /// Fenêtre qui affiche déjà le fichier : Roadie y va (et l'amène dans `explicit` si donnée). Sinon,
    /// le fichier s'ouvre avec son application par défaut ; sa nouvelle fenêtre rejoint `explicit`, ou la
    /// stage de son dossier, ou la stage active (règle des nouvelles fenêtres).
    private func openFile(_ file: LauncherFile, verb: LauncherVerb, into explicit: StageScope?) {
        let service = service
        let events = events
        let url = URL(fileURLWithPath: file.path)
        Task { @MainActor in
            let switcher = WindowSwitcherService(service: service)
            let entries = await switcher.load().entries
            let appURL = NSWorkspace.shared.urlForApplication(toOpen: url)
            let bundle = appURL.flatMap { Bundle(url: $0)?.bundleIdentifier }
            let found = await LauncherDocuments.window(showing: file.path, in: entries, preferredBundle: bundle)
            if let window = found.window {
                if let explicit, window.scope != explicit {
                    _ = WindowContextActions(snapshotService: service, stageStore: service.effectiveStageStore, eventLog: events)
                        .assign(windowID: window.id, to: explicit.stageID, desktopID: explicit.desktopID, displayID: explicit.displayID)
                }
                if let placed = await switcher.load().entries.first(where: { $0.id == window.id }) { _ = switcher.activate(placed) }
                self.rememberFolder(file, in: explicit ?? window.scope)
                events.append(RoadieEvent(type: "launcher.file", details: [
                    "verb": verb.rawValue, "outcome": "focused", "bundleID": window.window.bundleID,
                    "documentApps": found.exposing.joined(separator: ","), "scanned": found.scanned]))
                return
            }
            let scope = explicit ?? (verb == .open ? self.folderStage(file) : nil)
            let known = Set(entries.filter { $0.window.bundleID == bundle }.map(\.id))
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            if let appURL {
                _ = try? await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
            } else {
                NSWorkspace.shared.open(url)
            }
            self.rememberFolder(file, in: scope ?? self.activeStageScope())
            events.append(RoadieEvent(type: "launcher.file", details: [
                "verb": verb.rawValue, "outcome": scope == nil ? "opened" : "placing", "bundleID": bundle ?? "",
                "documentApps": found.exposing.joined(separator: ","), "scanned": found.scanned]))
            if let scope, let bundle {
                await Self.placeNewWindow(bundleID: bundle, known: known, into: scope, service: service, events: events)
            }
        }
    }

    /// Stage où s'ouvrent le plus souvent les fichiers de ce dossier ou d'un parent (trois niveaux au
    /// plus), d'après le classement par stage (076, clé `folder:`). O(4 × c + S).
    private func folderStage(_ file: LauncherFile) -> StageScope? {
        let ranking = LauncherRankingStore().load()
        let state = service.effectiveStageStore.state()
        var folder = file.folder
        for _ in 0..<4 {
            if let contexts = ranking.entries["folder:\(folder)"]?.contexts,
               let best = contexts.max(by: { $0.value.anchor < $1.value.anchor }),
               let scope = LauncherSearchContext.stage(for: best.key, in: state) {
                return scope
            }
            let parent = (folder as NSString).deletingLastPathComponent
            guard parent != folder, parent.count > 1, parent != NSHomeDirectory() else { break }
            folder = parent
        }
        return nil
    }

    private func rememberFolder(_ file: LauncherFile, in scope: StageScope?) {
        // Dossiers de l'utilisateur seulement : un fichier temporaire ne crée pas d'habitude (audit V15 F4).
        guard let scope, LauncherFileRules.isShown(file.path) else { return }
        let stage = service.effectiveStageStore.state().scopes.first { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID }?
            .stages.first { $0.id == scope.stageID }
        LauncherRankingStore().recordVisit("folder:\(file.folder)", query: "", context: LauncherSearchContext.rankingContext(scope, stage: stage))
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

    /// « Revenir » (SPEC-081) : la fenêtre vue avant celle de l'ouverture de la barre. La fenêtre en cours
    /// est la fenêtre active si Roadie la connaît, sinon la plus récente de l'historique : une fenêtre active
    /// absente des cibles (lecture AX vide, fenêtre auxiliaire) ne doit pas faire proposer la fenêtre en cours
    /// (session 097). O(n), n = taille de l'historique (512 au plus).
    nonisolated static func previousWindow(recent: [WindowID], focused: WindowID?, targets: [String: RoadieTarget]) -> RoadieTarget? {
        let known = recent.lazy.compactMap { targets["window:\($0.rawValue)"] }
        let current = focused.flatMap { targets["window:\($0.rawValue)"] } ?? known.first
        return known.first { $0.id != current?.id }
    }

    /// Après Échap, la fenêtre qui avait le clavier redevient clé, si son application est toujours au
    /// premier plan. Hors fil principal ; relecture 200 ms après (délai choisi,
    /// non mesuré) pour l'événement `launcher.focus_restore`.
    private func restoreFocusAfterEscape(_ saved: LauncherFocusSnapshot) {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == saved.pid else { return }
        let events = events
        // Diagnostic (session 098) : une fenêtre de Roadie qui reprend le clavier à la fermeture du panneau
        // garderait la frappe, quel que soit l'état de l'application.
        let roadieKey = Self.keyWindowName()
        DispatchQueue.global(qos: .userInitiated).async {
            var details = saved.restore()
            details["roadieKey"] = roadieKey
            Thread.sleep(forTimeInterval: 0.2)
            details["after"] = String(saved.focusIsSaved())
            DispatchQueue.main.async {
                details["roadieKeyAfter"] = MainActor.assumeIsolated { Self.keyWindowName() }
                events.append(RoadieEvent(type: "launcher.focus_restore", details: details))
            }
        }
    }

    /// Fenêtre de Roadie qui a le clavier : sa classe, « none » sinon.
    private static func keyWindowName() -> String {
        NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "none"
    }

    private func finish(_ result: TargetActionResult, command: String) {
        stopStyleUpdates()
        currentSession = nil
        currentCommand = nil
        if command == "targets.search" || command == "targets.actions" { LauncherBTTPause.shared.barClosed() }
        if let saved = escapeFocus, command == "targets.search" || command == "targets.actions" {
            escapeFocus = nil
            if result.message == "target_search_escaped" { restoreFocusAfterEscape(saved) }
        }
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

/// Contenu complet d'un presse-papiers, toutes ses représentations, pour le remettre après une copie
/// simulée. O(t) types.
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ board: NSPasteboard) {
        items = (board.pasteboardItems ?? []).map { item in
            Dictionary(item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }, uniquingKeysWith: { first, _ in first })
        }
    }

    func restore(to board: NSPasteboard) {
        board.clearContents()
        let restored = items.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { board.writeObjects(restored) }
    }
}
