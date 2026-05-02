import Foundation
import RoadieCore
import RoadieTiler
import RoadieStagePlugin
import RoadieFXCore
import RoadieDesktops

/// SPEC-010 : OSAXBridge partagé entre le daemon et les modules FX. Permet au
/// daemon d'envoyer directement des commandes osax (move_window_to_space,
/// set_sticky, set_level) sans passer par un module FX intermédiaire.
/// Note : RoadieFXCore est lié dynamiquement (target `.dynamicLibrary`), donc
/// le daemon ne lie aucun symbole CGS d'écriture statiquement (SC-007 préservé).
public enum DaemonOSAXBridge {
    public static let shared: OSAXBridge = OSAXBridge()
}

/// Routeur des commandes reçues sur le socket.
@MainActor
enum CommandRouter {
    static func route(_ request: Request, daemon: Daemon) async -> Response {
        switch request.command {
        case "windows.list":
            let payload: [String: AnyCodable] = [
                "windows": AnyCodable(daemon.registry.allWindows.map { state -> [String: Any] in
                    [
                        "id": Int(state.cgWindowID),
                        "pid": Int(state.pid),
                        "bundle": state.bundleID,
                        "title": state.title,
                        "frame": [Int(state.frame.origin.x), Int(state.frame.origin.y),
                                  Int(state.frame.size.width), Int(state.frame.size.height)],
                        "subrole": state.subrole.rawValue,
                        "is_tiled": state.isTileable,
                        "is_focused": daemon.registry.focusedWindowID == state.cgWindowID,
                        "stage": state.stageID?.value ?? "",
                    ]
                }),
            ]
            return .success(payload)

        case "daemon.status":
            let payload: [String: AnyCodable] = [
                "version": AnyCodable("0.1.0"),
                "tiled_windows": AnyCodable(daemon.registry.tileableWindows.count),
                "tiler_strategy": AnyCodable(daemon.layoutEngine.workspace.tilerStrategy.rawValue),
                "stage_manager_enabled": AnyCodable(daemon.config.stageManager.enabled),
                "current_stage": AnyCodable(daemon.stageManager?.currentStageID?.value ?? ""),
            ]
            return .success(payload)

        case "daemon.reload":
            do {
                let newConfig = try ConfigLoader.load()
                daemon.config = newConfig
                if let level = LogLevel(rawValue: newConfig.daemon.logLevel) {
                    Logger.shared.setMinLevel(level)
                }
                logInfo("config reloaded")
                return .success()
            } catch {
                return .error(.invalidArgument, "config reload failed: \(error)")
            }

        case "focus":
            guard let dirStr = request.args?["direction"],
                  let direction = Direction(rawValue: dirStr) else {
                return .error(.invalidArgument, "missing or invalid direction")
            }
            guard let from = daemon.registry.focusedWindowID else {
                return .error(.windowNotFound, "no focused window")
            }
            guard let neighbor = daemon.layoutEngine.focusNeighbor(of: from, direction: direction) else {
                return .error(.windowNotFound, "no neighbor in direction \(direction.rawValue)")
            }
            daemon.focusManager.setFocus(to: neighbor)
            return .success(["focused": AnyCodable(Int(neighbor))])

        case "move":
            guard let dirStr = request.args?["direction"],
                  let direction = Direction(rawValue: dirStr) else {
                return .error(.invalidArgument, "missing or invalid direction")
            }
            guard let wid = daemon.registry.focusedWindowID else {
                return .error(.windowNotFound, "no focused window")
            }
            let moved = daemon.layoutEngine.move(wid, direction: direction)
            daemon.applyLayout()
            return .success(["moved": AnyCodable(moved)])

        case "resize":
            guard let dirStr = request.args?["direction"],
                  let direction = Direction(rawValue: dirStr),
                  let deltaStr = request.args?["delta"],
                  let delta = Double(deltaStr) else {
                return .error(.invalidArgument, "missing or invalid args")
            }
            guard let wid = daemon.registry.focusedWindowID else {
                return .error(.windowNotFound, "no focused window")
            }
            daemon.layoutEngine.resize(wid, direction: direction, delta: CGFloat(delta))
            daemon.applyLayout()
            return .success()

        case "tiler.set":
            guard let strategyStr = request.args?["strategy"] else {
                return .error(.invalidArgument, "missing strategy argument")
            }
            let strategy = TilerStrategy(strategyStr)
            do {
                try daemon.layoutEngine.setStrategy(strategy)
            } catch {
                return .error(.invalidArgument, "\(error)")
            }
            daemon.applyLayout()
            return .success(["strategy": AnyCodable(strategy.rawValue)])

        case "tiler.list":
            return .success([
                "current": AnyCodable(daemon.layoutEngine.workspace.tilerStrategy.rawValue),
                "available": AnyCodable(TilerRegistry.availableStrategies.map(\.rawValue)),
            ])

        case "tree.dump":
            // Représentation textuelle de l'arbre pour diagnostic.
            return .success([
                "tree": AnyCodable(dumpTree(daemon.layoutEngine.workspace.rootNode)),
            ])

        case "balance":
            // Reset les adaptiveWeight de tout l'arbre à 1.0 (équivalent yabai --balance).
            balanceWeights(daemon.layoutEngine.workspace.rootNode)
            daemon.applyLayout()
            return .success()

        case "rebuild":
            // Reconstruit l'arbre BSP depuis les leaves existantes.
            // Utile si le tree s'est aplati (insertions avec target=nil successives).
            daemon.layoutEngine.rebuildTree()
            daemon.applyLayout()
            return .success()

        case "stage.list":
            guard let sm = daemon.stageManager else {
                return .error(.stageManagerDisabled, "stage manager disabled in config")
            }
            let stages = sm.stages.values.map { stage -> [String: Any] in
                [
                    "id": stage.id.value,
                    "display_name": stage.displayName,
                    "window_count": stage.memberWindows.count,
                ]
            }
            return .success([
                "current": AnyCodable(sm.currentStageID?.value ?? ""),
                "stages": AnyCodable(stages),
            ])

        case "stage.switch":
            guard let sm = daemon.stageManager else {
                return .error(.stageManagerDisabled, "stage manager disabled in config")
            }
            guard let stageStr = request.args?["stage_id"] else {
                return .error(.invalidArgument, "missing stage_id")
            }
            let stageID = StageID(stageStr)
            guard sm.stages[stageID] != nil else {
                return .error(.unknownStage, "unknown stage \(stageStr)")
            }
            sm.switchTo(stageID: stageID)
            return .success(["current": AnyCodable(stageID.value)])

        case "stage.assign":
            guard let sm = daemon.stageManager else {
                return .error(.stageManagerDisabled, "stage manager disabled in config")
            }
            guard let stageStr = request.args?["stage_id"] else {
                return .error(.invalidArgument, "missing stage_id")
            }
            let stageID = StageID(stageStr)
            guard let wid = daemon.registry.focusedWindowID else {
                return .error(.windowNotFound, "no focused window to assign")
            }
            // Lazy stages : auto-créer le stage s'il n'existe pas. Évite à
            // l'utilisateur de devoir `stage create N <name>` avant d'assigner.
            if sm.stages[stageID] == nil {
                _ = sm.createStage(id: stageID, displayName: "stage \(stageStr)")
            }
            sm.assign(wid: wid, to: stageID)
            return .success(["created": AnyCodable(true), "stage_id": AnyCodable(stageStr)])

        case "stage.create":
            guard let sm = daemon.stageManager else {
                return .error(.stageManagerDisabled, "stage manager disabled in config")
            }
            guard let stageStr = request.args?["stage_id"],
                  let displayName = request.args?["display_name"] else {
                return .error(.invalidArgument, "missing stage_id or display_name")
            }
            let stageID = StageID(stageStr)
            if sm.stages[stageID] != nil {
                return .error(.invalidArgument, "stage already exists")
            }
            _ = sm.createStage(id: stageID, displayName: displayName)
            return .success(["created": AnyCodable(stageID.value)])

        case "stage.delete":
            guard let sm = daemon.stageManager else {
                return .error(.stageManagerDisabled, "stage manager disabled in config")
            }
            guard let stageStr = request.args?["stage_id"] else {
                return .error(.invalidArgument, "missing stage_id")
            }
            if stageStr == "1" {
                return .error(.invalidArgument, "cannot delete default stage 1")
            }
            sm.deleteStage(id: StageID(stageStr))
            return .success()

        case "fx.status":
            // SPEC-004 : retourne l'état SIP + osax + modules chargés.
            // Toujours répond, même si fxLoader nil (= aucun module, vanilla).
            // - sip : état csrutil
            // - osax : "loaded" si le socket /var/tmp/roadied-osax.sock existe
            //   (= scripting addition active dans Dock), "absent" sinon
            // - modules : "name@version" séparés par virgule, format plat pour
            //   éviter le bug d'affichage CLI sur les arrays de dicts AnyCodable
            let sipState = FXLoader.detectSIP().rawValue
            let osaxConnected = FileManager.default.fileExists(atPath: "/var/tmp/roadied-osax.sock")
            let osaxState = osaxConnected ? "loaded" : "absent"
            let modulesList = (daemon.fxLoader?.modules ?? [])
                .map { "\($0.name)@\($0.version)" }
                .joined(separator: ", ")
            return .success([
                "sip": AnyCodable(sipState),
                "osax": AnyCodable(osaxState),
                "modules": AnyCodable(modulesList.isEmpty ? "[]" : "[\(modulesList)]")
            ])

        case "fx.reload":
            // Recharge tous les modules : unload + reload.
            // Best-effort : si dlclose échoue ou re-load échoue, log + continue.
            guard let loader = daemon.fxLoader else {
                return .error(.invalidArgument, "fx loader not initialized")
            }
            loader.unloadAll()
            let cfg = FXConfig.load(fromTOML: (try? String(contentsOfFile: ConfigLoader.defaultConfigPath(), encoding: .utf8)) ?? "")
            let reloaded = loader.loadAll(config: cfg)
            return .success(["reloaded": AnyCodable(reloaded.count)])

        case "window.stick":
            // SPEC-010 : pose ou retire le sticky flag (visible sur tous desktops).
            guard let frontmost = daemon.registry.focusedWindowID else {
                return .error(.windowNotFound, "no frontmost window")
            }
            let sticky = (request.args?["sticky"] ?? "true") == "true"
            let result = await DaemonOSAXBridge.shared.send(.setSticky(wid: frontmost, sticky: sticky))
            if !result.isOK {
                return .error(.internalError, "osax set_sticky failed")
            }
            return .success(["wid": AnyCodable(Int(frontmost)), "sticky": AnyCodable(sticky)])

        case "window.pin":
            // SPEC-010 : pose ou retire always-on-top (level 24 / 0).
            guard let frontmost = daemon.registry.focusedWindowID else {
                return .error(.windowNotFound, "no frontmost window")
            }
            let pinned = (request.args?["pinned"] ?? "true") == "true"
            let level = pinned ? 24 : 0
            let result = await DaemonOSAXBridge.shared.send(.setLevel(wid: frontmost, level: level))
            if !result.isOK {
                return .error(.internalError, "osax set_level failed")
            }
            return .success(["wid": AnyCodable(Int(frontmost)), "pinned": AnyCodable(pinned)])

        // MARK: - SPEC-012 window.display

        case "window.display":
            return await handleWindowDisplay(request: request, daemon: daemon)

        // MARK: - SPEC-011 desktop.*

        case "desktop.list":
            return await handleDesktopList(daemon: daemon)

        case "desktop.current":
            return await handleDesktopCurrent(daemon: daemon)

        case "desktop.focus":
            guard let selector = request.args?["selector"] else {
                return .error(.invalidArgument, "missing selector argument")
            }
            return await handleDesktopFocus(selector: selector, daemon: daemon)

        case "desktop.label":
            let name = request.args?["name"] ?? ""
            return await handleDesktopLabel(name: name, daemon: daemon)

        case "desktop.back":
            return await handleDesktopBack(daemon: daemon)

        default:
            return .error(.invalidArgument, "unknown command: \(request.command)")
        }
    }

