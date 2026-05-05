import Foundation
import Network
import Darwin
import RoadieCore

/// CLI client roadie. Encode la commande, envoie au daemon via socket, affiche la réponse.

// SIGPIPE → ignore. Sinon `roadie events --follow | sketchybar -m ...` reçoit
// SIGPIPE quand le consumer ferme et le shell tue le process avant que les
// errno -EPIPE puissent être gérés côté code.
signal(SIGPIPE, SIG_IGN)

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

case "heal":
    // SPEC-025 FR-005 — auto-cicatrisation rapide.
    sendAndPrint(Request(command: "daemon.heal"))

case "diag":
    // SPEC-025 US7 — diagnostic bundle pour bug report.
    handleDiag(args: args)

case "focus":
    guard args.count >= 3 else { printUsage(); exit(64) }
    sendAndPrint(Request(command: "focus", args: ["direction": args[2]]))

case "move":
    guard args.count >= 3 else { printUsage(); exit(64) }
    sendAndPrint(Request(command: "move", args: ["direction": args[2]]))

case "warp":
    guard args.count >= 3 else { printUsage(); exit(64) }
    sendAndPrint(Request(command: "warp", args: ["direction": args[2]]))

case "close":
    sendAndPrint(Request(command: "window.close"))

case "toggle":
    guard args.count >= 3 else { printUsage(); exit(64) }
    switch args[2] {
    case "floating":
        sendAndPrint(Request(command: "window.toggle.floating"))
    case "fullscreen":
        sendAndPrint(Request(command: "window.toggle.fullscreen"))
    case "native-fullscreen", "native":
        sendAndPrint(Request(command: "window.toggle.native-fullscreen"))
    default:
        FileHandle.standardError.write("roadie: unknown toggle '\(args[2])'. Valid: floating | fullscreen | native-fullscreen\n".data(using: .utf8) ?? Data())
        exit(64)
    }

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

case "tiling":
    // SPEC-026 US1 — sous-verbes balance/rotate/mirror (active trees per-display).
    guard args.count >= 3 else { printUsage(); exit(64) }
    switch args[2] {
    case "balance":
        sendAndPrint(Request(command: "tiling.balance"))
    case "rotate":
        guard args.count >= 4 else {
            FileHandle.standardError.write("usage: roadie tiling rotate <90|180|270>\n".data(using: .utf8)!)
            exit(64)
        }
        sendAndPrint(Request(command: "tiling.rotate", args: ["angle": args[3]]))
    case "mirror":
        guard args.count >= 4 else {
            FileHandle.standardError.write("usage: roadie tiling mirror <x|y>\n".data(using: .utf8)!)
            exit(64)
        }
        sendAndPrint(Request(command: "tiling.mirror", args: ["axis": args[3]]))
    default:
        FileHandle.standardError.write("unknown tiling subcommand: \(args[2])\n".data(using: .utf8)!)
        exit(64)
    }

case "scratchpad":
    // SPEC-026 US3 — `roadie scratchpad toggle <name>`.
    guard args.count >= 4, args[2] == "toggle" else {
        FileHandle.standardError.write("usage: roadie scratchpad toggle <name>\n".data(using: .utf8)!)
        exit(64)
    }
    sendAndPrint(Request(command: "scratchpad.toggle", args: ["name": args[3]]))

case "rebuild":
    sendAndPrint(Request(command: "rebuild"))

case "stage":
    handleStage(args: args)

case "desktop":
    handleDesktop(args: args)

case "events":
    handleEvents(args: args)

case "fx":
    handleFX(args: args)

case "window":
    handleWindow(args: args)

case "display":
    handleDisplay(args: args)

case "rail":
    handleRail(args: args)

default:
    printUsage()
    exit(64)
}

