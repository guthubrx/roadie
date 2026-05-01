import Foundation
import Cocoa
import ApplicationServices
import RoadieCore
import RoadieTiler
import RoadieStagePlugin

/// Daemon roadied — point d'entrée.
/// Bootstrap : check Accessibility → load config → init modules → start observers → run loop.

@MainActor
final class Daemon: AXEventDelegate, GlobalObserverDelegate, CommandHandler {
    let registry = WindowRegistry()
    let displayManager = DisplayManager()
    var config: Config
    let focusManager: FocusManager
    let layoutEngine: LayoutEngine
    let stageManager: StageManager?
    var globalObserver: GlobalObserver?
    var axEventLoop: AXEventLoop?
    var server: Server?
    var mouseRaiser: MouseRaiser?
    var periodicScanner: PeriodicScanner?
    var dragWatcher: DragWatcher?
    /// V2 multi-desktop : nil si `multi_desktop.enabled = false` (compat V1 stricte FR-020).
    var desktopManager: DesktopManager?
    /// Override gaps actif sur le desktop courant (US4 — DesktopRule appliquée au switch).
    /// nil = pas d'override, on utilise `config.tiling.effectiveOuterGaps` global.
    var currentDesktopGaps: OuterGaps?

    /// Drag tracking : on mémorise le wid qui reçoit des notifs move/resize pendant
    /// que l'utilisateur a le bouton enfoncé. Au mouseUp, on adapte uniquement ce wid.
    /// Pas de réaction pendant le drag — comportement déterministe, zéro travail
    /// pendant le mouvement.
    private var dragTrackedWid: WindowID?
    /// Anti-feedback-loop : timestamp du dernier applyLayout. Les notifs reçues dans
    /// les 200 ms après un apply proviennent de notre propre setBounds et sont
    /// ignorées. Sans cette garde, adapt → apply → notif → adapt → boucle.
    private var lastApplyTimestamp: Date = .distantPast

    init(config: Config) throws {
        self.config = config
        self.focusManager = FocusManager(registry: registry)
        // Enregistrement explicite des stratégies de tiling natives.
        // Pour ajouter "papillon", créer ButterflyTiler.swift puis ajouter
        // `ButterflyTiler.register()` ici. Aucun autre changement requis.
        BSPTiler.register()
        MasterStackTiler.register()
        self.layoutEngine = try LayoutEngine(registry: registry, strategy: config.tiling.defaultStrategy)
        if config.stageManager.enabled {
            // Hooks injectés via closure pour que StageManager puisse marquer les
            // leaves invisibles au tiler sans dépendance directe vers RoadieTiler.
            let engine = self.layoutEngine
            let display = self.displayManager
            let outerGaps = config.tiling.effectiveOuterGaps
            let gapsInner = CGFloat(config.tiling.gapsInner)
            let hooks = LayoutHooks(
                setLeafVisible: { wid, vis in engine.setLeafVisible(wid, vis) },
                applyLayout: {
                    engine.apply(rect: display.workArea,
                                 outerGaps: outerGaps, gapsInner: gapsInner)
                }
            )
            self.stageManager = StageManager(registry: registry,
                                             hideStrategy: config.stageManager.hideStrategy,
                                             layoutHooks: hooks)
        } else {
            self.stageManager = nil
        }
    }

