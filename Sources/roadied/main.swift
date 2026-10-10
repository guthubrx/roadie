import Foundation
import AppKit
import Darwin
import RoadieAX
import RoadieCore
import RoadieDaemon

let args = resolvedArguments()
// SPEC-011 atomique : les sous-commandes lecteur ne persistent pas l'etat canonique
// (stages.json, intent.json). Seuls `tiler` et `run` (legacy monolithique) sont
// writers autorises. Sans cela, plusieurs process roadied (rail + border + focus + ...)
// font chacun leur snapshot() avec mutation+save, et s'ecrasent mutuellement, causant
// des nouvelles fenetres assignees au mauvais stage (cf. bug observe).
private let roadieReaderCommands: Set<String> = [
    "rail", "border", "focus-mouse", "titlebar-menu", "target-mode", "restore-safety", "restore-watch"
]
if let first = args.first, roadieReaderCommands.contains(first) {
    setenv("ROADIE_PERSIST_STATE_CHANGES", "0", 1)
}
let service = SnapshotService()
var railController: RailController?
var borderController: BorderController?
var focusFollowsMouseController: FocusFollowsMouseController?
var titlebarContextMenuController: TitlebarContextMenuController?
var targetModeRuntimeController: TargetModeRuntimeController?
var displayChangeObserver: NSObjectProtocol?
var pendingDisplayHeal: Task<Void, Never>?
var displaySettlingUntil: Date = .distantPast
// Veille, réveil, changement de session : ticks suspendus jusqu'à cette date (SPEC-016 T065).
var tickSuspendedUntil: Date = .distantPast
var pendingWakeReconcile: DispatchWorkItem?
var powerObservers: [NSObjectProtocol] = []
var daemonStatusPublisher: DaemonStatusPublisher?
// Retenu globalement : la sous-commande `tiler` (runComponent) retourne avant
// NSApplication.run(), donc une reference locale serait desallouee.
var tilerLiveObserver: AXWindowEventObserver?
// Canal des commandes CLI (`run` et `tiler`), retenu pour toute la vie du process.
var commandSocketServer: CommandSocketServer?

func printUsage() {
    print("""
    usage:
      roadied run --yes [--interval-ms N] [--ticks N]
                       [--no-tiler] [--no-rail] [--no-border]
                       [--no-focus-mouse] [--no-titlebar-menu]
                       [--no-target-mode] [--no-restore-safety]
      roadied tiler --yes [--interval-ms N] [--ticks N] [--no-restore-safety]
      roadied rail
      roadied border
      roadied focus-mouse
      roadied titlebar-menu
      roadied target-mode
      roadied restore-watch --pid PID [--poll-ms N] [--grace-ms N]
      roadied snapshot [--json] [--prompt-permissions]
      roadied permissions [--prompt]
      roadied help | -h | --help
      roadied --version

    `run` et `tiler` partagent un verrou d'instance (~/.roadies/roadied.lock) :
    un seul des deux peut tourner par session.
    """)
}

/// Registre d'arrêt unique (SPEC-016 R9) : SIGTERM, SIGINT, SIGHUP et la fin normale de
/// NSApplication (`--ticks`) passent tous par `shutdown()`. Les actions s'exécutent une seule
/// fois, en ordre inverse d'enregistrement : le verrou d'instance, enregistré en premier, est
/// libéré en dernier, après la restauration des fenêtres masquées.
@MainActor
enum ShutdownRegistry {
    private static var actions: [() -> Void] = []
    private static var signalSources: [DispatchSourceSignal] = []
    private static var terminationObserver: NSObjectProtocol?
    private static var didShutdown = false

    static func register(_ action: @escaping () -> Void) {
        actions.append(action)
    }

    static func install() {
        guard signalSources.isEmpty else { return }
        // DispatchSourceSignal accepte une closure. Le handler par défaut est neutralisé par
        // SIG_IGN, sinon le process se termine avant que la source ne tire.
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated { shutdown() }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { shutdown() }
        }
    }

    static func shutdown() {
        guard !didShutdown else { return }
        didShutdown = true
        for action in actions.reversed() {
            action()
        }
    }

    static func shutdownAndExit(_ code: Int32) -> Never {
        shutdown()
        exit(code)
    }
}

