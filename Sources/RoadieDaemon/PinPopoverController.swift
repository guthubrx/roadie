import AppKit
import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore

public struct PinPopoverSettings: Equatable, Sendable {
    public static let inactiveButtonColor = "#4B4C4E"

    public var enabled: Bool
    public var showOnUnpinned: Bool
    public var buttonSize: CGFloat
    public var buttonColor: String
    public var titlebarHeight: CGFloat
    public var leadingExclusion: CGFloat
    public var trailingExclusion: CGFloat
    public var collapseEnabled: Bool
    public var proxyHeight: CGFloat
    public var proxyMinWidth: CGFloat

    public init(
        enabled: Bool = false,
        showOnUnpinned: Bool = true,
        buttonSize: CGFloat = 12.5,
        buttonColor: String = "#0A84FF",
        titlebarHeight: CGFloat = 36,
        leadingExclusion: CGFloat = 64,
        trailingExclusion: CGFloat = 16,
        collapseEnabled: Bool = true,
        proxyHeight: CGFloat = 28,
        proxyMinWidth: CGFloat = 160
    ) {
        self.enabled = enabled
        self.showOnUnpinned = showOnUnpinned
        self.buttonSize = buttonSize
        self.buttonColor = buttonColor
        self.titlebarHeight = titlebarHeight
        self.leadingExclusion = leadingExclusion
        self.trailingExclusion = trailingExclusion
        self.collapseEnabled = collapseEnabled
        self.proxyHeight = proxyHeight
        self.proxyMinWidth = proxyMinWidth
    }

    public init(config: PinPopoverConfig) {
        self.init(
            enabled: config.enabled,
            showOnUnpinned: config.showOnUnpinned,
            buttonSize: CGFloat(config.buttonSize),
            buttonColor: config.buttonColor,
            titlebarHeight: CGFloat(config.titlebarHeight),
            leadingExclusion: CGFloat(config.leadingExclusion),
            trailingExclusion: CGFloat(config.trailingExclusion),
            collapseEnabled: config.collapseEnabled,
            proxyHeight: CGFloat(config.proxyHeight),
            proxyMinWidth: CGFloat(config.proxyMinWidth)
        )
    }
}

public enum PinPopoverPlacementReason: String, Equatable, Codable, Sendable {
    case disabled
    case notPinned = "not_pinned"
    case notManaged = "not_managed"
    case notVisible = "not_visible"
    case collapsed
    case eligible
}

public struct PinPopoverPlacement: Equatable, Sendable {
    public var windowID: WindowID?
    public var buttonFrame: CGRect?
    public var proxyFrame: CGRect?
    public var isEligible: Bool
    public var reason: PinPopoverPlacementReason

    public init(
        windowID: WindowID?,
        buttonFrame: CGRect?,
        proxyFrame: CGRect? = nil,
        isEligible: Bool,
        reason: PinPopoverPlacementReason
    ) {
        self.windowID = windowID
        self.buttonFrame = buttonFrame
        self.proxyFrame = proxyFrame
        self.isEligible = isEligible
        self.reason = reason
    }
}

public struct PinPopoverMenuModel: Equatable, Sendable {
    public var sections: [PinPopoverMenuSection]
}

public struct PinPopoverMenuSection: Equatable, Sendable {
    public var title: String
    public var items: [PinPopoverMenuItem]
}

public struct PinPopoverMenuItem: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case window(WindowContextActionKind, String)
        case collapse
        case restore
    }

    public var title: String
    public var action: Action?
    public var children: [PinPopoverMenuItem]

    public init(title: String, action: Action? = nil, children: [PinPopoverMenuItem] = []) {
        self.title = title
        self.action = action
        self.children = children
    }
}

@MainActor
public final class PinPopoverController {
    private let snapshotService: SnapshotService
    private let actions: WindowContextActions
    private let stageStore: StageStore
    private let configLoader: () -> RoadieConfig
    private let events: EventLog
    private var timer: Timer?
    private var buttonPanels: [WindowID: PinButtonPanel] = [:]
    private var proxyPanels: [WindowID: PinProxyPanel] = [:]
    private var menuTargets: [PinPopoverMenuTarget] = []
    private var lastIgnoredAt: [String: Date] = [:]
    private var lastFrames: [WindowID: CGRect] = [:]
    private var hiddenUntilAfterMovement: [WindowID: Date] = [:]
    private var buttonHiddenUntil: Date = .distantPast
    private var eventMonitors: [Any] = []