    func bootstrap() throws {
        // Permissions Accessibility
        guard AXIsProcessTrusted() else {
            FileHandle.standardError.write("""
            roadied: permission Accessibility manquante.
            Ouvre Réglages Système > Confidentialité et sécurité > Accessibilité,
            ajoute le binaire et coche-le.

            Chemin attendu : /Users/moi/Applications/roadied.app

            """.data(using: .utf8) ?? Data())
            exit(2)
        }

        // Logger
        if let level = LogLevel(rawValue: config.daemon.logLevel) {
            Logger.shared.setMinLevel(level)
        }
        logInfo("roadied starting")

        // V2 multi-desktop : init AVANT load des stages pour pouvoir migrer V1→V2
        // au premier boot et faire pointer le stagesDir vers le bon desktop.
        if config.multiDesktop.enabled, let sm = stageManager {
            try config.validateDesktopRules()
            let provider = SkyLightDesktopProvider()
            let dm = DesktopManager(provider: provider,
                                    backAndForth: config.multiDesktop.backAndForth)
            self.desktopManager = dm
            // Migration V1→V2 (FR-023) : si le user vient de V1, mapper ses stages
            // au desktop courant. No-op les fois suivantes.
            if let currentUUID = provider.currentDesktopUUID() {
                _ = DesktopMigration.runIfNeeded(currentUUID: currentUUID)
            }
            // Hook de transition : applique le desktop_uuid au registry, swap le
            // dossier persistance du StageManager, applique la DesktopRule (V4),
            // ré-applique le layout.
            dm.onTransition = { [weak self] _, to in
                guard let self = self else { return }
                self.registry.applyDesktopUUID(to)
                let stagesDir = "~/.config/roadies/desktops/\(to)/stages"
                sm.reload(stagesDir: stagesDir)
                // V2 US4 : appliquer DesktopRule matching (par index ou label).
                self.applyDesktopRule(for: to)
                self.applyLayout()
            }
            dm.start()
        } else {
            // V1 strict : load global comme avant.
            stageManager?.loadFromDisk()
        }

        // Pre-existing stages from config
        if let sm = stageManager {
            for stageDef in config.stageManager.workspaces {
                let id = StageID(stageDef.id)
                if sm.stages[id] == nil {
                    _ = sm.createStage(id: id, displayName: stageDef.displayName)
                }
            }
        }

        // Observers
        globalObserver = GlobalObserver(delegate: self)
        axEventLoop = AXEventLoop(delegate: self)
        globalObserver?.start()

        // Seed du rect écran AVANT toute insertion : permet à BSPTiler de décider
        // de l'orientation du 1er split via l'aspect ratio (sinon target.lastFrame
        // est nil et on retombe sur parent.opposite — split top/bottom au lieu de
        // left/right pour un écran 16/9).
        let og = config.tiling.effectiveOuterGaps
        let area = displayManager.workArea
        let workArea = CGRect(
            x: area.origin.x + CGFloat(og.left),
            y: area.origin.y + CGFloat(og.top),
            width: area.width - CGFloat(og.left + og.right),
            height: area.height - CGFloat(og.top + og.bottom)
        )
        layoutEngine.setScreenRect(workArea)

        // Snapshot des apps déjà lancées
        for app in globalObserver?.currentApps() ?? [] {
            axEventLoop?.observe(app)
            registerExistingWindows(of: app)
        }

        // Server socket
        server = Server(socketPath: config.daemon.socketPath, handler: self)
        try server?.start()

        // Initial layout
        applyLayout()

        // Initialiser le focus avec la fenêtre frontmost réelle.
        focusManager.refreshFromSystem()

        // Click-to-raise universel : ramène toute fenêtre cliquée au-dessus,
        // indépendamment du tiling. Comble le trou laissé par AeroSpace.
        mouseRaiser = MouseRaiser(registry: registry)
        mouseRaiser?.start()

        // Drag-to-resize : adapte le tree quand l'utilisateur lâche après avoir
        // dragué un bord ou la barre de titre d'une fenêtre tilée.
        dragWatcher = DragWatcher { [weak self] in self?.onDragDrop() }
        dragWatcher?.start()

        // Filet périodique : re-scan les apps observées toutes les secondes pour
        // rattraper les fenêtres Electron qui ne notifient pas leur création.
        periodicScanner = PeriodicScanner(interval: 1.0) { [weak self] in
            self?.periodicScan()
        }
        periodicScanner?.start()

        logInfo("roadied ready")
    }

