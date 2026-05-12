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
var pinPopoverController: PinPopoverController?
var displayChangeObserver: NSObjectProtocol?

func printUsage() {
    print("""
    usage:
      roadied run --yes [--interval-ms N] [--ticks N] [--no-rail] [--no-restore-safety]
      roadied restore-watch --pid PID [--poll-ms N] [--grace-ms N]
      roadied snapshot [--json] [--prompt-permissions]
      roadied permissions [--prompt]
    """)
}

switch args.first {
case "run":
    guard args.contains("--yes") else {
        fputs("roadied: refusing to maintain layout without --yes\n", stderr)
        exit(2)
    }
    let intervalMs = value(after: "--interval-ms").flatMap(Double.init) ?? 500
    let ticks = value(after: "--ticks").flatMap(Int.init)
    let shouldStartRail = !args.contains("--no-rail")
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
    borderController = BorderController()
    borderController?.start()
    focusFollowsMouseController = FocusFollowsMouseController()
    focusFollowsMouseController?.start()
    titlebarContextMenuController = TitlebarContextMenuController()
    titlebarContextMenuController?.start()
    pinPopoverController = PinPopoverController()
    pinPopoverController?.start()
    displayChangeObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification,
        object: nil,
        queue: .main
    ) { _ in
        let report = DaemonHealthService().heal()
        print("display-change-heal state=\(report.state.repaired) layout=\(report.layout.attempted) failed=\(report.failed)")
        fflush(stdout)
    }

    let target = MaintenanceTimerTarget(maintainer: maintainer, maxTicks: ticks) { tick in
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
    // changement de fenetre, sans attendre le prochain polling tick. Coalesce les rafales
    // (250ms) et evite de doubler avec le polling regulier (skip si tick recent).
    var pendingLiveTick: DispatchWorkItem?
    var lastTickAt: Date = .distantPast
    let liveCoalesceMs = value(after: "--live-coalesce-ms").flatMap(Double.init) ?? 250
    let liveObserver = AXWindowEventObserver {
        // Si on a tick il y a moins de 200ms (polling), on ne refait pas.
        if Date().timeIntervalSince(lastTickAt) < 0.2 { return }
        pendingLiveTick?.cancel()
        let item = DispatchWorkItem {
            pendingLiveTick = nil
            lastTickAt = Date()
            target.tick(timer)
        }
        pendingLiveTick = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(liveCoalesceMs)), execute: item)
    }
    if !args.contains("--no-live-events") {
        liveObserver.start()
    }
    NSApplication.shared.run()
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
    private let onTick: (MaintenanceTick) -> Void
    private var tickCount = 0

    init(maintainer: LayoutMaintainer, maxTicks: Int?, onTick: @escaping (MaintenanceTick) -> Void) {
        self.maintainer = maintainer
        self.maxTicks = maxTicks
        self.onTick = onTick
    }

    @MainActor @objc func tick(_ timer: Timer) {
        onTick(maintainer.tick())
        tickCount += 1
        if let maxTicks, tickCount >= maxTicks {
            timer.invalidate()
            NSApplication.shared.terminate(nil)
        }
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