    public init(
        snapshotService: SnapshotService = SnapshotService(),
        actions: WindowContextActions = WindowContextActions(),
        stageStore: StageStore = StageStore(),
        configLoader: @escaping () -> RoadieConfig = { (try? RoadieConfigLoader.load()) ?? RoadieConfig() },
        events: EventLog = EventLog()
    ) {
        self.snapshotService = snapshotService
        self.actions = actions
        self.stageStore = stageStore
        self.configLoader = configLoader
        self.events = events
    }

    public func start() {
        guard timer == nil else { return }
        NSApplication.shared.setActivationPolicy(.accessory)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        installPointerDragSuppression()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
        buttonPanels.values.forEach { $0.orderOut(nil) }
        proxyPanels.values.forEach { $0.orderOut(nil) }
        buttonPanels.removeAll()
        proxyPanels.removeAll()
        menuTargets.removeAll()
        lastIgnoredAt.removeAll()
    }

    nonisolated public static func placement(
        for entry: ScopedWindowSnapshot,
        activeScope: StageScope?,
        settings: PinPopoverSettings
    ) -> PinPopoverPlacement {
        guard settings.enabled else {
            return PinPopoverPlacement(windowID: entry.window.id, buttonFrame: nil, isEligible: false, reason: .disabled)
        }
        guard entry.scope != nil, entry.window.isTileCandidate else {
            return PinPopoverPlacement(windowID: entry.window.id, buttonFrame: nil, isEligible: false, reason: .notManaged)
        }
        if entry.pin == nil, !settings.showOnUnpinned {
            return PinPopoverPlacement(windowID: entry.window.id, buttonFrame: nil, isEligible: false, reason: .notPinned)
        }
        if let pin = entry.pin, !pin.visibility(in: activeScope).shouldBeVisible {
            return PinPopoverPlacement(windowID: entry.window.id, buttonFrame: nil, isEligible: false, reason: .notVisible)
        }
        if entry.pinPresentation?.presentation == .collapsed {
            let proxy = entry.pinPresentation?.proxyFrame?.cgRect ?? defaultProxyFrame(for: entry.window.frame.cgRect, settings: settings)
            return PinPopoverPlacement(windowID: entry.window.id, buttonFrame: nil, proxyFrame: proxy, isEligible: true, reason: .collapsed)
        }
        let frame = entry.window.frame.cgRect
        let size = settings.buttonSize
        let minX = frame.minX + settings.leadingExclusion
        let maxX = frame.maxX - settings.trailingExclusion - size
        guard minX <= maxX else {
            return PinPopoverPlacement(windowID: entry.window.id, buttonFrame: nil, isEligible: false, reason: .notVisible)
        }
        let x = min(max(minX, frame.minX + settings.leadingExclusion + 4), maxX)
        let y = frame.minY + max(0, (settings.titlebarHeight - size) / 2) - 4
        return PinPopoverPlacement(
            windowID: entry.window.id,
            buttonFrame: CGRect(x: x, y: y, width: size, height: size).integral,
            isEligible: true,
            reason: .eligible
        )
    }

    nonisolated public static func menuModel(
        windowID: WindowID,
        pin: PersistentWindowPin?,
        presentation: PinPresentationState?,
        destinations: [WindowDestination],
        settings: PinPopoverSettings
    ) -> PinPopoverMenuModel {
        var windowItems: [PinPopoverMenuItem] = []
        if let pin {
            windowItems.append(PinPopoverMenuItem(
                title: pin.pinScope == .desktop ? "Pin actuel : ce desktop" : "Pin actuel : tous les desktops"
            ))
            windowItems.append(PinPopoverMenuItem(
                title: pin.pinScope == .desktop ? "Pin sur tous les desktops" : "Pin sur ce desktop",
                action: .window(pin.pinScope == .desktop ? .pinAllDesktops : .pinDesktop, "")
            ))
            windowItems.append(PinPopoverMenuItem(title: "Retirer le pin", action: .window(.unpin, "")))
        } else {
            windowItems.append(PinPopoverMenuItem(title: "Pin sur ce desktop", action: .window(.pinDesktop, "")))
            windowItems.append(PinPopoverMenuItem(title: "Pin sur tous les desktops", action: .window(.pinAllDesktops, "")))
        }
        if settings.collapseEnabled, pin != nil {
            let collapsed = presentation?.presentation == .collapsed
            windowItems.append(PinPopoverMenuItem(title: collapsed ? "Déplier la fenêtre" : "Replier la fenêtre", action: collapsed ? .restore : .collapse))
        }

        var sections = [PinPopoverMenuSection(title: "Fenêtre", items: windowItems)]
        sections.append(contentsOf: destinationSections(destinations: destinations))
        _ = windowID
        return PinPopoverMenuModel(sections: sections)
    }

