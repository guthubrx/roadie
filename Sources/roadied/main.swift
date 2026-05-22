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
    "rail", "border", "focus-mouse", "titlebar-menu", "target-mode", "restore-safety"
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
// Retenu globalement : la sous-commande `tiler` (runComponent) retourne avant
// NSApplication.run(), donc une reference locale serait desallouee.
var tilerLiveObserver: AXWindowEventObserver?

func printUsage() {
    print("""
    usage:
      roadied run --yes [--interval-ms N] [--ticks N]
                       [--no-tiler] [--no-rail] [--no-border]
                       [--no-focus-mouse] [--no-titlebar-menu]
                       [--no-target-mode] [--no-restore-safety]
      roadied tiler --yes [--interval-ms N] [--ticks N]
      roadied rail
      roadied border
      roadied focus-mouse
      roadied titlebar-menu
      roadied target-mode
      roadied restore-safety
      roadied restore-watch --pid PID [--poll-ms N] [--grace-ms N]
      roadied snapshot [--json] [--prompt-permissions]
      roadied permissions [--prompt]
    """)
}

/// Lance NSApplication.run() apres avoir installe les handlers SIGTERM/SIGINT
/// qui releasent le lock du composant avant exit. Utilise par les sous-commandes
/// de composant unique (rail, border, ...).
@MainActor
private func runComponent(_ name: String, start: () -> Void) -> Never {
    let lock = ComponentLockFile(component: name)
    do {
        try lock.acquire()
    } catch ComponentLockError.alreadyRunning(let pid) {
        fputs("roadied \(name): already running (pid \(pid))\n", stderr)
        exit(1)
    } catch {
        fputs("roadied \(name): failed to acquire lock: \(error)\n", stderr)
        exit(1)
    }

    // DispatchSourceSignal supporte une closure (contrairement a signal(3) qui exige
    // une fonction @convention(c) sans capture). On reset le handler par defaut via
    // signal(sig, SIG_IGN) sinon le process se termine sur SIGTERM avant que la source
    // ne tire.
    let signals: [Int32] = [SIGTERM, SIGINT, SIGHUP]
    var sources: [DispatchSourceSignal] = []
    for sig in signals {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler {
            lock.release()
            exit(0)
        }
        source.resume()
        sources.append(source)
    }
    // Garde les sources vivantes pour toute la duree du process.
    withExtendedLifetime(sources) {}

    NSApplication.shared.setActivationPolicy(.accessory)
    start()
    NSApplication.shared.run()
    lock.release()
    exit(0)
}

// MARK: - Fonctions de démarrage des composants (source unique, SPEC-012)
//
// Chaque composant a UNE seule fonction de démarrage, appelée à la fois par le mode
// monolithique (`run`) et par sa sous-commande modulaire. Cela élimine la duplication
// qui causait des divergences de comportement entre les deux modes (SPEC-011).

@MainActor
func startRailComponent() {
    railController = RailController()
    railController?.start()
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

@MainActor
func startRestoreSafetyComponent() {
    let safetyService = RestoreSafetyService(service: service)
    let pid = ProcessInfo.processInfo.processIdentifier
    let controller = RestoreSafetyRuntimeController(service: safetyService, pid: pid)
    controller.start()
}

/// Au changement de paramètres d'écran (display branché/débranché), planifie un
/// "parking heal" : `DaemonHealthService.heal()` migre les fenêtres des écrans
/// disparus vers un écran présent. Sans cet observer, les fenêtres d'un écran
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
                let report = DaemonHealthService().heal()
                print("display-change-heal parking=\(report.parking.kind.rawValue)/\(report.parking.reason.rawValue) state=\(report.state.repaired) layout=\(report.layout.attempted) failed=\(report.failed)")
                fflush(stdout)
            }
        }
    }
}

/// Démarre le tiler : observer d'écran + timer de polling + voie rapide AX.
/// La voie rapide re-tile en ~15-80ms dès qu'une fenêtre apparaît/change, sans
/// attendre le prochain tick de polling.
@MainActor
func startTilerComponent(interval: Double, ticks: Int?, displaySettleSeconds: Double, enableLiveEvents: Bool) {
    installDisplayChangeObserver(displaySettleSeconds: displaySettleSeconds)

    let maintainer = LayoutMaintainer(intervalSeconds: interval)
    var reportedAccessibilityDenied = false
    let target = MaintenanceTimerTarget(
        maintainer: maintainer,
        maxTicks: ticks,
        shouldTick: { Date() >= displaySettlingUntil }
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
            let tick = target.performTick(timer)
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

    // Démarrage des composants via les fonctions uniques partagées avec le mode modulaire
    // (SPEC-012). Ordre historique préservé. Chaque composant est actif par défaut,
    // désactivable via son flag --no-*.
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
    runComponent("tiler") {
        startTilerComponent(
            interval: interval,
            ticks: ticks,
            displaySettleSeconds: displaySettleSeconds,
            enableLiveEvents: !args.contains("--no-live-events")
        )
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
    runComponent("restore-safety") { startRestoreSafetyComponent() }
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
    let snapshot = service.snapshot(promptForPermissions: args.contains("--prompt"))
    print(TextFormatter.permissions(snapshot.permissions))
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

    @discardableResult
    @MainActor func performTick(_ timer: Timer) -> MaintenanceTick {
        let tick: MaintenanceTick
        if shouldTick() {
            tick = maintainer.tick()
            onTick(tick)
        } else {
            tick = MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0)
        }
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

private final class RestoreSafetyRuntimeController: @unchecked Sendable {
    private let service: RestoreSafetyService
    private let pid: Int32
    private var terminationObserver: NSObjectProtocol?
    private var signalSources: [DispatchSourceSignal] = []
    private var didMarkCleanExit = false

    init(service: RestoreSafetyService, pid: Int32) {
        self.service = service
        self.pid = pid
    }

    func start() {
        do {
            _ = try service.writeSnapshot()
            _ = try service.markRunStarted(pid: pid)
            startWatcher()
        } catch {
            fputs("roadied: restore safety startup failed: \(error)\n", stderr)
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.markCleanExit()
        }
        installSignalHandler(SIGTERM)
        installSignalHandler(SIGINT)
    }

    private func installSignalHandler(_ signalNumber: Int32) {
        signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
        source.setEventHandler { [weak self] in
            self?.markCleanExit()
            exit(0)
        }
        signalSources.append(source)
        source.resume()
    }

    private func startWatcher() {
        // Securite : on relance notre propre binaire (Bundle.main.executableURL) avec
        // des arguments hard-codes et le pid courant (provenance noyau, non user-controlled).
        // Aucune injection possible.
        guard let executable = Bundle.main.executableURL else { return }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["restore-watch", "--pid", String(pid)]
        do {
            try process.run()
        } catch {
            fputs("roadied: restore watcher failed to start: \(error)\n", stderr)
        }
    }

    private func markCleanExit() {
        guard !didMarkCleanExit else { return }
        didMarkCleanExit = true
        do {
            _ = try service.writeSnapshot()
            _ = try service.markCleanExit(pid: pid)
        } catch {
            fputs("roadied: restore safety clean exit failed: \(error)\n", stderr)
        }
    }
}

private func runRestoreWatcher(pid: Int32, pollMs: UInt32, graceMs: UInt32) -> Never {
    let service = RestoreSafetyService()
    while kill(pid, 0) == 0 {
        usleep(max(50, pollMs) * 1000)
    }
    usleep(graceMs * 1000)
    guard service.shouldRestoreAfterProcessExit(pid: pid) else {
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
        let result = try service.apply()
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
