import AppKit
import QuartzCore
import RoadieAX
import RoadieCore

/// Ce que `BorderController` demande au panneau d'afficher : valeur pure, comparable dans les tests.
/// `groupLabel` est nul pour une fenêtre hors groupe : le rendu reste alors celui d'une simple bordure.
struct BorderRenderModel: Equatable {
    var frame: CGRect
    var color: NSColor
    var thickness: CGFloat
    var cornerRadius: CGFloat
    var groupLabel: String?
}

/// Frontière vers l'écran réel (panneau AppKit), remplaçable par un faux dans les tests.
@MainActor
protocol BorderRendering: AnyObject {
    func render(_ model: BorderRenderModel)
    func hide()
}

@MainActor
public final class BorderController {
    private let snapshotService: SnapshotService
    private let configLoader: () -> RoadieConfig
    private let panel: BorderRendering
    private var refreshTimer: Timer?
    private var dragTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var dragMonitors: [Any] = []
    private var configWatcher: RailFileWatcher?
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
        self.panel = BorderPanel()
    }

    init(
        snapshotService: SnapshotService,
        configLoader: @escaping () -> RoadieConfig,
        panel: BorderRendering
    ) {
        self.snapshotService = snapshotService
        self.configLoader = configLoader
        self.panel = panel
    }

    public func start() {
        NSApplication.shared.setActivationPolicy(.accessory)
        UserInputActivity.shared.startMonitoring()
        if !started {
            started = true
            lifecycleGeneration &+= 1
            installObservers()
        }
        requestRefresh()
        syncPollingFallback()
    }

    public func stop() {
        started = false
        lifecycleGeneration &+= 1
        needsAnotherRefresh = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        dragTimer?.invalidate()
        dragTimer = nil
        configWatcher?.stop()
        configWatcher = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        dragMonitors.forEach { NSEvent.removeMonitor($0) }
        dragMonitors.removeAll()
        hidePanel()
    }

    private func installObservers() {
        let trigger: @MainActor () -> Void = { [weak self] in
            guard let self, self.started else { return }
            self.syncPollingFallback()
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
                self.syncPollingFallback()
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
        configWatcher = RailFileWatcher(
            path: {
                let active = ConfigReloadService.shared.state.activePath ?? RoadieConfigLoader.defaultConfigPath()
                let expanded = NSString(string: active).expandingTildeInPath
                return URL(fileURLWithPath: expanded).deletingLastPathComponent().path
            },
            observedFile: {
                let active = ConfigReloadService.shared.state.activePath ?? RoadieConfigLoader.defaultConfigPath()
                return NSString(string: active).expandingTildeInPath
            },
            onChange: trigger
        )
        configWatcher?.start()
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp], handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handlePointerEvent(event.type) }
        }) { dragMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp], handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handlePointerEvent(event.type) }
            return event
        }) { dragMonitors.append(local) }
    }

    private func handlePointerEvent(_ type: NSEvent.EventType) {
        guard started, configLoader().fx.borders.enabled else {
            dragTimer?.invalidate()
            dragTimer = nil
            return
        }
        if type == .leftMouseDragged {
            guard dragTimer == nil else { return }
            let newTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.started else { return }
                    if NSEvent.pressedMouseButtons == 0 && !UserInputActivity.shared.isCapturedPointerHeld {
                        self.dragTimer?.invalidate()
                        self.dragTimer = nil
                    }
                    self.requestRefresh()
                }
            }
            newTimer.tolerance = 0.02
            dragTimer = newTimer
            RunLoop.main.add(newTimer, forMode: .common)
        } else if type == .leftMouseUp {
            dragTimer?.invalidate()
            dragTimer = nil
            requestRefresh()
        }
    }

    /// En mode monolithique (`isQuietReaderReuseEnabled`), le tiler publie chaque snapshot :
    /// aucun polling permanent au repos. En mode modulaire (processus `border` isolé), un timer
    /// à 120 ms avec tolérance reste actif tant que les bordures sont activées.
    private func syncPollingFallback() {
        guard started else {
            refreshTimer?.invalidate()
            refreshTimer = nil
            return
        }
        let needsPolling = !snapshotService.isQuietReaderReuseEnabled && configLoader().fx.borders.enabled
        if needsPolling {
            guard refreshTimer == nil else { return }
            let newTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.requestRefresh() }
            }
            newTimer.tolerance = 0.03
            refreshTimer = newTimer
            RunLoop.main.add(newTimer, forMode: .common)
        } else {
            refreshTimer?.invalidate()
            refreshTimer = nil
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
        let config = configLoader().fx.borders
        guard config.enabled else {
            hidePanel()
            return
        }

        guard let snapshot = await snapshotService.readerSnapshot() else { return }
        // Si `start()` a été utilisé puis `stop()` pendant l'acquisition, ne rien réafficher.
        if wasStarted { guard started, lifecycleGeneration == generation else { return } }
        lastObservedRevision = snapshotService.publicationRevision
        guard configLoader().fx.borders == config else { return }
        render(snapshot: snapshot, config: config)
    }

    /// Suivi synchrone à 60 FPS pendant une animation ou un redimensionnement interactif (Lot F) :
    /// lit directement le dernier snapshot republié en mémoire (O(1), zéro appel AX, zéro saut de tâche).
    private func renderCachedSnapshot() {
        let currentRevision = snapshotService.publicationRevision
        guard currentRevision != lastObservedRevision else { return }
        let config = configLoader().fx.borders
        guard config.enabled else {
            lastObservedRevision = currentRevision
            hidePanel()
            return
        }
        guard let snapshot = snapshotService.cachedGestureSnapshot() else {
            requestRefresh()
            return
        }
        lastObservedRevision = currentRevision
        render(snapshot: snapshot, config: config)
    }

    private func render(snapshot: DaemonSnapshot, config: BorderConfig) {
        guard let focusedWindowID = snapshot.focusedWindowID,
              let entry = snapshot.windows.first(where: { $0.window.id == focusedWindowID }),
              entry.window.isTileCandidate,
              entry.scope != nil,
              !HiddenWindowPlacement.isHiddenOrLegacyOffscreen(entry.window.frame.cgRect, in: snapshot.displays),
              !Self.isWindowVisiblyOccluded(entry, in: snapshot)
        else {
            hidePanel()
            return
        }

        let color = entry.pin == nil ? activeColor(for: entry.scope?.stageID, config: config) : .systemRed
        panel.render(BorderRenderModel(
            frame: Self.axToNS(entry.window.frame.cgRect),
            color: color,
            thickness: CGFloat(max(1, config.thickness)),
            cornerRadius: CGFloat(max(0, config.cornerRadius)),
            groupLabel: Self.groupLabel(for: focusedWindowID, snapshot: snapshot)
        ))
    }

    private func hidePanel() {
        panel.hide()
    }

    private func activeColor(for stageID: StageID?, config: BorderConfig) -> NSColor {
        let rawColor: String
        if let stageID,
           let override = config.stageOverrides.first(where: { $0.stageID == stageID.rawValue }) {
            rawColor = override.activeColor ?? config.activeColor
        } else {
            rawColor = config.activeColor
        }
        return NSColor(hex: rawColor) ?? NSColor.systemBlue
    }

    /// Libellé discret « nom du groupe, position du membre actif/taille » (ex. « docs 2/3 »), ou nil hors groupe.
    /// Complexité : O(écrans x bureaux x stages x groupes + taille du groupe), exécuté à chaque rafraîchissement.
    static func groupLabel(for windowID: WindowID, snapshot: DaemonSnapshot) -> String? {
        for display in snapshot.state.displays.values {
            for desktop in display.desktops.values {
                for stage in desktop.stages.values {
                    guard let group = stage.groups.first(where: { $0.windowIDs.contains(windowID) }) else { continue }
                    let active = group.activeWindowID ?? windowID
                    let position = (group.windowIDs.firstIndex(of: active) ?? 0) + 1
                    return "\(group.id) \(position)/\(group.windowIDs.count)"
                }
            }
        }
        return nil
    }

    nonisolated public static func isWindowVisiblyOccluded(
        _ target: ScopedWindowSnapshot,
        in snapshot: DaemonSnapshot
    ) -> Bool {
        let targetFrame = target.window.frame.cgRect
        for entry in snapshot.windows {
            if entry.window.id == target.window.id {
                return false
            }
            guard entry.window.isOnScreen else { continue }
            let frame = entry.window.frame.cgRect
            guard !HiddenWindowPlacement.isHiddenOrLegacyOffscreen(frame, in: snapshot.displays) else { continue }
            let intersection = frame.intersection(targetFrame)
            guard !intersection.isNull,
                  intersection.width >= 24,
                  intersection.height >= 24,
                  intersection.width * intersection.height >= 2_500
            else { continue }
            return true
        }
        return false
    }

    static func axToNS(_ rect: CGRect) -> CGRect {
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
private final class BorderPanel: NSPanel, BorderRendering {
    private let borderView = BorderView()

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
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hasShadow = false
        contentView = borderView
    }

    func hide() {
        if isVisible { orderOut(nil) }
    }

    func render(_ model: BorderRenderModel) {
        let expanded = model.frame.insetBy(dx: -model.thickness / 2, dy: -model.thickness / 2)
        // FR-023 : aucun travail de fenêtre si rien n'a changé depuis le dernier rendu visible.
        guard !isVisible
            || expanded != self.frame
            || model.color != borderView.color
            || model.thickness != borderView.thickness
            || model.cornerRadius != borderView.cornerRadius
            || model.groupLabel != borderView.groupLabel
        else { return }
        if model.color != borderView.color { borderView.color = model.color }
        if model.thickness != borderView.thickness { borderView.thickness = model.thickness }
        if model.cornerRadius != borderView.cornerRadius { borderView.cornerRadius = model.cornerRadius }
        if model.groupLabel != borderView.groupLabel { borderView.groupLabel = model.groupLabel }
        if expanded != self.frame { setFrame(expanded, display: false) }
        orderFrontRegardless()
    }
}

