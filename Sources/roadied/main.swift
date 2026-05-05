import Foundation
import Cocoa
import ApplicationServices
import CoreGraphics
import RoadieCore
import RoadieTiler
import RoadieStagePlugin
import RoadieDesktops
import RoadieRail

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
/// SPEC-025 — wrapper class pour capturer une référence Daemon de manière
/// différée (utilisé par le hook applyLayout qui doit appeler la version full
/// multi-display, mais self n'est pas init au moment de la création du hook).
final class DaemonHolder: @unchecked Sendable {
    weak var daemon: Daemon?
}

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
    /// SPEC-015 : drag/resize avec modifier + clic souris.
    var mouseDragHandler: MouseDragHandler?
    /// SPEC-026 US5 — focus_follows_mouse watcher.
    var focusFollowsMouseWatcher: FocusFollowsMouseWatcher?
    /// SPEC-026 US6 — signal hooks dispatcher.
    var signalDispatcher: SignalDispatcher?
    /// SPEC-026 US3 — scratchpad manager.
    var scratchpadManager: ScratchpadManager?
    /// SPEC-026 US4 — index des bundleID sticky pour matching rapide.
    var stickyBundleIDs: Set<String> = []
    /// SPEC-026 fix Firefox slide — référence forte sur l'override hide. Sinon
    /// la weak ref dans StageManager.hideOverride collapse → fallback HideStrategy.corner.
    var opacityStageHider: OpacityStageHider?
    var periodicScanner: PeriodicScanner?
    var dragWatcher: DragWatcher?
    /// SPEC-004 fx-framework : loader de modules opt-in chargés via dlopen.
    /// nil tant que `bootstrap()` n'a pas tourné. Toujours instancié, même en SIP fully on.
    var fxLoader: FXLoader?
    /// SPEC-025 — flag one-shot pour auto-cure cross-stage drift au boot.
    /// Set à true après le 1er applyAll qui détecte+fixe un drift. Évite les
    /// reassigns en cascade pendant les stage switches.
    var didInitialDriftFix: Bool = false
    /// SPEC-025 — wrapper class pour capturer self.applyLayout dans la closure
    /// du hook LayoutHooks.applyLayout (self pas init au moment de la création
    /// du hook). Set à `self` à la fin de l'init pour permettre au hook
    /// d'appeler la version multi-display complète.
    private var daemonHolder: DaemonHolder?
    /// SPEC-011 : registry des desktops virtuels. nil si desktops.enabled=false.
    var desktopRegistry: DesktopRegistry?
    /// SPEC-011 : orchestrateur de bascule. nil si desktops.enabled=false.
    var desktopSwitcher: DesktopSwitcher?
    /// SPEC-012 : registry des écrans physiques.
    var displayRegistry: DisplayRegistry?
    /// SPEC-014 : cache LRU des vignettes fenêtres (capacité 50).
    var thumbnailCache: ThumbnailCache?
    /// SPEC-014 : service de capture ScreenCaptureKit (0.5 Hz par fenêtre observée).
    var sckCaptureService: SCKCaptureService?
    /// SPEC-014 : watcher click wallpaper → event wallpaper_click.
    var wallpaperClickWatcher: WallpaperClickWatcher?
    /// SPEC-021 T048 : reconciler périodique desktop macOS ↔ scope persisté.
    var windowDesktopReconciler: WindowDesktopReconciler?
    /// SPEC-024 — rail UI in-process. Stocké en propriété forte (sinon ARC le
    /// déalloue immédiatement après bootstrap, comme `AppState.daemon`).
    var railController: RailController?

    /// Drag tracking : on mémorise le wid qui reçoit des notifs move/resize pendant
    /// que l'utilisateur a le bouton enfoncé. Au mouseUp, on adapte uniquement ce wid.
    /// Pas de réaction pendant le drag — comportement déterministe, zéro travail
    /// pendant le mouvement.
    private var dragTrackedWid: WindowID?
    /// SPEC-018 : true si la migration V1→V2 a échoué au boot (disque plein, permission refusée).
    /// Exposé dans `daemon.status` pour debug. Ne bloque pas le boot.
    var migrationPending: Bool = false
    /// Anti-feedback-loop : timestamp du dernier applyLayout. Les notifs reçues dans
    /// les 200 ms après un apply proviennent de notre propre setBounds et sont
    /// ignorées. Sans cette garde, adapt → apply → notif → adapt → boucle.
    private var lastApplyTimestamp: Date = .distantPast
    /// Coalescing applyLayout : true si une Task applyAll est déjà en vol. Évite
    /// d'empiler 5 applyAll @MainActor consécutifs (chacun ~6 setBounds sync) qui
    /// saturent le main actor et bloquent les commandes CLI.
    private var applyLayoutInFlight = false
    /// Re-trigger demandé pendant un applyLayout en cours.
    private var applyLayoutNeedsRetrigger = false
    /// SPEC-013 : timestamp du dernier follow AltTab pour anti-feedback (évite
    /// les bascules en cascade quand un focus event suit une bascule).
    private var lastAltTabFollowTimestamp: Date = .distantPast
    /// Anti-feedback pour `followFocusToStageAndDesktop`. Sans ce guard, un
    /// switchTo programmatique rend la wid cible visible et focused, ce qui
    /// re-déclenche onFocusChanged → re-follow → oscillation entre 2 stages
    /// chacun ayant une wid focused (boucle observée 5×/300ms).
    private var lastFocusFollowTimestamp: Date = .distantPast

    init(config: Config) throws {
        self.config = config
        self.focusManager = FocusManager(registry: registry)
        // Enregistrement explicite des stratégies de tiling natives.
        // Pour ajouter "papillon", créer ButterflyTiler.swift puis ajouter
        // `ButterflyTiler.register()` ici. Aucun autre changement requis.
        BSPTiler.register()
        MasterStackTiler.register()
        // SPEC-025 amend — wire la politique de split BSP depuis la config TOML.
        if let policy = BSPTiler.SplitPolicy(rawValue: config.tiling.splitPolicy) {
            BSPTiler.splitPolicy = policy
        } else {
            logWarn("bsp_split_policy_invalid", [
                "value": config.tiling.splitPolicy,
                "fallback": "largest_dim",
                "valid": "largest_dim, dwindle",
            ])
            BSPTiler.splitPolicy = .largestDim
        }
        logInfo("bsp_split_policy", ["policy": BSPTiler.splitPolicy.rawValue])
        self.layoutEngine = try LayoutEngine(registry: registry, strategy: config.tiling.defaultStrategy)
        // SPEC-026 US2 — propage smart_gaps_solo au moteur.
        self.layoutEngine.smartGapsSolo = config.tiling.smartGapsSolo
        if config.stageManager.enabled {
            // Hooks injectés via closure pour que StageManager puisse marquer les
            // leaves invisibles au tiler sans dépendance directe vers RoadieTiler.
            let engine = self.layoutEngine
            let display = self.displayManager
            let registryRef = self.registry  // capture pour usage dans closures (self pas init)
            let outerGaps = config.tiling.effectiveOuterGaps
            let gapsInner = CGFloat(config.tiling.gapsInner)
            // SPEC-025 root-cause fix — le hook applyLayout doit appeler la
            // version FULL multi-display (engine.applyAll via daemon.applyLayout).
            // L'ancien code utilisait `engine.apply(rect: display.workArea)` qui
            // ne fait que mono-display primary → au stage switch les wids des
            // autres displays/stages n'étaient PAS show/hide → Firefox stage 2
            // restait offscreen quand on switch sur stage 2. Le wrapper class
            // permet de capturer self post-init (sans cycle de référence init).
            let daemonHolder = DaemonHolder()
            self.daemonHolder = daemonHolder
            let hooks = LayoutHooks(
                setLeafVisible: { wid, vis in engine.setLeafVisible(wid, vis) },
                applyLayout: {
                    if let d = daemonHolder.daemon {
                        d.applyLayout()
                    } else {
                        // Fallback init-time : avant que daemonHolder.daemon
                        // ne soit set en fin de bootstrap (rare en pratique).
                        engine.apply(rect: display.workArea,
                                     outerGaps: outerGaps, gapsInner: gapsInner)
                    }
                },
                reassignToStage: { wid, stageID in engine.reassignWindow(wid, toStage: stageID) },
                // SPEC-022 — closure scope-aware. Si displayUUID fourni, scope la
                // mutation à ce display uniquement (utilise activeStageByDisplay).
                // Sinon, comportement legacy (apply à tous, pour mode global).
                setActiveStage: { stageID, displayUUID in
                    if let uuid = displayUUID, !uuid.isEmpty,
                       let cfUUID = CFUUIDCreateFromString(nil, uuid as CFString) {
                        let did = CGDisplayGetDisplayIDFromUUID(cfUUID)
                        if did != 0 {
                            engine.setActiveStage(stageID, displayID: did)
                            return
                        }
                    }
                    engine.setActiveStage(stageID)
                }
            )
            self.stageManager = StageManager(registry: registry,
                                             hideStrategy: config.stageManager.hideStrategy,
                                             baseConfigDir: "~/.config/roadies",
                                             layoutHooks: hooks)
        } else {
            self.stageManager = nil
        }
        // SPEC-026 US4 — câblage sticky : closure qui regarde les rules pour décider
        // si une wid doit rester visible cross-stage. Capture sticky rules au boot ;
        // le reload met à jour l'index local.
        let registryRefForSticky = self.registry
        var stickyBundleIDs = Set(config.stickyRules.map { $0.matchBundleID })
        self.stickyBundleIDs = stickyBundleIDs
        self.stageManager?.shouldKeepWidStickyAcrossStages = { [weak self] wid in
            guard let self = self else { return false }
            guard let bundleID = registryRefForSticky.get(wid)?.bundleID else { return false }
            return self.stickyBundleIDs.contains(bundleID)
        }
        _ = stickyBundleIDs   // silence unused if reload path branches differently
        // SPEC-026 fix Firefox slide — installer OpacityStageHider si activé
        // ET si l'osax est disponible (sinon les setAlpha partent dans le vide
        // et les fenêtres ne sont ni cachées ni montrées — pire que le slide).
        if config.fxOpacityStageHideEnabled {
            let osaxSocket = "/var/tmp/roadied-osax.sock"
            if FileManager.default.fileExists(atPath: osaxSocket) {
                let hider = OpacityStageHider(bridge: DaemonOSAXBridge.shared)
                self.opacityStageHider = hider
                self.stageManager?.hideOverride = hider
                logInfo("opacity_stage_hider_installed")
            } else {
                logWarn("opacity_stage_hider_skipped", [
                    "reason": "osax_not_loaded",
                    "expected_socket": osaxSocket,
                    "remediation": "scripts/install-fx.sh + osascript reload Dock",
                ])
            }
        }
        self.thumbnailCache = ThumbnailCache(capacity: 50)
    }

    func bootstrap() async throws {
        // Permissions Accessibility — wait-loop : éviter le respawn-prompt-spam
        // launchd qui re-déclenche TCC en cascade quand l'utilisateur clique
        // "Allow" pendant que le daemon exit en boucle. Au lieu d'exit(2)
        // immédiat : ouvrir les Réglages, notifier, puis poll AXIsProcessTrusted()
        // toutes les 2s pendant 60s. Pendant ce temps, l'utilisateur a le temps
        // de cocher la case sans déclencher 30 prompts d'affilée.
        if !AXIsProcessTrusted() {
            FileHandle.standardError.write("""
            roadied: permission Accessibility manquante. Ouverture des Réglages…
            En attente que la case soit cochée (timeout 60s).

            """.data(using: .utf8) ?? Data())
            // Notification + ouverture Réglages (anti-spam 60s pour les
            // notifications elles-mêmes — pas le wait-loop).
            let marker = "/tmp/roadied-tcc-notif.last"
            let now = Int(Date().timeIntervalSince1970)
            let last = (try? String(contentsOfFile: marker)).flatMap(Int.init) ?? 0
            if now - last >= 60 {
                let prefURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                let tn = "/opt/homebrew/bin/terminal-notifier"
                let p = Process()
                if FileManager.default.fileExists(atPath: tn) {
                    p.launchPath = tn
                    p.arguments = [
                        "-title", "🔴 roadie : permission manquante",
                        "-message", "Re-cocher Accessibilité dans Réglages Système (clic).",
                        "-open", prefURL,
                        "-sound", "Funk",
                    ]
                } else {
                    p.launchPath = "/usr/bin/open"
                    p.arguments = [prefURL]
                }
                try? p.run()
                p.waitUntilExit()
                try? "\(now)".write(toFile: marker, atomically: true, encoding: .utf8)
            }
            // Poll 30 × 2s = 60s max. Sort dès que la perm passe (TCC propage
            // instantanément à AXIsProcessTrusted). Combiné avec
            // ThrottleInterval=30 dans le plist launchd, ça empêche
            // définitivement les bursts de prompts.
            for i in 0..<30 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if AXIsProcessTrusted() {
                    FileHandle.standardError.write("roadied: permission Accessibility OK après \(i * 2)s d'attente.\n".data(using: .utf8) ?? Data())
                    break
                }
            }
        }
        guard AXIsProcessTrusted() else {
            FileHandle.standardError.write("""
            roadied: permission Accessibility toujours manquante après 60s.
            launchd va respawn dans 30s (ThrottleInterval). Coche la case
            avant et ça repartira automatiquement.

            """.data(using: .utf8) ?? Data())
            exit(2)
        }

        // Logger
        if let level = LogLevel(rawValue: config.daemon.logLevel) {
            Logger.shared.setMinLevel(level)
        }
        logInfo("roadied starting")

        // SPEC-024 T015 — état Screen Recording (log-only). CGRequestScreenCaptureAccess()
        // crash le daemon dans le contexte launchd ; on se contente de Preflight (lecture).
        // Si denied : le rail aura des thumbnails dégradées (icônes app) — non bloquant.
        let scGranted = CGPreflightScreenCaptureAccess()
        if scGranted {
            logInfo("screen_capture_state", ["granted": "true"])
        } else {
            logWarn("screen_capture_state", ["granted": "false",
                "hint": "Réglages Système → Confidentialité → Enregistrement d'écran → cocher roadied.app"])
            FileHandle.standardError.write(
                "roadied: Screen Recording NON accordé — thumbnails de fenêtres seront dégradées en icônes.\n"
                    .data(using: .utf8) ?? Data())
        }

        stageManager?.loadFromDisk()
        // SPEC-021 T021 : brancher le service locator pour que WindowState.stageID
        // (computed) puisse déléguer à stageManager sans dépendance circulaire.
        StageManagerLocator.shared = stageManager

        // SPEC-025 FR-002 — auto-fix au boot. Détecte et corrige les drifts
        // widToScope/memberWindows + purge wids zombies (= fenêtres fermées
        // entre la dernière save et ce boot). Évite à l'utilisateur de devoir
        // mémoriser et lancer `roadie daemon audit --fix` à la main.
        let widsOffscreenAtRestore = StageManager.lastValidationInvalidatedCount
        var widsZombiesPurged = 0
        var widToScopeDriftsFixed = 0
        if let sm = stageManager {
            let violationsBefore = sm.auditOwnership()
            widToScopeDriftsFixed = violationsBefore.count
            // Capturer le compteur avant purge pour mesurer les zombies effectivement retirés.
            let memberCountBefore = sm.totalMemberCount()
            sm.purgeOrphanWindows()
            sm.rebuildWidToScopeIndex()
            let memberCountAfter = sm.totalMemberCount()
            widsZombiesPurged = max(0, memberCountBefore - memberCountAfter)
            if widToScopeDriftsFixed > 0 || widsZombiesPurged > 0 {
                logInfo("boot_audit_autofixed", [
                    "violations_before": String(widToScopeDriftsFixed),
                    "zombies_purged": String(widsZombiesPurged),
                ])
            } else {
                logInfo("boot_audit_clean")
            }
        }

        // SPEC-025 FR-003 — émettre BootStateHealth après auto-fix pour traçabilité.
        let totalWids = stageManager?.totalMemberCount() ?? 0
        let bootHealth = BootStateHealth(
            totalWids: totalWids,
            widsOffscreenAtRestore: widsOffscreenAtRestore,
            widsZombiesPurged: widsZombiesPurged,
            widToScopeDriftsFixed: widToScopeDriftsFixed
        )
        logInfo("boot_state_health", bootHealth.toLogPayload())
        // Notification utilisateur si état dégradé (best-effort terminal-notifier).
        if bootHealth.verdict != .healthy {
            let tn = "/opt/homebrew/bin/terminal-notifier"
            if FileManager.default.fileExists(atPath: tn) {
                let p = Process()
                p.launchPath = tn
                p.arguments = [
                    "-title", "🟡 roadie",
                    "-message", "State \(bootHealth.verdict.rawValue) — try `roadie heal`",
                    "-sound", "Tink",
                ]
                try? p.run()
            }
        }

        // Pre-existing stages from config (mode global uniquement — en perDisplay
        // les stages sont matérialisées par scope plus loin via ensureDefaultStage).
        if let sm = stageManager, sm.stageMode == .global {
            for stageDef in config.stageManager.workspaces {
                let id = StageID(stageDef.id)
                if sm.stages[id] == nil {
                    _ = sm.createStage(id: id, displayName: stageDef.displayName)
                }
            }
        }
        if let sm = stageManager {
            // Garantir le stage 1 par défaut (modèle "toujours au moins 1 stage par desktop").
            // SPEC-018 : en mode per_display, créer aussi dans stagesV2 au scope primary.
            // PAS `CGMainDisplayID()` qui est dynamique (suit le focus) — au boot le focus
            // peut être sur n'importe quel display → pollution du « mauvais » écran avec un
            // stage par défaut. On prend l'écran à origin (0,0) = primary stable au sens
            // macOS, qui correspond au choix utilisateur dans Réglages > Écrans.
            let defaultScope: StageScope?
            if config.desktops.mode == .perDisplay {
                let primaryScreen = NSScreen.screens.first(where: { $0.frame.origin == .zero })
                    ?? NSScreen.main
                let primaryDisplayID: CGDirectDisplayID
                if let s = primaryScreen,
                   let did = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                       as? CGDirectDisplayID {
                    primaryDisplayID = did
                } else {
                    primaryDisplayID = CGMainDisplayID()
                }
                let primaryUUID = resolveDisplayUUID(primaryDisplayID)
                defaultScope = StageScope(displayUUID: primaryUUID, desktopID: 1, stageID: StageID("1"))
            } else {
                defaultScope = nil
            }
            sm.ensureDefaultStage(scope: defaultScope)
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

        // CAUSE RACINE Grayjay (timing) : précharger stagesV2 AVANT registerExistingWindows.
        // Sans ça, registerWindow voit stagesV2 vide → ne propage pas `state.stageID` →
        // insertWindow place la wid dans le tree de la stage active (1) au lieu de son
        // tree de persistance → applyAll la layoute visible alors qu'elle devrait être
        // hidden. La persistence V2 (NestedStagePersistence) n'a aucune dépendance au
        // DesktopRegistry, on peut donc la setup tôt.
        if config.desktops.enabled, config.desktops.mode == .perDisplay,
           let sm = stageManager {
            let stagesDir = (NSString(string: "~/.config/roadies/stages")
                .expandingTildeInPath as String)
            // SPEC-025 BUG-002 amendement — active.toml global est un artefact legacy
            // (avant SPEC-022 et le passage à activeStageByDesktop per-(display,desktop))
            // strictement ignoré en mode per_display. Auto-cleanup : supprimer
            // silencieusement pour ne plus warner à chaque boot.
            let deprecatedActivePath = "\(stagesDir)/active.toml"
            if FileManager.default.fileExists(atPath: deprecatedActivePath) {
                do {
                    try FileManager.default.removeItem(atPath: deprecatedActivePath)
                    logInfo("deprecated_active_toml_cleaned", [
                        "path": deprecatedActivePath,
                        "spec": "022",
                    ])
                } catch {
                    logWarn("deprecated_active_toml_cleanup_failed", [
                        "path": deprecatedActivePath,
                        "error": "\(error)",
                    ])
                }
            }
            let earlyPV2 = NestedStagePersistence(stagesDir: stagesDir)
            sm.setMode(.perDisplay, persistence: earlyPV2)
            let primaryUUID = resolveDisplayUUID(CGMainDisplayID())
            sm.setCurrentDesktopKey(DesktopKey(displayUUID: primaryUUID, desktopID: 1))
        }

        // Snapshot des apps déjà lancées
        for app in globalObserver?.currentApps() ?? [] {
            axEventLoop?.observe(app)
            registerExistingWindows(of: app)
        }

        // Server socket
        server = Server(socketPath: config.daemon.socketPath, handler: self)
        try server?.start()

        // SPEC-022 — auto-assign des fenêtres orphelines au scope (display, desktop)
        // de leur position physique. Avant : toutes les wids orphelines atterrissaient
        // sur `currentStage` (1 seul scope), quel que soit leur display réel → en
        // multi-display Firefox sur LG se retrouvait dans built-in stage 1.
        // Maintenant : chaque wid résolue sur SON display via frame center.
        // Skip silencieusement les wids à frame anormale (offscreen, fullscreen Space)
        // — elles seront auto-assignées plus tard via axDidMoveWindow quand AX
        // reportera une frame valide.
        if let sm = stageManager, sm.stageMode == .perDisplay {
            let dskReg = desktopRegistry
            for state in registry.allWindows
                where state.isTileable && sm.scopeOf(wid: state.cgWindowID) == nil {
                let center = CGPoint(x: state.frame.midX, y: state.frame.midY)
                guard let did = layoutEngine.displayIDContainingPoint(center) else {
                    logInfo("auto_assign_skip_offscreen", [
                        "wid": String(state.cgWindowID),
                        "frame": "\(Int(state.frame.origin.x)),\(Int(state.frame.origin.y)) "
                                + "\(Int(state.frame.width))x\(Int(state.frame.height))",
                    ])
                    continue
                }
                let uuid = resolveDisplayUUID(did)
                guard !uuid.isEmpty else { continue }
                Task { @MainActor [weak self, weak sm] in
                    guard let self = self, let sm = sm else { return }
                    let desktopID = await dskReg?.currentID(for: did) ?? 1
                    let activeStage = sm.activeStageByDesktop[
                        DesktopKey(displayUUID: uuid, desktopID: desktopID)] ?? StageID("1")
                    let scope = StageScope(displayUUID: uuid, desktopID: desktopID,
                                            stageID: activeStage)
                    if sm.stagesV2[scope] == nil {
                        _ = sm.createStage(id: activeStage,
                                            displayName: activeStage.value, scope: scope)
                    }
                    sm.assign(wid: state.cgWindowID, to: scope)
                    let cgwid = state.cgWindowID
                    // SPEC-025 amend — fix bug "tree flatten after assign" :
                    // skip le remove+insert si la wid est déjà dans le bon tree
                    // (cas dominant). Le remove+insert agressif aplatissait
                    // systématiquement l'arbre BSP que le 1er insert venait de
                    // construire (= politique dwindle perdue, drift observable).
                    let currentTreeDisplay = self.layoutEngine.displayIDForWindow(cgwid)
                    if currentTreeDisplay != did {
                        // Vraie pollution : la wid n'est pas dans le tree cible.
                        // Nettoyer + ré-insérer en préservant la position BSP via
                        // focusedID (= dernier focused réel, pas nil).
                        let focused = self.registry.focusedWindowID
                        let nearTarget: WindowID? = (focused != nil && focused != cgwid)
                            ? focused : nil
                        self.layoutEngine.removeWindow(cgwid)
                        self.layoutEngine.insertWindow(cgwid, focusedID: nearTarget,
                                                        displayID: did)
                        logInfo("tree_force_reinsert", [
                            "wid": String(cgwid),
                            "from_display": String(currentTreeDisplay ?? 0),
                            "to_display": String(did),
                            "near": nearTarget.map(String.init) ?? "nil",
                            "reason": "auto_assign_orphan",
                        ])
                    }
                    self.applyLayout()
                    logInfo("auto_assign_orphan_to_display", [
                        "wid": String(cgwid),
                        "display_uuid": uuid,
                        "desktop_id": String(desktopID),
                        "stage": activeStage.value,
                        "tree_preserved": String(currentTreeDisplay == did),
                    ])
                }
            }
        } else if let sm = stageManager, let currentStage = sm.currentStageID {
            // Mode global (V1 compat) : comportement legacy = tout dans currentStage.
            for state in registry.allWindows where state.isTileable && state.stageID == nil {
                sm.assign(wid: state.cgWindowID, to: currentStage)
            }
        }

        // SPEC-025 root-cause fix — wire le DaemonHolder vers self pour que
        // le hook applyLayout (créé à init time) puisse appeler la version
        // multi-display complète au stage switch. Sans ça, fallback engine.apply
        // mono-display → wids cross-display/stage pas show/hide → Firefox stage 2
        // restait offscreen.
        daemonHolder?.daemon = self

        // Initialiser le focus avec la fenêtre frontmost réelle.
        focusManager.refreshFromSystem()

        // Click-to-raise universel : ramène toute fenêtre cliquée au-dessus,
        // indépendamment du tiling. Comble le trou laissé par AeroSpace.
        // SPEC-015 : skip le raise quand le modifier mouse-drag est pressé pour
        // éviter le double-trigger raise+drag (= raise actif uniquement sur clic
        // simple).
        mouseRaiser = MouseRaiser(
            registry: registry,
            skipWhenModifier: config.mouse.modifier
        )
        // Click sur une fenêtre d'un autre stage → switch vers son stage. Sans ce hook,
        // le raise nu remettait la fenêtre on-screen sans changer de stage → incohérence
        // (cf. observation utilisateur : "Grayjay visible alors que stage 2 inactif").
        mouseRaiser?.onClickInOtherStage = { [weak self] _, stageID in
            guard let self = self, let sm = self.stageManager else { return false }
            guard sm.currentStageID != stageID else { return false }
            sm.switchTo(stageID: stageID)
            return true
        }
        mouseRaiser?.start()

        // SPEC-015 : drag/resize de fenêtre via modifier + clic. Lifecycle géré
        // ici, callbacks branchent vers la logique daemon (drop cross-display
        // SPEC-013, retire-from-tile, adaptResize).
        let mdh = MouseDragHandler(registry: registry, config: config.mouse)
        mdh.removeFromTile = { [weak self] wid in
            self?.layoutEngine.removeWindow(wid)
        }
        mdh.adaptResize = { [weak self] wid, finalFrame in
            guard let self = self else { return }
            _ = self.layoutEngine.adaptToManualResize(wid, newFrame: finalFrame)
            self.applyLayout()
        }
        mdh.onDragDrop = { [weak self] wid, wasFloatingBeforeDrag in
            self?.onDragDrop(wid: wid, wasFloatingBeforeDrag: wasFloatingBeforeDrag)
        }
        mdh.start()
        self.mouseDragHandler = mdh

        // SPEC-026 US5 — wire mouse_follows_focus + focus_follows_mouse.
        focusManager.mouseFollowsFocus = config.focus.mouseFollowsFocus
        let ffmw = FocusFollowsMouseWatcher(
            registry: registry,
            focusManager: focusManager,
            mouseDragHandler: mdh
        )
        if config.focus.focusFollowsMouse {
            ffmw.start()
        }
        self.focusFollowsMouseWatcher = ffmw

        // SPEC-026 US6 — signal hooks dispatcher.
        let sigDispatcher = SignalDispatcher()
        sigDispatcher.loadConfig(config.signals)
        sigDispatcher.start()
        self.signalDispatcher = sigDispatcher

        // SPEC-026 US3 — scratchpad manager.
        let scratchpadMgr = ScratchpadManager(registry: registry)
        scratchpadMgr.loadConfig(config.scratchpads)
        self.scratchpadManager = scratchpadMgr

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

        // SPEC-018 : reconcile state.stageID ↔ stage.memberWindows après le scan AX
        // initial. PAS de purgeOrphanWindows ici : le scan AX peut être incomplet à
        // T+1.5s (apps lentes type iTerm avec plusieurs fenêtres), purger des wid
        // légitimes encore en cours de scan vide les stages persistées. Les wid
        // vraiment mortes sont nettoyées en continu via handleWindowDestroyed.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5s pour laisser scan AX peupler
            // SPEC-021 : reconcileStageOwnership supprimée (single source of truth via widToScope).
            // SPEC-018 fix : ré-insertion défensive — assure que toutes les wid tilées du
            // registry sont dans le tree BSP (cas observé : après stage switch + reswitch
            // le tree était vide, focus/move/swap retournaient "no neighbor"). Idempotent.
            // SPEC-022 — réconciliation tree per-display (plus globale).
            if let self = self {
                Task { @MainActor [weak self] in
                    await self?.rebuildAllTrees()
                }
            }
            // Purge des helpers persistés par les sessions précédentes (Firefox WebExtension
            // frames 66×20, Grayjay/Electron tooltips, iTerm popovers). Sans ce passage, les
            // ~4-8 wids helpers s'accumulent dans `1.toml` à chaque sauvegarde et polluent
            // `windows.list` + le navrail. Le critère taille est stable, sûr d'appeler ici.
            self?.stageManager?.purgeOrphanWindows()
            // Au boot, currentStageID est restauré depuis le disque mais on n'a jamais
            // déclenché de hide pour les wids assignées à d'autres stages. Sans ce passage,
            // une fenêtre comme Grayjay (stage 2) reste on-screen alors que stage 1 est
            // actif. switchTo(currentStageID) est idempotent côté state mais réapplique
            // le hide → résout l'incohérence visuelle au démarrage.
            if let sm = self?.stageManager, let active = sm.currentStageID {
                sm.switchTo(stageID: active)
            }
            // Re-tile pour que les wids assignées à des stages non-actives soient cachées
            self?.applyLayout()
        }

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
        registry.onFocusChanged = { [weak loader, weak self] wid in
            guard let wid = wid else { return }
            loader?.bus.publish(FXEvent(kind: .windowFocused, wid: CGWindowID(wid)))
            // Bridge IPC : le rail (et tout subscriber `events --follow`) reçoit aussi
            // l'event pour pouvoir promouvoir la vignette focused en hero (SPEC-019).
            Task { @MainActor in
                EventBus.shared.publish(DesktopEvent(
                    name: "window_focused",
                    payload: ["wid": String(wid)]
                ))
            }
            // Auto-switch stage/desktop sur le focus de la fenêtre cible. Branché ici
            // (et pas dans axDidChangeFocusedWindow) parce qu'AltTab/Cmd-Tab peut router
            // le focus via plusieurs chemins (kAXFocusedWindowChanged direct, ou
            // kAXApplicationActivated → refreshFromSystem) — onFocusChanged est le seul
            // point central qui fire pour TOUTES les sources. Idempotent via
            // currentStageID != targetStage.
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard self.config.focus.stageFollowsFocus else { return }
                self.followFocusToStageAndDesktop(wid: wid)
            }
            // SPEC-026 US5 — mouse_follows_focus depuis source externe (Alt+Tab,
            // click app dans Dock, etc.). Le check `isWarpInhibited` (interne à
            // warpCursorToFocusedIfEnabled) empêche un warp redondant quand
            // focus_follows_mouse vient de poser le focus (souris déjà dessus).
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.focusManager.warpCursorToFocusedIfEnabled()
            }
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

            // SPEC-013 T009 : migration V2 → V3 transparente. Ne rien faire si déjà
            // migrée ou si pas de layout legacy. primaryUUID résolu depuis NSScreen
            // primary à ce stade (pas encore de DisplayRegistry).
            // Si plusieurs écrans connectés, on prend l'écran à origin (0,0) =
            // primary canonical. En cas d'absence d'UUID stable (cas rare),
            // skip — la migration sera retentée au prochain boot.
            if let primaryScreen = NSScreen.screens.first(where: { $0.frame.origin == .zero })
                ?? NSScreen.main,
               let displayID = primaryScreen.deviceDescription[
                   NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
                let primaryUUID = CFUUIDCreateString(nil, cfUUID) as String? ?? ""
                if !primaryUUID.isEmpty {
                    do {
                        let migrated = try DesktopMigration.runIfNeeded(
                            configDir: configDir, primaryUUID: primaryUUID)
                        if migrated > 0 {
                            logInfo("migration v2->v3 completed",
                                    ["count": String(migrated), "target_uuid": primaryUUID])
                        }
                    } catch {
                        logWarn("migration v2->v3 failed (non-fatal)",
                                ["error": "\(error)"])
                    }
                }
            }

            // SPEC-018 T030 : migration silencieuse V1→V2 (stages globaux → scoped per_display).
            // Déclenché uniquement en mode per_display, avant l'init du StageManager V2.
            // Sur erreur : flag migrationPending = true, boot continue en mode flat (V1).
            if config.desktops.mode == .perDisplay,
               let primaryScreen = NSScreen.screens.first(where: { $0.frame.origin == .zero })
                   ?? NSScreen.main,
               let displayID = primaryScreen.deviceDescription[
                   NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
                let mainUUID = CFUUIDCreateString(nil, cfUUID) as String? ?? ""
                if !mainUUID.isEmpty {
                    let stagesDirPath = (NSString(string: "~/.config/roadies/stages")
                        .expandingTildeInPath as String)
                    let migrator = MigrationV1V2(stagesDir: stagesDirPath, mainDisplayUUID: mainUUID)
                    do {
                        if let report = try migrator.runIfNeeded() {
                            logInfo("migration_v1_to_v2 completed", [
                                "migrated_count": String(report.migratedCount),
                                "backup_path": report.backupPath,
                                "target_display_uuid": report.targetDisplayUUID,
                                "duration_ms": String(report.durationMs),
                            ])
                            EventBus.shared.publish(DesktopEvent.migrationV1V2(
                                migratedCount: report.migratedCount,
                                backupPath: report.backupPath,
                                targetUUID: report.targetDisplayUUID,
                                durationMs: report.durationMs
                            ))
                            self.migrationPending = false
                        }
                    } catch {
                        logError("migration_v1_to_v2 failed", ["error": "\(error)"])
                        self.migrationPending = true
                    }
                }
            }

            // SPEC-018 fix : passer le primaryUUID pour que DesktopRegistry utilise
            // les paths V3 display-scoped au lieu du legacy V2 (cf. refactor V3 paths).
            let dRegistry = DesktopRegistry(
                configDir: configDir,
                displayUUID: resolveDisplayUUID(CGMainDisplayID()),
                count: config.desktops.count,
                mode: config.desktops.mode
            )
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

                // SPEC-018 : configurer la persistence V2 (scopée) selon le mode.
                let stagesDir = (NSString(string: "~/.config/roadies/stages")
                    .expandingTildeInPath as String)
                let stageMode: StageMode = config.desktops.mode == .perDisplay
                    ? .perDisplay : .global
                let persistenceV2: any StagePersistenceV2 = stageMode == .global
                    ? FlatStagePersistence(stagesDir: stagesDir)
                    : NestedStagePersistence(stagesDir: stagesDir)
                mgr.setMode(stageMode, persistence: persistenceV2)
                logInfo("stage_manager: mode set",
                        ["stage_mode": stageMode.rawValue])
                // SPEC-018 : matérialiser stage 1 dans stagesV2 maintenant que le mode V2 est actif.
                // Sans ça, `stage list` filtré par scope retourne vide et `stage 1` échoue
                // avec "unknown_stage in current scope" (la stage 1 V1 du boot n'a pas migré).
                if stageMode == .perDisplay {
                    let primaryUUID = resolveDisplayUUID(CGMainDisplayID())
                    // SPEC-019 — invariant utilisateur : "il devrait toujours y avoir au
                    // minimum la première stage" sur CHAQUE écran. Itérer sur les displays
                    // physiques (via NSScreen — DisplayRegistry n'est pas encore init à
                    // ce stade du bootstrap) et matérialiser stage 1 partout.
                    var seenUUIDs = Set<String>()
                    for screen in NSScreen.screens {
                        guard let cgID = screen.deviceDescription[
                            NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                        else { continue }
                        let uuid = resolveDisplayUUID(cgID)
                        guard !uuid.isEmpty, seenUUIDs.insert(uuid).inserted else { continue }
                        let scope = StageScope(displayUUID: uuid, desktopID: 1,
                                               stageID: StageID("1"))
                        mgr.ensureDefaultStage(scope: scope)
                    }
                    // Garde-fou : si NSScreen.screens est vide (cas extrême), au minimum
                    // matérialiser sur le primary connu.
                    if seenUUIDs.isEmpty && !primaryUUID.isEmpty {
                        let scope = StageScope(displayUUID: primaryUUID, desktopID: 1,
                                               stageID: StageID("1"))
                        mgr.ensureDefaultStage(scope: scope)
                    }
                    // SPEC-018 audit-cohérence F5 : initialiser le scope desktop courant
                    // (primary, desktop 1) pour que les futurs switchTo persistent dans
                    // le bon `_active.toml` et que currentStageID reste cohérent.
                    mgr.setCurrentDesktopKey(
                        DesktopKey(displayUUID: primaryUUID, desktopID: 1))
                }
                // SPEC-021 T031 : reconstruire l'index inverse widToScope/widToStageV1
                // depuis memberWindows persistés. Source unique de vérité pour l'API
                // scopeOf(wid:)/stageIDOf(wid:). Coût O(stages × members) une fois.
                mgr.rebuildWidToScopeIndex()
                // SPEC-021 T069 (US4) : audit read-only des invariants au boot.
                // Violation = drift hérité d'une session précédente buggée. Log + continue
                // (pas de crash) — le code post-T028 maintient les invariants par
                // construction, donc une violation signale un fichier TOML incohérent.
                let violations = mgr.auditOwnership()
                if !violations.isEmpty {
                    logError("ownership_invariant_violation_boot",
                             ["count": String(violations.count),
                              "first": violations.first ?? ""])
                }
            }
            let stageHook: (@Sendable (Int) async -> Void)? = sm.map { mgr in
                { @Sendable (newDesktopID: Int) async in
                    await MainActor.run {
                        mgr.reload(forDesktop: newDesktopID)
                        // SPEC-018 audit-cohérence F5+F6 : après reload, repositionner
                        // le scope desktop courant pour que `currentStageID` se resync
                        // au stage actif mémorisé du nouveau desktop. Sans ça, le
                        // legacy currentStageID retient le stage du desktop précédent.
                        let primaryUUID = self.resolveDisplayUUID(CGMainDisplayID())
                        mgr.setCurrentDesktopKey(
                            DesktopKey(displayUUID: primaryUUID, desktopID: newDesktopID))
                        // Garantir stage 1 + stage actif sur le desktop d'arrivée.
                        // SPEC-019 INV-3 : passer le scope explicite pour matérialiser
                        // stage 1 dans `stagesV2[(uuid, newDesktopID, "1")]` et créer le
                        // dossier disque correspondant. Sans le scope, l'API V1 fallback
                        // ne crée rien dans stagesV2 → desktop neuf reste sans stage 1.
                        let arrivalScope = StageScope(displayUUID: primaryUUID,
                                                       desktopID: newDesktopID,
                                                       stageID: StageID("1"))
                        mgr.ensureDefaultStage(scope: arrivalScope)
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

            // SPEC-021 T048+T049 : démarrer le reconciler périodique desktop macOS ↔ scope
            // persisté. Rebuild le cache spaceID avant de démarrer (SkyLightBridge @MainActor).
            // T049 : stop graceful via windowDesktopReconciler?.stop() si besoin d'un shutdown
            // explicite. En pratique, le process termine via exit() et Swift annule toutes les
            // Tasks automatiquement — pas de handler SIGTERM dans ce daemon.
            if let sm = stageManager, config.desktops.mode == .perDisplay {
                let pollMs = config.desktops.windowDesktopPollMs
                if let displaySpaces = SkyLightBridge.managedDisplaySpaces() {
                    await dRegistry.rebuildSpaceIDCache(from: displaySpaces)
                }
                let reconciler = WindowDesktopReconciler(
                    registry: registry,
                    desktopRegistry: dRegistry,
                    stageManager: sm,
                    layoutEngine: self.layoutEngine,
                    displayRegistry: self.displayRegistry,
                    pollIntervalMs: pollMs
                )
                reconciler.applyLayoutCallback = { [weak self] in
                    self?.applyLayout()
                }
                reconciler.start()
                self.windowDesktopReconciler = reconciler
            }
        } else {
            logInfo("desktops disabled (desktops.enabled=false)")
        }

        // SPEC-012 T009/T018 : init DisplayRegistry + observer didChangeScreenParameters.
        // L'observer est dans bootstrap() car les notifications AppKit ne peuvent pas
        // être observées proprement depuis un actor Swift.
        // Transmettre les gaps de [tiling] au DisplayRegistry pour que applyAll
        // les utilise comme defaults par display (sinon 0/4 hardcodés et les
        // gaps de la config sont ignorés en multi-display).
        let dspRegistry = DisplayRegistry(
            defaultGapsOuter: config.tiling.gapsOuter,
            defaultGapsInner: config.tiling.gapsInner
        )
        await dspRegistry.refresh()
        // T038 : appliquer les règles per-display de la config après chaque refresh.
        await dspRegistry.applyRules(config.displays)
        // SPEC-013 : seed currentByDisplay du DesktopRegistry avec la liste des
        // displays présents pour que `desktop list` expose la map dès le boot.
        if let dRegistry = self.desktopRegistry {
            let presentIDs = await dspRegistry.displays.map(\.id)
            await dRegistry.syncCurrentByDisplay(presentIDs: presentIDs)
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak dspRegistry] _ in
            guard let self, let dspRegistry else { return }
            Task { @MainActor in
                // T026 : capturer l'état avant refresh pour calculer le diff.
                let oldDisplays = await dspRegistry.displays
                await dspRegistry.refresh()
                // T038 : ré-appliquer les règles per-display après chaque refresh.
                await dspRegistry.applyRules(self.config.displays)
                let newDisplays = await dspRegistry.displays
                await self.handleDisplayConfigurationChange(old: oldDisplays, new: newDisplays)
            }
        }
        self.displayRegistry = dspRegistry
        logInfo("display_registry initialized", ["count": String(await dspRegistry.count)])

        // SPEC-013 nettoyage pré-recovery : retirer du BSP les leaves avec frame
        // dégénérée. Ces leaves sont issues de drags ou restaurations corrompues.
        // Si on ne les retire pas, applyLayout va re-calculer des cellules x20px
        // pour elles et écraser le recovery.
        for state in registry.allWindows {
            if state.frame.size.height < 100 || state.frame.size.height > 100_000 {
                layoutEngine.removeWindow(state.cgWindowID)
                logInfo("boot: degenerate leaf removed from BSP tree", [
                    "wid": String(state.cgWindowID),
                    "frame_h": String(Int(state.frame.size.height)),
                ])
            }
        }

        // SPEC-013 recovery au boot : ramener à l'écran les fenêtres dont la frame
        // est offscreen (Y < -1000 typiquement, ou hors de tous les displays).
        // Cause : un cycle hide/show précédent a corrompu state.frame via les
        // events axDidMoveWindow déclenchés par moveOffScreen, sans que le show
        // ne soit correctement appliqué. Recovery = pour chaque fenêtre orpheline,
        // setBounds à expectedFrame (si valide) ou centrer sur le primary.
        let primaryScreen = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
        if let primaryScreen {
            let primaryHeight = primaryScreen.frame.height
            for state in registry.allWindows {
                let center = CGPoint(x: state.frame.midX, y: state.frame.midY)
                let onScreen = NSScreen.screens.contains { screen in
                    let nsCenter = CGPoint(x: center.x,
                                           y: primaryHeight - center.y)
                    return screen.frame.contains(nsCenter)
                }
                // Détection orphan élargie :
                //  - center hors de tous les displays (cas 1)
                //  - OU frame degenerate (height < 100 ou y < -500) — cas où
                //    HideStrategy.moveOffScreen a placé la fenêtre dans un coin
                //    extrême sans qu'un show postérieur ne soit appliqué.
                let isDegenerate = state.frame.size.height < 100
                    || state.frame.origin.y < -500
                let needsRecovery = !onScreen || isDegenerate
                if needsRecovery, let element = registry.axElement(for: state.cgWindowID) {
                    // AVANT toute action : vérifier si CGWindowList rapporte une
                    // taille radicalement différente de l'AX bounds. C'est un
                    // mismatch connu sur certaines apps (iTerm tabs, Firefox
                    // Netflix) où kAXSize retourne 20px alors que la fenêtre
                    // physique fait 2000+. Si le CG bounds est sain, on adopte
                    // simplement cette valeur dans state.frame et on skip la
                    // recovery (la fenêtre est déjà bien placée à l'écran).
                    if let cgInfo = liveCGBounds(for: state.cgWindowID),
                       cgInfo.size.height >= 100 {
                        registry.updateFrame(state.cgWindowID, frame: cgInfo)
                        registry.update(state.cgWindowID) { $0.expectedFrame = cgInfo }
                        logInfo("recovery: AX/CG mismatch fixed", [
                            "wid": String(state.cgWindowID),
                            "ax_frame": "\(Int(state.frame.size.width))x\(Int(state.frame.size.height))",
                            "cg_frame": "\(Int(cgInfo.size.width))x\(Int(cgInfo.size.height))",
                        ])
                        continue
                    }
                    let target: CGRect
                    if state.expectedFrame != .zero
                        && state.expectedFrame.size.height >= 100 {
                        target = state.expectedFrame
                    } else {
                        // Centre sur le primary (visibleFrame AX).
                        let pf = primaryScreen.visibleFrame
                        let pfAX = CGRect(
                            x: pf.origin.x,
                            y: primaryHeight - pf.origin.y - pf.height,
                            width: pf.width, height: pf.height)
                        target = CGRect(
                            x: pfAX.midX - 400, y: pfAX.midY - 300,
                            width: 800, height: 600)
                    }
                    // Réveiller la fenêtre AX-collapsed avant setBounds. Une fenêtre
                    // dans le coin "AeroSpace hide" peut être en état où setBounds
                    // est silencieusement ignoré ; un setMinimized(false) +
                    // setFullscreen(false) + setBounds répétés débloquent.
                    AXReader.setMinimized(element, false)
                    AXReader.setFullscreen(element, false)
                    AXReader.raise(element)
                    AXReader.setBounds(element, frame: target)
                    AXReader.setBounds(element, frame: target)  // 2e passe : certaines apps refusent le 1er setBounds après wake
                    registry.updateFrame(state.cgWindowID, frame: target)
                    registry.update(state.cgWindowID) { $0.expectedFrame = target }
                    logInfo("recovery: orphaned offscreen window restored", [
                        "wid": String(state.cgWindowID),
                        "old_frame": "\(Int(state.frame.origin.x)),\(Int(state.frame.origin.y))",
                        "new_frame": "\(Int(target.origin.x)),\(Int(target.origin.y))",
                    ])
                }
            }
        }

        // SPEC-013 : balance les weights des arbres BSP au boot. Cause des frames
        // x20 absurdes : drags antérieurs ont affaissé les weights vers 0.001.
        // Reset à 1.0 = équivalent `yabai -m space --balance` au boot.
        for (_, root) in layoutEngine.workspace.rootsByDisplay {
            balanceWeights(root)
        }

        // Initial layout APRÈS init du DisplayRegistry, pour que applyAll prenne
        // la branche multi-display et tile chaque écran (sinon fallback mono-écran
        // tile uniquement le primary, les autres écrans restent en placement libre).
        applyLayout()

        // SPEC-014 : init SCKCaptureService + WallpaperClickWatcher.
        let sck = SCKCaptureService()
        let thumbCacheRef = self.thumbnailCache
        sck.onCapture = { [weak self] entry in
            thumbCacheRef?.put(entry)
            EventBus.shared.publish(DesktopEvent.thumbnailUpdated(wid: entry.wid))
            _ = self // keep alive
        }
        self.sckCaptureService = sck

        if AXIsProcessTrusted() {
            let watcher = WallpaperClickWatcher(registry: registry)
            // SPEC-014 T060 (US4) : câbler le coordinator si stage manager présent.
            if let sm = self.stageManager {
                let coordinator = WallpaperStageCoordinator(registry: registry, stageManager: sm)
                watcher.onWallpaperClick = { point in
                    coordinator.handleClick(at: point)
                }
            } else {
                // Fallback : juste publier l'event si stage manager désactivé.
                watcher.onWallpaperClick = { point in
                    EventBus.shared.publish(DesktopEvent.wallpaperClick(
                        x: Int(point.x), y: Int(point.y), displayID: CGMainDisplayID()))
                }
            }
            watcher.start()
            self.wallpaperClickWatcher = watcher
        } else {
            logWarn("wallpaper_watcher: AX not trusted, watcher skipped")
        }

        logInfo("roadied ready")

        // SPEC-024 — démarrage du rail in-process (fusion mono-binaire). Le rail
        // accède directement aux sous-systèmes du daemon via le proxy
        // CommandHandler ; plus de socket Unix loop-back ni d'EventStream sous-process.
        // Stocké dans une propriété forte pour éviter le déalloc ARC.
        self.railController = RailIntegration.start(handler: self)
        logInfo("rail_started_inprocess")
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
        var frame = AXReader.bounds(axWindow) ?? .zero
        // SPEC-022 — au registre initial, si AX retourne une frame degenerate
        // (height ou width < 100, classique sur Firefox/iTerm pendant init AX),
        // tenter CGWindowList qui souvent retourne la bonne taille. Sans ça,
        // la wid est créée comme "helper" et reste mal classifiée toute sa vie.
        let minDim = WindowState.minimumUsefulDimension
        if frame.size.height < minDim || frame.size.width < minDim {
            if let cg = liveCGBounds(for: wid),
               cg.size.height >= minDim && cg.size.width >= minDim {
                logInfo("registerWindow: AX degenerate, used CG fallback", [
                    "wid": String(wid),
                    "ax": "\(Int(frame.size.width))x\(Int(frame.size.height))",
                    "cg": "\(Int(cg.size.width))x\(Int(cg.size.height))",
                ])
                frame = cg
            }
        }
        let isMin = AXReader.isMinimized(axWindow)
        let isFs = AXReader.isFullscreen(axWindow)
        let state = WindowState(cgWindowID: wid, pid: pid, bundleID: bundleID,
                                title: AXReader.title(axWindow), frame: frame,
                                subrole: subrole,
                                isFloating: subrole.isFloatingByDefault,
                                isMinimized: isMin, isFullscreen: isFs)
        registry.register(state, axElement: axWindow)
        axEventLoop?.subscribeDestruction(pid: pid, axWindow: axWindow)
        // CAUSE RACINE Grayjay (insertion) : si la wid est déjà persistée dans une
        // stage V2, propager `state.stageID` AVANT `insertWindow`. Sans ce passage,
        // `LayoutEngine.stageID(for:)` fallback sur `activeStageID` (= "1" au boot),
        // et la wid est insérée dans le mauvais tree → applyAll la layoute comme une
        // wid de stage 1 visible, contredit la persistance.
        // SPEC-021 : block obsolete. state.stageID est maintenant computed via
        // widToScope (rebuilt au boot par rebuildWidToScopeIndex). Inutile de
        // re-propager au register d'une wid : si elle est dans memberWindows,
        // l'index pointera correctement.
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
        // CAUSE RACINE Grayjay : si la wid est DÉJÀ persistée dans une stage (mode V2),
        // ne PAS l'écraser avec le stage courant. La délégation V1→V2 (F11) propagerait
        // cette ré-assignation à stagesV2 + disque → la mémoire de l'attribution serait
        // perdue. La wid recevra son state.stageID correct via reconcileStageOwnership
        // au boot (sens stagesV2 → state.stageID).
        if state.isTileable, let sm = stageManager {
            let alreadyAssigned: Bool = {
                if sm.stageMode == .perDisplay {
                    return sm.stagesV2.values.contains { stage in
                        stage.memberWindows.contains { $0.cgWindowID == state.cgWindowID }
                    }
                } else {
                    return sm.stages.values.contains { stage in
                        stage.memberWindows.contains { $0.cgWindowID == state.cgWindowID }
                    }
                }
            }()
            if !alreadyAssigned {
                // SPEC-022 : en perDisplay, assigner au scope du display PHYSIQUE de
                // la wid (frame center → displayUUID). Sinon (V1 global), legacy
                // currentStageID. Sans cette résolution, toutes les wids scannées
                // partaient sur le scope courant (= built-in) quel que soit leur
                // display réel → tout finissait dans built-in stage 1 en multi-display.
                if sm.stageMode == .perDisplay {
                    let center = CGPoint(x: state.frame.midX, y: state.frame.midY)
                    if let did = layoutEngine.displayIDContainingPoint(center) {
                        let uuid = resolveDisplayUUID(did)
                        if !uuid.isEmpty {
                            // Résoudre le current desktop pour ce display.
                            let dskReg = desktopRegistry
                            let cgwid = state.cgWindowID
                            Task { @MainActor [weak self, weak sm] in
                                guard let self = self, let sm = sm else { return }
                                let desktopID = await dskReg?.currentID(for: did) ?? 1
                                let activeStage = sm.activeStageByDesktop[
                                    DesktopKey(displayUUID: uuid, desktopID: desktopID)] ?? StageID("1")
                                let scope = StageScope(displayUUID: uuid, desktopID: desktopID,
                                                        stageID: activeStage)
                                if sm.stagesV2[scope] == nil {
                                    _ = sm.createStage(id: activeStage,
                                                        displayName: activeStage.value, scope: scope)
                                }
                                sm.assign(wid: cgwid, to: scope)
                                // SPEC-025 amend — voir commentaire identique
                                // ligne 430 (registerExistingWindows). Skip le
                                // remove+insert si la wid est déjà dans le bon
                                // tree, pour préserver la profondeur BSP.
                                let currentTreeDisplay = self.layoutEngine.displayIDForWindow(cgwid)
                                if currentTreeDisplay != did {
                                    let focused = self.registry.focusedWindowID
                                    let nearTarget: WindowID? = (focused != nil && focused != cgwid)
                                        ? focused : nil
                                    self.layoutEngine.removeWindow(cgwid)
                                    self.layoutEngine.insertWindow(cgwid, focusedID: nearTarget,
                                                                    displayID: did)
                                    logInfo("tree_force_reinsert", [
                                        "wid": String(cgwid),
                                        "from_display": String(currentTreeDisplay ?? 0),
                                        "to_display": String(did),
                                        "near": nearTarget.map(String.init) ?? "nil",
                                        "reason": "auto_assign_orphan_runtime",
                                    ])
                                }
                                self.applyLayout()
                            }
                        }
                    }
                    // Sinon : frame offscreen / display introuvable → laisser orphelin,
                    // sera ré-évalué par axDidMoveWindow plus tard.
                } else if let stageID = sm.currentStageID {
                    sm.assign(wid: state.cgWindowID, to: stageID)
                }
            }
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

    func applyLayout(then completion: (@MainActor @Sendable () -> Void)? = nil) {
        lastApplyTimestamp = Date()
        if let dspRegistry = displayRegistry {
            // T018 : multi-display → distribuer sur tous les écrans.
            // @MainActor obligatoire : applyAll fait des appels AX (AXReader.setBounds)
            // qui doivent être sur le main thread. Sans @MainActor un AXValue créé sur
            // un thread bg pollue le pool autorelease du main → SIGSEGV au prochain
            // pool drain pendant NSApp.run.
            // Coalescing : si une applyAll est en vol, on ne re-spawn pas (ça empile
            // sur le main actor et bloque la socket-handler des minutes). On set juste
            // un flag pour redéclencher une fois la première finie.
            if applyLayoutInFlight {
                applyLayoutNeedsRetrigger = true
                return
            }
            applyLayoutInFlight = true
            let outerSides = config.tiling.effectiveOuterGaps
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                logInfo("applyAll start")
                await self.layoutEngine.applyAll(displayRegistry: dspRegistry, outerSides: outerSides)
                logInfo("applyAll done")
                // SPEC-025 — invariant cross-stage : auditOwnership détecte les wids
                // dans 2+ scopes simultanément (= "wid stage 2 visible aussi en stage 1"
                // signalé par user). Émission warn structurée, parser bash agrège en
                // stage_double_membership_5m (NUMERIC_AXES, threshold 1 = invariant absolu).
                if let sm = self.stageManager {
                    let violations = sm.auditOwnership()
                    let doubleMembership = violations.filter { $0.contains("in 2 scopes") }
                    for v in doubleMembership {
                        logWarn("stage_double_membership", ["violation": String(v.prefix(220))])
                    }
                }
                // SPEC-025 — invariant orphan : toute wid présente dans un tree
                // (= tilée) DOIT appartenir à une stage. Sinon : pas de stage
                // ownership → modules FX (borders, opacity) ne la voient pas
                // + cross-stage drift possible. Catch silencieux des bugs
                // d'insertion qui oublient l'assignment (cf. toggle floating
                // pré-fix wid 17848 sans stage).
                if let sm = self.stageManager {
                    var orphans: [WindowID] = []
                    var crossStage: [(WindowID, String, String)] = []
                    for (treeKey, root) in self.layoutEngine.workspace.rootsByStageDisplay {
                        for leaf in root.allLeaves {
                            let widScope = sm.scopeOf(wid: leaf.windowID)
                            if widScope == nil {
                                orphans.append(leaf.windowID)
                            } else if let s = widScope, s.stageID != treeKey.stageID {
                                crossStage.append((leaf.windowID, treeKey.stageID.value, s.stageID.value))
                            }
                        }
                    }
                    for wid in orphans {
                        logWarn("tiled_orphan_stage", ["wid": String(wid)])
                    }
                    for (wid, treeStage, scopeStage) in crossStage {
                        logWarn("tile_in_wrong_tree", [
                            "wid": String(wid),
                            "tree_stage": treeStage,
                            "scope_stage": scopeStage,
                        ])
                    }
                    // SPEC-025 — staged_orphan_tree : wid présente dans memberWindows
                    // d'une stage MAIS pas dans le tree (= aucune leaf dans rootsByStageDisplay).
                    // Symptôme : wid "fantôme" visible avec frame native macOS, jamais
                    // reframée par applyAll. Cas typique : sm.assign() oublié d'insérer
                    // dans le tree (cf. fix CommandRouter case stage.assign 2026-05-05).
                    var allTreeLeaves = Set<WindowID>()
                    for (_, root) in self.layoutEngine.workspace.rootsByStageDisplay {
                        for leaf in root.allLeaves { allTreeLeaves.insert(leaf.windowID) }
                    }
                    for (scope, stage) in sm.stagesV2 {
                        for member in stage.memberWindows {
                            if !allTreeLeaves.contains(member.cgWindowID) {
                                logWarn("staged_orphan_tree", [
                                    "wid": String(member.cgWindowID),
                                    "scope_stage": scope.stageID.value,
                                    "scope_display": scope.displayUUID,
                                ])
                            }
                        }
                    }
                    // SPEC-025 root-cause fix — auto-cure UNIQUEMENT au tout 1er
                    // applyAll après boot (one-shot via flag). Garantit que les
                    // wids sont dans le bon tree dès le démarrage du daemon
                    // (= cas Firefox stage 2 inséré tree stage 1 par boot race).
                    // Pas d'auto-cure aux applyAll suivants → pas de cascade
                    // reassign pendant stage switches (= pas d'animation parasite).
                    if !crossStage.isEmpty && !self.didInitialDriftFix {
                        let fixed = self.layoutEngine.fixCrossStageDrift { wid in
                            sm.scopeOf(wid: wid)?.stageID
                        }
                        if fixed > 0 {
                            logInfo("tile_cross_stage_boot_fixed", ["count": String(fixed)])
                        }
                        self.didInitialDriftFix = true
                    }
                }
                self.applyLayoutInFlight = false
                // SPEC-025 — completion appelée APRÈS setBounds + audit, mais
                // AVANT que d'autres events AX externes ne puissent intervenir.
                // Caller idéal : focus-follow après move/warp.
                completion?()
                if self.applyLayoutNeedsRetrigger {
                    self.applyLayoutNeedsRetrigger = false
                    self.applyLayout()
                }
            }
        } else {
            // Fallback mono-écran (avant que le displayRegistry soit initialisé).
            let area = displayManager.workArea
            let gaps = config.tiling.effectiveOuterGaps
            layoutEngine.apply(rect: area,
                               outerGaps: gaps,
                               gapsInner: CGFloat(config.tiling.gapsInner))
        }
    }

    // MARK: - SPEC-012 T026-T029 : recovery branch/débranch

    /// Diff `old` vs `new` et migre les fenêtres des écrans retirés vers le primary (T027).
    /// Pour chaque écran ajouté, crée un root vide (T028).
    /// Émet `display_configuration_changed` si la liste a changé (T029).
    func handleDisplayConfigurationChange(old: [Display], new: [Display]) async {
        let oldIDs = Set(old.map(\.id))
        let newIDs = Set(new.map(\.id))
        let removed = old.filter { !newIDs.contains($0.id) }
        let added = new.filter { !oldIDs.contains($0.id) }
        guard !removed.isEmpty || !added.isEmpty else { return }
        let primaryID = CGMainDisplayID()
        let primary = new.first(where: { $0.isMain }) ?? new.first
        // T027 : migrer les fenêtres des écrans retirés vers le primary.
        if let primary {
            for removedDisplay in removed {
                guard let removedRoot = layoutEngine.workspace.rootsByDisplay[removedDisplay.id] else { continue }
                let wids = removedRoot.allLeaves.map { $0.windowID }
                for wid in wids {
                    guard let state = registry.get(wid) else { continue }
                    let clamped = clampFrameToVisible(state.frame, in: primary.visibleFrame)
                    if let element = registry.axElement(for: wid) {
                        AXReader.setBounds(element, frame: clamped)
                    }
                    registry.updateFrame(wid, frame: clamped)
                    _ = layoutEngine.moveWindow(wid, fromDisplay: removedDisplay.id, toDisplay: primaryID)
                    if let dRegistry = desktopRegistry {
                        let currentDeskID = await dRegistry.currentID
                        try? await dRegistry.updateWindowDisplayUUID(
                            cgwid: UInt32(wid),
                            desktopID: currentDeskID,
                            displayUUID: primary.uuid
                        )
                    }
                }
                layoutEngine.clearDisplayRoot(for: removedDisplay.id)
                logInfo("display removed: windows migrated to primary", [
                    "removed_id": String(removedDisplay.id),
                    "count": String(wids.count),
                ])
            }
        }
        // T028 : créer des roots vides pour les écrans ajoutés.
        for addedDisplay in added {
            layoutEngine.initDisplayRoot(for: addedDisplay.id)
            logInfo("display added: root initialized", ["id": String(addedDisplay.id)])
        }
        // SPEC-013 T031-T032 : restoration au rebranchement.
        // Pour chaque écran ajouté qui a un historique sur disque, restorer son
        // current desktop + ses fenêtres précédemment assignées.
        if let dRegistry = desktopRegistry {
            let configDir = URL(fileURLWithPath:
                (NSString(string: "~/.config/roadies").expandingTildeInPath as String))
            for addedDisplay in added {
                let uuid = addedDisplay.uuid
                guard !uuid.isEmpty else { continue }
                // Restore current per-display.
                if let saved = DesktopPersistence.loadCurrent(
                    configDir: configDir, displayUUID: uuid) {
                    await dRegistry.setCurrent(saved, on: addedDisplay.id)
                    logInfo("display rebranched: current restored", [
                        "uuid": uuid, "desktop": String(saved),
                    ])
                }
                // Restore fenêtres assignées (matching N1 cgwid > N2 bundle/title).
                for desktopID in 1...config.desktops.count {
                    let snapshots = DesktopPersistence.loadDesktopWindows(
                        configDir: configDir, displayUUID: uuid, desktopID: desktopID)
                    var restoredCount = 0
                    for snap in snapshots {
                        // N1 : matching par cgwid encore vivant.
                        if let state = registry.get(WindowID(snap.cgwid)) {
                            // Bouger vers ce display + ajuster expectedFrame.
                            if let element = registry.axElement(for: state.cgWindowID) {
                                AXReader.setBounds(element, frame: snap.expectedFrame)
                            }
                            registry.updateFrame(state.cgWindowID, frame: snap.expectedFrame)
                            registry.update(state.cgWindowID) { $0.desktopID = desktopID }
                            // Re-router dans l'arbre du display.
                            if state.isTileable {
                                if let curDisplay = layoutEngine.displayIDForWindow(state.cgWindowID),
                                   curDisplay != addedDisplay.id {
                                    _ = layoutEngine.moveWindow(state.cgWindowID,
                                                                fromDisplay: curDisplay,
                                                                toDisplay: addedDisplay.id)
                                }
                            }
                            restoredCount += 1
                            continue
                        }
                        // N2 : matching par bundleID + title prefix (cas process redémarré).
                        let candidates = registry.allWindows.filter {
                            $0.bundleID == snap.bundleID
                                && (!snap.titlePrefix.isEmpty
                                    && $0.title.hasPrefix(snap.titlePrefix))
                        }
                        if candidates.count == 1 {
                            let cand = candidates[0]
                            if let element = registry.axElement(for: cand.cgWindowID) {
                                AXReader.setBounds(element, frame: snap.expectedFrame)
                            }
                            registry.updateFrame(cand.cgWindowID, frame: snap.expectedFrame)
                            registry.update(cand.cgWindowID) { $0.desktopID = desktopID }
                            if cand.isTileable,
                               let curDisplay = layoutEngine.displayIDForWindow(cand.cgWindowID),
                               curDisplay != addedDisplay.id {
                                _ = layoutEngine.moveWindow(cand.cgWindowID,
                                                            fromDisplay: curDisplay,
                                                            toDisplay: addedDisplay.id)
                            }
                            restoredCount += 1
                        }
                        // FR-020 : N1+N2 fail → ignore silencieusement.
                    }
                    if restoredCount > 0 {
                        logInfo("display rebranched: windows restored", [
                            "uuid": uuid,
                            "desktop": String(desktopID),
                            "count": String(restoredCount),
                        ])
                    }
                }
            }
            // Sync currentByDisplay avec la liste des displays présents.
            await dRegistry.syncCurrentByDisplay(presentIDs: new.map(\.id))
        }
        // Ré-appliquer le layout sur tous les écrans.
        applyLayout()
        // T029 : émettre display_configuration_changed via le bus RoadieCore.
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        EventBus.shared.publish(DesktopEvent(
            name: "display_configuration_changed",
            payload: ["ts": String(ts)]
        ))
    }

    /// Ajuste `frame` pour qu'elle tienne dans `visible` (clamp + shift), T027.
    private func clampFrameToVisible(_ frame: CGRect, in visible: CGRect) -> CGRect {
        var origin = frame.origin
        var size = frame.size
        if size.width > visible.width * 0.95 { size.width = visible.width * 0.8 }
        if size.height > visible.height * 0.95 { size.height = visible.height * 0.8 }
        if origin.x < visible.minX { origin.x = visible.minX + 10 }
        if origin.y < visible.minY { origin.y = visible.minY + 10 }
        if origin.x + size.width > visible.maxX { origin.x = visible.maxX - size.width - 10 }
        if origin.y + size.height > visible.maxY { origin.y = visible.maxY - size.height - 10 }
        return CGRect(origin: origin, size: size)
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

    /// SPEC-013 : suit le focus d'une fenêtre cachée (déclenchée par AltTab,
    /// Cmd-Tab, ou tout autre raise programmatique) en basculant le desktop du
    /// display où la fenêtre vit. Sans ça, l'app remonte au front mais sa
    /// fenêtre reste invisible (offscreen via HideStrategy).
    func followAltTabFocus(_ wid: WindowID) async {
        guard let dReg = desktopRegistry,
              let state = registry.get(wid) else { return }
        let mode = await dReg.mode
        guard mode == .perDisplay else { return }
        // BUGFIX : ne pas réagir aux dialogs/popovers (subrole != standard).
        // Un dialog peut prendre le focus juste après ouverture, ce qui ferait
        // basculer le desktop entier sans raison. macOS gère leur visibilité.
        guard state.isTileable else { return }
        // Identifier le display où la fenêtre est censée vivre.
        // state.frame est offscreen quand cachée → fallback expectedFrame.
        var displayID: CGDirectDisplayID?
        let frameCenter = CGPoint(x: state.frame.midX, y: state.frame.midY)
        displayID = layoutEngine.displayIDContainingPoint(frameCenter)
        if displayID == nil && state.expectedFrame != .zero {
            let expCenter = CGPoint(x: state.expectedFrame.midX,
                                    y: state.expectedFrame.midY)
            displayID = layoutEngine.displayIDContainingPoint(expCenter)
        }
        guard let resolvedDisplay = displayID else { return }
        let currentOnDisplay = await dReg.currentID(for: resolvedDisplay)

        // SPEC-022 — re-étiquetage automatique via SkyLight DÉSACTIVÉ.
        // Le modèle utilisateur : l'étiquette (widToScope) est pilotée par les
        // décisions explicites (drag manuel, raccourci, drag rail). Le système ne
        // doit PAS re-étiqueter sur la position physique macOS observée. Sinon :
        // - Click sur thumb → switchTo → focus change → followAltTabFocus →
        //   SkyLight observe la wid (peut-être sur Space différent à cause d'un
        //   fullscreen Netflix transient) → re-assign → la thumb migre vers
        //   l'autre écran « sans raison ».
        // Le drift éventuel sera corrigé par l'user via drag explicite. Si on veut
        // un audit/réconciliation, ce sera un outil séparé pas un effet de bord.
        _ = SkyLightBridge.self  // ref maintenue pour ne pas casser l'import si non utilisé ailleurs

        // No-op si la fenêtre est déjà sur le desktop courant du display.
        guard state.desktopID != currentOnDisplay else { return }
        let targetDesktop = state.desktopID
        // Anti-feedback : si on a déjà basculé pour ce wid très récemment, skip.
        let now = Date()
        if now.timeIntervalSince(lastAltTabFollowTimestamp) < 0.3 { return }
        lastAltTabFollowTimestamp = now

        // Bascule : appliquer hide/show ciblé pour ce display.
        await dReg.setCurrent(targetDesktop, on: resolvedDisplay)
        let allWindows = registry.allWindows
        for s in allWindows {
            let c1 = CGPoint(x: s.frame.midX, y: s.frame.midY)
            var did = layoutEngine.displayIDContainingPoint(c1)
            if did == nil && s.expectedFrame != .zero {
                let c2 = CGPoint(x: s.expectedFrame.midX, y: s.expectedFrame.midY)
                did = layoutEngine.displayIDContainingPoint(c2)
            }
            guard let resolvedDid = did, resolvedDid == resolvedDisplay else { continue }
            // BUGFIX : skip non-tileable (dialogs, popovers système). Sinon on
            // les cache offscreen alors que macOS les gère en floating natif.
            guard s.isTileable else { continue }
            let shouldShow = s.desktopID == targetDesktop
            layoutEngine.setLeafVisible(s.cgWindowID, shouldShow)
            if shouldShow {
                HideStrategyImpl.show(s.cgWindowID, registry: registry,
                                      strategy: config.stageManager.hideStrategy)
            } else {
                HideStrategyImpl.hide(s.cgWindowID, registry: registry,
                                      strategy: config.stageManager.hideStrategy)
            }
        }
        applyLayout()
        logInfo("alttab follow: desktop switched", [
            "wid": String(wid),
            "display_id": String(resolvedDisplay),
            "desktop": String(targetDesktop),
        ])
    }

    /// Auto-switch stage + desktop pour révéler la fenêtre nouvellement focused.
    /// Idempotent : ne fait rien si stage/desktop courants matchent déjà.
    /// Anti-parasite via `state.isTileable` (filtre dialogs/popovers/helpers).
    /// PAS de filtre sur la position : une wid cachée par HideStrategy est offscreen
    /// (origin.x ≈ -100000), c'est précisément le cas qu'on veut suivre.
    func followFocusToStageAndDesktop(wid: WindowID) {
        // SPEC-022 — check moins strict que isTileable : on veut suivre le focus
        // même vers les wids "float" (iTerm drawer, etc.) tant que ce sont des
        // windows utilisateur réelles. On exclut seulement les vrais helpers
        // (subrole non-standard ou size < 100, popovers/tooltips/dialogs).
        guard let state = registry.get(wid),
              state.subrole == .standard,
              !state.isHelperWindow,
              !state.isMinimized else { return }
        // Anti-feedback : si on a déjà fait un follow récent (< 500ms), skip.
        // switchTo() rend la wid cible visible/focused, ce qui re-fire onFocusChanged
        // sur cette wid puis sur l'ancienne (effet ping-pong). Sans ce guard, on
        // oscille entre 2 stages tant que les 2 ont une wid focused.
        let now = Date()
        if now.timeIntervalSince(lastFocusFollowTimestamp) < 0.5 { return }
        // 1. Desktop (mode per_display uniquement, géré dans followAltTabFocus).
        if config.desktops.enabled {
            Task { @MainActor [weak self] in
                await self?.followAltTabFocus(wid)
            }
        }
        // 2. Stage : switcher si différent et que la stage cible existe DANS LE
        // SCOPE PHYSIQUE DE LA WID. Avant : check global de l'existence (true si
        // stage existe sur n'importe quel display) → switchTo échouait avec
        // 'unknown stage in current scope' quand la stage existait sur un autre
        // display que celui de la wid. SPEC-026 fix : résoudre le scope correct.
        if let sm = stageManager,
           let targetStage = state.stageID,
           sm.currentStageID != targetStage {
            if sm.stageMode == .perDisplay {
                // Pose le timestamp SYNCHRONE avant le Task pour éviter la race :
                // sans ça, 2 onFocusChanged dans la même 500ms passent tous les
                // deux le check anti-feedback (le Task async n'a pas eu le
                // temps d'updater le timestamp). Résultat : ping-pong.
                lastFocusFollowTimestamp = now
                let center = CGPoint(x: state.frame.midX, y: state.frame.midY)
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    guard let display = await self.displayRegistry?.displayContaining(point: center) else {
                        return
                    }
                    let desktopID = await self.desktopRegistry?.currentID(for: display.id) ?? 1
                    let fullScope = StageScope(displayUUID: display.uuid,
                                               desktopID: desktopID, stageID: targetStage)
                    guard sm.stagesV2[fullScope] != nil else {
                        logInfo("focus_follow_skipped", [
                            "wid": String(wid),
                            "want_stage": targetStage.value,
                            "scope": "\(String(display.uuid.prefix(8)))/\(desktopID)",
                            "reason": "stage_missing_in_target_scope",
                        ])
                        return
                    }
                    logInfo("focus_follow stage switch", [
                        "wid": String(wid),
                        "from": sm.currentStageID?.value ?? "nil",
                        "to": targetStage.value,
                        "scope": "\(String(display.uuid.prefix(8)))/\(desktopID)",
                    ])
                    sm.switchTo(stageID: targetStage, scope: fullScope)
                }
            } else {
                // Mode global : check legacy.
                guard sm.stages[targetStage] != nil else {
                    logInfo("focus_follow_skipped", [
                        "wid": String(wid),
                        "want_stage": targetStage.value,
                        "reason": "stage_missing",
                    ])
                    return
                }
                logInfo("focus_follow stage switch", [
                    "wid": String(wid),
                    "from": sm.currentStageID?.value ?? "nil",
                    "to": targetStage.value,
                ])
                lastFocusFollowTimestamp = now
                sm.switchTo(stageID: targetStage)
            }
        }
    }

    /// SPEC-013 : retourne les bounds réels d'une fenêtre via CGWindowList
    /// (= source de vérité système), utilisé pour détecter le mismatch AX/CG
    /// sur certaines apps (iTerm tabs, Firefox plein écran AX-collapsed).
    private func liveCGBounds(for wid: WindowID) -> CGRect? {
        guard let arr = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                                    kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        for info in arr {
            guard let n = info[kCGWindowNumber as String] as? WindowID, n == wid else { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            return CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )
        }
        return nil
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
        // Émettre window_created sur le bus DesktopEvent pour que le rail se resync.
        // Sans ça, ouvrir une nouvelle fenêtre n'apparaît pas dans le navrail tant qu'un
        // autre event ne déclenche pas un reload (stage_changed, desktop_changed, etc.).
        if let wid = axWindowID(of: axWindow) {
            EventBus.shared.publish(DesktopEvent(name: "window_created",
                                                payload: ["wid": String(wid)]))
            // SPEC-026 US3 — tente d'attacher la wid à un scratchpad pending.
            if let app = NSRunningApplication(processIdentifier: pid) {
                scratchpadManager?.tryAttachOnWindowCreated(
                    wid: wid, bundleID: app.bundleIdentifier
                )
            }
        }
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
        // Émettre window_destroyed sur le bus DesktopEvent pour que le rail retire
        // immédiatement la vignette correspondante. Sans ça, la wid morte reste
        // affichée jusqu'au prochain refresh (stage_changed, desktop_changed).
        EventBus.shared.publish(DesktopEvent(name: "window_destroyed",
                                            payload: ["wid": String(wid)]))
    }
    func axDidMoveWindow(pid: pid_t, wid: WindowID) {
        guard let element = registry.axElement(for: wid),
              let frame = AXReader.bounds(element) else { return }
        // SPEC-025 amend — log info pour distinguer mouvement piloté par roadie
        // (= dans la fenêtre 200ms post-applyLayout) vs mouvement subi (drag user,
        // macOS Mission Control, snap auto). Source = "self" si le delta est
        // imputable à notre propre setBounds, "external" sinon.
        let prevFrame = registry.get(wid)?.frame
        let timeSinceApply = Date().timeIntervalSince(lastApplyTimestamp)
        let source = timeSinceApply < 0.2 ? "self" : "external"
        if let prev = prevFrame {
            let dx = abs(prev.origin.x - frame.origin.x)
            let dy = abs(prev.origin.y - frame.origin.y)
            let dw = abs(prev.width - frame.width)
            let dh = abs(prev.height - frame.height)
            if dx + dy + dw + dh > 1 {
                logInfo("ax_window_moved", [
                    "wid": String(wid),
                    "source": source,
                    "from": "\(Int(prev.origin.x)),\(Int(prev.origin.y)) \(Int(prev.width))x\(Int(prev.height))",
                    "to": "\(Int(frame.origin.x)),\(Int(frame.origin.y)) \(Int(frame.width))x\(Int(frame.height))",
                    "since_apply_ms": String(Int(timeSinceApply * 1000)),
                ])
            }
        }
        registry.updateFrame(wid, frame: frame)
        trackDrag(wid: wid)
        propagateExpectedFrame(wid: wid, frame: frame)
        fxLoader?.bus.publish(FXEvent(kind: .windowMoved,
                                      wid: CGWindowID(wid), frame: frame))
    }
    func axDidResizeWindow(pid: pid_t, wid: WindowID) {
        guard let element = registry.axElement(for: wid),
              let frame = AXReader.bounds(element) else { return }
        // SPEC-022 — rejeter les frames degenerate (height ou width < 100 px).
        // Cause : iTerm/Firefox AX reporte parfois 1836×20 pendant des transitions
        // (drawer ouvert/fermé, change d'onglet). Si on accepte, isHelperWindow
        // devient true → wid classifiée non-tileable → tile ne la replace plus →
        // reste offscreen invisible quand on switch de stage.
        // Les vraies fenêtres > 100 px passent normalement. Un user qui réduit
        // volontairement à 20 px (cas très rare) n'aura pas le cache à jour, mais
        // le drag manuel suivant déclenchera axDidMoveWindow qui re-set la frame.
        let minDim = WindowState.minimumUsefulDimension
        if frame.size.height < minDim || frame.size.width < minDim {
            // Fallback : tenter CGWindowList qui souvent reporte la bonne taille
            // quand AX bug. Si CG est sain, l'adopter. Sinon, ignorer cet update.
            if let cgInfo = liveCGBounds(for: wid),
               cgInfo.size.height >= minDim && cgInfo.size.width >= minDim {
                registry.updateFrame(wid, frame: cgInfo)
                logInfo("axDidResize: AX degenerate, used CG fallback", [
                    "wid": String(wid),
                    "ax": "\(Int(frame.size.width))x\(Int(frame.size.height))",
                    "cg": "\(Int(cgInfo.size.width))x\(Int(cgInfo.size.height))",
                ])
                propagateExpectedFrame(wid: wid, frame: cgInfo)
            } else {
                logInfo("axDidResize: ignored degenerate frame", [
                    "wid": String(wid),
                    "ax": "\(Int(frame.size.width))x\(Int(frame.size.height))",
                ])
            }
            return
        }
        registry.updateFrame(wid, frame: frame)
        trackDrag(wid: wid)
        propagateExpectedFrame(wid: wid, frame: frame)
        // SPEC-025 — drag-resize externe (= hors fenêtre 200ms post-applyLayout) :
        // marque la wid comme user-resized pour que tiler_extreme_aspect ne crie
        // pas si l'utilisateur compresse volontairement la fenêtre.
        if Date().timeIntervalSince(lastApplyTimestamp) >= 0.2 {
            layoutEngine.noteUserResize(wid)
        }
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
        if dragTrackedWid != wid {
            // SPEC-025 — log INFO pour post-mortem drag (avant: aucun log start).
            logInfo("drag_started", [
                "wid": String(wid),
                "from_frame": "\(Int(state.frame.origin.x)),\(Int(state.frame.origin.y)) \(Int(state.frame.width))x\(Int(state.frame.height))",
                "from_display": String(layoutEngine.displayIDForWindow(wid) ?? 0),
                "scope_stage": stageManager?.scopeOf(wid: wid)?.stageID.value ?? "nil",
            ])
        }
        dragTrackedWid = wid
    }

    /// Variante MouseDragHandler : la wid est connue (pas via dragTrackedWid),
    /// et on doit en plus restaurer `isFloating=false` + réinsérer dans le tree
    /// si la fenêtre était tilée avant le drag (cf. user feedback : un drag
    /// manuel ne doit pas transformer une fenêtre tilée en floating permanent).
    func onDragDrop(wid: WindowID, wasFloatingBeforeDrag: Bool) {
        // Force le tracking pour réutiliser la logique cross-display existante.
        dragTrackedWid = wid
        onDragDrop()
        // Re-tile si la wid n'était pas explicitement floatée par l'utilisateur.
        // MouseDragHandler.handleMouseDragged a mis isFloating=true + removeFromTile
        // au 1er drag delta — on défait ça maintenant que le drag est terminé.
        guard !wasFloatingBeforeDrag else { return }
        registry.update(wid) { $0.isFloating = false }
        // Si la wid n'est plus dans aucun tree (cas same-display drag), réinsérer.
        if layoutEngine.displayIDForWindow(wid) == nil {
            // SPEC-025 amend — passer focused au lieu de nil pour préserver
            // la sémantique BSP (insertion près de la wid voisine, pas au root).
            let focused = registry.focusedWindowID
            let nearTarget: WindowID? = (focused != nil && focused != wid) ? focused : nil
            layoutEngine.insertWindow(wid, focusedID: nearTarget)
            applyLayout()
            logInfo("drag_retile", ["wid": String(wid),
                                     "near": nearTarget.map(String.init) ?? "nil"])
        }
    }

    /// Appelé par DragWatcher au `leftMouseUp`. Si un wid a été trackée pendant le drag,
    /// on lit sa frame finale et on :
    /// 1) si la fenêtre a traversé un autre écran, on migre l'arbre (FR-013 spec-012)
    /// 2) sinon, on adapte les weights de l'arbre en conséquence
    func onDragDrop() {
        guard let wid = dragTrackedWid else { return }
        dragTrackedWid = nil
        guard let element = registry.axElement(for: wid),
              let frame = AXReader.bounds(element) else {
            logInfo("drag_ended_no_element", ["wid": String(wid)])
            return
        }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let resolvedDisplay = layoutEngine.displayIDContainingPoint(center)
        let treeDisplay = layoutEngine.displayIDForWindow(wid)
        // SPEC-025 — log INFO pour post-mortem drag end (avant: rien).
        logInfo("drag_ended", [
            "wid": String(wid),
            "drop_frame": "\(Int(frame.origin.x)),\(Int(frame.origin.y)) \(Int(frame.width))x\(Int(frame.height))",
            "drop_center": "\(Int(center.x)),\(Int(center.y))",
            "resolved_display": resolvedDisplay.map(String.init) ?? "nil",
            "tree_display": treeDisplay.map(String.init) ?? "nil",
            "will_migrate": String(resolvedDisplay != nil && treeDisplay != nil && resolvedDisplay != treeDisplay),
        ])
        // SPEC-022 fix : si frame center offscreen (Netflix fullscreen, window
        // hidée par stage switch, etc.), NE PAS faker realDisplayID = main.
        // Le fallback CGMainDisplayID() forçait une migration vers built-in à
        // chaque mouvement offscreen → toutes les wids LG migraient vers built-in.
        // Skip la migration : la wid garde son scope d'origine, sera ré-évaluée
        // quand AX reportera une frame valide.
        guard let realDisplayID = resolvedDisplay else {
            logInfo("drag_skip_offscreen", ["wid": String(wid)])
            // Adapt manual resize si la frame est valide mais offscreen (cas dock).
            _ = layoutEngine.adaptToManualResize(wid, newFrame: frame)
            return
        }
        let treeDisplayID = treeDisplay
        if let src = treeDisplayID, src != realDisplayID {
            // Migration cross-display : la fenêtre a été draggée d'un écran à l'autre.
            _ = layoutEngine.moveWindow(wid, fromDisplay: src, toDisplay: realDisplayID)
            if let dRegistry = desktopRegistry, let dReg = displayRegistry {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    let mode = await dRegistry.mode
                    // SPEC-013 FR-011 : en mode per_display, la fenêtre adopte le
                    // current desktop du display cible. En global, garde son desktopID
                    // (compat V2, FR-013).
                    let newDesktopID: Int
                    if mode == .perDisplay {
                        newDesktopID = await dRegistry.currentID(for: realDisplayID)
                        self.registry.update(wid) { $0.desktopID = newDesktopID }
                    } else {
                        newDesktopID = await dRegistry.currentID
                    }
                    let displays = await dReg.displays
                    if let dst = displays.first(where: { $0.id == realDisplayID }) {
                        try? await dRegistry.updateWindowDisplayUUID(
                            cgwid: UInt32(wid),
                            desktopID: newDesktopID,
                            displayUUID: dst.uuid
                        )
                        // SPEC-022 fix : migrer aussi l'ownership stagesV2. Sans ça, la wid
                        // reste membre de la stage du display source → rail panel source affiche
                        // toujours la vignette alors que la window est physiquement sur le
                        // display cible. assign(wid:to:scope:) retire la wid de tous les
                        // autres scopes et l'ajoute au scope cible (active stage du nouveau
                        // (display, desktop)).
                        if let sm = self.stageManager, sm.stageMode == .perDisplay {
                            let targetKey = DesktopKey(displayUUID: dst.uuid,
                                                        desktopID: newDesktopID)
                            let targetStageID = sm.activeStageByDesktop[targetKey]
                                                ?? StageID("1")
                            let targetScope = StageScope(displayUUID: dst.uuid,
                                                          desktopID: newDesktopID,
                                                          stageID: targetStageID)
                            // Garantir que la stage cible existe (lazy create si absent).
                            if sm.stagesV2[targetScope] == nil {
                                _ = sm.createStage(id: targetStageID,
                                                    displayName: targetStageID.value,
                                                    scope: targetScope)
                            }
                            sm.assign(wid: wid, to: targetScope)
                            // Notifier les rails (les 2 panels concernés vont resync).
                            EventBus.shared.publish(DesktopEvent(
                                name: "window_assigned",
                                payload: ["wid": String(wid),
                                          "stage_id": targetStageID.value,
                                          "display_uuid": dst.uuid,
                                          "desktop_id": String(newDesktopID)]))
                        }
                    }
                    self.applyLayout()
                }
            } else {
                applyLayout()
            }
            logInfo("drag_migrated_cross_display",
                     ["wid": String(wid), "from": String(src), "to": String(realDisplayID)])
            return
        }
        if layoutEngine.adaptToManualResize(wid, newFrame: frame) {
            logInfo("drag_adapted_same_display",
                    ["wid": String(wid), "display": String(realDisplayID)])
            applyLayout()
        } else {
            logInfo("drag_no_action", [
                "wid": String(wid),
                "display": String(realDisplayID),
                "reason": "adaptToManualResize returned false (frame matches calculated)",
            ])
        }
    }
    func axDidChangeFocusedWindow(pid: pid_t, axWindow: AXUIElement) {
        // Auto-GC : à chaque event de focus, vérifier que les fenêtres connues
        // existent encore (rattrape les Cmd+W que kAXUIElementDestroyed a ratés).
        pruneDeadWindows()
        // Cause root du focus-thrashing : `refreshFromSystem()` re-query
        // NSWorkspace.frontmostApplication.AXFocusedWindow, qui pour les apps
        // multi-window peut retourner la *main* window de l'app au lieu de la
        // fenêtre que macOS vient juste de focaliser (c'est-à-dire l'axWindow
        // qu'on reçoit ici). Race ⇒ on écrasait le focus du clic. Fix : utiliser
        // directement l'élément reçu, fallback refreshFromSystem si non résolvable.
        if let wid = axWindowID(of: axWindow) {
            if registry.get(wid) == nil {
                registerWindow(pid: pid, axWindow: axWindow)
            }
            registry.setFocus(wid)
            // L'auto-switch stage/desktop est branché sur registry.onFocusChanged
            // (cf. bootstrap()), couvrant toutes les sources de focus change y compris
            // les paths qui ne passent pas par cette callback AX directe.
        } else {
            focusManager.refreshFromSystem()
        }
        // windowFocused FX publié automatiquement par registry.onFocusChanged
        // (cf. branchement dans bootstrap()).

        // T042 : recalculer l'écran actif et émettre display_changed si changé.
        if let dReg = displayRegistry,
           let wid = axWindowID(of: axWindow),
           let state = registry.get(wid) {
            let center = CGPoint(x: state.frame.midX, y: state.frame.midY)
            Task { @MainActor in
                if let newDisplay = await dReg.displayContaining(point: center) {
                    let changed = await dReg.setActive(id: newDisplay.id)
                    if changed {
                        let ts = Int64(Date().timeIntervalSince1970 * 1000)
                        EventBus.shared.publish(DesktopEvent(
                            name: "display_changed",
                            payload: [
                                "display_index": String(newDisplay.index),
                                "display_id": String(newDisplay.id),
                                "ts": String(ts),
                            ]
                        ))
                    }
                }
            }
        }
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

    // MARK: - SPEC-018 : résolution du scope courant

    /// Résout le StageScope correspondant à l'emplacement courant (curseur → frontmost → primary).
    /// Retourne `.global(StageID(""))` en mode global (stageID placeholder, complété par le caller).
    /// En mode per_display, résout displayUUID + desktopID et retourne un scope partiel
    /// (stageID == StageID("")) que le caller complète avec l'ID réel avant lookup.
    /// SPEC-026 — variante qui priorise la fenêtre focused (mieux pour stage.switch
    /// quand mouse_follows_focus est activé : le curseur peut se balader).
    func currentStageScopeFocusedFirst() async -> StageScope {
        guard config.desktops.mode == .perDisplay else {
            return .global(StageID(""))
        }
        // Priorité 1 : fenêtre focused (intent stable).
        if let wid = registry.focusedWindowID,
           let state = registry.get(wid) {
            let center = CGPoint(x: state.frame.midX, y: state.frame.midY)
            if let display = await displayRegistry?.displayContaining(point: center) {
                let desktopID = await desktopRegistry?.currentID(for: display.id) ?? 1
                let scope = StageScope(displayUUID: display.uuid, desktopID: desktopID, stageID: StageID(""))
                logInfo("scope_inferred_from", [
                    "source": "focused_window",
                    "display_uuid": display.uuid,
                    "desktop_id": String(desktopID),
                    "wid": String(wid),
                ])
                return scope
            }
        }
        // Fallback : curseur (la logique d'origine).
        return await currentStageScope()
    }

    func currentStageScope() async -> StageScope {
        guard config.desktops.mode == .perDisplay else {
            return .global(StageID(""))
        }
        // Priorité 1 : position du curseur (source de vérité, cohérent avec desktop.focus).
        let mouseLoc = NSEvent.mouseLocation
        if let display = await displayRegistry?.displayContaining(point: mouseLoc) {
            let desktopID = await desktopRegistry?.currentID(for: display.id) ?? 1
            let scope = StageScope(displayUUID: display.uuid, desktopID: desktopID, stageID: StageID(""))
            logInfo("scope_inferred_from", [
                "source": "cursor",
                "display_uuid": display.uuid,
                "desktop_id": String(desktopID),
            ])
            return scope
        }
        // Priorité 2 : fenêtre frontmost.
        if let wid = registry.focusedWindowID,
           let state = registry.get(wid) {
            let center = CGPoint(x: state.frame.midX, y: state.frame.midY)
            if let display = await displayRegistry?.displayContaining(point: center) {
                let desktopID = await desktopRegistry?.currentID(for: display.id) ?? 1
                let scope = StageScope(displayUUID: display.uuid, desktopID: desktopID, stageID: StageID(""))
                logInfo("scope_inferred_from", [
                    "source": "frontmost",
                    "display_uuid": display.uuid,
                    "desktop_id": String(desktopID),
                ])
                return scope
            }
        }
        // Fallback : display principal.
        let primaryID = CGMainDisplayID()
        let uuid = resolveDisplayUUID(primaryID)
        let desktopID = await desktopRegistry?.currentID(for: primaryID) ?? 1
        logInfo("scope_inferred_from", [
            "source": "primary",
            "display_uuid": uuid,
            "desktop_id": String(desktopID),
        ])
        return StageScope(displayUUID: uuid, desktopID: desktopID, stageID: StageID(""))
    }

    /// Convertit un CGDirectDisplayID en UUID stable cross-reboot.
    private func resolveDisplayUUID(_ id: CGDirectDisplayID) -> String {
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "" }
        return CFUUIDCreateString(nil, cfUUID) as String? ?? ""
    }

    /// SPEC-022 — réconciliation BSP tree per-display, basée sur widToScope (single
    /// source of truth SPEC-021). Pour chaque display physique : retire les wids du
    /// tree qui ne devraient pas y être, et insère celles qui devraient y être.
    /// Élimine la pollution cross-display en mode multi-écran.
    func rebuildAllTrees() async {
        guard let sm = stageManager, sm.stageMode == .perDisplay,
              let dReg = displayRegistry else { return }
        let displays = await dReg.displays
        for display in displays {
            let activeStage = sm.activeStageByDesktop[
                DesktopKey(displayUUID: display.uuid, desktopID: 1)] ?? StageID("1")
            // SPEC-022 — déclarer la stage active per-display. Sans ça, applyAll
            // utiliserait le fallback global "1" pour tous les displays.
            layoutEngine.setActiveStage(activeStage, displayID: display.id)
            // Wids attendues sur ce tree : celles dont widToScope pointe vers
            // (display.uuid, *, *). Cross-stage handled : seules celles de la stage
            // active du display seront visibles, les autres présentes en tree mais
            // marquées invisible par switchTo.
            let expectedWids = registry.allWindows.compactMap { state -> WindowID? in
                guard state.isTileable else { return nil }
                guard let scope = sm.scopeOf(wid: state.cgWindowID) else { return nil }
                guard scope.displayUUID == display.uuid else { return nil }
                return state.cgWindowID
            }
            // Nettoyer toute wid présente dans ce tree mais pas attendue.
            let key = StageDisplayKey(stageID: activeStage, displayID: display.id)
            if let root = layoutEngine.workspace.rootsByStageDisplay[key] {
                let presentWids = root.allLeaves.map { $0.windowID }
                for wid in presentWids where !expectedWids.contains(wid) {
                    layoutEngine.removeWindow(wid)
                }
            }
            // Insérer les attendues manquantes.
            _ = layoutEngine.ensureTreePopulated(with: expectedWids, displayID: display.id)
        }
        // SPEC-026 — rebalance TOUS les trees après rebuild, pas seulement les
        // actifs. Les inserts en cascade peuvent déséquilibrer les poids des
        // trees non-actifs (ex: stage 2 reconstruit alors que stage 1 active),
        // qui produisent des frames extrêmes au prochain stage switch.
        let balanced = layoutEngine.balanceAllTrees()
        logInfo("rebuild_all_trees_done", [
            "displays": String(displays.count),
            "leaves_rebalanced": String(balanced),
        ])
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
