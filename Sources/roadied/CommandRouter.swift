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

        default:
            return .error(.invalidArgument, "unknown command: \(request.command)")
        }
    }
}