/// Prend le verrou d'instance `lockName` pour toute la vie du process, ou quitte avec un
/// message clair si un autre process le détient. Le verrou est libéré par le registre d'arrêt.
@MainActor
private func acquireInstanceLock(_ lockName: String, label: String) {
    let lock = ComponentLockFile(component: lockName)
    do {
        try lock.acquire()
    } catch ComponentLockError.alreadyRunning(let pid) {
        let owner = pid > 0 ? "pid \(pid)" : "pid inconnu"
        fputs("roadied \(label): already running (\(owner), lock ~/.roadies/\(lockName).lock); stop it before starting another instance\n", stderr)
        exit(1)
    } catch {
        fputs("roadied \(label): failed to acquire lock: \(error)\n", stderr)
        exit(1)
    }
    ShutdownRegistry.install()
    // La closure retient le verrou : sans elle, `deinit` le libérerait à la sortie de portée.
    ShutdownRegistry.register { lock.release() }
}

/// Lance NSApplication.run() sous verrou d'instance. Utilisé par les sous-commandes de
/// composant unique (tiler, rail, border, ...).
@MainActor
private func runComponent(_ name: String, lockName: String? = nil, start: () -> Void) -> Never {
    acquireInstanceLock(lockName ?? name, label: name)
    NSApplication.shared.setActivationPolicy(.accessory)
    start()
    NSApplication.shared.run()
    ShutdownRegistry.shutdownAndExit(0)
}

/// Publie `~/.roadies/daemon-status.json` au démarrage puis toutes les 5 s ; le fichier n'est
/// réécrit qu'en cas de changement (permission, config) ou de battement dû (30 s).
@MainActor
func startDaemonStatusPublisher(mode: String) {
    let publisher = DaemonStatusPublisher(mode: mode)
    publisher.publish()
    daemonStatusPublisher = publisher
    let timer = Timer(timeInterval: 5, repeats: true) { _ in
        MainActor.assumeIsolated { _ = daemonStatusPublisher?.publish() }
    }
    RunLoop.main.add(timer, forMode: .common)
}

// MARK: - Fonctions de démarrage des composants (source unique, SPEC-012)
//
// Chaque composant a UNE seule fonction de démarrage, appelée à la fois par le mode
// monolithique (`run`) et par sa sous-commande modulaire. Cela élimine la duplication
// qui causait des divergences de comportement entre les deux modes (SPEC-011).

@MainActor
func startRailComponent() {
    UserInputActivity.shared.startMonitoring()
    railController = RailController()
    railController?.start()
    ShutdownRegistry.register { railController?.stop() }
}

@MainActor
func startBorderComponent() {
    borderController = BorderController()
    borderController?.start()
}

@MainActor
func startFocusMouseComponent() {
    focusFollowsMouseController = FocusFollowsMouseController()
    focusFollowsMouseController?.start()
}

@MainActor
func startTitlebarMenuComponent() {
    titlebarContextMenuController = TitlebarContextMenuController()
    titlebarContextMenuController?.start()
}

@MainActor
func startTargetModeComponent() {
    targetModeRuntimeController = TargetModeRuntimeController(service: service)
    targetModeRuntimeController?.start()
}

/// Canal socket des commandes CLI, servi par le process qui détient le verrou d'instance.
/// Enregistré après le verrou : le registre l'arrête avant de libérer le verrou.
@MainActor
func startCommandSocketComponent() {
    commandSocketServer = CommandSocketServer.start(router: CLICommandRouter())
    ShutdownRegistry.register { commandSocketServer?.stop() }
}

/// Sécurité de restauration, tenue par le process qui détient le verrou d'instance (`run` ou
/// `tiler`) : le watcher surveille donc le pid du tiler. À appeler AVANT le tiler, pour que la
/// reprise d'un arrêt incomplet précède toute disposition.
@MainActor
func startRestoreSafetyComponent() {
    let controller = RestoreSafetyRuntimeController(
        service: RestoreSafetyService(service: service),
        stageStore: service.effectiveStageStore,
        pid: ProcessInfo.processInfo.processIdentifier
    )
    // Retenu par le registre d'arrêt (action enregistrée dans `start()`).
    controller.start()
}

