import AppKit
import QuartzCore
import RoadieAX
import RoadieCore
import RoadieTiler

/// Représentation pure d'un onglet dans une stage en mode `.tabbed` (Spec 164).
public struct StageTabItem: Equatable, Sendable {
    public var windowID: WindowID
    public var appName: String
    public var title: String
    public var bundleID: String
    public var isFocused: Bool

    public init(windowID: WindowID, appName: String, title: String, bundleID: String, isFocused: Bool) {
        self.windowID = windowID
        self.appName = appName
        self.title = title
        self.bundleID = bundleID
        self.isFocused = isFocused
    }

    public var displayLabel: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == appName { return appName }
        return "\(appName) — \(trimmed)"
    }
}

/// Cible pure d'une barre d'onglets pour une stage active `.tabbed` comptant au moins 2 fenêtres (Spec 164).
public struct StageTabBarTarget: Equatable, Sendable {
    public var scope: StageScope
    public var frame: CGRect
    public var tabs: [StageTabItem]

    public init(scope: StageScope, frame: CGRect, tabs: [StageTabItem]) {
        self.scope = scope
        self.frame = frame
        self.tabs = tabs
    }
}

/// Frontière de rendu AppKit pour `StageTabBarController`, remplaçable par un espion dans les tests.
@MainActor
protocol StageTabBarRendering: AnyObject {
    func render(_ targets: [StageTabBarTarget], onSelect: @escaping @MainActor (WindowID) -> Void)
    func hideAll()
}

/// Contrôleur de barre d'onglets cliquable pour les stages en mode `.tabbed` (Spec 164).
/// Zéro panneau créé lorsqu'aucune stage active n'est en mode `.tabbed` avec au moins 2 fenêtres.
@MainActor
public final class StageTabBarController {
    private let snapshotService: SnapshotService
    private let configLoader: () -> RoadieConfig
    private let renderer: StageTabBarRendering
    private var observers: [NSObjectProtocol] = []
    private var started = false
    private var isRefreshing = false
    private var needsAnotherRefresh = false
    private var lastObservedRevision: UInt64 = 0
    private var lifecycleGeneration: UInt64 = 0

    public init(
        snapshotService: SnapshotService = SnapshotService(),
        configLoader: @escaping () -> RoadieConfig = { ConfigReloadService.shared.currentConfig() }
    ) {
        self.snapshotService = snapshotService
        self.configLoader = configLoader
        self.renderer = StageTabBarPanelPool()
    }

    init(
        snapshotService: SnapshotService,
        configLoader: @escaping () -> RoadieConfig,
        renderer: StageTabBarRendering
    ) {
        self.snapshotService = snapshotService
        self.configLoader = configLoader
        self.renderer = renderer
    }

    public func start() {
        NSApplication.shared.setActivationPolicy(.accessory)
        if !started {
            started = true
            lifecycleGeneration &+= 1
            installObservers()
        }
        requestRefresh()
    }

    public func stop() {
        started = false
        lifecycleGeneration &+= 1
        needsAnotherRefresh = false
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        renderer.hideAll()
    }

    /// Calcul pur des barres d'onglets à afficher (testable sans AppKit).
    public static func computeTargets(
        snapshot: DaemonSnapshot,
        config: RoadieConfig,
        outerGapsProvider: (Int, DisplaySnapshot) -> Insets,
        frameTransform: ((CGRect) -> CGRect)? = nil
    ) -> [StageTabBarTarget] {
        let transform: (CGRect) -> CGRect = frameTransform ?? { BorderController.axToNS($0) }
        var targets: [StageTabBarTarget] = []
        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.compactMap { entry -> (WindowID, ScopedWindowSnapshot)? in
            guard entry.window.isTileCandidate,
                  entry.window.isOnScreen,
                  entry.window.furniture?.isNativeFullscreen != true,
                  !HiddenWindowPlacement.isHiddenOrLegacyOffscreen(entry.window.frame.cgRect, in: snapshot.displays)
            else { return nil }
            return (entry.window.id, entry)
        })

