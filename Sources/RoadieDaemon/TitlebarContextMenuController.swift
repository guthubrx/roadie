import AppKit
import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore

public struct TitlebarContextMenuSettings: Equatable, Sendable {
    public var enabled: Bool
    public var height: CGFloat
    public var leadingExclusion: CGFloat
    public var trailingExclusion: CGFloat
    public var managedWindowsOnly: Bool
    public var tileCandidatesOnly: Bool
    public var includeStageDestinations: Bool
    public var includeDesktopDestinations: Bool
    public var includeDisplayDestinations: Bool

    public init(
        enabled: Bool = false,
        height: CGFloat = 36,
        leadingExclusion: CGFloat = 84,
        trailingExclusion: CGFloat = 16,
        managedWindowsOnly: Bool = true,
        tileCandidatesOnly: Bool = true,
        includeStageDestinations: Bool = true,
        includeDesktopDestinations: Bool = true,
        includeDisplayDestinations: Bool = true
    ) {
        self.enabled = enabled
        self.height = height
        self.leadingExclusion = leadingExclusion
        self.trailingExclusion = trailingExclusion
        self.managedWindowsOnly = managedWindowsOnly
        self.tileCandidatesOnly = tileCandidatesOnly
        self.includeStageDestinations = includeStageDestinations
        self.includeDesktopDestinations = includeDesktopDestinations
        self.includeDisplayDestinations = includeDisplayDestinations
    }

    public init(config: TitlebarContextMenuConfig) {
        self.init(
            enabled: config.enabled,
            height: CGFloat(config.height),
            leadingExclusion: CGFloat(config.leadingExclusion),
            trailingExclusion: CGFloat(config.trailingExclusion),
            managedWindowsOnly: config.managedWindowsOnly,
            tileCandidatesOnly: config.tileCandidatesOnly,
            includeStageDestinations: config.includeStageDestinations,
            includeDesktopDestinations: config.includeDesktopDestinations,
            includeDisplayDestinations: config.includeDisplayDestinations
        )
    }
}

public enum TitlebarHitTestReason: String, Equatable, Codable, Sendable {
    case disabled
    case noWindow = "no_window"
    case notManaged = "not_managed"
    case notTitlebar = "not_titlebar"
    case excludedMargin = "excluded_margin"
    case transient
    case noDestination = "no_destination"
    case eligible
}

public struct TitlebarHitTest: Equatable, Sendable {
    public var screenPoint: CGPoint
    public var windowID: WindowID?
    public var isEligible: Bool
    public var reason: TitlebarHitTestReason
    public var window: WindowSnapshot?
    public var scope: StageScope?

    public init(
        screenPoint: CGPoint,
        windowID: WindowID?,
        isEligible: Bool,
        reason: TitlebarHitTestReason,
        window: WindowSnapshot? = nil,
        scope: StageScope? = nil
    ) {
        self.screenPoint = screenPoint
        self.windowID = windowID
        self.isEligible = isEligible
        self.reason = reason
        self.window = window
        self.scope = scope
    }
}

public enum WindowContextActionKind: String, Equatable, Codable, Sendable {
    case stage
    case desktop
    case desktopStage = "desktop_stage"
    case display
    case floatStage = "float_stage"
    case pinDesktop = "pin_desktop"
    case pinAllDesktops = "pin_all_desktops"
    case unpin
    case maximize
    case affinityApp = "affinity_app"
    case affinityAppTitle = "affinity_app_title"
    case removeAffinityApp = "remove_affinity_app"
}

public struct WindowContextAction: Equatable, Sendable {
    public var windowID: WindowID
    public var kind: WindowContextActionKind
    public var targetID: String
    public var sourceScope: StageScope?

    public init(windowID: WindowID, kind: WindowContextActionKind, targetID: String, sourceScope: StageScope?) {
        self.windowID = windowID
        self.kind = kind
        self.targetID = targetID
        self.sourceScope = sourceScope
    }
}

public struct WindowDestination: Equatable, Sendable {
    public var kind: WindowContextActionKind
    public var id: String
    public var label: String
    public var isCurrent: Bool
    public var isAvailable: Bool
    public var parentID: String?
    public var parentLabel: String?

