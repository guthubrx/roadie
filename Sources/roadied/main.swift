import Foundation
import Cocoa
import ApplicationServices
import RoadieCore
import RoadieTiler
import RoadieStagePlugin
import RoadieDesktops

// MARK: - StageOpsBridge

/// Adaptateur StageManager (@MainActor) → DesktopStageOps (async actor-safe).
/// Vit dans roadied pour éviter une dépendance RoadieDesktops → RoadieStagePlugin.
/// SPEC-011 refactor.
struct StageOpsBridge: DesktopStageOps {
    let manager: StageManager

    func currentStageID() async -> Int? {
        await MainActor.run { manager.currentStageID.flatMap { Int($0.value) } }
    }

    func deactivateAll() async {
        await MainActor.run { manager.deactivateAll() }
    }

    func activate(_ stageID: Int) async {
        await MainActor.run { manager.activate(stageID: StageID(String(stageID))) }
    }
}

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
    /// SPEC-004 fx-framework : loader de modules opt-in chargés via dlopen.
    /// nil tant que `bootstrap()` n'a pas tourné. Toujours instancié, même en SIP fully on.
    var fxLoader: FXLoader?
    /// SPEC-011 : registry des desktops virtuels. nil si desktops.enabled=false.
    var desktopRegistry: DesktopRegistry?
    /// SPEC-011 : orchestrateur de bascule. nil si desktops.enabled=false.
    var desktopSwitcher: DesktopSwitcher?
    /// SPEC-012 : registry des écrans physiques.
    var displayRegistry: DisplayRegistry?

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
                                             baseConfigDir: "~/.config/roadies",
                                             layoutHooks: hooks)
        } else {
            self.stageManager = nil
        }
    }

    func bootstrap() async throws {
        // Permissions Accessibility
        guard AXIsProcessTrusted() else {
            FileHandle.standardError.write("""
            roadied: permission Accessibility manquante.
            Ouvre Réglages Système > Confidentialité et sécurité > Accessibilité,
            ajoute le binaire et coche-le.

            Chemin attendu : ~/Applications/roadied.app

            """.data(using: .utf8) ?? Data())
            exit(2)
        }

        // Logger
        if let level = LogLevel(rawValue: config.daemon.logLevel) {
            Logger.shared.setMinLevel(level)
        }
        logInfo("roadied starting")

        stageManager?.loadFromDisk()

        // Pre-existing stages from config
        if let sm = stageManager {
            for stageDef in config.stageManager.workspaces {
                let id = StageID(stageDef.id)
                if sm.stages[id] == nil {
                    _ = sm.createStage(id: id, displayName: stageDef.displayName)
                }
            }
            // Garantir le stage 1 par défaut (modèle "toujours au moins 1 stage par desktop").
            sm.ensureDefaultStage()
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

        // Auto-assign des fenêtres orphelines au stage courant (migration utilisateurs existants).
        // Si 5 fenêtres n'ont pas de stageID après loadFromDisk, elles atterrissent toutes
        // dans le stage 1 du desktop courant. Sans effet si stageManager est nil (mode V1 strict).
        if let sm = stageManager, let currentStage = sm.currentStageID {
            for state in registry.allWindows where state.isTileable && state.stageID == nil {
                sm.assign(wid: state.cgWindowID, to: currentStage)
            }
        }

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

        // SPEC-004 : init FX loader (gracieux même si SIP fully on ou aucun module).
        // Le daemon reste 100 % fonctionnel sans modules. Si SIP partial off + dylibs
        // présents : modules chargés, sinon log informatif et continue vanilla.
        let sipState = FXLoader.detectSIP()
        let fxConfigText = (try? String(contentsOfFile: ConfigLoader.defaultConfigPath(), encoding: .utf8)) ?? ""
        let fxCfg = FXConfig.load(fromTOML: fxConfigText)
        let loader = FXLoader()
        let loaded = loader.loadAll(config: fxCfg)
        logInfo("fx_loader: SIP=\(sipState.rawValue), loaded \(loaded.count) module(s)")
        for m in loaded {
            logInfo("fx_loader: loaded \(m.name) v\(m.version)")
        }
        self.fxLoader = loader

        // SPEC-004 : replay des fenêtres existantes vers le bus FX. Au bootstrap,
        // `registerWindow(isInitial:true)` tournait AVANT que `fxLoader` soit assigné,
        // donc les modules opt-in (Borders, etc.) ne recevaient aucun `windowCreated`
        // pour les fenêtres déjà ouvertes. On les rejoue ici, une fois.
        for state in registry.allWindows where state.isTileable {
            loader.bus.publish(FXEvent(kind: .windowCreated,
                                       wid: CGWindowID(state.cgWindowID),
                                       bundleID: state.bundleID,
                                       frame: state.frame,
                                       isFloating: state.isFloating))
        }
        if let focusedWID = registry.focusedWindowID {
            loader.bus.publish(FXEvent(kind: .windowFocused,
                                       wid: CGWindowID(focusedWID)))
        }
        // Pont focus : tout changement de `registry.focusedWindowID` (depuis AX
        // notifications, MouseRaiser, click-to-raise, manual) publie un
        // windowFocused sur le bus FX. Évite que le module Borders rate des focus
        // changes qui n'ont pas transité par axDidChangeFocusedWindow (apps Electron).
        registry.onFocusChanged = { [weak loader] wid in
            guard let wid = wid else { return }
            loader?.bus.publish(FXEvent(kind: .windowFocused, wid: CGWindowID(wid)))
        }

        // SPEC-011 : init desktops virtuels si activé
        if config.desktops.enabled {
            let configDir = URL(fileURLWithPath:
                (NSString(string: "~/.config/roadies").expandingTildeInPath as String))

            // T054 : Migration au boot (avant DesktopRegistry.load)
            let desktopsDir = configDir.appendingPathComponent("desktops")
            let stagesDir = configDir.appendingPathComponent("stages")
            do {
                try archiveSpec003LegacyDirs(desktopsDir: desktopsDir)
                try await migrateV1ToV2(stagesDir: stagesDir, desktopsDir: desktopsDir)
            } catch {
                logWarn("migration error (non-fatal)", ["error": "\(error)"])
            }

            let dRegistry = DesktopRegistry(configDir: configDir, count: config.desktops.count)
            await dRegistry.load()
            let dBus = DesktopEventBus()
            let dCfg = DesktopSwitcherConfig(
                count: config.desktops.count,
                backAndForth: config.desktops.backAndForth
            )

            // SPEC-011 unification sources : substituer la persistence V1 (fichiers) par
            // DesktopBackedStagePersistence (DesktopRegistry). À partir de ce point, toutes
            // les lectures/écritures de stages passent par state.toml via DesktopRegistry.
            // Le currentID du registry est la source de vérité pour l'ID de desktop courant.
            let sm = self.stageManager
            if let mgr = sm {
                let currentDeskID = await dRegistry.currentID
                let dbPersistence = DesktopBackedStagePersistence(
                    registry: dRegistry,
                    desktopID: currentDeskID
                )
                mgr.setPersistence(dbPersistence)
                logInfo("stage_persistence: switched to DesktopRegistry-backed",
                        ["desktop": String(currentDeskID)])
            }
            let stageHook: (@Sendable (Int) async -> Void)? = sm.map { mgr in
                { @Sendable (newDesktopID: Int) async in
                    await MainActor.run {
                        mgr.reload(forDesktop: newDesktopID)
                        // Garantir stage 1 + stage actif sur le desktop d'arrivée.
                        // Si le desktop n'a jamais eu de stages persistés, crée stage 1 et l'active.
                        mgr.ensureDefaultStage()
                    }
                }
            }
            // T048 : câbler onStageChanged → DesktopEventBus (émission stage_changed)
            let busRef = dBus
            sm?.onStageChanged = { @MainActor deskID, fromStage, toStage in
                let event = DesktopChangeEvent(
                    event: "stage_changed",
                    from: fromStage,
                    to: toStage,
                    desktopID: deskID
                )
                Task { await busRef.publish(event) }
            }
            // SPEC-011 refactor : bridge StageManager (MainActor) → DesktopStageOps (async).
            // Adaptateur qui traduit les appels async actor-isolated en @MainActor.
            let dStageOps: (any DesktopStageOps)? = sm.map { mgr in
                StageOpsBridge(manager: mgr)
            }
            let dSwitcher = DesktopSwitcher(
                registry: dRegistry,
                stageOps: dStageOps,
                bus: dBus,
                config: dCfg,
                onDesktopChanged: stageHook
            )
            self.desktopRegistry = dRegistry
            self.desktopSwitcher = dSwitcher

            // SPEC-011 T-boot : populer le DesktopRegistry avec les fenêtres déjà
            // enregistrées dans WindowRegistry.
            // Les fenêtres sont toutes on-screen au boot (HideStrategy via StageManager
            // garantit qu'aucune fenêtre n'est laissée offscreen — plus besoin de recovery).
            let currentDeskID = await dRegistry.currentID
            for state in registry.allWindows where state.isTileable {
                let entry = WindowEntry(
                    cgwid: UInt32(state.cgWindowID),
                    bundleID: state.bundleID,
                    title: state.title,
                    expectedFrame: state.frame,
                    stageID: 1
                )
                do {
                    try await dRegistry.assignWindow(entry, to: currentDeskID)
                } catch {
                    logWarn("boot: desktop assignWindow failed",
                            ["wid": String(state.cgWindowID), "error": "\(error)"])
                }
            }
            logInfo("boot: windows seeded into desktop",
                    ["desktop": String(currentDeskID),
                     "count": String(await dRegistry.windows(of: currentDeskID).count)])

            // T049 : bridge DesktopEventBus → EventBus.shared (RoadieCore).
            // Le Server utilise EventBus.shared pour les connexions events.subscribe.
            // Ce bridge garantit que desktop_changed + stage_changed sont servis
            // aux subscribers, sans modifier Server.swift.
            Task { @MainActor in
                let bridge = await dBus.subscribe()
                for await evt in bridge {
                    // Relayer vers RoadieCore.EventBus (JSON-line conforme au contrat)
                    let payload: [String: String]
                    if evt.event == "stage_changed" {
                        payload = [
                            "desktop_id": evt.desktopID,
                            "from": evt.from,
                            "to": evt.to,
                            "ts": String(evt.ts),
                        ]
                    } else {
                        var p: [String: String] = ["from": evt.from, "to": evt.to,
                                                    "ts": String(evt.ts)]
                        if !evt.fromLabel.isEmpty { p["from_label"] = evt.fromLabel }
                        if !evt.toLabel.isEmpty { p["to_label"] = evt.toLabel }
                        payload = p
                    }
                    EventBus.shared.publish(DesktopEvent(name: evt.event, payload: payload))
                }
            }

            // T031 : aligner le StageManager sur le desktop courant restauré
            let restoredID = await dRegistry.currentID
            sm?.reload(forDesktop: restoredID)
            // Le reload swap le stagesDir et reset currentStageID. Re-garantir
            // le stage 1 + stage actif (sinon ensureDefaultStage du boot est
            // perdu — currentStageID redevient nil et la bascule de desktop
            // ne fait plus rien).
            sm?.ensureDefaultStage()

            logInfo("desktops initialized",
                    ["count": String(config.desktops.count),
                     "current": String(await dRegistry.currentID)])
        } else {
            logInfo("desktops disabled (desktops.enabled=false)")
        }

        // SPEC-012 T009/T018 : init DisplayRegistry + observer didChangeScreenParameters.
        // L'observer est dans bootstrap() car les notifications AppKit ne peuvent pas
        // être observées proprement depuis un actor Swift.
        let dspRegistry = DisplayRegistry()
        await dspRegistry.refresh()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak dspRegistry] _ in
            guard let self, let dspRegistry else { return }
            Task {
                await dspRegistry.refresh()
                // Re-distribuer le layout sur tous les écrans après changement de config.
                await self.layoutEngine.applyAll(displayRegistry: dspRegistry)
            }
        }
        self.displayRegistry = dspRegistry
        logInfo("display_registry initialized", ["count": String(await dspRegistry.count)])

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
        // SPEC-011 : pont WindowRegistry → DesktopRegistry.
        // Enregistrer la fenêtre dans le desktop courant si le subsystème est actif.
        // Les fenêtres offscreen (origin.x < -1000) au moment du boot (déjà déplacées
        // par un run précédent) ne reçoivent pas d'expectedFrame valide — on les ignore
        // et on attend une notification AX avec une vraie position.
        if let dReg = desktopRegistry, frame.origin.x > -1000 {
            let entry = WindowEntry(
                cgwid: UInt32(wid),
                bundleID: bundleID,
                title: AXReader.title(axWindow),
                expectedFrame: frame,
                stageID: 1
            )
            Task { @MainActor in
                let currentDeskID = await dReg.currentID
                do {
                    try await dReg.assignWindow(entry, to: currentDeskID)
                    logInfo("window registered in desktop",
                            ["wid": String(wid), "desktop": String(currentDeskID)])
                } catch {
                    logWarn("desktop assignWindow failed",
                            ["wid": String(wid), "error": "\(error)"])
                }
            }
        }
        // Auto-assign la fenêtre au stage actif. Sans effet si stageManager nil ou
        // si la fenêtre n'est pas tileable (floating, modale).
        if state.isTileable, let sm = stageManager, let stageID = sm.currentStageID {
            sm.assign(wid: state.cgWindowID, to: stageID)
        }

        if !isInitial { applyLayout() }

        // SPEC-004 : pont vers le bus FX. Les modules opt-in (RoadieBorders, etc.)
        // s'abonnent à `windowCreated` pour spawner leurs overlays.
        // Filtre : ne publie que pour les fenêtres tileables réelles. Les
        // sous-éléments AX (toolbars, search fields, palettes flottantes
        // d'iTerm/Cursor/etc.) sont exclus pour ne pas créer de bordures
        // fantômes sur les UI internes des apps.
        if state.isTileable {
            fxLoader?.bus.publish(FXEvent(kind: .windowCreated,
                                          wid: CGWindowID(wid),
                                          bundleID: bundleID,
                                          frame: frame,
                                          isFloating: state.isFloating))
        }
    }

    func applyLayout() {
        lastApplyTimestamp = Date()
        if let dspRegistry = displayRegistry {
            // T018 : multi-display → distribuer sur tous les écrans.
            // applyAll est async, Task détaché pour préserver la surface sync.
            Task { await self.layoutEngine.applyAll(displayRegistry: dspRegistry) }
        } else {
            // Fallback mono-écran (avant que le displayRegistry soit initialisé).
            let area = displayManager.workArea
            let gaps = config.tiling.effectiveOuterGaps
            layoutEngine.apply(rect: area,
                               outerGaps: gaps,
                               gapsInner: CGFloat(config.tiling.gapsInner))
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
                removeWindowFromDesktopRegistry(wid: state.cgWindowID)
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

    /// SPEC-011 : retire une fenêtre du DesktopRegistry à sa destruction.
    /// Fire-and-forget : les erreurs de persistance sont loguées dans removeWindow.
    private func removeWindowFromDesktopRegistry(wid: WindowID) {
        guard let dReg = desktopRegistry else { return }
        Task { await dReg.removeWindow(cgwid: UInt32(wid)) }
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
        removeWindowFromDesktopRegistry(wid: wid)
        applyLayout()
        logInfo("window destroyed", ["wid": String(wid), "pid": String(pid)])
        fxLoader?.bus.publish(FXEvent(kind: .windowDestroyed, wid: CGWindowID(wid)))
    }
    func axDidMoveWindow(pid: pid_t, wid: WindowID) {
        guard let element = registry.axElement(for: wid),
              let frame = AXReader.bounds(element) else { return }
        registry.updateFrame(wid, frame: frame)
        trackDrag(wid: wid)
        propagateExpectedFrame(wid: wid, frame: frame)
        fxLoader?.bus.publish(FXEvent(kind: .windowMoved,
                                      wid: CGWindowID(wid), frame: frame))
    }
    func axDidResizeWindow(pid: pid_t, wid: WindowID) {
        guard let element = registry.axElement(for: wid),
              let frame = AXReader.bounds(element) else { return }
        registry.updateFrame(wid, frame: frame)
        trackDrag(wid: wid)
        propagateExpectedFrame(wid: wid, frame: frame)
        fxLoader?.bus.publish(FXEvent(kind: .windowResized,
                                      wid: CGWindowID(wid), frame: frame))
    }

    /// SPEC-011 FR-005 : propage la nouvelle frame au DesktopRegistry pour que la
    /// prochaine bascule de desktop restaure la position/taille courante.
    /// Guards : (a) feature active, (b) hors fenêtre anti-feedback applyLayout 200 ms,
    /// (c) frame on-screen (exclut positions offscreen de la bascule, typiquement
    /// >= 3000 ou <= -1000, cf. DesktopSwitcher).
    private func propagateExpectedFrame(wid: WindowID, frame: CGRect) {
        guard let dReg = desktopRegistry,
              Date().timeIntervalSince(lastApplyTimestamp) >= 0.2 else { return }
        // Filtre on-screen rigoureux : la frame doit intersecter le visibleFrame
        // d'au moins un écran connecté (en coords AX top-left). Sinon c'est une
        // position offscreen (bascule en cours, ou fenêtre laissée hors-écran
        // par un autre process) → on n'écrase pas l'expectedFrame mémorisée.
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let mainHeight = screens[0].frame.height
        let onScreen = screens.contains { ns in
            // visibleFrame en coords Quartz (origin bottom-left).
            // Conversion AX top-left : axY = mainHeight - (ns.maxY)
            let vis = ns.visibleFrame
            let axRect = CGRect(
                x: vis.origin.x,
                y: mainHeight - (vis.origin.y + vis.height),
                width: vis.width,
                height: vis.height)
            return axRect.intersects(frame)
        }
        guard onScreen else { return }
        let cgwid = UInt32(wid)
        Task {
            let resolved = await dReg.desktopID(for: cgwid)
            let fallback = await dReg.currentID
            let did = resolved ?? fallback
            do {
                try await dReg.updateExpectedFrame(cgwid: cgwid, desktopID: did, frame: frame)
            } catch {
                logWarn("propagateExpectedFrame failed",
                        ["wid": String(wid), "desktop": String(did), "error": "\(error)"])
            }
        }
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
        // windowFocused FX publié automatiquement par registry.onFocusChanged
        // (cf. branchement dans bootstrap()).
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
            removeWindowFromDesktopRegistry(wid: wid)
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
    Task { @MainActor in
        do {
            try await daemon.bootstrap()
        } catch {
            FileHandle.standardError.write("roadied: bootstrap error: \(error)\n".data(using: .utf8) ?? Data())
            exit(1)
        }
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