        for display in snapshot.displays {
            guard let activeScope = snapshot.state.activeScope(on: display.id),
                  let stage = snapshot.state.stage(scope: activeScope),
                  stage.mode == .tabbed
            else { continue }

            let liveWindows = stage.windowIDs.compactMap { id -> WindowSnapshot? in
                guard let entry = windowsByID[id], entry.scope == activeScope else { return nil }
                return entry.window
            }
            guard liveWindows.count >= 2 else { continue }

            let gaps = outerGapsProvider(liveWindows.count, display)
            guard let axBarFrame = TabbedLayoutStrategy.tabBarFrame(
                in: display.visibleFrame.cgRect,
                outerGaps: gaps,
                barHeight: config.tiling.tabbedBarHeight,
                windowCount: liveWindows.count
            ) else { continue }

            let focusedID = snapshot.focusedWindowID.flatMap { id in
                liveWindows.contains(where: { $0.id == id }) ? id : nil
            } ?? stage.focusedWindowID.flatMap { id in
                liveWindows.contains(where: { $0.id == id }) ? id : nil
            } ?? liveWindows.first?.id

            let tabs = liveWindows.map { window in
                StageTabItem(
                    windowID: window.id,
                    appName: window.appName,
                    title: window.title,
                    bundleID: window.bundleID,
                    isFocused: window.id == focusedID
                )
            }
            targets.append(StageTabBarTarget(
                scope: activeScope,
                frame: transform(axBarFrame),
                tabs: tabs
            ))
        }
        return targets
    }

    private func installObservers() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .roadieSnapshotDidPublish, object: nil, queue: .main
        ) { [weak self] notification in
            let revision = notification.userInfo?["revision"] as? UInt64
            Task { @MainActor in
                guard let self, self.started else { return }
                if let revision, revision == self.lastObservedRevision { return }
                self.requestRefresh()
            }
        })
        for name: Notification.Name in [
            .roadieConfigDidReload,
            .roadieSettingsDidChange,
            NSApplication.didChangeScreenParametersNotification,
        ] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.started else { return }
                    self.requestRefresh()
                }
            })
        }
    }

    private func requestRefresh() {
        guard started else { return }
        if isRefreshing {
            needsAnotherRefresh = true
            return
        }
        let generation = lifecycleGeneration
        Task { @MainActor [weak self] in
            guard let self, self.started, self.lifecycleGeneration == generation else { return }
            await self.refresh()
        }
    }

    func refresh() async {
        guard !isRefreshing else {
            if started { needsAnotherRefresh = true }
            return
        }
        let generation = lifecycleGeneration
        let wasStarted = started
        isRefreshing = true
        defer {
            isRefreshing = false
            if needsAnotherRefresh, started, lifecycleGeneration == generation {
                needsAnotherRefresh = false
                requestRefresh()
            } else {
                needsAnotherRefresh = false
            }
        }
        guard let snapshot = await snapshotService.readerSnapshot() else { return }
        if wasStarted { guard started, lifecycleGeneration == generation else { return } }
        lastObservedRevision = snapshotService.publicationRevision
        let config = configLoader()
        let targets = Self.computeTargets(
            snapshot: snapshot,
            config: config,
            outerGapsProvider: { count, display in
                self.snapshotService.effectiveOuterGaps(windowCount: count, display: display)
            }
        )
        if targets.isEmpty {
            renderer.hideAll()
            return
        }
        let service = snapshotService
        renderer.render(targets) { windowID in
            Task.detached(priority: .userInitiated) {
                _ = WindowCommandService(service: service).focus(windowID: windowID)
            }
        }
    }
}

// MARK: - Rendu AppKit

@MainActor
private final class StageTabBarPanelPool: StageTabBarRendering {
    private var panels: [StageScope: StageTabBarPanel] = [:]

    func render(_ targets: [StageTabBarTarget], onSelect: @escaping @MainActor (WindowID) -> Void) {
        guard !targets.isEmpty else {
            hideAll()
            return
        }
        let activeScopes = Set(targets.map(\.scope))
        for (scope, panel) in panels where !activeScopes.contains(scope) {
            panel.orderOut(nil)
            panels.removeValue(forKey: scope)
        }
        for target in targets {
            let panel = panels[target.scope] ?? {
                let created = StageTabBarPanel()
                panels[target.scope] = created
                return created
            }()
            panel.apply(target, onSelect: onSelect)
        }
    }

    func hideAll() {
        guard !panels.isEmpty else { return }
        for panel in panels.values {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }
}

@MainActor
private final class StageTabBarPanel: NSPanel {
    private let stackView = NSStackView()
    private var buttonTargets: [StageTabButtonTarget] = []
    private var lastTarget: StageTabBarTarget?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hasShadow = true

        let container = NSVisualEffectView()
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fillEqually
        stackView.spacing = 4
        stackView.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: container.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        contentView = container
    }

    func apply(_ target: StageTabBarTarget, onSelect: @escaping @MainActor (WindowID) -> Void) {
        if frame != target.frame {
            setFrame(target.frame, display: false)
        }
        if lastTarget?.tabs != target.tabs {
            lastTarget = target
            rebuildButtons(tabs: target.tabs, onSelect: onSelect)
        }
        orderFrontRegardless()
    }

    private func rebuildButtons(tabs: [StageTabItem], onSelect: @escaping @MainActor (WindowID) -> Void) {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        buttonTargets.removeAll()
        let iconCache = SharedAppIconCache.shared
        for tab in tabs {
            let button = NSButton(frame: .zero)
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.lineBreakMode = .byTruncatingTail
            button.alignment = .left
            button.imagePosition = .imageLeading
            button.wantsLayer = true
            button.layer?.cornerRadius = 6
            button.layer?.backgroundColor = tab.isFocused
                ? NSColor.controlAccentColor.withAlphaComponent(0.32).cgColor
                : NSColor.white.withAlphaComponent(0.06).cgColor
            button.font = .systemFont(ofSize: 12, weight: tab.isFocused ? .semibold : .regular)
            button.contentTintColor = tab.isFocused ? .labelColor : .secondaryLabelColor
            button.title = " " + tab.displayLabel
            if let icon = iconCache.cleanedIcon(for: tab.bundleID) {
                let sized = icon.copy() as? NSImage ?? icon
                sized.size = NSSize(width: 14, height: 14)
                button.image = sized
            }
            let target = StageTabButtonTarget {
                onSelect(tab.windowID)
            }
            button.target = target
            button.action = #selector(StageTabButtonTarget.press(_:))
            buttonTargets.append(target)
            stackView.addArrangedSubview(button)
        }
    }
}

@MainActor
private final class StageTabButtonTarget: NSObject {
    private let handler: () -> Void
    init(handler: @escaping () -> Void) { self.handler = handler }
    @objc func press(_ sender: Any?) { handler() }
}