    public init(
        kind: WindowContextActionKind,
        id: String,
        label: String,
        isCurrent: Bool,
        isAvailable: Bool = true,
        parentID: String? = nil,
        parentLabel: String? = nil
    ) {
        self.kind = kind
        self.id = id
        self.label = label
        self.isCurrent = isCurrent
        self.isAvailable = isAvailable
        self.parentID = parentID
        self.parentLabel = parentLabel
    }
}

@MainActor
public final class TitlebarContextMenuController {
    private let snapshotService: SnapshotService
    private let actions: WindowContextActions
    private let configLoader: () -> RoadieConfig
    private let events: EventLog
    private var monitors: [Any] = []
    private var menuTargets: [TitlebarMenuActionTarget] = []
    private var lastIgnoredAt: [String: Date] = [:]
    private let readPreference: (_ domain: String, _ key: String) -> Any?
    /// Rôle AX de l'élément sous un point en coordonnées AX (SPEC-050), injectable pour les tests.
    private let elementRoleAt: (CGPoint) -> String?

    public init(
        snapshotService: SnapshotService = SnapshotService(),
        actions: WindowContextActions = WindowContextActions(),
        configLoader: @escaping () -> RoadieConfig = { ConfigReloadService.shared.currentConfig() },
        events: EventLog = EventLog(),
        readPreference: @escaping (_ domain: String, _ key: String) -> Any? = { domain, key in
            CFPreferencesCopyAppValue(key as CFString, domain as CFString)
        },
        elementRoleAt: @escaping (CGPoint) -> String? = TitlebarContextMenuController.liveElementRole
    ) {
        self.readPreference = readPreference
        self.elementRoleAt = elementRoleAt
        self.snapshotService = snapshotService
        self.actions = actions
        self.configLoader = configLoader
        self.events = events
    }