@MainActor
private final class BorderView: NSView {
    var color: NSColor = .systemBlue { didSet { updateVisuals() } }
    var thickness: CGFloat = 2 { didSet { updateVisuals() } }
    var cornerRadius: CGFloat = 10 { didSet { updateVisuals() } }
    var groupLabel: String? { didSet { updateVisuals() } }

    /// Rendu vectoriel par `CAShapeLayer` : aucun tampon bitmap plein-cadre alloué par CoreAnimation
    /// pour l'intérieur transparent de la bordure (Lot B).
    private let strokeLayer = CAShapeLayer()
    private let pillView = BorderGroupPillView()

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = nil
        strokeLayer.fillColor = nil
        layer?.addSublayer(strokeLayer)
        pillView.isHidden = true
        addSubview(pillView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateVisuals()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateVisuals()
    }

    private func updateVisuals() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strokeLayer.frame = bounds
        let rect = bounds.insetBy(dx: thickness / 2, dy: thickness / 2)
        if rect.width > 0, rect.height > 0 {
            let clampedRadius = min(cornerRadius, rect.width / 2, rect.height / 2)
            strokeLayer.path = CGPath(roundedRect: rect, cornerWidth: clampedRadius, cornerHeight: clampedRadius, transform: nil)
        } else {
            strokeLayer.path = nil
        }
        strokeLayer.lineWidth = thickness
        var resolvedColor = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolvedColor = color.cgColor
        }
        strokeLayer.strokeColor = resolvedColor
        CATransaction.commit()
        updateGroupPill()
    }

    /// Pastille dans le coin haut droit, à l'intérieur de la bordure, couleur de la bordure.
    /// Largeur bornée à la place disponible ; libellé tronqué sur une ligne ; rien si la place manque.
    private func updateGroupPill() {
        guard let groupLabel else {
            pillView.isHidden = true
            return
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        let text = NSAttributedString(string: groupLabel, attributes: attributes)
        guard let geometry = BorderGroupPill.geometry(bounds: bounds, thickness: thickness, textSize: text.size()) else {
            pillView.isHidden = true
            return
        }
        pillView.frame = geometry.pill
        pillView.color = color
        pillView.text = text
        pillView.textRect = CGRect(
            x: geometry.text.minX - geometry.pill.minX,
            y: geometry.text.minY - geometry.pill.minY,
            width: geometry.text.width,
            height: geometry.text.height
        )
        pillView.isHidden = false
        pillView.needsDisplay = true
    }
}

