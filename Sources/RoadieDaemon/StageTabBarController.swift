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

/// Cible pure d'une barre d'onglets pour une stage `.tabbed` (Spec 164) ou une tuile `.tabGroup`
/// en mode `spatialBsp` (Spec 165), comptant au moins 2 fenêtres vivantes.
public struct StageTabBarTarget: Equatable, Sendable {
    public var barID: String
    public var scope: StageScope
    public var frame: CGRect
    public var tabs: [StageTabItem]
    public var isTileGroup: Bool

    public init(
        barID: String? = nil,
        scope: StageScope,
        frame: CGRect,
        tabs: [StageTabItem],
        isTileGroup: Bool = false
    ) {
        self.barID = barID ?? "\(scope.description)#stage"
        self.scope = scope
        self.frame = frame
        self.tabs = tabs
        self.isTileGroup = isTileGroup
    }
}

/// Actions interactives exposées par une barre d'onglets (clic, réordonnancement horizontal, glisser-sortir).
@MainActor
struct StageTabBarCallbacks {
    var onSelect: @MainActor (WindowID) -> Void
    var onReorder: @MainActor (WindowID, Int) -> Void = { _, _ in }
    var onDragBegin: @MainActor (WindowID, CGPoint) -> Void = { _, _ in }
    var onDragMove: @MainActor (WindowID, CGPoint) -> Void = { _, _ in }
    var onDragEnd: @MainActor (WindowID, CGPoint) -> Void = { _, _ in }
    var onDragCancel: @MainActor () -> Void = {}
}

/// Frontière de rendu AppKit pour `StageTabBarController`, remplaçable par un espion dans les tests.
@MainActor
protocol StageTabBarRendering: AnyObject {
    func render(_ targets: [StageTabBarTarget], onSelect: @escaping @MainActor (WindowID) -> Void)
    func render(_ targets: [StageTabBarTarget], callbacks: StageTabBarCallbacks)
    func hideAll()
}

extension StageTabBarRendering {
    func render(_ targets: [StageTabBarTarget], callbacks: StageTabBarCallbacks) {
        render(targets, onSelect: callbacks.onSelect)
    }
}