/// Au changement de paramètres d'écran (display branché/débranché), planifie un
/// "parking heal" léger : `DaemonHealthService.healDisplayChange()` migre les stages des
/// écrans disparus vers un écran présent (un seul snapshot, service partagé) ; le tick
/// suivant applique la disposition. Sans cet observer, les fenêtres d'un écran
/// déconnecté restent orphelines (floating) indéfiniment.
@MainActor
func installDisplayChangeObserver(displaySettleSeconds: Double) {
    displayChangeObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification,
        object: nil,
        queue: .main
    ) { _ in
        Task { @MainActor in
            displaySettlingUntil = Date().addingTimeInterval(displaySettleSeconds)
            pendingDisplayHeal?.cancel()
            pendingDisplayHeal = Task { @MainActor in
                let nanoseconds = UInt64(displaySettleSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                pendingDisplayHeal = nil
                displaySettlingUntil = .distantPast
                let report = DaemonHealthService(service: service, stageStore: service.effectiveStageStore).healDisplayChange()
                print("display-change-heal parking=\(report.kind.rawValue)/\(report.reason.rawValue)")
                fflush(stdout)
            }
        }
    }
}

/// Veille, verrouillage de session : suspend les ticks. Réveil, retour de session : reprise
/// 3 s plus tard par une seule réconciliation, le temps que macOS restaure écrans et fenêtres.
@MainActor
func installPowerObservers(reconcile: @escaping @MainActor () -> Void) {
    let center = NSWorkspace.shared.notificationCenter
    let suspendNames = [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification]
    let resumeNames = [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification]
    for name in suspendNames {
        powerObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                pendingWakeReconcile?.cancel()
                pendingWakeReconcile = nil
                tickSuspendedUntil = .distantFuture
            }
        })
    }
    for name in resumeNames {
        powerObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let resumeDelay: TimeInterval = 3
                tickSuspendedUntil = Date().addingTimeInterval(resumeDelay)
                pendingWakeReconcile?.cancel()
                let item = DispatchWorkItem {
                    MainActor.assumeIsolated {
                        pendingWakeReconcile = nil
                        tickSuspendedUntil = .distantPast
                        reconcile()
                    }
                }
                pendingWakeReconcile = item
                DispatchQueue.main.asyncAfter(deadline: .now() + resumeDelay, execute: item)
            }
        })
    }
}

/// Démarre le tiler : observer d'écran + timer de polling + voie rapide AX.
/// La voie rapide re-tile en ~15-80ms dès qu'une fenêtre apparaît/change, sans
/// attendre le prochain tick de polling.
@MainActor
func startTilerComponent(interval: Double, ticks: Int?, displaySettleSeconds: Double, enableLiveEvents: Bool) {
    UserInputActivity.shared.startMonitoring()
    installDisplayChangeObserver(displaySettleSeconds: displaySettleSeconds)

    let maintainer = LayoutMaintainer(intervalSeconds: interval)
    var reportedAccessibilityDenied = false
    let target = MaintenanceTimerTarget(
        maintainer: maintainer,
        maxTicks: ticks,
        shouldTick: { Date() >= displaySettlingUntil && Date() >= tickSuspendedUntil }
    ) { tick in
        if tick.accessibilityDenied {
            if !reportedAccessibilityDenied {
                fputs("roadied: accessibilityTrusted=false; enable Accessibility for roadied or run from a trusted terminal\n", stderr)
                fflush(stderr)
                reportedAccessibilityDenied = true
            }
            return
        }
        reportedAccessibilityDenied = false
        if tick.commands > 0 || tick.failed > 0 {
            print("commands=\(tick.commands) applied=\(tick.applied) clamped=\(tick.clamped) failed=\(tick.failed)")
            fflush(stdout)
        }
    }
    let timer = Timer(timeInterval: interval, target: target, selector: #selector(MaintenanceTimerTarget.tick(_:)), userInfo: nil, repeats: true)
    RunLoop.main.add(timer, forMode: .common)
    installPowerObservers { target.performTick(timer, countsTowardLimit: false) }

    guard enableLiveEvents else { return }
    let liveEvents = EventLog()
    var pendingLiveTick: DispatchWorkItem?
    var lastLiveTickAt: Date = .distantPast
    let liveCoalesceMs = value(after: "--live-coalesce-ms").flatMap(Double.init) ?? 80
    let fastLiveCoalesceMs = value(after: "--fast-live-coalesce-ms").flatMap(Double.init) ?? 15
    let fastNotifications: Set<String> = [
        kAXWindowCreatedNotification as String,
        kAXFocusedWindowChangedNotification as String,
        kAXMainWindowChangedNotification as String,
        kAXWindowDeminiaturizedNotification as String,
        kAXUIElementDestroyedNotification as String,
    ]
    let liveObserver = AXWindowEventObserver { notification in
        let isFastEvent = fastNotifications.contains(notification)
        if !isFastEvent && Date().timeIntervalSince(lastLiveTickAt) < 0.2 { return }
        pendingLiveTick?.cancel()
        let requestedAt = Date()
        let delayMs = isFastEvent ? fastLiveCoalesceMs : liveCoalesceMs
        let item = DispatchWorkItem {
            pendingLiveTick = nil
            let beforeTick = Date()
            let tick = target.performTick(timer, countsTowardLimit: false)
            lastLiveTickAt = Date()
            if isFastEvent || tick.commands > 0 || tick.failed > 0 {
                liveEvents.append(RoadieEvent(type: "live_tick", details: [
                    "notification": notification,
                    "fast": String(isFastEvent),
                    "delayMs": String(format: "%.1f", delayMs),
                    "latencyMs": String(format: "%.1f", beforeTick.timeIntervalSince(requestedAt) * 1000),
                    "durationMs": String(format: "%.1f", Date().timeIntervalSince(beforeTick) * 1000),
                    "commands": String(tick.commands),
                    "applied": String(tick.applied),
                    "failed": String(tick.failed),
                ]))
            }
        }
        pendingLiveTick = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(delayMs)), execute: item)
    }
    liveObserver.start()
    tilerLiveObserver = liveObserver
}