/// SPEC-014 : `roadie rail status|toggle`.
/// SPEC-019 : `roadie rail renderer <id>` / `roadie rail renderers list`.
func handleRail(args: [String]) {
    guard args.count >= 3 else { printUsage(); exit(64) }
    switch args[2] {
    case "status":
        sendAndPrint(Request(command: "rail.status"))
    case "toggle":
        sendAndPrint(Request(command: "rail.toggle"))
    case "renderers":
        // `roadie rail renderers list`
        guard args.count >= 4, args[3] == "list" else { printUsage(); exit(64) }
        sendAndPrint(Request(command: "rail.renderer.list"))
    case "renderer":
        // `roadie rail renderer <id>`
        guard args.count >= 4 else { printUsage(); exit(2) }
        sendAndPrint(Request(command: "rail.renderer.set", args: ["id": args[3]]))
    default:
        printUsage(); exit(64)
    }
}

/// SPEC-010/012 : `roadie window space|display|stick|pin|unpin`.
func handleWindow(args: [String]) {
    guard args.count >= 3 else { printUsage(); exit(64) }
    switch args[2] {
    case "space":
        guard args.count >= 4 else { printUsage(); exit(2) }
        sendAndPrint(Request(command: "window.space", args: ["selector": args[3]]))
    case "display":
        // SPEC-012 T023 : roadie window display <1..N|prev|next|main>
        guard args.count >= 4 else { printUsage(); exit(2) }
        sendAndPrint(Request(command: "window.display", args: ["selector": args[3]]))
    case "desktop":
        // SPEC-013 : roadie window desktop <N> — assigner la fenêtre frontmost
        // au desktop N du display courant. Hide si N != current.
        guard args.count >= 4 else { printUsage(); exit(2) }
        sendAndPrint(Request(command: "window.desktop", args: ["selector": args[3]]))
    case "stick":
        let sticky = args.count >= 4 ? args[3] : "true"
        sendAndPrint(Request(command: "window.stick", args: ["sticky": sticky]))
    case "unstick":
        sendAndPrint(Request(command: "window.stick", args: ["sticky": "false"]))
    case "pin":
        sendAndPrint(Request(command: "window.pin", args: ["pinned": "true"]))
    case "unpin":
        sendAndPrint(Request(command: "window.pin", args: ["pinned": "false"]))
    case "swap":
        // SPEC-018 US1a : roadie window swap <left|right|up|down>
        guard args.count >= 4 else { printUsage(); exit(2) }
        sendAndPrint(Request(command: "window.swap", args: ["direction": args[3]]))
    case "insert":
        // SPEC-018 US4 : roadie window insert <north|south|east|west|stack>
        guard args.count >= 4 else { printUsage(); exit(2) }
        sendAndPrint(Request(command: "window.insert", args: ["direction": args[3]]))
    default:
        printUsage(); exit(64)
    }
}

/// SPEC-012 T035 : `roadie display list/current/focus`.
///   roadie display list [--json]
///   roadie display current [--json]
///   roadie display focus <1..N|prev|next|main>
func handleDisplay(args: [String]) {
    guard args.count >= 3 else { printUsage(); exit(2) }
    let json = args.contains("--json")
    switch args[2] {
    case "list":
        if json {
            sendAndPrint(Request(command: "display.list"))
        } else {
            sendDisplayListAsTable()
        }
    case "current":
        sendAndPrint(Request(command: "display.current"))
    case "focus":
        guard args.count >= 4 else { printUsage(); exit(2) }
        sendAndPrint(Request(command: "display.focus", args: ["selector": args[3]]))
    default:
        printUsage(); exit(2)
    }
}