    public func start() {
        guard monitors.isEmpty else { return }
        NSApplication.shared.setActivationPolicy(.accessory)
        let config = configLoader().experimental.titlebarContextMenu
        debug("start enabled=\(config.enabled) height=\(config.height) leading=\(config.leadingExclusion) trailing=\(config.trailingExclusion)")
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown], handler: { [weak self] event in
            guard let self else { return event }
            return self.handleRightMouseDown(at: RoadieScreenCoordinate.mouseEventPoint(event), source: "local") ? nil : event
        }) {
            monitors.append(local)
            debug("local-monitor=installed")
        } else {
            debug("local-monitor=failed")
        }
        // SPEC-050 : un clic simple ne coûte qu'une comparaison ; seul un double-clic lit l'état.
        if let doubleClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] event in
            guard event.clickCount == 2 else { return }
            let point = RoadieScreenCoordinate.mouseEventPoint(event)
            DispatchQueue.main.async {
                _ = self?.handleDoubleClick(at: point, clickCount: 2)
            }
        }) {
            monitors.append(doubleClick)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown], handler: { [weak self] event in
            let point = RoadieScreenCoordinate.mouseEventPoint(event)
            DispatchQueue.main.async {
                _ = self?.handleRightMouseDown(at: point, source: "global")
            }
        }) {
            monitors.append(global)
            debug("global-monitor=installed")
        } else {
            debug("global-monitor=failed")
        }
    }

    public func stop() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        menuTargets.removeAll()
        lastIgnoredAt.removeAll()
    }

    /// Vrai si Roadie doit traiter ce clic : double-clic exact, réglage actif, et macOS sans action
    /// sur ce double-clic (sinon les deux agiraient). O(1).
    nonisolated static func handlesDoubleClick(clickCount: Int, enabled: Bool, macOSAction: MacOSDoubleClickAction) -> Bool {
        clickCount == 2 && enabled && macOSAction == .none
    }

    /// Rôles AX qui gardent leur propre double-clic (sélection d'un mot, bouton, onglet, lien,
    /// contenu web) : la maximisation ne doit pas les remplacer.
    nonisolated static let interactiveRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXComboBox", "AXButton", "AXPopUpButton", "AXMenuButton",
        "AXRadioButton", "AXCheckBox", "AXTabGroup", "AXRadioGroup", "AXLink", "AXWebArea",
        "AXSlider", "AXIncrementor", "AXDisclosureTriangle",
    ]

    /// Cible valide : fenêtre tuilée (une fenêtre flottante garde sa taille, SPEC-047) et
    /// élément sous le pointeur non interactif. O(1).
    nonisolated static func isDoubleClickTarget(pinned: Bool, role: String?) -> Bool {
        !pinned && !(role.map(interactiveRoles.contains) ?? false)
    }

    nonisolated public static func liveElementRole(at point: CGPoint) -> String? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y),
                                               &element) == .success, let element else { return nil }
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success else { return nil }
        return role as? String
    }

    /// Double-clic sur la barre de titre d'une fenêtre gérée : maximisation Roadie (SPEC-050).
    /// Même zone et mêmes filtres que le menu par clic droit, même si ce menu est désactivé.
    @discardableResult
    public func handleDoubleClick(at point: CGPoint, clickCount: Int) -> Bool {
        let config = configLoader().experimental.titlebarContextMenu
        guard Self.handlesDoubleClick(clickCount: clickCount, enabled: config.doubleClickMaximize,
                                      macOSAction: MacOSWindowSetting.doubleClickAction(read: readPreference))
        else { return false }
        var settings = TitlebarContextMenuSettings(config: config)
        settings.enabled = true
        let snapshot = snapshotService.snapshot()
        let axPoint = Self.appKitPointToAX(point)
        let hit = Self.hitTest(point: axPoint, snapshot: snapshot, settings: settings)
        guard hit.isEligible, let windowID = hit.windowID,
              Self.isDoubleClickTarget(pinned: snapshot.windows.first { $0.window.id == windowID }?.pin != nil,
                                       role: elementRoleAt(axPoint))
        else { return false }
        let result = WindowCommandService(service: snapshotService).toggleMaximize(windowID: windowID)
        events.append(RoadieEvent(
            type: "titlebar_context_menu.action",
            scope: hit.scope,
            details: ["action": "double_click_maximize", "windowID": String(windowID.rawValue), "message": result.message]
        ))
        return true
    }

    @discardableResult
    public func handleRightMouseDown(at point: CGPoint, source: String = "unknown") -> Bool {
        let settings = TitlebarContextMenuSettings(config: configLoader().experimental.titlebarContextMenu)
        // Menu désactivé (défaut) : aucun relevé des fenêtres ni réconciliation d'état à chaque
        // clic droit. Les moniteurs restent installés pour suivre un rechargement à chaud.
        guard settings.enabled else { return false }
        let snapshot = snapshotService.snapshot()
        let axPoint = Self.appKitPointToAX(point)
        let hit = Self.hitTest(point: axPoint, snapshot: snapshot, settings: settings)
        traceClick(source: source, rawPoint: point, axPoint: axPoint, hit: hit, snapshot: snapshot, settings: settings)
        guard hit.isEligible, let window = hit.window, let windowID = hit.windowID else {
            logIgnored(hit: hit, window: hit.window)
            return false
        }

        let destinations = actions.destinations(for: windowID, in: snapshot, settings: settings)
        let pin = snapshot.windows.first(where: { $0.window.id == windowID })?.pin
        let menu = buildMenu(window: window, windowID: windowID, sourceScope: hit.scope, destinations: destinations, pin: pin)
        guard menu.items.contains(where: { $0.submenu != nil }) else {
            var noDestination = hit
            noDestination.isEligible = false
            noDestination.reason = .noDestination
            logIgnored(hit: noDestination, window: window)
            return false
        }

        events.append(RoadieEvent(
            type: "titlebar_context_menu.shown",
            scope: hit.scope,
            details: eventDetails(window: window, reason: .eligible)
        ))
        _ = menu.popUp(positioning: nil, at: point, in: nil)
        return true
    }

    nonisolated public static func appKitPointToAX(_ point: CGPoint) -> CGPoint {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let primary else { return point }
        return CGPoint(x: point.x, y: primary.frame.height - point.y)
    }

    nonisolated public static func hitTest(
        point: CGPoint,
        snapshot: DaemonSnapshot,
        settings: TitlebarContextMenuSettings
    ) -> TitlebarHitTest {
        guard settings.enabled else {
            return TitlebarHitTest(screenPoint: point, windowID: nil, isEligible: false, reason: .disabled)
        }
        guard let entry = FocusFollowsMousePicker.frontWindow(at: point, in: snapshot) else {
            return TitlebarHitTest(screenPoint: point, windowID: nil, isEligible: false, reason: .noWindow)
        }
        if settings.managedWindowsOnly, entry.scope == nil {
            return TitlebarHitTest(
                screenPoint: point,
                windowID: entry.window.id,
                isEligible: false,
                reason: .notManaged,
                window: entry.window,
                scope: entry.scope
            )
        }
        if settings.tileCandidatesOnly, !entry.window.isTileCandidate {
            return TitlebarHitTest(
                screenPoint: point,
                windowID: entry.window.id,
                isEligible: false,
                reason: .transient,
                window: entry.window,
                scope: entry.scope
            )
        }
        let frame = entry.window.frame.cgRect
        let distanceFromTop = point.y - frame.minY
        guard distanceFromTop >= 0, distanceFromTop <= settings.height else {
            return TitlebarHitTest(
                screenPoint: point,
                windowID: entry.window.id,
                isEligible: false,
                reason: .notTitlebar,
                window: entry.window,
                scope: entry.scope
            )
        }
        let distanceFromLeft = point.x - frame.minX
        let distanceFromRight = frame.maxX - point.x
        if distanceFromLeft < settings.leadingExclusion || distanceFromRight < settings.trailingExclusion {
            return TitlebarHitTest(
                screenPoint: point,
                windowID: entry.window.id,
                isEligible: false,
                reason: .excludedMargin,
                window: entry.window,
                scope: entry.scope
            )
        }
        return TitlebarHitTest(
            screenPoint: point,
            windowID: entry.window.id,
            isEligible: true,
            reason: .eligible,
            window: entry.window,
            scope: entry.scope
        )
    }

    private func buildMenu(
        window: WindowSnapshot,
        windowID: WindowID,
        sourceScope: StageScope?,
        destinations: [WindowDestination],
        pin: PersistentWindowPin?
    ) -> NSMenu {
        menuTargets.removeAll(keepingCapacity: true)
        let menu = NSMenu(title: "Roadie")
        addWindowSubmenu(windowID: windowID, sourceScope: sourceScope, pin: pin, to: menu)
        addAffinitySubmenu(window: window, windowID: windowID, sourceScope: sourceScope, to: menu)
        addSubmenu(title: "Envoyer la fenêtre vers stage", kind: .stage, windowID: windowID, sourceScope: sourceScope, destinations: destinations, to: menu)
        addDesktopStageSubmenu(windowID: windowID, sourceScope: sourceScope, destinations: destinations, to: menu)
        addSubmenu(title: "Envoyer la fenêtre vers desktop", kind: .desktop, windowID: windowID, sourceScope: sourceScope, destinations: destinations, to: menu)
        addSubmenu(title: "Envoyer la fenêtre vers écran", kind: .display, windowID: windowID, sourceScope: sourceScope, destinations: destinations, to: menu)
        return menu
    }

    private func addAffinitySubmenu(
        window: WindowSnapshot,
        windowID: WindowID,
        sourceScope: StageScope?,
        to menu: NSMenu
    ) {
        guard sourceScope != nil else { return }
        let parent = NSMenuItem(title: "Affinité d'ouverture", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: parent.title)
        addActionItem(
            title: "Toujours ouvrir cette app ici",
            kind: .affinityApp,
            windowID: windowID,
            sourceScope: sourceScope,
            to: submenu
        )
        addActionItem(
            title: "Toujours ouvrir cette app + ce titre ici",
            kind: .affinityAppTitle,
            windowID: windowID,
            sourceScope: sourceScope,
            isEnabled: !window.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            to: submenu
        )
        submenu.addItem(.separator())
        addActionItem(
            title: "Retirer l'affinité pour cette app",
            kind: .removeAffinityApp,
            windowID: windowID,
            sourceScope: sourceScope,
            to: submenu
        )
        parent.submenu = submenu
        menu.addItem(parent)
    }

    private func addWindowSubmenu(
        windowID: WindowID,
        sourceScope: StageScope?,
        pin: PersistentWindowPin?,
        to menu: NSMenu
    ) {
        let parent = NSMenuItem(title: "Fenêtre", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Fenêtre")
        addActionItem(
            title: "Maximiser / restaurer (garder le navrail)",
            kind: .maximize,
            windowID: windowID,
            sourceScope: sourceScope,
            to: submenu
        )
        submenu.addItem(.separator())
        if let pin {
            let stateTitle: String
            switch pin.pinScope {
            case .stage: stateTitle = "État actuel : flottante dans cette stage"
            case .desktop: stateTitle = "Pin actuel : ce desktop"
            case .allDesktops: stateTitle = "Pin actuel : tous les desktops"
            }
            let stateItem = NSMenuItem(title: stateTitle, action: nil, keyEquivalent: "")
            stateItem.isEnabled = false
            submenu.addItem(stateItem)
            submenu.addItem(.separator())
            let choices: [(String, WindowContextActionKind, WindowPinScope)] = [
                ("Flotter dans cette stage", .floatStage, .stage),
                ("Pin sur ce desktop", .pinDesktop, .desktop),
                ("Pin sur tous les desktops", .pinAllDesktops, .allDesktops)
            ]
            for (title, kind, scope) in choices where scope != pin.pinScope {
                addActionItem(title: title, kind: kind, windowID: windowID, sourceScope: sourceScope, to: submenu)
            }
            addActionItem(
                title: pin.pinScope == .stage ? "Revenir au tuilage" : "Retirer le pin",
                kind: .unpin,
                windowID: windowID,
                sourceScope: sourceScope,
                to: submenu
            )
        } else {
            addActionItem(title: "Flotter dans cette stage", kind: .floatStage, windowID: windowID, sourceScope: sourceScope, to: submenu)
            addActionItem(title: "Pin sur ce desktop", kind: .pinDesktop, windowID: windowID, sourceScope: sourceScope, to: submenu)
            addActionItem(title: "Pin sur tous les desktops", kind: .pinAllDesktops, windowID: windowID, sourceScope: sourceScope, to: submenu)
        }
        parent.submenu = submenu
        menu.addItem(parent)
    }

    private func addActionItem(
        title: String,
        kind: WindowContextActionKind,
        windowID: WindowID,
        sourceScope: StageScope?,
        isEnabled: Bool = true,
        to menu: NSMenu
    ) {
        let item = NSMenuItem(title: title, action: #selector(TitlebarMenuActionTarget.choose(_:)), keyEquivalent: "")
        item.representedObject = kind.rawValue
        item.isEnabled = isEnabled
        item.target = actionTarget(windowID: windowID, kind: kind, sourceScope: sourceScope)
        menu.addItem(item)
    }

    private func addSubmenu(
        title: String,
        kind: WindowContextActionKind,
        windowID: WindowID,
        sourceScope: StageScope?,
        destinations: [WindowDestination],
        to menu: NSMenu
    ) {
        let filtered = destinations.filter { $0.kind == kind && !$0.isCurrent && $0.isAvailable }
        guard !filtered.isEmpty else { return }
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        for destination in filtered {
            let item = NSMenuItem(title: destination.label, action: #selector(TitlebarMenuActionTarget.choose(_:)), keyEquivalent: "")
            item.representedObject = destination.id
            item.target = actionTarget(windowID: windowID, kind: kind, sourceScope: sourceScope)
            submenu.addItem(item)
        }
        parent.submenu = submenu
        menu.addItem(parent)
    }

    private func addDesktopStageSubmenu(
        windowID: WindowID,
        sourceScope: StageScope?,
        destinations: [WindowDestination],
        to menu: NSMenu
    ) {
        let filtered = destinations.filter { $0.kind == .desktopStage && !$0.isCurrent && $0.isAvailable }
        guard !filtered.isEmpty else { return }
        let parent = NSMenuItem(title: "Envoyer la fenêtre vers desktop/stage", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: parent.title)
        let grouped = Dictionary(grouping: filtered) { destination in
            destination.parentID ?? ""
        }
        var parentLabels: [String: String] = [:]
        for destination in filtered {
            guard let parentID = destination.parentID else { continue }
            parentLabels[parentID] = destination.parentLabel ?? "Desktop \(parentID)"
        }
        for desktopID in grouped.keys.sorted(by: desktopSort) {
            guard let stages = grouped[desktopID]?.sorted(by: { $0.label < $1.label }) else { continue }
            let desktopItem = NSMenuItem(title: parentLabels[desktopID] ?? "Desktop \(desktopID)", action: nil, keyEquivalent: "")
            let stageMenu = NSMenu(title: desktopItem.title)
            for destination in stages {
                let item = NSMenuItem(title: destination.label, action: #selector(TitlebarMenuActionTarget.choose(_:)), keyEquivalent: "")
                item.representedObject = destination.id
                item.target = actionTarget(windowID: windowID, kind: .desktopStage, sourceScope: sourceScope)
                stageMenu.addItem(item)
            }
            desktopItem.submenu = stageMenu
            submenu.addItem(desktopItem)
        }
        parent.submenu = submenu
        menu.addItem(parent)
    }

    /// Cible d'un élément de menu, retenue jusqu'au prochain menu. L'identifiant de destination
    /// arrive par `representedObject`.
    private func actionTarget(windowID: WindowID, kind: WindowContextActionKind, sourceScope: StageScope?) -> TitlebarMenuActionTarget {
        let target = TitlebarMenuActionTarget { [weak self] targetID in
            self?.executeAndLog(WindowContextAction(windowID: windowID, kind: kind, targetID: targetID, sourceScope: sourceScope))
        }
        menuTargets.append(target)
        return target
    }

    /// Exécute l'action choisie dans le menu et journalise son résultat, quel que soit le sous-menu.
    func executeAndLog(_ action: WindowContextAction) {
        let result = actions.execute(action)
        events.append(RoadieEvent(
            type: result.changed ? "titlebar_context_menu.action" : "titlebar_context_menu.failed",
            scope: action.sourceScope,
            details: [
                "windowID": String(action.windowID.rawValue),
                "kind": action.kind.rawValue,
                "targetID": action.targetID,
                "result": result.changed ? "changed" : "failed",
                "message": result.message
            ]
        ))
    }

    private func desktopSort(_ lhs: String, _ rhs: String) -> Bool {
        switch (Int(lhs), Int(rhs)) {
        case let (l?, r?): return l < r
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return lhs < rhs
        }
    }

    private func logIgnored(hit: TitlebarHitTest, window: WindowSnapshot?) {
        guard shouldLogIgnored(hit) else { return }
        events.append(RoadieEvent(
            type: "titlebar_context_menu.ignored",
            scope: hit.scope,
            details: eventDetails(window: window, reason: hit.reason)
        ))
    }

    private func shouldLogIgnored(_ hit: TitlebarHitTest) -> Bool {
        switch hit.reason {
        case .disabled, .notTitlebar:
            return false
        case .eligible:
            return true
        case .noWindow, .notManaged, .excludedMargin, .transient, .noDestination:
            let key = "\(hit.windowID.map { String($0.rawValue) } ?? "-"):\(hit.reason.rawValue)"
            let now = Date()
            if let previous = lastIgnoredAt[key], now.timeIntervalSince(previous) < 2 {
                return false
            }
            lastIgnoredAt[key] = now
            return true
        }
    }

    private func traceClick(
        source: String,
        rawPoint: CGPoint,
        axPoint: CGPoint,
        hit: TitlebarHitTest,
        snapshot: DaemonSnapshot,
        settings: TitlebarContextMenuSettings
    ) {
        let windowSummary: String
        if let window = hit.window {
            windowSummary = "window=\(window.id.rawValue) app=\(window.appName) frame=\(window.frame.x),\(window.frame.y),\(window.frame.width),\(window.frame.height)"
        } else {
            windowSummary = "window=-"
        }
        debug(
            "click source=\(source) raw=\(Int(rawPoint.x)),\(Int(rawPoint.y)) ax=\(Int(axPoint.x)),\(Int(axPoint.y)) enabled=\(settings.enabled) windows=\(snapshot.windows.count) reason=\(hit.reason.rawValue) eligible=\(hit.isEligible) \(windowSummary)"
        )
    }

    private func eventDetails(window: WindowSnapshot?, reason: TitlebarHitTestReason) -> [String: String] {
        var details = ["reason": reason.rawValue]
        if let window {
            details["windowID"] = String(window.id.rawValue)
            details["bundleID"] = window.bundleID
            details["title"] = window.title
        }
        return details
    }

    private func debug(_ message: String) {
        fputs("roadied: titlebar-context-menu \(message)\n", stderr)
        fflush(stderr)
    }
}

private final class TitlebarMenuActionTarget: NSObject {
    private let handler: (String) -> Void

    init(handler: @escaping (String) -> Void) {
        self.handler = handler
    }

    @objc func choose(_ sender: NSMenuItem) {
        guard let targetID = sender.representedObject as? String else { return }
        handler(targetID)
    }
}