switch args.first {
case "run":
    guard args.contains("--yes") else {
        fputs("roadied: refusing to maintain layout without --yes\n", stderr)
        exit(2)
    }
    let intervalMs = value(after: "--interval-ms").flatMap(Double.init) ?? 500
    let ticks = value(after: "--ticks").flatMap(Int.init)
    let displaySettleSeconds = max(0.5, (value(after: "--display-settle-ms").flatMap(Double.init) ?? 1500) / 1000)
    let interval = max(100, intervalMs) / 1000

    // Verrou d'instance partagé avec `tiler` (FR-019), tenu jusqu'à la sortie.
    acquireInstanceLock("roadied", label: "run")
    startDaemonStatusPublisher(mode: "run")

    // Démarrage des composants via les fonctions uniques partagées avec le mode modulaire
    // (SPEC-012). Ordre historique préservé. Chaque composant est actif par défaut,
    // désactivable via son flag --no-*. La sécurité de restauration passe avant le tiler.
    if !args.contains("--no-restore-safety") { startRestoreSafetyComponent() }
    if !args.contains("--no-rail") { startRailComponent() }
    if !args.contains("--no-border") { startBorderComponent() }
    if !args.contains("--no-focus-mouse") { startFocusMouseComponent() }
    if !args.contains("--no-titlebar-menu") { startTitlebarMenuComponent() }
    if !args.contains("--no-target-mode") { startTargetModeComponent() }
    if !args.contains("--no-tiler") {
        startTilerComponent(
            interval: interval,
            ticks: ticks,
            displaySettleSeconds: displaySettleSeconds,
            enableLiveEvents: !args.contains("--no-live-events")
        )
    }
    startCommandSocketComponent()
    NSApplication.shared.run()
case "tiler":
    guard args.contains("--yes") else {
        fputs("roadied tiler: refusing to maintain layout without --yes\n", stderr)
        exit(2)
    }
    let intervalMs = value(after: "--interval-ms").flatMap(Double.init) ?? 500
    let ticks = value(after: "--ticks").flatMap(Int.init)
    let displaySettleSeconds = max(0.5, (value(after: "--display-settle-ms").flatMap(Double.init) ?? 1500) / 1000)
    let interval = max(100, intervalMs) / 1000
    runComponent("tiler", lockName: "roadied") {
        startDaemonStatusPublisher(mode: "tiler")
        if !args.contains("--no-restore-safety") { startRestoreSafetyComponent() }
        startTilerComponent(
            interval: interval,
            ticks: ticks,
            displaySettleSeconds: displaySettleSeconds,
            enableLiveEvents: !args.contains("--no-live-events")
        )
        startCommandSocketComponent()
    }
case "rail":
    runComponent("rail") { startRailComponent() }
case "border":
    runComponent("border") { startBorderComponent() }
case "focus-mouse":
    runComponent("focus-mouse") { startFocusMouseComponent() }
case "titlebar-menu":
    runComponent("titlebar-menu") { startTitlebarMenuComponent() }
case "target-mode":
    runComponent("target-mode") { startTargetModeComponent() }
case "restore-safety":
    // Compatibilité : la sécurité de restauration vit désormais dans `run` et `tiler`, pour
    // que le watcher surveille le pid du tiler et non celui d'un process séparé.
    fputs("roadied restore-safety: handled by `roadied run` and `roadied tiler`; nothing to do\n", stderr)
    exit(0)
case "restore-watch":
    guard let rawPID = value(after: "--pid"), let pid = Int32(rawPID) else {
        fputs("roadied: restore-watch requires --pid PID\n", stderr)
        exit(64)
    }
    let pollMs = value(after: "--poll-ms").flatMap(UInt32.init) ?? 500
    let graceMs = value(after: "--grace-ms").flatMap(UInt32.init) ?? 800
    runRestoreWatcher(pid: pid, pollMs: pollMs, graceMs: graceMs)
case "snapshot":
    let snapshot = service.snapshot(promptForPermissions: args.contains("--prompt-permissions"))
    if args.contains("--json") {
        do {
            print(try SnapshotEncoding.json(snapshot))
        } catch {
            fputs("roadied: failed to encode snapshot: \(error)\n", stderr)
            exit(1)
        }
    } else {
        print(TextFormatter.displays(snapshot.displays))
        print("")
        print(TextFormatter.windows(snapshot.windows))
    }
case "permissions":
    let local = AXPermissions.snapshot(prompt: args.contains("--prompt"))
    print(TextFormatter.permissions(
        daemon: DaemonStatusReading.read(),
        localAccessibility: local.accessibilityTrusted,
        localScreenRecording: CGPreflightScreenCaptureAccess()
    ))
case "help", "-h", "--help":
    printUsage()
    exit(0)
case "--version", "version":
    print("roadied \(RoadieVersion.current)")
    exit(0)
default:
    printUsage()
    exit(args.isEmpty ? 0 : 64)
}

