import AppKit
import Darwin
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages

@MainActor
public final class RailController {
    nonisolated private static let transientMissingMemberRailGrace: TimeInterval = 15

    private let store: StageStore
    private let snapshotService: SnapshotService
    private let commandService: StageCommandService
    private let desktopCommandService: DesktopCommandService
    private let events = EventLog()
    private let railRuntimeStateStore = RailRuntimeStateStore()
    private let thumbnails = RailThumbnailStore.shared
    private var panels: [DisplayID: RailPanel] = [:]
    private var screenFrames: [DisplayID: CGRect] = [:]
    /// Cadres (coordonnees AX) des fenetres gerees de la stage active de chaque ecran, releves au dernier cycle.
    /// Le survol du rail les lit au lieu de demander un snapshot complet (SPEC-016 FR-024).
    private var managedWindowFrames: [DisplayID: [CGRect]] = [:]
    private var rebuildTask: Task<Void, Never>?
    private var pendingRebuild: (reason: String, requestedAt: Date?)?
    private var lastRenderSignatures: [DisplayID: String] = [:]
    /// Révisions des vignettes par écran (SPEC-048 C-03) : un changement seul met à jour les images
    /// des cartes existantes, sans reconstruire le panneau.
    private var lastThumbnailSignatures: [DisplayID: String] = [:]
    private var contentCache = RailDisplayContentCache()
    private var lastRenderedSettings: RailSettings?
    private var lastConfigRefreshPath: String?
    private var lastConfigRefreshStamp: [Int64]?
    /// Statut d'enregistrement mémorisé (SPEC-048 C-02) : relu quand le watcher signale un
    /// changement, ou quand le processus enregistreur a disparu ; sinon aucune lecture par tick.
    private var recordingStatusCache: TargetRecordingStatus?
    private var recordingStatusDirty = true
    private var refreshTimer: Timer?
    private var hoverTimer: Timer?
    private var stageLabelTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var stageStoreWatcher: RailFileWatcher?
    private var configWatcher: RailFileWatcher?
    private var recordingStatusWatcher: RailFileWatcher?
    private var pendingStageStoreRefresh: DispatchWorkItem?
    private var lastStageStoreRailSignature: String?
    private var pendingStageStoreRailSignature: String?
    private var lastInteractiveRailRefreshAt: Date = .distantPast
    private var clickMonitors: [Any] = []
    private var pendingDrag: PendingRailDrag?
    private var pendingStageReorder: PendingStageReorder?
    private var defersPanelRebuild: Bool {
        pendingDrag != nil || pendingStageReorder != nil || windowDragController.hasActiveDrag
    }
    private var dragReleasedSince: Date?
    private var dragGhost: RailDragGhostWindow?
    private let dropPreview = DropPreviewController()
    private var stageMenuTargets: [NSObject] = []
    private lazy var windowDragController = WindowDragReorderController(preview: dropPreview)
    private var focusedWindowID: WindowID?
    private var protectedBlurredWindows: [WindowID: Date] = [:]

    public init(
        store: StageStore = StageStore(),
        snapshotService: SnapshotService = SnapshotService(),
        commandService: StageCommandService = StageCommandService(),
        desktopCommandService: DesktopCommandService = DesktopCommandService()
    ) {
        self.store = store
        self.snapshotService = snapshotService
        self.commandService = commandService
        self.desktopCommandService = desktopCommandService
    }

