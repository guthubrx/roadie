import AppKit
import RoadieCore

public struct TargetOverlayStyle: Sendable {
    public var drawTargetFrames: Bool
    public var fillColor: String
    public var fillOpacity: Double
    public var borderColor: String
    public var borderOpacity: Double
    public var labelColor: String
    public var labelBackgroundOpacity: Double
    public var labelPlacement: TargetGridLabelPlacement

    public init(
        drawTargetFrames: Bool = false,
        fillColor: String = "#000000",
        fillOpacity: Double = 0,
        borderColor: String = "#4DABF7",
        borderOpacity: Double = 0.9,
        labelColor: String = "#FFFFFF",
        labelBackgroundOpacity: Double = 0.84,
        labelPlacement: TargetGridLabelPlacement = .callout
    ) {
        self.drawTargetFrames = drawTargetFrames
        self.fillColor = fillColor
        self.fillOpacity = min(1, max(0, fillOpacity))
        self.borderColor = borderColor
        self.borderOpacity = min(1, max(0, borderOpacity))
        self.labelColor = labelColor
        self.labelBackgroundOpacity = min(1, max(0, labelBackgroundOpacity))
        self.labelPlacement = labelPlacement
    }

    public static let labels = TargetOverlayStyle()

    public static func grid(_ config: TargetGridConfig) -> TargetOverlayStyle {
        TargetOverlayStyle(
            drawTargetFrames: config.overlayDrawGrid,
            fillColor: config.overlayFillColor,
            fillOpacity: config.overlayFillOpacity,
            borderColor: config.overlayBorderColor,
            borderOpacity: config.overlayBorderOpacity,
            labelColor: config.overlayLabelColor,
            labelBackgroundOpacity: config.overlayLabelBackgroundOpacity,
            labelPlacement: config.labelPlacement
        )
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
        activate: @escaping @MainActor (String) -> TargetActionResult,
        onFinish: @escaping @MainActor (TargetActionResult) -> Void
    ) -> TargetOverlaySessionHandle? {
        let session = TargetInteractiveSession(
            state: state,
            duration: duration,
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
    public static func startSearch(
        targets: [RoadieTarget],
        alphabet: String,
        load: (
            _ deliver: @escaping @MainActor @Sendable ([RoadieTarget], Int) -> Void,
            _ done: @escaping @MainActor @Sendable () -> Void
        ) -> Void,
        activate: @escaping @MainActor (RoadieTarget, TargetActionVerb) -> TargetActionResult,
        onFinish: @escaping @MainActor (TargetActionResult) -> Void
    ) -> TargetOverlaySessionHandle? {
        let session = TargetSearchSession(targets: targets, alphabet: alphabet, activate: activate, onFinish: onFinish)
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
            // Mode recherche : décodage propre (ponctuation, Tab, modificateurs de Retour), les modes
            // lettres et grille gardent `KeyInput`.
            if let search = session as? TargetSearchSession {
                let input = SearchKeyInput(event: event)
                guard input.kind != .ignored else { return Unmanaged.passUnretained(event) }
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
        activate: @escaping @MainActor (String) -> TargetActionResult,
        onFinish: (@MainActor (TargetActionResult) -> Void)?
    ) {
        self.state = state
        self.duration = max(1, duration)
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
        windows = TargetOverlayPresenter.overlayWindows(for: badges)
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
    private let style: TargetOverlayStyle
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
@MainActor
private final class TargetSearchSession: TargetOverlaySessionHandle, KeyEventTapSession {
    /// Fermeture sans frappe pendant ce délai.
    static let idleTimeout: TimeInterval = 60

    private var model: TargetSearchModel
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
        activate: @escaping @MainActor (RoadieTarget, TargetActionVerb) -> TargetActionResult,
        onFinish: (@MainActor (TargetActionResult) -> Void)?
    ) {
        let mouse = NSEvent.mouseLocation
        let pointerScreen = NSScreen.screens.first { $0.frame.contains(mouse) }?.frame
        self.pointerScreen = pointerScreen
        self.model = TargetSearchModel(targets: targets, alphabet: alphabet) { Self.rank($0, windowOrder: -1, pointerScreen: pointerScreen) }
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
        // Une fenêtre par écran : la barre suit l'écran du pointeur, même sans correspondance.
        windows = NSScreen.screens.map { TargetOverlayWindow(frame: $0.frame, badges: [], style: .labels) }
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

    func cancel() {
        finish(TargetActionResult(changed: false, message: "target_search_cancelled", error: "cancelled"))
    }

    /// Exigé par `KeyEventTapSession` ; la recherche reçoit `SearchKeyInput` via `handleSearch`.
    func handle(_ input: KeyInput) {}

    fileprivate func handleSearch(_ input: SearchKeyInput) {
        guard !finished else { return }
        lastInputAt = Date()
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
        case .labelCharacter(let value):
            _ = model.typeLabel(value)
        case .delete:
            model.deleteBackward()
        case .next:
            model.next()
        case .previous:
            model.previous()
        case .escape, .confirm, .ignored:
            break
        }
        render()
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
        let highlightedID = model.highlighted?.id
        let badges: [TargetOverlayBadge] = model.matches.compactMap { target in
            guard let frame = target.frame?.cgRect else { return nil }
            return TargetOverlayBadge(
                label: target.label,
                title: target.title,
                kind: target.kind,
                isActive: target.isActive,
                frame: RoadieScreenCoordinate.axRectToNS(frame),
                isHighlighted: target.id == highlightedID
            )
        }
        let bar = TargetSearchBar(query: model.query, matchCount: model.matches.count, properties: model.properties, isLoading: isLoading)
        let mouse = NSEvent.mouseLocation
        let barWindow = windows.first { $0.frame.contains(mouse) } ?? windows.first
        for window in windows {
            window.update(badges: badges, searchBar: window === barWindow ? bar : nil)
        }
    }

    private func finish(_ result: TargetActionResult) {
        guard !finished else { return }
        finished = true
        cleanup()
        onFinish?(result)
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

/// Touches du mode recherche (SPEC-021). Les touches mortes et la composition sont ignorées : la
/// recherche ne tient pas compte des accents. Les combinaisons Commande (sauf Cmd-Retour) passent à
/// l'app ou au système.
public struct SearchKeyInput: Sendable, Equatable {
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

    public let kind: Kind

    init(event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let shift = flags.contains(.maskShift)
        let command = flags.contains(.maskCommand)
        let control = flags.contains(.maskControl)
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
        let text = String(utf16CodeUnits: chars, count: length)
        self.kind = Self.kind(
            keyCode: keyCode, text: text, shift: shift, command: command, control: control,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        )
    }

    public init(kind: Kind) {
        self.kind = kind
    }

    /// Décodage pur, testable : code de touche, texte produit et modificateurs.
    public static func kind(keyCode: Int64, text: String, shift: Bool, command: Bool, control: Bool, isRepeat: Bool) -> Kind {
        switch keyCode {
        case 53: return .escape
        case 51: return .delete
        case 36, 76: return .confirm(shift: shift, command: command, isRepeat: isRepeat)
        default: break
        }
        // Cmd-Tab, Cmd-Espace… restent au système.
        if command { return .ignored }
        switch keyCode {
        case 48: return shift ? .previous : .next
        case 125: return .next
        case 126: return .previous
        default: break
        }
        if control {
            switch text.lowercased() {
            case "n", "\u{0E}": return .next
            case "p", "\u{10}": return .previous
            default: return .ignored
            }
        }
        guard text.count == 1, let character = text.first else { return .ignored }
        if character.isLetter && shift { return .labelCharacter(String(character).lowercased()) }
        if character.isLetter || character.isNumber || " *;?".contains(character) {
            return .text(String(character))
        }
        return .ignored
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

    /// Mode recherche : nouvelles étiquettes et barre de saisie (nil = pas de barre sur cet écran).
    func update(badges: [TargetOverlayBadge], searchBar: TargetSearchBar?) {
        guard let view = contentView as? TargetOverlayView else { return }
        view.badges = badges
        view.searchBar = searchBar
        view.needsDisplay = true
    }
}

/// Contenu de la barre de saisie du mode recherche.
private struct TargetSearchBar {
    var query: String
    var matchCount: Int
    var properties: String?
    var isLoading: Bool
}

private final class TargetOverlayView: NSView {
    fileprivate var badges: [TargetOverlayBadge]
    fileprivate var searchBar: TargetSearchBar?
    private let screenOrigin: CGPoint
    private let style: TargetOverlayStyle

    private struct BadgePlacement {
        var badge: CGRect
        var target: CGRect
    }

    init(frame: CGRect, badges: [TargetOverlayBadge], screenOrigin: CGPoint, style: TargetOverlayStyle) {
        self.badges = badges
        self.screenOrigin = screenOrigin
        self.style = style
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        nil
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
            occupied.append(placement.badge.insetBy(dx: -4, dy: -4))
        }
        if let searchBar {
            drawSearchBar(searchBar)
        }
    }

    private func drawSearchBar(_ bar: TargetSearchBar) {
        let text: String
        if let properties = bar.properties {
            text = properties
        } else {
            let count = bar.matchCount == 0 ? "aucune correspondance" : "\(bar.matchCount) correspondance\(bar.matchCount > 1 ? "s" : "")"
            text = "🔍 \(bar.query)▏   \(count)\(bar.isLoading ? " · lecture…" : "")"
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let width = min(bounds.width - 40, max(420, size.width + 40))
        let rect = CGRect(x: bounds.midX - width / 2, y: bounds.minY + 48, width: width, height: 40).integral
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor(calibratedWhite: 0.06, alpha: 0.92).setFill()
        path.fill()
        NSColor.systemGreen.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 1.5
        path.stroke()
        text.draw(
            in: CGRect(x: rect.minX + 20, y: rect.midY - size.height / 2, width: rect.width - 40, height: size.height),
            withAttributes: attributes
        )
    }

    private func placement(for badge: TargetOverlayBadge, avoiding occupied: [CGRect]) -> BadgePlacement? {
        let localFrame = badge.frame.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y)
        guard bounds.intersects(localFrame), localFrame.width > 4, localFrame.height > 4 else { return nil }

        let label = badge.label.isEmpty ? "?" : badge.label
        let textSize = label.size(withAttributes: Self.textAttributes)
        let badgeSize = CGSize(width: max(28, textSize.width + 16), height: 24)
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
        let gap: CGFloat = 10
        let inset: CGFloat = 6
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
        let stepX = badgeSize.width + 6
        let stepY = badgeSize.height + 6
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
        let x = min(max(rect.minX, bounds.minX + 4), bounds.maxX - rect.width - 4)
        let y = min(max(rect.minY, bounds.minY + 4), bounds.maxY - rect.height - 4)
        return CGRect(origin: CGPoint(x: x, y: y), size: rect.size)
    }

    private func drawTargetFrame(for badge: TargetOverlayBadge, placement: BadgePlacement) {
        if badge.isHighlighted {
            let path = NSBezierPath(roundedRect: placement.target.insetBy(dx: -2, dy: -2), xRadius: 6, yRadius: 6)
            NSColor.systemGreen.setStroke()
            path.lineWidth = 3
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
        let textSize = label.size(withAttributes: Self.textAttributes)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        (badge.isHighlighted ? NSColor.systemGreen.withAlphaComponent(0.85)
            : NSColor(calibratedWhite: 0.04, alpha: CGFloat(style.labelBackgroundOpacity))).setFill()
        path.fill()
        (badge.isHighlighted ? NSColor.white : badge.isActive ? NSColor.systemBlue : tint(for: badge.kind)).setStroke()
        path.lineWidth = badge.isHighlighted ? 2.5 : 1.5
        path.stroke()

        var attributes = Self.textAttributes
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

    private static let textAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
        .foregroundColor: NSColor.white,
    ]

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