/// Formatage texte du tableau `display list`.
/// Colonnes : INDEX  ID  NAME  FRAME  IS_MAIN  IS_ACTIVE  WINDOWS
func sendDisplayListAsTable() {
    do {
        let response = try SocketClient.send(Request(command: "display.list"))
        if response.status == .error {
            OutputFormatter.print(response: response)
            exit(1)
        }
        let payload = response.payload ?? [:]
        let displays = (payload["displays"]?.value as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
        func pad(_ s: String, _ w: Int) -> String {
            s.count >= w ? s : s + String(repeating: " ", count: w - s.count)
        }
        print("\(pad("INDEX", 5))  \(pad("ID", 10))  \(pad("NAME", 24))  \(pad("FRAME", 22))  \(pad("IS_MAIN", 7))  \(pad("ACTIVE", 6))  WINDOWS")
        if displays.isEmpty {
            print("(no displays detected)")
            return
        }
        for d in displays {
            let index = (d["index"] as? Int) ?? 0
            let id = (d["id"] as? Int) ?? 0
            let name = (d["name"] as? String) ?? ""
            let isMain = (d["is_main"] as? Bool) == true ? "*" : ""
            let isActive = (d["is_active"] as? Bool) == true ? "*" : ""
            let windows = (d["windows"] as? Int) ?? 0
            let frameArr = (d["frame"] as? [Any])?.compactMap { $0 as? Int } ?? []
            let frame = frameArr.count == 4
                ? "\(frameArr[0]),\(frameArr[1]) \(frameArr[2])x\(frameArr[3])"
                : "?"
            print("\(pad(String(index), 5))  \(pad(String(id), 10))  \(pad(name, 24))  \(pad(frame, 22))  \(pad(isMain, 7))  \(pad(isActive, 6))  \(windows)")
        }
    } catch SocketClient.Error.daemonNotRunning {
        FileHandle.standardError.write("roadie: daemon not running\n".data(using: .utf8) ?? Data())
        exit(3)
    } catch {
        FileHandle.standardError.write("roadie: \(error)\n".data(using: .utf8) ?? Data())
        exit(1)
    }
}

func handleFX(args: [String]) {
    guard args.count >= 3 else { printUsage(); exit(64) }
    switch args[2] {
    case "status":
        sendAndPrint(Request(command: "fx.status"))
    case "reload":
        sendAndPrint(Request(command: "fx.reload"))
    default:
        printUsage(); exit(64)
    }
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
    case "audit":
        // SPEC-021 T080 — audit read-only des invariants stage/desktop ownership.
        // SPEC-022 — `--fix` pour aussi auto-corriger les drifts physiques.
        let fix = args.contains("--fix")
        sendAndPrint(Request(command: "daemon.audit",
                             args: fix ? ["fix": "true"] : nil))
    case "health":
        // SPEC-025 FR-004 — health metric instantané.
        sendAndPrint(Request(command: "daemon.health"))
    case "heal":
        // SPEC-025 FR-005 — alias de `roadie heal`. Pratique pour les users
        // qui pensent en namespace `daemon.*`.
        sendAndPrint(Request(command: "daemon.heal"))
    default:
        printUsage(); exit(64)
    }
}

/// Extrait les flags `--display <selector>` et `--desktop <id>` d'un tableau d'args.
/// Retourne un dict prêt à merger dans Request.args. Les flags sont consommés
/// (non-positionnels) et ignorés dans le reste du parsing.
private func extractScopeOverrides(from args: [String]) -> [String: String] {
    var overrides: [String: String] = [:]
    var i = 0
    while i < args.count {
        if args[i] == "--display", i + 1 < args.count {
            overrides["display"] = args[i + 1]
            i += 2
        } else if args[i] == "--desktop", i + 1 < args.count {
            overrides["desktop"] = args[i + 1]
            i += 2
        } else {
            i += 1
        }
    }
    return overrides
}

