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
    /// Barre de défilement à droite de la liste (session 119).
    var scrollbar = false

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
        style.scrollbar = config.showScrollbar
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
        screenOnly: Bool = false,
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
            screenOnly: screenOnly,
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

    static func overlayWindows(for badges: [TargetOverlayBadge], style: TargetOverlayStyle = .labels) -> [TargetOverlayWindow] {
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

    /// Écrans sur lesquels créer une fenêtre overlay dès l'ouverture (Lot I) : en recherche à l'écran ou
    /// `launcher_on_screen`, tous les écrans ; pour le lanceur seul, uniquement l'écran de la barre. O(s).
    static func initialOverlayFrames(
        screens: [CGRect],
        barScreen: CGRect?,
        pointerScreen: CGRect?,
        expectsOnScreenScan: Bool
    ) -> [CGRect] {
        guard !expectsOnScreenScan, !screens.isEmpty else { return screens }
        if let target = barScreen ?? pointerScreen, let matched = screens.first(where: { $0 == target }) {
            return [matched]
        }
        return [screens[0]]
    }

    /// Écrans supplémentaires à ouvrir paresseusement dès qu'une étiquette ou un aperçu fantôme
    /// apparaît sur un autre moniteur (Lot I). O(s · b).
    static func missingOverlayFrames(
        existing: [CGRect],
        screens: [CGRect],
        badgeFrames: [CGRect],
        hasGhost: Bool
    ) -> [CGRect] {
        guard hasGhost || !badgeFrames.isEmpty else { return [] }
        return screens.filter { frame in
            guard !existing.contains(frame) else { return false }
            if hasGhost { return true }
            return badgeFrames.contains { frame.insetBy(dx: -80, dy: -80).intersects($0) }
        }
    }
}

/// Session interactive pilotée par un tap clavier (CGEventTap) : installation et réactivation
/// partagées par la session de cibles et la session de grille.
@MainActor
protocol KeyEventTapSession: AnyObject {
    var eventTap: CFMachPort? { get set }
    var runLoopSource: CFRunLoopSource? { get set }
    var eventTapContext: UnsafeMutableRawPointer? { get set }
    var finished: Bool { get }
    func handle(_ input: KeyInput)
}

extension KeyEventTapSession {
    func reenableEventTap() {
        guard !finished, let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func removeEventTap() {
        if let eventTapContext { KeyEventTapOwners.shared.remove(eventTapContext) }
        eventTapContext = nil
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CFRunLoopSourceInvalidate(runLoopSource)
        }
        runLoopSource = nil
        eventTap = nil
    }

    func installEventTap() -> Bool {
        let mask = TargetSearchDismissal.eventMask(search: self is TargetSearchSession)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon,
                  let session = KeyEventTapOwners.shared.owner(for: refcon) as? any KeyEventTapSession
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
            // Défilement sur la liste ou la grille (session 131) : il déplace la sélection, la fenêtre dessous ne bouge pas.
            if type == .scrollWheel, let search = session as? TargetSearchSession {
                let delta = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
                let consumed = MainActor.assumeIsolated { search.handleScroll(at: event.location, delta: delta) }
                return consumed ? nil : Unmanaged.passUnretained(event)
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
                guard !session.finished else { return }
                session.handle(input)
            }
            return nil
        }
        let context = KeyEventTapOwners.shared.register(self)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: context
        ) else {
            KeyEventTapOwners.shared.remove(context)
            return false
        }
        eventTapContext = context
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
    var eventTapContext: UnsafeMutableRawPointer?
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
        removeEventTap()
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
    var eventTapContext: UnsafeMutableRawPointer?
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
        removeEventTap()
        hideOverlayNow()
    }
}