    public func start() {
        NSApplication.shared.setActivationPolicy(.accessory)
        rebuildPanels(reason: "start")
        startClickMonitors()
        startHoverTimer()
        startWatchers()
        startSettingsObserver()
        refreshTimer?.invalidate()
        let newRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rebuildPanels(reason: "timer") }
        }
        refreshTimer = newRefreshTimer
        RunLoop.main.add(newRefreshTimer, forMode: .common)
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildPanels(reason: "screen") }
        }
    }

    /// Arrete tout ce que `start()` a mis en place : timers, surveillances de fichiers, moniteurs souris,
    /// observateur d'ecran et panneaux. Appelable plusieurs fois ; `start()` peut ensuite etre rappele.
    public func stop() {
        rebuildTask?.cancel()
        rebuildTask = nil
        pendingRebuild = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        hoverTimer?.invalidate()
        hoverTimer = nil
        stageLabelTimer?.invalidate()
        stageLabelTimer = nil
        pendingStageStoreRefresh?.cancel()
        pendingStageStoreRefresh = nil
        pendingStageStoreRailSignature = nil
        [configWatcher, recordingStatusWatcher, stageStoreWatcher].forEach { $0?.stop() }
        clickMonitors.forEach { NSEvent.removeMonitor($0) }
        clickMonitors.removeAll()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        settingsObserver = nil
        cancelRailDrags()
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
        thumbnails.prune(keeping: [], owner: "rail")
        screenFrames.removeAll()
        lastRenderSignatures.removeAll()
        lastThumbnailSignatures.removeAll()
        contentCache = RailDisplayContentCache()
        lastRenderedSettings = nil
        lastConfigRefreshPath = nil
        lastConfigRefreshStamp = nil
        // Watcher arrêté : un changement pendant l'arrêt ne serait jamais signalé (SPEC-048 C-02).
        recordingStatusCache = nil
        recordingStatusDirty = true
    }

    private func startWatchers() {
        configWatcher = RailFileWatcher(
            path: { ConfigReloadService.shared.state.activePath ?? RoadieConfigLoader.defaultConfigPath() },
            onChange: { [weak self] in self?.refreshPanelsForConfigChange(reason: "config") }
        )
        recordingStatusWatcher = RailFileWatcher(
            path: {
                try? FileManager.default.createDirectory(at: TargetRecordingStatusStore.directoryURL, withIntermediateDirectories: true)
                return TargetRecordingStatusStore.directoryURL.path
            },
            observedFile: { TargetRecordingStatusStore.defaultURL.path },
            onChange: { [weak self] in
                self?.recordingStatusDirty = true
                self?.rebuildPanels(reason: "recording_status")
            }
        )
        let stageStorePath = store.fileURL.path
        stageStoreWatcher = RailFileWatcher(
            path: { stageStorePath },
            onChange: { [weak self] in self?.scheduleStageStoreRefresh(reason: "stage_store") }
        )
        [configWatcher, recordingStatusWatcher, stageStoreWatcher].forEach { $0?.start() }
    }

    private func startSettingsObserver() {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .roadieSettingsDidChange, object: nil, queue: .main
        ) { [weak self] notification in
            let changedPath = notification.userInfo?["configPath"] as? String
            Task { @MainActor in
                guard let self, let changedPath else { return }
                let activePath = ConfigReloadService.shared.state.activePath ?? RoadieConfigLoader.defaultConfigPath()
                guard URL(fileURLWithPath: changedPath).resolvingSymlinksInPath()
                    == URL(fileURLWithPath: activePath).resolvingSymlinksInPath() else { return }
                self.refreshPanelsForConfigChange(reason: "settings")
            }
        }
    }

    /// Notification des réglages et événement vnode portent la même écriture : un seul cycle.
    private func refreshPanelsForConfigChange(reason: String) {
        let path = ConfigReloadService.shared.state.activePath ?? RoadieConfigLoader.defaultConfigPath()
        let stamp = fileModificationStamp(path)
        guard path != lastConfigRefreshPath || stamp != lastConfigRefreshStamp else { return }
        rebuildPanels(reason: reason)
    }

    private func scheduleStageStoreRefresh(reason: String) {
        let signature = Self.railSignature(for: store.state())
        if signature == lastStageStoreRailSignature || signature == pendingStageStoreRailSignature {
            return
        }
        pendingStageStoreRailSignature = signature
        pendingStageStoreRefresh?.cancel()
        let requestedAt = Date()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.pendingStageStoreRefresh = nil
                self?.rebuildPanels(reason: reason, requestedAt: requestedAt, railSignature: signature)
            }
        }
        pendingStageStoreRefresh = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20), execute: item)
    }

    nonisolated static func railSignature(for state: PersistentStageState) -> String {
        var parts: [String] = []
        parts.append("activeDisplay=\(state.activeDisplayID?.rawValue ?? "-")")
        for selection in state.desktopSelections.sorted(by: { $0.displayID.rawValue < $1.displayID.rawValue }) {
            let lastDesktopID = selection.lastDesktopID.map { String($0.rawValue) } ?? "-"
            parts.append("desktop=\(selection.displayID.rawValue):\(selection.currentDesktopID.rawValue):last=\(lastDesktopID)")
        }
        for scope in state.scopes.sorted(by: {
            if $0.displayID.rawValue != $1.displayID.rawValue { return $0.displayID.rawValue < $1.displayID.rawValue }
            return $0.desktopID.rawValue < $1.desktopID.rawValue
        }) {
            parts.append("scope=\(scope.displayID.rawValue):\(scope.desktopID.rawValue):active=\(scope.activeStageID.rawValue)")
            for stage in scope.stages {
                let members = stage.members.map {
                    "\($0.windowID.rawValue):closed=\($0.confirmedClosedAt == nil ? 0 : 1)"
                }.joined(separator: ",")
                parts.append("stage=\(stage.id.rawValue):\(stage.name):\(stage.mode.rawValue):\(members)")
            }
        }
        return parts.joined(separator: "|")
    }

    private func startClickMonitors() {
        guard clickMonitors.isEmpty else { return }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .rightMouseDragged, .rightMouseUp], handler: { [weak self] event in
            let screenPoint = RoadieScreenCoordinate.mouseEventPoint(event)
            if Self.isRightMouseEvent(event.type),
               self?.handleRightMouse(event.type, at: screenPoint) == true {
                return nil
            }
            self?.handleMouse(event.type, at: screenPoint)
            return event
        }) {
            clickMonitors.append(local)
        }
        // Le moniteur global ne voit que les evenements livres a une autre application : si le curseur est
        // sur un panneau, c'est que celui-ci laissait passer le clic (passthrough). Le rail ne doit pas
        // agir en plus de la fenetre qui a recu le clic.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .rightMouseDragged, .rightMouseUp], handler: { [weak self] event in
            let screenPoint = RoadieScreenCoordinate.mouseEventPoint(event)
            DispatchQueue.main.async {
                if Self.isRightMouseEvent(event.type) {
                    _ = self?.handleRightMouse(event.type, at: screenPoint, fromGlobalMonitor: true)
                } else {
                    self?.handleMouse(event.type, at: screenPoint, fromGlobalMonitor: true)
                }
            }
        }) {
            clickMonitors.append(global)
        }
    }

    private func startHoverTimer() {
        hoverTimer?.invalidate()
        let newHoverTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateRailHover()
            }
        }
        hoverTimer = newHoverTimer
        RunLoop.main.add(newHoverTimer, forMode: .common)
    }

    // Complexite : O(p) par tick - p = nombre de panneaux ; aucun snapshot (cadres du dernier cycle).
    private func updateRailHover() {
        resetStaleRailDrags()
        let point = NSEvent.mouseLocation
        let canHide = pendingDrag == nil && pendingStageReorder == nil && !windowDragController.hasActiveDrag
        for (displayID, panel) in panels {
            guard panel.isVisible else { continue }
            let overManagedWindow = railClickWouldHitManagedWindow(at: point, displayID: displayID, panel: panel)
            panel.updateMousePassthrough(at: point, allowEmptyRail: !overManagedWindow)
            panel.updateAutoHide(mouse: point, canHide: canHide)
        }
    }

    /// Un bouton relache hors de nos fenetres peut ne jamais produire de mouse-up : sans cette remise a zero,
    /// `pendingDrag` resterait actif et bloquerait le masquage automatique du rail.
    /// Le bouton doit etre observe relache pendant 0,4 s : un mouse-up normal est livre quelques ms apres le
    /// relachement et ne doit pas etre perdu.
    private func resetStaleRailDrags() {
        let pressed = NSEvent.pressedMouseButtons
        let leftStale = (pendingDrag != nil || windowDragController.hasActiveDrag) && pressed & 1 == 0
        let rightStale = pendingStageReorder != nil && pressed & 2 == 0
        guard leftStale || rightStale else {
            dragReleasedSince = nil
            return
        }
        let since = dragReleasedSince ?? Date()
        dragReleasedSince = since
        guard Date().timeIntervalSince(since) > 0.4 else { return }
        if leftStale {
            pendingDrag = nil
            windowDragController.cancelPendingDrag()
            dropPreview.endDrag()
            panels.values.forEach { $0.hideWindowDropPreview() }
        }
        if rightStale {
            pendingStageReorder = nil
            panels.values.forEach { $0.hideStageReorderPreview() }
        }
        dragGhost?.hide()
        dragReleasedSince = nil
    }

    private func cancelRailDrags() {
        pendingDrag = nil
        pendingStageReorder = nil
        windowDragController.cancelPendingDrag()
        panels.values.forEach { $0.hideStageReorderPreview() }
        panels.values.forEach { $0.hideWindowDropPreview() }
        dragGhost?.hide()
        dropPreview.endDrag()
    }

    /// Redessine les etiquettes de stage seulement pendant leur fondu (SPEC-016 FR-024).
    /// Avant la fin de la visibilite et apres la fin du fondu, l'opacite est constante : aucun timer.
    private func scheduleStageLabelFade(_ label: RailStageLabelConfig) {
        stageLabelTimer?.invalidate()
        stageLabelTimer = nil
        guard label.enabled, label.visibilitySeconds > 0, let visibleUntil = label.visibleUntil else { return }
        let fadeEnd = visibleUntil + max(label.fadeSeconds, 0)
        guard Date().timeIntervalSince1970 < fadeEnd else { return }
        let timer = Timer(fire: Date(timeIntervalSince1970: visibleUntil), interval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickStageLabelFade(until: fadeEnd) }
        }
        stageLabelTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tickStageLabelFade(until fadeEnd: TimeInterval) {
        panels.values.filter(\.isVisible).forEach { $0.refreshStageLabels() }
        if Date().timeIntervalSince1970 >= fadeEnd {
            stageLabelTimer?.invalidate()
            stageLabelTimer = nil
        }
    }

    private static func isRightMouseEvent(_ type: NSEvent.EventType) -> Bool {
        type == .rightMouseDown || type == .rightMouseDragged || type == .rightMouseUp
    }

    private func handleMouse(_ type: NSEvent.EventType, at screenPoint: CGPoint, fromGlobalMonitor: Bool = false) {
        switch type {
        case .leftMouseDown:
            handleMouseDown(at: screenPoint, fromGlobalMonitor: fromGlobalMonitor)
        case .leftMouseDragged:
            handleMouseDragged(to: screenPoint)
        case .leftMouseUp:
            handleMouseUp(at: screenPoint)
        default:
            break
        }
    }

    private func handleMouseDown(at screenPoint: CGPoint, fromGlobalMonitor: Bool = false) {
        // Un nouveau clic invalide tout drag precedent reste en suspens.
        pendingDrag = nil
        dragGhost?.hide()
        dropPreview.endDrag()
        for (displayID, panel) in panels {
            guard panel.isVisible, panel.frame.contains(screenPoint) else { continue }
            // Evenement global sur un panneau = le panneau laissait passer le clic : la fenetre dessous l'a recu.
            if fromGlobalMonitor, panel.ignoresMouseEvents { continue }
            if panel.revealIfCollapsed() {
                return
            }
            let overManagedWindow = railClickWouldHitManagedWindow(at: screenPoint, displayID: displayID, panel: panel)
            guard panel.shouldCaptureMouse(at: screenPoint, allowEmptyRail: !overManagedWindow) else {
                continue
            }
            if let payload = panel.dragPayload(at: screenPoint) {
                pendingDrag = PendingRailDrag(
                    displayID: displayID,
                    windowID: payload.windowID,
                    sourceStageID: payload.sourceStageID,
                    clickAction: payload.clickAction,
                    grabUnit: payload.grabUnit,
                    startPoint: screenPoint,
                    didDrag: false
                )
                return
            }
            if let action = panel.action(at: screenPoint) {
                perform(action, displayID: displayID)
            } else if let stageID = panel.emptyStageID(at: screenPoint) {
                guard !emptyRailClickHitsManagedWindow(at: screenPoint, displayID: displayID) else {
                    return
                }
                print("rail empty switch stage \(stageID.rawValue)")
                fflush(stdout)
                perform(.switchStage(stageID), displayID: displayID)
            } else {
                return
            }
            rebuildPanels()
            return
        }
        // SPEC-051 C-05 : sans bande de titre gérée sous le clic, aucun relevé ni contexte de glisser.
        let frames = managedWindowFrames.values.flatMap { $0 }
        guard Self.clickMayStartWindowDrag(atAXPoint: Self.nsToAX(screenPoint), frames: frames) else {
            windowDragController.handleMouseDownOutsideTitleBands()
            return
        }
        windowDragController.handleMouseDown(at: screenPoint)
    }

    /// Pré-filtre du glisser de fenêtre : le point tombe dans la bande de titre (44 points, comme
    /// `DropPreviewController.dragSourceWindow`) d'une fenêtre gérée du dernier cycle, avec une
    /// marge de 4 points pour un cadre qui vient de bouger. O(w).
    nonisolated static func clickMayStartWindowDrag(atAXPoint point: CGPoint, frames: [CGRect]) -> Bool {
        frames.contains { frame in
            CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: min(44, frame.height))
                .insetBy(dx: -4, dy: -4).contains(point)
        }
    }

    private func handleRightMouse(_ type: NSEvent.EventType, at screenPoint: CGPoint, fromGlobalMonitor: Bool = false) -> Bool {
        switch type {
        case .rightMouseDown:
            dragGhost?.hide()
            if pendingStageReorder != nil {
                panels.values.forEach { $0.hideStageReorderPreview() }
                pendingStageReorder = nil
            }
            for (displayID, panel) in panels {
                guard panel.isVisible,
                      panel.frame.contains(screenPoint),
                      !(fromGlobalMonitor && panel.ignoresMouseEvents),
                      let payload = panel.stageDragPayload(at: screenPoint)
                else { continue }
                pendingStageReorder = PendingStageReorder(
                    displayID: displayID,
                    stageID: payload.stageID,
                    windowID: payload.windowID,
                    startPoint: screenPoint,
                    didDrag: false
                )
                return true
            }
            return false

        case .rightMouseDragged:
            guard var reorder = pendingStageReorder else { return false }
            if reorder.didDrag || hypot(screenPoint.x - reorder.startPoint.x, screenPoint.y - reorder.startPoint.y) > 6 {
                reorder.didDrag = true
                pendingStageReorder = reorder
                panels[reorder.displayID]?.showStageReorderPreview(at: screenPoint, sourceStageID: reorder.stageID)
            }
            return true

        case .rightMouseUp:
            guard let reorder = pendingStageReorder else { return false }
            // Lire la destination aimantée avant de retirer l’aperçu qui la mémorise.
            let position = reorder.didDrag
                ? panels[reorder.displayID]?.stageReorderPosition(at: screenPoint, sourceStageID: reorder.stageID) : nil
            pendingStageReorder = nil
            panels.values.forEach { $0.hideStageReorderPreview() }
            dragGhost?.hide()
            guard let panel = panels[reorder.displayID] else { return true }
            if reorder.didDrag {
                if let position {
                    events.append(RoadieEvent(type: "rail_stage_drop", details: [
                        "stage_id": reorder.stageID.rawValue, "display_id": reorder.displayID.rawValue,
                        "x": String(Double(screenPoint.x)), "y": String(Double(screenPoint.y)), "position": String(position),
                    ]))
                    perform(.moveStage(reorder.stageID, position), displayID: reorder.displayID)
                    rebuildPanels()
                }
                return true
            }
            showStageMenu(stageID: reorder.stageID, displayID: reorder.displayID, windowID: reorder.windowID, panel: panel, at: screenPoint)
            return true

        default:
            return false
        }
    }

    private func showStageMenu(stageID: StageID, displayID: DisplayID, windowID: WindowID?, panel: RailPanel, at screenPoint: CGPoint) {
        stageMenuTargets.removeAll(keepingCapacity: true)
        guard panel.isVisible, panel.frame.contains(screenPoint) else { return }
        guard panel.stageID(at: screenPoint) == stageID else { return }

        let snapshot = snapshotService.sharedSnapshot()
        let targets = Self.stageDisplayMoveTargets(sourceDisplayID: displayID, in: snapshot)
        let currentName = stageName(stageID: stageID, displayID: displayID)

        let menu = NSMenu(title: currentName)
        if let windowID {
            addWindowSection(to: menu, windowID: windowID, stageID: stageID, displayID: displayID, snapshot: snapshot)
            menu.addItem(.separator())
        }

        let stageHeader = NSMenuItem(title: "Stage", action: nil, keyEquivalent: "")
        stageHeader.isEnabled = false
        menu.addItem(stageHeader)

        let renameTarget = RailMenuActionTarget { [weak self] in
            self?.promptRenameStage(stageID: stageID, displayID: displayID, currentName: currentName)
        }
        let renameItem = NSMenuItem(title: "Renommer \"\(currentName)\"...", action: #selector(RailMenuActionTarget.choose(_:)), keyEquivalent: "")
        renameItem.target = renameTarget
        stageMenuTargets.append(renameTarget)
        menu.addItem(renameItem)

        let moveMenu = NSMenu(title: "Envoyer la stage vers ecran")
        if targets.isEmpty {
            let item = NSMenuItem(title: "Aucun autre ecran", action: nil, keyEquivalent: "")
            item.isEnabled = false
            moveMenu.addItem(item)
        } else {
            for targetDisplay in targets {
                let title = "Ecran \(targetDisplay.index) - \(targetDisplay.name)"
                let item = NSMenuItem(title: title, action: #selector(RailStageMoveMenuTarget.choose(_:)), keyEquivalent: "")
                item.representedObject = targetDisplay.id.rawValue
                let target = RailStageMoveMenuTarget { [weak self] selectedDisplayID in
                    guard let self else { return }
                    self.perform(.moveStageToDisplay(stageID, selectedDisplayID), displayID: displayID)
                    self.rebuildPanels()
                }
                item.target = target
                stageMenuTargets.append(target)
                moveMenu.addItem(item)
            }
        }
        let moveItem = NSMenuItem(title: "Envoyer la stage vers ecran", action: nil, keyEquivalent: "")
        moveItem.submenu = moveMenu
        menu.addItem(moveItem)

        applyFont(to: menu, font: currentStageTextConfig.font)
        menu.popUp(positioning: nil, at: panel.convertPoint(fromScreen: screenPoint), in: panel.contentView)
    }

    private var currentStageTextConfig: RailStageLabelConfig {
        RailVisualConfig.load(settings: RailSettings.load(
            path: ConfigReloadService.shared.state.activePath ?? RoadieConfigLoader.defaultConfigPath()
        )).stageLabel
    }

    private func applyFont(to menu: NSMenu, font: NSFont) {
        menu.font = font
        menu.items.compactMap(\.submenu).forEach { applyFont(to: $0, font: font) }
    }

    private func addWindowSection(
        to menu: NSMenu,
        windowID: WindowID,
        stageID: StageID,
        displayID: DisplayID,
        snapshot: DaemonSnapshot
    ) {
        let header = NSMenuItem(title: "Fenetre", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let stageMenu = NSMenu(title: "Envoyer la fenetre vers stage")
        for target in windowStageTargets(displayID: displayID, excluding: stageID, snapshot: snapshot) {
            let item = NSMenuItem(title: target.title, action: #selector(RailMenuActionTarget.choose(_:)), keyEquivalent: "")
            let action = RailMenuActionTarget { [weak self] in
                guard let self else { return }
                self.perform(.moveWindow(windowID, target.stageID, nil, true), displayID: displayID)
                self.rebuildPanels()
            }
            item.target = action
            stageMenuTargets.append(action)
            stageMenu.addItem(item)
        }
        let stageItem = NSMenuItem(title: "Envoyer la fenetre vers stage", action: nil, keyEquivalent: "")
        stageItem.submenu = stageMenu
        menu.addItem(stageItem)

        let desktopMenu = NSMenu(title: "Envoyer la fenetre vers desktop")
        for target in windowDesktopTargets(displayID: displayID) {
            let item = NSMenuItem(title: target.title, action: #selector(RailMenuActionTarget.choose(_:)), keyEquivalent: "")
            let action = RailMenuActionTarget { [weak self] in
                guard let self else { return }
                self.perform(.moveWindowToDesktop(windowID, target.desktopID), displayID: displayID)
                self.rebuildPanels()
            }
            item.target = action
            stageMenuTargets.append(action)
            desktopMenu.addItem(item)
        }
        let desktopItem = NSMenuItem(title: "Envoyer la fenetre vers desktop", action: nil, keyEquivalent: "")
        desktopItem.submenu = desktopMenu
        menu.addItem(desktopItem)

        let displayMenu = NSMenu(title: "Envoyer la fenetre vers ecran")
        let displayTargets = Self.stageDisplayMoveTargets(sourceDisplayID: displayID, in: snapshot)
        if displayTargets.isEmpty {
            let item = NSMenuItem(title: "Aucun autre ecran", action: nil, keyEquivalent: "")
            item.isEnabled = false
            displayMenu.addItem(item)
        } else {
            for targetDisplay in displayTargets {
                let item = NSMenuItem(title: "Ecran \(targetDisplay.index) - \(targetDisplay.name)", action: #selector(RailMenuActionTarget.choose(_:)), keyEquivalent: "")
                let action = RailMenuActionTarget { [weak self] in
                    guard let self else { return }
                    self.perform(.moveWindowToDisplay(windowID, targetDisplay.id), displayID: displayID)
                    self.rebuildPanels()
                }
                item.target = action
                stageMenuTargets.append(action)
                displayMenu.addItem(item)
            }
        }
        let displayItem = NSMenuItem(title: "Envoyer la fenetre vers ecran", action: nil, keyEquivalent: "")
        displayItem.submenu = displayMenu
        menu.addItem(displayItem)
    }

    private func windowStageTargets(displayID: DisplayID, excluding sourceStageID: StageID, snapshot: DaemonSnapshot) -> [(title: String, stageID: StageID)] {
        var state = store.state()
        let desktopID = state.currentDesktopID(for: displayID)
        let scope = state.scope(displayID: displayID, desktopID: desktopID)
        let liveIDs = snapshotService.railWindowIDs(in: snapshot)
        let order = StagePresentationOrder(scope: scope, liveWindowIDs: liveIDs)
        var targets: [(String, StageID)] = []
        for (index, stage) in order.visibleStages.enumerated() where stage.id != sourceStageID {
            targets.append((StagePresentationOrder.menuLabel(stage, position: index + 1), stage.id))
        }
        let emptyID = order.emptyStageIDs.first ?? nextGeneratedStageID(in: scope)
        if emptyID != sourceStageID {
            targets.append(("Prochaine stage vide", emptyID))
        }
        return targets
    }

    private func windowDesktopTargets(displayID: DisplayID) -> [(title: String, desktopID: DesktopID)] {
        let state = store.state()
        let current = state.currentDesktopID(for: displayID)
        return (1...6).compactMap { raw in
            let desktopID = DesktopID(rawValue: raw)
            guard desktopID != current else { return nil }
            let label = state.label(displayID: displayID, desktopID: desktopID)
            let title = label.map { "Desktop \(raw) - \($0)" } ?? "Desktop \(raw)"
            return (title, desktopID)
        }
    }

    private func promptRenameStage(stageID: StageID, displayID: DisplayID, currentName: String) {
        // `ignoringOtherApps` est ignore depuis macOS 14 : l'activation cooperative suffit pour l'alerte.
        NSApplication.shared.activate()
        let textConfig = currentStageTextConfig
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: textConfig.lineHeight + 8))
        input.font = textConfig.font
        input.stringValue = currentName
        input.selectText(nil)

        let alert = NSAlert()
        alert.messageText = "Renommer la stage"
        alert.informativeText = "Nouveau nom pour \(currentName)"
        alert.accessoryView = input
        alert.addButton(withTitle: "Renommer")
        alert.addButton(withTitle: "Annuler")
        alert.buttons.forEach { $0.font = textConfig.font }

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let trimmed = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != currentName else { return }
        perform(.renameStage(stageID, trimmed), displayID: displayID)
        rebuildPanels()
    }

    private func stageName(stageID: StageID, displayID: DisplayID) -> String {
        var state = store.state()
        let desktopID = state.currentDesktopID(for: displayID)
        let scope = state.scope(displayID: displayID, desktopID: desktopID)
        return scope.stages.first { $0.id == stageID }?.name ?? "Stage \(stageID.rawValue)"
    }

    private func nextGeneratedStageID(in scope: PersistentStageScope) -> StageID {
        let used = Set(scope.stages.map(\.id.rawValue))
        for index in 1...99 where !used.contains(String(index)) {
            return StageID(rawValue: String(index))
        }
        return StageID(rawValue: UUID().uuidString)
    }

    private func perform(_ action: RailAction, displayID: DisplayID) {
        switch action {
        case .switchStage(let stageID):
            print("rail switch stage \(stageID.rawValue)")
            fflush(stdout)
            events.append(RoadieEvent(type: "rail_stage_switch", details: ["displayID": displayID.rawValue, "stageID": stageID.rawValue]))
            _ = commandService.switchTo(stageID.rawValue, displayID: displayID)
        case .focusNativeFullscreen(let windowID, let bundleID, let stageID):
            print("rail focus native fullscreen \(windowID.rawValue)")
            fflush(stdout)
            events.append(RoadieEvent(type: "rail_native_fullscreen_focus", details: [
                "displayID": displayID.rawValue,
                "stageID": stageID.rawValue,
                "windowID": String(windowID.rawValue),
                "bundleID": bundleID
            ]))
            _ = commandService.focusNativeFullscreen(
                windowID: windowID,
                bundleID: bundleID,
                stageID: stageID,
                displayID: displayID
            )
        case .summonWindow(let windowID):
            print("rail summon window \(windowID.rawValue)")
            fflush(stdout)
            events.append(RoadieEvent(type: "rail_window_summon", details: ["displayID": displayID.rawValue, "windowID": String(windowID.rawValue)]))
            _ = commandService.summon(windowID: windowID, displayID: displayID)
        case .moveWindow(let windowID, let stageID, let insertionIndex, let focusAssignedWindow, let stageInsertion):
            let insertionDescription = insertionIndex.map { " index \($0)" } ?? ""
            print("rail move window \(windowID.rawValue) -> stage \(stageID.rawValue)\(insertionDescription)")
            fflush(stdout)
            var details = [
                "displayID": displayID.rawValue,
                "windowID": String(windowID.rawValue),
                "stageID": stageID.rawValue,
                "focusAssignedWindow": String(focusAssignedWindow),
            ]
            if let insertionIndex {
                details["insertionIndex"] = String(insertionIndex)
            }
            if let stageInsertion { details["stageInsertion"] = stageInsertion.eventDescription }
            events.append(RoadieEvent(
                type: "rail_window_move",
                details: details
            ))
            _ = commandService.assign(
                windowID: windowID,
                to: stageID.rawValue,
                displayID: displayID,
                insertionIndex: insertionIndex,
                stageInsertion: stageInsertion,
                focusAssignedWindow: focusAssignedWindow
            )
        case .moveWindowToDesktop(let windowID, let desktopID):
            print("rail move window \(windowID.rawValue) -> desktop \(desktopID.rawValue)")
            fflush(stdout)
            events.append(RoadieEvent(
                type: "rail_window_desktop",
                details: ["displayID": displayID.rawValue, "windowID": String(windowID.rawValue), "desktopID": String(desktopID.rawValue)]
            ))
            _ = desktopCommandService.assign(windowID: windowID, to: desktopID, displayID: displayID, follow: false)
        case .moveWindowToDisplay(let windowID, let targetDisplayID):
            print("rail move window \(windowID.rawValue) -> display \(targetDisplayID.rawValue)")
            fflush(stdout)
            events.append(RoadieEvent(
                type: "rail_window_display",
                details: ["displayID": displayID.rawValue, "windowID": String(windowID.rawValue), "targetDisplayID": targetDisplayID.rawValue]
            ))
            _ = commandService.summon(windowID: windowID, displayID: targetDisplayID)
        case .placeWindow(let candidate):
            let windowID = candidate.sourceWindowID
            print("rail place window \(windowID.rawValue)")
            fflush(stdout)
            events.append(RoadieEvent(
                type: "rail_window_place",
                details: ["displayID": displayID.rawValue, "windowID": String(windowID.rawValue)]
            ))
            _ = commandService.place(
                windowID: windowID,
                displayID: displayID,
                orderedWindowIDs: candidate.orderedWindowIDs,
                placements: candidate.placements,
                treeMutation: candidate.treeMutation
            )
        case .moveStage(let stageID, let position):
            print("rail reorder stage \(stageID.rawValue) -> \(position)")
            fflush(stdout)
            events.append(RoadieEvent(
                type: "rail_stage_reorder",
                details: ["displayID": displayID.rawValue, "stageID": stageID.rawValue, "position": String(position)]
            ))
            _ = commandService.reorder(stageID.rawValue, to: position, displayID: displayID)
        case .renameStage(let stageID, let name):
            print("rail rename stage \(stageID.rawValue) -> \(name)")
            fflush(stdout)
            events.append(RoadieEvent(
                type: "rail_stage_rename",
                details: ["displayID": displayID.rawValue, "stageID": stageID.rawValue]
            ))
            // Nom déjà porté par une autre stage (SPEC-067) : refus signalé par le son d’alerte système.
            if commandService.rename(stageID.rawValue, to: name, displayID: displayID).outcome == .failed { NSSound.beep() }
        case .moveStageToDisplay(let stageID, let targetDisplayID):
            print("rail move stage \(stageID.rawValue) -> display \(targetDisplayID.rawValue)")
            fflush(stdout)
            events.append(RoadieEvent(
                type: "rail_stage_move_display",
                details: [
                    "displayID": displayID.rawValue,
                    "stageID": stageID.rawValue,
                    "targetDisplayID": targetDisplayID.rawValue
                ]
            ))
            _ = commandService.moveStageToDisplay(
                stageID: stageID,
                sourceDisplayID: displayID,
                targetDisplayID: targetDisplayID,
                source: "rail"
            )
        }
    }

    private func handleMouseDragged(to screenPoint: CGPoint) {
        guard var drag = pendingDrag else {
            windowDragController.handleMouseDragged(to: screenPoint)
            if windowDragController.activeDraggedWindowIDForDrop() != nil,
               showWindowDropPreviews(at: screenPoint) { dropPreview.hide() }
            return
        }
        if hypot(screenPoint.x - drag.startPoint.x, screenPoint.y - drag.startPoint.y) > 6 {
            if !drag.didDrag {
                if dragGhost == nil {
                    dragGhost = RailDragGhostWindow()
                }
                dragGhost?.show(image: thumbnails.cachedImage(for: drag.windowID), at: screenPoint, grabUnit: drag.grabUnit)
                // Un seul snapshot pour tout le drag (SPEC-016 FR-025).
                dropPreview.beginDrag()
            } else {
                dragGhost?.move(to: screenPoint, grabUnit: drag.grabUnit)
            }
            if let targetDisplayID = displayID(at: screenPoint),
               panels.values.allSatisfy({ !$0.frame.contains(screenPoint) }) {
                _ = dropPreview.update(sourceWindowID: drag.windowID, at: screenPoint, displayID: targetDisplayID)
            } else {
                dropPreview.hide()
            }
            drag.didDrag = true
            pendingDrag = drag
            _ = showWindowDropPreviews(at: screenPoint)
        }
    }

    private func showWindowDropPreviews(at point: CGPoint) -> Bool {
        var shown = false
        for panel in panels.values where panel.isVisible {
            if panel.showWindowDropPreview(at: point) != nil { shown = true }
        }
        return shown
    }

    private func handleMouseUp(at screenPoint: CGPoint) {
        defer {
            panels.values.forEach { $0.hideWindowDropPreview() }
            rebuildPanels()
        }
        guard let drag = pendingDrag else {
            if handleWindowDropOnRail(at: screenPoint) {
                return
            }
            windowDragController.handleMouseUp(at: screenPoint)
            return
        }
        pendingDrag = nil
        dragGhost?.hide()
        defer { dropPreview.endDrag() }

        guard drag.didDrag else {
            perform(drag.clickAction ?? .switchStage(drag.sourceStageID), displayID: drag.displayID)
            rebuildPanels()
            return
        }

        guard let targetDisplayID = displayID(at: screenPoint),
              let panel = panels[targetDisplayID] else { return }
        guard let target = panel.windowDropTarget(at: screenPoint) else {
            guard displayID(at: screenPoint) != nil else { return }
            print("rail drag summon window \(drag.windowID.rawValue)")
            fflush(stdout)
            if let candidate = dropPreview.update(sourceWindowID: drag.windowID, at: screenPoint, displayID: targetDisplayID) {
                perform(.placeWindow(candidate), displayID: candidate.displayID)
            } else {
                perform(.summonWindow(drag.windowID), displayID: targetDisplayID)
            }
            rebuildPanels()
            return
        }
        guard Self.railDropMovesWindow(
            sourceDisplayID: drag.displayID,
            sourceStageID: drag.sourceStageID,
            targetDisplayID: targetDisplayID,
            targetStageID: target.stageID
        ) else { return }
        print("rail drag window \(drag.windowID.rawValue) -> stage \(target.stageID.rawValue) index \(target.insertionIndex)")
        fflush(stdout)
        applyRailWindowDrop(drag.windowID, target: target, displayID: targetDisplayID, at: screenPoint)
        rebuildPanels()
    }

    private func handleWindowDropOnRail(at screenPoint: CGPoint) -> Bool {
        guard let windowID = windowDragController.activeDraggedWindowIDForDrop() else {
            return false
        }
        for (displayID, panel) in panels {
            guard panel.isVisible,
                  let target = panel.windowDropTarget(at: screenPoint)
            else { continue }
            windowDragController.cancelPendingDrag()
            // Dépôt reconnu sur le navrail : il consomme la session de geste (A17).
            _ = UserInputActivity.shared.takeGesture()
            print("rail external drag window \(windowID.rawValue) -> stage \(target.stageID.rawValue) index \(target.insertionIndex)")
            fflush(stdout)
            applyRailWindowDrop(windowID, target: target, displayID: displayID, at: screenPoint)
            rebuildPanels()
            return true
        }
        return false
    }

    private func applyRailWindowDrop(_ windowID: WindowID, target: RailWindowDropTarget,
                                     displayID: DisplayID, at point: CGPoint) {
        events.append(RoadieEvent(type: "rail_window_drop", details: [
            "windowID": String(windowID.rawValue), "displayID": displayID.rawValue,
            "stageID": target.stageID.rawValue, "x": String(Double(point.x)), "y": String(Double(point.y)),
            "coordinateSpace": "screen_ns",
            "kind": target.stageInsertion == nil ? "existing_stage" : "new_stage",
            "stageInsertion": target.stageInsertion?.eventDescription ?? "existing"
        ]))
        perform(.moveWindow(windowID, target.stageID, target.insertionIndex, false,
                            stageInsertion: target.stageInsertion), displayID: displayID)
    }

    /// Cycle de rafraichissement du rail. Le snapshot partage est lu a chaque appel (le timer tourne chaque seconde),
    /// mais les vues ne sont reconstruites que si le contenu visible a change (SPEC-016 FR-024) :
    /// stages, membres, etats de presentation, ecrans masques, configuration, vignettes.
    // Complexite : O(d * (s + n)) - d = ecrans, s = stages, n = fenetres du snapshot.
    private func rebuildPanels(reason: String = "direct", requestedAt: Date? = nil, railSignature: String? = nil) {
        guard !defersPanelRebuild else { return }
        pendingRebuild = (reason, requestedAt)
        guard rebuildTask == nil else { return }
        let service = snapshotService
        rebuildTask = Task { [weak self] in
            let result = await service.readerSnapshot()
            guard !Task.isCancelled else { return }
            guard let snapshot = result else {
                self?.rebuildTask = nil
                return
            }
            guard let self else { return }
            let request = self.pendingRebuild ?? (reason, requestedAt)
            self.pendingRebuild = nil
            self.rebuildTask = nil
            self.renderPanels(snapshot: snapshot, reason: request.reason, requestedAt: request.requestedAt)
        }
    }

    /// O(1) par tick : décodage seulement après un signal du watcher ou la fin de l'enregistreur.
    private func currentRecordingStatus() -> TargetRecordingStatus? {
        let next = Self.recordingStatus(cached: recordingStatusCache, dirty: recordingStatusDirty,
                                        isAlive: ProcessLiveness.isAlive,
                                        load: { TargetRecordingStatusStore().activeStatus() })
        recordingStatusCache = next
        recordingStatusDirty = false
        return next
    }

    /// Statut à afficher : relu seulement si le watcher l'a signalé ou si l'enregistreur a disparu. O(1).
    nonisolated static func recordingStatus(
        cached: TargetRecordingStatus?,
        dirty: Bool,
        isAlive: (pid_t) -> Bool,
        load: () -> TargetRecordingStatus?
    ) -> TargetRecordingStatus? {
        if dirty { return load() }
        guard let cached else { return nil }
        return isAlive(cached.pid) ? cached : load()
    }

    private func renderPanels(snapshot: DaemonSnapshot, reason: String, requestedAt: Date?) {
        // Les cartes restent fixes entre l'appui et le dépôt ; le cycle suivant applique les nouveautés.
        guard !defersPanelRebuild else { return }
        let startedAt = Date()
        let latencyMs = requestedAt.map { startedAt.timeIntervalSince($0) * 1000 }
        let configPath = ConfigReloadService.shared.state.activePath ?? RoadieConfigLoader.defaultConfigPath()
        lastConfigRefreshPath = configPath
        lastConfigRefreshStamp = fileModificationStamp(configPath)
        let snapshotMs = Date().timeIntervalSince(startedAt) * 1000
        updateFocusSensitiveCaptureProtection(from: snapshot)
        let state = store.state()
        lastStageStoreRailSignature = Self.railSignature(for: state)
        let settings = RailSettings.load(path: configPath)
        var config = RailVisualConfig.load(settings: settings)
        let runtimeState = railRuntimeStateStore.load()
        config.stageLabel.visibleUntil = runtimeState.stageLabelsVisibleUntil
        let recordConfig = snapshotService.effectiveConfig.experimental.targetRecord
        let recordingStatus: TargetRecordingStatus?
        if recordConfig.indicator.showsNavrail {
            recordingStatus = currentRecordingStatus()
        } else {
            recordingStatus = nil
            recordingStatusDirty = true // relu au réaffichage de l'indicateur
        }
        let recordingIndicatorBottomOffset = CGFloat(recordConfig.navrailBottomOffset)
        let liveWindowIDs = snapshotService.railWindowIDs(in: snapshot, state: state)
        let protectedWindowIDs = Set(protectedBlurredWindows.keys)
        // Deux ecrans peuvent partager un UUID (clones, docks) : on garde le premier au lieu de planter.
        let screensByDisplayID = Dictionary(NSScreen.screens.compactMap { screen in
            Self.displayID(for: screen).map { ($0, screen) }
        }, uniquingKeysWith: { first, _ in first })
        // Une lecture d'intent par scope : le zoom adapté au rail reste réversible au survol.
        let zoom = Self.railZoomWindowIDs(in: snapshot, intentForScope: snapshotService.commandLayoutIntent)
        let hiddenDisplayIDs = Self.railHiddenDisplayIDs(
            in: snapshot,
            hideOnMaximized: config.hideOnMaximized,
            railAwareZoomWindowIDs: zoom.reservingRail,
            fullscreenWindowIDs: zoom.fullscreen
        )
        updateManagedWindowFrames(from: snapshot)

        // Contenu visible de chaque ecran : sert a la signature, aux captures de vignettes et au rendu.
        var contents: [DisplayID: RailDisplayContent] = [:]
        var displaySignatures: [DisplayID: String] = [:]
        var thumbnailSignatures: [DisplayID: String] = [:]
        let sharedSignature = [
            "recording=\(recordingStatus?.name ?? "-"):\(recordingIndicatorBottomOffset)",
            "pinned=\(runtimeState.isPinned)",
            "labelUntil=\(runtimeState.stageLabelsVisibleUntil.map { String($0) } ?? "-")",
        ].joined(separator: "|")
        var visibleMembers: [PersistentStageMember] = []
        var representedWindowIDs: Set<WindowID> = []
        for displayID in screensByDisplayID.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let screen = screensByDisplayID[displayID] else { continue }
            let desktopID = state.currentDesktopID(for: displayID)
            let scope = state.scopes.first { $0.displayID == displayID && $0.desktopID == desktopID }
                ?? PersistentStageScope(displayID: displayID, desktopID: desktopID)
            let content = contentCache.content(
                scope: scope,
                presentationStates: Self.railWindowPresentationStates(in: scope, snapshot: snapshot),
                liveWindowIDs: liveWindowIDs, now: startedAt
            )
            contents[displayID] = content
            let memberIDs = content.stages.flatMap(\.members).map(\.windowID)
            displaySignatures[displayID] = "\(sharedSignature)|hidden=\(hiddenDisplayIDs.contains(displayID))|\(screen.frame)|\(screen.visibleFrame)|\(screen.localizedName)|\(content.signature)"
            thumbnailSignatures[displayID] = thumbnails.revisionSignature(for: memberIDs)
            // SPEC-051 C-06 : un rail replié ne montre aucune vignette ; elles reprennent au dépliage.
            if !hiddenDisplayIDs.contains(displayID), panels[displayID]?.isRailCollapsed != true {
                visibleMembers.append(contentsOf: content.stages.flatMap(\.members))
            }
            representedWindowIDs.formUnion(content.stages.flatMap(\.members).map(\.windowID))
        }
        // Les membres encore representes (retenus 15 s) gardent leur vignette ; seuls les autres sont purges.
        thumbnails.prune(keeping: representedWindowIDs)
        let initialThumbnailCaptureBudget = thumbnailCaptureBudget(for: reason, now: startedAt)
        let visibleIDs = Set(visibleMembers.map(\.windowID))
        let liveFrames = Dictionary(
            snapshot.windows.compactMap { visibleIDs.contains($0.window.id) ? ($0.window.id, $0.window.frame) : nil },
            uniquingKeysWith: { first, _ in first }
        )
        thumbnails.requestCaptures(
            for: visibleMembers,
            protectedWindowIDs: protectedWindowIDs,
            liveFrames: liveFrames,
            displayWidth: config.previewWidth,
            budget: initialThumbnailCaptureBudget
        )
        if Self.isInteractiveRefresh(reason) {
            lastInteractiveRailRefreshAt = Date()
        }

        let changedDisplays = Self.changedDisplayIDs(previous: lastRenderSignatures, current: displaySignatures,
                                                     settingsChanged: settings != lastRenderedSettings)
        let thumbnailOnlyDisplays = Self.changedDisplayIDs(previous: lastThumbnailSignatures, current: thumbnailSignatures,
                                                           settingsChanged: false).subtracting(changedDisplays)
        lastThumbnailSignatures = thumbnailSignatures
        for displayID in thumbnailOnlyDisplays where !hiddenDisplayIDs.contains(displayID) {
            panels[displayID]?.refreshThumbnails(thumbnails)
        }
        guard !changedDisplays.isEmpty else { return }
        lastRenderSignatures = displaySignatures
        lastRenderedSettings = settings
        contentCache.prune(keeping: Set(screensByDisplayID.keys))

        var renderedStages = 0
        for (displayID, screen) in screensByDisplayID where changedDisplays.contains(displayID) {
            screenFrames[displayID] = screen.frame
            guard let content = contents[displayID] else { continue }
            if hiddenDisplayIDs.contains(displayID) {
                panels[displayID]?.orderOut(nil)
                continue
            }
            let panel = panels[displayID] ?? RailPanel()
            panel.onVisibleWidthChanged = { [weak self] displayID in
                self?.relayoutAfterRailWidthChange(on: displayID)
            }
            panel.onRevealed = { [weak self] _ in self?.rebuildPanels(reason: "reveal") }
            panel.position(on: screen, displayID: displayID, config: config, runtimeStore: railRuntimeStateStore)
            renderedStages += content.stages.count
            panel.render(
                content: content,
                displayName: screen.localizedName,
                config: config,
                thumbnails: thumbnails,
                recordingStatus: recordingStatus,
                recordingIndicatorBottomOffset: recordingIndicatorBottomOffset
            )
            if panels[displayID] == nil {
                panels[displayID] = panel
                panel.makeKey()
                panel.orderFrontRegardless()
            } else if !panel.isVisible {
                panel.orderFrontRegardless()
            }
        }

        for displayID in panels.keys where screensByDisplayID[displayID] == nil {
            panels[displayID]?.orderOut(nil)
            panels.removeValue(forKey: displayID)
            screenFrames.removeValue(forKey: displayID)
        }
        scheduleStageLabelFade(config.stageLabel)
        let totalMs = Date().timeIntervalSince(startedAt) * 1000
        if reason != "timer" || totalMs >= 80 {
            var details = [
                "reason": reason,
                "durationMs": Self.formatMs(totalMs),
                "snapshotMs": Self.formatMs(snapshotMs),
                "displays": String(screensByDisplayID.count),
                "stages": String(renderedStages),
                "thumbnailCaptureBudget": String(initialThumbnailCaptureBudget),
            ]
            if let latencyMs {
                details["latencyMs"] = Self.formatMs(latencyMs)
            }
            events.append(RoadieEvent(type: "rail_refresh", details: details))
        }
    }

    nonisolated static func changedDisplayIDs(previous: [DisplayID: String], current: [DisplayID: String],
                                             settingsChanged: Bool) -> Set<DisplayID> {
        let ids = Set(previous.keys).union(current.keys)
        return settingsChanged ? ids : Set(ids.filter { previous[$0] != current[$0] })
    }

    private static func formatMs(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// Nombre maximal de captures lancees par cycle. Juste apres une action de l'utilisateur, aucune :
    /// le rail reste reactif, les vignettes se rafraichissent au cycle suivant.
    private func thumbnailCaptureBudget(for reason: String, now: Date) -> Int {
        switch reason {
        case "stage_store", "direct":
            return 0
        case "timer":
            if now.timeIntervalSince(lastInteractiveRailRefreshAt) < 2 {
                return 0
            }
            return 1
        default:
            return 8
        }
    }

    private static func isInteractiveRefresh(_ reason: String) -> Bool {
        reason == "stage_store" || reason == "direct"
    }

    // Complexite : O(n) - un seul passage sur les fenetres du snapshot.
    private func updateManagedWindowFrames(from snapshot: DaemonSnapshot) {
        var displayByActiveScope: [StageScope: DisplayID] = [:]
        for display in snapshot.displays {
            if let scope = snapshot.state.activeScope(on: display.id) {
                displayByActiveScope[scope] = display.id
            }
        }
        var frames: [DisplayID: [CGRect]] = [:]
        for entry in snapshot.windows where entry.window.isTileCandidate {
            if let scope = entry.scope, let displayID = displayByActiveScope[scope] {
                frames[displayID, default: []].append(entry.window.frame.cgRect)
            }
        }
        managedWindowFrames = frames
    }

    // Resize conserve sa disposition ; overlay adapte uniquement le zoom qui suit ce rail.
    // O(c + w) : index par fenêtre en resize, une seule cible en overlay.
    func relayoutAfterRailWidthChange(on displayID: DisplayID) {
        let settings = snapshotService.currentRailSettings()
        // Changement de largeur du rail : intention externe, nouvelle génération (A13, T213).
        let generation = PlacementGeneration.shared.next()
        let snapshot = snapshotService.snapshot()
        let commands: [ApplyCommand]
        if settings.layoutMode == "resize" {
            let displayByWindow: [WindowID: DisplayID] = Dictionary(
                snapshot.windows.compactMap { entry in
                    entry.scope.map { (entry.window.id, $0.displayID) }
                },
                uniquingKeysWith: { first, _ in first }
            )
            commands = snapshotService.applyPlan(from: snapshot, generation: generation).commands.filter { command in
                displayByWindow[command.window.id] == displayID
            }
        } else {
            guard let scope = snapshot.state.activeScope(on: displayID),
                  let intent = snapshotService.commandLayoutIntent(scope: scope),
                  intent.zoomReservesRail == true,
                  let zoomedID = intent.zoomedWindowID,
                  let entry = snapshot.windows.first(where: { $0.window.id == zoomedID && $0.scope == scope }),
                  entry.window.furniture?.isNativeFullscreen != true,
                  entry.window.isTileCandidate,
                  let display = snapshot.displays.first(where: { $0.id == displayID }),
                  let target = snapshotService.maximizedFrame(on: display) else { return }
            let observed = entry.window.frame.cgRect
            let matches = LayoutMaintainer.matches(observed, target)
                && observed.minX >= target.minX && display.visibleFrame.cgRect.contains(observed)
            commands = matches ? [] : [ApplyCommand(window: entry.window, frame: Rect(target))]
        }
        guard !commands.isEmpty else { return }
        let result = snapshotService.apply(ApplyPlan(commands: commands), generation: generation)
        print("rail relayout display=\(displayID.rawValue) commands=\(commands.count) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)")
        fflush(stdout)
    }

    private func updateFocusSensitiveCaptureProtection(from snapshot: DaemonSnapshot) {
        let now = Date()
        protectedBlurredWindows = protectedBlurredWindows.filter { $0.value > now }
        defer { focusedWindowID = snapshot.focusedWindowID }

        guard let previous = focusedWindowID,
              previous != snapshot.focusedWindowID,
              let entry = snapshot.windows.first(where: { $0.window.id == previous }),
              RailThumbnailStore.isDRMSensitiveBundle(entry.window.bundleID)
        else { return }

        protectedBlurredWindows[previous] = now.addingTimeInterval(3)
    }

    private func displayID(at screenPoint: CGPoint) -> DisplayID? {
        screenFrames.first { _, frame in frame.contains(screenPoint) }?.key
    }

    // Complexite : O(w) - w = fenetres gerees de l'ecran, lues dans les cadres du dernier cycle (0 snapshot).
    private func emptyRailClickHitsManagedWindow(at screenPoint: CGPoint, displayID: DisplayID) -> Bool {
        let axPoint = Self.nsToAX(screenPoint)
        return managedWindowFrames[displayID, default: []].contains { $0.insetBy(dx: -2, dy: -2).contains(axPoint) }
    }

    private func railClickWouldHitManagedWindow(at screenPoint: CGPoint, displayID: DisplayID, panel: RailPanel) -> Bool {
        guard panel.isVisible,
              panel.frame.contains(screenPoint),
              !panel.hasDirectRailInteraction(at: screenPoint)
        else { return false }
        if panel.isInSafetyMargin(at: screenPoint) {
            return true
        }
        return emptyRailClickHitsManagedWindow(at: screenPoint, displayID: displayID)
    }

    private static func nsToAX(_ point: CGPoint) -> CGPoint {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let primary else { return point }
        return CGPoint(x: point.x, y: primary.frame.height - point.y)
    }

    /// O(d) : seuls les intents des stages actives déterminent le mode explicite du rail.
    nonisolated static func railZoomWindowIDs(
        in snapshot: DaemonSnapshot, intentForScope: (StageScope) -> LayoutIntent?
    ) -> (reservingRail: Set<WindowID>, fullscreen: Set<WindowID>) {
        var reservingRail: Set<WindowID> = []
        var fullscreen: Set<WindowID> = []
        for display in snapshot.displays {
            guard let scope = snapshot.state.activeScope(on: display.id),
                  let intent = intentForScope(scope), let windowID = intent.zoomedWindowID else { continue }
            if intent.zoomReservesRail == true { reservingRail.insert(windowID) }
            else { fullscreen.insert(windowID) }
        }
        return (reservingRail, fullscreen)
    }

    /// Ecrans devant lesquels le rail se masque (SPEC-016 FR-028) : une fenetre de la stage active, visible a
    /// l'ecran, est en plein écran Roadie explicite ou natif ; avec `hideOnMaximized`, simplement agrandie (voir
    /// `WindowPresentationStateResolver` : une fenetre tilee seule n'est jamais « agrandie »).
    // Complexite : O(n) - n = fenetres du snapshot.
    nonisolated public static func railHiddenDisplayIDs(
        in snapshot: DaemonSnapshot,
        hideOnMaximized: Bool,
        railAwareZoomWindowIDs: Set<WindowID> = [],
        fullscreenWindowIDs: Set<WindowID> = []
    ) -> Set<DisplayID> {
        var displayByActiveScope: [StageScope: DisplayID] = [:]
        for display in snapshot.displays {
            if let scope = snapshot.state.activeScope(on: display.id) {
                displayByActiveScope[scope] = display.id
            }
        }
        let states = WindowPresentationStateResolver().statesByWindowID(in: snapshot)
        var hidden: Set<DisplayID> = []
        for entry in snapshot.windows where entry.window.isTileCandidate && entry.window.isOnScreen {
            guard let scope = entry.scope, let displayID = displayByActiveScope[scope] else { continue }
            if fullscreenWindowIDs.contains(entry.window.id) {
                hidden.insert(displayID)
                continue
            }
            switch states[entry.window.id] {
            case .nativeFullscreen:
                hidden.insert(displayID)
            case .maximized where hideOnMaximized && !railAwareZoomWindowIDs.contains(entry.window.id):
                hidden.insert(displayID)
            default:
                break
            }
        }
        return hidden
    }

    /// Un dépôt de vignette ne déplace rien s'il retombe sur la stage d'origine du même écran.
    /// Les identifiants de stage sont locaux à un écran : la même valeur sur un autre écran
    /// désigne une autre stage, le dépôt doit partir.
    nonisolated static func railDropMovesWindow(
        sourceDisplayID: DisplayID,
        sourceStageID: StageID,
        targetDisplayID: DisplayID,
        targetStageID: StageID
    ) -> Bool {
        sourceDisplayID != targetDisplayID || sourceStageID != targetStageID
    }

    nonisolated public static func stageDisplayMoveTargets(
        sourceDisplayID: DisplayID,
        in snapshot: DaemonSnapshot
    ) -> [DisplaySnapshot] {
        snapshot.displays
            .filter { $0.id != sourceDisplayID }
            .sorted { $0.index < $1.index }
    }

    nonisolated public static func railVisibleStageIDs(
        in scope: PersistentStageScope,
        liveWindowIDs: Set<WindowID>,
        now: Date = Date()
    ) -> [StageID] {
        StagePresentationOrder(scope: scope, liveWindowIDs: liveWindowIDs, now: now).visibleStageIDs
    }

    nonisolated public static func railDisplayStage(
        _ stage: PersistentStage,
        liveWindowIDs: Set<WindowID>,
        now: Date = Date()
    ) -> PersistentStage {
        let liveMembers = stage.members.filter {
            isRailRepresentedMember($0, liveWindowIDs: liveWindowIDs, now: now)
        }
        let liveMemberIDs = Set(liveMembers.map(\.windowID))
        let liveGroups = stage.groups.compactMap { group -> WindowGroup? in
            var updated = group
            for windowID in group.windowIDs where !liveMemberIDs.contains(windowID) {
                updated.remove(windowID)
            }
            return updated.windowIDs.count >= 2 ? updated : nil
        }
        let focusedWindowID = stage.focusedWindowID.flatMap { liveMemberIDs.contains($0) ? $0 : nil }
        let previousFocusedWindowID = stage.previousFocusedWindowID.flatMap { liveMemberIDs.contains($0) ? $0 : nil }
        return PersistentStage(
            id: stage.id,
            name: stage.name,
            mode: stage.mode,
            focusedWindowID: focusedWindowID ?? liveMembers.first?.windowID,
            previousFocusedWindowID: previousFocusedWindowID,
            parkingState: stage.parkingState,
            origin: stage.origin,
            hostDisplayID: stage.hostDisplayID,
            restoredAt: stage.restoredAt,
            members: liveMembers,
            groups: liveGroups
        )
    }

    /// Vraies stages vides automatiques : les membres absents et noms personnels ne sont pas réutilisés.
    nonisolated static func railEmptyStageIDs(
        in scope: PersistentStageScope,
        liveWindowIDs: Set<WindowID>,
        now: Date = Date()
    ) -> [StageID] {
        StagePresentationOrder(scope: scope, liveWindowIDs: liveWindowIDs, now: now).emptyStageIDs
    }

    // Un membre present dans le snapshot est toujours represente. Une fermeture AX confirmée masque
    // immédiatement le membre absent. Une autre absence (changement de stage ou plein écran natif) reste
    // représentée 15 s après `missingSince`, puis sa carte disparait (SPEC-016 FR-027). Cette grâce exige une observation
    // réelle récente : une ancienne référence d'écran reconnecté ne crée pas de carte fantôme.
    nonisolated fileprivate static func isRailRepresentedMember(
        _ member: PersistentStageMember,
        liveWindowIDs: Set<WindowID>,
        now: Date = Date()
    ) -> Bool {
        if liveWindowIDs.contains(member.windowID) {
            return true
        }
        if member.confirmedClosedAt != nil {
            return false
        }
        guard let missingSince = member.missingSince, let lastSeenAt = member.lastSeenAt else { return false }
        let observationAge = missingSince.timeIntervalSince(lastSeenAt)
        let missingAge = now.timeIntervalSince(missingSince)
        return observationAge >= 0 && observationAge <= transientMissingMemberRailGrace
            && missingAge >= 0 && missingAge <= transientMissingMemberRailGrace
    }

    // Complexite : O(n + m) - n = fenetres du snapshot, m = membres du scope.
    nonisolated public static func railWindowPresentationStates(
        in scope: PersistentStageScope,
        snapshot: DaemonSnapshot
    ) -> [WindowID: WindowPresentationState] {
        guard let display = snapshot.displays.first(where: { $0.id == scope.displayID }) else {
            return [:]
        }
        var windowsByID: [WindowID: WindowSnapshot] = [:]
        for entry in snapshot.windows {
            windowsByID[entry.window.id] = entry.window
        }
        let tiledCounts = WindowPresentationStateResolver.tiledWindowCounts(in: snapshot)
        var states: [WindowID: WindowPresentationState] = [:]
        for stage in scope.stages {
            let stageScope = StageScope(displayID: scope.displayID, desktopID: scope.desktopID, stageID: stage.id)
            let isOnlyTiledWindowInStage = tiledCounts[stageScope, default: 0] <= 1
            for member in stage.members {
                if let window = windowsByID[member.windowID] {
                    states[member.windowID] = WindowPresentationStateResolver.state(
                        for: window,
                        on: display,
                        frameOverride: member.frame,
                        isOnlyTiledWindowInScope: window.isTileCandidate && isOnlyTiledWindowInStage
                    )
                } else if let presentationState = member.presentationState {
                    states[member.windowID] = presentationState
                }
            }
        }
        return states
    }

    private static func displayID(for screen: NSScreen) -> DisplayID? {
        guard let raw = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(raw)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) as String?
        else { return nil }
        return DisplayID(rawValue: string)
    }
}

/// Contenu visible du rail d'un ecran, calcule une fois par cycle : sert a la signature (reconstruction
/// seulement si elle change) et au rendu, pour que les deux voient exactement les memes stages.
struct RailDisplayContent {
    let scope: PersistentStageScope
    let presentationStates: [WindowID: WindowPresentationState]
    /// Stages représentées ou nommées, dans l'ordre du scope, membres filtrés.
    let stages: [PersistentStage]
    let emptyStageIDs: [StageID]
    let signature: String

    // Complexite : O(m) - m = membres du scope.
    init(scope: PersistentStageScope, presentationStates: [WindowID: WindowPresentationState], liveWindowIDs: Set<WindowID>, now: Date = Date()) {
        self.scope = scope
        self.presentationStates = presentationStates
        let order = StagePresentationOrder(scope: scope, liveWindowIDs: liveWindowIDs, now: now)
        stages = order.visibleStages
        emptyStageIDs = order.emptyStageIDs
        var parts = ["desktop=\(scope.desktopID.rawValue)", "active=\(scope.activeStageID.rawValue)"]
        for stage in stages {
            let members = stage.members
                .map { "\($0.windowID.rawValue):\($0.bundleID):\(presentationStates[$0.windowID].map(String.init(describing:)) ?? "normal")" }
                .joined(separator: ",")
            parts.append("stage=\(stage.id.rawValue):\(stage.name):\(stage.focusedWindowID.map { String($0.rawValue) } ?? "-"):\(members)")
        }
        parts.append("empty=\(emptyStageIDs.map(\.rawValue).joined(separator: ","))")
        signature = parts.joined(separator: ";")
    }
}

/// Une entrée par écran. La visibilité est recontrôlée même quand aucun fichier ne change :
/// l'expiration des 15 secondes de grâce ne doit jamais rester en cache.
struct RailDisplayContentCache {
    private struct Entry {
        let represented: Set<WindowID>
        let content: RailDisplayContent
    }
    private var entries: [DisplayID: Entry] = [:]
    private(set) var builds = 0

    mutating func content(scope: PersistentStageScope, presentationStates: [WindowID: WindowPresentationState],
                          liveWindowIDs: Set<WindowID>, now: Date) -> RailDisplayContent {
        let represented = Set(scope.stages.flatMap(\.members).filter {
            RailController.isRailRepresentedMember($0, liveWindowIDs: liveWindowIDs, now: now)
        }.map(\.windowID))
        if let entry = entries[scope.displayID], entry.content.scope == scope,
           entry.content.presentationStates == presentationStates, entry.represented == represented {
            return entry.content
        }
        let content = RailDisplayContent(scope: scope, presentationStates: presentationStates,
                                         liveWindowIDs: liveWindowIDs, now: now)
        entries[scope.displayID] = Entry(represented: represented, content: content)
        builds += 1
        return content
    }

    mutating func prune(keeping ids: Set<DisplayID>) { entries = entries.filter { ids.contains($0.key) } }
}

enum RailAction {
    case switchStage(StageID)
    case focusNativeFullscreen(WindowID, String, StageID)
    case summonWindow(WindowID)
    case moveWindow(WindowID, StageID, Int?, Bool, stageInsertion: StageInsertion? = nil)
    case moveWindowToDesktop(WindowID, DesktopID)
    case moveWindowToDisplay(WindowID, DisplayID)
    case placeWindow(DropPreviewCandidate)
    case moveStage(StageID, Int)
    case renameStage(StageID, String)
    case moveStageToDisplay(StageID, DisplayID)
}

struct RailWindowDropTarget {
    var stageID: StageID
    var insertionIndex: Int
    var stageInsertion: StageInsertion? = nil
}

@MainActor
final class RailMenuActionTarget: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func choose(_ sender: NSMenuItem) {
        handler()
    }
}

@MainActor
final class RailStageMoveMenuTarget: NSObject {
    private let handler: (DisplayID) -> Void

    init(handler: @escaping (DisplayID) -> Void) {
        self.handler = handler
    }

    @objc func choose(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        handler(DisplayID(rawValue: raw))
    }
}

struct RailDragPayload {
    var windowID: WindowID
    var sourceStageID: StageID
    var clickAction: RailAction?
    var grabUnit: CGPoint
}

struct RailStageDragPayload {
    var stageID: StageID
    var windowID: WindowID?
}

struct PendingRailDrag {
    var displayID: DisplayID
    var windowID: WindowID
    var sourceStageID: StageID
    var clickAction: RailAction?
    var grabUnit: CGPoint
    var startPoint: CGPoint
    var didDrag: Bool
}

struct PendingStageReorder {
    var displayID: DisplayID
    var stageID: StageID
    var windowID: WindowID?
    var startPoint: CGPoint
    var didDrag: Bool
}
