import Foundation
import RoadieCore
import RoadieTiler
import RoadieStagePlugin

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
                try newConfig.validateDesktopRules()
                daemon.config = newConfig
                if let level = LogLevel(rawValue: newConfig.daemon.logLevel) {
                    Logger.shared.setMinLevel(level)
                }
                // V2 — reload à chaud du multi-desktop (FR-019). Si l'utilisateur
                // active multi_desktop.enabled à chaud, on instancie DesktopManager
                // et on déclenche la transition initiale. Si désactive, on coupe.
                daemon.reconfigureMultiDesktop(newConfig: newConfig)
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
            guard sm.stages[stageID] != nil else {
                return .error(.unknownStage, "unknown stage \(stageStr)")
            }
            guard let wid = daemon.registry.focusedWindowID else {
                return .error(.windowNotFound, "no focused window to assign")
            }
            sm.assign(wid: wid, to: stageID)
            return .success()

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
            sm.deleteStage(id: StageID(stageStr))
            return .success()

        // MARK: - V2 desktop.* (FR-009..FR-013)

        case "desktop.list":
            // Lecture seule : autorisée même quand multi_desktop.enabled=false (FR-009 commentaire contracts).
            let dm = daemon.desktopManager
            let desktops = dm?.listDesktops() ?? []
            let stagesPerDesktop = countStagesPerDesktop(in: dm?.currentUUID, daemon: daemon)
            let allWindows = daemon.registry.allWindows
            var payload: [[String: Any]] = []
            for info in desktops {
                let stageCount: Int = stagesPerDesktop[info.uuid] ?? 0
                let windowCount: Int = allWindows.filter { $0.desktopUUID == info.uuid }.count
                let entry: [String: Any] = [
                    "index": info.index,
                    "uuid": info.uuid,
                    "label": info.label ?? "",
                    "stage_count": stageCount,
                    "window_count": windowCount,
                ]
                payload.append(entry)
            }
            return .success([
                "current_uuid": AnyCodable(dm?.currentUUID ?? ""),
                "desktops": AnyCodable(payload),
            ])

        case "desktop.current":
            guard let dm = daemon.desktopManager else {
                return .error(.multiDesktopDisabled, "multi_desktop disabled, set enabled=true in roadies.toml")
            }
            guard let cur = dm.currentUUID,
                  let info = dm.listDesktops().first(where: { $0.uuid == cur }) else {
                return .error(.unknownDesktop, "no current desktop detected")
            }
            return .success([
                "uuid": AnyCodable(info.uuid),
                "index": AnyCodable(info.index),
                "label": AnyCodable(info.label ?? ""),
                "current_stage_id": AnyCodable(daemon.stageManager?.currentStageID?.value ?? ""),
                "stage_count": AnyCodable(daemon.stageManager?.stages.count ?? 0),
                "window_count": AnyCodable(daemon.registry.allWindows.filter { $0.desktopUUID == cur }.count),
                "tiler_strategy": AnyCodable(daemon.layoutEngine.workspace.tilerStrategy.rawValue),
            ])

        case "desktop.focus":
            guard let dm = daemon.desktopManager else {
                return .error(.multiDesktopDisabled, "multi_desktop disabled")
            }
            guard let selector = request.args?["selector"] else {
                return .error(.invalidArgument, "missing selector")
            }
            guard let target = dm.resolveSelector(selector) else {
                return .error(.unknownDesktop, "unknown desktop selector \"\(selector)\"")
            }
            dm.focus(uuid: target)
            return .success([
                "current_uuid": AnyCodable(dm.currentUUID ?? ""),
                "target_uuid": AnyCodable(target),
            ])

        case "desktop.label":
            guard let dm = daemon.desktopManager else {
                return .error(.multiDesktopDisabled, "multi_desktop disabled")
            }
            guard let cur = dm.currentUUID else {
                return .error(.unknownDesktop, "no current desktop")
            }
            let raw = request.args?["name"] ?? ""
            // Vide → retire le label. Sinon valider format (alphanumérique + - _ ; max 32).
            if raw.isEmpty {
                dm.setLabel(nil, for: cur)
            } else {
                guard isValidLabel(raw) else {
                    return .error(.invalidArgument, "invalid label: alphanumeric + '-_' only, max 32 chars")
                }
                dm.setLabel(raw, for: cur)
            }
            // F9 fix : persister le label sur disque dans DesktopState pour survivre au redémarrage.
            persistDesktopLabel(uuid: cur, label: raw.isEmpty ? nil : raw, daemon: daemon)
            return .success(["uuid": AnyCodable(cur), "label": AnyCodable(raw)])

        case "desktop.back":
            guard let dm = daemon.desktopManager else {
                return .error(.multiDesktopDisabled, "multi_desktop disabled")
            }
            guard let target = dm.resolveSelector("recent") else {
                return .error(.unknownDesktop, "no recent desktop")
            }
            dm.focus(uuid: target)
            return .success(["target_uuid": AnyCodable(target)])

        default:
            return .error(.invalidArgument, "unknown command: \(request.command)")
        }
    }

    /// Stage_count par UUID : actuellement, le `stageManager` ne tient qu'un seul desktop
    /// chargé en mémoire (le courant) pour l'empreinte mémoire constante (research.md
    /// décision 3). Le count des autres desktops est lu depuis disque (lazy stat).
    private static func countStagesPerDesktop(in currentUUID: String?, daemon: Daemon) -> [String: Int] {
        var result: [String: Int] = [:]
        if let cur = currentUUID, let sm = daemon.stageManager {
            result[cur] = sm.stages.count
        }
        // Pour les desktops non actifs, lire le dossier stages persistant (count des .toml -1 pour active.toml).
        let home = NSString(string: "~").expandingTildeInPath
        let root = "\(home)/.config/roadies/desktops"
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: root) {
            for entry in entries where result[entry] == nil {
                let stagesDir = "\(root)/\(entry)/stages"
                if let files = try? FileManager.default.contentsOfDirectory(atPath: stagesDir) {
                    let count = files.filter { $0.hasSuffix(".toml") && $0 != "active.toml" }.count
                    result[entry] = count
                }
            }
        }
        return result
    }

    /// Validation d'un label desktop (FR-012) : alphanumérique + '-_', max 32 chars, non vide.
    private static func isValidLabel(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 32 else { return false }
        let allowed: Set<Character> = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return s.allSatisfy { allowed.contains($0) }
    }

    /// Persiste le label desktop dans `~/.config/roadies/desktops/<uuid>/label.txt`
    /// (fichier minimal pour éviter de toucher au DesktopState complet à chaque label).
    /// Le label est rechargé au boot par DesktopManager (à câbler en V2.1, pour l'instant
    /// la persistance est indépendante du DesktopState principal).
    private static func persistDesktopLabel(uuid: String, label: String?, daemon: Daemon) {
        let home = NSString(string: "~").expandingTildeInPath
        let dir = "\(home)/.config/roadies/desktops/\(uuid)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = "\(dir)/label.txt"
        if let l = label {
            try? l.write(toFile: path, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