/// Contrôleur de barre d'onglets cliquable et interactive pour les stages `.tabbed` (Spec 164)
/// et les tuiles `.tabGroup` en `spatialBsp` (Spec 165).
/// Zéro panneau créé lorsqu'aucune barre n'est nécessaire.
@MainActor
public final class StageTabBarController {
    private let snapshotService: SnapshotService
    private let configLoader: () -> RoadieConfig
    private let renderer: StageTabBarRendering
    private var dropPreview: DropPreviewController?
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
        dropPreview?.invalidate()
        renderer.hideAll()
    }

    /// Calcul pur des barres d'onglets à afficher (testable sans AppKit).
    /// Couvre les stages globales `.tabbed` (Spec 164) ET les tuiles `.tabGroup` dans `spatialBsp` (Spec 165).
    public static func computeTargets(
        snapshot: DaemonSnapshot,
        config: RoadieConfig,
        outerGapsProvider: (Int, DisplaySnapshot) -> Insets,
        treeProvider: (StageScope) -> BSPTree? = { _ in nil },
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
                  let stage = snapshot.state.stage(scope: activeScope)
            else { continue }

            let liveWindows = stage.windowIDs.compactMap { id -> WindowSnapshot? in
                guard let entry = windowsByID[id], entry.scope == activeScope else { return nil }
                return entry.window
            }
            guard liveWindows.count >= 2 else { continue }

            if stage.mode == .tabbed {
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
                    barID: "\(activeScope.description)#stage",
                    scope: activeScope,
                    frame: transform(axBarFrame),
                    tabs: tabs,
                    isTileGroup: false
                ))
            } else if stage.mode.usesTreeEngine, let rawTree = treeProvider(activeScope) {
                let liveByID = Dictionary(uniqueKeysWithValues: liveWindows.map { ($0.id, $0) })
                let absent = Set(rawTree.windowIDs).subtracting(liveByID.keys)
                let projected = rawTree.projected(excluding: absent)
                guard !projected.tabGroups.isEmpty else { continue }
                let gaps = outerGapsProvider(liveWindows.count, display)
                let container = display.visibleFrame.cgRect.inset(by: gaps)
                let placements = projected.tabBarFrames(
                    in: container,
                    innerGap: CGFloat(config.tiling.gapsInner),
                    tabBarHeight: CGFloat(config.tiling.tabbedBarHeight)
                )
                for placement in placements {
                    let groupWindows = placement.windowIDs.compactMap { liveByID[$0] }
                    guard groupWindows.count >= 2 else { continue }
                    let activeID: WindowID
                    if let globalFocus = snapshot.focusedWindowID, placement.windowIDs.contains(globalFocus) {
                        activeID = globalFocus
                    } else if placement.windowIDs.contains(placement.active) {
                        activeID = placement.active
                    } else {
                        activeID = groupWindows[0].id
                    }
                    let tabs = groupWindows.map { window in
                        StageTabItem(
                            windowID: window.id,
                            appName: window.appName,
                            title: window.title,
                            bundleID: window.bundleID,
                            isFocused: window.id == activeID
                        )
                    }
                    let anchorKey = placement.windowIDs.map(\.rawValue).min() ?? 0
                    targets.append(StageTabBarTarget(
                        barID: "\(activeScope.description)#tile-\(anchorKey)",
                        scope: activeScope,
                        frame: transform(placement.barFrame),
                        tabs: tabs,
                        isTileGroup: true
                    ))
                }
            }
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
        let stageState = snapshotService.effectiveStageStore.state()
        let targets = Self.computeTargets(
            snapshot: snapshot,
            config: config,
            outerGapsProvider: { count, display in
                self.snapshotService.effectiveOuterGaps(windowCount: count, display: display)
            },
            treeProvider: { scope in
                stageState.bspTree(for: scope)
            }
        )
        if targets.isEmpty {
            renderer.hideAll()
            return
        }
        let service = snapshotService
        let callbacks = StageTabBarCallbacks(
            onSelect: { windowID in
                Task.detached(priority: .userInitiated) {
                    _ = WindowCommandService(service: service).focus(windowID: windowID)
                }
            },
            onReorder: { windowID, toIndex in
                Task.detached(priority: .userInitiated) {
                    _ = WindowCommandService(service: service).tabReorder(windowID: windowID, toIndex: toIndex)
                }
            },
            onDragBegin: { [weak self] windowID, point in
                self?.beginTabDetachDrag(windowID: windowID, at: point)
            },
            onDragMove: { [weak self] windowID, point in
                self?.updateTabDetachDrag(windowID: windowID, at: point)
            },
            onDragEnd: { [weak self] windowID, point in
                self?.finishTabDetachDrag(windowID: windowID, at: point)
            },
            onDragCancel: { [weak self] in
                self?.cancelTabDetachDrag()
            }
        )
        renderer.render(targets, callbacks: callbacks)
    }

    private func ensureDropPreview() -> DropPreviewController {
        if let dropPreview { return dropPreview }
        let created = DropPreviewController(engine: DropPreviewEngine(service: snapshotService))
        dropPreview = created
        return created
    }

    private func beginTabDetachDrag(windowID: WindowID, at point: CGPoint) {
        let preview = ensureDropPreview()
        let context = preview.makeContext(preferCachedSnapshot: true)
        preview.beginDrag(
            context: context,
            sourceGestureOwned: false,
            allowsLiveUpdates: true,
            sourceWindowID: windowID
        )
        _ = preview.update(sourceWindowID: windowID, at: point)
    }

    private func updateTabDetachDrag(windowID: WindowID, at point: CGPoint) {
        _ = dropPreview?.update(sourceWindowID: windowID, at: point)
    }

    private func cancelTabDetachDrag() {
        dropPreview?.endDrag()
    }

    private func finishTabDetachDrag(windowID: WindowID, at point: CGPoint) {
        guard let preview = dropPreview else { return }
        guard let candidate = preview.update(sourceWindowID: windowID, at: point) else {
            preview.endDrag()
            return
        }
        let service = snapshotService
        preview.endDrag {
            Task.detached(priority: .userInitiated) {
                _ = StageCommandService(service: service).place(
                    windowID: candidate.sourceWindowID,
                    displayID: candidate.displayID,
                    orderedWindowIDs: candidate.orderedWindowIDs,
                    placements: candidate.placements,
                    treeMutation: candidate.treeMutation
                )
                _ = WindowCommandService(service: service).focus(windowID: candidate.sourceWindowID)
            }
        }
    }
}

