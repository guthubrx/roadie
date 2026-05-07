import Foundation
import AppKit
import RoadieDaemon

let args = Array(CommandLine.arguments.dropFirst())
let service = SnapshotService()
var railController: RailController?

func printUsage() {
    print("""
    usage:
      roadied run --yes [--interval-ms N] [--ticks N] [--no-rail]
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
    let maintainer = LayoutMaintainer(intervalSeconds: interval)
    var reportedAccessibilityDenied = false
    if shouldStartRail {
        railController = RailController()
        railController?.start()
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
    NSApplication.shared.run()
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
