import Foundation
import AppKit
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

        case "warp":
            guard let dirStr = request.args?["direction"],
                  let direction = Direction(rawValue: dirStr) else {
                return .error(.invalidArgument, "missing or invalid direction")
            }
            guard let wid = daemon.registry.focusedWindowID else {
                return .error(.windowNotFound, "no focused window")
            }
            let warped = daemon.layoutEngine.warp(wid, direction: direction)
            daemon.applyLayout()
            return .success(["warped": AnyCodable(warped)])

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

        case "window.close":
            guard let wid = daemon.registry.focusedWindowID,
                  let element = daemon.registry.axElement(for: wid) else {
                return .error(.windowNotFound, "no focused window")
            }
            let ok = AXReader.close(element)
            return .success(["closed": AnyCodable(ok)])

        case "window.toggle.floating":
            guard let wid = daemon.registry.focusedWindowID,
                  let state = daemon.registry.get(wid) else {
                return .error(.windowNotFound, "no focused window")
            }
            let newFloating = !state.isFloating
            daemon.registry.update(wid) { $0.isFloating = newFloating }
            if newFloating {
                daemon.layoutEngine.removeWindow(wid)
            } else {
                daemon.layoutEngine.insertWindow(wid, focusedID: nil)
            }
            daemon.applyLayout()
            return .success(["floating": AnyCodable(newFloating)])

        case "window.toggle.fullscreen":
            // Zoom-fullscreen yabai-style : la fenêtre prend tout le visibleFrame
            // du display courant en restant dans la même Space. Pas de toucher AX.
            guard let wid = daemon.registry.focusedWindowID,
                  let state = daemon.registry.get(wid),
                  let element = daemon.registry.axElement(for: wid) else {
                return .error(.windowNotFound, "no focused window")
            }
            let newZoom = !state.isZoomed
            if newZoom {
                // Sauvegarder la frame actuelle, calculer le visibleFrame AX du display.
                let center = CGPoint(x: state.frame.midX, y: state.frame.midY)
                let displayID = daemon.layoutEngine.displayIDContainingPoint(center) ?? CGMainDisplayID()
                guard let dReg = daemon.displayRegistry else {
                    return .error(.invalidArgument, "no display registry")
                }
                let displays = await dReg.displays
                guard let dst = displays.first(where: { $0.id == displayID }) else {
                    return .error(.invalidArgument, "display not found")
                }
                let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height ?? 0
                let vfNS = dst.visibleFrame
                let vfAX = CGRect(x: vfNS.origin.x,
                                  y: primaryHeight - vfNS.origin.y - vfNS.height,
                                  width: vfNS.width, height: vfNS.height)
                daemon.registry.update(wid) {
                    $0.preZoomFrame = state.frame
                    $0.isZoomed = true
                }
                AXReader.setBounds(element, frame: vfAX)
            } else {
                if let pre = state.preZoomFrame {
                    AXReader.setBounds(element, frame: pre)
                }
                daemon.registry.update(wid) {
                    $0.isZoomed = false
                    $0.preZoomFrame = nil
                }
                daemon.applyLayout()
            }
            return .success(["zoomed": AnyCodable(newZoom)])

        case "window.toggle.native-fullscreen":
            guard let wid = daemon.registry.focusedWindowID,
                  let element = daemon.registry.axElement(for: wid),
                  let state = daemon.registry.get(wid) else {
                return .error(.windowNotFound, "no focused window")
            }
            let isFs = AXReader.isFullscreen(element)
            AXReader.setFullscreen(element, !isFs)
            daemon.registry.update(wid) { $0.isFullscreen = !isFs }
            _ = state
            return .success(["native_fullscreen": AnyCodable(!isFs)])

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

        // MARK: - SPEC-012 window.display + display.*

        case "window.display":
            return await handleWindowDisplay(request: request, daemon: daemon)

        case "window.desktop":
            return await handleWindowDesktop(request: request, daemon: daemon)

        case "display.list":
            return await handleDisplayList(daemon: daemon)

        case "display.current":
            return await handleDisplayCurrent(daemon: daemon)

        case "display.focus":
            guard let selector = request.args?["selector"] else {
                return .error(.invalidArgument, "missing selector")
            }
            return await handleDisplayFocus(selector: selector, daemon: daemon)

        // MARK: - SPEC-011 desktop.*

        case "desktop.list":
            return await handleDesktopList(daemon: daemon)

        case "desktop.current":
            return await handleDesktopCurrent(daemon: daemon)

        case "desktop.focus":
            guard let selector = request.args?["selector"] else {
                return .error(.invalidArgument, "missing selector argument")
            }
            // SPEC-013 : en mode per_display, scoper le hide/show au display de la
            // frontmost. En mode global, fallback sur le path V2 (DesktopSwitcher).
            let mode = await daemon.desktopRegistry?.mode ?? .global
            if mode == .perDisplay {
                return await handleDesktopFocusPerDisplay(selector: selector, daemon: daemon)
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
        let mode = await registry.mode
        let currentByDisplay = await registry.currentByDisplay
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
        // SPEC-013 FR-010 : exposer le mode + la map per-display.
        let perDisplay: [[String: Any]] = currentByDisplay
            .sorted(by: { $0.key < $1.key })
            .map { (k, v) in ["display_id": Int(k), "current": v] }
        return .success([
            "desktops": AnyCodable(items),
            "mode": AnyCodable(mode.rawValue),
            "current_by_display": AnyCodable(perDisplay),
        ])
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
        let mode = await registry.mode
        // SPEC-013 FR-009 : en perDisplay, retourner aussi le current du display
        // de la frontmost.
        var displayID: CGDirectDisplayID? = nil
        var displayCurrent: Int? = nil
        if mode == .perDisplay,
           let frontmost = daemon.registry.focusedWindowID,
           let state = daemon.registry.get(frontmost) {
            let center = CGPoint(x: state.frame.midX, y: state.frame.midY)
            displayID = daemon.layoutEngine.displayIDContainingPoint(center)
            if let did = displayID {
                displayCurrent = await registry.currentID(for: did)
            }
        }
        let desktop = await registry.desktop(id: displayCurrent ?? currentID)
        var payload: [String: AnyCodable] = [
            "id": AnyCodable(displayCurrent ?? currentID),
            "label": AnyCodable(desktop?.label ?? ""),
            "active_stage_id": AnyCodable(desktop?.activeStageID ?? 1),
            "windows": AnyCodable(desktop?.windows.count ?? 0),
            "mode": AnyCodable(mode.rawValue),
        ]
        if let did = displayID {
            payload["display_id"] = AnyCodable(Int(did))
        }
        return .success(payload)
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

    /// SPEC-013 : envoyer la fenêtre frontmost vers desktop N du display courant.
    /// Met à jour state.desktopID. Si N != current desktop du display, hide
    /// la fenêtre offscreen. Sinon (la fenêtre reste visible sur le desktop courant),
    /// re-applique le layout.
    private static func handleWindowDesktop(request: Request, daemon: Daemon) async -> Response {
        guard daemon.config.desktops.enabled else {
            return .error(.multiDesktopDisabled, "multi_desktop disabled")
        }
        guard let registry = daemon.desktopRegistry else {
            return .error(.internalError, "desktop registry not initialized")
        }
        guard let selectorStr = request.args?["selector"],
              let targetID = Int(selectorStr) else {
            return .error(.invalidArgument, "missing or invalid selector")
        }
        guard targetID >= 1 && targetID <= daemon.config.desktops.count else {
            return .error(.invalidArgument, "desktop \(targetID) out of range")
        }
        guard let wid = daemon.registry.focusedWindowID,
              let state = daemon.registry.get(wid) else {
            return .error(.windowNotFound, "no focused window")
        }
        // Display de la fenêtre via son centre (frame réel ou expectedFrame fallback).
        let center = CGPoint(x: state.frame.midX, y: state.frame.midY)
        var displayID = daemon.layoutEngine.displayIDContainingPoint(center)
        if displayID == nil && state.expectedFrame != .zero {
            let expCenter = CGPoint(x: state.expectedFrame.midX, y: state.expectedFrame.midY)
            displayID = daemon.layoutEngine.displayIDContainingPoint(expCenter)
        }
        let resolvedDisplayID = displayID ?? CGMainDisplayID()
        let currentOnDisplay = await registry.currentID(for: resolvedDisplayID)
        // Mise à jour du desktopID.
        daemon.registry.update(wid) { $0.desktopID = targetID }
        // Si target != current du display, hide. Sinon, applyLayout.
        if targetID != currentOnDisplay {
            if state.isTileable {
                daemon.layoutEngine.setLeafVisible(wid, false)
            }
            HideStrategyImpl.hide(wid, registry: daemon.registry,
                                  strategy: daemon.config.stageManager.hideStrategy)
        }
        daemon.applyLayout()
        logInfo("window.desktop: window assigned", [
            "wid": String(wid),
            "desktop": String(targetID),
            "display_id": String(resolvedDisplayID),
            "current": String(currentOnDisplay),
        ])
        return .success([
            "cgwid": AnyCodable(Int(wid)),
            "desktop": AnyCodable(targetID),
            "display_id": AnyCodable(Int(resolvedDisplayID)),
            "hidden": AnyCodable(targetID != currentOnDisplay),
        ])
    }

    /// SPEC-013 T010-T011 : focus desktop scopé au display de la frontmost.
    /// Cache uniquement les fenêtres dont le centre tombe sur ce display ; restaure
    /// celles dont le desktopID == targetID. Les autres displays sont intouchés.
    private static func handleDesktopFocusPerDisplay(selector: String,
                                                     daemon: Daemon) async -> Response {
        logInfo("desktop.focus per_display ENTER", ["selector": selector])
        defer { logInfo("desktop.focus per_display EXIT", ["selector": selector]) }
        guard daemon.config.desktops.enabled else {
            return .error(.multiDesktopDisabled,
                          "multi_desktop disabled, set [desktops] enabled = true in roadies.toml")
        }
        guard let registry = daemon.desktopRegistry else {
            return .error(.internalError, "desktop registry not initialized")
        }
        // SPEC-013 fix CRUCIAL : utiliser la position du CURSEUR comme source
        // de vérité (= où l'utilisateur regarde RÉELLEMENT au moment du
        // raccourci), pas la frontmost AX qui peut avoir transité ailleurs
        // entre le clic user et le traitement de la commande. C'est le pattern
        // yabai/AeroSpace. Fallback frontmost si curseur sur aucun display.
        var targetDisplayID: CGDirectDisplayID = CGMainDisplayID()
        let mouseLoc = NSEvent.mouseLocation
        if let hit = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) }),
           let did = hit.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
               as? CGDirectDisplayID {
            targetDisplayID = did
        } else if let frontmost = daemon.registry.focusedWindowID,
                  let state = daemon.registry.get(frontmost) {
            // Fallback secondaire : centre de la frontmost.
            let center = CGPoint(x: state.frame.midX, y: state.frame.midY)
            if let did = daemon.layoutEngine.displayIDContainingPoint(center) {
                targetDisplayID = did
            }
        }
        let previousID = await registry.currentID(for: targetDisplayID)
        guard let targetID = await resolveSelector(
            selector, registry: registry, count: daemon.config.desktops.count) else {
            return .error(.unknownDesktop, "unknown desktop selector \"\(selector)\"")
        }
        // Same desktop + back-and-forth → bascule vers recent **du display ciblé**
        // (pas le recent global, qui pourrait pointer sur un desktop d'un autre
        // écran et faire basculer le mauvais display).
        var resolvedTarget = targetID
        if resolvedTarget == previousID {
            if daemon.config.desktops.backAndForth,
               let recent = await registry.recentID(for: targetDisplayID) {
                resolvedTarget = recent
            } else {
                // No-op
                return .success([
                    "current_id": AnyCodable(previousID),
                    "previous_id": AnyCodable(previousID),
                    "display_id": AnyCodable(Int(targetDisplayID)),
                    "event_emitted": AnyCodable(false),
                ])
            }
        }
        logInfo("desktop.focus per_display resolved", [
            "target_display": String(targetDisplayID),
            "previous_id": String(previousID),
            "resolved_target": String(resolvedTarget),
        ])
        // Mute le current du display ciblé.
        await registry.setCurrent(resolvedTarget, on: targetDisplayID)

        // SPEC-013 T034/FR-016 : persister le current per-display sur disque pour
        // restoration au rebranchement.
        if let displays = await daemon.displayRegistry?.displays,
           let dst = displays.first(where: { $0.id == targetDisplayID }),
           !dst.uuid.isEmpty {
            let configDir = URL(fileURLWithPath:
                (NSString(string: "~/.config/roadies").expandingTildeInPath as String))
            DesktopPersistence.saveCurrent(
                configDir: configDir,
                displayUUID: dst.uuid,
                currentID: resolvedTarget
            )
            // Snapshot des fenêtres du display ciblé pour le desktop courant.
            let snapshots: [DesktopPersistence.WindowSnapshot] = daemon.registry.allWindows
                .compactMap { state in
                    let center = CGPoint(x: state.frame.midX, y: state.frame.midY)
                    guard let did = daemon.layoutEngine.displayIDContainingPoint(center),
                          did == targetDisplayID,
                          state.desktopID == resolvedTarget else { return nil }
                    return DesktopPersistence.WindowSnapshot(
                        cgwid: UInt32(state.cgWindowID),
                        bundleID: state.bundleID,
                        titlePrefix: String(state.title.prefix(80)),
                        expectedFrame: state.frame
                    )
                }
            DesktopPersistence.saveDesktopWindows(
                configDir: configDir,
                displayUUID: dst.uuid,
                desktopID: resolvedTarget,
                windows: snapshots
            )
        }

        // Hide/show ciblé : pour chaque fenêtre du registry, si son centre tombe
        // sur le display ciblé, appliquer la visibilité selon son desktopID.
        // BUGFIX : une fenêtre cachée est offscreen → state.frame.midXY tombe
        // hors de tous les displays → displayIDContainingPoint retourne nil →
        // skip → jamais reshown. Fallback sur expectedFrame (pré-hide position).
        let allWindows = daemon.registry.allWindows
        for state in allWindows {
            let frameCenter = CGPoint(x: state.frame.midX, y: state.frame.midY)
            var did = daemon.layoutEngine.displayIDContainingPoint(frameCenter)
            if did == nil && state.expectedFrame != .zero {
                let expCenter = CGPoint(x: state.expectedFrame.midX,
                                        y: state.expectedFrame.midY)
                did = daemon.layoutEngine.displayIDContainingPoint(expCenter)
            }
            guard let resolvedDid = did, resolvedDid == targetDisplayID else { continue }
            let shouldShow = state.desktopID == resolvedTarget
            logInfo("desktop.focus per_display window", [
                "wid": String(state.cgWindowID),
                "desktop": String(state.desktopID),
                "should_show": shouldShow ? "yes" : "no",
            ])
            if state.isTileable {
                daemon.layoutEngine.setLeafVisible(state.cgWindowID, shouldShow)
            }
            if shouldShow {
                HideStrategyImpl.show(state.cgWindowID,
                                      registry: daemon.registry,
                                      strategy: daemon.config.stageManager.hideStrategy)
            } else {
                HideStrategyImpl.hide(state.cgWindowID,
                                      registry: daemon.registry,
                                      strategy: daemon.config.stageManager.hideStrategy)
            }
        }
        daemon.applyLayout()

        // Émet event desktop_changed avec display_id (FR-024).
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        EventBus.shared.publish(DesktopEvent(
            name: "desktop_changed",
            payload: [
                "from": String(previousID),
                "to": String(resolvedTarget),
                "display_id": String(targetDisplayID),
                "mode": "per_display",
                "ts": String(ts),
            ]
        ))
        return .success([
            "current_id": AnyCodable(resolvedTarget),
            "previous_id": AnyCodable(previousID),
            "display_id": AnyCodable(Int(targetDisplayID)),
            "event_emitted": AnyCodable(true),
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

    // MARK: - SPEC-012 display handlers (T022)

    private static func handleWindowDisplay(request: Request, daemon: Daemon) async -> Response {
        guard let dReg = daemon.displayRegistry else {
            return .error(.invalidArgument, "display_registry not initialized")
        }
        guard let selectorStr = request.args?["selector"] else {
            return .error(.invalidArgument, "missing selector")
        }
        guard let wid = daemon.registry.focusedWindowID else {
            return .error(.windowNotFound, "no focused window")
        }
        guard let state = daemon.registry.get(wid) else {
            return .error(.windowNotFound, "wid not registered")
        }
        let count = await dReg.count
        guard let dstDisplay = await resolveDisplaySelector(
            selectorStr,
            registry: dReg,
            count: count,
            currentWindowFrame: state.frame
        ) else {
            return .error(.unknownDesktop, "unknown display selector \"\(selectorStr)\"")
        }
        // Résoudre le display source via le centre de la frame de la fenêtre.
        let center = CGPoint(x: state.frame.midX, y: state.frame.midY)
        let srcDisplay = await dReg.displayContaining(point: center) ?? dstDisplay
        // No-op si même écran.
        if srcDisplay.id == dstDisplay.id {
            return .success([
                "cgwid": AnyCodable(Int(wid)),
                "from": AnyCodable(srcDisplay.index),
                "to": AnyCodable(dstDisplay.index),
            ])
        }
        // Calculer la nouvelle frame : centrer dans visibleFrame dst, clamp si dépasse.
        // CRITIQUE : `Display.visibleFrame` est en coords NS (origin bottom-left)
        // mais `AXReader.setBounds` attend des coords AX (origin top-left).
        // Sans conversion, une fenêtre déplacée vers un écran positionné EN HAUT
        // du primary atterrit hors-écran et macOS la clamp → reste sur l'origine.
        let dstVisAX = nsToAxRect(dstDisplay.visibleFrame)
        var newSize = state.frame.size
        if newSize.width > dstVisAX.width * 0.95 { newSize.width = dstVisAX.width * 0.8 }
        if newSize.height > dstVisAX.height * 0.95 { newSize.height = dstVisAX.height * 0.8 }
        let newOrigin = CGPoint(
            x: dstVisAX.midX - newSize.width / 2,
            y: dstVisAX.midY - newSize.height / 2
        )
        let newFrame = CGRect(origin: newOrigin, size: newSize)
        // Appliquer via AX.
        if let element = daemon.registry.axElement(for: wid) {
            AXReader.setBounds(element, frame: newFrame)
        }
        daemon.registry.updateFrame(wid, frame: newFrame)
        // Mise à jour de l'arbre (uniquement si tileable).
        if state.isTileable {
            _ = daemon.layoutEngine.moveWindow(wid, fromDisplay: srcDisplay.id, toDisplay: dstDisplay.id)
        }
        // Mise à jour du displayUUID dans le DesktopRegistry. SPEC-013 FR-012 :
        // en mode per_display, la fenêtre adopte le current desktop du display cible.
        if let dRegistry = daemon.desktopRegistry {
            let mode = await dRegistry.mode
            let targetDeskID: Int
            if mode == .perDisplay {
                targetDeskID = await dRegistry.currentID(for: dstDisplay.id)
                daemon.registry.update(wid) { $0.desktopID = targetDeskID }
            } else {
                targetDeskID = await dRegistry.currentID
            }
            try? await dRegistry.updateWindowDisplayUUID(
                cgwid: UInt32(wid),
                desktopID: targetDeskID,
                displayUUID: dstDisplay.uuid
            )
        }
        // Re-appliquer le layout sur tous les écrans.
        daemon.applyLayout()
        return .success([
            "cgwid": AnyCodable(Int(wid)),
            "from": AnyCodable(srcDisplay.index),
            "to": AnyCodable(dstDisplay.index),
            "new_frame": AnyCodable([
                Int(newFrame.origin.x), Int(newFrame.origin.y),
                Int(newFrame.size.width), Int(newFrame.size.height),
            ]),
        ])
    }

    // MARK: - SPEC-012 T032 : display.list

    private static func handleDisplayList(daemon: Daemon) async -> Response {
        guard let dReg = daemon.displayRegistry else {
            return .error(.invalidArgument, "display_registry not initialized")
        }
        let displays = await dReg.displays
        let activeID = await dReg.activeID
        let payload: [[String: Any]] = displays.map { d in
            let leafCount = daemon.layoutEngine.workspace.rootsByDisplay[d.id]?.allLeaves.count ?? 0
            return [
                "index": d.index,
                "id": Int(d.id),
                "uuid": d.uuid,
                "name": d.name,
                "frame": [Int(d.frame.origin.x), Int(d.frame.origin.y),
                          Int(d.frame.size.width), Int(d.frame.size.height)],
                "visible_frame": [Int(d.visibleFrame.origin.x), Int(d.visibleFrame.origin.y),
                                  Int(d.visibleFrame.size.width), Int(d.visibleFrame.size.height)],
                "is_main": d.isMain,
                "is_active": d.id == activeID,
                "windows": leafCount,
            ]
        }
        return .success(["displays": AnyCodable(payload)])
    }

    // MARK: - SPEC-012 T033 : display.current

    private static func handleDisplayCurrent(daemon: Daemon) async -> Response {
        guard let dReg = daemon.displayRegistry else {
            return .error(.invalidArgument, "display_registry not initialized")
        }
        // Résoudre via la fenêtre focusée, sinon fallback sur le display principal.
        let display: Display?
        if let wid = daemon.registry.focusedWindowID,
           let state = daemon.registry.get(wid) {
            let center = CGPoint(x: state.frame.midX, y: state.frame.midY)
            display = await dReg.displayContaining(point: center)
        } else {
            let allDisplays = await dReg.displays
            display = allDisplays.first { $0.isMain } ?? allDisplays.first
        }
        guard let d = display else {
            return .error(.invalidArgument, "no display available")
        }
        return .success([
            "index": AnyCodable(d.index),
            "id": AnyCodable(Int(d.id)),
            "uuid": AnyCodable(d.uuid),
            "name": AnyCodable(d.name),
        ])
    }

    // MARK: - SPEC-012 T034 : display.focus

    private static func handleDisplayFocus(selector: String, daemon: Daemon) async -> Response {
        guard let dReg = daemon.displayRegistry else {
            return .error(.invalidArgument, "display_registry not initialized")
        }
        let count = await dReg.count
        guard count > 0 else {
            return .error(.invalidArgument, "no displays available")
        }
        // Résoudre le selector sans frame courante (aucune fenêtre n'est nécessaire ici).
        let dst: Display?
        if let n = Int(selector) {
            guard (1...count).contains(n) else {
                return .error(.unknownDesktop, "unknown display selector \"\(selector)\"")
            }
            dst = await dReg.display(at: n)
        } else {
            let activeID = await dReg.activeID
            let currentIndex = (await dReg.displays.first { $0.id == activeID })?.index ?? 1
            switch selector {
            case "main":
                dst = await dReg.displays.first { $0.isMain }
            case "next":
                dst = await dReg.display(at: (currentIndex % count) + 1)
            case "prev":
                dst = await dReg.display(at: currentIndex <= 1 ? count : currentIndex - 1)
            default:
                return .error(.unknownDesktop, "unknown display selector \"\(selector)\"")
            }
        }
        guard let d = dst else {
            return .error(.unknownDesktop, "unknown display selector \"\(selector)\"")
        }
        // Focus la première leaf tilée de l'écran cible.
        if let root = daemon.layoutEngine.workspace.rootsByDisplay[d.id],
           let firstLeaf = root.allLeaves.first(where: { $0.isVisible }) {
            daemon.focusManager.setFocus(to: firstLeaf.windowID)
            return .success([
                "display": AnyCodable(d.index),
                "focused": AnyCodable(Int(firstLeaf.windowID)),
            ])
        }
        return .success([
            "display": AnyCodable(d.index),
            "focused": AnyCodable(""),
        ])
    }

    /// Convertit un rect NSScreen (origin bottom-left, Quartz) en rect AX (origin top-left).
    /// macOS AXUIElement attend des coordonnées top-left, NSScreen donne bottom-left.
    /// La hauteur de référence est celle du primary screen (NSScreen.screens[0].frame.height).
    private static func nsToAxRect(_ ns: CGRect) -> CGRect {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(
            x: ns.origin.x,
            y: mainHeight - (ns.origin.y + ns.height),
            width: ns.width,
            height: ns.height
        )
    }

    /// Résout un selector d'écran (`1..N`, `prev`, `next`, `main`) vers un `Display`.
    /// Le selector numérique est 1-based. `prev`/`next` sont relatifs à l'écran
    /// contenant la fenêtre courante.
    private static func resolveDisplaySelector(
        _ selector: String,
        registry: DisplayRegistry,
        count: Int,
        currentWindowFrame: CGRect
    ) async -> Display? {
        if let n = Int(selector) {
            guard (1...count).contains(n) else { return nil }
            return await registry.display(at: n)
        }
        let center = CGPoint(x: currentWindowFrame.midX, y: currentWindowFrame.midY)
        let current = await registry.displayContaining(point: center)
        let currentIndex = current?.index ?? 1
        switch selector {
        case "main":
            return await registry.displays.first { $0.isMain }
        case "next":
            let nextIndex = (currentIndex % count) + 1
            return await registry.display(at: nextIndex)
        case "prev":
            let prevIndex = currentIndex <= 1 ? count : currentIndex - 1
            return await registry.display(at: prevIndex)
        default:
            return nil
        }
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