func value(after flag: String) -> String? {
    guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else {
        return nil
    }
    return args[index + 1]
}

func resolvedArguments() -> [String] {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.isEmpty && Bundle.main.bundleIdentifier == "com.roadie.roadied" {
        return ["run", "--yes"]
    }
    return arguments
}

private final class MaintenanceTimerTarget: NSObject {
    private let maintainer: LayoutMaintainer
    private let maxTicks: Int?
    private let shouldTick: () -> Bool
    private let onTick: (MaintenanceTick) -> Void
    private var tickCount = 0

    init(
        maintainer: LayoutMaintainer,
        maxTicks: Int?,
        shouldTick: @escaping () -> Bool = { true },
        onTick: @escaping (MaintenanceTick) -> Void
    ) {
        self.maintainer = maintainer
        self.maxTicks = maxTicks
        self.shouldTick = shouldTick
        self.onTick = onTick
    }

    /// `countsTowardLimit` : seuls les ticks du timer comptent pour `--ticks` ; les ticks live
    /// (événements AX) et la réconciliation de réveil n'avancent pas le compteur.
    @discardableResult
    @MainActor func performTick(_ timer: Timer, countsTowardLimit: Bool = true) -> MaintenanceTick {
        let tick: MaintenanceTick
        if shouldTick() {
            tick = maintainer.tick()
            onTick(tick)
        } else {
            tick = MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
        }
        guard countsTowardLimit else { return tick }
        tickCount += 1
        if let maxTicks, tickCount >= maxTicks {
            timer.invalidate()
            NSApplication.shared.terminate(nil)
        }
        return tick
    }

    @MainActor @objc func tick(_ timer: Timer) {
        performTick(timer)
    }
}

/// Cycle de vie de la restauration dans le daemon (SPEC-016 R9) : reprise d'un arrêt
/// incomplet au démarrage, watcher de crash dans sa propre session, snapshot à chaque
/// changement de stage active et toutes les 30 s, restauration des fenêtres masquées à l'arrêt.
@MainActor
final class RestoreSafetyRuntimeController {
    private static let checkInterval: TimeInterval = 2
    private static let snapshotInterval: TimeInterval = 30

    private let service: RestoreSafetyService
    private let stageStore: StageStore
    private let pid: Int32
    private var lastStageSignature: [String] = []
    private var lastSnapshotAt: Date = .distantPast

    init(service: RestoreSafetyService, stageStore: StageStore, pid: Int32) {
        self.service = service
        self.stageStore = stageStore
        self.pid = pid
    }

