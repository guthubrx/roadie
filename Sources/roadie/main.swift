import Foundation
import RoadieCore
import RoadieDaemon

let args = Array(CommandLine.arguments.dropFirst())
let service = SnapshotService()

func printUsage() {
    print("""
    usage:
      roadie windows list [--json]
      roadie display list [--json]
      roadie state dump [--json]
      roadie layout plan [--json]
      roadie layout apply [--yes] [--json]
      roadie config show
      roadie permissions [--prompt]
    """)
}

func printJSON(_ snapshot: DaemonSnapshot) {
    do {
        print(try SnapshotEncoding.json(snapshot))
    } catch {
        fputs("roadie: failed to encode snapshot: \(error)\n", stderr)
        exit(1)
    }
}

switch args.first {
case "windows":
    guard args.dropFirst().first == "list" else {
        printUsage()
        exit(64)
    }
    let snapshot = service.snapshot()
    if args.contains("--json") {
        printJSON(snapshot)
    } else {
        print(TextFormatter.windows(snapshot.windows))
    }
case "display":
    guard args.dropFirst().first == "list" else {
        printUsage()
        exit(64)
    }
    let snapshot = service.snapshot()
    if args.contains("--json") {
        printJSON(snapshot)
    } else {
        print(TextFormatter.displays(snapshot.displays))
    }
case "state":
    guard args.dropFirst().first == "dump" else {
        printUsage()
        exit(64)
    }
    printJSON(service.snapshot())
case "layout":
    let verb = args.dropFirst().first
    let snapshot = service.snapshot()
    let plan = service.applyPlan(from: snapshot)
    switch verb {
    case "plan":
        if args.contains("--json") {
            do {
                print(try SnapshotEncoding.json(plan))
            } catch {
                fputs("roadie: failed to encode layout plan: \(error)\n", stderr)
                exit(1)
            }
        } else {
            print(TextFormatter.applyPlan(plan))
        }
    case "apply":
        guard args.contains("--yes") else {
            fputs("roadie: refusing to move windows without --yes\n", stderr)
            print(TextFormatter.applyPlan(plan))
            exit(2)
        }
        let result = service.apply(plan)
        if args.contains("--json") {
            do {
                print(try SnapshotEncoding.json(result))
            } catch {
                fputs("roadie: failed to encode apply result: \(error)\n", stderr)
                exit(1)
            }
        } else {
            print(TextFormatter.applyResult(result))
        }
    default:
        printUsage()
        exit(64)
    }
case "permissions":
    let snapshot = service.snapshot(promptForPermissions: args.contains("--prompt"))
    print(TextFormatter.permissions(snapshot.permissions))
case "config":
    guard args.dropFirst().first == "show" else {
        printUsage()
        exit(64)
    }
    do {
        let config = try RoadieConfigLoader.load()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(config), as: UTF8.self))
    } catch {
        fputs("roadie: config load failed: \(error)\n", stderr)
        exit(1)
    }
default:
    printUsage()
    exit(args.isEmpty ? 0 : 64)
}