    nonisolated public static func contextAction(
        for action: PinPopoverMenuItem.Action,
        windowID: WindowID,
        sourceScope: StageScope?
    ) -> WindowContextAction? {
        guard case let .window(kind, targetID) = action else { return nil }
        return WindowContextAction(windowID: windowID, kind: kind, targetID: targetID, sourceScope: sourceScope)
    }

    nonisolated public static func collapsedPresentation(
        for window: WindowSnapshot,
        settings: PinPopoverSettings,
        now: Date = Date()
    ) -> PinPresentationState {
        PinPresentationState(
            windowID: window.id,
            presentation: .collapsed,
            restoreFrame: window.frame,
            proxyFrame: Rect(defaultProxyFrame(for: window.frame.cgRect, settings: settings)),
            updatedAt: now
        )
    }

    nonisolated public static func proxyTitle(for window: WindowSnapshot) -> String {
        let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? window.appName : title
    }

    private func refresh() {
        let settings = PinPopoverSettings(config: configLoader().experimental.pinPopover)
        guard settings.enabled else {
            hideAll()
            return
        }

        let snapshot = snapshotService.snapshot()
        let now = Date()
        var liveButtons = Set<WindowID>()
        var liveProxies = Set<WindowID>()
        let buttonSuppressed = buttonHiddenUntil > now
        let liveWindowIDs = Set(snapshot.windows.map(\.window.id))
        lastFrames = lastFrames.filter { liveWindowIDs.contains($0.key) }
        hiddenUntilAfterMovement = hiddenUntilAfterMovement.filter { liveWindowIDs.contains($0.key) && $0.value > now }

        for entry in snapshot.windows {
            let frame = entry.window.frame.cgRect.integral
            if let previous = lastFrames[entry.window.id], frameChanged(previous, frame) {
                hiddenUntilAfterMovement[entry.window.id] = now.addingTimeInterval(0.35)
            }
            lastFrames[entry.window.id] = frame
            if let hiddenUntil = hiddenUntilAfterMovement[entry.window.id], hiddenUntil > now {
                buttonPanels[entry.window.id]?.orderOut(nil)
                proxyPanels[entry.window.id]?.orderOut(nil)
                continue
            }

            let activeScope = entry.pin.flatMap { snapshot.state.activeScope(on: $0.homeScope.displayID) }
            let placement = Self.placement(for: entry, activeScope: activeScope, settings: settings)
            guard placement.isEligible else {
                logIgnoredIfNeeded(entry: entry, placement: placement)
                continue
            }
            if let buttonFrame = placement.buttonFrame {
                if buttonSuppressed {
                    buttonPanels[entry.window.id]?.orderOut(nil)
                } else {
                    liveButtons.insert(entry.window.id)
                    showButton(
                        window: entry.window,
                        frame: buttonFrame,
                        isActive: isActive(entry.window, focusedWindowID: snapshot.focusedWindowID),
                        settings: settings
                    )
                }
            }
            if let proxyFrame = placement.proxyFrame {
                liveProxies.insert(entry.window.id)
                showProxy(window: entry.window, frame: proxyFrame, settings: settings)
            }
        }

        for (windowID, panel) in buttonPanels where !liveButtons.contains(windowID) {
            panel.orderOut(nil)
            buttonPanels.removeValue(forKey: windowID)
        }
        for (windowID, panel) in proxyPanels where !liveProxies.contains(windowID) {
            panel.orderOut(nil)
            proxyPanels.removeValue(forKey: windowID)
        }
    }