func handleStage(args: [String]) {
    // roadie stage <stage_id>                                     → switch
    // roadie stage list [--display <sel>] [--desktop <id>]       → list
    // roadie stage assign <stage_id> [--display <sel>] [...]     → assign frontmost
    // roadie stage create <id> <name> [--display <sel>] [...]    → create
    // roadie stage delete <id> [--display <sel>] [...]           → delete
    // roadie stage rename <id> <new_name> [--display <sel>] [...] → rename
    guard args.count >= 3 else { printUsage(); exit(64) }
    let arg2 = args[2]
    let scopeOverrides = extractScopeOverrides(from: args)

    switch arg2 {
    case "list":
        sendAndPrint(Request(command: "stage.list", args: scopeOverrides.isEmpty ? nil : scopeOverrides))
    case "assign":
        guard args.count >= 4 else { printUsage(); exit(64) }
        var reqArgs = scopeOverrides
        reqArgs["stage_id"] = args[3]
        sendAndPrint(Request(command: "stage.assign", args: reqArgs))
    case "create":
        guard args.count >= 5 else { printUsage(); exit(64) }
        var reqArgs = scopeOverrides
        reqArgs["stage_id"] = args[3]
        reqArgs["display_name"] = args[4]
        sendAndPrint(Request(command: "stage.create", args: reqArgs))
    case "delete":
        guard args.count >= 4 else { printUsage(); exit(64) }
        var reqArgs = scopeOverrides
        reqArgs["stage_id"] = args[3]
        sendAndPrint(Request(command: "stage.delete", args: reqArgs))
    case "rename":
        // SPEC-014 T071 : `roadie stage rename <id> <new_name>`
        guard args.count >= 5 else { printUsage(); exit(64) }
        var reqArgs = scopeOverrides
        reqArgs["stage_id"] = args[3]
        reqArgs["new_name"] = args[4]
        sendAndPrint(Request(command: "stage.rename", args: reqArgs))
    default:
        // arg2 est le stage_id pour switch. SPEC-019 : honorer aussi les flags
        // `--display <sel>` / `--desktop <id>` pour cibler un scope précis (utile
        // au rail qui envoie le scope de son panel d'origine).
        var reqArgs = scopeOverrides
        reqArgs["stage_id"] = arg2
        sendAndPrint(Request(command: "stage.switch", args: reqArgs))
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
            // SPEC-018 US4 : erreurs de scope override.
            case "unknown_display", "desktop_out_of_range": exit(5)
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
///   roadie events --follow [--types T1,T2]   (contrat events-stream.md)
///   roadie events --follow [--filter <event>]  (legacy, conservé pour compatibilité)
func handleEvents(args: [String]) {
    let isFollow = args.contains("--follow")
    guard isFollow else {
        FileHandle.standardError.write(
            "usage: roadie events --follow [--types desktop_changed,stage_changed]\n"
                .data(using: .utf8) ?? Data())
        exit(2)
    }
    // --types T1,T2 (contrat) ou --filter T (legacy répétable)
    var types: Set<String> = []
    var i = 0
    while i < args.count {
        if args[i] == "--types", i + 1 < args.count {
            let list = args[i + 1].split(separator: ",").map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
            types.formUnion(list)
            i += 2
        } else if args[i] == "--filter", i + 1 < args.count {
            types.insert(args[i + 1])
            i += 2
        } else {
            i += 1
        }
    }
    streamEventsToStdout(types: types)
}

/// Connexion persistante au daemon via le socket Unix : envoie la commande
/// `events.subscribe` avec filtre types optionnel, lit l'ack, puis boucle en
/// relayant chaque ligne reçue vers stdout (auto-flush).
/// Exit 0 sur Ctrl+C, exit 3 si daemon indisponible (contrat events-stream.md).
func streamEventsToStdout(types: Set<String>) {
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
            // POSIX write direct (pas NSFileHandle) : si le pipe parent
            // ferme (SketchyBar quit), write() retourne -1 + EPIPE sans
            // exception ObjC (qui faisait crasher le process — cf crash
            // report roadie-2026-05-02-091514.ips). On exit proprement.
            let ok = line.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> Bool in
                let n = Darwin.write(1, buf.baseAddress, buf.count)
                if n <= 0 { return false }
                let nl: UInt8 = 0x0A
                return Darwin.write(1, [nl], 1) > 0
            }
            if !ok { exitOnDaemonGone.signal(); return }
        }
    }

    connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
            // Envoyer types dans les args si filtre demandé (contrat events-stream.md)
            let reqArgs: [String: String]? = types.isEmpty
                ? nil
                : ["types": types.sorted().joined(separator: ",")]
            let req = Request(command: "events.subscribe", args: reqArgs)
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

