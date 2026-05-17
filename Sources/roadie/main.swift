import Foundation
import RoadieAX
import RoadieCore
import RoadieDaemon

let args = Array(CommandLine.arguments.dropFirst())
let service = SnapshotService()

func printUsage() {
    print("""
    usage:
      roadie windows list [--json]
      roadie display list|current [--json]
      roadie display focus N|left|right|up|down
      roadie state dump|audit|heal [--json]
      roadie tree dump [--json]
      roadie layout plan [--json]
      roadie layout apply [--yes] [--json]
      roadie layout split horizontal|vertical
      roadie layout toggle-split [left|right|up|down]
      roadie layout join-with|insert left|right|up|down
      roadie layout flatten|zoom-parent
      roadie layout width next|prev|nudge [DELTA]|ratio RATIO [--all]
      roadie config show|validate|reload [--json] [--config PATH]
      roadie rules validate|list|explain [--json] [--config PATH]
      roadie group create|add|remove|focus|dissolve|list ...
      roadie query state|windows|displays|desktops|stages|groups|rules|health|events|event_catalog|performance|restore
      roadie rail status|pin|unpin|toggle
      roadie rail labels show|hide|status
      roadie doctor
      roadie self-test
      roadie events tail [N]
      roadie events subscribe [--from-now] [--initial-state] [--type TYPE] [--scope SCOPE]
      roadie performance summary|recent|thresholds [--json] [--limit N]
      roadie restore snapshot|status|apply [--yes] [--json]
      roadie cleanup [--dry-run|--apply] [--json]
      roadie metrics [--json]
      roadie permissions [--prompt]
      roadie focus status
      roadie focus back-and-forth|left|right|up|down
      roadie bookmark set|focus|jump|clear|list NAME
      roadie move|warp|wrap|resize left|right|up|down
      roadie mode bsp|mutableBsp|masterStack|float
      roadie window display N
      roadie window desktop N [--follow]
      roadie window bookmark set|focus|jump|clear|list NAME
      roadie window reset
      roadie desktop list|current
      roadie desktop focus N|prev|next|last|back|back-and-forth
      roadie desktop summon N
      roadie desktop label N NAME
      roadie stage list
      roadie stage create|delete N
      roadie stage rename N NAME
      roadie stage reorder N POSITION
      roadie stage switch|assign N
      roadie stage switch-position|assign-position N
      roadie stage switch-visible prev|next
      roadie stage assign-empty
      roadie stage summon WINDOW_ID
      roadie stage move-to-display N|left|right|up|down [--follow|--no-follow]
      roadie stage mode bsp|mutableBsp|masterStack|float
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
        guard let target = args.dropFirst(2).first else {
            fputs("roadie: display focus requires N|left|right|up|down\n", stderr)
            exit(64)
        }
        let commandService = DisplayCommandService(service: service)
        let result: StageCommandResult
        if let index = Int(target), index > 0 {
            result = commandService.focus(index: index)
        } else if let direction = Direction(rawValue: target) {
            result = commandService.focus(direction)
        } else {
            fputs("roadie: display focus requires N|left|right|up|down\n", stderr)
            exit(64)
        }
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
    case "flatten":
        let result = LayoutCommandService(service: service).flatten()
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "split":
        let result = LayoutCommandService(service: service).split(args.dropFirst(2).first ?? "")
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "toggle-split":
        let rawDirection = args.dropFirst(2).first
        let direction = rawDirection.flatMap(Direction.init(rawValue:))
        if rawDirection != nil && direction == nil {
            fputs("roadie: layout toggle-split expects optional left|right|up|down\n", stderr)
            exit(64)
        }
        let result = LayoutCommandService(service: service).toggleSplit(direction)
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "insert":
        guard let rawDirection = args.dropFirst(2).first, let direction = Direction(rawValue: rawDirection) else {
            fputs("roadie: layout insert requires left|right|up|down\n", stderr)
            exit(64)
        }
        let result = LayoutCommandService(service: service).insert(direction)
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "join-with":
        guard let rawDirection = args.dropFirst(2).first, let direction = Direction(rawValue: rawDirection) else {
            fputs("roadie: layout join-with requires left|right|up|down\n", stderr)
            exit(64)
        }
        let result = LayoutCommandService(service: service).join(with: direction)
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "zoom-parent":
        let result = LayoutCommandService(service: service).zoomParent()
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "width":
        let result = runWidthLayoutCommand(Array(args.dropFirst(2)))
        print(result.message)
        exit(result.changed ? 0 : 1)
    default:
        printUsage()
        exit(64)
    }
case "tree":
    guard args.dropFirst().first == "dump" else {
        printUsage()
        exit(64)
    }
    let dump = TreeDumpService(service: service).dump()
    if args.contains("--json") {
        do {
            print(try SnapshotEncoding.json(dump))
        } catch {
            fputs("roadie: failed to encode tree dump: \(error)\n", stderr)
            exit(1)
        }
    } else {
        print(TextFormatter.treeDump(dump))
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
    let verb = args.dropFirst().first
    guard verb == "tail" || verb == "subscribe" else {
        printUsage()
        exit(64)
    }
    if verb == "tail" {
        let limit = args.dropFirst(2).first.flatMap(Int.init) ?? 20
        print(EventLog().tail(limit: limit).joined(separator: "\n"))
    } else {
        runEventSubscription(Array(args.dropFirst(2)))
    }
case "performance":
    runPerformanceCommand(Array(args.dropFirst()))
case "restore":
    runRestoreCommand(Array(args.dropFirst()))
case "cleanup":
    let dryRun = !args.contains("--apply")
    let report = FileAdministrationService().run(dryRun: dryRun)
    if args.contains("--json") {
        printCodableJSON(report)
    } else {
        print(TextFormatter.fileAdmin(report))
    }
case "metrics":
    let metrics = MetricsService(service: service).collect()
    if args.contains("--json") {
        do {
            print(try SnapshotEncoding.json(metrics))
        } catch {
            fputs("roadie: failed to encode metrics: \(error)\n", stderr)
            exit(1)
        }
    } else {
        print(TextFormatter.metrics(metrics))
    }
case "config":
    let verb = args.dropFirst().first
    guard verb == "show" || verb == "validate" || verb == "reload" else {
        printUsage()
        exit(64)
    }
    let configPath = value(after: "--config", in: Array(args.dropFirst(2)))
    if verb == "validate" {
        let report = RoadieConfigLoader.validate(path: configPath)
        if args.contains("--json") {
            printCodableJSON(report)
        } else {
            print(TextFormatter.configValidation(report))
        }
        exit(report.hasErrors ? 1 : 0)
    } else if verb == "reload" {
        let result = ConfigReloadService().reload(path: configPath ?? RoadieConfigLoader.defaultConfigPath())
        if args.contains("--json") {
            printCodableJSON(result)
        } else {
            print("status=\(result.status.rawValue)")
            if let error = result.error {
                print("error=\(error)")
            }
        }
        exit(result.status == .applied ? 0 : 1)
    }
    do {
        let config = try RoadieConfigLoader.load(from: configPath)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(config), as: UTF8.self))
    } catch {
        fputs("roadie: config load failed: \(error)\n", stderr)
        exit(1)
    }
case "rules":
    runRulesCommand(Array(args.dropFirst()))
case "group":
    runGroupCommand(Array(args.dropFirst()))
case "query":
    runQueryCommand(Array(args.dropFirst()))
case "rail":
    guard let verb = args.dropFirst().first,
          ["status", "pin", "unpin", "toggle", "labels"].contains(verb)
    else {
        printUsage()
        exit(64)
    }
    let runtimeStore = RailRuntimeStateStore()
    switch verb {
    case "status":
        let pinned = runtimeStore.load().isPinned
        print((RailSettings.load().statusLines + ["runtime.pinned=\(pinned)"]).joined(separator: "\n"))
    case "pin":
        let state = runtimeStore.setPinned(true)
        print("rail pinned=\(state.isPinned)")
    case "unpin":
        let state = runtimeStore.setPinned(false)
        print("rail pinned=\(state.isPinned)")
    case "toggle":
        let state = runtimeStore.togglePinned()
        print("rail pinned=\(state.isPinned)")
    case "labels":
        let subcommand = args.dropFirst(2).first ?? "show"
        let settings = RailSettings.load().stageLabel
        switch subcommand {
        case "show":
            let state = runtimeStore.showStageLabels(for: settings.visibilitySeconds)
            if settings.visibilitySeconds <= 0 {
                print("rail labels visible=always")
            } else {
                print("rail labels visible_until=\(state.stageLabelsVisibleUntil ?? 0)")
            }
        case "hide":
            let state = runtimeStore.hideStageLabels()
            print("rail labels visible_until=\(state.stageLabelsVisibleUntil ?? 0)")
        case "status":
            let state = runtimeStore.load()
            let until = state.stageLabelsVisibleUntil.map { String($0) } ?? "-"
            print("rail labels visibility_seconds=\(settings.visibilitySeconds) fade_seconds=\(settings.fadeSeconds) visible_until=\(until)")
        default:
            printUsage()
            exit(64)
        }
    default:
        printUsage()
        exit(64)
    }
case "focus":
    if args.dropFirst().first == "status" {
        print(TextFormatter.focusStatus(service.snapshot()))
        exit(0)
    } else if args.dropFirst().first == "back-and-forth" {
        let result = WindowCommandService(service: service).focusBackAndForth()
        print(result.message)
        exit(result.changed ? 0 : 1)
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
case "bookmark":
    runBookmarkCommand(Array(args.dropFirst()))
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
    let windowCommands = WindowCommandService(service: service)
    let result: WindowCommandResult
    switch subject {
    case "fullscreen":
        result = windowCommands.toggleFullscreen()
    case "native-fullscreen":
        result = windowCommands.toggleNativeFullscreen()
    case "floating":
        print("roadie: \(args.joined(separator: " ")) is not implemented in this build")
        exit(1)
    default:
        printUsage()
        exit(64)
    }
    print(result.message)
    exit(result.changed ? 0 : 1)
default:
    printUsage()
    exit(args.isEmpty ? 0 : 64)
}

func printCodableJSON<T: Encodable>(_ value: T) {
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        print(String(decoding: try encoder.encode(value), as: UTF8.self))
    } catch {
        fputs("roadie: failed to encode JSON: \(error)\n", stderr)
        exit(1)
    }
}

func value(after flag: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: flag) else { return nil }
    let valueIndex = args.index(after: index)
    guard valueIndex < args.endIndex else { return nil }
    return args[valueIndex]
}

func intValue(after flag: String, in args: [String], default defaultValue: Int) -> Int {
    value(after: flag, in: args).flatMap(Int.init) ?? defaultValue
}

func runPerformanceCommand(_ args: [String]) -> Never {
    guard let verb = args.first else {
        printUsage()
        exit(64)
    }
    let performance = PerformanceLogService()
    let json = args.contains("--json")
    switch verb {
    case "summary":
        let report = performance.summary(limit: intValue(after: "--limit", in: args, default: 500))
        json ? printCodableJSON(report) : print(TextFormatter.performanceSummary(report))
        exit(0)
    case "recent":
        let events = performance.recent(limit: intValue(after: "--limit", in: args, default: 20))
        json ? printCodableJSON(events) : print(TextFormatter.performanceRecent(events))
        exit(0)
    case "thresholds":
        let thresholds = performance.thresholds()
        json ? printCodableJSON(thresholds) : print(TextFormatter.performanceThresholds(thresholds))
        exit(0)
    default:
        printUsage()
        exit(64)
    }
}

@MainActor
func runRestoreCommand(_ args: [String]) -> Never {
    guard let verb = args.first else {
        printUsage()
        exit(64)
    }
    let restore = RestoreSafetyService(service: service)
    let json = args.contains("--json")
    do {
        switch verb {
        case "snapshot":
            let snapshot = try restore.writeSnapshot()
            json ? printCodableJSON(snapshot) : print("restore snapshot written windows=\(snapshot.windows.count)")
            exit(0)
        case "status":
            let status = restore.status()
            json ? printCodableJSON(status) : print(TextFormatter.restoreStatus(status))
            exit(status.exists ? 0 : 1)
        case "apply":
            guard args.contains("--yes") else {
                fputs("roadie: restore apply requires --yes\n", stderr)
                exit(2)
            }
            let result = try restore.apply()
            json ? printCodableJSON(result) : print(TextFormatter.restoreApply(result))
            exit(result.failed == 0 ? 0 : 1)
        default:
            printUsage()
            exit(64)
        }
    } catch {
        fputs("roadie: restore \(verb) failed: \(error)\n", stderr)
        exit(1)
    }
}

@MainActor
func runWidthLayoutCommand(_ args: [String]) -> WindowCommandResult {
    guard let verb = args.first else {
        return WindowCommandResult(message: "layout width: requires next|prev|nudge|ratio", changed: false)
    }
    let scope: WidthAdjustmentScope = args.contains("--all") ? .allWindows : .activeWindow
    let widthService = WidthAdjustmentService(service: service)
    let result: WidthAdjustmentResult
    switch verb {
    case "next":
        result = widthService.apply(WidthAdjustmentIntent(scope: scope, mode: .presetNext))
    case "prev", "previous":
        result = widthService.apply(WidthAdjustmentIntent(scope: scope, mode: .presetPrevious))
    case "nudge":
        result = widthService.apply(WidthAdjustmentIntent(
            scope: scope,
            mode: .nudge,
            delta: args.dropFirst().first.flatMap(Double.init)
        ))
    case "ratio":
        guard let raw = args.dropFirst().first, let ratio = Double(raw) else {
            return WindowCommandResult(message: "layout width ratio: requires numeric ratio", changed: false)
        }
        result = widthService.apply(WidthAdjustmentIntent(scope: scope, mode: .explicitRatio, targetRatio: ratio))
    default:
        return WindowCommandResult(message: "layout width: requires next|prev|nudge|ratio", changed: false)
    }
    return WindowCommandResult(message: result.message, changed: result.changed)
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
    case "bookmark":
        runBookmarkCommand(Array(args.dropFirst()))
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
func runBookmarkCommand(_ args: [String]) {
    let command = WindowBookmarkCommandService(service: service)
    switch args.first {
    case "set":
        guard let name = args.dropFirst().first else {
            fputs("roadie: bookmark set requires a name\n", stderr)
            exit(64)
        }
        let result = command.set(name)
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "focus", "jump":
        guard let name = args.dropFirst().first else {
            fputs("roadie: bookmark focus requires a name\n", stderr)
            exit(64)
        }
        let result = command.focus(name)
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "clear", "remove":
        guard let name = args.dropFirst().first else {
            fputs("roadie: bookmark clear requires a name\n", stderr)
            exit(64)
        }
        let result = command.clear(name)
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "list":
        let result = command.list()
        print(result.message)
        exit(0)
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
    case "back-and-forth":
        let result = DesktopCommandService(service: service).backAndForth()
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "summon":
        guard let rawID = args.dropFirst().first, let id = Int(rawID), id > 0 else {
            fputs("roadie: desktop summon requires a positive id\n", stderr)
            exit(64)
        }
        let result = DesktopCommandService(service: service).summon(DesktopID(rawValue: id))
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
    case "switch-position", "switch-pos":
        guard let rawPosition = args.dropFirst().first, let position = Int(rawPosition), position > 0 else {
            fputs("roadie: stage switch-position requires a positive position\n", stderr)
            exit(64)
        }
        let result = StageCommandService(service: service).switchToPosition(position)
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "switch-visible":
        guard let rawDirection = args.dropFirst().first,
              let direction = StageCycleDirection(rawValue: rawDirection)
        else {
            fputs("roadie: stage switch-visible requires prev|next\n", stderr)
            exit(64)
        }
        let result = StageCommandService(service: service).switchVisible(direction)
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
    case "assign-position", "assign-pos":
        guard let rawPosition = args.dropFirst().first, let position = Int(rawPosition), position > 0 else {
            fputs("roadie: stage assign-position requires a positive position\n", stderr)
            exit(64)
        }
        let result = StageCommandService(service: service).assignPosition(position)
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "assign-empty":
        let result = StageCommandService(service: service).assignEmpty()
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "summon":
        guard let rawWindowID = args.dropFirst().first, let id = UInt32(rawWindowID) else {
            fputs("roadie: stage summon requires a window id\n", stderr)
            exit(64)
        }
        let snapshot = service.snapshot()
        let state = StageStore().state()
        guard let activeDisplayID = state.activeDisplayID ?? snapshot.focusedWindowID.flatMap({ focusedID in
            snapshot.windows.first { $0.window.id == focusedID }?.scope?.displayID
        }) ?? snapshot.displays.first?.id else {
            fputs("roadie: stage summon: no active display\n", stderr)
            exit(1)
        }
        let result = StageCommandService(service: service).summon(windowID: WindowID(rawValue: id), displayID: activeDisplayID)
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "move-to-display":
        guard let rawTarget = args.dropFirst().first else {
            fputs("roadie: stage move-to-display requires a display index or direction\n", stderr)
            exit(64)
        }
        let flags = Array(args.dropFirst(2))
        let allowedFlags: Set<String> = ["--follow", "--no-follow"]
        if let unknown = flags.first(where: { !allowedFlags.contains($0) }) {
            fputs("roadie: unknown stage move-to-display option \(unknown)\n", stderr)
            exit(64)
        }
        if flags.contains("--follow"), flags.contains("--no-follow") {
            fputs("roadie: stage move-to-display accepts only one of --follow or --no-follow\n", stderr)
            exit(64)
        }
        let followFocus: Bool? = flags.contains("--follow") ? true : (flags.contains("--no-follow") ? false : nil)
        let commandService = StageCommandService(service: service)
        let result: StageCommandResult
        if let index = Int(rawTarget), index > 0 {
            result = commandService.moveActiveStageToDisplay(index: index, followFocus: followFocus)
        } else if let direction = Direction(rawValue: rawTarget) {
            result = commandService.moveActiveStageToDisplay(direction: direction, followFocus: followFocus)
        } else {
            fputs("roadie: stage move-to-display requires a display index or left|right|up|down\n", stderr)
            exit(64)
        }
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
func runEventSubscription(_ args: [String]) -> Never {
    let options = parseEventSubscriptionOptions(args)
    let subscription = EventSubscriptionService()
    var cursor = subscription.start(options: options)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let correlationId = emitCommandEvent(
        type: "command.received",
        command: "events.subscribe",
        result: "received"
    )
    for event in subscription.initialEvents(snapshot: service.snapshot().automationSnapshot(), options: options) {
        if let data = try? encoder.encode(event),
           let line = String(data: data, encoding: .utf8) {
            print(line)
        }
    }
    emitCommandEvent(
        type: "command.applied",
        command: "events.subscribe",
        result: "streaming",
        correlationId: correlationId
    )
    fflush(stdout)
    while true {
        let result = subscription.readAvailable(from: cursor, options: options)
        cursor = result.cursor
        for event in result.events {
            if let data = try? encoder.encode(event),
               let line = String(data: data, encoding: .utf8) {
                print(line)
            }
        }
        fflush(stdout)
        Thread.sleep(forTimeInterval: 0.2)
    }
}

@discardableResult
func emitCommandEvent(type: String, command: String, result: String, correlationId: String = UUID().uuidString) -> String {
    EventLog().append(RoadieEventEnvelope(
        id: "cmd_\(UUID().uuidString)",
        type: type,
        scope: .command,
        subject: AutomationSubject(kind: "command", id: command),
        correlationId: correlationId,
        cause: .command,
        payload: [
            "command": .string(command),
            "result": .string(result)
        ]
    ))
    return correlationId
}

func parseEventSubscriptionOptions(_ args: [String]) -> EventSubscriptionOptions {
    var fromNow = false
    var initialState = false
    var types = Set<String>()
    var scopes = Set<AutomationScope>()
    var index = 0
    while index < args.count {
        switch args[index] {
        case "--from-now":
            fromNow = true
            index += 1
        case "--initial-state":
            initialState = true
            index += 1
        case "--type":
            guard args.indices.contains(index + 1) else {
                fputs("roadie: events subscribe --type requires a value\n", stderr)
                exit(64)
            }
            types.insert(args[index + 1])
            index += 2
        case "--scope":
            guard args.indices.contains(index + 1) else {
                fputs("roadie: events subscribe --scope requires a value\n", stderr)
                exit(64)
            }
            scopes.insert(AutomationScope(rawValue: args[index + 1]))
            index += 2
        case let unknown:
            fputs("roadie: unknown events subscribe option \(unknown)\n", stderr)
            exit(64)
        }
    }
    return EventSubscriptionOptions(fromNow: fromNow, initialState: initialState, types: types, scopes: scopes)
}

func runRulesCommand(_ args: [String]) -> Never {
    guard let verb = args.first, ["validate", "list", "explain"].contains(verb) else {
        printUsage()
        exit(64)
    }
    let options = parseRulesOptions(Array(args.dropFirst()))
    let service = RulesCommandService(configPath: options.configPath)

    switch verb {
    case "validate":
        let report = service.validate()
        if options.json {
            printCodableJSON(report)
        } else {
            print(TextFormatter.configValidation(report))
        }
        exit(report.hasErrors ? 1 : 0)
    case "list":
        do {
            let rules = try service.list()
            if options.json {
                printCodableJSON(rules)
            } else {
                print(TextFormatter.rules(rules))
            }
            exit(0)
        } catch {
            fputs("roadie: rules list failed: \(error)\n", stderr)
            exit(1)
        }
    case "explain":
        guard let app = options.app else {
            fputs("roadie: rules explain requires --app APP\n", stderr)
            exit(64)
        }
        let window = WindowSnapshot(
            id: WindowID(rawValue: 1),
            pid: 0,
            appName: app,
            bundleID: options.bundleID ?? "",
            title: options.title ?? "",
            frame: Rect(x: 0, y: 0, width: 1, height: 1),
            isOnScreen: true,
            isTileCandidate: true
        )
        let context = WindowRuleMatchContext(
            role: options.role,
            subrole: options.subrole,
            display: options.display,
            desktop: options.desktop,
            stage: options.stage,
            isFloating: options.isFloating
        )
        do {
            let explanation = try service.explain(window: window, context: context)
            if options.json {
                printCodableJSON(explanation)
            } else {
                print(TextFormatter.ruleExplanation(explanation))
            }
            exit(explanation.matchedRuleID == nil ? 1 : 0)
        } catch {
            fputs("roadie: rules explain failed: \(error)\n", stderr)
            exit(1)
        }
    default:
        printUsage()
        exit(64)
    }
}

func runGroupCommand(_ args: [String]) -> Never {
    let service = WindowGroupCommandService()
    switch args.first {
    case "list":
        let result = service.list()
        print(result.message)
        exit(0)
    case "create":
        guard let id = args.dropFirst().first else {
            fputs("roadie: group create requires an id\n", stderr)
            exit(64)
        }
        let ids = args.dropFirst(2).compactMap(UInt32.init).map(WindowID.init(rawValue:))
        let result = service.create(id: id, windowIDs: ids)
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "add":
        guard let id = args.dropFirst().first,
              let rawWindowID = args.dropFirst(2).first,
              let windowID = UInt32(rawWindowID)
        else {
            fputs("roadie: group add requires GROUP_ID WINDOW_ID\n", stderr)
            exit(64)
        }
        let result = service.add(windowID: WindowID(rawValue: windowID), to: id)
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "remove":
        guard let id = args.dropFirst().first,
              let rawWindowID = args.dropFirst(2).first,
              let windowID = UInt32(rawWindowID)
        else {
            fputs("roadie: group remove requires GROUP_ID WINDOW_ID\n", stderr)
            exit(64)
        }
        let result = service.remove(windowID: WindowID(rawValue: windowID), from: id)
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "focus":
        guard let id = args.dropFirst().first,
              let rawWindowID = args.dropFirst(2).first,
              let windowID = UInt32(rawWindowID)
        else {
            fputs("roadie: group focus requires GROUP_ID WINDOW_ID\n", stderr)
            exit(64)
        }
        let result = service.focus(windowID: WindowID(rawValue: windowID), in: id)
        print(result.message)
        exit(result.changed ? 0 : 1)
    case "dissolve":
        guard let id = args.dropFirst().first else {
            fputs("roadie: group dissolve requires GROUP_ID\n", stderr)
            exit(64)
        }
        let result = service.dissolve(id: id)
        print(result.message)
        exit(result.changed ? 0 : 1)
    default:
        printUsage()
        exit(64)
    }
}

@MainActor
func runQueryCommand(_ args: [String]) -> Never {
    guard let name = args.first else {
        printUsage()
        exit(64)
    }
    let result = AutomationQueryService(service: service).query(name)
    if case .object(let object) = result.data,
       object["error"] != nil {
        printCodableJSON(result)
        exit(64)
    }
    printCodableJSON(result)
    exit(0)
}

struct RulesOptions {
    var json = false
    var configPath: String?
    var app: String?
    var bundleID: String?
    var title: String?
    var role: String?
    var subrole: String?
    var display: String?
    var desktop: String?
    var stage: String?
    var isFloating: Bool?
}

func parseRulesOptions(_ args: [String]) -> RulesOptions {
    var options = RulesOptions()
    var index = 0
    while index < args.count {
        switch args[index] {
        case "--json":
            options.json = true
            index += 1
        case "--config":
            options.configPath = requiredRulesOption(args, index: index, name: "--config")
            index += 2
        case "--app":
            options.app = requiredRulesOption(args, index: index, name: "--app")
            index += 2
        case "--bundle-id":
            options.bundleID = requiredRulesOption(args, index: index, name: "--bundle-id")
            index += 2
        case "--title":
            options.title = requiredRulesOption(args, index: index, name: "--title")
            index += 2
        case "--role":
            options.role = requiredRulesOption(args, index: index, name: "--role")
            index += 2
        case "--subrole":
            options.subrole = requiredRulesOption(args, index: index, name: "--subrole")
            index += 2
        case "--display":
            options.display = requiredRulesOption(args, index: index, name: "--display")
            index += 2
        case "--desktop":
            options.desktop = requiredRulesOption(args, index: index, name: "--desktop")
            index += 2
        case "--stage":
            options.stage = requiredRulesOption(args, index: index, name: "--stage")
            index += 2
        case "--floating":
            options.isFloating = true
            index += 1
        case "--tiled":
            options.isFloating = false
            index += 1
        case let unknown:
            fputs("roadie: unknown rules option \(unknown)\n", stderr)
            exit(64)
        }
    }
    return options
}

func requiredRulesOption(_ args: [String], index: Int, name: String) -> String {
    guard args.indices.contains(index + 1) else {
        fputs("roadie: rules \(name) requires a value\n", stderr)
        exit(64)
    }
    return args[index + 1]
}

@MainActor
func runModeCommand(_ rawMode: String?) {
    guard let rawMode, let mode = WindowManagementMode(roadieValue: rawMode) else {
        fputs("roadie: mode requires bsp|mutableBsp|masterStack|float\n", stderr)
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
    // Securite : on n'accepte que des chemins absolus pour l'executable, evitant le PATH lookup
    // et toute resolution implicite. Les seuls callers internes utilisent des paths hard-codes.
    guard executable.hasPrefix("/") else {
        fputs("roadie: refusing relative executable path: \(executable)\n", stderr)
        exit(1)
    }
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
