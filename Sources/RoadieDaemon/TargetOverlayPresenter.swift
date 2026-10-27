import AppKit
import os
import RoadieCore

public struct TargetOverlayStyle: Sendable, Equatable {
    public var drawTargetFrames: Bool
    public var fillColor: String
    public var fillOpacity: Double
    public var borderColor: String
    public var borderOpacity: Double
    public var labelColor: String
    public var labelBackgroundOpacity: Double
    public var labelPlacement: TargetGridLabelPlacement
    /// Taille de police des étiquettes, 8 à 48 pt (SPEC-023). Les dimensions du badge suivent `scale`.
    public var labelFontSize: CGFloat
    public var searchTextFontSize: CGFloat
    public var commandTextFontSize: CGFloat
    public var searchFontFamily: String
    public var commandFontFamily: String
    /// Thème de la barre (session 101) et nombre de résultats montrés (0 : autant que la place).
    var theme: LauncherTheme = .roadie
    var maxRows = 0

    public init(
        drawTargetFrames: Bool = false,
        fillColor: String = "#000000",
        fillOpacity: Double = 0,
        borderColor: String = "#4DABF7",
        borderOpacity: Double = 0.9,
        labelColor: String = "#FFFFFF",
        labelBackgroundOpacity: Double = 0.84,
        labelPlacement: TargetGridLabelPlacement = .callout,
        labelFontSize: CGFloat = 13,
        searchTextFontSize: CGFloat = 15,
        commandTextFontSize: CGFloat = 13,
        searchFontFamily: String = "system",
        commandFontFamily: String = "system"
    ) {
        self.drawTargetFrames = drawTargetFrames
        self.fillColor = fillColor
        self.fillOpacity = min(1, max(0, fillOpacity))
        self.borderColor = borderColor
        self.borderOpacity = min(1, max(0, borderOpacity))
        self.labelColor = labelColor
        self.labelBackgroundOpacity = min(1, max(0, labelBackgroundOpacity))
        self.labelPlacement = labelPlacement
        self.labelFontSize = min(48, max(8, labelFontSize))
        self.searchTextFontSize = min(48, max(8, searchTextFontSize))
        self.commandTextFontSize = min(48, max(8, commandTextFontSize))
        self.searchFontFamily = searchFontFamily
        self.commandFontFamily = commandFontFamily
    }

    /// Facteur appliqué aux dimensions des étiquettes : 1 à 13 pt, taille d'origine.
    public var scale: CGFloat { labelFontSize / 13 }

    public static let labels = TargetOverlayStyle()

    /// Style des lettres, à la taille de `experimental.target_mode.label_font_size`.
    public static func labels(_ config: TargetModeConfig) -> TargetOverlayStyle {
        TargetOverlayStyle(labelFontSize: CGFloat(config.labelFontSize))
    }

    /// Un thème autre que `roadie` apporte ses tailles et ses polices (session 101).
    static func search(_ config: TargetModeConfig, theme: LauncherTheme = .roadie) -> TargetOverlayStyle {
        var style = TargetOverlayStyle(
            labelFontSize: CGFloat(config.searchLabelFontSize),
            searchTextFontSize: CGFloat(theme.ownsSizes ? theme.searchText.size : config.searchTextFontSize),
            commandTextFontSize: CGFloat(theme.ownsSizes ? theme.title.size : config.commandTextFontSize),
            searchFontFamily: theme.ownsSizes ? theme.searchText.font : config.searchFontFamily,
            commandFontFamily: theme.ownsSizes ? theme.title.font : config.commandFontFamily
        )
        style.theme = theme
        style.maxRows = config.visibleResults
        return style
    }

    /// Style de la barre avec le thème du moment (clair ou sombre). O(f), f fichiers de thèmes importés.
    @MainActor static func launcher(_ config: TargetModeConfig) -> TargetOverlayStyle {
        search(config, theme: LauncherThemeCatalog.resolve(config, dark: LauncherThemeCatalog.systemIsDark))
    }

    public static func grid(_ config: TargetGridConfig) -> TargetOverlayStyle {
        TargetOverlayStyle(
            drawTargetFrames: config.overlayDrawGrid,
            fillColor: config.overlayFillColor,
            fillOpacity: config.overlayFillOpacity,
            borderColor: config.overlayBorderColor,
            borderOpacity: config.overlayBorderOpacity,
            labelColor: config.overlayLabelColor,
            labelBackgroundOpacity: config.overlayLabelBackgroundOpacity,
            labelPlacement: config.labelPlacement,
            labelFontSize: CGFloat(config.labelFontSize)
        )
    }
}

/// Dimensions des étiquettes, proportionnelles à `labelFontSize` (SPEC-023 R8). À 13 pt elles
/// valent les constantes d'origine. Les épaisseurs de trait ne changent pas. Toutes en O(1).
extension TargetOverlayStyle {
    /// Badge : marge du texte 16, largeur minimale 28, hauteur 24.
    func badgeSize(textWidth: CGFloat) -> CGSize {
        CGSize(width: max(28 * scale, textWidth + 16 * scale), height: 24 * scale)
    }

    var badgeCornerRadius: CGFloat { 8 * scale }
    /// Écart entre le badge et le bord de sa cible.
    var badgeGap: CGFloat { 10 * scale }
    /// Retrait du badge le long du bord de sa cible.
    var badgeInset: CGFloat { 6 * scale }
    /// Espace entre deux positions essayées autour de la cible.
    var badgePlacementSpacing: CGFloat { 6 * scale }
    /// Marge gardée libre autour d'un badge déjà placé.
    var badgeAvoidanceMargin: CGFloat { 4 * scale }
    /// Marge entre le badge et le bord de l'écran.
    var badgeEdgeMargin: CGFloat { 4 * scale }

    /// Garde le badge dans `bounds`, à `badgeEdgeMargin` du bord.
    func clampedBadge(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        let margin = badgeEdgeMargin
        let x = min(max(rect.minX, bounds.minX + margin), bounds.maxX - rect.width - margin)
        let y = min(max(rect.minY, bounds.minY + margin), bounds.maxY - rect.height - margin)
        return CGRect(origin: CGPoint(x: x, y: y), size: rect.size)
    }
}

public enum TargetGridArrowDirection: Sendable {
    case left
    case right
    case up
    case down
}

@MainActor
public protocol TargetOverlaySessionHandle: AnyObject {
    func cancel()
    func updateStyle(_ style: TargetOverlayStyle)
}

extension TargetOverlaySessionHandle {
    public func updateStyle(_ style: TargetOverlayStyle) {}
}

