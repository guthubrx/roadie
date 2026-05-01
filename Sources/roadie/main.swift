import Foundation
import RoadieCore

/// CLI client roadie. Encode la commande, envoie au daemon via socket, affiche la réponse.

let args = CommandLine.arguments
guard args.count >= 2 else {
    printUsage()
    exit(64)
}

let command = args[1]

switch command {
case "--help", "-h":
    printUsage()
    exit(0)

case "windows":
    guard args.count >= 3 else { printUsage(); exit(64) }
    handleWindows(verb: args[2])

case "daemon":
    guard args.count >= 3 else { printUsage(); exit(64) }
    handleDaemon(verb: args[2])

case "focus":
    guard args.count >= 3 else { printUsage(); exit(64) }
    sendAndPrint(Request(command: "focus", args: ["direction": args[2]]))

case "move":
    guard args.count >= 3 else { printUsage(); exit(64) }
    sendAndPrint(Request(command: "move", args: ["direction": args[2]]))

case "resize":
    guard args.count >= 4 else { printUsage(); exit(64) }
    sendAndPrint(Request(command: "resize",
                         args: ["direction": args[2], "delta": args[3]]))

case "tiler":
    guard args.count >= 3 else { printUsage(); exit(64) }
    if args[2] == "list" {
        sendAndPrint(Request(command: "tiler.list"))
    } else {
        sendAndPrint(Request(command: "tiler.set", args: ["strategy": args[2]]))
    }

case "tree":
    sendAndPrint(Request(command: "tree.dump"))

case "balance":
    sendAndPrint(Request(command: "balance"))

case "rebuild":
    sendAndPrint(Request(command: "rebuild"))

case "stage":
    handleStage(args: args)

default:
    printUsage()
    exit(64)
}

func handleWindows(verb: String) {
    switch verb {
    case "list":
        sendAndPrint(Request(command: "windows.list"))
    default:
        printUsage(); exit(64)
    }
}

func handleDaemon(verb: String) {
    switch verb {
    case "status":
        sendAndPrint(Request(command: "daemon.status"))
    case "reload":
        sendAndPrint(Request(command: "daemon.reload"))
    default:
        printUsage(); exit(64)
    }
}

func handleStage(args: [String]) {
    // roadie stage <stage_id>            → switch
    // roadie stage list                  → list
    // roadie stage assign <stage_id>     → assign frontmost
    // roadie stage create <id> <name>    → create
    // roadie stage delete <id>           → delete
    guard args.count >= 3 else { printUsage(); exit(64) }
    let arg2 = args[2]
    switch arg2 {
    case "list":
        sendAndPrint(Request(command: "stage.list"))
    case "assign":
        guard args.count >= 4 else { printUsage(); exit(64) }
        sendAndPrint(Request(command: "stage.assign", args: ["stage_id": args[3]]))
    case "create":
        guard args.count >= 5 else { printUsage(); exit(64) }
        sendAndPrint(Request(command: "stage.create",
                             args: ["stage_id": args[3], "display_name": args[4]]))
    case "delete":
        guard args.count >= 4 else { printUsage(); exit(64) }
        sendAndPrint(Request(command: "stage.delete", args: ["stage_id": args[3]]))
    default:
        // arg2 est le stage_id pour switch
        sendAndPrint(Request(command: "stage.switch", args: ["stage_id": arg2]))
    }
}

func sendAndPrint(_ request: Request) {
    do {
        let response = try SocketClient.send(request)
        OutputFormatter.print(response: response)
        if response.status == .error { exit(1) }
    } catch SocketClient.Error.daemonNotRunning {
        FileHandle.standardError.write(
            "roadie: daemon not running. Start with `roadied --daemon` or via launchctl.\n"
                .data(using: .utf8) ?? Data())
        exit(2)
    } catch {
        FileHandle.standardError.write("roadie: \(error)\n".data(using: .utf8) ?? Data())
        exit(1)
    }
}

func printUsage() {
    let usage = """
    usage:
      roadie windows list
      roadie daemon status | reload
      roadie focus <left|right|up|down>
      roadie move <left|right|up|down>
      roadie resize <left|right|up|down> <delta>
      roadie tiler list                          # liste les stratégies disponibles
      roadie tiler <strategy>                    # change la stratégie active
      roadie stage list
      roadie stage <stage_id>                    # switch to stage
      roadie stage assign <stage_id>             # assign frontmost
      roadie stage create <stage_id> <name>      # create new stage
      roadie stage delete <stage_id>             # delete stage
    """
    FileHandle.standardError.write((usage + "\n").data(using: .utf8) ?? Data())
}
