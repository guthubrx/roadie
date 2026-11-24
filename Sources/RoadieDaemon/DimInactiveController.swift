import AppKit
import QuartzCore
import RoadieAX
import RoadieCore

/// Cible d'assombrissement pour une fenêtre inactive visible (Spec 162). Pur et comparable dans les tests.
public struct DimInactiveTarget: Equatable, Sendable {
    public var windowID: WindowID
    public var frame: CGRect
    public var opacity: CGFloat
    public var cornerRadius: CGFloat

    public init(windowID: WindowID, frame: CGRect, opacity: CGFloat, cornerRadius: CGFloat) {
        self.windowID = windowID
        self.frame = frame
        self.opacity = opacity
        self.cornerRadius = cornerRadius
    }
}

/// Frontière de rendu AppKit pour `DimInactiveController`, remplaçable par un espion dans les tests.
@MainActor
protocol DimInactiveRendering: AnyObject {
    func render(_ targets: [DimInactiveTarget])
    func hideAll()
}

/// Assombrissement léger et traversant aux clics des fenêtres tuilées visibles non focalisées (Spec 162).
/// Lorsque `fx.dim_inactive.enabled == false` : 0 panneau, 0 timer, 0 charge CPU/RAM.
@MainActor
public final class DimInactiveController {
    private let snapshotService: SnapshotService
    private let configLoader: () -> RoadieConfig
    private let renderer: DimInactiveRendering
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
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
        self.renderer = DimInactivePanelPool()
    }

    init(
        snapshotService: SnapshotService,
        configLoader: @escaping () -> RoadieConfig,
        renderer: DimInactiveRendering
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
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        renderer.hideAll()
    }

    /// Calcul pur des fenêtres inactives à assombrir (testable sans AppKit).
    /// Exclut la fenêtre focalisée, les fenêtres non tuilables/flottantes, le plein écran natif,
    /// les stages inactives et les cadres masqués hors écran.
    public static func computeTargets(
        snapshot: DaemonSnapshot,
        config: DimInactiveConfig,
        cornerRadius: CGFloat = 10,
        frameTransform: ((CGRect) -> CGRect)? = nil
    ) -> [DimInactiveTarget] {
        guard config.enabled, config.opacity > 0 else { return [] }
        let transform: (CGRect) -> CGRect = frameTransform ?? { BorderController.axToNS($0) }
        let opacity = CGFloat(min(0.75, max(0.05, config.opacity)))
        let focusedID = snapshot.focusedWindowID
        var targets: [DimInactiveTarget] = []
        targets.reserveCapacity(snapshot.windows.count)

        for entry in snapshot.windows {
            guard entry.window.id != focusedID,
                  entry.window.isOnScreen,
                  entry.window.isTileCandidate,
                  entry.window.furniture?.isNativeFullscreen != true,
                  let scope = entry.scope,
                  snapshot.state.activeScope(on: scope.displayID) == scope,
                  !HiddenWindowPlacement.isHiddenOrLegacyOffscreen(entry.window.frame.cgRect, in: snapshot.displays),
                  snapshot.displays.contains(where: { $0.frame.cgRect.intersects(entry.window.frame.cgRect) })
            else { continue }

            let rect = entry.window.frame.cgRect
            guard rect.width >= 32, rect.height >= 32 else { continue }
            targets.append(DimInactiveTarget(
                windowID: entry.window.id,
                frame: transform(rect),
                opacity: opacity,
                cornerRadius: max(0, cornerRadius)
            ))
        }
        return targets
    }

    private func installObservers() {
        let trigger: @MainActor () -> Void = { [weak self] in
            guard let self, self.started else { return }
            self.requestRefresh()
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: .roadieWindowFramesDidRepublish, object: nil, queue: nil
        ) { [weak self] _ in
            let apply: @MainActor () -> Void = {
                guard let self, self.started else { return }
                self.renderCachedSnapshot()
            }
            if Thread.isMainThread {
                MainActor.assumeIsolated { apply() }
            } else {
                Task { @MainActor in apply() }
            }
        })
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
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in trigger() }
            })
        }
        for name: Notification.Name in [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in trigger() }
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
        let fullConfig = configLoader()
        let dimConfig = fullConfig.fx.dimInactive
        guard dimConfig.enabled else {
            renderer.hideAll()
            return
        }
        guard let snapshot = await snapshotService.readerSnapshot() else { return }
        if wasStarted { guard started, lifecycleGeneration == generation else { return } }
        lastObservedRevision = snapshotService.publicationRevision
        guard configLoader().fx.dimInactive == dimConfig else { return }
        let targets = Self.computeTargets(
            snapshot: snapshot,
            config: dimConfig,
            cornerRadius: CGFloat(fullConfig.fx.borders.cornerRadius)
        )
        renderer.render(targets)
    }

    private func renderCachedSnapshot() {
        let currentRevision = snapshotService.publicationRevision
        guard currentRevision != lastObservedRevision else { return }
        let fullConfig = configLoader()
        let dimConfig = fullConfig.fx.dimInactive
        guard dimConfig.enabled else {
            lastObservedRevision = currentRevision
            renderer.hideAll()
            return
        }
        guard let snapshot = snapshotService.cachedGestureSnapshot() else {
            requestRefresh()
            return
        }
        lastObservedRevision = currentRevision
        let targets = Self.computeTargets(
            snapshot: snapshot,
            config: dimConfig,
            cornerRadius: CGFloat(fullConfig.fx.borders.cornerRadius)
        )
        renderer.render(targets)
    }
}

/// Pool léger de panneaux `NSPanel` traversants aux clics, ordonnés juste au-dessus de chaque fenêtre cible.
@MainActor
private final class DimInactivePanelPool: DimInactiveRendering {
    private var panels: [WindowID: DimInactivePanel] = [:]

    func render(_ targets: [DimInactiveTarget]) {
        guard !targets.isEmpty else {
            hideAll()
            return
        }
        let activeIDs = Set(targets.map(\.windowID))
        for (id, panel) in panels where !activeIDs.contains(id) {
            panel.orderOut(nil)
            panels.removeValue(forKey: id)
        }
        for target in targets {
            let panel = panels[target.windowID] ?? {
                let created = DimInactivePanel()
                panels[target.windowID] = created
                return created
            }()
            panel.apply(target)
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
private final class DimInactivePanel: NSPanel {
    private var currentOpacity: CGFloat = -1
    private var currentRadius: CGFloat = -1

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        colorSpace = .sRGB
        level = .normal
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hasShadow = false
        let view = NSView()
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        contentView = view
    }

    func apply(_ target: DimInactiveTarget) {
        if currentOpacity != target.opacity {
            currentOpacity = target.opacity
            contentView?.layer?.backgroundColor = NSColor.black.withAlphaComponent(target.opacity).cgColor
        }
        if currentRadius != target.cornerRadius {
            currentRadius = target.cornerRadius
            contentView?.layer?.cornerRadius = target.cornerRadius
        }
        if self.frame != target.frame {
            setFrame(target.frame, display: false)
        }
        order(.above, relativeTo: Int(target.windowID.rawValue))
    }
}
