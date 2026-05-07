import Foundation
import RoadieDaemon

let args = Array(CommandLine.arguments.dropFirst())
let service = SnapshotService()

func printUsage() {
    print("""
    usage:
      roadied run --yes [--interval-ms N] [--ticks N]
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
    let maintainer = LayoutMaintainer(intervalSeconds: max(100, intervalMs) / 1000)
    var reportedAccessibilityDenied = false
    maintainer.run(maxTicks: ticks) { tick in
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