    private func installPointerDragSuppression() {
        guard eventMonitors.isEmpty else { return }
        if let globalDrag = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged], handler: { [weak self] _ in
            Task { @MainActor in self?.hideButtonsDuringPointerDrag() }
        }) {
            eventMonitors.append(globalDrag)
        }
        if let localDrag = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged], handler: { [weak self] event in
            self?.hideButtonsDuringPointerDrag()
            return event
        }) {
            eventMonitors.append(localDrag)
        }
    }

    private func hideButtonsDuringPointerDrag() {
        buttonHiddenUntil = Date().addingTimeInterval(0.35)
        buttonPanels.values.forEach { $0.orderOut(nil) }
    }

    private func frameChanged(_ previous: CGRect, _ current: CGRect) -> Bool {
        abs(previous.minX - current.minX) > 1 ||
            abs(previous.minY - current.minY) > 1 ||
            abs(previous.width - current.width) > 1 ||
            abs(previous.height - current.height) > 1
    }

    nonisolated private static func destinationSections(destinations: [WindowDestination]) -> [PinPopoverMenuSection] {
        [
            PinPopoverMenuSection(title: "Envoyer vers stage", items: menuItems(for: .stage, in: destinations)),
            PinPopoverMenuSection(title: "Envoyer vers desktop/stage", items: desktopStageItems(in: destinations)),
            PinPopoverMenuSection(title: "Envoyer vers desktop", items: menuItems(for: .desktop, in: destinations)),
            PinPopoverMenuSection(title: "Envoyer vers écran", items: menuItems(for: .display, in: destinations))
        ].filter { !$0.items.isEmpty }
    }

    nonisolated private static func menuItems(for kind: WindowContextActionKind, in destinations: [WindowDestination]) -> [PinPopoverMenuItem] {
        TitlebarContextMenuController.availableDestinations(for: kind, in: destinations)
            .map { PinPopoverMenuItem(title: $0.label, action: .window(kind, $0.id)) }
    }

    nonisolated private static func desktopStageItems(in destinations: [WindowDestination]) -> [PinPopoverMenuItem] {
        TitlebarContextMenuController.desktopStageDestinationGroups(in: destinations).map { group in
            return PinPopoverMenuItem(
                title: group.label,
                children: group.stages.map {
                    PinPopoverMenuItem(title: $0.label, action: .window(.desktopStage, $0.id))
                }
            )
        }
    }

    private func showButton(window: WindowSnapshot, frame: CGRect, isActive: Bool, settings: PinPopoverSettings) {
        let panel = buttonPanels[window.id] ?? PinButtonPanel()
        buttonPanels[window.id] = panel
        panel.onClick = { [weak self] in self?.showMenu(for: window.id, at: panel.frame.origin, settings: settings) }
        let color = isActive
            ? (NSColor(hex: settings.buttonColor) ?? .systemBlue)
            : (NSColor(hex: PinPopoverSettings.inactiveButtonColor) ?? NSColor(calibratedWhite: 0.3, alpha: 1))
        panel.render(frame: Self.axToNS(frame), color: color)
    }

    private func showProxy(window: WindowSnapshot, frame: CGRect, settings: PinPopoverSettings) {
        let panel = proxyPanels[window.id] ?? PinProxyPanel()
        proxyPanels[window.id] = panel
        panel.onClick = { [weak self] in self?.showMenu(for: window.id, at: panel.frame.origin, settings: settings) }
        panel.render(frame: Self.axToNS(frame), title: Self.proxyTitle(for: window), color: NSColor(hex: settings.buttonColor) ?? .systemBlue)
    }

    private func showMenu(for windowID: WindowID, at point: CGPoint, settings: PinPopoverSettings) {
        let snapshot = snapshotService.snapshot()
        guard let entry = snapshot.windows.first(where: { $0.window.id == windowID }) else { return }
        let contextSettings = TitlebarContextMenuSettings(
            enabled: true,
            includeStageDestinations: true,
            includeDesktopDestinations: true,
            includeDisplayDestinations: true
        )
        let destinations = actions.destinations(for: windowID, in: snapshot, settings: contextSettings)
        let model = Self.menuModel(
            windowID: windowID,
            pin: entry.pin,
            presentation: entry.pinPresentation,
            destinations: destinations,
            settings: settings
        )
        let menu = buildMenu(from: model, windowID: windowID, sourceScope: entry.scope)
        events.append(RoadieEvent(
            type: "pin_popover.shown",
            scope: entry.scope,
            details: ["windowID": String(windowID.rawValue)]
        ))
        _ = menu.popUp(positioning: nil, at: point, in: nil)
    }

    private func buildMenu(from model: PinPopoverMenuModel, windowID: WindowID, sourceScope: StageScope?) -> NSMenu {
        menuTargets.removeAll(keepingCapacity: true)
        let menu = NSMenu(title: "Roadie")
        for section in model.sections {
            let parent = NSMenuItem(title: section.title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: section.title)
            for item in section.items {
                submenu.addItem(nsMenuItem(from: item, windowID: windowID, sourceScope: sourceScope))
            }
            parent.submenu = submenu
            menu.addItem(parent)
        }
        return menu
    }

    private func nsMenuItem(from item: PinPopoverMenuItem, windowID: WindowID, sourceScope: StageScope?) -> NSMenuItem {
        if !item.children.isEmpty {
            let parent = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: item.title)
            for child in item.children {
                submenu.addItem(nsMenuItem(from: child, windowID: windowID, sourceScope: sourceScope))
            }
            parent.submenu = submenu
            return parent
        }

        guard let action = item.action else {
            let disabled = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
            disabled.isEnabled = false
            return disabled
        }
        let menuItem = NSMenuItem(title: item.title, action: #selector(PinPopoverMenuTarget.choose(_:)), keyEquivalent: "")
        let target = PinPopoverMenuTarget { [weak self] in
            self?.perform(action, windowID: windowID, sourceScope: sourceScope)
        }
        menuItem.target = target
        menuTargets.append(target)
        return menuItem
    }

    private func perform(_ action: PinPopoverMenuItem.Action, windowID: WindowID, sourceScope: StageScope?) {
        switch action {
        case let .window(kind, targetID):
            guard let contextAction = Self.contextAction(for: .window(kind, targetID), windowID: windowID, sourceScope: sourceScope) else { return }
            let result = actions.execute(contextAction)
            if kind == .unpin {
                buttonPanels.removeValue(forKey: windowID)?.orderOut(nil)
                proxyPanels.removeValue(forKey: windowID)?.orderOut(nil)
            }
            events.append(RoadieEvent(
                type: result.changed ? "pin_popover.action" : "pin_popover.failed",
                scope: sourceScope,
                details: ["windowID": String(windowID.rawValue), "kind": kind.rawValue, "message": result.message]
            ))
        case .collapse:
            collapse(windowID: windowID, sourceScope: sourceScope)
        case .restore:
            restore(windowID: windowID, sourceScope: sourceScope)
        }
    }

    private func collapse(windowID: WindowID, sourceScope: StageScope?) {
        let settings = PinPopoverSettings(config: configLoader().experimental.pinPopover)
        guard settings.collapseEnabled else { return }
        let snapshot = snapshotService.snapshot()
        guard let entry = snapshot.windows.first(where: { $0.window.id == windowID }),
              let pin = entry.pin,
              let display = snapshot.displays.first(where: { $0.id == pin.homeScope.displayID })
        else { return }

        let restoreFrame = entry.window.frame
        let presentation = Self.collapsedPresentation(for: entry.window, settings: settings)
        var state = stageStore.state()
        state.setPinPresentation(
            windowID: windowID,
            presentation: presentation.presentation,
            restoreFrame: presentation.restoreFrame,
            proxyFrame: presentation.proxyFrame
        )
        stageStore.save(state)
        _ = snapshotService.setFrame(hiddenFrame(for: restoreFrame.cgRect, on: display, among: snapshot.displays), of: entry.window)
        events.append(RoadieEvent(type: "window.pin_collapsed", scope: sourceScope, details: ["windowID": String(windowID.rawValue)]))
        refresh()
    }

    private func restore(windowID: WindowID, sourceScope: StageScope?) {
        let snapshot = snapshotService.snapshot()
        var state = stageStore.state()
        let presentation = state.removePinPresentation(windowID: windowID)
        stageStore.save(state)
        if let frame = presentation?.restoreFrame,
           let window = snapshot.windows.first(where: { $0.window.id == windowID })?.window {
            _ = snapshotService.setFrame(frame.cgRect, of: window)
        }
        proxyPanels.removeValue(forKey: windowID)?.orderOut(nil)
        events.append(RoadieEvent(type: "window.pin_restored", scope: sourceScope, details: ["windowID": String(windowID.rawValue)]))
        refresh()
    }

    private func logIgnoredIfNeeded(entry: ScopedWindowSnapshot, placement: PinPopoverPlacement) {
        guard entry.pin != nil else { return }
        switch placement.reason {
        case .disabled, .notPinned:
            return
        case .notManaged, .notVisible, .collapsed, .eligible:
            let key = "\(entry.window.id.rawValue):\(placement.reason.rawValue)"
            let now = Date()
            if let previous = lastIgnoredAt[key], now.timeIntervalSince(previous) < 2 {
                return
            }
            lastIgnoredAt[key] = now
            events.append(RoadieEvent(
                type: "pin_popover.ignored",
                scope: entry.scope,
                details: [
                    "windowID": String(entry.window.id.rawValue),
                    "reason": placement.reason.rawValue
                ]
            ))
        }
    }

    private func hideAll() {
        buttonPanels.values.forEach { $0.orderOut(nil) }
        proxyPanels.values.forEach { $0.orderOut(nil) }
        buttonPanels.removeAll()
        proxyPanels.removeAll()
        lastFrames.removeAll()
        hiddenUntilAfterMovement.removeAll()
    }

    private func isActive(_ window: WindowSnapshot, focusedWindowID: WindowID?) -> Bool {
        if let focusedWindowID {
            return window.id == focusedWindowID
        }
        return window.furniture?.isFocused == true
    }

    nonisolated private static func defaultProxyFrame(for frame: CGRect, settings: PinPopoverSettings) -> CGRect {
        CGRect(
            x: frame.minX,
            y: frame.minY,
            width: max(settings.proxyMinWidth, min(frame.width, 320)),
            height: settings.proxyHeight
        ).integral
    }

    private func hiddenFrame(for frame: CGRect, on display: DisplaySnapshot, among displays: [DisplaySnapshot]) -> CGRect {
        let visible = display.visibleFrame.cgRect
        let displayFrame = display.frame.cgRect
        let useLeft = displays.contains { (other: DisplaySnapshot) in
            let otherFrame = other.frame.cgRect
            return other.id != display.id && abs(otherFrame.maxX - displayFrame.minX) < 2
        }
        if useLeft {
            return CGRect(x: visible.maxX - 1, y: visible.maxY - 1, width: frame.width, height: frame.height).integral
        }
        return CGRect(x: visible.minX + 1 - frame.width, y: visible.maxY - 1, width: frame.width, height: frame.height).integral
    }

    private static func axToNS(_ rect: CGRect) -> CGRect {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let primary else { return rect }
        return CGRect(
            x: rect.minX,
            y: primary.frame.height - rect.minY - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}

@MainActor
private final class PinButtonPanel: NSPanel {
    private let buttonView = PinButtonView()
    var onClick: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = false
        hasShadow = false
        contentView = buttonView
    }

    func render(frame: CGRect, color: NSColor) {
        buttonView.color = color
        setFrame(frame, display: true)
        orderFrontRegardless()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

@MainActor
private final class PinButtonView: NSView {
    var color: NSColor = .systemBlue { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 0.25, dy: 0.25)
        let path = NSBezierPath(ovalIn: rect)

        color.setFill()
        path.fill()

        NSColor.black.withAlphaComponent(0.10).setStroke()
        path.lineWidth = 0.45
        path.stroke()
    }
}

@MainActor
private final class PinProxyPanel: NSPanel {
    private let proxyView = PinProxyView()
    var onClick: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = false
        hasShadow = true
        contentView = proxyView
    }

    func render(frame: CGRect, title: String, color: NSColor) {
        proxyView.title = title
        proxyView.color = color
        setFrame(frame, display: true)
        orderFrontRegardless()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

@MainActor
private final class PinProxyView: NSView {
    var title: String = "" { didSet { needsDisplay = true } }
    var color: NSColor = .systemBlue { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
        path.fill()
        color.withAlphaComponent(0.75).setStroke()
        path.lineWidth = 1
        path.stroke()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        NSString(string: title).draw(
            in: bounds.insetBy(dx: 10, dy: 6),
            withAttributes: attributes
        )
    }
}

private final class PinPopoverMenuTarget: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func choose(_ sender: NSMenuItem) {
        handler()
    }
}

private extension NSColor {
    convenience init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard raw.count == 6 || raw.count == 8,
              let value = UInt64(raw, radix: 16)
        else { return nil }
        let hasAlpha = raw.count == 8
        let red = CGFloat((value >> (hasAlpha ? 24 : 16)) & 0xff) / 255
        let green = CGFloat((value >> (hasAlpha ? 16 : 8)) & 0xff) / 255
        let blue = CGFloat((value >> (hasAlpha ? 8 : 0)) & 0xff) / 255
        let alpha = hasAlpha ? CGFloat(value & 0xff) / 255 : 1
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
