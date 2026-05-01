import Foundation
import Network
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

case "desktop":
    handleDesktop(args: args)

case "events":
    handleEvents(args: args)

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
        if response.status == .error {
            // Codes exit V2 (cf. specs/003-multi-desktop/contracts/cli-protocol.md) :
            // 2 = bad usage / selector invalide, 3 = daemon down, 4 = multi_desktop disabled,
            // 5 = desktop introuvable, 1 = autre.
            switch response.errorCode ?? "" {
            case "invalid_argument": exit(2)
            case "multi_desktop_disabled": exit(4)
            case "unknown_desktop", "unknown_stage", "window_not_found": exit(5)
            default: exit(1)
            }
        }
    } catch SocketClient.Error.daemonNotRunning {
        FileHandle.standardError.write(
            "roadie: daemon not running. Start with `roadied --daemon` or via launchctl.\n"
                .data(using: .utf8) ?? Data())
        exit(3)
    } catch {
        FileHandle.standardError.write("roadie: \(error)\n".data(using: .utf8) ?? Data())
        exit(1)
    }
}

/// V2 multi-desktop (FR-009..FR-013).
///   roadie desktop list [--json]
///   roadie desktop current [--json]
///   roadie desktop focus <selector>          # prev|next|recent|first|last|N|<label>
///   roadie desktop label <name>              # vide → retire
///   roadie desktop back                      # alias de focus recent
func handleDesktop(args: [String]) {
    guard args.count >= 3 else { printUsage(); exit(2) }
    let json = args.contains("--json")
    switch args[2] {
    case "list":
        if json {
            sendAndPrint(Request(command: "desktop.list"))
        } else {
            sendDesktopListAsTable()
        }
    case "current":
        sendAndPrint(Request(command: "desktop.current"))
    case "focus":
        guard args.count >= 4 else { printUsage(); exit(2) }
        sendAndPrint(Request(command: "desktop.focus", args: ["selector": args[3]]))
    case "label":
        let name = args.count >= 4 ? args[3] : ""
        sendAndPrint(Request(command: "desktop.label", args: ["name": name]))
    case "back":
        sendAndPrint(Request(command: "desktop.back"))
    default:
        printUsage(); exit(2)
    }
}

/// V2 events stream (FR-014..FR-016).
///   roadie events --follow [--filter <event-name>]...
func handleEvents(args: [String]) {
    let isFollow = args.contains("--follow")
    guard isFollow else {
        FileHandle.standardError.write("usage: roadie events --follow [--filter <event>]\n".data(using: .utf8) ?? Data())
        exit(2)
    }
    // Collecte des filtres : --filter peut être répété.
    var filters: Set<String> = []
    var i = 0
    while i < args.count {
        if args[i] == "--filter", i + 1 < args.count {
            filters.insert(args[i + 1])
            i += 2
        } else {
            i += 1
        }
    }
    streamEventsToStdout(filters: filters)
}

