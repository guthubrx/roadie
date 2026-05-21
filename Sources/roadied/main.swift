import Foundation
import AppKit
import Darwin
import RoadieAX
import RoadieCore
import RoadieDaemon

let args = resolvedArguments()
let service = SnapshotService()
var railController: RailController?
var borderController: BorderController?
var focusFollowsMouseController: FocusFollowsMouseController?
var titlebarContextMenuController: TitlebarContextMenuController?
var targetModeRuntimeController: TargetModeRuntimeController?
var displayChangeObserver: NSObjectProtocol?
var pendingDisplayHeal: Task<Void, Never>?
var displaySettlingUntil: Date = .distantPast

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

switch args.first {
case "run":
    guard args.contains("--yes") else {
        fputs("roadied: refusing to maintain layout without --yes\n", stderr)
        exit(2)
    }
    let intervalMs = value(after: "--interval-ms").flatMap(Double.init) ?? 500
    let ticks = value(after: "--ticks").flatMap(Int.init)
    let displaySettleSeconds = max(0.5, (value(after: "--display-settle-ms").flatMap(Double.init) ?? 1500) / 1000)
    let shouldStartTiler = !args.contains("--no-tiler")
    let shouldStartRail = !args.contains("--no-rail")
    let shouldStartBorder = !args.contains("--no-border")
    let shouldStartFocusMouse = !args.contains("--no-focus-mouse")
    let shouldStartTitlebarMenu = !args.contains("--no-titlebar-menu")
    let shouldStartTargetMode = !args.contains("--no-target-mode")
    let shouldStartRestoreSafety = !args.contains("--no-restore-safety")
    let interval = max(100, intervalMs) / 1000
    let maintainer = LayoutMaintainer(intervalSeconds: interval)
    let restoreSafety = RestoreSafetyService(service: service)
    let pid = ProcessInfo.processInfo.processIdentifier
    var reportedAccessibilityDenied = false
    var restoreSafetyController: RestoreSafetyRuntimeController?
    if shouldStartRestoreSafety {
        restoreSafetyController = RestoreSafetyRuntimeController(service: restoreSafety, pid: pid)
        restoreSafetyController?.start()
    }
    if shouldStartRail {
        railController = RailController()
        railController?.start()
    }
    if shouldStartBorder {
        borderController = BorderController()
        borderController?.start()
    }
    if shouldStartFocusMouse {
        focusFollowsMouseController = FocusFollowsMouseController()
        focusFollowsMouseController?.start()
    }
    if shouldStartTitlebarMenu {
        titlebarContextMenuController = TitlebarContextMenuController()
        titlebarContextMenuController?.start()
    }
    if shouldStartTargetMode {
        targetModeRuntimeController = TargetModeRuntimeController(service: service)
        targetModeRuntimeController?.start()
    }
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

    if shouldStartTiler {
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

        // Live re-evaluation : declenche un tick() supplementaire des qu'AX nous notifie d'un
        // changement de fenetre, sans attendre le prochain polling tick. Les changements de
        // focus (AltTab/clic externe) ont une voie rapide ; les autres evenements restent
        // coalesces plus largement pour eviter les rafales AX.
        let liveEvents = EventLog()
        var pendingLiveTick: DispatchWorkItem?
        var lastLiveTickAt: Date = .distantPast
        let liveCoalesceMs = value(after: "--live-coalesce-ms").flatMap(Double.init) ?? 80
        let fastLiveCoalesceMs = value(after: "--fast-live-coalesce-ms").flatMap(Double.init) ?? 15
        let fastNotifications: Set<String> = [
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
        if !args.contains("--no-live-events") {
            liveObserver.start()
        }
    } else {
        // Sans tiler, on garde le maintainer instancie pour ne pas casser les references
        // (les autres controleurs peuvent dependre indirectement de SnapshotService partage)
        // mais on ne demarre ni timer ni AX observer.
        _ = maintainer
        _ = restoreSafety
    }
    NSApplication.shared.run()
case "tiler":
    guard args.contains("--yes") else {
        fputs("roadied tiler: refusing to maintain layout without --yes\n", stderr)
        exit(2)
    }
    let intervalMs = value(after: "--interval-ms").flatMap(Double.init) ?? 500
    let ticks = value(after: "--ticks").flatMap(Int.init)
    let interval = max(100, intervalMs) / 1000
    runComponent("tiler") {
        let maintainer = LayoutMaintainer(intervalSeconds: interval)
        var reportedAccessibilityDenied = false
        let target = MaintenanceTimerTarget(
            maintainer: maintainer,
            maxTicks: ticks
        ) { tick in
            if tick.accessibilityDenied {
                if !reportedAccessibilityDenied {
                    fputs("roadied tiler: accessibilityTrusted=false\n", stderr)
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
    }
case "rail":
    runComponent("rail") {
        railController = RailController()
        railController?.start()
    }
case "border":
    runComponent("border") {
        borderController = BorderController()
        borderController?.start()
    }
case "focus-mouse":
    runComponent("focus-mouse") {
        focusFollowsMouseController = FocusFollowsMouseController()
        focusFollowsMouseController?.start()
    }
case "titlebar-menu":
    runComponent("titlebar-menu") {
        titlebarContextMenuController = TitlebarContextMenuController()
        titlebarContextMenuController?.start()
    }
case "target-mode":
    runComponent("target-mode") {
        targetModeRuntimeController = TargetModeRuntimeController(service: service)
        targetModeRuntimeController?.start()
    }
case "restore-safety":
    runComponent("restore-safety") {
        let safetyService = RestoreSafetyService(service: service)
        let pid = ProcessInfo.processInfo.processIdentifier
        let controller = RestoreSafetyRuntimeController(service: safetyService, pid: pid)
        controller.start()
    }
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
