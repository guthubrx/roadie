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

    public var hasAnyDestinationFamily: Bool {
        includeStageDestinations || includeDesktopDestinations || includeDisplayDestinations
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
    case pinDesktop = "pin_desktop"
    case pinAllDesktops = "pin_all_desktops"
    case unpin
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

    public init(
        snapshotService: SnapshotService = SnapshotService(),
        actions: WindowContextActions = WindowContextActions(),
        configLoader: @escaping () -> RoadieConfig = { (try? RoadieConfigLoader.load()) ?? RoadieConfig() },
        events: EventLog = EventLog()
    ) {
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
            return self.handleRightMouseDown(at: NSEvent.mouseLocation, source: "local") ? nil : event
        }) {
            monitors.append(local)
            debug("local-monitor=installed")
        } else {
            debug("local-monitor=failed")
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown], handler: { [weak self] _ in
            DispatchQueue.main.async {
                _ = self?.handleRightMouseDown(at: NSEvent.mouseLocation, source: "global")
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

    @discardableResult
    public func handleRightMouseDown(at point: CGPoint, source: String = "unknown") -> Bool {
        let settings = TitlebarContextMenuSettings(config: configLoader().experimental.titlebarContextMenu)
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
        let menu = buildMenu(windowID: windowID, sourceScope: hit.scope, destinations: destinations, pin: pin)
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
        guard let entry = window(at: point, in: snapshot) else {
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

    nonisolated private static func window(at point: CGPoint, in snapshot: DaemonSnapshot) -> ScopedWindowSnapshot? {
        snapshot.windows
            .filter { $0.window.isOnScreen && $0.window.frame.cgRect.contains(point) }
            .sorted {
                let lhsArea = $0.window.frame.width * $0.window.frame.height
                let rhsArea = $1.window.frame.width * $1.window.frame.height
                if lhsArea == rhsArea { return $0.window.id > $1.window.id }
                return lhsArea < rhsArea
            }
            .first
    }

    private func buildMenu(
        windowID: WindowID,
        sourceScope: StageScope?,
        destinations: [WindowDestination],
        pin: PersistentWindowPin?
    ) -> NSMenu {
        menuTargets.removeAll(keepingCapacity: true)
        let menu = NSMenu(title: "Roadie")
        addWindowSubmenu(windowID: windowID, sourceScope: sourceScope, pin: pin, to: menu)
        addSubmenu(title: "Envoyer la fenêtre vers stage", kind: .stage, windowID: windowID, sourceScope: sourceScope, destinations: destinations, to: menu)
        addDesktopStageSubmenu(windowID: windowID, sourceScope: sourceScope, destinations: destinations, to: menu)
        addSubmenu(title: "Envoyer la fenêtre vers desktop", kind: .desktop, windowID: windowID, sourceScope: sourceScope, destinations: destinations, to: menu)
        addSubmenu(title: "Envoyer la fenêtre vers écran", kind: .display, windowID: windowID, sourceScope: sourceScope, destinations: destinations, to: menu)
        return menu
    }

    private func addWindowSubmenu(
        windowID: WindowID,
        sourceScope: StageScope?,
        pin: PersistentWindowPin?,
        to menu: NSMenu
    ) {
        let parent = NSMenuItem(title: "Fenêtre", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Fenêtre")
        if let pin {
            let stateItem = NSMenuItem(
                title: pin.pinScope == .desktop ? "Pin actuel : ce desktop" : "Pin actuel : tous les desktops",
                action: nil,
                keyEquivalent: ""
            )
            stateItem.isEnabled = false
            submenu.addItem(stateItem)
            submenu.addItem(.separator())
            addActionItem(
                title: pin.pinScope == .desktop ? "Pin sur tous les desktops" : "Pin sur ce desktop",
                kind: pin.pinScope == .desktop ? .pinAllDesktops : .pinDesktop,
                windowID: windowID,
                sourceScope: sourceScope,
                to: submenu
            )
            addActionItem(title: "Retirer le pin", kind: .unpin, windowID: windowID, sourceScope: sourceScope, to: submenu)
        } else {
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
        to menu: NSMenu
    ) {
        let item = NSMenuItem(title: title, action: #selector(TitlebarMenuActionTarget.choose(_:)), keyEquivalent: "")
        item.representedObject = kind.rawValue
        let target = TitlebarMenuActionTarget { [weak self] targetID in
            guard let self else { return }
            let action = WindowContextAction(windowID: windowID, kind: kind, targetID: targetID, sourceScope: sourceScope)
            let result = self.actions.execute(action)
            self.events.append(RoadieEvent(
                type: result.changed ? "titlebar_context_menu.action" : "titlebar_context_menu.failed",
                scope: sourceScope,
                details: [
                    "windowID": String(windowID.rawValue),
                    "kind": kind.rawValue,
                    "targetID": targetID,
                    "result": result.changed ? "changed" : "failed",
                    "message": result.message
                ]
            ))
        }
        item.target = target
        menuTargets.append(target)
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
            let target = TitlebarMenuActionTarget { [weak self] targetID in
                guard let self else { return }
                let action = WindowContextAction(windowID: windowID, kind: kind, targetID: targetID, sourceScope: sourceScope)
                let result = self.actions.execute(action)
                self.events.append(RoadieEvent(
                    type: result.changed ? "titlebar_context_menu.action" : "titlebar_context_menu.failed",
                    scope: sourceScope,
                    details: [
                        "windowID": String(windowID.rawValue),
                        "kind": kind.rawValue,
                        "targetID": targetID,
                        "result": result.changed ? "changed" : "failed",
                        "message": result.message
                    ]
                ))
            }
            item.target = target
            menuTargets.append(target)
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
                let target = TitlebarMenuActionTarget { [weak self] targetID in
                    guard let self else { return }
                    let action = WindowContextAction(windowID: windowID, kind: .desktopStage, targetID: targetID, sourceScope: sourceScope)
                    let result = self.actions.execute(action)
                    self.events.append(RoadieEvent(
                        type: result.changed ? "titlebar_context_menu.action" : "titlebar_context_menu.failed",
                        scope: sourceScope,
                        details: [
                            "windowID": String(windowID.rawValue),
                            "kind": WindowContextActionKind.desktopStage.rawValue,
                            "targetID": targetID,
                            "result": result.changed ? "changed" : "failed",
                            "message": result.message
                        ]
                    ))
                }
                item.target = target
                menuTargets.append(target)
                stageMenu.addItem(item)
            }
            desktopItem.submenu = stageMenu
            submenu.addItem(desktopItem)
        }
        parent.submenu = submenu
        menu.addItem(parent)
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