/// Connexion persistante au daemon via le socket Unix : envoie la commande
/// `events.subscribe`, lit l'ack, puis boucle en relayant chaque ligne reçue
/// vers stdout (auto-flush). Termine sur Ctrl+C ou perte du daemon (exit 3).
func streamEventsToStdout(filters: Set<String>) {
    let socketPath = (NSString(string: "~/.roadies/daemon.sock").expandingTildeInPath as String)
    guard FileManager.default.fileExists(atPath: socketPath) else {
        FileHandle.standardError.write("roadie: daemon not running\n".data(using: .utf8) ?? Data())
        exit(3)
    }
    let endpoint = NWEndpoint.unix(path: socketPath)
    let connection = NWConnection(to: endpoint, using: .tcp)
    let exitOnDaemonGone = DispatchSemaphore(value: 0)

    // Buffer pour réassembler les lignes JSON (paquet TCP peut couper au milieu).
    var buffer = Data()

    func processBuffer() {
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: 0..<nl)
            buffer.removeSubrange(0...nl)
            if line.isEmpty { continue }
            // Filtre : si filtres non vides, ne keep que les events matching.
            if !filters.isEmpty {
                if let dict = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                   let name = dict["event"] as? String,
                   !filters.contains(name) {
                    continue
                }
                // Si pas d'event field (ack), on laisse passer en lecture brute.
            }
            FileHandle.standardOutput.write(line)
            FileHandle.standardOutput.write(Data([0x0A]))
        }
    }

    connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
            let req = Request(command: "events.subscribe")
            guard var data = try? JSONEncoder().encode(req) else { exit(1) }
            data.append(0x0A)
            connection.send(content: data, completion: .contentProcessed { _ in })
            // Boucle de réception.
            func loop() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                    if let data = data, !data.isEmpty {
                        buffer.append(data)
                        processBuffer()
                    }
                    if let error = error {
                        FileHandle.standardError.write("roadie: events stream error: \(error)\n"
                            .data(using: .utf8) ?? Data())
                        exitOnDaemonGone.signal()
                        return
                    }
                    if isComplete {
                        exitOnDaemonGone.signal()
                        return
                    }
                    loop()
                }
            }
            loop()
        case .failed(let err):
            FileHandle.standardError.write("roadie: events failed: \(err)\n".data(using: .utf8) ?? Data())
            exitOnDaemonGone.signal()
        case .cancelled:
            exitOnDaemonGone.signal()
        default:
            break
        }
    }
    // Ctrl+C → graceful exit 0.
    signal(SIGINT) { _ in exit(0) }
    signal(SIGTERM) { _ in exit(0) }

    connection.start(queue: .global())
    exitOnDaemonGone.wait()
    // Daemon gone → exit 3 par contrats CLI (events-stream.md).
    exit(3)
}

/// Formattage texte du tableau `desktop list` (T069).
/// Colonnes : INDEX UUID(8) LABEL CURRENT STAGES WINDOWS
func sendDesktopListAsTable() {
    do {
        let response = try SocketClient.send(Request(command: "desktop.list"))
        if response.status == .error {
            OutputFormatter.print(response: response)
            exit(response.errorCode == "multi_desktop_disabled" ? 4 : 1)
        }
        let payload = response.payload ?? [:]
        let currentUUID = (payload["current_uuid"]?.value as? String) ?? ""
        let desktops = (payload["desktops"]?.value as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
        if desktops.isEmpty {
            print("INDEX  UUID                                   LABEL  CURRENT  STAGES  WINDOWS")
            print("(no desktops detected)")
            return
        }
        // Header — pad manuel car String(format: %s) attend un C-string et crash
        // sur les String Swift natives (SIGSEGV).
        func pad(_ s: String, _ w: Int) -> String {
            s.count >= w ? s : s + String(repeating: " ", count: w - s.count)
        }
        print("\(pad("INDEX", 5))  \(pad("UUID", 36))  \(pad("LABEL", 8))  \(pad("CURRENT", 7))  \(pad("STAGES", 6))  WINDOWS")
        for d in desktops {
            let idx = (d["index"] as? Int) ?? 0
            let uuid = (d["uuid"] as? String) ?? ""
            let label = (d["label"] as? String) ?? ""
            let isCurrent = uuid == currentUUID ? "*" : ""
            let stages = (d["stage_count"] as? Int) ?? 0
            let windows = (d["window_count"] as? Int) ?? 0
            print("\(pad(String(idx), 5))  \(pad(uuid, 36))  \(pad(label, 8))  \(pad(isCurrent, 7))  \(pad(String(stages), 6))  \(windows)")
        }
    } catch SocketClient.Error.daemonNotRunning {
        FileHandle.standardError.write(
            "roadie: daemon not running\n".data(using: .utf8) ?? Data())
        exit(3)
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
      roadie desktop list [--json]               # V2 multi-desktop
      roadie desktop current [--json]
      roadie desktop focus <prev|next|recent|first|last|N|label>
      roadie desktop label <name>                # name vide → retire
      roadie desktop back                        # alias de focus recent
      roadie events --follow [--filter <event>]  # JSON-lines stream sur stdout
    """
    FileHandle.standardError.write((usage + "\n").data(using: .utf8) ?? Data())
}
