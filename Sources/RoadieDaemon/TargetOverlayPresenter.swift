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

    public static func search(_ config: TargetModeConfig) -> TargetOverlayStyle {
        TargetOverlayStyle(
            labelFontSize: CGFloat(config.searchLabelFontSize),
            searchTextFontSize: CGFloat(config.searchTextFontSize),
            commandTextFontSize: CGFloat(config.commandTextFontSize),
            searchFontFamily: config.searchFontFamily,
            commandFontFamily: config.commandFontFamily
        )
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
    public static func startSearch(
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
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon,
                  let session = Unmanaged<AnyObject>.fromOpaque(refcon).takeUnretainedValue() as? any KeyEventTapSession
            else { return Unmanaged.passUnretained(event) }
            // macOS desactive le tap s'il repond trop lentement ou sur saisie utilisateur : on le reactive.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                Task { @MainActor in session.reenableEventTap() }
                return Unmanaged.passUnretained(event)
            }
            guard type == .keyDown else { return Unmanaged.passUnretained(event) }
            // Mode recherche : décodage propre (ponctuation, Tab, modificateurs de Retour), selon l'état
            // de la saisie (mode commande ou non) ; les modes lettres et grille gardent `KeyInput`.
            if let search = session as? TargetSearchSession {
                let input = SearchKeyInput(event: event, mode: search.keyMode.withLock { $0 })
                guard input.swallowed else { return Unmanaged.passUnretained(event) }
                Task { @MainActor in search.handleSearch(input) }
                return nil
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
    /// État de la saisie pour le tap clavier, lu hors de l'acteur principal (T027) : mis à jour à
    /// chaque affichage, remis en recherche à la fin de la session.
    nonisolated let keyMode = OSAllocatedUnfairLock(initialState: SearchKeyInput.Mode.emptySearch)
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
    /// Écran du pointeur à l'ouverture, celui de la barre.
    private let pointerScreen: CGRect?
    /// Des fenêtres sont encore en cours de lecture.
    private var isLoading = true

    init(
        targets: [RoadieTarget],
        alphabet: String,
        style: TargetOverlayStyle,
        commands: SlashCommandRunner,
        runDeferred: @escaping @MainActor ([String]) -> Void,
        openSettings: @escaping @MainActor (SettingCategory?) -> Void,
        activate: @escaping @MainActor (RoadieTarget, TargetActionVerb) -> TargetActionResult,
        onFinish: (@MainActor (TargetActionResult) -> Void)?
    ) {
        let mouse = NSEvent.mouseLocation
        let pointerScreen = NSScreen.screens.first { $0.frame.contains(mouse) }?.frame
        self.pointerScreen = pointerScreen
        self.model = TargetSearchModel(targets: targets, alphabet: alphabet) { Self.rank($0, windowOrder: -1, pointerScreen: pointerScreen) }
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
        render()
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
        finish(TargetActionResult(changed: false, message: "target_search_cancelled", error: "cancelled"))
    }

    /// Exigé par `KeyEventTapSession` ; la recherche reçoit `SearchKeyInput` via `handleSearch`.
    func handle(_ input: KeyInput) {}

    fileprivate func handleSearch(_ input: SearchKeyInput) {
        guard !finished else { return }
        lastInputAt = Date()
        // Mode commande (SPEC-023 R3) : aiguillage avant le modèle de recherche.
        if model.isCommandMode {
            handleCommand(input)
            return
        }
        if case .escape = input.kind {
            model.cancelPendingReturn()
            cancel()
            return
        }
        if case .confirm(let shift, let command, let isRepeat) = input.kind {
            guard !isRepeat, let target = model.highlighted else { return }
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
            if model.isCommandMode { enterCommandMode() }
        case .labelCharacter(let value):
            _ = model.typeLabel(value)
        case .delete:
            model.deleteBackward()
        case .next, .previous:
            model.handleNavigation(input)
        case .escape, .confirm, .ignored:
            break
        }
        render()
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
        // Chaque changement de saisie passe ici : le tap décode la touche suivante dans le bon mode.
        let mode: SearchKeyInput.Mode = commandModel != nil ? .command : model.query.isEmpty ? .emptySearch : .search
        keyMode.withLock { $0 = mode }
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
        let highlightedID = model.highlighted?.id
        // Barre vide : aucune étiquette (`*` les montre toutes). Étiquettes d'une lettre : chacun encadré.
        let shown = model.query.isEmpty ? [] : model.matches
        let framesAll = model.hasShortLabels
        let badges: [TargetOverlayBadge] = shown.compactMap { target in
            guard let frame = target.frame?.cgRect else { return nil }
            return TargetOverlayBadge(
                label: target.label,
                title: target.title,
                kind: target.kind,
                isActive: target.isActive,
                frame: RoadieScreenCoordinate.axRectToNS(frame),
                isHighlighted: target.id == highlightedID,
                isFramed: framesAll,
                isSearchResult: true
            )
        }
        show(badges: badges, bar: TargetSearchBar(query: model.query, matchCount: model.matches.count, properties: model.properties, isLoading: isLoading))
    }

    private func show(badges: [TargetOverlayBadge], bar: TargetSearchBar) {
        let barWindow = pointerScreen.flatMap { screen in windows.first { $0.frame == screen } } ?? windows.first
        for window in windows {
            window.update(badges: badges, searchBar: window === barWindow ? bar : nil)
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
        cleanup()
        onFinish?(activate(target, verb))
    }

    private func cleanup() {
        timer?.invalidate()
        timer = nil
        keyMode.withLock { $0 = .search }
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
    /// flèches parcourent l'historique, Retour exécute sans attendre de second Retour.
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
            case .arrow: historyDown()
            case .control: nextSuggestion()
            case .tab, nil: complete()
            }
        case .previous:
            switch input.navigationSource {
            case .arrow: historyUp()
            case .tab, .control, nil: previousSuggestion()
            }
        case .confirm(_, _, let isRepeat):
            if !isRepeat { return .submit(submit()) }
        case .escape:
            return .close
        case .ignored:
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
        case confirm(shift: Bool, command: Bool, isRepeat: Bool)
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
        case 36, 76: self.init(kind: .confirm(shift: shift, command: command, isRepeat: isRepeat)); return
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
    init(frame: CGRect, badges: [TargetOverlayBadge], style: TargetOverlayStyle) {
        let content = TargetOverlayView(
            frame: CGRect(origin: .zero, size: frame.size),
            badges: badges,
            screenOrigin: frame.origin,
            style: style
        )
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
        contentView = content
    }

    func updateStyle(_ style: TargetOverlayStyle) {
        guard let view = contentView as? TargetOverlayView else { return }
        view.updateStyle(style)
    }

    /// Mode recherche : nouvelles étiquettes et barre de saisie (nil = pas de barre sur cet écran).
    func update(badges: [TargetOverlayBadge], searchBar: TargetSearchBar?) {
        guard let view = contentView as? TargetOverlayView else { return }
        view.badges = badges
        view.searchBar = searchBar
        view.needsDisplay = true
    }
}

private final class TargetOverlayView: NSView {
    fileprivate var badges: [TargetOverlayBadge]
    fileprivate var searchBar: TargetSearchBar?
    private let screenOrigin: CGPoint
    private var style: TargetOverlayStyle
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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
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