// MARK: - Rendu AppKit

@MainActor
private final class StageTabBarPanelPool: StageTabBarRendering {
    private var panels: [String: StageTabBarPanel] = [:]

    func render(_ targets: [StageTabBarTarget], onSelect: @escaping @MainActor (WindowID) -> Void) {
        render(targets, callbacks: StageTabBarCallbacks(onSelect: onSelect))
    }

    func render(_ targets: [StageTabBarTarget], callbacks: StageTabBarCallbacks) {
        guard !targets.isEmpty else {
            hideAll()
            return
        }
        let activeBarIDs = Set(targets.map(\.barID))
        for (barID, panel) in panels where !activeBarIDs.contains(barID) {
            guard !panel.isTrackingDrag else { continue }
            panel.orderOut(nil)
            panels.removeValue(forKey: barID)
        }
        for target in targets {
            let panel = panels[target.barID] ?? {
                let created = StageTabBarPanel()
                panels[target.barID] = created
                return created
            }()
            panel.apply(target, callbacks: callbacks)
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
    private var tabViews: [StageTabItemView] = []
    private var lastTarget: StageTabBarTarget?
    private var callbacks: StageTabBarCallbacks?
    var isTrackingDrag = false

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

    func apply(_ target: StageTabBarTarget, callbacks: StageTabBarCallbacks) {
        self.callbacks = callbacks
        guard !isTrackingDrag else { return }
        if frame != target.frame {
            setFrame(target.frame, display: false)
        }
        if lastTarget?.tabs != target.tabs || lastTarget?.isTileGroup != target.isTileGroup {
            lastTarget = target
            rebuildButtons(target: target)
        }
        orderFrontRegardless()
    }

    private func rebuildButtons(target: StageTabBarTarget) {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        tabViews.removeAll()
        let iconCache = SharedAppIconCache.shared
        for (index, tab) in target.tabs.enumerated() {
            let icon: NSImage? = iconCache.cleanedIcon(for: tab.bundleID).map {
                let sized = $0.copy() as? NSImage ?? $0
                sized.size = NSSize(width: 14, height: 14)
                return sized
            }
            let itemView = StageTabItemView(
                tab: tab,
                index: index,
                icon: icon,
                allowsDetach: target.isTileGroup,
                panel: self
            )
            tabViews.append(itemView)
            stackView.addArrangedSubview(itemView)
        }
    }

    fileprivate func handleInteraction(for itemView: StageTabItemView, startEvent: NSEvent) {
        guard let callbacks else { return }
        let startScreenPoint = NSEvent.mouseLocation
        let tab = itemView.tab
        let startIndex = itemView.index
        let allowsDetach = itemView.allowsDetach
        let barZone = frame.insetBy(dx: -16, dy: -26)
        var didMove = false
        var detached = false
        var cancelled = false
        var reorderTargetIndex = startIndex

        isTrackingDrag = true
        defer {
            isTrackingDrag = false
            clearReorderHighlight()
            itemView.alphaValue = 1.0
        }

        trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp, .flagsChanged, .keyDown],
            timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { [weak self] event, stop in
            guard let self, let event else { stop.pointee = true; return }
            let screenPoint = NSEvent.mouseLocation
            switch event.type {
            case .keyDown where event.keyCode == 53:
                cancelled = true
                if detached { callbacks.onDragCancel() }
                stop.pointee = true
            case .flagsChanged:
                if detached {
                    callbacks.onDragMove(tab.windowID, screenPoint)
                }
            case .leftMouseDragged:
                let dist = hypot(screenPoint.x - startScreenPoint.x, screenPoint.y - startScreenPoint.y)
                if dist >= 6 { didMove = true }
                guard didMove else { return }
                if !detached && allowsDetach && !barZone.contains(screenPoint) {
                    detached = true
                    clearReorderHighlight()
                    itemView.alphaValue = 0.45
                    callbacks.onDragBegin(tab.windowID, screenPoint)
                } else if detached {
                    callbacks.onDragMove(tab.windowID, screenPoint)
                } else {
                    itemView.alphaValue = 0.72
                    reorderTargetIndex = self.tabIndex(atScreenX: screenPoint.x)
                    self.highlightReorderSlot(reorderTargetIndex)
                }
            case .leftMouseUp:
                if detached {
                    callbacks.onDragEnd(tab.windowID, screenPoint)
                } else if !didMove {
                    callbacks.onSelect(tab.windowID)
                } else if reorderTargetIndex != startIndex {
                    callbacks.onReorder(tab.windowID, reorderTargetIndex)
                }
                stop.pointee = true
            default:
                break
            }
        }
        if cancelled && !detached {
            return
        }
    }

    private func tabIndex(atScreenX screenX: CGFloat) -> Int {
        guard !tabViews.isEmpty else { return 0 }
        let localX = screenX - frame.minX
        let ratio = max(0, min(0.999, localX / max(1, frame.width)))
        return min(tabViews.count - 1, max(0, Int(floor(ratio * CGFloat(tabViews.count)))))
    }

    private func highlightReorderSlot(_ index: Int) {
        for (idx, view) in tabViews.enumerated() {
            view.setReorderHighlight(idx == index)
        }
    }

    private func clearReorderHighlight() {
        for view in tabViews {
            view.setReorderHighlight(false)
        }
    }
}

@MainActor
private final class StageTabItemView: NSView {
    let tab: StageTabItem
    let index: Int
    let allowsDetach: Bool
    private weak var panel: StageTabBarPanel?
    private let iconView = NSImageView()
    private let labelField = NSTextField(labelWithString: "")