    // MARK: - Desktop handlers (SPEC-011)

    private static func handleDesktopList(daemon: Daemon) async -> Response {
        guard daemon.config.desktops.enabled else {
            return .error(.multiDesktopDisabled,
                          "multi_desktop disabled, set [desktops] enabled = true in roadies.toml")
        }
        guard let registry = daemon.desktopRegistry else {
            return .error(.internalError, "desktop registry not initialized")
        }
        let currentID = await registry.currentID
        let recentID = await registry.recentID
        let allDesktops = await registry.allDesktops()
        let items: [[String: Any]] = allDesktops.map { d in
            [
                "id": d.id,
                "label": d.label ?? "",
                "current": d.id == currentID,
                "recent": d.id == recentID,
                "windows": d.windows.count,
                "stages": d.stages.count,
            ]
        }
        return .success(["desktops": AnyCodable(items)])
    }

    private static func handleDesktopCurrent(daemon: Daemon) async -> Response {
        guard daemon.config.desktops.enabled else {
            return .error(.multiDesktopDisabled,
                          "multi_desktop disabled, set [desktops] enabled = true in roadies.toml")
        }
        guard let registry = daemon.desktopRegistry else {
            return .error(.internalError, "desktop registry not initialized")
        }
        let currentID = await registry.currentID
        let desktop = await registry.desktop(id: currentID)
        return .success([
            "id": AnyCodable(currentID),
            "label": AnyCodable(desktop?.label ?? ""),
            "active_stage_id": AnyCodable(desktop?.activeStageID ?? 1),
            "windows": AnyCodable(desktop?.windows.count ?? 0),
        ])
    }

