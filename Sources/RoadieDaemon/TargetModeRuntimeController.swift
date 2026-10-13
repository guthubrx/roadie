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
        load: (
            _ deliver: @escaping @MainActor @Sendable ([RoadieTarget], Int) -> Void,
            _ done: @escaping @MainActor @Sendable () -> Void
        ) -> Void,
        activate: @escaping @MainActor (RoadieTarget, TargetActionVerb) -> TargetActionResult,
        onFinish: @escaping @MainActor (TargetActionResult) -> Void
    ) -> TargetOverlaySessionHandle?
}

/// Présentation réelle : délègue à `TargetOverlayPresenter`.
struct LiveTargetModeOverlayPresenter: TargetModeOverlayPresenting {
    func startInteractive(
        _ state: TargetOverlayState,
        duration: TimeInterval,
        activate: @escaping @MainActor (String) -> TargetActionResult,
        onFinish: @escaping @MainActor (TargetActionResult) -> Void
    ) -> TargetOverlaySessionHandle? {
        TargetOverlayPresenter.startInteractive(state, duration: duration, activate: activate, onFinish: onFinish)
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
        load: (
            _ deliver: @escaping @MainActor @Sendable ([RoadieTarget], Int) -> Void,
            _ done: @escaping @MainActor @Sendable () -> Void
        ) -> Void,
        activate: @escaping @MainActor (RoadieTarget, TargetActionVerb) -> TargetActionResult,
        onFinish: @escaping @MainActor (TargetActionResult) -> Void
    ) -> TargetOverlaySessionHandle? {
        TargetOverlayPresenter.startSearch(targets: targets, alphabet: alphabet, load: load, activate: activate, onFinish: onFinish)
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

    public convenience init(service: SnapshotService = SnapshotService(), events: EventLog = EventLog()) {
        self.init(service: service, events: events, presenter: LiveTargetModeOverlayPresenter())
    }

    init(service: SnapshotService, events: EventLog, presenter: any TargetModeOverlayPresenting) {
        self.service = service
        self.events = events
        self.presenter = presenter
    }

    public func start() {
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

    public func stop() {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observer = nil
        currentSession?.cancel()
        currentSession = nil
        events.append(RoadieEvent(type: "target_mode.runtime_stopped"))
    }

    /// Interne (et non privé) : les tests l'appellent sans notification distribuée.
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
        case "targets.search":
            startTargetsSearch(command)
        case "grid.interactive":
            startGridInteractive(command)
        default:
            events.append(RoadieEvent(type: "target_mode.command_rejected", details: [
                "command": command.name,
                "reason": "unknown_command"
            ]))
        }
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
        currentSession = presenter.startSearch(
            targets: roadieTargets,
            alphabet: appTargets.hintCharacters,
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
            onFinish: { [weak self] result in
                self?.finish(result, command: command.name)
            }
        )
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
        let grid = TargetGridService(service: service)
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