    init(tab: StageTabItem, index: Int, icon: NSImage?, allowsDetach: Bool, panel: StageTabBarPanel) {
        self.tab = tab
        self.index = index
        self.allowsDetach = allowsDetach
        self.panel = panel
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = tab.isFocused
            ? NSColor.controlAccentColor.withAlphaComponent(0.32).cgColor
            : NSColor.white.withAlphaComponent(0.06).cgColor
        toolTip = allowsDetach
            ? tr("\(tab.displayLabel) — cliquer pour activer, glisser pour réordonner ou détacher en tuile",
                 "\(tab.displayLabel) — click to focus, drag to reorder or detach as tile")
            : tab.displayLabel

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 5
        row.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        row.translatesAutoresizingMaskIntoConstraints = false

        if let icon {
            iconView.image = icon
            iconView.imageScaling = .scaleProportionallyDown
            iconView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                iconView.widthAnchor.constraint(equalToConstant: 14),
                iconView.heightAnchor.constraint(equalToConstant: 14),
            ])
            row.addArrangedSubview(iconView)
        }

        labelField.stringValue = tab.displayLabel
        labelField.font = .systemFont(ofSize: 12, weight: tab.isFocused ? .semibold : .regular)
        labelField.textColor = tab.isFocused ? .labelColor : .secondaryLabelColor
        labelField.lineBreakMode = .byTruncatingTail
        labelField.maximumNumberOfLines = 1
        labelField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(labelField)

        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func setReorderHighlight(_ active: Bool) {
        layer?.borderWidth = active ? 1.5 : 0
        layer?.borderColor = active ? NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor : nil
    }

    override func mouseDown(with event: NSEvent) {
        panel?.handleInteraction(for: self, startEvent: event)
    }
}