@MainActor
private final class BorderGroupPillView: NSView {
    var color: NSColor = .systemBlue
    var text: NSAttributedString?
    var textRect: CGRect = .zero

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        text?.draw(in: textRect)
    }
}

/// Géométrie de la pastille de groupe (fonction pure, testable sans AppKit à l'écran).
enum BorderGroupPill {
    static let rightMargin: CGFloat = 8
    static let topMargin: CGFloat = 6
    static let horizontalPadding: CGFloat = 6
    static let verticalPadding: CGFloat = 2
    /// Largeur de texte minimale pour que la pastille reste lisible (au moins « … » et un caractère).
    static let minimumTextWidth: CGFloat = 16

    struct Geometry: Equatable {
        var pill: CGRect
        var text: CGRect
    }

    /// Pastille ancrée en haut à droite. Sa largeur ne dépasse jamais l'espace entre les deux marges
    /// intérieures de la bordure : l'origine ne devient donc jamais négative. `nil` si la place
    /// (largeur ou hauteur) est insuffisante. O(1).
    static func geometry(bounds: CGRect, thickness: CGFloat, textSize: CGSize) -> Geometry? {
        let inset = thickness + rightMargin
        let availableWidth = bounds.width - 2 * inset
        let pillHeight = textSize.height + 2 * verticalPadding
        guard availableWidth >= minimumTextWidth + 2 * horizontalPadding,
              bounds.height >= pillHeight + 2 * (thickness + topMargin)
        else { return nil }
        let pillWidth = min(textSize.width + 2 * horizontalPadding, availableWidth)
        let pill = CGRect(
            x: bounds.maxX - inset - pillWidth,
            y: bounds.maxY - thickness - topMargin - pillHeight,
            width: pillWidth,
            height: pillHeight
        )
        let text = CGRect(
            x: pill.minX + horizontalPadding,
            y: pill.minY + verticalPadding,
            width: pillWidth - 2 * horizontalPadding,
            height: textSize.height
        )
        return Geometry(pill: pill, text: text)
    }
}