    func start() {
        do {
            if let recovery = try service.startRun(pid: pid) {
                print("restore-recovery attempted=\(recovery.attempted) applied=\(recovery.applied) failed=\(recovery.failed)")
                fflush(stdout)
            }
        } catch {
            fputs("roadied: restore safety startup failed: \(error)\n", stderr)
        }
        writeSnapshot()
        startWatcher()
        ShutdownRegistry.register { [self] in
            writeSnapshot()
            let result = service.finishRun(pid: pid)
            print("restore-shutdown unhidden=\(result.applied) failed=\(result.failed)")
            fflush(stdout)
        }
        // Comparer la stage active à chaque tick évite de dépendre des commandes de stage.
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.snapshotIfNeeded() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func snapshotIfNeeded() {
        let changed = stageSignature() != lastStageSignature
        guard changed || Date().timeIntervalSince(lastSnapshotAt) >= Self.snapshotInterval else { return }
        writeSnapshot()
    }

    /// Une entrée par scope : écran, desktop et stage active. O(s), s = nombre de scopes.
    private func stageSignature() -> [String] {
        stageStore.state().scopes.map { "\($0.displayID.rawValue)/\($0.desktopID.rawValue)/\($0.activeStageID.rawValue)" }
    }

    private func writeSnapshot() {
        lastStageSignature = stageSignature()
        lastSnapshotAt = Date()
        do {
            _ = try service.writeSnapshot()
        } catch {
            fputs("roadied: restore snapshot failed: \(error)\n", stderr)
        }
    }

    /// Relance notre propre binaire avec des arguments fixes et le pid courant (provenance
    /// noyau) : aucune injection possible. `POSIX_SPAWN_SETSID` place le watcher dans sa
    /// propre session, pour qu'il survive à la fermeture de tmux ou au bootout launchd qui
    /// tuent le groupe du daemon. Les signaux ignorés par le daemon retrouvent leur action
    /// par défaut, et aucun descripteur (dont le verrou d'instance) n'est hérité hors 1 et 2.
    private func startWatcher() {
        guard let executable = Bundle.main.executableURL?.path else { return }
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF))
        var defaultSignals = sigset_t()
        sigemptyset(&defaultSignals)
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            sigaddset(&defaultSignals, signalNumber)
        }
        posix_spawnattr_setsigdefault(&attributes, &defaultSignals)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addinherit_np(&actions, 1)
        posix_spawn_file_actions_addinherit_np(&actions, 2)

        let arguments = [executable, "restore-watch", "--pid", String(pid)]
        var cArguments: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { cArguments.forEach { free($0) } }
        var child: pid_t = 0
        let status = posix_spawn(&child, executable, &actions, &attributes, &cArguments, environ)
        if status != 0 {
            fputs("roadied: restore watcher failed to start: \(String(cString: strerror(status)))\n", stderr)
        }
    }
}

/// Surveille le daemon `pid` (tiler ou `run`) ; s'il disparaît sans arrêt propre, ramène
/// les fenêtres masquées à leur dernière frame visible.
@MainActor
private func runRestoreWatcher(pid: Int32, pollMs: UInt32, graceMs: UInt32) -> Never {
    let restore = RestoreSafetyService(service: service)
    while kill(pid, 0) == 0 || errno == EPERM {
        usleep(max(50, pollMs) * 1000)
    }
    usleep(graceMs * 1000)
    guard restore.shouldRestoreAfterProcessExit(pid: pid) else {
        exit(0)
    }
    EventLog().append(RoadieEventEnvelope(
        id: "restore_\(UUID().uuidString)",
        type: "restore.crash_detected",
        scope: .restore,
        subject: AutomationSubject(kind: "process", id: String(pid)),
        cause: .system,
        payload: [:]
    ))
    do {
        // nil : une nouvelle instance a déjà repris le marqueur (et restauré au démarrage).
        guard let result = try restore.recoverAfterProcessExit(pid: pid) else { exit(0) }
        EventLog().append(RoadieEventEnvelope(
            id: "restore_\(UUID().uuidString)",
            type: "restore.crash_completed",
            scope: .restore,
            subject: AutomationSubject(kind: "process", id: String(pid)),
            cause: .system,
            payload: [
                "attempted": .int(result.attempted),
                "applied": .int(result.applied),
                "failed": .int(result.failed),
                "missing": .int(result.missing)
            ]
        ))
        exit(result.failed == 0 ? 0 : 1)
    } catch {
        fputs("roadied: restore watcher apply failed: \(error)\n", stderr)
        exit(1)
    }
}