    private func periodicScan() {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            scanAndRegisterWindows(pid: app.processIdentifier, source: "periodic")
        }
    }

    /// Au démarrage, snapshotter les fenêtres existantes via CGWindowListCopyWindowInfo
    /// et les enregistrer dans le registry comme si elles venaient d'être créées.
    func registerExistingWindows(of app: NSRunningApplication) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let windows = AXReader.windows(of: appElement)
        for window in windows {
            registerWindow(pid: app.processIdentifier, axWindow: window, isInitial: true)
        }
    }

    func registerWindow(pid: pid_t, axWindow: AXUIElement, isInitial: Bool = false) {
        guard let wid = axWindowID(of: axWindow) else {
            logInfo("registerWindow skipped: axWindowID returned nil",
                    ["pid": String(pid), "title": AXReader.title(axWindow)])
            return
        }
        guard registry.get(wid) == nil else {
            logDebug("registerWindow skipped: already known", ["wid": String(wid)])
            return
        }
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        // Filtrer apps exclues
        if config.exclusions.floatingBundles.contains(bundleID) {
            // On l'enregistre quand même mais en floating
            let frame = AXReader.bounds(axWindow) ?? .zero
            let state = WindowState(cgWindowID: wid, pid: pid, bundleID: bundleID,
                                    title: AXReader.title(axWindow), frame: frame,
                                    subrole: AXReader.subrole(axWindow),
                                    isFloating: true)
            registry.register(state, axElement: axWindow)
            return
        }
        let subrole = AXReader.subrole(axWindow)
        let frame = AXReader.bounds(axWindow) ?? .zero
        let isMin = AXReader.isMinimized(axWindow)
        let isFs = AXReader.isFullscreen(axWindow)
        let state = WindowState(cgWindowID: wid, pid: pid, bundleID: bundleID,
                                title: AXReader.title(axWindow), frame: frame,
                                subrole: subrole,
                                isFloating: subrole.isFloatingByDefault,
                                isMinimized: isMin, isFullscreen: isFs)
        registry.register(state, axElement: axWindow)
        axEventLoop?.subscribeDestruction(pid: pid, axWindow: axWindow)
        if state.isTileable {
            let targetID = registry.insertionTarget(for: wid)
            logInfo("insert decision", [
                "new_wid": String(wid),
                "target": targetID.map(String.init) ?? "nil",
                "focused": registry.focusedWindowID.map(String.init) ?? "nil",
                "prev_focused": registry.previousFocusedWindowID.map(String.init) ?? "nil",
                "initial": String(isInitial),
            ])
            layoutEngine.insertWindow(wid, focusedID: targetID)
            // Pendant le bootstrap, le focus système n'est pas encore propagé via
            // refreshFromSystem (appelé en fin de bootstrap). Sans cette ligne, chaque
            // fenêtre initiale serait insérée avec target=nil → tree plat avec N enfants
            // top-level au lieu d'une cascade BSP. On simule donc focus = dernière insérée
            // pour que la suivante splitte celle-ci. À la fin du bootstrap, refreshFromSystem
            // remettra le focus réel sur la frontmost.
            if isInitial {
                registry.setFocus(wid)
            }
        }
        if !isInitial { applyLayout() }
    }

    func applyLayout() {
        let area = displayManager.workArea
        // V2 US4 : si une DesktopRule a posé un override de gaps pour le desktop
        // courant, l'utiliser à la place du global. Sinon comportement V1 inchangé.
        let gaps = currentDesktopGaps ?? config.tiling.effectiveOuterGaps
        layoutEngine.apply(rect: area,
                           outerGaps: gaps,
                           gapsInner: CGFloat(config.tiling.gapsInner))
        // Marquer le timestamp pour que les notifs AX déclenchées par notre setBounds
        // soient ignorées par scheduleAdaptResize pendant 200ms (cf. anti-feedback-loop).
        lastApplyTimestamp = Date()
    }

    /// V2 — reload à chaud de la section [multi_desktop] (FR-019). Active le
    /// DesktopManager si nécessaire, ou le coupe si l'utilisateur a désactivé.
    func reconfigureMultiDesktop(newConfig: Config) {
        let wasEnabled = (desktopManager != nil)
        let nowEnabled = newConfig.multiDesktop.enabled
        guard wasEnabled != nowEnabled else {
            // Mêmes flags : juste mettre à jour back_and_forth si DesktopManager actif.
            desktopManager?.backAndForth = newConfig.multiDesktop.backAndForth
            return
        }
        if nowEnabled, let sm = stageManager {
            // Activation à chaud : on duplique la logique de bootstrap.
            let provider = SkyLightDesktopProvider()
            let dm = DesktopManager(provider: provider,
                                    backAndForth: newConfig.multiDesktop.backAndForth)
            self.desktopManager = dm
            if let currentUUID = provider.currentDesktopUUID() {
                _ = DesktopMigration.runIfNeeded(currentUUID: currentUUID)
            }
            dm.onTransition = { [weak self] _, to in
                guard let self = self else { return }
                self.registry.applyDesktopUUID(to)
                let stagesDir = "~/.config/roadies/desktops/\(to)/stages"
                sm.reload(stagesDir: stagesDir)
                self.applyDesktopRule(for: to)
                self.applyLayout()
            }
            dm.start()
        } else {
            // Désactivation à chaud : on lâche le DesktopManager. Le state actuel
            // (stages dans desktops/<uuid>/) reste sur disque, prêt pour réactivation.
            self.desktopManager = nil
            self.currentDesktopGaps = nil
        }
    }

    /// V2 US4 — applique la `[[desktops]]` rule matching le desktop d'arrivée :
    /// override `default_strategy`, `gaps_*`, `default_stage`. No-op si aucune règle ne matche.
    func applyDesktopRule(for desktopUUID: String) {
        guard let dm = desktopManager else { return }
        let info = dm.listDesktops().first(where: { $0.uuid == desktopUUID })
        let label = dm.label(for: desktopUUID)
        // Match par index OU par label (mutuellement exclusif, validé au boot par validateDesktopRules).
        let rule = config.desktops.first { r in
            if let mi = r.matchIndex, info?.index == mi { return true }
            if let ml = r.matchLabel, label == ml { return true }
            return false
        }
        guard let rule = rule else {
            currentDesktopGaps = nil
            return
        }
        // Override stratégie de tiling.
        if let strat = rule.defaultStrategy {
            try? layoutEngine.setStrategy(strat)
        }
        // Override gaps.
        if let go = rule.gapsOverride() {
            currentDesktopGaps = go.resolve(over: config.tiling.effectiveOuterGaps)
        } else {
            currentDesktopGaps = nil
        }
        // Default stage : appliqué uniquement si aucun stage actif sur ce desktop.
        if let ds = rule.defaultStage,
           let sm = stageManager,
           sm.currentStageID == nil,
           sm.stages[StageID(ds)] != nil {
            sm.switchTo(stageID: StageID(ds))
        }
    }

    /// Auto-GC : purge les fenêtres dont le CGWindowID n'existe plus dans le système.
    /// Vérifie aussi l'état minimized en temps réel (rattrape les notifs ratées).
    /// Appelé avant chaque commande et sur certains events AX.
    func pruneDeadWindows() {
        let liveIDs = liveCGWindowIDs()
        let allWindows = registry.allWindows
        var changed = false
        for state in allWindows {
            // Cas 1 : fenêtre détruite côté système.
            if !liveIDs.contains(state.cgWindowID) {
                logInfo("auto-GC : window pruned (dead)", ["wid": String(state.cgWindowID)])
                layoutEngine.removeWindow(state.cgWindowID)
                stageManager?.handleWindowDestroyed(state.cgWindowID)
                registry.unregister(state.cgWindowID)
                changed = true
                continue
            }
            // Cas 2 : fenêtre minimized en temps réel mais le tree pense qu'elle est visible.
            // Synchroniser via setLeafVisible (préserve la position dans l'arbre).
            guard let element = registry.axElement(for: state.cgWindowID) else { continue }
            let liveMinimized = AXReader.isMinimized(element)
            if liveMinimized && !state.isMinimized {
                logInfo("auto-GC : window minimized externally", ["wid": String(state.cgWindowID)])
                registry.update(state.cgWindowID) { $0.isMinimized = true }
                layoutEngine.setLeafVisible(state.cgWindowID, false)
                changed = true
            } else if !liveMinimized && state.isMinimized {
                logInfo("auto-GC : window deminimized externally", ["wid": String(state.cgWindowID)])
                registry.update(state.cgWindowID) { $0.isMinimized = false }
                layoutEngine.setLeafVisible(state.cgWindowID, true)
                changed = true
            }
        }
        if changed { applyLayout() }
    }

    private func liveCGWindowIDs() -> Set<WindowID> {
        guard let arr = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        var ids = Set<WindowID>()
        for info in arr {
            if let n = info[kCGWindowNumber as String] as? WindowID { ids.insert(n) }
        }
        return ids
    }

    // MARK: - AXEventDelegate

    func axDidCreateWindow(pid: pid_t, axWindow: AXUIElement) {
        logInfo("axDidCreateWindow fired", [
            "pid": String(pid),
            "title": AXReader.title(axWindow),
            "subrole": AXReader.subrole(axWindow).rawValue,
            "wid_at_creation": axWindowID(of: axWindow).map(String.init) ?? "nil",
        ])
        registerWindow(pid: pid, axWindow: axWindow)
        // Race condition macOS : à la création, le CGWindowID n'est pas toujours encore alloué.
        // Retry après un court délai pour rattraper les fenêtres ratées.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self?.registerWindow(pid: pid, axWindow: axWindow)
        }
    }
    func axDidDestroyWindow(pid: pid_t, axWindow: AXUIElement) {
        // 1. Tenter lookup direct (peut retourner nil si la fenêtre est déjà détruite).
        // 2. Fallback : scanner le registry pour matcher l'AXUIElement par CFEqual.
        let wid: WindowID? = axWindowID(of: axWindow)
            ?? registry.allWindows.first(where: { state in
                guard state.pid == pid,
                      let registered = registry.axElement(for: state.cgWindowID) else { return false }
                return CFEqual(registered, axWindow)
            })?.cgWindowID

        guard let wid = wid else {
            // Si on n'a pas pu résoudre, faire un auto-GC qui compare le registry
            // à CGWindowList — coût modéré, garantit la cohérence à terme.
            pruneDeadWindows()
            return
        }
        layoutEngine.removeWindow(wid)
        stageManager?.handleWindowDestroyed(wid)
        registry.unregister(wid)
        applyLayout()
        logInfo("window destroyed", ["wid": String(wid), "pid": String(pid)])
    }
    func axDidMoveWindow(pid: pid_t, wid: WindowID) {
        guard let element = registry.axElement(for: wid),
              let frame = AXReader.bounds(element) else { return }
        registry.updateFrame(wid, frame: frame)
        trackDrag(wid: wid)
    }
    func axDidResizeWindow(pid: pid_t, wid: WindowID) {
        guard let element = registry.axElement(for: wid),
              let frame = AXReader.bounds(element) else { return }
        registry.updateFrame(wid, frame: frame)
        trackDrag(wid: wid)
    }

    /// Mémorise le wid qui reçoit des notifs pendant un drag. Aucune action immédiate :
    /// on attend le `leftMouseUp` (DragWatcher) pour adapter le tree d'un coup.
    private func trackDrag(wid: WindowID) {
        // Si la notif arrive tout de suite après notre propre apply, c'est notre
        // setBounds qui répond, pas un drag user. Pas de tracking.
        if Date().timeIntervalSince(lastApplyTimestamp) < 0.2 { return }
        // Ignorer les fenêtres non-tilées (floating, modales).
        guard let state = registry.get(wid), state.isTileable else { return }
        dragTrackedWid = wid
    }

    /// Appelé par DragWatcher au `leftMouseUp`. Si un wid a été trackée pendant le drag,
    /// on lit sa frame finale et on adapte les weights de l'arbre en conséquence.
    func onDragDrop() {
        guard let wid = dragTrackedWid else { return }
        dragTrackedWid = nil
        guard let element = registry.axElement(for: wid),
              let frame = AXReader.bounds(element) else { return }
        if layoutEngine.adaptToManualResize(wid, newFrame: frame) {
            logDebug("drag adapted", ["wid": String(wid)])
            applyLayout()
        }
    }
    func axDidChangeFocusedWindow(pid: pid_t, axWindow: AXUIElement) {
        // Auto-GC : à chaque event de focus, vérifier que les fenêtres connues
        // existent encore (rattrape les Cmd+W que kAXUIElementDestroyed a ratés).
        pruneDeadWindows()
        // Fallback : si la fenêtre focalisée n'est pas connue, l'enregistrer maintenant.
        if let wid = axWindowID(of: axWindow), registry.get(wid) == nil {
            registerWindow(pid: pid, axWindow: axWindow)
        }
        focusManager.refreshFromSystem()
    }
    /// Scanne les fenêtres d'une app et enregistre celles qui ne le sont pas encore.
    /// Appelé depuis les paths d'activation (NSWorkspace, AX) et le scanner périodique.
    private func scanAndRegisterWindows(pid: pid_t, source: String) {
        let appElement = AXUIElementCreateApplication(pid)
        let windows = AXReader.windows(of: appElement)
        var registered = 0
        for window in windows {
            if let wid = axWindowID(of: window), registry.get(wid) == nil {
                registerWindow(pid: pid, axWindow: window)
                registered += 1
            }
        }
        // Log uniquement quand on a effectivement enregistré quelque chose,
        // sinon le scanner périodique spamme les logs.
        if registered > 0 {
            logInfo("scanWindows", [
                "source": source,
                "pid": String(pid),
                "windows_found": String(windows.count),
                "newly_registered": String(registered),
            ])
        }
    }

    func axDidActivateApplication(pid: pid_t) {
        pruneDeadWindows()
        focusManager.refreshFromSystem()
        scanAndRegisterWindows(pid: pid, source: "AX")
    }

    func axDidMiniaturizeWindow(pid: pid_t, axWindow: AXUIElement) {
        guard let wid = resolveWid(pid: pid, axWindow: axWindow) else { return }
        // Marquer invisible (la leaf reste dans l'arbre à sa place, mais le tiler la skip).
        // Préserve la position d'origine pour la dé-minimisation.
        layoutEngine.setLeafVisible(wid, false)
        registry.update(wid) { $0.isMinimized = true }
        applyLayout()
        logInfo("window miniaturized", ["wid": String(wid), "pid": String(pid)])
    }

    func axDidDeminiaturizeWindow(pid: pid_t, axWindow: AXUIElement) {
        guard let wid = resolveWid(pid: pid, axWindow: axWindow) else { return }
        registry.update(wid) { $0.isMinimized = false }
        // La leaf est encore dans l'arbre à sa position d'origine — il suffit de la rendre visible.
        layoutEngine.setLeafVisible(wid, true)
        applyLayout()
        logInfo("window deminiaturized", ["wid": String(wid), "pid": String(pid)])
    }

    /// Résolution du wid à partir d'un AXUIElement (via getter direct ou CFEqual scan).
    private func resolveWid(pid: pid_t, axWindow: AXUIElement) -> WindowID? {
        if let wid = axWindowID(of: axWindow) { return wid }
        return registry.allWindows.first(where: { state in
            guard state.pid == pid,
                  let registered = registry.axElement(for: state.cgWindowID) else { return false }
            return CFEqual(registered, axWindow)
        })?.cgWindowID
    }

    func didActivateApp(_ app: NSRunningApplication) {
        // Si on n'observait pas encore cette app (cas Terminal.app déjà running au démarrage
        // mais non capturée par currentApps() par exemple), démarrer l'observation maintenant.
        axEventLoop?.observe(app)
        focusManager.refreshFromSystem()
        // Scan : Cursor (Electron) et certaines apps ne déclenchent pas
        // kAXApplicationActivatedNotification, on rattrape via le path NSWorkspace.
        scanAndRegisterWindows(pid: app.processIdentifier, source: "NSWorkspace")
    }

    // MARK: - GlobalObserverDelegate

    func didLaunchApp(_ app: NSRunningApplication) {
        axEventLoop?.observe(app)
        registerExistingWindows(of: app)
    }
    func didTerminateApp(pid: pid_t) {
        axEventLoop?.unobserve(pid: pid)
        // Retirer toutes les fenêtres de cette app du registry et du tree.
        // macOS ne fire pas systématiquement kAXUIElementDestroyedNotification
        // pour chaque fenêtre quand l'app entière se termine.
        let widsToRemove = registry.allWindows.filter { $0.pid == pid }.map { $0.cgWindowID }
        for wid in widsToRemove {
            layoutEngine.removeWindow(wid)
            stageManager?.handleWindowDestroyed(wid)
            registry.unregister(wid)
        }
        if !widsToRemove.isEmpty {
            logInfo("app terminated, windows removed", [
                "pid": String(pid),
                "count": String(widsToRemove.count),
            ])
            applyLayout()
        }
    }

    // MARK: - CommandHandler

    func handle(_ request: Request) async -> Response {
        guard request.version == "roadie/1" else {
            return .error(.invalidArgument, "unknown protocol version")
        }
        // Auto-GC avant chaque commande pour rattraper les destroyed-notifications ratés.
        pruneDeadWindows()
        return await CommandRouter.route(request, daemon: self)
    }
}

