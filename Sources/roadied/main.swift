import Foundation
import AppKit
import Darwin
import RoadieDaemon
import RoadieCore

let args = resolvedArguments()
let service = SnapshotService()
var railController: RailController?
var borderController: BorderController?
var focusFollowsMouseController: FocusFollowsMouseController?
var focusStageActivationObserver: FocusStageActivationObserver?
var displayChangeObserver: NSObjectProtocol?

func printUsage() {
    print("""
    usage:
      roadied run --yes [--interval-ms N] [--ticks N] [--no-rail]
      roadied control-center
      roadied crash-watcher --pid PID
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
    let interval = max(100, intervalMs) / 1000
    let config = (try? RoadieConfigLoader.load()) ?? RoadieConfig()
    let restoreSafety = RestoreSafetyService(path: config.restoreSafety.snapshotPath)
    let maintainer = LayoutMaintainer(
        intervalSeconds: interval,
        restoreSafety: config.restoreSafety.enabled ? restoreSafety : nil,
        config: config
    )
    var reportedAccessibilityDenied = false
    let restoreOnExit = RestoreOnExitHandler(config: config, restoreSafety: restoreSafety)
    if shouldStartRail {
        railController = RailController()
        railController?.start()
    }
    borderController = BorderController()
    borderController?.start()
    focusFollowsMouseController = FocusFollowsMouseController()
    focusFollowsMouseController?.start()
    focusStageActivationObserver = FocusStageActivationObserver(maintainer: maintainer)
    focusStageActivationObserver?.start()
    displayChangeObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification,
        object: nil,
        queue: .main
    ) { _ in
        let report = DaemonHealthService().heal()
        print("display-change-heal state=\(report.state.repaired) layout=\(report.layout.attempted) failed=\(report.failed)")
        fflush(stdout)
    }

    let terminateObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification,
        object: nil,
        queue: .main
    ) { _ in
        restoreOnExit.run()
    }

    let target = MaintenanceTimerTarget(maintainer: maintainer, maxTicks: ticks, onFinish: restoreOnExit.run) { tick in
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
    NSApplication.shared.run()
    NotificationCenter.default.removeObserver(terminateObserver)
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
case "control-center":
    fputs("roadied: control center is disabled in this build\n", stderr)
    exit(64)
case "crash-watcher":
    guard let rawPID = value(after: "--pid"), let pid = Int32(rawPID) else {
        fputs("roadied: crash-watcher requires --pid PID\n", stderr)
        exit(64)
    }
    let config = (try? RoadieConfigLoader.load()) ?? RoadieConfig()
    guard config.restoreSafety.enabled, config.restoreSafety.crashWatcher else {
        print("restore watcher: disabled")
        exit(0)
    }
    let result = RestoreSafetyService(path: config.restoreSafety.snapshotPath).restoreIfDaemonMissing(pid: pid) { candidate in
        Darwin.kill(candidate, 0) == 0 || errno == EPERM
    }
    print(result.message)
    exit(result.failed == 0 ? 0 : 1)
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
    private let onFinish: () -> Void
    private var tickCount = 0

    init(maintainer: LayoutMaintainer, maxTicks: Int?, onFinish: @escaping () -> Void, onTick: @escaping (MaintenanceTick) -> Void) {
        self.maintainer = maintainer
        self.maxTicks = maxTicks
        self.onFinish = onFinish
        self.onTick = onTick
    }

    @MainActor @objc func tick(_ timer: Timer) {
        onTick(maintainer.tick())
        tickCount += 1
        if let maxTicks, tickCount >= maxTicks {
            timer.invalidate()
            onFinish()
            NSApplication.shared.terminate(nil)
        }
    }
}

private final class RestoreOnExitHandler: @unchecked Sendable {
    private let config: RoadieConfig
    private let restoreSafety: RestoreSafetyService
    private let lock = NSLock()
    private var restored = false

    init(config: RoadieConfig, restoreSafety: RestoreSafetyService) {
        self.config = config
        self.restoreSafety = restoreSafety
    }

    func run() {
        lock.lock()
        defer { lock.unlock() }
        guard config.restoreSafety.enabled, config.restoreSafety.restoreOnExit, !restored else { return }
        restored = true
        _ = restoreSafety.save(restoreSafety.capture())
        let result = restoreSafety.restoreFromDisk()
        print("restore-on-exit restored=\(result.restored) failed=\(result.failed)")
        fflush(stdout)
    }
}