    private static func handleDesktopFocus(selector: String, daemon: Daemon) async -> Response {
        guard daemon.config.desktops.enabled else {
            return .error(.multiDesktopDisabled,
                          "multi_desktop disabled, set [desktops] enabled = true in roadies.toml")
        }
        guard let registry = daemon.desktopRegistry,
              let switcher = daemon.desktopSwitcher else {
            return .error(.internalError, "desktop subsystem not initialized")
        }
        let previousID = await registry.currentID
        guard let targetID = await resolveSelector(
            selector, registry: registry, count: daemon.config.desktops.count) else {
            return .error(.unknownDesktop, "unknown desktop selector \"\(selector)\"")
        }
        let wasNoop = targetID == previousID && !daemon.config.desktops.backAndForth
        do {
            try await switcher.switch(to: targetID)
        } catch DesktopError.unknownDesktop {
            return .error(.unknownDesktop, "unknown desktop selector \"\(selector)\"")
        } catch {
            return .error(.internalError, "\(error)")
        }
        let currentID = await registry.currentID
        return .success([
            "current_id": AnyCodable(currentID),
            "previous_id": AnyCodable(previousID),
            "event_emitted": AnyCodable(!wasNoop && currentID != previousID),
        ])
    }

    private static func handleDesktopLabel(name: String, daemon: Daemon) async -> Response {
        guard daemon.config.desktops.enabled else {
            return .error(.multiDesktopDisabled,
                          "multi_desktop disabled, set [desktops] enabled = true in roadies.toml")
        }
        guard let registry = daemon.desktopRegistry else {
            return .error(.internalError, "desktop registry not initialized")
        }
        // Validation via Validation.swift (T043, US4)
        if !name.isEmpty {
            guard isValidDesktopLabel(name) else {
                return .error(.invalidArgument,
                              "invalid_label: alphanumeric + '-_' only, max 32 chars")
            }
            guard !isReservedDesktopLabel(name) else {
                return .error(.invalidArgument, "invalid_label: \"\(name)\" is reserved")
            }
        }
        let currentID = await registry.currentID
        do {
            try await registry.setLabel(name.isEmpty ? nil : name, for: currentID)
        } catch {
            return .error(.internalError, "save failed: \(error)")
        }
        let msg = name.isEmpty
            ? "desktop \(currentID) label removed"
            : "desktop \(currentID) labeled as \"\(name)\""
        return .success(["message": AnyCodable(msg), "id": AnyCodable(currentID)])
    }

    private static func handleDesktopBack(daemon: Daemon) async -> Response {
        guard daemon.config.desktops.enabled else {
            return .error(.multiDesktopDisabled,
                          "multi_desktop disabled, set [desktops] enabled = true in roadies.toml")
        }
        guard let registry = daemon.desktopRegistry,
              let switcher = daemon.desktopSwitcher else {
            return .error(.internalError, "desktop subsystem not initialized")
        }
        let previousID = await registry.currentID
        do {
            try await switcher.back()
        } catch DesktopError.noRecentDesktop {
            return .error(.invalidArgument, "no recent desktop")
        } catch {
            return .error(.internalError, "\(error)")
        }
        let currentID = await registry.currentID
        return .success([
            "current_id": AnyCodable(currentID),
            "previous_id": AnyCodable(previousID),
        ])
    }

}