@MainActor
public enum TargetOverlayPresenter {
    public static func present(_ state: TargetOverlayState, duration: TimeInterval, style: TargetOverlayStyle = .labels) {
        let badges = TargetOverlayBadge.badges(from: state)
        guard !badges.isEmpty else { return }

        NSApplication.shared.setActivationPolicy(.accessory)
        let windows = TargetOverlayPresenter.overlayWindows(for: badges, style: style)
        windows.forEach { $0.orderFrontRegardless() }

        let timer = Timer.scheduledTimer(withTimeInterval: max(0.2, duration), repeats: false) { _ in
            Task { @MainActor in
                windows.forEach { $0.orderOut(nil) }
                NSApplication.shared.stop(nil)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        NSApplication.shared.run()
    }

    @discardableResult
    public static func startInteractive(
        _ state: TargetOverlayState,
        duration: TimeInterval,
        style: TargetOverlayStyle = .labels,
        activate: @escaping @MainActor (String) -> TargetActionResult,
        onFinish: @escaping @MainActor (TargetActionResult) -> Void
    ) -> TargetOverlaySessionHandle? {
        let session = TargetInteractiveSession(
            state: state,
            duration: duration,
            style: style,
            activate: activate,
            onFinish: onFinish
        )
        if let immediate = session.start() {
            onFinish(immediate)
            return nil
        }
        return session
    }

    @discardableResult
    public static func startGridInteractive(
        initialPath: String,
        duration: TimeInterval,
        config: TargetGridConfig,
        displayIndex: Int? = nil,
        stateProvider: @escaping @MainActor (Int?, String) -> TargetOverlayState,
        activate: @escaping @MainActor (Int?, String) -> TargetActionResult,
        focusAt: @escaping @MainActor (CGRect) -> Void = { _ in },
        displayNeighbor: @escaping @MainActor (Int?, TargetGridArrowDirection) -> Int? = { _, _ in nil },
        onFinish: @escaping @MainActor (TargetActionResult) -> Void
    ) -> TargetOverlaySessionHandle? {
        let session = TargetGridInteractiveSession(
            initialPath: initialPath,
            initialDisplayIndex: displayIndex,
            duration: duration,
            config: config,
            stateProvider: stateProvider,
            activate: activate,
            focusAt: focusAt,
            displayNeighbor: displayNeighbor,
            onFinish: onFinish
        )
        if let immediate = session.start() {
            onFinish(immediate)
            return nil
        }
        return session
    }

    /// Mode recherche (SPEC-021) : barre de saisie, filtrage, mise en avant, validation au clavier.
    @discardableResult
    /// Barre immédiate (SPEC-021) : la session s'ouvre avec `targets`, puis `load` lit les fenêtres en
    /// arrière-plan. Il appelle `deliver(cibles, rang de fenêtre)` pour chaque fenêtre lue, puis `done`.
    /// Mode commande (SPEC-023) : `commands` exécute la saisie qui suit `/` ; `runDeferred` et
    /// `openSettings` partent après la fin de la session (research R2).
    static func startSearch(
        targets: [RoadieTarget],
        alphabet: String,
        style: TargetOverlayStyle = .labels,
        commands: SlashCommandRunner,
        runDeferred: @escaping @MainActor ([String]) -> Void,
        openSettings: @escaping @MainActor (SettingCategory?) -> Void,
        load: (
            _ deliver: @escaping @MainActor @Sendable ([RoadieTarget], Int) -> Void,
            _ done: @escaping @MainActor @Sendable () -> Void
        ) -> Void,
        activate: @escaping @MainActor (RoadieTarget, TargetActionVerb) -> TargetActionResult,
        launcher: LauncherSearchContext = .disabled,
        onFinish: @escaping @MainActor (TargetActionResult) -> Void
    ) -> TargetOverlaySessionHandle? {
        let session = TargetSearchSession(
            targets: targets,
            alphabet: alphabet,
            style: style,
            commands: commands,
            runDeferred: runDeferred,
            openSettings: openSettings,
            activate: activate,
            launcher: launcher,
            onFinish: onFinish
        )
        if let immediate = session.start() {
            onFinish(immediate)
            return nil
        }
        load(
            { [weak session] targets, order in session?.append(targets, windowOrder: order) },
            { [weak session] in session?.finishLoading() }
        )
        return session
    }

    fileprivate static func screenUnionFrame() -> CGRect {
        NSScreen.screens
            .map(\.frame)
            .reduce(CGRect.null) { partial, frame in
                partial.isNull ? frame : partial.union(frame)
            }
    }

    fileprivate static func overlayWindows(for badges: [TargetOverlayBadge], style: TargetOverlayStyle = .labels) -> [TargetOverlayWindow] {
        let screens = NSScreen.screens
        let frames = screens.map(\.frame)
        let visibleFrames = frames.filter { frame in
            badges.contains { badge in
                frame.insetBy(dx: -80, dy: -80).intersects(badge.frame)
            }
        }
        let targetFrames = visibleFrames.isEmpty ? frames : visibleFrames
        return targetFrames.map { TargetOverlayWindow(frame: $0, badges: badges, style: style) }
    }
}

/// Session interactive pilotée par un tap clavier (CGEventTap) : installation et réactivation
/// partagées par la session de cibles et la session de grille.
@MainActor
private protocol KeyEventTapSession: AnyObject {
    var eventTap: CFMachPort? { get set }
    var runLoopSource: CFRunLoopSource? { get set }
    var finished: Bool { get }
    func handle(_ input: KeyInput)
}

extension KeyEventTapSession {
    func reenableEventTap() {
        guard !finished, let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func installEventTap() -> Bool {
        let mask = TargetSearchDismissal.eventMask(search: self is TargetSearchSession)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon,
                  let session = Unmanaged<AnyObject>.fromOpaque(refcon).takeUnretainedValue() as? any KeyEventTapSession
            else { return Unmanaged.passUnretained(event) }
            // macOS desactive le tap s'il repond trop lentement ou sur saisie utilisateur : on le reactive.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                Task { @MainActor in session.reenableEventTap() }
                return Unmanaged.passUnretained(event)
            }
            if TargetSearchDismissal.isMouseDown(type), let search = session as? TargetSearchSession {
                // installEventTap est isolé sur MainActor : cette source appartient à la boucle
                // principale. Fermer ici, avant un timer de Retour, sans consommer le clic.
                let clicks = Int(event.getIntegerValueField(.mouseEventClickState))
                let consumed = MainActor.assumeIsolated { search.handleMouseDown(at: event.location, type: type, clicks: clicks) }
                if consumed { return nil }
                return Unmanaged.passUnretained(event)
            }
            // Glisser de la barre (session 102) : seul un glisser commencé sur la barre est pris.
            if type == .leftMouseDragged || type == .leftMouseUp, let search = session as? TargetSearchSession {
                let consumed = MainActor.assumeIsolated { search.handleMouseDrag(at: event.location, ended: type == .leftMouseUp) }
                return consumed ? nil : Unmanaged.passUnretained(event)
            }
            guard type == .keyDown else { return Unmanaged.passUnretained(event) }
            // La recherche possède un vrai champ key : AppKit reçoit texte, IME et raccourcis.
            // Son panneau traite seulement navigation/validation ; lettres et grille gardent le tap.
            if session is TargetSearchSession {
                return Unmanaged.passUnretained(event)
            }
            let input = KeyInput(event: event)
            guard input.isRoadieHandled else {
                return Unmanaged.passUnretained(event)
            }
            Task { @MainActor in
                session.handle(input)
            }
            return nil
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
}

@MainActor
private final class TargetInteractiveSession: TargetOverlaySessionHandle, KeyEventTapSession {
    private let state: TargetOverlayState
    private let duration: TimeInterval
    private var style: TargetOverlayStyle
    private let activate: @MainActor (String) -> TargetActionResult
    private let onFinish: (@MainActor (TargetActionResult) -> Void)?
    private let labels: Set<String>
    private var buffer = ""
    private var lastInputAt: Date?
    private var result = TargetActionResult(changed: false, message: "target_interactive_cancelled", error: "cancelled")
    private var pendingActivation: String?
    private(set) var finished = false
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    private var timer: Timer?
    private var windows: [TargetOverlayWindow] = []

    init(
        state: TargetOverlayState,
        duration: TimeInterval,
        style: TargetOverlayStyle,
        activate: @escaping @MainActor (String) -> TargetActionResult,
        onFinish: (@MainActor (TargetActionResult) -> Void)?
    ) {
        self.state = state
        self.duration = max(1, duration)
        self.style = style
        self.activate = activate
        self.onFinish = onFinish
        self.labels = Set(state.report.targets.map { $0.label.uppercased() }.filter { !$0.isEmpty })
    }

    func start() -> TargetActionResult? {
        let badges = TargetOverlayBadge.badges(from: state)
        guard !badges.isEmpty else {
            return TargetActionResult(changed: false, message: "target_interactive: no visible targets", error: "no_targets")
        }
        guard installEventTap() else {
            return TargetActionResult(changed: false, message: "target_interactive: event tap unavailable", error: "event_tap_unavailable")
        }

        NSApplication.shared.setActivationPolicy(.accessory)
        windows = TargetOverlayPresenter.overlayWindows(for: badges, style: style)
        windows.forEach { $0.orderFrontRegardless() }

        let startedAt = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(startedAt: startedAt) }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        return nil
    }

    func updateStyle(_ style: TargetOverlayStyle) {
        guard !finished, self.style != style else { return }
        self.style = style
        windows.forEach { $0.updateStyle(style) }
    }

    func cancel() {
        finish(TargetActionResult(changed: false, message: "target_interactive_cancelled", error: "cancelled"))
    }

    func handle(_ input: KeyInput) {
        switch input.kind {
        case .escape:
            finish(TargetActionResult(changed: false, message: "target_interactive_cancelled", error: "cancelled"))
        case .delete:
            buffer = String(buffer.dropLast())
            lastInputAt = Date()
        case .characters(let value):
            guard !value.isEmpty else { return }
            let candidate = buffer + value.uppercased()
            if hasPrefix(candidate) {
                buffer = candidate
            } else if hasPrefix(value.uppercased()) {
                buffer = value.uppercased()
            } else {
                buffer = ""
            }
            lastInputAt = Date()
            activateIfUnambiguous()
        case .confirm:
            if labels.contains(buffer) {
                finishActivating(buffer)
            }
        case .arrow:
            break
        case .other:
            break
        }
    }

    private func tick(startedAt: Date) {
        if Date().timeIntervalSince(startedAt) >= duration {
            finish(TargetActionResult(changed: false, message: "target_interactive_timeout", error: "timeout"))
            return
        }
        guard let lastInputAt,
              Date().timeIntervalSince(lastInputAt) >= 0.45,
              labels.contains(buffer)
        else { return }
        finishActivating(buffer)
    }

    private func activateIfUnambiguous() {
        guard labels.contains(buffer) else { return }
        let longerMatches = labels.contains { $0 != buffer && $0.hasPrefix(buffer) }
        if !longerMatches {
            finishActivating(buffer)
        }
    }

    private func hasPrefix(_ value: String) -> Bool {
        labels.contains { $0.hasPrefix(value) }
    }

    private func finish(_ result: TargetActionResult) {
        guard !finished else { return }
        finished = true
        self.result = result
        complete()
    }

    private func finishActivating(_ label: String) {
        guard !finished else { return }
        finished = true
        pendingActivation = label
        result = TargetActionResult(changed: false, message: "target_interactive_selected \(label)")
        complete()
    }

    private func complete() {
        cleanup()
        if let pendingActivation {
            result = activate(pendingActivation)
            self.pendingActivation = nil
        }
        onFinish?(result)
    }

    private func hideOverlayNow() {
        guard !windows.isEmpty else { return }
        for window in windows {
            window.alphaValue = 0
            window.orderOut(nil)
            window.close()
        }
        windows = []
        NSApplication.shared.updateWindows()
    }

    private func cleanup() {
        timer?.invalidate()
        timer = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        eventTap = nil
        hideOverlayNow()
    }
}

@MainActor
private final class TargetGridInteractiveSession: TargetOverlaySessionHandle, KeyEventTapSession {
    private let duration: TimeInterval
    private let config: TargetGridConfig
    private var style: TargetOverlayStyle
    private let stateProvider: @MainActor (Int?, String) -> TargetOverlayState
    private let activate: @MainActor (Int?, String) -> TargetActionResult
    private let focusAt: @MainActor (CGRect) -> Void
    private let displayNeighbor: @MainActor (Int?, TargetGridArrowDirection) -> Int?
    private let onFinish: (@MainActor (TargetActionResult) -> Void)?
    private var path: String
    private var displayIndex: Int?
    private var labels: Set<String> = []
    private var currentTargets: [RoadieTarget] = []
    private var result = TargetActionResult(changed: false, message: "grid_interactive_cancelled", error: "cancelled")
    private var pendingActivation: String?
    private(set) var finished = false
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    private var timer: Timer?
    private var windows: [TargetOverlayWindow] = []
    private var lastActivityAt = Date()

    init(
        initialPath: String,
        initialDisplayIndex: Int?,
        duration: TimeInterval,
        config: TargetGridConfig,
        stateProvider: @escaping @MainActor (Int?, String) -> TargetOverlayState,
        activate: @escaping @MainActor (Int?, String) -> TargetActionResult,
        focusAt: @escaping @MainActor (CGRect) -> Void,
        displayNeighbor: @escaping @MainActor (Int?, TargetGridArrowDirection) -> Int?,
        onFinish: (@MainActor (TargetActionResult) -> Void)?
    ) {
        self.path = initialPath.uppercased()
        self.displayIndex = initialDisplayIndex
        self.duration = max(1, duration)
        self.config = config
        self.style = TargetOverlayStyle.grid(config)
        self.stateProvider = stateProvider
        self.activate = activate
        self.focusAt = focusAt
        self.displayNeighbor = displayNeighbor
        self.onFinish = onFinish
    }

    func start() -> TargetActionResult? {
        guard installEventTap() else {
            return TargetActionResult(changed: false, message: "grid_interactive: event tap unavailable", error: "event_tap_unavailable")
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        lastActivityAt = Date()
        show(path: path)
        wakeMouseIfNeeded()

        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        return nil
    }

    func updateStyle(_ style: TargetOverlayStyle) {
        guard !finished, self.style != style else { return }
        self.style = style
        windows.forEach { $0.updateStyle(style) }
    }

    func cancel() {
        finish(TargetActionResult(changed: false, message: "grid_interactive_cancelled", error: "cancelled"))
    }

    private func show(path: String) {
        hideOverlayNow()
        let state = stateProvider(displayIndex, path)
        let badges = TargetOverlayBadge.badges(from: state)
        currentTargets = state.report.targets
        labels = Set(state.report.targets.map { $0.label.uppercased() }.filter { !$0.isEmpty })
        windows = TargetOverlayPresenter.overlayWindows(for: badges, style: style)
        windows.forEach { $0.orderFrontRegardless() }
    }

    func handle(_ input: KeyInput) {
        let key = input.normalizedName
        if key == config.exitKey {
            finish(TargetActionResult(changed: false, message: "grid_interactive_cancelled", error: "cancelled"))
            return
        }
        if key == config.resetKey {
            markActivity()
            path = ""
            show(path: path)
            wakeMouseIfNeeded()
            return
        }
        if key == config.backKey {
            guard !path.isEmpty else { return }
            markActivity()
            path = String(path.dropLast())
            show(path: path)
            wakeMouseIfNeeded()
            return
        }
        if key == config.confirmActionKey {
            guard !path.isEmpty else { return }
            finishActivating(path)
            return
        }
        if config.arrowNavigationEnabled {
            switch input.kind {
            case .arrow(let direction):
                moveSelection(direction: direction)
                return
            default:
                break
            }
        }

        switch input.kind {
        case .escape:
            if config.mode == .autoClick {
                finish(TargetActionResult(changed: false, message: "grid_interactive_cancelled", error: "cancelled"))
            }
        case .delete:
            if config.mode == .autoClick {
                guard !path.isEmpty else { return }
                markActivity()
                path = String(path.dropLast())
                show(path: path)
                wakeMouseIfNeeded()
            }
        case .confirm:
            if config.mode == .autoClick {
                guard !path.isEmpty else { return }
                finishActivating(path)
            }
        case .arrow:
            break
        case .characters(let value):
            guard let label = value.uppercased().first.map(String.init),
                  labels.contains(label)
            else { return }
            markActivity()
            path += label
            if config.mode == .autoClick && path.count >= config.maxDepth {
                finishActivating(path)
            } else {
                show(path: path)
                wakeMouseIfNeeded()
            }
        case .other:
            break
        }
    }

    private func moveSelection(direction: KeyInput.ArrowDirection) {
        let ordered = orderedGridLabels()
        guard !path.isEmpty else {
            moveDisplay(direction: direction)
            return
        }
        guard let last = path.last,
              let index = ordered.firstIndex(of: String(last).uppercased())
        else { return }

        let row = index / config.columns
        let column = index % config.columns
        var nextRow = row
        var nextColumn = column

        switch direction {
        case .left:
            nextColumn -= 1
        case .right:
            nextColumn += 1
        case .up:
            nextRow -= 1
        case .down:
            nextRow += 1
        }

        switch config.arrowEdgeBehavior {
        case .clamp:
            nextRow = min(config.rows - 1, max(0, nextRow))
            nextColumn = min(config.columns - 1, max(0, nextColumn))
        case .wrap:
            nextRow = (nextRow + config.rows) % config.rows
            nextColumn = (nextColumn + config.columns) % config.columns
        }

        let nextIndex = nextRow * config.columns + nextColumn
        guard nextIndex != index, ordered.indices.contains(nextIndex) else { return }

        markActivity()
        path = String(path.dropLast()) + ordered[nextIndex]
        show(path: path)
        wakeMouseIfNeeded()
    }

    private func moveDisplay(direction: KeyInput.ArrowDirection) {
        guard let targetIndex = displayNeighbor(displayIndex, direction.targetGridDirection) else { return }
        markActivity()
        displayIndex = targetIndex
        show(path: path)
        wakeMouseIfNeeded()
    }

    private func markActivity() {
        lastActivityAt = Date()
    }

    private func wakeMouseIfNeeded() {
        if let frame = mouseFollowTargetFrame() {
            let target = CGPoint(x: frame.midX, y: frame.midY)
            if config.mouseFollowGrid {
                moveMouse(to: target)
            }
            if config.focusFollowGrid {
                focusAt(frame)
            }
            if config.mouseFollowGrid || config.focusFollowGrid {
                return
            }
        }
        let delta = CGFloat(config.wakeMousePixels)
        guard delta > 0,
              let current = CGEvent(source: nil)?.location
        else { return }
        let screenFrame = TargetOverlayPresenter.screenUnionFrame()
        let direction: CGFloat = current.x + delta <= screenFrame.maxX - 1 ? 1 : -1
        let moved = CGPoint(x: current.x + direction * delta, y: current.y)
        CGWarpMouseCursorPosition(moved)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: moved, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        CGWarpMouseCursorPosition(current)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: current, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    private func mouseFollowTargetFrame() -> CGRect? {
        if !path.isEmpty,
           let target = currentTargets.first(where: { $0.id.hasSuffix("/\(path)") }),
           let frame = target.frame?.cgRect {
            return frame
        }
        let frames = currentTargets.compactMap { $0.frame?.cgRect }
        let union = frames.reduce(nil as CGRect?, { partial, frame in
            partial.map { $0.union(frame) } ?? frame
        })
        if let union {
            return union
        }
        if let first = currentTargets.first,
           let frame = first.frame?.cgRect {
            return frame
        }
        return nil
    }

    private func moveMouse(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    private func orderedGridLabels() -> [String] {
        let count = config.rows * config.columns
        return Array(config.hintCharacters.map { String($0).uppercased() }.prefix(count))
    }

    private func tick() {
        if Date().timeIntervalSince(lastActivityAt) >= duration {
            finish(TargetActionResult(changed: false, message: "grid_interactive_timeout", error: "timeout"))
        }
    }

    private func finish(_ result: TargetActionResult) {
        guard !finished else { return }
        finished = true
        self.result = result
        complete()
    }

    private func finishActivating(_ path: String) {
        guard !finished else { return }
        finished = true
        pendingActivation = path
        result = TargetActionResult(changed: false, message: "grid_interactive_selected \(path)")
        complete()
    }

    private func complete() {
        cleanup()
        if let pendingActivation {
            result = activate(displayIndex, pendingActivation)
            self.pendingActivation = nil
        }
        onFinish?(result)
    }

    private func hideOverlayNow() {
        guard !windows.isEmpty else { return }
        for window in windows {
            window.alphaValue = 0
            window.orderOut(nil)
            window.close()
        }
        windows = []
        NSApplication.shared.updateWindows()
    }

    private func cleanup() {
        timer?.invalidate()
        timer = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        eventTap = nil
        hideOverlayNow()
    }
}

/// Politique du clic extérieur (SPEC-028), partagée avec les tests sans installer de tap système.
enum TargetSearchDismissal {
    static func isMouseDown(_ type: CGEventType) -> Bool {
        type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown
    }

    static func eventMask(search: Bool) -> CGEventMask {
        let keyboard = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard search else { return keyboard }
        let mouseTypes: [CGEventType] = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged, .leftMouseUp]
        return mouseTypes.reduce(keyboard) { mask, type in
            mask | CGEventMask(1 << type.rawValue)
        }
    }

    /// Annuler le Retour différé avant la fermeture empêche une activation après le clic.
    static func cancelIfOutside(at point: CGPoint, layout: SearchBarLayout?, model: inout TargetSearchModel) -> Bool {
        guard let layout, !layout.contains(point) else { return false }
        model.cancelPendingReturn()
        return true
    }
}

/// Session du mode recherche (SPEC-021). La logique est dans `TargetSearchModel` ; la session lit les
/// touches, met à jour l'affichage et active la cible figée au moment de la validation.
/// Une requête qui commence par `/` passe en mode commande (SPEC-023) : les touches vont alors à
/// `SlashCommandModel` et Retour exécute la commande par `SlashCommandRunner`.
@MainActor
private final class TargetSearchSession: TargetOverlaySessionHandle, KeyEventTapSession {
    /// Fermeture sans frappe pendant ce délai.
    static let idleTimeout: TimeInterval = 60

    private var model: TargetSearchModel
    /// Mode commande : créé à la frappe du `/` dans une requête vide, nil en mode recherche.
    private var commandModel: SlashCommandModel?
    private var inputPanel: SearchInputPanel?
    private var style: TargetOverlayStyle
    private let commands: SlashCommandRunner
    private let runDeferred: @MainActor ([String]) -> Void
    private let openSettings: @MainActor (SettingCategory?) -> Void
    private let activate: @MainActor (RoadieTarget, TargetActionVerb) -> TargetActionResult
    private let onFinish: (@MainActor (TargetActionResult) -> Void)?
    private var lastInputAt = Date()
    private(set) var finished = false
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    private var timer: Timer?
    private var windows: [TargetOverlayWindow] = []
    private var searchBarLayout: SearchBarLayout?
    /// Dernière barre montrée : le clic sur le chip retrouve son rectangle (session 099).
    private var shownBar: TargetSearchBar?
    /// Résultats dont la présentation se choisit (session 099) ; nil : liste seule.
    private var viewSource: LauncherViewSource?
    /// Écran du pointeur à l'ouverture : classement des cibles, et barre si `bar_screen` vaut `mouse`.
    private let pointerScreen: CGRect?
    /// Place de la barre (session 102) et glisser en cours : point de départ, centre de la barre au départ,
    /// déplacement réel.
    private var placement: SearchBarPlacement = .bottom
    private var drag: (start: CGPoint, center: CGPoint, moved: Bool)?
    /// Des fenêtres sont encore en cours de lecture.
    private var isLoading = true
    /// Lanceur (SPEC-073) : liste en sections au-dessus de la barre, et ligne choisie.
    private var launcher: LauncherSearchContext
    private var launcherList = LauncherList.empty
    private var launcherSelection: String?
    /// Requête et cibles de la dernière liste : elle n'est recalculée que si l'une change.
    private var launcherQuery: String?
    private var launcherTargetIDs: [String] = []
    /// Étapes du lanceur (SPEC-074) : objet, puis verbe, puis destination si le verbe en demande une.
    private enum LauncherStep: Equatable {
        case objects
        case verbs(LauncherSubject)
        case destinations(LauncherSubject, LauncherVerb)
        /// ⌘S (SPEC-079) : la saisie est l'abréviation ; échec si l'action ne se garde pas.
        case saving(LauncherAction, Result<LauncherAlias, LauncherAlias.Refusal>)
        /// Lot de la sélection multiple (SPEC-091) : ses verbes, puis la destination d'« Envoyer vers… ».
        case batchVerbs
        case batchDestinations
    }
    /// Sélection multiple (SPEC-091), gardée quand la saisie change.
    private var selection = LauncherSelection()
    private var step = LauncherStep.objects
    private var actionList = LauncherActionList()
    private var actionSelection: String?
    /// Saisie des deuxième et troisième étapes ; la requête de l'objet reste dans `model`.
    private var stepQuery = ""
    /// État de tuilage de la fenêtre dont les verbes sont montrés, lu une fois à l'entrée (SPEC-075).
    private var stepTiling: LauncherTilingState?
    /// Touche tenue qui change ce que fait Retour (SPEC-075).
    private var heldModifier: LauncherModifier?
    /// Maj tenue seule : sous-titre `mods.shift` d'une ligne de workflow (SPEC-088 FR-006).
    private var heldShift = false
    /// Rangs ⌘1 à ⌘9 : index des lignes montrées, dans l'ordre, calculés avec la géométrie.
    private var pickRows: [Int] = []
    /// Lettres Maj (SPEC-084) : index de la ligne de cible montrée pour chaque lettre, dans l'ordre affiché.
    private var letterRows: [String: Int] = [:]
    /// Lettres simples de `hint_characters`, dans leur ordre.
    private let letters: [String]
    /// Fichiers de Spotlight pour la saisie `filesQuery` (SPEC-077) ; `filesChanged` force la liste.
    private let fileSearch = LauncherFileSearch()
    private var files: [LauncherFile] = []
    private var filesQuery: String?
    private var filesChanged = false
    /// Ligne copiée par ⌘C : son détail le dit jusqu'à la frappe suivante.
    private var copiedRowID: String?
    /// Documents et onglets ouverts (SPEC-082), arrivés en fond après l'ouverture.
    private var openItems: [LauncherOpenItem] = []
    /// Chemin tapé (SPEC-087) : lecture du dossier en fond, éléments de la saisie `pathFor`.
    private let pathListing = LauncherPathListing()
    private var pathFiles: [LauncherFile] = []
    private var pathFor: String?
    /// Workflows (SPEC-088) : script en cours, saisie demandée et dernière réponse, par entrée.
    private var workflowRuns: [String: AlfredProcess] = [:]
    private var workflowRequested: [String: String] = [:]
    private var workflowResponses: [String: (argument: String, response: AlfredScriptFilterResponse?, error: String?)] = [:]
    private var workflowPending: [String: DispatchWorkItem] = [:]
    /// Aperçu actif (SPEC-078) : demande envoyée au contrôleur, attente de 150 ms, fantôme rendu.
    private var sentPreview: LauncherPreviewRequest?
    private var pendingPreview: LauncherPreviewRequest?
    private var previewWork: DispatchWorkItem?
    private var ghost: LauncherGhost?
    /// Étape « Garder » : la commande vient d'être copiée par ⌘C.
    private var savingCopied = false

    init(
        targets: [RoadieTarget],
        alphabet: String,
        style: TargetOverlayStyle,
        commands: SlashCommandRunner,
        runDeferred: @escaping @MainActor ([String]) -> Void,
        openSettings: @escaping @MainActor (SettingCategory?) -> Void,
        activate: @escaping @MainActor (RoadieTarget, TargetActionVerb) -> TargetActionResult,
        launcher: LauncherSearchContext,
        onFinish: (@MainActor (TargetActionResult) -> Void)?
    ) {
        self.launcher = launcher
        let mouse = NSEvent.mouseLocation
        let pointerScreen = NSScreen.screens.first { $0.frame.contains(mouse) }?.frame
        self.pointerScreen = pointerScreen
        self.placement = launcher.barPlacement
        self.model = TargetSearchModel(targets: targets, alphabet: alphabet) { Self.rank($0, windowOrder: -1, pointerScreen: pointerScreen) }
        self.letters = LauncherList.letters(alphabet)
        self.style = style
        self.commands = commands
        self.runDeferred = runDeferred
        self.openSettings = openSettings
        self.activate = activate
        self.onFinish = onFinish
    }

    /// Écran du pointeur d'abord : la première correspondance mise en avant est sous les yeux, pas sur
    /// un autre moniteur. Puis les fenêtres de l'avant vers l'arrière (cibles Roadie : -1).
    private static func rank(_ target: RoadieTarget, windowOrder: Int, pointerScreen: CGRect?) -> Int {
        guard let pointerScreen, let frame = (target.clickFrame ?? target.frame)?.cgRect else { return 100_000 + windowOrder }
        let ns = RoadieScreenCoordinate.axRectToNS(frame)
        return (pointerScreen.contains(CGPoint(x: ns.midX, y: ns.midY)) ? 0 : 100_000) + windowOrder
    }

    func append(_ targets: [RoadieTarget], windowOrder: Int) {
        guard !finished else { return }
        model.append(targets) { Self.rank($0, windowOrder: windowOrder, pointerScreen: pointerScreen) }
        render()
    }

    func finishLoading() {
        guard !finished else { return }
        isLoading = false
        render()
    }

    func start() -> TargetActionResult? {
        guard installEventTap() else {
            return TargetActionResult(changed: false, message: "target_search: event tap unavailable", error: "event_tap_unavailable")
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        // Une fenêtre par écran : la barre reste sur l'écran du pointeur choisi à l'ouverture.
        windows = NSScreen.screens.map { TargetOverlayWindow(frame: $0.frame, badges: [], style: style) }
        windows.forEach { $0.orderFrontRegardless() }
        let input = SearchInputPanel()
        input.viewCycle = SearchInputPanel.cycleKey(launcher.viewCycleKey, layout: TargetSearchHotkey.currentLayoutTable())
        input.onChange = { [weak self] text in self?.replaceInput(text) }
        input.onKey = { [weak self] key in self?.handleSearch(key) }
        input.onFlags = { [weak self] flags in self?.modifiersChanged(flags) }
        if let subject = launcher.initialSubject { enterVerbs(subject) }
        input.onCancel = { [weak self] in self?.cancel() }
        launcher.subscribeGrid { [weak self] view in self?.updateGrid(view) }
        inputPanel = input
        if let text = launcher.initialQuery, !text.isEmpty { model.replaceQuery(text) }
        render()
        input.beginEditing()
        if launcher.restoredQuery { input.selectAllText() }
        launcher.loadOpenItems { [weak self] items in
            guard let self, !self.finished else { return }
            self.openItems = items
            self.filesChanged = true
            self.render()
        }
        launcher.refreshApps { [weak self] apps in
            guard let self, !self.finished else { return }
            self.launcher.apps = apps
            self.launcherQuery = nil
            self.render()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        return nil
    }

    func updateStyle(_ style: TargetOverlayStyle) {
        guard !finished, self.style != style else { return }
        self.style = style
        windows.forEach { $0.updateStyle(style) }
        render()
    }

    func cancel() {
        finish(TargetActionResult(changed: false, message: "target_search_cancelled", error: "cancelled"))
    }

    fileprivate func handleMouseDown(at point: CGPoint, type: CGEventType, clicks: Int = 1) -> Bool {
        guard !finished else { return false }
        let nsPoint = RoadieScreenCoordinate.axRectToNS(CGRect(origin: point, size: .zero)).origin
        if let layout = searchBarLayout, layout.contains(nsPoint) {
            lastInputAt = Date()
            model.cancelPendingReturn()
            if let panel = layout.panel, panel.contains(nsPoint) {
                if type == .leftMouseDown, step != .objects,
                   let index = layout.suggestionIndex(at: nsPoint, count: actionList.rows.count,
                                                      selected: actionList.rows.firstIndex { $0.id == actionSelection && $0.id != nil }),
                   let id = actionList.rows[index].id {
                    actionSelection = id
                    confirmStep()
                    return true
                }
                if type == .leftMouseDown, commandModel == nil, step == .objects,
                   let index = layout.suggestionIndex(at: nsPoint, count: launcherList.rows.count, selected: selectedLauncherRow),
                   let id = launcherList.rows[index].id {
                    launcherSelection = id
                    syncHighlight()
                    activateSelection(immediate: true)
                    return true
                }
                if type == .leftMouseDown, var command = commandModel,
                   let index = layout.suggestionIndex(at: nsPoint, count: command.suggestions.count, selected: command.selected) {
                    command.selectSuggestion(at: index)
                    command.acceptSelectedSuggestion()
                    commandModel = command
                    render()
                }
                // Hors d'une ligne (marges, titres) : le fond de la liste déplace la barre (session 102).
                if type == .leftMouseDown { beginDrag(at: nsPoint, bar: layout.bar, clicks: clicks) }
                return true
            }
            // Chip de la présentation (session 099) : un clic passe à la suivante.
            if type == .leftMouseDown, step == .objects, viewSource != nil, let bar = shownBar,
               let chip = SearchBarRenderer.counterFrame(bar, bar: layout.bar, style: style), chip.contains(nsPoint) {
                cycleView()
                return true
            }
            // Bord de la barre, hors du champ : glisser la déplace, double-clic la remet à sa place par défaut.
            if type == .leftMouseDown, let bar = shownBar,
               !SearchBarRenderer.inputFrame(bar, bar: layout.bar, style: style).contains(nsPoint) {
                beginDrag(at: nsPoint, bar: layout.bar, clicks: clicks)
                return true
            }
            return false // Le champ natif reçoit clic, sélection et menu contextuel.
        }
        if TargetSearchDismissal.cancelIfOutside(at: nsPoint, layout: searchBarLayout, model: &model) { cancel() }
        return false
    }

    /// Début d'un glisser de la barre ; un double-clic oublie la place retenue (session 102).
    private func beginDrag(at point: CGPoint, bar: CGRect, clicks: Int) {
        if clicks >= 2 {
            drag = nil
            placement = launcher.defaultBarPlacement
            launcher.savePlacement(nil)
            render()
            return
        }
        drag = (point, CGPoint(x: bar.midX, y: bar.midY), false)
    }

    /// Glisser de la barre : elle suit le pointeur ; au relâchement, sa place est retenue. Vrai si
    /// l'événement appartient au glisser. O(rendu).
    fileprivate func handleMouseDrag(at point: CGPoint, ended: Bool) -> Bool {
        guard !finished, var current = drag else { return false }
        let nsPoint = RoadieScreenCoordinate.axRectToNS(CGRect(origin: point, size: .zero)).origin
        let dx = nsPoint.x - current.start.x, dy = nsPoint.y - current.start.y
        if abs(dx) + abs(dy) > 2 { current.moved = true }
        if current.moved, let screen = windows.first(where: { $0.frame.contains(current.center) })?.frame
            ?? launcher.barScreenFrame ?? pointerScreen {
            placement = .custom(center: CGPoint(x: current.center.x + dx, y: current.center.y + dy), in: screen)
            render()
        }
        drag = ended ? nil : current
        if ended, current.moved { launcher.savePlacement(placement) }
        return true
    }

    private func replaceInput(_ text: String) {
        guard !finished else { return }
        lastInputAt = Date()
        model.cancelPendingReturn()
        if step != .objects {
            stepQuery = text
            refreshActions()
            render()
            return
        }
        if text.hasPrefix("/"), !Self.isPath(text) {
            if commandModel == nil {
                model.replaceQuery("/")
                enterCommandMode()
            }
            commandModel?.replaceInput(String(text.dropFirst()))
        } else {
            commandModel = nil
            model.replaceQuery(text)
        }
        render()
    }

    /// Exigé par `KeyEventTapSession` ; la recherche reçoit `SearchKeyInput` via `handleSearch`.
    func handle(_ input: KeyInput) {}

    fileprivate func handleSearch(_ input: SearchKeyInput) {
        guard !finished else { return }
        lastInputAt = Date()
        if step != .objects {
            handleStep(input)
            return
        }
        // Mode commande (SPEC-023 R3) : aiguillage avant le modèle de recherche. Un chemin `/Users…`
        // reste une recherche (SPEC-087).
        if commandModel != nil {
            handleCommand(input)
            return
        }
        if case .escape = input.kind {
            model.cancelPendingReturn()
            // Échap vide d'abord la sélection, puis ferme (SPEC-091 FR-003).
            if !selection.isEmpty {
                selection.clear()
                render()
                return
            }
            // Message distinct : le contrôleur rend le focus clavier à l'application (session 097).
            finish(TargetActionResult(changed: false, message: "target_search_escaped", error: "cancelled"))
            return
        }
        if case .confirm(let shift, let command, let option, let control, let isRepeat) = input.kind {
            guard !isRepeat else { return }
            // Retour avec une sélection : ses verbes, sans agir tout de suite (FR-003).
            if !selection.isEmpty {
                enterBatch()
                render()
                return
            }
            if let modifier = Self.modifier(command: command && !shift, option: option, control: control),
               let variant = currentVariant(modifier) {
                finishVariant(variant)
                return
            }
            if case .calc(let calc)? = launcherList.row(for: launcherSelection) {
                finishCalc(calc)
                return
            }
            if confirmWorkflow(modifiers: Self.alfredModifiers(command: command, option: option, control: control, shift: shift)) { return }
            if confirmWeb() { return }
            if case .app(let app, _)? = launcherList.row(for: launcherSelection) {
                finishLaunching(app)
                return
            }
            if case .file(let file)? = launcherList.row(for: launcherSelection) {
                finishAction(LauncherAction(subject: .file(file), verb: .open, destination: nil))
                return
            }
            switch launcherList.row(for: launcherSelection) {
            case .phrase(let action, _)?, .alias(_, let action, _)?:
                finishAction(action)
                return
            case .project(let project)?:
                finishAction(LauncherAction(subject: .project(project.name), verb: .reopenProject, destination: nil))
                return
            case .action(let key, let action, _, _)?:
                if key == "undo-batch" { finishUndo() } else { finishAction(action) }
                return
            case .rule(let suggestion, let choice)?:
                finishRule(suggestion, choice)
                return
            case .openItem(let item)?:
                finishOpenItem(item)
                return
            default: break
            }
            guard let target = model.highlighted else { return }
            if let verb = model.pressReturn(shift: shift, command: command, at: Date()) {
                finishActivating(target, verb)
            }
            return
        }
        // Retour seul en attente : les autres touches sont ignorées jusqu'à l'échéance.
        guard !model.isAwaitingSecondReturn else { return }
        switch input.kind {
        case .text(let value):
            model.type(value)
            if model.isCommandMode, !Self.isPath(model.query) { enterCommandMode() }
        case .labelCharacter(let value):
            // Maj + lettre d'une pastille : sa ligne s'ouvre, comme ⌘ + chiffre (SPEC-084).
            guard let index = letterRows[value], index < launcherList.rows.count else { return }
            launcherSelection = launcherList.rows[index].id
            syncHighlight()
            activateSelection(immediate: true)
            return
        case .delete:
            model.deleteBackward()
        case .next, .previous:
            navigate(input)
        case .actions:
            // Chemin tapé : → ouvre les verbes, Tab complète (SPEC-087).
            if Self.isPath(model.query), case .file(let file)? = launcherList.row(for: launcherSelection) {
                enterVerbs(.file(file))
            } else if case .workflowItem(_, let item, _)? = launcherList.row(for: launcherSelection), item.isFile,
                      let path = item.arg.first, path.hasPrefix("/") {
                // Fichier rendu par un workflow (filtre de fichiers) : ses verbes de Roadie (SPEC-089 FR-006).
                enterVerbs(.file(LauncherFile(path: path, name: (path as NSString).lastPathComponent, isFolder: false, lastUsed: nil)))
            } else {
                navigate(SearchKeyInput(kind: .next, navigationSource: .tab))
            }
        case .pick(let rank):
            pick(rank)
            return
        case .copy:
            copySelection()
        case .save:
            if let action = objectAction() { enterSaving(action) }
        case .showRules:
            model.replaceQuery("")
        case .selectToggle:
            if let subject = Self.subject(of: launcherList.row(for: launcherSelection)) { selection.toggle(subject) }
        case .selectAddNext:
            if let subject = Self.subject(of: launcherList.row(for: launcherSelection)), LauncherSelection.key(subject) != nil {
                selection.add(subject)
                launcherSelection = launcherList.neighbour(of: launcherSelection, step: 1)
                syncHighlight()
            }
        case .selectRemoveLast:
            selection.removeLast()
        case .selectionVerbs:
            if !selection.isEmpty { enterBatch() }
        case .selectClear:
            selection.clear()
        case .move(let step):
            moveInGrid(step)
        case .cycleView:
            cycleView()
        case .preview:
            if case .file(let file)? = launcherList.row(for: launcherSelection) {
                finishAction(LauncherAction(subject: .file(file), verb: .quickLook, destination: nil))
                return
            }
            if case .workflowItem(_, let item, _)? = launcherList.row(for: launcherSelection), let raw = item.quickLookURL {
                let path = URL(string: raw).flatMap { $0.isFileURL ? $0.path : nil } ?? NSString(string: raw).expandingTildeInPath
                if path.hasPrefix("/") {
                    let file = LauncherFile(path: path, name: (path as NSString).lastPathComponent, isFolder: false, lastUsed: nil)
                    finishAction(LauncherAction(subject: .file(file), verb: .quickLook, destination: nil))
                    return
                }
            }
        case .escape, .confirm, .ignored:
            break
        }
        render()
    }

    /// Flèches et Ctrl-N/P parcourent la liste du lanceur ; Tab complète la ligne choisie.
    private func navigate(_ input: SearchKeyInput) {
        guard !launcherList.rows.isEmpty else { model.handleNavigation(input); return }
        // Grille (SPEC-092 FR-004) : ↑ ↓ changent de rangée ; Tab garde son rôle.
        if let columns = gridColumns, input.navigationSource != .tab {
            if case .next = input.kind { moveInGrid(columns) } else { moveInGrid(-columns) }
            return
        }
        if input.navigationSource == .tab, case .next = input.kind {
            switch launcherList.row(for: launcherSelection) {
            case .app(let app, _): enterVerbs(.app(app))
            case .target(let target): enterVerbs(.target(target))
            case .file(let file):
                if Self.isPath(model.query) { completePath(file) } else { enterVerbs(.file(file)) }
            case .phrase(let action, _), .alias(_, let action, _): enterVerbs(action.subject)
            case .project(let project): enterVerbs(.project(project.name))
            case .action(_, let action, _, _): enterVerbs(action.subject)
            case .rule, .openItem, .calc: break
            case .workflowKeyword(let entry): completeWorkflow(entry, nil)
            case .web(let row):
                if let url = row.url { enterVerbs(.url(url)) } else if case .hint(let search) = row.kind { model.replaceQuery(search.keyword + " ") }
            case .history(let query): model.replaceQuery(query)
            case .workflowItem(let entry, let item, _):
                // Fichier rendu par un workflow (filtre de fichiers, grille de fichiers) : ses verbes de Roadie.
                if item.isFile, let path = item.arg.first, path.hasPrefix("/") {
                    enterVerbs(.file(LauncherFile(path: path, name: (path as NSString).lastPathComponent, isFolder: false, lastUsed: nil)))
                } else if let text = item.autocomplete { completeWorkflow(entry, text) }
            case .header, nil: model.handleNavigation(input)
            }
            return
        }
        guard case .next = input.kind else {
            launcherSelection = launcherList.neighbour(of: launcherSelection, step: -1)
            syncHighlight()
            return
        }
        launcherSelection = launcherList.neighbour(of: launcherSelection, step: 1)
        syncHighlight()
    }

    /// La ligne choisie et le cadre épais à l'écran désignent la même cible. O(n).
    private func syncHighlight() {
        switch launcherList.row(for: launcherSelection) {
        case .target(let target): model.highlight(targetID: target.id)
        case .app, .file, .phrase, .alias, .project, .action, .rule, .openItem, .calc, .workflowKeyword, .workflowItem, .web, .history:
            model.highlight(targetID: nil)
        case .header, nil: break
        }
    }

    /// Recalcule la liste si la requête ou les cibles ont changé. Nouvelle requête : la meilleure
    /// ligne est choisie ; nouvelles cibles seulement : la ligne choisie est gardée si elle reste. O(a + n).
    /// Lignes de la barre, puis la présentation choisie pour leur source (session 099).
    private func refreshLauncher() {
        refreshLauncherRows()
        viewSource = currentViewSource()
        applyViewMode()
    }

    /// Présentation des résultats : celle retenue pour la source ; la grille d'un workflow (092) garde la
    /// sienne. O(1).
    private var viewMode: LauncherViewMode { launcher.workflowGrid == nil ? launcher.viewBook.mode(for: viewSource) : .list }

    /// Colonnes de la grille montrée ; nil pour une liste.
    private var gridColumns: Int? {
        if let grid = launcher.workflowGrid { return grid.loadingText == nil ? grid.columns : nil }
        return viewMode.columns
    }

    /// Source des résultats (FR-001) : une seule entrée de workflow à résultats, un chemin tapé, ou des
    /// fichiers dans la recherche ordinaire. O(e + n).
    private func currentViewSource() -> LauncherViewSource? {
        guard launcher.workflowGrid == nil, step == .objects, commandModel == nil, !model.query.isEmpty else { return nil }
        let runs = launcher.workflowEntries.filter { if case .run = $0.match(model.query) { return true } else { return false } }
        if !runs.isEmpty {
            guard runs.count == 1, let entry = runs.first, [.scriptFilter, .listFilter, .fileFilter].contains(entry.kind) else { return nil }
            let files = entry.kind == .fileFilter || launcherList.rows.contains { if case .workflowItem(_, let item, _) = $0 { return item.isFile } else { return false } }
            return .workflow(entry.id, itemsAreFiles: files)
        }
        if Self.isPath(model.query) { return .folder(LauncherPathRules.parts(model.query).directory) }
        return launcherList.rows.contains { if case .file = $0 { return true } else { return false } } ? .files : nil
    }

    /// En grille : lignes sans titres de section, fichiers seuls pour la recherche ordinaire ; la ligne
    /// choisie reste si elle est montrée. Sans effet en liste. O(n).
    private func applyViewMode() {
        guard let source = viewSource, viewMode != .list else { return }
        let rows = source.gridRows(launcherList.rows)
        guard rows != launcherList.rows else { return }
        launcherList = .idle(rows)
        if launcherList.row(for: launcherSelection) == nil { launcherSelection = launcherList.best }
        syncHighlight()
    }

    /// Présentation suivante pour cette source (touche ou chip), retenue ; les lignes sont refaites. O(s).
    private func cycleView() {
        guard let source = viewSource else { return }
        launcher.viewBook.set(viewMode.next, for: source)
        launcher.saveViews(launcher.viewBook)
        launcherQuery = nil
        filesChanged = true
        render()
    }

    private func refreshLauncherRows() {
        if let grid = launcher.workflowGrid {
            refreshGrid(grid)
            return
        }
        let runs = launcher.workflowEntries.compactMap { entry -> (entry: AlfredEntry, argument: String)? in
            if case .run(let argument) = entry.match(model.query) { return (entry, argument) }
            return nil
        }
        pruneWorkflows(keeping: Set(runs.map(\.entry.id)))
        if !runs.isEmpty {
            refreshWorkflows(runs)
            return
        }
        if Self.isPath(model.query) {
            refreshPath()
            return
        }
        refreshFiles()
        let ids = model.matches.map(\.id)
        guard model.query != launcherQuery || ids != launcherTargetIDs || filesChanged else { return }
        let queryChanged = model.query != launcherQuery
        if queryChanged { copiedRowID = nil }
        launcherQuery = model.query
        launcherTargetIDs = ids
        filesChanged = false
        // Barre vide (SPEC-081) : les propositions du moment, la première choisie.
        if model.query.isEmpty {
            launcherList = .idle(launcher.idleRows)
            if queryChanged || launcherList.row(for: launcherSelection) == nil { launcherSelection = launcherList.best }
            syncHighlight()
            return
        }
        // Phrase (SPEC-079) : les premiers mots cherchent l'objet, la ligne de l'action passe en tête.
        let phrase = LauncherPhrase.parse(model.query, destinations: launcher.destinations, newStageHome: launcher.newStageHome)
        launcherList = LauncherList(query: phrase?.objectQuery ?? model.query, apps: launcher.apps, details: launcher.details,
                                    targets: model.matches, ranking: launcher.ranking, now: Date(), context: launcher.rankingContext,
                                    files: phrase == nil ? files : [], projects: launcher.projects, openItems: openItems)
        if let phrase, let subject = Self.subject(of: launcherList.row(for: launcherList.best)),
           let action = phrase.action(for: subject, activeStage: launcher.activeStage) {
            launcherList.prepend(.phrase(action, LauncherPhrase.title(action)), header: "Phrase")
        }
        if let (name, alias) = launcher.aliases.alias(for: model.query), let action = launcher.aliasAction(alias) {
            launcherList.prepend(.alias(name, action, LauncherPhrase.title(action)), header: "Abréviation")
        }
        // Mots-clés de workflows en cours de frappe (SPEC-088), après la première section.
        let keywords = launcher.workflowEntries.filter { $0.match(model.query) == .suggest }
        launcherList.insertSection("Workflows", keywords.prefix(4).map(LauncherList.Row.workflowKeyword))
        // Recherches de repli et actions universelles sur texte des workflows, en bas (SPEC-089 FR-003, FR-004).
        launcherList.appendSection("Repli", fallbackRows(model.query))
        // Web (SPEC-090) : repli en bas ; recherche par mot-clé et adresse tapée en tête, choisies.
        let webRows = LauncherWeb.fallbackRows(model.query, template: launcher.webSearchTemplate,
                                               searches: launcher.webSearches, fallbacks: launcher.fallbackSearches).map(LauncherList.Row.web)
        if model.query.hasPrefix("^") {
            // `^texte` (lu sur « ⌃ ↩ ») : les recherches web en tête, la première choisie (session 094).
            launcherList.prependSection("Web", webRows)
        } else {
            launcherList.appendSection("Web", webRows)
            if let (search, text) = LauncherWeb.keywordSearch(model.query, in: launcher.webSearches) {
                if text.isEmpty {
                    launcherList.prepend(.web(LauncherWebRow(kind: .hint(search), title: "\(search.title) : tapez la recherche")), header: "Web")
                } else if let url = LauncherWeb.searchURL(search.url, query: text) {
                    launcherList.prepend(.web(LauncherWebRow(kind: .search(url), title: "Rechercher « \(text) » sur \(search.title)")), header: "Web")
                }
            } else if let search = launcher.webSearches.first(where: { $0.keyword.lowercased() == model.query.lowercased() }) {
                // Mot-clé seul : l'invite, sans prendre la sélection (`g` ne cache pas Ghostty).
                launcherList.insertSection("Web", [.web(LauncherWebRow(kind: .hint(search), title: "\(search.title) : tapez la recherche"))])
            }
        }
        if let url = LauncherWeb.address(model.query) {
            launcherList.prepend(.web(LauncherWebRow(kind: .address(url), title: "Ouvrir \(url.absoluteString)")), header: "Adresse")
        }
        // Calcul (SPEC-087) : son résultat passe en tête et devient la ligne choisie.
        if let calc = LauncherCalculator.evaluate(model.query) {
            launcherList.prepend(.calc(calc), header: "Calcul")
        }
        if queryChanged || launcherList.row(for: launcherSelection) == nil { launcherSelection = launcherList.best }
        syncHighlight()
    }

    // MARK: - Workflows (SPEC-088)

    /// Bits des modificateurs d'Alfred pour les touches tenues avec Retour.
    private static func alfredModifiers(command: Bool, option: Bool, control: Bool, shift: Bool) -> Int {
        (command ? 1_048_576 : 0) + (option ? 524_288 : 0) + (control ? 262_144 : 0) + (shift ? 131_072 : 0)
    }

    /// Entrées qui ne correspondent plus à la saisie : leur script s'arrête, leur réponse est oubliée.
    private func pruneWorkflows(keeping active: Set<String>) {
        for key in Set(workflowRuns.keys).union(workflowResponses.keys).union(workflowPending.keys) where !active.contains(key) {
            workflowRuns.removeValue(forKey: key)?.cancel()
            workflowPending.removeValue(forKey: key)?.cancel()
            workflowResponses[key] = nil
            workflowRequested[key] = nil
        }
    }

    /// Mot-clé tapé : seules les lignes de ce ou ces workflows, sous leur nom ; la réponse précédente
    /// reste affichée pendant que le script tourne (FR-002, FR-005, FR-006). O(i log i).
    private func refreshWorkflows(_ runs: [(entry: AlfredEntry, argument: String)]) {
        let query = model.query
        for run in runs where run.entry.kind == .scriptFilter || run.entry.kind == .fileFilter { requestScriptFilter(run.entry, run.argument) }
        guard query != launcherQuery || filesChanged else { return }
        let queryChanged = query != launcherQuery
        if queryChanged { copiedRowID = nil }
        launcherQuery = query
        filesChanged = false
        var rows: [LauncherList.Row] = []
        for (entry, argument) in runs {
            rows.append(.header(entry.workflowName))
            if entry.kind == .listFilter {
                // Filtre de liste (SPEC-089 FR-005) : éléments fixes, filtrés par la barre.
                let items = AlfredScriptFilterResponse.filter(entry.listItems, query: argument, mode: entry.filterMode)
                rows += items.enumerated().map { .workflowItem(entry, $0.element, index: $0.offset) }
                continue
            }
            guard entry.kind == .scriptFilter || entry.kind == .fileFilter else { rows.append(.workflowKeyword(entry)); continue }
            guard let answer = workflowResponses[entry.id], let response = answer.response else {
                let waiting = workflowResponses[entry.id]?.error ?? (entry.runningSubtitle.isEmpty ? "Recherche…" : entry.runningSubtitle)
                rows.append(.workflowItem(entry, AlfredItem(title: entry.title, subtitle: waiting, valid: false), index: 0))
                continue
            }
            var items = entry.filtersResults ? AlfredScriptFilterResponse.filter(response.items, query: argument, mode: entry.filterMode) : response.items
            if !response.skipKnowledge {
                // Classement appris par `uid`, l'ordre du script sinon (tri stable).
                let ranking = launcher.ranking
                items = items.enumerated().sorted { a, b in
                    let ua = a.element.uid.map { ranking.exactUses("\(entry.id):\($0)", query: query) } ?? 0
                    let ub = b.element.uid.map { ranking.exactUses("\(entry.id):\($0)", query: query) } ?? 0
                    return ua != ub ? ua > ub : a.offset < b.offset
                }.map(\.element)
            }
            if items.isEmpty { rows.append(.workflowItem(entry, AlfredItem(title: "Aucun résultat", subtitle: entry.title, valid: false), index: 0)) }
            rows += items.enumerated().map { .workflowItem(entry, $0.element, index: $0.offset) }
        }
        launcherList = .idle(rows)
        if queryChanged || launcherList.row(for: launcherSelection) == nil { launcherSelection = launcherList.best }
        syncHighlight()
    }

    /// Grille d'un workflow (SPEC-092) : ses tuiles, filtrées par la saisie si la grille l'est ; à
    /// l'ouverture, la tuile `preselect`, sinon la première choisissable. O(n × m).
    private func refreshGrid(_ grid: AlfredGridView) {
        let first = launcherQuery == nil
        guard first || model.query != launcherQuery else { return }
        launcherQuery = model.query
        if let text = grid.loadingText {
            // Attente ou échec du script : une seule ligne, sans tuiles.
            launcherList = .idle([.workflowItem(grid.entry, AlfredItem(title: text, subtitle: grid.entry.workflowName, valid: false), index: 0)])
            launcherSelection = launcherList.best
            return
        }
        var items = grid.filterable ? AlfredScriptFilterResponse.filter(grid.items, query: model.query, mode: grid.entry.filterMode) : grid.items
        if grid.learnsOrder { items = AlfredGridView.learned(items, entryID: grid.entry.id, ranking: launcher.ranking, query: model.query) }
        launcherList = .idle(items.enumerated().map { .workflowItem(grid.entry, $0.element, index: $0.offset) })
        let preselected = first ? grid.preselect.flatMap { uid in items.firstIndex { $0.uid == uid } } : nil
        let index = preselected ?? items.firstIndex(where: AlfredGridView.isSelectable)
        launcherSelection = index.map { launcherList.rows[$0].id } ?? nil
    }

    /// Tuiles arrivées après le texte d'attente (session 095) : la grille ouverte est remplacée, la saisie
    /// gardée, la présélection appliquée. Une autre grille ou une barre fermée l'ignorent.
    private func updateGrid(_ view: AlfredGridView) {
        guard !finished, launcher.workflowGrid?.entry.id == view.entry.id else { return }
        launcher.workflowGrid = view
        launcherQuery = nil
        launcherSelection = nil
        render()
    }

    /// Tuile voisine dans la grille (← → : ± 1, ↑ ↓ : ± colonnes), espaceurs sautés. O(n / |step|).
    private func moveInGrid(_ step: Int) {
        guard let index = selectedLauncherRow else { return }
        let rows = launcherList.rows
        let selectable: (Int) -> Bool = { index in
            if case .workflowItem(_, let item, _) = rows[index] { return AlfredGridView.isSelectable(item) }
            return rows[index].id != nil
        }
        if let next = AlfredGridView.neighbour(of: index, step: step, count: rows.count, selectable: selectable) {
            launcherSelection = rows[next].id
        }
    }

    /// Lignes de repli : texte du workflow avec la saisie, ou nom de l'action universelle. O(t).
    private func fallbackRows(_ query: String) -> [LauncherList.Row] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        return launcher.workflowTriggers.enumerated().compactMap { index, entry in
            let title: String
            switch entry.kind {
            case .fallback: title = entry.title.replacingOccurrences(of: "{query}", with: text)
            case .universalAction where entry.acceptsText: title = "\(entry.title) : « \(text) »"
            default: return nil
            }
            return .workflowItem(entry, AlfredItem(title: title, subtitle: entry.workflowName, arg: [text]), index: index)
        }
    }

    /// Lance le Script Filter pour cet argument : tout de suite à la première frappe, 100 ms après la
    /// dernière ensuite ; la frappe suivante arrête le script en cours (FR-004). « Alfred filtre les
    /// résultats » : une seule fois par mot-clé. `rerun` : relancé à l'identique.
    private func requestScriptFilter(_ entry: AlfredEntry, _ argument: String, force: Bool = false) {
        let key = entry.id
        if !force {
            if let answer = workflowResponses[key], entry.filtersResults || answer.argument == argument { return }
            if workflowRequested[key] == argument { return }
        }
        workflowRequested[key] = argument
        workflowRuns.removeValue(forKey: key)?.cancel()
        workflowPending.removeValue(forKey: key)?.cancel()
        let query = model.query
        let start: @MainActor () -> Void = { [weak self] in
            guard let self, !self.finished, self.workflowRequested[key] == argument else { return }
            self.workflowRuns[key] = self.launcher.runScriptFilter(entry, argument) { [weak self] response, error in
                guard let self, !self.finished, self.workflowRequested[key] == argument else { return }
                self.workflowRuns[key] = nil
                self.workflowResponses[key] = (argument, response, error ?? (response == nil ? "Réponse illisible" : nil))
                self.filesChanged = true
                self.render()
                if let rerun = response?.rerun {
                    DispatchQueue.main.asyncAfter(deadline: .now() + rerun) { [weak self] in
                        MainActor.assumeIsolated {
                            guard let self, !self.finished, self.model.query == query else { return }
                            self.requestScriptFilter(entry, argument, force: true)
                        }
                    }
                }
            }
        }
        guard workflowResponses[key] != nil, !force else { start(); return }
        let work = DispatchWorkItem { MainActor.assumeIsolated { start() } }
        workflowPending[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    /// Retour sur une ligne de workflow ; vrai si c'en était une (FR-007). Modificateur sans connexion
    /// propre : géré par le moteur (research R6).
    private func confirmWorkflow(modifiers: Int) -> Bool {
        switch launcherList.row(for: launcherSelection) {
        case .workflowKeyword(let entry):
            if case .run(let argument) = entry.match(model.query), entry.kind == .keyword {
                finishWorkflow(entry, arg: [argument], variables: [:], modifiers: modifiers, rankingKey: entry.id)
            } else if case .suggest = entry.match(model.query) {
                // Entrée Keyword sans argument obligatoire : Retour la lance, comme Alfred (FR-003).
                if entry.kind == .keyword, entry.argument != .required {
                    finishWorkflow(entry, arg: [""], variables: [:], modifiers: modifiers, rankingKey: entry.id)
                } else {
                    completeWorkflow(entry, nil)
                    render()
                }
            }
            return true
        case .workflowItem(let entry, let item, let index):
            let mod = item.mods[modifiers]
            guard mod?.valid ?? item.valid else {
                if let text = item.autocomplete { completeWorkflow(entry, text); render() }
                return true
            }
            // Grille : variables du schéma au moment de la grille et de sa réponse (SPEC-092 FR-006).
            var variables = entry.kind == .grid ? launcher.workflowGrid?.variables ?? [:] : workflowResponses[entry.id]?.response?.variables ?? [:]
            variables.merge(item.variables) { $1 }
            variables.merge(mod?.variables ?? [:]) { $1 }
            finishWorkflow(entry, arg: mod?.arg ?? item.arg, variables: variables, modifiers: modifiers,
                           rankingKey: LauncherList.Row.workflowItem(entry, item, index: index).rankingKey)
            return true
        default:
            return false
        }
    }

    /// Retour sur une ligne web ou une recherche récente ; vrai si c'en était une (SPEC-090).
    private func confirmWeb() -> Bool {
        switch launcherList.row(for: launcherSelection) {
        case .web(let row):
            if let url = row.url {
                finishAction(LauncherAction(subject: .url(url), verb: .open, destination: nil))
            } else if case .hint(let search) = row.kind {
                model.replaceQuery(search.keyword + " ")
                render()
            }
            return true
        case .history(let query):
            model.replaceQuery(query)
            render()
            return true
        default:
            return false
        }
    }

    /// Tab : `autocomplete` d'une ligne après le mot-clé (research R7), ou le mot-clé seul.
    private func completeWorkflow(_ entry: AlfredEntry, _ text: String?) {
        let prefix = entry.keyword + (entry.withSpace ? " " : "")
        let completed = text.map { $0.lowercased().hasPrefix(entry.keyword.lowercased()) ? $0 : prefix + $0 } ?? prefix
        model.replaceQuery(completed)
    }

    private func finishWorkflow(_ entry: AlfredEntry, arg: [String], variables: [String: String], modifiers: Int, rankingKey: String?) {
        guard !finished else { return }
        finished = true
        let query = model.query
        launcher.recordQuery(query)
        cleanup()
        if let rankingKey { launcher.recordVisit(rankingKey, query) }
        onFinish?(launcher.runWorkflow(entry, arg, variables, modifiers))
    }

    /// Icône d'une ligne de workflow : image du workflow (chemin relatif à son dossier), icône d'un
    /// fichier, ou icône du workflow.
    private static func workflowIcon(_ icon: AlfredIcon?, entry: AlfredEntry) -> SlashSuggestion.Icon {
        let fallback: SlashSuggestion.Icon = entry.icon.map(SlashSuggestion.Icon.image) ?? .symbol("puzzlepiece.extension")
        switch icon {
        case .image(let path)?:
            let absolute = path.hasPrefix("/") ? path : (entry.folder as NSString).appendingPathComponent(path)
            return FileManager.default.fileExists(atPath: absolute) ? .image(absolute) : fallback
        case .fileIcon(let path)?: return .file(NSString(string: path).expandingTildeInPath)
        case .fileType?: return .symbol("doc")
        case nil: return fallback
        }
    }

    /// Saisie qui désigne un chemin plutôt qu'une commande (SPEC-087 FR-004). O(c + r).
    private static func isPath(_ text: String) -> Bool {
        LauncherPathRules.isPath(text, commands: LauncherPathRules.commandNames, rootEntries: LauncherPathRules.rootEntries)
    }

    /// Chemin tapé : le dossier est lu en fond, la liste montre ses éléments dès la réponse ; rien
    /// d'autre n'est cherché (SPEC-087 FR-005, FR-008). O(f).
    private func refreshPath() {
        let query = model.query
        if query != pathFor {
            pathFor = query
            fileSearch.cancel()
            pathListing.list(LauncherPathRules.parts(query)) { [weak self] files in
                guard let self, !self.finished, self.model.query == query, self.step == .objects else { return }
                self.pathFiles = files
                self.filesChanged = true
                self.render()
            }
        }
        guard query != launcherQuery || filesChanged else { return }
        let queryChanged = query != launcherQuery
        if queryChanged { copiedRowID = nil }
        launcherQuery = query
        filesChanged = false
        launcherList = .path(pathFiles)
        if queryChanged || launcherList.row(for: launcherSelection) == nil { launcherSelection = launcherList.best }
        syncHighlight()
    }

    /// Tab sur un élément d'un chemin : la saisie devient son chemin, `/` final pour un dossier (FR-006).
    private func completePath(_ file: LauncherFile) {
        model.replaceQuery(LauncherPathRules.completion(file, in: LauncherPathRules.parts(model.query)))
    }

    /// Retour sur un calcul : le résultat est copié, la barre se ferme (SPEC-087 FR-003).
    private func finishCalc(_ calc: LauncherCalculation) {
        launcher.recordQuery(model.query)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(calc.text, forType: .string)
        finish(TargetActionResult(changed: true, message: "launcher calc copied"))
    }

    /// Nouvelle saisie : les fichiers qui la contiennent encore restent affichés pendant que Spotlight
    /// cherche ; sa réponse ne sert que si la saisie n'a pas changé entre-temps. O(f).
    private func refreshFiles() {
        guard model.query != filesQuery else { return }
        let query = model.query
        filesQuery = query
        let needle = LauncherMatch.fold(LauncherFileRules.needle(query))
        files = needle.isEmpty ? [] : files.filter { LauncherMatch.fold($0.name).contains(needle) }
        fileSearch.search(query) { [weak self] found in
            guard let self, !self.finished, self.model.query == query, self.step == .objects else { return }
            self.files = found
            self.filesChanged = true
            self.render()
        }
    }

    /// Objet d'une ligne de la liste. O(1).
    private static func subject(of row: LauncherList.Row?) -> LauncherSubject? {
        switch row {
        case .app(let app, _): .app(app)
        case .target(let target): .target(target)
        case .file(let file): .file(file)
        case .phrase(let action, _), .alias(_, let action, _): action.subject
        case .project(let project): .project(project.name)
        case .action(_, let action, _, _): action.subject
        case .web(let row): row.url.map(LauncherSubject.url)
        case .rule, .openItem, .calc, .workflowKeyword, .workflowItem, .history, .header, nil: nil
        }
    }

    /// ⌘C : chemin d'un fichier ou d'une application, titre d'une fenêtre ou d'une cible (SPEC-077).
    private func copySelection() {
        let text: String? = switch launcherList.row(for: launcherSelection) {
        case .app(let app, _): app.path
        case .file(let file): file.path
        case .target(let target): target.subtitle.isEmpty ? target.title : "\(target.title) - \(target.subtitle)"
        case .phrase(_, let title), .alias(_, _, let title): title
        case .project(let project): project.name
        case .action(_, _, let title, _): title
        case .openItem(let item): item.url ?? item.title
        case .calc(let calc): calc.text
        case .workflowKeyword(let entry): entry.keyword
        case .workflowItem(_, let item, _): item.copyText ?? (item.arg.isEmpty ? item.title : item.arg.joined(separator: "\n"))
        case .web(let row): row.url?.absoluteString
        case .history(let query): query
        case .rule, .header, nil: nil
        }
        guard let text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedRowID = launcherSelection
    }

    private var selectedLauncherRow: Int? { launcherList.rows.firstIndex { $0.id == launcherSelection && $0.id != nil } }

    /// Clic sur une ligne : action immédiate, sans attendre un éventuel double Retour.
    private func activateSelection(immediate: Bool) {
        switch launcherList.row(for: launcherSelection) {
        case .app(let app, _): finishLaunching(app)
        case .target(let target): finishActivating(target, target.source == .app ? .click : (target.actions.first ?? .focus))
        case .file(let file): finishAction(LauncherAction(subject: .file(file), verb: .open, destination: nil))
        case .phrase(let action, _), .alias(_, let action, _): finishAction(action)
        case .project(let project): finishAction(LauncherAction(subject: .project(project.name), verb: .reopenProject, destination: nil))
        case .action(let key, let action, _, _): if key == "undo-batch" { finishUndo() } else { finishAction(action) }
        case .rule(let suggestion, let choice): finishRule(suggestion, choice)
        case .openItem(let item): finishOpenItem(item)
        case .calc(let calc): finishCalc(calc)
        case .workflowKeyword, .workflowItem: _ = confirmWorkflow(modifiers: 0)
        case .web, .history: _ = confirmWeb()
        case .header, nil: break
        }
    }

    // MARK: - Verbes et destinations (SPEC-074)

    private func enterVerbs(_ subject: LauncherSubject) {
        step = .verbs(subject)
        stepQuery = ""
        stepTiling = if case .target(let target) = subject, target.kind == .window, let id = target.scope.windowId {
            launcher.tiling(WindowID(rawValue: id))
        } else { nil }
        model.highlight(targetID: { if case .target(let target) = subject { return target.id } else { return nil } }())
        refreshActions()
    }

    /// Objet des étapes verbe et destination.
    private var stepSubject: LauncherSubject? {
        switch step {
        case .objects, .batchVerbs, .batchDestinations: nil
        case .verbs(let subject), .destinations(let subject, _): subject
        case .saving(let action, _): action.subject
        }
    }

    // MARK: - Garder une action (SPEC-079)

    /// Action de la ligne choisie à l'étape des objets : son action par défaut, ou celle de la phrase. O(1).
    private func objectAction() -> LauncherAction? {
        switch launcherList.row(for: launcherSelection) {
        case .app(let app, _): LauncherAction(subject: .app(app), verb: .open, destination: nil)
        case .file(let file): LauncherAction(subject: .file(file), verb: .open, destination: nil)
        case .target(let target): LauncherAction(subject: .target(target), verb: .focus, destination: nil)
        case .phrase(let action, _), .alias(_, let action, _): action
        case .project(let project): LauncherAction(subject: .project(project.name), verb: .reopenProject, destination: nil)
        case .action(_, let action, _, _): action
        case .web(let row): row.url.map { LauncherAction(subject: .url($0), verb: .open, destination: nil) }
        case .rule, .openItem, .calc, .workflowKeyword, .workflowItem, .history, .header, nil: nil
        }
    }

    /// Document ou onglet : la barre se ferme, sa fenêtre passe devant (SPEC-082).
    private func finishOpenItem(_ item: LauncherOpenItem) {
        guard !finished else { return }
        finished = true
        let query = model.query
        launcher.recordQuery(query)
        cleanup()
        launcher.recordVisit("open:\(item.kind.rawValue):\(item.bundleID):\(item.title)", query)
        onFinish?(launcher.activateOpenItem(item))
    }

    /// Choix d'une règle proposée : la barre se ferme sur le résultat (SPEC-081).
    private func finishRule(_ suggestion: RuleSuggestion, _ choice: RuleChoice) {
        guard !finished else { return }
        finished = true
        cleanup()
        onFinish?(launcher.ruleChoice(suggestion, choice))
    }

    /// Action composée aux étapes des verbes et des destinations. O(1).
    private func stepAction() -> LauncherAction? {
        guard let subject = stepSubject else { return nil }
        switch actionList.row(for: actionSelection) {
        case .verb(let verb): return verb.needsDestination ? nil : LauncherAction(subject: subject, verb: verb, destination: nil)
        case .destination(let verb, let destination): return LauncherAction(subject: subject, verb: verb, destination: destination)
        case .workflow, .header, nil: return nil
        }
    }

    private func enterSaving(_ action: LauncherAction) {
        step = .saving(action, LauncherAlias.from(action, stageName: launcher.stageName))
        stepQuery = ""
        savingCopied = false
        actionList = LauncherActionList()
        actionSelection = nil
    }

    /// Lignes de l'étape « Garder » : l'abréviation tapée, la commande, ou la raison du refus.
    private func savingRows(_ action: LauncherAction, _ alias: Result<LauncherAlias, LauncherAlias.Refusal>) -> [SlashSuggestion] {
        var rows = [SlashSuggestion(text: "Garder : \(LauncherPhrase.title(action))", kind: .header)]
        switch alias {
        case .failure(let refusal):
            rows.append(SlashSuggestion(text: "Cette action ne se garde pas", detail: refusal.message, kind: .result, icon: .symbol("xmark.circle")))
        case .success(let alias):
            let name = stepQuery.trimmingCharacters(in: .whitespaces)
            let replaced = launcher.aliases.alias(for: name).map { " · remplace « \($0.1.name) »" } ?? ""
            rows.append(SlashSuggestion(text: name.isEmpty ? "Abréviation…" : "Abréviation « \(name) »",
                                        detail: LauncherAlias.isValidName(name) ? "Retour enregistre\(replaced)" : "1 à 12 caractères, sans espace",
                                        kind: .result, icon: .symbol("character.cursor.ibeam")))
            rows.append(SlashSuggestion(text: alias.command, detail: savingCopied ? "Copiée dans le presse-papiers" : "⌘C copie la commande",
                                        kind: .result, icon: .symbol("terminal")))
        }
        return rows
    }

    private func confirmSaving(_ alias: LauncherAlias) {
        let name = stepQuery.trimmingCharacters(in: .whitespaces)
        guard LauncherAlias.isValidName(name) else { return }
        _ = launcher.saveAlias(alias, name)
        finish(TargetActionResult(changed: true, message: "launcher alias saved: \(LauncherMatch.fold(name))"))
    }

    private func enterDestinations(_ subject: LauncherSubject, _ verb: LauncherVerb) {
        step = .destinations(subject, verb)
        stepQuery = ""
        refreshActions()
    }

    /// Échap ou effacement dans un champ vide : une étape en arrière.
    private func stepBack() {
        switch step {
        case .objects: break
        case .verbs:
            step = .objects
            stepQuery = ""
            launcherQuery = nil
        case .destinations(let subject, _):
            enterVerbs(subject)
        case .saving, .batchVerbs:
            step = .objects
            stepQuery = ""
            launcherQuery = nil
        case .batchDestinations:
            enterBatch()
        }
    }

    // MARK: - Sélection multiple (SPEC-091)

    private func enterBatch() {
        step = .batchVerbs
        stepQuery = ""
        refreshActions()
    }

    /// Le lot part au contrôleur après la fermeture : une action par objet (FR-005).
    private func finishBatch(_ verb: LauncherVerb, _ destination: LauncherDestination?) {
        guard !finished else { return }
        finished = true
        launcher.recordQuery(model.query)
        let actions = selection.actions(verb, destination: destination)
        cleanup()
        onFinish?(launcher.performBatch(actions))
    }

    /// « Annuler » de la barre vide pour un lot (FR-006).
    private func finishUndo() {
        guard !finished else { return }
        finished = true
        cleanup()
        onFinish?(launcher.undo())
    }

    private func refreshActions() {
        switch step {
        case .objects: return
        case .verbs(let subject):
            actionList = .verbs(for: subject, query: stepQuery, destinations: launcher.destinations, newStageHome: launcher.newStageHome,
                                tiling: stepTiling)
            if case .file(let file) = subject {
                actionList.appendWorkflows(launcher.workflowTriggers.filter { AlfredWorkflowIndex.accepts($0, path: file.path) }, query: stepQuery)
            }
        case .destinations(let subject, let verb):
            actionList = .destinations(for: subject, verb: verb, query: stepQuery, destinations: launcher.destinations,
                                       newStageHome: launcher.newStageHome)
        case .saving:
            return
        case .batchVerbs:
            actionList = .batch(selection, query: stepQuery)
        case .batchDestinations:
            let title = "\(selection.count) choisi\(selection.count > 1 ? "s" : "")"
            actionList = .destinations(for: .project(title), verb: LauncherActionList.batchDestinationVerb(selection), query: stepQuery,
                                       destinations: launcher.destinations, newStageHome: launcher.newStageHome)
        }
        actionSelection = actionList.best
    }

    private func handleStep(_ input: SearchKeyInput) {
        if case .saving(_, let alias) = step {
            switch input.kind {
            case .escape: stepBack()
            case .delete: if stepQuery.isEmpty { stepBack() }
            case .confirm(_, _, _, _, let isRepeat):
                guard !isRepeat, case .success(let alias) = alias else { return }
                confirmSaving(alias)
                return
            case .copy:
                guard case .success(let alias) = alias else { break }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(alias.command, forType: .string)
                savingCopied = true
            default: break
            }
            render()
            return
        }
        switch input.kind {
        case .save:
            if let action = stepAction() { enterSaving(action) }
        case .escape:
            stepBack()
        case .delete:
            if stepQuery.isEmpty { stepBack() }
        case .pick(let rank):
            pick(rank)
            return
        case .next where input.navigationSource == .tab, .actions:
            // Tab ou → sur un verbe qui demande une destination : la troisième étape.
            if case .verb(let verb)? = actionList.row(for: actionSelection), verb.needsDestination, case .verbs(let subject) = step {
                enterDestinations(subject, verb)
            } else if case .verb(.sendTo)? = actionList.row(for: actionSelection), step == .batchVerbs {
                step = .batchDestinations
                stepQuery = ""
                refreshActions()
            }
        case .next:
            actionSelection = actionList.neighbour(of: actionSelection, step: 1)
        case .previous:
            actionSelection = actionList.neighbour(of: actionSelection, step: -1)
        case .confirm(_, _, _, _, let isRepeat):
            guard !isRepeat else { return }
            confirmStep()
            return
        case .text, .labelCharacter, .ignored, .copy, .preview, .showRules, .selectToggle, .selectAddNext, .selectRemoveLast,
             .selectionVerbs, .selectClear, .move, .cycleView:
            break
        }
        render()
    }

    // MARK: - Aperçu actif (SPEC-078)

    /// Destination de la ligne choisie, si elle se prête à l'aperçu. O(1).
    private var desiredPreview: LauncherPreviewRequest? {
        guard let subject = stepSubject, case .destination(let verb, let destination)? = actionList.row(for: actionSelection) else { return nil }
        return LauncherPreviewRequest.of(LauncherAction(subject: subject, verb: verb, destination: destination))
    }

    /// La ligne se pose 150 ms sur une destination : l'aperçu s'y pose. Elle la quitte : l'aperçu
    /// précédent est défait tout de suite. Rappelée à chaque rendu ; sans effet si rien ne change.
    private func schedulePreview() {
        let desired = desiredPreview
        guard desired != pendingPreview else { return }
        pendingPreview = desired
        previewWork?.cancel()
        previewWork = nil
        guard let desired else {
            ghost = nil
            if sentPreview != nil {
                sentPreview = nil
                launcher.preview(nil) { _ in }
            }
            return
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.finished, self.pendingPreview == desired else { return }
                self.ghost = nil
                self.sentPreview = desired
                self.launcher.preview(desired) { [weak self] ghost in
                    guard let self, !self.finished, self.sentPreview == desired else { return }
                    self.ghost = ghost
                    self.render()
                }
            }
        }
        previewWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    // MARK: - Touches du lanceur (SPEC-075)

    /// Une seule touche tenue choisit la variante ; deux à la fois, aucune. O(1).
    private static func modifier(command: Bool, option: Bool, control: Bool) -> LauncherModifier? {
        switch (command, option, control) {
        case (true, false, false): .command
        case (false, true, false): .option
        case (false, false, true): .control
        default: nil
        }
    }

    private func modifiersChanged(_ flags: NSEvent.ModifierFlags) {
        let held = flags.contains(.shift) ? nil : Self.modifier(command: flags.contains(.command), option: flags.contains(.option),
                                                              control: flags.contains(.control))
        let shift = flags.intersection([.command, .option, .control, .shift]) == .shift
        guard held != heldModifier || shift != heldShift else { return }
        heldModifier = held
        heldShift = shift
        render()
    }

    /// Variante de la ligne choisie à l'étape des objets, hors mode commande. O(1).
    private func currentVariant(_ modifier: LauncherModifier) -> LauncherVariant? {
        guard step == .objects, commandModel == nil else { return nil }
        let subject: LauncherSubject
        switch launcherList.row(for: launcherSelection) {
        case .app(let app, _): subject = .app(app)
        case .target(let target): subject = .target(target)
        case .file(let file): subject = .file(file)
        case .web(let row):
            guard let url = row.url else { return nil }
            subject = .url(url)
        case .phrase, .alias, .project, .action, .rule, .openItem, .calc, .workflowKeyword, .workflowItem, .history, .header, nil: return nil
        }
        return LauncherVariant.of(subject, modifier: modifier, query: model.query,
                                  newStageHome: launcher.newStageHome, activeStage: launcher.activeStage)
    }

    private func finishVariant(_ variant: LauncherVariant) {
        switch variant.effect {
        case .action(let action):
            finishAction(action)
        case .webSearch(let text):
            guard !finished else { return }
            finished = true
            launcher.recordQuery(model.query)
            cleanup()
            onFinish?(launcher.webSearch(text))
        }
    }

    /// ⌘ + chiffre : action par défaut de la ligne de ce rang parmi celles montrées. O(1).
    private func pick(_ rank: Int) {
        guard rank >= 1, rank <= pickRows.count else { return }
        let index = pickRows[rank - 1]
        if step == .objects {
            guard commandModel == nil, index < launcherList.rows.count else { return }
            launcherSelection = launcherList.rows[index].id
            syncHighlight()
            activateSelection(immediate: true)
        } else {
            guard index < actionList.rows.count else { return }
            actionSelection = actionList.rows[index].id
            confirmStep()
        }
    }

    private func confirmStep() {
        if step == .batchVerbs || step == .batchDestinations {
            switch actionList.row(for: actionSelection) {
            case .verb(.sendTo):
                step = .batchDestinations
                stepQuery = ""
                refreshActions()
                render()
            case .verb(let verb): finishBatch(verb, nil)
            case .destination(_, let destination): finishBatch(.sendTo, destination)
            case .workflow, .header, nil: break
            }
            return
        }
        let subject: LauncherSubject
        switch step {
        case .objects, .saving, .batchVerbs, .batchDestinations: return
        case .verbs(let current): subject = current
        case .destinations(let current, _): subject = current
        }
        switch actionList.row(for: actionSelection) {
        case .verb(let verb):
            if verb.needsDestination {
                enterDestinations(subject, verb)
                render()
            } else {
                finishAction(LauncherAction(subject: subject, verb: verb, destination: nil))
            }
        case .destination(let verb, let destination):
            finishAction(LauncherAction(subject: subject, verb: verb, destination: destination))
        case .workflow(let entry):
            // Action sur fichier d'un workflow (SPEC-089 FR-003) : le chemin en argument.
            if case .file(let file) = subject { finishWorkflow(entry, arg: [file.path], variables: [:], modifiers: 0, rankingKey: nil) }
        case .header, nil:
            break
        }
    }

    /// Verbes d'une cible déjà connus du mode recherche : exécutés comme avant (clics, aller à).
    /// Les autres passent au lanceur, après la fermeture de la barre.
    private func finishAction(_ action: LauncherAction) {
        if action.position == nil, case .target(let target) = action.subject, let verb = Self.searchVerb(action.verb, for: target) {
            finishActivating(target, verb)
            return
        }
        guard !finished else { return }
        finished = true
        let query = model.query
        launcher.recordQuery(query)
        // Retour sur la destination de l'aperçu : la disposition reste ; sur une autre, elle est restaurée.
        if sentPreview != nil {
            launcher.endPreview(sentPreview == LauncherPreviewRequest.of(action))
            sentPreview = nil
        }
        cleanup()
        launcher.recordVisit(action.subject.rankingKey, query)
        onFinish?(launcher.perform(action))
    }

    private static func searchVerb(_ verb: LauncherVerb, for target: RoadieTarget) -> TargetActionVerb? {
        switch verb {
        case .click: .click
        case .doubleClick: .doubleClick
        case .rightClick: .rightClick
        case .commandClick: .commandClick
        case .focus, .show: target.actions.first ?? .focus
        default: nil
        }
    }

    private func finishLaunching(_ app: LauncherApp) {
        guard !finished else { return }
        finished = true
        let query = model.query
        launcher.recordQuery(query)
        cleanup()
        launcher.recordVisit(app.rankingKey, query)
        onFinish?(launcher.launch(app))
    }

    /// Premier `/` d'une requête vide : la boîte de commandes prend la main. Le contexte (stages,
    /// bookmarks) est lu une fois, à la bascule.
    private func enterCommandMode() {
        model.cancelPendingReturn()
        let context = commands.context()
        commandModel = SlashCommandModel(history: commands.loadHistory()) {
            SlashCommandCatalog.suggestions(for: $0, context: context)
        }
    }

    private func handleCommand(_ input: SearchKeyInput) {
        guard var command = commandModel else { return }
        let effect = command.handle(input)
        commandModel = command
        switch effect {
        case .update:
            render()
        case .close:
            cancel()
        case .leave:
            // Le `/` est effacé : la requête de recherche revient à vide.
            commandModel = nil
            model.deleteBackward()
            render()
        case .submit(let line):
            execute(line)
        }
    }

    /// Retour en mode commande. Succès, action différée et réglages ferment la boîte ; un résultat
    /// d'information ou une erreur s'affichent dans la boîte, qui reste ouverte.
    private func execute(_ line: String) {
        switch commands.execute(line) {
        case .done:
            finish(TargetActionResult(changed: true, message: "command_box_done"))
        case .deferred(let argv):
            let runDeferred = runDeferred
            finish(TargetActionResult(changed: false, message: "command_box_deferred")) { runDeferred(argv) }
        case .openSettings(let category):
            let openSettings = openSettings
            finish(TargetActionResult(changed: false, message: "command_box_settings")) { openSettings(category) }
        case .info(let lines):
            commandModel?.setMessage(.info(lines))
            render()
        case .failed(let error):
            let hint = error.suggestion.map { " Vouliez-vous dire « \($0) » ?" } ?? ""
            commandModel?.setMessage(.error(error.message + hint, usage: error.usage))
            render()
        }
    }

    private func tick() {
        guard !finished else { return }
        if let target = model.highlighted, let verb = model.pendingReturn(at: Date()) {
            finishActivating(target, verb)
            return
        }
        if Date().timeIntervalSince(lastInputAt) >= Self.idleTimeout {
            finish(TargetActionResult(changed: false, message: "target_search_timeout", error: "timeout"))
        }
    }

    private func render() {
        schedulePreview()
        if case .saving(let action, let alias) = step {
            let rows = savingRows(action, alias)
            show(badges: [], bar: TargetSearchBar(query: stepQuery, matchCount: 0, properties: nil, isLoading: false,
                                                  suggestions: rows, selectedSuggestion: rows.count > 1 ? 1 : nil, richRows: true))
            return
        }
        if step != .objects {
            let subjectID = model.highlighted?.id
            let badges: [TargetOverlayBadge] = model.matches.compactMap { target in
                guard target.id == subjectID, let frame = target.frame?.cgRect else { return nil }
                return TargetOverlayBadge(label: target.label, title: target.title, kind: target.kind, isActive: target.isActive,
                                          frame: RoadieScreenCoordinate.axRectToNS(frame), isHighlighted: true, isFramed: true, isSearchResult: true)
            }
            let batch = step == .batchVerbs
            show(badges: badges, bar: TargetSearchBar(
                query: stepQuery, matchCount: actionList.rows.filter { $0.id != nil }.count, properties: nil, isLoading: false,
                suggestions: actionList.rows.map { row in
                    // Lot : chaque verbe avec le nombre d'objets qu'il concerne (SPEC-091 FR-004).
                    guard batch, case .verb(let verb) = row else { return Self.suggestion(row, app: stepSubject?.appName ?? "") }
                    var line = Self.suggestion(row, app: "")
                    line.text = LauncherSelection.title(verb, count: selection.applicable(verb).count)
                    return line
                },
                selectedSuggestion: actionList.rows.firstIndex { $0.id == actionSelection && $0.id != nil },
                richRows: true))
            return
        }
        if let command = commandModel {
            // Mode commande : la saisie, la liste et le message, sans aucune cible.
            show(badges: [], bar: TargetSearchBar(
                query: model.query,
                matchCount: 0,
                properties: nil,
                isLoading: false,
                commandInput: command.input,
                suggestions: command.suggestions,
                selectedSuggestion: command.selected,
                message: command.message
            ))
            return
        }
        refreshLauncher()
        // Icône d'une fenêtre : celle de son application, retrouvée par son nom. O(a).
        let appPaths = Dictionary(launcher.apps.map { ($0.name, $0.path) }, uniquingKeysWith: { first, _ in first })
        var suggestions = launcherList.rows.map { Self.suggestion($0, appPaths: appPaths) }
        // Touche tenue : la ligne choisie annonce ce que Retour fera (SPEC-075).
        if let modifier = heldModifier, let index = selectedLauncherRow, let variant = currentVariant(modifier) {
            suggestions[index].detail = variant.title
        }
        // Workflow : le sous-titre du modificateur tenu (SPEC-088 FR-006).
        if heldModifier != nil || heldShift, let index = selectedLauncherRow,
           case .workflowItem(_, let item, _)? = launcherList.row(for: launcherSelection) {
            let bits = Self.alfredModifiers(command: heldModifier == .command, option: heldModifier == .option,
                                            control: heldModifier == .control, shift: heldShift)
            if let subtitle = item.mods[bits]?.subtitle { suggestions[index].detail = subtitle }
        }
        if let copied = copiedRowID, let index = launcherList.rows.firstIndex(where: { $0.id == copied }) {
            suggestions[index].detail = "Copié dans le presse-papiers"
        }
        // Sélection multiple : « ✓ » devant les lignes choisies (SPEC-091 FR-002).
        if !selection.isEmpty {
            for (index, row) in launcherList.rows.enumerated() {
                if let subject = Self.subject(of: row), selection.contains(subject) { suggestions[index].text = "✓ " + suggestions[index].text }
            }
        }
        // Présentation en grille (session 099) : images montrées par leur contenu, noms sous la tuile ou en pied.
        var viewGrid: SearchGrid?
        if launcher.workflowGrid == nil, let columns = viewMode.columns, let source = viewSource {
            for index in suggestions.indices {
                if case .file(let path)? = suggestions[index].icon, AlfredGridView.isImage(path) { suggestions[index].icon = .image(path) }
            }
            let footer = selectedLauncherRow.map { suggestions[$0].text } ?? ""
            viewGrid = SearchGrid(columns: columns, showTitles: !source.namesInFooter, showSubtitles: false,
                                  footer: source.namesInFooter ? footer : nil)
        }
        var bar = TargetSearchBar(
            query: model.query, matchCount: model.matches.count, properties: model.properties, isLoading: isLoading,
            suggestions: suggestions, selectedSuggestion: selectedLauncherRow,
            richRows: true)
        bar.grid = viewGrid
        // Chip de la présentation (session 099) : là où elle se choisit.
        if viewSource != nil { bar.viewChip = "\(viewMode.symbol) \(viewMode.title)" }
        // Chip (SPEC-081) : une règle attend pendant une recherche ; ⌘R la montre.
        if launcher.pendingRules > 0, !model.query.isEmpty { bar.chip = "💡 \(launcher.pendingRules)" }
        if let grid = launcher.workflowGrid, grid.loadingText == nil {
            // Grille (SPEC-092 FR-003) : titre et sous-titre sur la tuile, ou en pied pour la tuile choisie.
            var footer: [String] = []
            if case .workflowItem(_, let item, _)? = launcherList.row(for: launcherSelection) {
                if grid.titlesInFooter, grid.showTitles, !item.title.isEmpty { footer.append(item.title) }
                if grid.subtitlesInFooter, grid.showSubtitles, !item.subtitle.isEmpty { footer.append(item.subtitle) }
            }
            bar.grid = SearchGrid(columns: grid.columns, showTitles: grid.showTitles && !grid.titlesInFooter,
                                  showSubtitles: grid.showSubtitles && !grid.subtitlesInFooter,
                                  footer: grid.titlesInFooter || grid.subtitlesInFooter ? footer.joined(separator: " · ") : nil)
        }
        if !selection.isEmpty {
            let chosen = "\(selection.count) choisi\(selection.count > 1 ? "s" : "")"
            bar.chip = bar.chip.map { "\($0) · \(chosen)" } ?? chosen
        }
        // Barre vide : aucune lettre ; sinon les cibles montrées en reçoivent une (SPEC-084).
        show(badges: [], bar: bar, letterTargets: !model.query.isEmpty)
    }

    /// Ligne des étapes verbe et destination.
    private static func suggestion(_ row: LauncherActionList.Row, app: String) -> SlashSuggestion {
        switch row {
        case .header(let title):
            return SlashSuggestion(text: title, kind: .header)
        case .workflow(let entry):
            return SlashSuggestion(text: "Workflow : \(entry.title)", detail: entry.workflowName, kind: .result, icon: workflowIcon(nil, entry: entry))
        case .verb(let verb):
            return SlashSuggestion(text: verb.title(app: app), detail: verb.needsDestination ? "Tab ou Retour : choisir" : "",
                                   kind: .result, icon: .symbol(verb.needsDestination ? "arrow.right.circle" : "play.circle"))
        case .destination(let verb, let destination):
            let symbol = switch destination.kind {
            case .stage: "square.stack.3d.up"
            case .desktop: "rectangle.on.rectangle"
            case .display: "display"
            case .newStage: "plus.square.on.square"
            }
            return SlashSuggestion(text: "\(verb.destinationPrefix) \(destination.title)", detail: destination.detail,
                                   kind: .result, icon: .symbol(symbol))
        }
    }

    /// Ligne du lanceur dessinée par la barre : en-tête, application avec son icône, ou cible.
    private static func suggestion(_ row: LauncherList.Row, appPaths: [String: String]) -> SlashSuggestion {
        switch row {
        case .header(let title):
            return SlashSuggestion(text: title, kind: .header)
        case .app(let app, let detail):
            return SlashSuggestion(text: app.name, detail: detail, kind: .result, icon: .file(app.path))
        case .target(let target):
            let symbol = switch target.kind {
            case .window: "macwindow"
            case .stage: "square.stack.3d.up"
            case .desktop: "rectangle.on.rectangle"
            case .display: "display"
            case .bookmark: "bookmark"
            case .appElement, .gridCell: "cursorarrow.rays"
            }
            // Fenêtre : sa vignette réelle si Roadie l'a capturée, sinon l'icône de son application (SPEC-076).
            let icon: SlashSuggestion.Icon = if target.kind == .window, let id = target.scope.windowId {
                .window(id, app: appPaths[target.title])
            } else { .symbol(symbol) }
            return SlashSuggestion(text: target.title, detail: target.subtitle, kind: .result, icon: icon)
        case .file(let file):
            return SlashSuggestion(text: file.name, detail: file.location, kind: .result, icon: .file(file.path))
        case .phrase(let action, let title):
            return SlashSuggestion(text: title, detail: "Retour fait l'action · ⌘S la garde", kind: .result, icon: icon(of: action, appPaths: appPaths))
        case .alias(let name, let action, let title):
            return SlashSuggestion(text: title, detail: "Abréviation « \(name) »", kind: .result, icon: icon(of: action, appPaths: appPaths))
        case .project(let project):
            return SlashSuggestion(text: project.name, detail: "Projet · \(project.windows.count) fenêtre\(project.windows.count > 1 ? "s" : "")",
                                   kind: .result, icon: .symbol("square.stack.3d.down.right"))
        case .action(_, let action, let title, let detail):
            return SlashSuggestion(text: title, detail: detail, kind: .result, icon: icon(of: action, appPaths: appPaths))
        case .openItem(let item):
            let icon: SlashSuggestion.Icon = item.windowID.map { .window($0.rawValue, app: appPaths[item.appName]) }
                ?? appPaths[item.appName].map(SlashSuggestion.Icon.file) ?? .symbol(item.kind == .tab ? "globe" : "doc")
            return SlashSuggestion(text: item.title, detail: item.detail, kind: .result, icon: icon)
        case .web(let row):
            let (detail, symbol): (String, String) = switch row.kind {
            case .address: ("Retour ouvre · Tab : ouvrir dans une stage", "globe")
            case .search(let url): (url.host ?? "", "magnifyingglass")
            case .hint(let search): ("Tab ou Retour : « \(search.keyword) »", "keyboard")
            }
            return SlashSuggestion(text: row.title, detail: detail, kind: .result, icon: .symbol(symbol))
        case .history(let query):
            return SlashSuggestion(text: query, detail: "Recherche récente", kind: .result, icon: .symbol("clock.arrow.circlepath"))
        case .workflowKeyword(let entry):
            return SlashSuggestion(text: entry.title, detail: entry.subtitle.isEmpty ? "\(entry.keyword) · \(entry.workflowName)" : entry.subtitle,
                                   kind: .result, icon: workflowIcon(nil, entry: entry))
        case .workflowItem(let entry, let item, _):
            return SlashSuggestion(text: item.title, detail: item.subtitle, kind: .result, icon: workflowIcon(item.icon, entry: entry))
        case .calc(let calc):
            return SlashSuggestion(text: calc.text, detail: "\(calc.expression) · Retour copie", kind: .result, icon: .symbol("equal.square"))
        case .rule(let suggestion, let choice):
            let text = switch choice {
            case .create: "Créer la règle : \(suggestion.appName) toujours dans \(suggestion.stageTitle)"
            case .later: "Plus tard"
            case .never: "Jamais pour \(suggestion.appName) dans \(suggestion.stageTitle)"
            }
            let detail = choice == .create ? "\(suggestion.count) déplacements cette semaine" : choice == .later ? "Reproposer demain" : "Ne plus proposer"
            return SlashSuggestion(text: text, detail: detail, kind: .result,
                                   icon: .symbol(choice == .create ? "lightbulb" : choice == .later ? "clock" : "nosign"))
        }
    }

    /// Icône de l'objet d'une phrase ou d'une abréviation : application, fichier, ou symbole. O(1).
    private static func icon(of action: LauncherAction, appPaths: [String: String]) -> SlashSuggestion.Icon {
        switch action.subject {
        case .app(let app): .file(app.path)
        case .file(let file): .file(file.path)
        case .target(let target): appPaths[target.title].map(SlashSuggestion.Icon.file) ?? .symbol("macwindow")
        case .project: .symbol("square.stack.3d.down.right")
        case .url: .symbol("globe")
        }
    }

    /// `letterTargets` : étape des objets avec une saisie ; les lignes de cible montrées reçoivent une
    /// lettre et leur fenêtre le même badge à l'écran. O(v), v lignes montrées.
    private func show(badges: [TargetOverlayBadge], bar: TargetSearchBar, letterTargets: Bool = false) {
        var bar = bar
        var badges = badges
        bar.usesNativeInput = true
        bar.placement = placement
        let barWindow = (launcher.barScreenFrame ?? pointerScreen).flatMap { screen in windows.first { $0.frame == screen } } ?? windows.first
        searchBarLayout = barWindow.map { bar.layout(in: $0.frame, style: style) }
        // ⌘1 à ⌘9 sur les lignes montrées ; le rang sert au dessin et à la touche (SPEC-075).
        pickRows = []
        if bar.richRows, let layout = searchBarLayout {
            for index in layout.visibleRange(count: bar.suggestions.count, selected: bar.selectedSuggestion)
            where bar.suggestions[index].kind != .header && pickRows.count < 9 {
                pickRows.append(index)
                bar.suggestions[index].shortcut = "\(launcher.pickModifier.symbol)\(pickRows.count)"
            }
        }
        letterRows = [:]
        if letterTargets, let layout = searchBarLayout {
            let highlightedID = model.highlighted?.id
            let visible = layout.visibleRange(count: bar.suggestions.count, selected: bar.selectedSuggestion)
            for (letter, index, target) in launcherList.letterRows(visible: visible, letters: letters) {
                letterRows[letter] = index
                bar.suggestions[index].letter = "⇧" + letter.uppercased()
                guard let frame = target.frame?.cgRect, launcher.isOnScreen(target) else { continue }
                badges.append(TargetOverlayBadge(label: letter.uppercased(), title: target.title, kind: target.kind,
                                                 isActive: target.isActive, frame: RoadieScreenCoordinate.axRectToNS(frame),
                                                 isHighlighted: target.id == highlightedID, isFramed: true, isSearchResult: true))
            }
        }
        inputPanel?.labelLetters = Set(letterRows.keys)
        inputPanel?.pickModifier = launcher.pickModifier.flags
        inputPanel?.gridColumns = step == .objects ? gridColumns : nil
        shownBar = bar
        let selectable = Self.subject(of: launcherList.row(for: launcherSelection)).flatMap(LauncherSelection.key) != nil
        inputPanel?.selectionKeys = step == .objects ? SelectionKeys(hasSelection: !selection.isEmpty, rowSelectable: selectable) : SelectionKeys()
        inputPanel?.field.placeholderString = switch step {
        case .objects: launcher.workflowGrid.map { "Filtrer : \($0.entry.workflowName)" } ?? "Rechercher ou saisir /commande"
        case .verbs: "Verbe ou destination…"
        case .destinations, .batchDestinations: "Stage, bureau ou écran…"
        case .saving: "Abréviation (12 caractères au plus)…"
        case .batchVerbs: "Verbe pour la sélection…"
        }
        if let layout = searchBarLayout {
            let text = step != .objects ? stepQuery : commandModel.map { "/" + $0.input } ?? model.query
            inputPanel?.update(text: text,
                frame: SearchBarRenderer.inputFrame(bar, bar: layout.bar, style: style),
                font: SearchBarRenderer.font(family: style.searchFontFamily, size: style.searchTextFontSize),
                color: LauncherTheme.color(style.theme.searchText.color))
        }
        for window in windows {
            window.update(badges: badges, searchBar: window === barWindow ? bar : nil, ghost: ghost)
        }
    }

    /// `then` : action de la boîte de commandes, lancée après la fin de la session (research R2).
    private func finish(_ result: TargetActionResult, then action: (@MainActor @Sendable () -> Void)? = nil) {
        guard !finished else { return }
        finished = true
        CommandBoxFollowUp.finish(cleanup: cleanup, notify: { onFinish?(result) }, then: action)
    }

    private func finishActivating(_ target: RoadieTarget, _ verb: TargetActionVerb) {
        guard !finished else { return }
        finished = true
        let query = model.query
        launcher.recordQuery(query)
        cleanup()
        launcher.recordVisit(LauncherList.rankingKey(target), query)
        onFinish?(activate(target, verb))
    }

    private func cleanup() {
        fileSearch.cancel()
        pathListing.cancel()
        workflowRuns.values.forEach { $0.cancel() }
        workflowRuns = [:]
        workflowPending.values.forEach { $0.cancel() }
        workflowPending = [:]
        previewWork?.cancel()
        previewWork = nil
        pendingPreview = nil
        if sentPreview != nil {
            sentPreview = nil
            launcher.preview(nil) { _ in }
        }
        model.cancelPendingReturn()
        searchBarLayout = nil
        timer?.invalidate()
        timer = nil
        inputPanel?.endEditing()
        inputPanel = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        eventTap = nil
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows = []
        NSApplication.shared.updateWindows()
    }
}

/// Fin d'une session suivie d'une action de la boîte de commandes (SPEC-023 R2) : nettoyer la session,
/// prévenir le contrôleur (qui remet son état à zéro), puis lancer l'action un tour de boucle plus tard.
/// Lancée plus tôt, une commande `grid` ou `targets` ouvrirait sa session avant cette remise à zéro,
/// qui effacerait alors la nouvelle session du contrôleur.
@MainActor
enum CommandBoxFollowUp {
    static func finish(cleanup: () -> Void, notify: () -> Void, then action: (@MainActor @Sendable () -> Void)?) {
        cleanup()
        notify()
        guard let action else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { action() } }
    }
}

/// Effet d'une touche de la boîte de commandes pour la session (SPEC-023 R3).
enum CommandBoxKeyEffect: Equatable {
    /// Saisie, liste ou message à redessiner.
    case update
    /// Retour : commande à exécuter, sans `/`.
    case submit(String)
    /// Échap : fermer sans action.
    case close
    /// `/` effacé : la main revient à la recherche.
    case leave
}

extension SlashCommandModel {
    /// Aiguillage pur d'une touche en mode commande : la recherche n'en voit aucune. Maj + lettre écrit
    /// une majuscule, Tab complète, Maj-Tab et Ctrl-P remontent la liste, Ctrl-N la descend, les
    /// flèches parcourent les suggestions (historique à vide/sans proposition), Retour accepte le
    /// choix explicite puis exécute sans attendre de second Retour.
    /// Complexité : celle de l'opération appelée, O(c + l) au plus.
    mutating func handle(_ input: SearchKeyInput) -> CommandBoxKeyEffect {
        switch input.kind {
        case .text(let value):
            type(value)
        case .labelCharacter(let value):
            type(value.uppercased())
        case .delete:
            deleteBackward()
            if !isActive { return .leave }
        case .next:
            switch input.navigationSource {
            case .arrow:
                if self.input.isEmpty || historyCursor != nil || suggestions.isEmpty { historyDown() }
                else { nextSuggestion() }
            case .control: nextSuggestion()
            case .tab, nil: complete()
            }
        case .previous:
            switch input.navigationSource {
            case .arrow:
                if self.input.isEmpty || historyCursor != nil || suggestions.isEmpty { historyUp() }
                else { previousSuggestion() }
            case .tab, .control, nil: previousSuggestion()
            }
        case .confirm(_, _, _, _, let isRepeat):
            if !isRepeat {
                acceptSelectedSuggestion()
                return .submit(submit())
            }
        case .escape:
            return .close
        case .ignored, .pick, .actions, .copy, .preview, .save, .showRules, .selectToggle, .selectAddNext, .selectRemoveLast,
             .selectionVerbs, .selectClear, .move, .cycleView:
            break
        }
        return .update
    }
}

/// Touches du mode recherche (SPEC-021) et de la boîte de commandes (SPEC-023). Le décodage lit le
/// caractère produit par la touche : sur AZERTY, Maj + `:` arrive comme texte `/`. Les combinaisons
/// Commande (sauf Cmd-Retour) passent à l'app ou au système. En recherche, une touche ignorée est
/// laissée à l'app active ; en mode commande, toute touche sans Commande est retenue (T027).
public struct SearchKeyInput: Sendable, Equatable {
    /// État de la saisie lu par le tap clavier (SPEC-023 T027, T030).
    public enum Mode: Sendable, Equatable {
        /// Recherche, requête vide : le `/` ouvre le mode commande.
        case emptySearch
        /// Recherche en cours : décodage de la SPEC-021 inchangé (FR-010), `/` ignoré.
        case search
        /// Mode commande : tout caractère imprimable est du texte.
        case command
    }

    public enum Kind: Sendable, Equatable {
        case text(String)
        case labelCharacter(String)
        case delete
        case escape
        case next
        case previous
        /// Option et Contrôle choisissent une variante du lanceur (SPEC-075).
        case confirm(shift: Bool, command: Bool, option: Bool = false, control: Bool = false, isRepeat: Bool)
        /// ⌘1 à ⌘9 : action par défaut de la ligne de ce rang parmi celles montrées (SPEC-075).
        case pick(Int)
        /// → en fin de saisie : verbes de la ligne choisie, comme Tab (SPEC-075).
        case actions
        /// ⌘C sans texte sélectionné : copier la ligne choisie ; ⌘Y : son aperçu (SPEC-077).
        case copy
        case preview
        /// ⌘S : garder l'action choisie en abréviation et en commande (SPEC-079).
        case save
        /// ⌘R : vider la saisie et montrer la règle proposée (SPEC-081).
        case showRules
        /// Sélection multiple (SPEC-091) : ⌥↑ ajoute ou retire, ⌥↓ ajoute et descend, ⌥← retire la
        /// dernière, ⌥→ verbes du lot, ⌥⌫ vide.
        case selectToggle, selectAddNext, selectRemoveLast, selectionVerbs, selectClear
        /// Grille d'un workflow (SPEC-092) : ← (-1) et → (+1).
        case move(Int)
        /// Touche des présentations (session 099) : liste → grille → grandes tuiles.
        case cycleView
        case ignored
    }

    /// Touche à l'origine de `.next` ou `.previous` : la boîte de commandes leur donne des rôles
    /// différents (compléter, historique, suggestion suivante).
    public enum NavigationSource: Sendable, Equatable {
        case tab
        case arrow
        case control
    }

    public let kind: Kind
    /// Renseignée pour `.next` et `.previous` uniquement.
    public let navigationSource: NavigationSource?
    /// Touche retenue par le tap, donc cachée à l'app active. Faux pour `.ignored`, sauf en mode
    /// commande sans Commande (flèche gauche, touche morte : retenues sans effet).
    public let swallowed: Bool

    init(event: CGEvent, mode: Mode) {
        let flags = event.flags
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
        self.init(
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            text: String(utf16CodeUnits: chars, count: length),
            shift: flags.contains(.maskShift),
            command: flags.contains(.maskCommand),
            control: flags.contains(.maskControl),
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            mode: mode
        )
    }

    public init(kind: Kind, navigationSource: NavigationSource? = nil, swallowed: Bool? = nil) {
        self.kind = kind
        self.navigationSource = navigationSource
        self.swallowed = swallowed ?? (kind != .ignored)
    }

    /// Décodage pur, testable, du mode recherche : code de touche, texte produit et modificateurs.
    public static func kind(keyCode: Int64, text: String, shift: Bool, command: Bool, control: Bool, isRepeat: Bool) -> Kind {
        SearchKeyInput(keyCode: keyCode, text: text, shift: shift, command: command, control: control, isRepeat: isRepeat).kind
    }

    /// Décodage pur du mode recherche (SPEC-021), avec la touche de navigation. O(1).
    public init(keyCode: Int64, text: String, shift: Bool, command: Bool, control: Bool, isRepeat: Bool) {
        self.init(keyCode: keyCode, text: text, shift: shift, command: command, control: control, isRepeat: isRepeat, mode: .search)
    }

    /// Décodage pur selon l'état de la saisie. O(t), t ≤ 8 caractères produits.
    public init(keyCode: Int64, text: String, shift: Bool, command: Bool, control: Bool, isRepeat: Bool, mode: Mode) {
        switch keyCode {
        case 53: self.init(kind: .escape); return
        case 51: self.init(kind: .delete); return
        case 36, 76: self.init(kind: .confirm(shift: shift, command: command, control: control, isRepeat: isRepeat)); return
        default: break
        }
        // Cmd-Tab, Cmd-Espace… restent au système.
        if command { self.init(kind: .ignored); return }
        switch keyCode {
        case 48: self.init(kind: shift ? .previous : .next, navigationSource: .tab); return
        case 125: self.init(kind: .next, navigationSource: .arrow); return
        case 126: self.init(kind: .previous, navigationSource: .arrow); return
        default: break
        }
        // Sans Commande : le mode commande retient aussi les touches sans effet.
        let commandMode = mode == .command
        if control {
            switch text.lowercased() {
            case "n", "\u{0E}": self.init(kind: .next, navigationSource: .control)
            case "p", "\u{10}": self.init(kind: .previous, navigationSource: .control)
            default: self.init(kind: .ignored, swallowed: commandMode)
            }
            return
        }
        if commandMode {
            // Caractère produit avec Maj ou Option (`#`, `@`, `{`…) ; touche morte en attente : texte vide.
            let printable = !text.isEmpty && text.allSatisfy(Self.isPrintable)
            self.init(kind: printable ? .text(text) : .ignored, swallowed: true)
            return
        }
        guard text.count == 1, let character = text.first else { self.init(kind: .ignored); return }
        if character.isLetter && shift { self.init(kind: .labelCharacter(String(character).lowercased())); return }
        // Liste de la SPEC-021 (FR-010) ; le `/` d'une requête vide ouvre le mode commande.
        if character.isLetter || character.isNumber || " *;?".contains(character) || (mode == .emptySearch && character == "/") {
            self.init(kind: .text(String(character)))
            return
        }
        self.init(kind: .ignored)
    }

    /// Ni caractère de contrôle, ni touche de fonction (zone privée U+F700…, flèches comprises).
    private static func isPrintable(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .privateUse, .unassigned: false
            default: true
            }
        }
    }
}

private struct KeyInput: Sendable {
    enum Kind: Sendable {
        case characters(String)
        case escape
        case delete
        case confirm
        case arrow(ArrowDirection)
        case other
    }

    enum ArrowDirection: Sendable {
        case left
        case right
        case up
        case down

        var targetGridDirection: TargetGridArrowDirection {
            switch self {
            case .left: return .left
            case .right: return .right
            case .up: return .up
            case .down: return .down
            }
        }
    }

    var kind: Kind
    var normalizedName: String

    init(event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == 53 {
            self.kind = .escape
            self.normalizedName = "escape"
            return
        }
        if keyCode == 51 {
            self.kind = .delete
            self.normalizedName = "backspace"
            return
        }
        if keyCode == 36 {
            self.kind = .confirm
            self.normalizedName = "return"
            return
        }
        if keyCode == 49 {
            self.kind = .confirm
            self.normalizedName = "space"
            return
        }
        if keyCode == 123 {
            self.kind = .arrow(.left)
            self.normalizedName = "arrow_left"
            return
        }
        if keyCode == 124 {
            self.kind = .arrow(.right)
            self.normalizedName = "arrow_right"
            return
        }
        if keyCode == 125 {
            self.kind = .arrow(.down)
            self.normalizedName = "arrow_down"
            return
        }
        if keyCode == 126 {
            self.kind = .arrow(.up)
            self.normalizedName = "arrow_up"
            return
        }
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
        let text = String(utf16CodeUnits: chars, count: length)
            .filter { $0.isLetter || $0.isNumber }
        self.kind = text.isEmpty ? .other : .characters(String(text))
        if let first = text.first {
            let flags = event.flags
            var parts: [String] = []
            if flags.contains(.maskCommand) { parts.append("command") }
            if flags.contains(.maskControl) { parts.append("control") }
            if flags.contains(.maskAlternate) { parts.append("alt") }
            if flags.contains(.maskShift) { parts.append("shift") }
            parts.append(String(first).lowercased())
            self.normalizedName = parts.joined(separator: "+")
        } else {
            self.normalizedName = "other"
        }
    }

    var isRoadieHandled: Bool {
        switch kind {
        case .characters, .escape, .delete, .confirm, .arrow:
            return true
        case .other:
            return false
        }
    }
}

private struct TargetOverlayBadge {
    var label: String
    var title: String
    var kind: TargetKind
    var isActive: Bool
    var frame: CGRect
    /// Correspondance mise en avant du mode recherche (vert).
    var isHighlighted = false
    /// Recherche avec des étiquettes d'une lettre : cadre fin autour de chaque résultat.
    var isFramed = false
    /// Résultat du mode recherche : étiquette sur fond vert.
    var isSearchResult = false

    static func badges(from state: TargetOverlayState) -> [TargetOverlayBadge] {
        state.report.targets.compactMap { target in
            guard let frame = target.frame?.cgRect else { return nil }
            return TargetOverlayBadge(
                label: target.label,
                title: target.title,
                kind: target.kind,
                isActive: target.isActive,
                frame: RoadieScreenCoordinate.axRectToNS(frame)
            )
        }
    }
}

@MainActor
private final class TargetOverlayWindow: NSPanel {
    private let overlay: TargetOverlayView
    /// Flou derrière la barre et la liste d'un thème translucide (session 101), sous la vue dessinée.
    private var blurViews: [NSVisualEffectView] = []

    init(frame: CGRect, badges: [TargetOverlayBadge], style: TargetOverlayStyle) {
        let content = TargetOverlayView(
            frame: CGRect(origin: .zero, size: frame.size),
            badges: badges,
            screenOrigin: frame.origin,
            style: style
        )
        overlay = content
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hasShadow = false
        let container = NSView(frame: CGRect(origin: .zero, size: frame.size))
        content.autoresizingMask = [.width, .height]
        container.addSubview(content)
        contentView = container
    }

    func updateStyle(_ style: TargetOverlayStyle) {
        overlay.updateStyle(style)
    }

    /// Mode recherche : nouvelles étiquettes et barre de saisie (nil = pas de barre sur cet écran).
    func update(badges: [TargetOverlayBadge], searchBar: TargetSearchBar?, ghost: LauncherGhost? = nil) {
        let view = overlay
        view.badges = badges
        view.searchBar = searchBar
        view.ghost = ghost
        view.needsDisplay = true
        updateBlur(searchBar)
    }

    /// O(2) : une vue de flou par surface (barre, liste), réutilisées d'un rendu à l'autre.
    private func updateBlur(_ searchBar: TargetSearchBar?) {
        let theme = overlay.currentStyle.theme
        guard let container = contentView, let searchBar, let appearance = theme.blurAppearance else {
            blurViews.forEach { $0.isHidden = true }
            return
        }
        let layout = searchBar.layout(in: overlay.bounds, style: overlay.currentStyle)
        let rects = [layout.bar] + (layout.panel.map { [$0] } ?? [])
        while blurViews.count < rects.count {
            let blur = NSVisualEffectView()
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.masksToBounds = true
            container.addSubview(blur, positioned: .below, relativeTo: overlay)
            blurViews.append(blur)
        }
        for (index, blur) in blurViews.enumerated() {
            guard index < rects.count else { blur.isHidden = true; continue }
            blur.isHidden = false
            blur.frame = rects[index]
            blur.appearance = NSAppearance(named: appearance)
            blur.material = appearance == .aqua ? .popover : .hudWindow
            blur.layer?.cornerRadius = min(CGFloat(theme.roundness), rects[index].height / 2)
        }
    }
}

private final class TargetOverlayView: NSView {
    fileprivate var badges: [TargetOverlayBadge]
    fileprivate var searchBar: TargetSearchBar?
    /// Place de la fenêtre à venir pendant l'aperçu actif (SPEC-078), en coordonnées d'écran.
    fileprivate var ghost: LauncherGhost?
    private let screenOrigin: CGPoint
    private var style: TargetOverlayStyle
    var currentStyle: TargetOverlayStyle { style }
    // Réutilisés pour mesurer et dessiner chaque badge : aucune allocation de police dans la boucle.
    private var textAttributes: [NSAttributedString.Key: Any]

    private static func badgeTextAttributes(_ style: TargetOverlayStyle) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedSystemFont(ofSize: style.labelFontSize, weight: .semibold),
         .foregroundColor: NSColor.white]
    }

    private struct BadgePlacement {
        var badge: CGRect
        var target: CGRect
    }

    init(frame: CGRect, badges: [TargetOverlayBadge], screenOrigin: CGPoint, style: TargetOverlayStyle) {
        self.badges = badges
        self.screenOrigin = screenOrigin
        self.style = style
        self.textAttributes = Self.badgeTextAttributes(style)
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    func updateStyle(_ style: TargetOverlayStyle) {
        if self.style.labelFontSize != style.labelFontSize {
            textAttributes = Self.badgeTextAttributes(style)
        }
        self.style = style
        needsDisplay = true
    }

    override var isOpaque: Bool { false }

    /// Fantôme : rectangle translucide en couleur d'accent et icône de l'application, à la place que
    /// prendra la fenêtre ; dessiné sous les étiquettes et la barre.
    private func drawGhost(_ ghost: LauncherGhost) {
        let local = ghost.frame.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y)
        guard local.intersects(bounds) else { return }
        let path = NSBezierPath(roundedRect: local.insetBy(dx: 2, dy: 2), xRadius: 12, yRadius: 12)
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 2
        path.setLineDash([10, 6], count: 2, phase: 0)
        path.stroke()
        if let icon = ghost.icon {
            let side = min(96, local.width * 0.4, local.height * 0.4)
            icon.draw(in: CGRect(x: local.midX - side / 2, y: local.midY - side / 2, width: side, height: side),
                      from: .zero, operation: .sourceOver, fraction: 0.85)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let ghost { drawGhost(ghost) }
        var occupied: [CGRect] = []
        for badge in badges {
            guard let placement = placement(for: badge, avoiding: occupied) else { continue }
            drawTargetFrame(for: badge, placement: placement)
            drawPointer(for: badge, placement: placement)
            drawBadge(badge, in: placement.badge)
            occupied.append(placement.badge.insetBy(dx: -style.badgeAvoidanceMargin, dy: -style.badgeAvoidanceMargin))
        }
        if let searchBar {
            SearchBarRenderer.draw(searchBar, in: bounds, style: style)
        }
    }

    private func placement(for badge: TargetOverlayBadge, avoiding occupied: [CGRect]) -> BadgePlacement? {
        let localFrame = badge.frame.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y)
        guard bounds.intersects(localFrame), localFrame.width > 4, localFrame.height > 4 else { return nil }

        let label = badge.label.isEmpty ? "?" : badge.label
        let textSize = label.size(withAttributes: textAttributes)
        let badgeSize = style.badgeSize(textWidth: textSize.width)
        if badge.kind == .gridCell, style.labelPlacement == .center {
            let rect = clamped(CGRect(
                x: localFrame.midX - badgeSize.width / 2,
                y: localFrame.midY - badgeSize.height / 2,
                width: badgeSize.width,
                height: badgeSize.height
            )).integral
            return BadgePlacement(badge: rect, target: localFrame)
        }
        let candidates = candidateOrigins(for: localFrame, badgeSize: badgeSize)
        for origin in candidates {
            let rect = clamped(CGRect(origin: origin, size: badgeSize)).integral
            if !occupied.contains(where: { $0.intersects(rect) }) {
                return BadgePlacement(badge: rect, target: localFrame)
            }
        }
        let fallback = clamped(CGRect(origin: candidates.first ?? localFrame.origin, size: badgeSize)).integral
        return BadgePlacement(badge: fallback, target: localFrame)
    }

    private func candidateOrigins(for frame: CGRect, badgeSize: CGSize) -> [CGPoint] {
        let gap = style.badgeGap
        let inset = style.badgeInset
        let primary = CGPoint(x: frame.minX + inset, y: frame.maxY + gap)
        let anchors = [
            primary,
            CGPoint(x: frame.maxX - badgeSize.width - inset, y: frame.maxY + gap),
            CGPoint(x: frame.maxX + gap, y: frame.midY - badgeSize.height / 2),
            CGPoint(x: frame.minX - badgeSize.width - gap, y: frame.midY - badgeSize.height / 2),
            CGPoint(x: frame.minX + inset, y: frame.minY - badgeSize.height - gap),
            CGPoint(x: frame.maxX - badgeSize.width - inset, y: frame.minY - badgeSize.height - gap),
            CGPoint(x: frame.midX - badgeSize.width / 2, y: frame.midY - badgeSize.height / 2),
            CGPoint(x: frame.minX + inset, y: frame.maxY - badgeSize.height - inset),
            CGPoint(x: frame.maxX - badgeSize.width - inset, y: frame.maxY - badgeSize.height - inset),
        ]
        let stepX = badgeSize.width + style.badgePlacementSpacing
        let stepY = badgeSize.height + style.badgePlacementSpacing
        var result = anchors
        for ring in 1...8 {
            let distanceX = CGFloat(ring) * stepX
            let distanceY = CGFloat(ring) * stepY
            result.append(contentsOf: [
                CGPoint(x: primary.x + distanceX, y: primary.y),
                CGPoint(x: primary.x - distanceX, y: primary.y),
                CGPoint(x: primary.x, y: primary.y - distanceY),
                CGPoint(x: primary.x, y: primary.y + distanceY),
                CGPoint(x: primary.x + distanceX, y: primary.y - distanceY),
                CGPoint(x: primary.x - distanceX, y: primary.y - distanceY),
            ])
        }
        return result
    }

    private func clamped(_ rect: CGRect) -> CGRect {
        style.clampedBadge(rect, in: bounds)
    }

    private func drawTargetFrame(for badge: TargetOverlayBadge, placement: BadgePlacement) {
        if badge.isHighlighted {
            let path = NSBezierPath(roundedRect: placement.target.insetBy(dx: -2, dy: -2), xRadius: 6, yRadius: 6)
            NSColor.systemGreen.setStroke()
            path.lineWidth = 3
            path.stroke()
            return
        }
        if badge.isFramed {
            let path = NSBezierPath(roundedRect: placement.target.insetBy(dx: -2, dy: -2), xRadius: 6, yRadius: 6)
            NSColor.systemGreen.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 1.5
            path.stroke()
            return
        }
        guard style.drawTargetFrames, badge.kind == .gridCell else { return }
        let rect = placement.target.integral.insetBy(dx: 0.5, dy: 0.5)
        guard rect.width > 2, rect.height > 2 else { return }

        let path = NSBezierPath(rect: rect)
        (NSColor(hex: style.fillColor) ?? .systemBlue)
            .withAlphaComponent(CGFloat(style.fillOpacity))
            .setFill()
        path.fill()

        (NSColor(hex: style.borderColor) ?? .systemBlue)
            .withAlphaComponent(CGFloat(style.borderOpacity))
            .setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawPointer(for badge: TargetOverlayBadge, placement: BadgePlacement) {
        guard !(badge.kind == .gridCell && style.labelPlacement == .center) else { return }
        let badgeRect = placement.badge
        let targetRect = placement.target
        let targetPoint = nearestPoint(on: targetRect, to: CGPoint(x: badgeRect.midX, y: badgeRect.midY))
        let anchor = nearestPoint(on: badgeRect, to: targetPoint)
        let dx = targetPoint.x - anchor.x
        let dy = targetPoint.y - anchor.y
        let distance = max(1, hypot(dx, dy))
        let ux = dx / distance
        let uy = dy / distance
        let perp = CGPoint(x: -uy * 5, y: ux * 5)
        let tip = CGPoint(x: anchor.x + ux * min(16, distance), y: anchor.y + uy * min(16, distance))

        let path = NSBezierPath()
        path.move(to: CGPoint(x: anchor.x + perp.x, y: anchor.y + perp.y))
        path.line(to: tip)
        path.line(to: CGPoint(x: anchor.x - perp.x, y: anchor.y - perp.y))
        path.close()

        NSColor(calibratedWhite: 0.04, alpha: CGFloat(style.labelBackgroundOpacity)).setFill()
        path.fill()
        (badge.isActive ? NSColor.systemBlue : tint(for: badge.kind)).withAlphaComponent(0.9).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func nearestPoint(on rect: CGRect, to point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    private func drawBadge(_ badge: TargetOverlayBadge, in rect: CGRect) {
        let label = badge.label.isEmpty ? "?" : badge.label
        let textSize = label.size(withAttributes: textAttributes)
        let path = NSBezierPath(roundedRect: rect, xRadius: style.badgeCornerRadius, yRadius: style.badgeCornerRadius)
        // Recherche : fond vert pour chaque résultat ; seule la bordure distingue la cible choisie
        // (épaisse et blanche).
        (badge.isHighlighted || badge.isSearchResult ? NSColor.systemGreen.withAlphaComponent(0.85)
            : NSColor(calibratedWhite: 0.04, alpha: CGFloat(style.labelBackgroundOpacity))).setFill()
        path.fill()
        (badge.isHighlighted ? NSColor.white : badge.isActive ? NSColor.systemBlue : tint(for: badge.kind)).setStroke()
        path.lineWidth = badge.isHighlighted ? 2.5 : 1.5
        path.stroke()

        var attributes = textAttributes
        if badge.kind == .gridCell {
            attributes[.foregroundColor] = NSColor(hex: style.labelColor) ?? .white
        }
        label.draw(
            in: CGRect(
                x: rect.minX + (rect.width - textSize.width) / 2,
                y: rect.minY + (rect.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            ),
            withAttributes: attributes
        )
    }

    private func tint(for kind: TargetKind) -> NSColor {
        switch kind {
        case .window:
            return .systemGreen
        case .stage:
            return .systemOrange
        case .display:
            return .systemPurple
        case .desktop:
            return .systemGray
        case .bookmark:
            return .systemPink
        case .appElement:
            return .systemTeal
        case .gridCell:
            return .systemYellow
        }
    }
}
