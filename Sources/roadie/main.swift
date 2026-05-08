import Foundation
import RoadieCore
import RoadieDaemon

let args = Array(CommandLine.arguments.dropFirst())
let service = SnapshotService()

func printUsage() {
    print("""
    usage:
      roadie windows list [--json]
      roadie display list|current [--json]
      roadie display focus N
      roadie state dump|audit|heal [--json]
      roadie layout plan [--json]
      roadie layout apply [--yes] [--json]
      roadie config show|validate
      roadie rail status
      roadie doctor
      roadie self-test
      roadie events tail [N]
      roadie permissions [--prompt]
      roadie focus status
      roadie focus|move|warp|wrap|resize left|right|up|down
      roadie mode bsp|masterStack|float
      roadie window display N
      roadie window desktop N [--follow]
      roadie window reset
      roadie desktop list|current
      roadie desktop focus N|prev|next|last|back
      roadie desktop label N NAME
      roadie stage list
      roadie stage create|delete N
      roadie stage rename N NAME
      roadie stage reorder N POSITION
      roadie stage switch|assign N
      roadie stage mode bsp|masterStack|float
      roadie stage prev|next
      roadie balance
      roadie daemon health|heal [--json]
      roadie daemon restart
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
    let verb = args.dropFirst().first
    guard verb == "list" || verb == "current" || verb == "focus" else {
        printUsage()
        exit(64)
    }
    if verb == "focus" {
        guard let rawIndex = args.dropFirst(2).first, let index = Int(rawIndex), index > 0 else {
            fputs("roadie: display focus requires a positive index\n", stderr)
            exit(64)
        }
        let result = DisplayCommandService(service: service).focus(index: index)
        print(result.message)
        exit(result.changed ? 0 : 1)
    }
    let snapshot = service.snapshot()
    if args.contains("--json") {
        printJSON(snapshot)
    } else if verb == "current" {
        print(TextFormatter.currentDisplay(snapshot, state: StageStore().state()))
    } else {
        print(TextFormatter.displays(snapshot.displays, state: StageStore().state()))
    }
case "state":
    let verb = args.dropFirst().first
    guard verb == "dump" || verb == "audit" || verb == "heal" else {
        printUsage()
        exit(64)
    }
    if verb == "dump" {
        printJSON(service.snapshot())
    } else if verb == "audit" {
        let report = StateAuditService(service: service).run()
        if args.contains("--json") {
            do {
                print(try SnapshotEncoding.json(report))
            } catch {
                fputs("roadie: failed to encode state audit: \(error)\n", stderr)
                exit(1)
            }
        } else {
            print(TextFormatter.stateAudit(report))
        }
        exit(report.failed ? 1 : 0)
    } else {
        let report = StateAuditService(service: service).heal()
        if args.contains("--json") {
            do {
                print(try SnapshotEncoding.json(report))
            } catch {
                fputs("roadie: failed to encode state heal: \(error)\n", stderr)
                exit(1)
            }
        } else {
            print(TextFormatter.stateHeal(report))
        }
        exit(report.audit.failed ? 1 : 0)
    }
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
case "doctor":
    let snapshot = service.snapshot()
    let plan = service.applyPlan(from: snapshot)
    print(TextFormatter.doctor(snapshot: snapshot, plan: plan, persistentState: StageStore().state()))
case "self-test":
    let report = SelfTestService(service: service).run()
    print(TextFormatter.selfTest(report))
    exit(report.failed ? 1 : 0)
case "events":
    guard args.dropFirst().first == "tail" else {
        printUsage()
        exit(64)
    }
    let limit = args.dropFirst(2).first.flatMap(Int.init) ?? 20
    print(EventLog().tail(limit: limit).joined(separator: "\n"))
case "config":
    let verb = args.dropFirst().first
    guard verb == "show" || verb == "validate" else {
        printUsage()
        exit(64)
    }
    if verb == "validate" {
        let report = RoadieConfigLoader.validate()
        print(TextFormatter.configValidation(report))
        exit(report.hasErrors ? 1 : 0)
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
case "rail":
    guard args.dropFirst().first == "status" else {
        printUsage()
        exit(64)
    }
    print(RailSettings.load().statusLines.joined(separator: "\n"))
case "focus":
    if args.dropFirst().first == "status" {
        print(TextFormatter.focusStatus(service.snapshot()))
        exit(0)
    } else {
        runDirectionalCommand(args.dropFirst().first, verb: "focus") {
            WindowCommandService(service: service).focus($0)
        }
    }
case "move":
    runDirectionalCommand(args.dropFirst().first, verb: "move") {
        WindowCommandService(service: service).move($0)
    }
case "warp", "wrap":
    runDirectionalCommand(args.dropFirst().first, verb: "warp") {
        WindowCommandService(service: service).warp($0)
    }
case "resize":
    runDirectionalCommand(args.dropFirst().first, verb: "resize") {
        WindowCommandService(service: service).resize($0)
    }
case "mode":
    runModeCommand(args.dropFirst().first)
case "window":
    runWindowCommand(Array(args.dropFirst()))
case "desktop":
    runDesktopCommand(Array(args.dropFirst()))
case "stage":
    runStageCommand(Array(args.dropFirst()))
case "balance":
    let snapshot = service.snapshot()
    service.removeLayoutIntents(in: snapshot)
    let result = service.apply(service.applyPlan(from: service.snapshot()))
    print(TextFormatter.applyResult(result))
case "daemon":
    if args.dropFirst().first == "health" {
        let report = DaemonHealthService(service: service).run()
        if args.contains("--json") {
            do {
                print(try SnapshotEncoding.json(report))
            } catch {
                fputs("roadie: failed to encode daemon health: \(error)\n", stderr)
                exit(1)
            }
        } else {
            print(TextFormatter.daemonHealth(report))
        }
        exit(report.failed ? 1 : 0)
    } else if args.dropFirst().first == "heal" {
        let report = DaemonHealthService(service: service).heal()
        if args.contains("--json") {
            do {
                print(try SnapshotEncoding.json(report))
            } catch {
                fputs("roadie: failed to encode daemon heal: \(error)\n", stderr)
                exit(1)
            }
        } else {
            print(TextFormatter.daemonHeal(report))
        }
        exit(report.failed ? 1 : 0)
    } else if args.dropFirst().first == "restart" {
        runShell("/Users/moi/Nextcloud/10.Scripts/39.roadie/scripts/start", [])
    } else {
        printUsage()
        exit(64)
    }
case "toggle":
    let subject = args.dropFirst().first ?? ""
    switch subject {
    case "floating", "fullscreen", "native-fullscreen":
        print("roadie: \(args.joined(separator: " ")) is not implemented in this build")
    default:
        printUsage()
        exit(64)
    }
default:
    printUsage()
    exit(args.isEmpty ? 0 : 64)
}

@MainActor
func runDirectionalCommand(
    _ rawDirection: String?,
    verb: String,
    action: (Direction) -> WindowCommandResult
) {
    guard let rawDirection, let direction = Direction(rawValue: rawDirection) else {
        fputs("roadie: \(verb) requires left|right|up|down\n", stderr)
        exit(64)
    }
    let result = action(direction)
    print(result.message)
    exit(result.changed ? 0 : 1)
}

@MainActor
func runWindowCommand(_ args: [String]) {
    switch args.first {
    case "display":
        guard args.indices.contains(1), let index = Int(args[1]) else {
            fputs("roadie: window display requires an index\n", stderr)
            exit(64)
        }
        let result = WindowCommandService(service: service).sendToDisplay(index)
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "reset":
        let result = WindowCommandService(service: service).reset()
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "desktop":
        guard args.indices.contains(1), let id = Int(args[1]), id > 0 else {
            fputs("roadie: window desktop requires a positive id\n", stderr)
            exit(64)
        }
        let result = DesktopCommandService(service: service).assignActiveWindow(
            to: DesktopID(rawValue: id),
            follow: args.contains("--follow")
        )
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "swap":
        runDirectionalCommand(args.dropFirst().first, verb: "window swap") {
            WindowCommandService(service: service).move($0)
        }
    case "close":
        print("roadie: window close is not implemented in this build")
    default:
        printUsage()
        exit(64)
    }
}

@MainActor
func runDesktopCommand(_ args: [String]) {
    switch args.first {
    case "list":
        let result = DesktopCommandService(service: service).list()
        print(result.message)
        exit(0)
    case "current":
        let result = DesktopCommandService(service: service).current()
        print(result.message)
        exit(0)
    case "label":
        guard let rawID = args.dropFirst().first, let id = Int(rawID), id > 0, !args.dropFirst(2).isEmpty else {
            fputs("roadie: desktop label requires a positive id and label\n", stderr)
            exit(64)
        }
        let result = DesktopCommandService(service: service).label(
            DesktopID(rawValue: id),
            as: args.dropFirst(2).joined(separator: " ")
        )
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "focus":
        guard let rawID = args.dropFirst().first, let id = Int(rawID), id > 0 else {
            fputs("roadie: desktop focus requires a positive id\n", stderr)
            exit(64)
        }
        let result = DesktopCommandService(service: service).focus(DesktopID(rawValue: id))
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "prev":
        let result = DesktopCommandService(service: service).cycle(.prev)
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "next":
        let result = DesktopCommandService(service: service).cycle(.next)
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "last", "back":
        let result = DesktopCommandService(service: service).last()
        print(result.message)
        exit(result.changed ? 0 : 1)
    default:
        printUsage()
        exit(64)
    }
}

@MainActor
func runStageCommand(_ args: [String]) {
    switch args.first {
    case "list":
        let result = StageCommandService(service: service).list()
        print(result.message)
        exit(0)
    case "create":
        guard let stageID = args.dropFirst().first else {
            fputs("roadie: stage create requires a stage id\n", stderr)
            exit(64)
        }
        let name = args.dropFirst(2).isEmpty ? nil : args.dropFirst(2).joined(separator: " ")
        let result = StageCommandService(service: service).create(stageID, name: name)
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "rename":
        guard let stageID = args.dropFirst().first, !args.dropFirst(2).isEmpty else {
            fputs("roadie: stage rename requires a stage id and name\n", stderr)
            exit(64)
        }
        let result = StageCommandService(service: service).rename(stageID, to: args.dropFirst(2).joined(separator: " "))
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "reorder":
        guard let stageID = args.dropFirst().first,
              let rawPosition = args.dropFirst(2).first,
              let position = Int(rawPosition)
        else {
            fputs("roadie: stage reorder requires a stage id and numeric position\n", stderr)
            exit(64)
        }
        let result = StageCommandService(service: service).reorder(stageID, to: position)
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "delete":
        guard let stageID = args.dropFirst().first else {
            fputs("roadie: stage delete requires a stage id\n", stderr)
            exit(64)
        }
        let result = StageCommandService(service: service).delete(stageID)
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "mode":
        runModeCommand(args.dropFirst().first)
    case "switch":
        guard let stageID = args.dropFirst().first else {
            fputs("roadie: stage switch requires a stage id\n", stderr)
            exit(64)
        }
        let result = StageCommandService(service: service).switchTo(stageID)
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "assign":
        guard let stageID = args.dropFirst().first else {
            fputs("roadie: stage assign requires a stage id\n", stderr)
            exit(64)
        }
        let result = StageCommandService(service: service).assign(stageID)
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "prev":
        let result = StageCommandService(service: service).cycle(.prev)
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "next":
        let result = StageCommandService(service: service).cycle(.next)
        print(result.message)
        exit(result.changed ? 0 : 1)
    case .some(let rawStageID):
        let result = StageCommandService(service: service).switchTo(rawStageID)
        print(result.message)
        exit(result.changed ? 0 : 1)
    case nil:
        printUsage()
        exit(64)
    }
}

@MainActor
func runModeCommand(_ rawMode: String?) {
    guard let rawMode, let mode = WindowManagementMode(roadieValue: rawMode) else {
        fputs("roadie: mode requires bsp|masterStack|float\n", stderr)
        exit(64)
    }
    let result = StageCommandService(service: service).setMode(mode)
    print(result.message)
    exit(result.changed ? 0 : 1)
}

@MainActor
func runCompatibilityCommand(_ group: String, _ args: [String]) {
    print("roadie: \(group) \(args.joined(separator: " ")) accepted; persistent \(group) state is not implemented in this build")
}

@MainActor
func runShell(_ executable: String, _ arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    do {
        try process.run()
        process.waitUntilExit()
        exit(process.terminationStatus)
    } catch {
        fputs("roadie: failed to run \(executable): \(error)\n", stderr)
        exit(1)
    }
}