// MARK: - Bootstrap

/// Holder global pour garder le daemon vivant tant que le process tourne.
@MainActor
enum AppState {
    static var daemon: Daemon?
}

@MainActor
func bootstrap() {
    let config: Config
    do {
        config = try ConfigLoader.load()
    } catch {
        FileHandle.standardError.write("roadied: config error: \(error)\n".data(using: .utf8) ?? Data())
        exit(1)
    }

    let daemon: Daemon
    do {
        daemon = try Daemon(config: config)
    } catch {
        FileHandle.standardError.write("roadied: init error: \(error)\n".data(using: .utf8) ?? Data())
        exit(1)
    }
    AppState.daemon = daemon   // empêcher la désallocation
    do {
        try daemon.bootstrap()
    } catch {
        FileHandle.standardError.write("roadied: bootstrap error: \(error)\n".data(using: .utf8) ?? Data())
        exit(1)
    }
}

// NSEvent.addGlobalMonitorForEvents (utilisé par MouseRaiser) nécessite un NSApp
// actif pour dispatcher les events globaux. Un RunLoop.main.run() nu ne suffit pas :
// le runloop tourne mais NSApp ne pompe pas la queue système.
// `.accessory` couplé à LSUIElement=true du bundle empêche l'apparition dans le Dock.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

DispatchQueue.main.async { Task { @MainActor in bootstrap() } }

app.run()