/// Formattage texte du tableau `desktop list` (T069, SPEC-011).
/// Colonnes : ID  LABEL  CURRENT  RECENT  WINDOWS  STAGES
/// Schéma JSON daemon : {"desktops": [{id, label, current, recent, windows, stages}, ...]}
func sendDesktopListAsTable() {
    do {
        let response = try SocketClient.send(Request(command: "desktop.list"))
        if response.status == .error {
            OutputFormatter.print(response: response)
            exit(response.errorCode == "multi_desktop_disabled" ? 4 : 1)
        }
        let payload = response.payload ?? [:]
        let desktops = (payload["desktops"]?.value as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
        // Pad manuel : String(format: %s) crash sur String Swift natives (SIGSEGV).
        func pad(_ s: String, _ w: Int) -> String {
            s.count >= w ? s : s + String(repeating: " ", count: w - s.count)
        }
        print("\(pad("ID", 3))  \(pad("LABEL", 8))  \(pad("CURRENT", 7))  \(pad("RECENT", 6))  \(pad("WINDOWS", 7))  STAGES")
        if desktops.isEmpty {
            print("(no desktops detected)")
            return
        }
        for d in desktops {
            let id = (d["id"] as? Int) ?? 0
            let rawLabel = (d["label"] as? String) ?? ""
            let label = rawLabel.isEmpty ? "(none)" : rawLabel
            let isCurrent = (d["current"] as? Bool) == true ? "*" : ""
            let isRecent = (d["recent"] as? Bool) == true ? "*" : ""
            let windows = (d["windows"] as? Int) ?? 0
            let stages = (d["stages"] as? Int) ?? 0
            print("\(pad(String(id), 3))  \(pad(label, 8))  \(pad(isCurrent, 7))  \(pad(isRecent, 6))  \(pad(String(windows), 7))  \(stages)")
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
      roadie daemon status | reload | audit
      roadie focus <left|right|up|down>
      roadie move <left|right|up|down>            # swap avec voisin
      roadie warp <left|right|up|down>            # split la cellule voisine en 2
      roadie resize <left|right|up|down> <delta>
      roadie close                                # ferme la fenêtre frontmost
      roadie toggle <floating|fullscreen|native-fullscreen>
      roadie tiler list                          # liste les stratégies disponibles
      roadie tiler <strategy>                    # change la stratégie active
      roadie stage list [--display <sel>] [--desktop <id>]    # SPEC-018 scope override
      roadie stage <stage_id>                              # switch to stage
      roadie stage assign <stage_id> [--display <sel>] [--desktop <id>]
      roadie stage create <stage_id> <name> [--display <sel>] [--desktop <id>]
      roadie stage delete <stage_id> [--display <sel>] [--desktop <id>]
      roadie stage rename <stage_id> <new_name> [--display <sel>] [--desktop <id>]
      roadie desktop list [--json]               # V2 multi-desktop
      roadie desktop current [--json]
      roadie desktop focus <prev|next|recent|first|last|N|label>
      roadie desktop label <name>                # name vide → retire
      roadie desktop back                        # alias de focus recent
      roadie events --follow [--filter <event>]  # JSON-lines stream sur stdout
      roadie fx status | reload                  # SPEC-004 framework SIP-off opt-in
      roadie window space <prev|next|N|label>    # SPEC-010 déplacer fenêtre cross-desktop
      roadie window display <1..N|prev|next|main> # SPEC-012 déplacer fenêtre vers écran N
      roadie display list [--json]               # SPEC-012 lister les écrans physiques
      roadie display current [--json]            # SPEC-012 écran de la fenêtre frontmost
      roadie display focus <1..N|prev|next|main> # SPEC-012 focus première fenêtre d'un écran
      roadie window stick [true|false]           # SPEC-010 sticky (visible sur tous desktops)
      roadie window unstick                      # alias de stick false
      roadie window pin | unpin                  # SPEC-010 always-on-top
      roadie rail status                         # état du rail (intégré au daemon)
      roadie rail toggle                         # no-op (config via [fx.rail].enabled)
      roadie heal                                # SPEC-025 auto-cicatrisation
      roadie diag [--out <path>]                 # SPEC-025 bundle de diagnostic pour bug report
    """
    FileHandle.standardError.write((usage + "\n").data(using: .utf8) ?? Data())
}

// MARK: - SPEC-025 US7 — `roadie diag` : bundle de diagnostic pour bug report

/// Crée un bundle compressé contenant les logs récents, l'état actuel du daemon,
/// la config TOML, les snapshots stages et les infos système macOS pertinentes.
/// Format : `~/Desktop/roadie-diag-YYYYMMDD-HHMMSS.tar.gz` (ou `--out <path>`).
///
/// Les utilisateurs peuvent attacher ce bundle à un bug report. Le maintainer
/// a tout ce qu'il faut pour reproduire / comprendre sans demander de détails.
///
/// **Anonymisation** : titres de fenêtres et bundle IDs ne sont PAS anonymisés
/// dans cette version — l'utilisateur doit reviewer le bundle avant envoi
/// (mention dans l'output). Future amélioration : flag `--anonymize`.
func handleDiag(args: [String]) {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let timestamp = formatter.string(from: Date())
    let defaultOut = "\(NSHomeDirectory())/Desktop/roadie-diag-\(timestamp).tar.gz"

    var outPath = defaultOut
    if let i = args.firstIndex(of: "--out"), i + 1 < args.count {
        outPath = args[i + 1]
    }

    // Working dir temporaire pour rassembler les fichiers avant tar.
    let workDir = "\(NSTemporaryDirectory())roadie-diag-\(timestamp)"
    try? FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: workDir) }

    let collectedFiles = collectDiagFiles(into: workDir)

    // Tarball gzippé.
    let tarProc = Process()
    tarProc.launchPath = "/usr/bin/tar"
    tarProc.arguments = ["-czf", outPath, "-C", NSTemporaryDirectory(),
                          "roadie-diag-\(timestamp)"]
    do {
        try tarProc.run()
        tarProc.waitUntilExit()
    } catch {
        FileHandle.standardError.write("roadie diag: tar failed: \(error)\n"
            .data(using: .utf8) ?? Data())
        exit(1)
    }
    // SPEC-025 audit fix : check tar terminationStatus. Sans ça, un tar qui échoue
    // (disque plein, permission, etc.) produit un fichier incomplet sans erreur visible.
    guard tarProc.terminationStatus == 0 else {
        FileHandle.standardError.write(
            "roadie diag: tar exit code \(tarProc.terminationStatus) (output may be corrupt)\n"
                .data(using: .utf8) ?? Data())
        exit(1)
    }

    let attrs = try? FileManager.default.attributesOfItem(atPath: outPath)
    let size = (attrs?[.size] as? Int) ?? 0

    let summary = """
    roadie diag — bundle créé : \(outPath)
      taille : \(size) bytes
      contient : \(collectedFiles.count) fichiers (\(collectedFiles.joined(separator: ", ")))

    ⚠ Le bundle peut contenir des informations sensibles (titres de fenêtres,
    bundle IDs d'apps installées). Reviewer avant envoi à un mainteneur tiers.

    Pour ouvrir : tar -xzf \(outPath)
    """
    print(summary)
}

/// Collecte les fichiers utiles pour le diagnostic dans `workDir`.
private func collectDiagFiles(into workDir: String) -> [String] {
    var collected: [String] = []
    let fm = FileManager.default

    // 1. Logs récents (200 dernières lignes).
    let logSrc = "\(NSHomeDirectory())/.local/state/roadies/daemon.log"
    if fm.fileExists(atPath: logSrc) {
        let tailDest = "\(workDir)/daemon.log.tail"
        let proc = Process()
        proc.launchPath = "/bin/sh"
        proc.arguments = ["-c", "tail -200 '\(logSrc)' > '\(tailDest)'"]
        try? proc.run()
        proc.waitUntilExit()
        collected.append("daemon.log.tail")
    }

    // 2. Config TOML.
    let configSrc = "\(NSHomeDirectory())/.config/roadies/roadies.toml"
    if fm.fileExists(atPath: configSrc) {
        try? fm.copyItem(atPath: configSrc, toPath: "\(workDir)/roadies.toml")
        collected.append("roadies.toml")
    }

    // 3. Stages persistés (sans .legacy.* pour réduire la taille).
    let stagesSrc = "\(NSHomeDirectory())/.config/roadies/stages"
    let stagesDest = "\(workDir)/stages"
    if fm.fileExists(atPath: stagesSrc) {
        try? fm.createDirectory(atPath: stagesDest, withIntermediateDirectories: true)
        let cp = Process()
        cp.launchPath = "/bin/sh"
        cp.arguments = ["-c",
            "find '\(stagesSrc)' -name '*.toml' -not -name '*.legacy.*' -print0 | " +
            "xargs -0 -I {} cp -p {} '\(stagesDest)/'"]
        try? cp.run()
        cp.waitUntilExit()
        collected.append("stages/")
    }

    // 4. Output `roadie daemon status --json`, `roadie daemon health`,
    //    `roadie windows list`, `roadie display list` (snapshots état runtime).
    captureCommand("daemon", "status", to: "\(workDir)/status.json", flags: ["--json"])
    captureCommand("daemon", "health", to: "\(workDir)/health.json")
    captureCommand("daemon", "audit", to: "\(workDir)/audit.txt")
    captureCommand("windows", "list", to: "\(workDir)/windows.txt")
    captureCommand("display", "list", to: "\(workDir)/displays.txt")
    captureCommand("stage", "list", to: "\(workDir)/stages-current.txt")
    if fm.fileExists(atPath: "\(workDir)/status.json") { collected.append("status.json") }
    if fm.fileExists(atPath: "\(workDir)/health.json") { collected.append("health.json") }
    if fm.fileExists(atPath: "\(workDir)/audit.txt") { collected.append("audit.txt") }
    if fm.fileExists(atPath: "\(workDir)/windows.txt") { collected.append("windows.txt") }
    if fm.fileExists(atPath: "\(workDir)/displays.txt") { collected.append("displays.txt") }
    if fm.fileExists(atPath: "\(workDir)/stages-current.txt") { collected.append("stages-current.txt") }

    // 5. Infos système macOS (version, displays, codesign daemon).
    let sysInfo = Process()
    sysInfo.launchPath = "/bin/sh"
    sysInfo.arguments = ["-c", """
        {
          echo '=== macOS version ==='; sw_vers
          echo
          echo '=== uname ==='; uname -a
          echo
          echo '=== codesign daemon ==='
          codesign -dv --verbose=2 ~/Applications/roadied.app/Contents/MacOS/roadied 2>&1 | head -10
          echo
          echo '=== launchctl list roadie ==='; launchctl list | grep roadie || true
          echo
          echo '=== pgrep roadied ==='; pgrep -lf roadied || true
        } > '\(workDir)/system-info.txt'
    """]
    try? sysInfo.run()
    sysInfo.waitUntilExit()
    if fm.fileExists(atPath: "\(workDir)/system-info.txt") {
        collected.append("system-info.txt")
    }

    return collected
}

/// Helper : exécute `roadie <obj> <verb> [flags]`, sauve stdout dans `dest`.
private func captureCommand(_ obj: String, _ verb: String, to dest: String,
                             flags: [String] = []) {
    let proc = Process()
    proc.launchPath = "/bin/sh"
    let args = flags.joined(separator: " ")
    proc.arguments = ["-c",
        "timeout 3 ~/.local/bin/roadie \(obj) \(verb) \(args) > '\(dest)' 2>&1 || true"]
    try? proc.run()
    proc.waitUntilExit()
}
