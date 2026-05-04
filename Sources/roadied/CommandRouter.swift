import Foundation
import AppKit
import RoadieCore
import RoadieTiler
import RoadieStagePlugin
import RoadieFXCore
import RoadieDesktops
import TOMLKit

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
            // SPEC-018 : normalise les state.stageID qui référencent des stages
            // inexistantes (héritage persistance desktop). Cheap : O(N windows).
            // SPEC-014 : ajouter app_name pour résoudre l'icône côté rail (NSRunningApplication.localizedName).
            let runningByPID = Dictionary(uniqueKeysWithValues:
                NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) })
            let payload: [String: AnyCodable] = [
                "windows": AnyCodable(daemon.registry.allWindows.map { state -> [String: Any] in
                    let appName: String = runningByPID[state.pid]?.localizedName ?? state.bundleID
                    return [
                        "id": Int(state.cgWindowID),
                        "pid": Int(state.pid),
                        "bundle": state.bundleID,
                        "app_name": appName,
                        "title": state.title,
                        "frame": [Int(state.frame.origin.x), Int(state.frame.origin.y),
                                  Int(state.frame.size.width), Int(state.frame.size.height)],
                        "subrole": state.subrole.rawValue,
                        "is_tiled": state.isTileable,
                        "is_floating": state.isFloating,
                        "is_focused": daemon.registry.focusedWindowID == state.cgWindowID,
                        "stage": state.stageID?.value ?? "",
                    ]
                }),
            ]
            return .success(payload)

        case "daemon.status":
            // SPEC-018 : ajouter stages_mode, migration_pending, current_scope.
            // SPEC-024 : ajouter arch_version (2 = mono-binaire, rail in-process).
            let currentScope = await daemon.currentStageScope()
            let payload: [String: AnyCodable] = [
                "version": AnyCodable("0.1.0"),
                "arch_version": AnyCodable(2),
                "tiled_windows": AnyCodable(daemon.registry.tileableWindows.count),
                "tiler_strategy": AnyCodable(daemon.layoutEngine.workspace.tilerStrategy.rawValue),
                "stage_manager_enabled": AnyCodable(daemon.config.stageManager.enabled),
                "current_stage": AnyCodable(daemon.stageManager?.currentStageID?.value ?? ""),
                "stages_mode": AnyCodable(daemon.stageManager?.stageMode.rawValue ?? "global"),
                "migration_pending": AnyCodable(daemon.migrationPending),
                "rail_inprocess": AnyCodable(daemon.railController != nil),
                "current_scope": AnyCodable([
                    "display_uuid": currentScope.displayUUID,
                    "desktop_id": currentScope.desktopID,
                    "inferred_from": "cursor",
                ] as [String: Any]),
            ]
            return .success(payload)

        case "daemon.audit":
            // SPEC-021 T080 — audit read-only des invariants stage/desktop ownership.
            // SPEC-022 — étendu : si arg `fix=true`, lance aussi l'integrity check
            // physique (frames degenerate, wids offscreen-active, leafs misplaced)
            // ET applique les corrections.
            let fix = (request.args?["fix"] ?? "false") == "true"
            // SPEC-024 fix : si fix=true ET violations widToScope drift,
            // rebuild l'index inverse via rebuildWidToScopeIndex() (qui existe
            // dans StageManager). Sans ça, fix=true ne traitait que l'integrity
            // physique mais laissait les violations d'ownership intactes.
            let violationsBefore = daemon.stageManager?.auditOwnership() ?? []
            var rebuildApplied = false
            if fix, !violationsBefore.isEmpty, let sm = daemon.stageManager {
                // 1. Purge les wids orphelines (fenêtres fermées + helpers) du
                //    memberWindows — sinon rebuildWidToScopeIndex va re-injecter
                //    des wids fantômes dans widToScope.
                sm.purgeOrphanWindows()
                // 2. Rebuild widToScope depuis memberWindows (cohérence I1).
                sm.rebuildWidToScopeIndex()
                rebuildApplied = true
            }
            let violations = fix && rebuildApplied
                ? (daemon.stageManager?.auditOwnership() ?? [])
                : violationsBefore
            var integrity: [String: AnyCodable] = [:]
            if let reconciler = daemon.windowDesktopReconciler {
                let report = await reconciler.runIntegrityCheck(autoFix: fix)
                integrity = [
                    "degenerate_frames": AnyCodable(report.degenerateFrames),
                    "offscreen_with_active_scope": AnyCodable(report.offscreenWithActiveScope),
                    "tree_leaf_wrong_display": AnyCodable(report.treeLeafWrongDisplay),
                    "member_on_wrong_display": AnyCodable(report.memberOnWrongDisplay),
                    "fixed_count": AnyCodable(fix ? report.fixedCount : 0),
                ]
            }
            let payload: [String: AnyCodable] = [
                "violations": AnyCodable(violations),
                "count": AnyCodable(violations.count),
                "healthy": AnyCodable(violations.isEmpty && integrity.isEmpty),
                "integrity": AnyCodable(integrity),
                "fix_applied": AnyCodable(fix),
                "ownership_rebuild_applied": AnyCodable(rebuildApplied),
                "violations_before_fix": AnyCodable(violationsBefore.count),
            ]
            return .success(payload)

        case "daemon.health":
            // SPEC-025 FR-004 — health metric instantané. Compteurs cumulés
            // depuis le dernier boot + verdict global.
            let totalWids = daemon.stageManager?.totalMemberCount() ?? 0
            let violationsNow = daemon.stageManager?.auditOwnership().count ?? 0
            let offscreenAtRestore = StageManager.lastValidationInvalidatedCount
            let health = BootStateHealth(
                totalWids: totalWids,
                widsOffscreenAtRestore: offscreenAtRestore,
                widsZombiesPurged: 0,  // cumulé depuis boot non tracé granulairement
                widToScopeDriftsFixed: violationsNow
            )
            return .success([
                "total_wids": AnyCodable(totalWids),
                "offscreen_at_restore": AnyCodable(offscreenAtRestore),
                "zombies_purged": AnyCodable(0),
                "drifts_fixed": AnyCodable(violationsNow),
                "verdict": AnyCodable(health.verdict.rawValue),
            ])

        case "daemon.heal":
            // SPEC-025 FR-005 — orchestration de toutes les réparations connues.
            // Idempotent : relancer 2× = pas de side effect.
            let start = Date()
            var purged = 0
            var driftsFixed = 0
            if let sm = daemon.stageManager {
                let memberBefore = sm.totalMemberCount()
                let violationsBefore = sm.auditOwnership()
                driftsFixed = violationsBefore.count
                sm.purgeOrphanWindows()
                sm.rebuildWidToScopeIndex()
                purged = max(0, memberBefore - sm.totalMemberCount())
            }
            daemon.applyLayout()
            var widsRestored = 0
            if let reconciler = daemon.windowDesktopReconciler {
                let report = await reconciler.runIntegrityCheck(autoFix: true)
                widsRestored = report.fixedCount
            }
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            logInfo("daemon_heal", [
                "purged": String(purged),
                "drifts_fixed": String(driftsFixed),
                "wids_restored": String(widsRestored),
                "duration_ms": String(durationMs),
            ])
            return .success([
                "purged": AnyCodable(purged),
                "drifts_fixed": AnyCodable(driftsFixed),
                "wids_restored": AnyCodable(widsRestored),
                "duration_ms": AnyCodable(durationMs),
            ])

        case "daemon.reload":
            do {
                let newConfig = try ConfigLoader.load()
                daemon.config = newConfig
                if let level = LogLevel(rawValue: newConfig.daemon.logLevel) {
                    Logger.shared.setMinLevel(level)
                }
                logInfo("config reloaded")
                // SPEC-019 — signaler aux consommateurs externes (rail) qu'ils doivent
                // relire leur config (ex: [fx.rail].renderer pour switcher de rendu).
                EventBus.shared.publish(DesktopEvent(name: "config_reloaded"))
                return .success()
            } catch {
                return .error(.invalidArgument, "config reload failed: \(error)")
            }

        case "rail.renderer.list":
            // SPEC-019 — liste des renderers connus côté daemon (manifest hardcoded,
            // miroir de Sources/RoadieRail/Renderers/Bootstrap.swift) + le `current`
            // lu depuis le TOML utilisateur.
            let knownRenderers: [(id: String, displayName: String)] = [
                ("stacked-previews", "Stacked previews"),
                ("icons-only",       "Icons only"),
                ("hero-preview",     "Hero preview"),
                ("mosaic",           "Mosaic"),
                ("parallax-45",      "Parallax 45\u{00B0}"),
            ]
            let currentRenderer = readCurrentRendererID() ?? "stacked-previews"
            let payload: [String: AnyCodable] = [
                "default": AnyCodable("stacked-previews"),
                "current": AnyCodable(currentRenderer),
                "renderers": AnyCodable(knownRenderers.map { r -> [String: Any] in
                    ["id": r.id, "display_name": r.displayName]
                }),
            ]
            return .success(payload)

        case "rail.renderer.set":
            guard let id = request.args?["id"], !id.isEmpty else {
                return .error(.invalidArgument, "missing renderer id")
            }
            let knownIDs = ["stacked-previews", "icons-only", "hero-preview", "mosaic", "parallax-45"]
            guard knownIDs.contains(id) else {
                return .error(.invalidArgument,
                              "renderer '\(id)' not found. Available: \(knownIDs.joined(separator: ", "))")
            }
            let previous = readCurrentRendererID() ?? "stacked-previews"
            do {
                try writeRendererID(id)
            } catch {
                return .error(.internalError, "failed to write TOML: \(error)")
            }
            // Reload config + signaler au rail.
            if let newConfig = try? ConfigLoader.load() {
                daemon.config = newConfig
            }
            EventBus.shared.publish(DesktopEvent(name: "config_reloaded"))
            return .success([
                "previous": AnyCodable(previous),
                "current": AnyCodable(id),
            ])

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
            // SPEC-025 BUG-002 fix : capter le display ID avant le warp pour
            // détecter les warps cross-display (warp_cross_display_edge).
            // LayoutEngine.warp ne met à jour QUE le tree. Sans ce sync, le
            // stageManager.memberWindows et le desktopRegistry restent désync
            // → au prochain restart la wid est ré-assignée à la stage du
            // SOURCE display (drift physique vs logique).
            let srcDisplayID = daemon.layoutEngine.displayIDForWindow(wid)
            let warped = daemon.layoutEngine.warp(wid, direction: direction)
            // Détecter cross-display : displayID a changé après le warp.
            let dstDisplayID = daemon.layoutEngine.displayIDForWindow(wid)
            if warped, let src = srcDisplayID, let dst = dstDisplayID, src != dst,
               let dRegistry = daemon.desktopRegistry,
               let dispReg = daemon.displayRegistry {
                let displays = await dispReg.displays
                if let dstDisplay = displays.first(where: { $0.id == dst }) {
                    let mode = await dRegistry.mode
                    let targetDeskID: Int = (mode == .perDisplay)
                        ? await dRegistry.currentID(for: dst)
                        : await dRegistry.currentID
                    daemon.registry.update(wid) { $0.desktopID = targetDeskID }
                    try? await dRegistry.updateWindowDisplayUUID(
                        cgwid: UInt32(wid),
                        desktopID: targetDeskID,
                        displayUUID: dstDisplay.uuid)
                    if let sm = daemon.stageManager, sm.stageMode == .perDisplay {
                        let activeStage = sm.activeStageByDesktop[
                            DesktopKey(displayUUID: dstDisplay.uuid, desktopID: targetDeskID)]
                            ?? StageID("1")
                        let targetScope = StageScope(displayUUID: dstDisplay.uuid,
                                                      desktopID: targetDeskID,
                                                      stageID: activeStage)
                        if sm.stagesV2[targetScope] == nil {
                            _ = sm.createStage(id: activeStage,
                                                displayName: activeStage.value,
                                                scope: targetScope)
                        }
                        sm.assign(wid: wid, to: targetScope)
                        EventBus.shared.publish(DesktopEvent(
                            name: "window_assigned",
                            payload: ["wid": String(wid),
                                      "stage_id": activeStage.value,
                                      "display_uuid": dstDisplay.uuid,
                                      "desktop_id": String(targetDeskID)]))
                        logInfo("warp_cross_display_synced", [
                            "wid": String(wid),
                            "from_display": String(src),
                            "to_display": String(dst),
                            "stage_id": activeStage.value,
                        ])
                    }
                }
            }
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
            // SPEC-022 — rebuild per-display + per-stage actif. Pour chaque display,
            // injecter les wids dont widToScope pointe vers (uuid, currentDesktop, *)
            // dans le tree de leur stage active. Plus de pollution cross-display.
            await daemon.rebuildAllTrees()
            daemon.layoutEngine.rebuildTree()
            daemon.applyLayout()
            return .success()

        case "stage.list":
            // SPEC-018 : reconcile avant lecture (évite que des wid avec stageID
            // périmé apparaissent dans la mauvaise stage ou nulle part).
            guard let sm = daemon.stageManager else {
                return .error(.stageManagerDisabled, "stage manager disabled in config")
            }
            // SPEC-018 : en mode per_display, filtrer par (displayUUID, desktopID) du scope.
            // US4 : si request.args["display"] ou ["desktop"] présents, override le scope implicite.
            // En mode global, comportement V1 identique (toutes les stages).
            var scopeError: Response? = nil
            let scope: StageScope
            if sm.stageMode == .perDisplay {
                guard let resolved = await resolveScope(request: request, daemon: daemon,
                                                        errorOut: &scopeError) else {
                    return scopeError ?? .error(.internalError, "scope resolution failed")
                }
                scope = resolved
            } else {
                scope = await daemon.currentStageScope()
            }
            let currentID: String
            let scopedStages: [[String: Any]]
            if sm.stageMode == .global {
                // Mode global : compat V1 — liste plate, currentStageID direct.
                currentID = sm.currentStageID?.value ?? ""
                let sortedStages = sm.stages.values.sorted { lhs, rhs in
                    lhs.id.value.localizedStandardCompare(rhs.id.value) == .orderedAscending
                }
                scopedStages = sortedStages.map { stage -> [String: Any] in
                    [
                        "id": stage.id.value,
                        "display_name": stage.displayName,
                        "window_count": stage.memberWindows.count,
                        "window_ids": stage.memberWindows.map { Int($0.cgWindowID) },
                        "is_active": stage.id.value == currentID,
                    ]
                }
                return .success([
                    "current": AnyCodable(currentID),
                    "stages": AnyCodable(scopedStages),
                ])
            } else {
                // Mode per_display : filtrer stagesV2 par (displayUUID, desktopID).
                let filtered = sm.stagesV2.filter {
                    $0.key.displayUUID == scope.displayUUID && $0.key.desktopID == scope.desktopID
                }
                // SPEC-022 : "current stage" du scope = activeStageByDesktop[(uuid, desktopID)],
                // PAS le scalaire global currentStageID (qui ne reflète que le scope visible).
                let scopedKey = DesktopKey(displayUUID: scope.displayUUID,
                                            desktopID: scope.desktopID)
                currentID = sm.activeStageByDesktop[scopedKey]?.value ?? ""
                // SPEC-022 — tri stable par stage.id pour que le rail panel n'inverse pas
                // les vignettes d'un poll au suivant (Dictionary.filter retourne dans
                // un ordre non-déterministe).
                let sortedFiltered = filtered.sorted { lhs, rhs in
                    lhs.key.stageID.value.localizedStandardCompare(rhs.key.stageID.value)
                        == .orderedAscending
                }
                scopedStages = sortedFiltered.map { (scopeKey, stage) -> [String: Any] in
                    [
                        "id": stage.id.value,
                        "display_name": stage.displayName,
                        "window_count": stage.memberWindows.count,
                        "window_ids": stage.memberWindows.map { Int($0.cgWindowID) },
                        "is_active": stage.id.value == currentID,
                    ]
                }
                return .success([
                    "current": AnyCodable(currentID),
                    "mode": AnyCodable(sm.stageMode.rawValue),
                    "stages": AnyCodable(scopedStages),
                    "scope": AnyCodable([
                        "display_uuid": scope.displayUUID,
                        "desktop_id": scope.desktopID,
                    ] as [String: Any]),
                ])
            }

        case "stage.switch":
            guard let sm = daemon.stageManager else {
                return .error(.stageManagerDisabled, "stage manager disabled in config")
            }
            guard let stageStr = request.args?["stage_id"] else {
                return .error(.invalidArgument, "missing stage_id")
            }
            let stageID = StageID(stageStr)
            // Lazy auto-create : si la stage n'existe pas dans le scope courant,
            // la créer vide puis switcher dessus. Cohérent avec stage.assign qui
            // est déjà lazy. Évite l'échec silencieux quand l'utilisateur tape
            // Alt+N avant d'avoir jamais peuplé la stage N.
            // SPEC-022 : en mode per_display, utiliser le switchTo scopé pour que
            // le switch n'affecte QUE le scope cible (display, desktop) et pas
            // l'écran visible courant si le scope est distant.
            if sm.stageMode == .perDisplay {
                var scopeError: Response? = nil
                guard let baseScope = await resolveScope(request: request, daemon: daemon,
                                                         errorOut: &scopeError) else {
                    return scopeError ?? .error(.internalError, "scope resolution failed")
                }
                let fullScope = StageScope(displayUUID: baseScope.displayUUID,
                                           desktopID: baseScope.desktopID, stageID: stageID)
                if sm.stagesV2[fullScope] == nil {
                    _ = sm.createStage(id: stageID, displayName: "stage \(stageStr)",
                                       scope: fullScope)
                }
                sm.switchTo(stageID: stageID, scope: fullScope)
            } else {
                if sm.stages[stageID] == nil {
                    _ = sm.createStage(id: stageID, displayName: "stage \(stageStr)")
                }
                sm.switchTo(stageID: stageID)
            }
            return .success(["current": AnyCodable(stageID.value)])

        case "stage.assign":
            guard let sm = daemon.stageManager else {
                return .error(.stageManagerDisabled, "stage manager disabled in config")
            }
            guard let stageStr = request.args?["stage_id"] else {
                return .error(.invalidArgument, "missing stage_id")
            }
            let stageID = StageID(stageStr)
            // SPEC-014 T053 : accepter un wid explicite (drag-drop dans rail UI).
            // Fallback sur focusedWindowID pour compat ascendante CLI.
            let wid: WindowID
            if let widStr = request.args?["wid"], let widInt = UInt32(widStr) {
                wid = WindowID(widInt)
            } else if let focused = daemon.registry.focusedWindowID {
                wid = focused
            } else {
                return .error(.windowNotFound, "no wid provided and no focused window")
            }
            // Lazy stages : auto-créer le stage s'il n'existe pas.
            // SPEC-018 : en mode per_display, créer ET assign dans le scope courant (ou overridé).
            // SPEC-022 : si --display absent, le scope cible est dérivé du DISPLAY PHYSIQUE
            // de la wid (frame center → display), PAS du curseur. Sinon "Shift+Alt+2"
            // sur une fenêtre du LG alors que le curseur est sur built-in assignait
            // logiquement la wid au built-in → cascade de moves cross-display foireux.
            // assignedScope est capturé pour l'auto-switch suivant (assign_follows_focus).
            var assignedScope: StageScope? = nil
            if sm.stageMode == .perDisplay {
                let baseScope: StageScope
                let hasExplicitDisplay = request.args?["display"] != nil
                if hasExplicitDisplay {
                    var scopeError: Response? = nil
                    guard let resolved = await resolveScope(request: request, daemon: daemon,
                                                             errorOut: &scopeError) else {
                        return scopeError ?? .error(.internalError, "scope resolution failed")
                    }
                    baseScope = resolved
                } else {
                    // Inférer depuis le display physique de la wid.
                    if let state = daemon.registry.get(wid),
                       let dReg = daemon.displayRegistry,
                       let dskReg = daemon.desktopRegistry {
                        let center = CGPoint(x: state.frame.midX, y: state.frame.midY)
                        let displays = await dReg.displays
                        // 1. Display contenant le centre. 2. Sinon scope existant
                        //    de la wid via widToScope. 3. Fallback scope curseur.
                        if let display = displays.first(where: { $0.frame.contains(center) }) {
                            let desktopID = await dskReg.currentID(for: display.id)
                            baseScope = StageScope(displayUUID: display.uuid,
                                                    desktopID: desktopID,
                                                    stageID: StageID(""))
                        } else if let known = sm.scopeOf(wid: wid) {
                            baseScope = known
                        } else {
                            baseScope = await daemon.currentStageScope()
                        }
                    } else {
                        baseScope = await daemon.currentStageScope()
                    }
                }
                let fullScope = StageScope(displayUUID: baseScope.displayUUID,
                                           desktopID: baseScope.desktopID, stageID: stageID)
                if sm.stagesV2[fullScope] == nil {
                    _ = sm.createStage(id: stageID, displayName: "stage \(stageStr)",
                                       scope: fullScope)
                }
                sm.assign(wid: wid, to: fullScope)  // overload V2 scope-aware
                assignedScope = fullScope
            } else {
                if sm.stages[stageID] == nil {
                    _ = sm.createStage(id: stageID, displayName: "stage \(stageStr)")
                }
                sm.assign(wid: wid, to: stageID)  // API V1
            }
            // Si la stage cible n'est pas la stage active, deux comportements
            // possibles selon `[focus] assign_follows_focus` :
            //   - true (défaut, yabai-style) : switcher sur la stage cible →
            //     l'utilisateur voit immédiatement le résultat de son assign.
            //   - false : cacher la fenêtre, l'utilisateur reste sur la courante
            //     (utile pour dispatcher plusieurs fenêtres avant de bouger).
            if let current = sm.currentStageID, current != stageID {
                if daemon.config.focus.assignFollowsFocus {
                    // SPEC-022 : utiliser le scope ciblé par l'assign (display physique
                    // de la wid), pas le scope courant du curseur. Sinon le switch
                    // s'applique au mauvais display → cascade de hides cross-display.
                    if let scope = assignedScope {
                        sm.switchTo(stageID: stageID, scope: scope)
                    } else {
                        sm.switchTo(stageID: stageID)
                    }
                } else if let state = daemon.registry.get(wid) {
                    if state.isTileable {
                        daemon.layoutEngine.setLeafVisible(wid, false)
                    }
                    HideStrategyImpl.hide(wid, registry: daemon.registry,
                                          strategy: daemon.config.stageManager.hideStrategy)
                }
            }
            daemon.applyLayout()
            // SPEC-018 FR-017 : émettre stage_assigned enrichi (display_uuid + desktop_id).
            let assignUUID: String
            let assignDesktopID: Int
            if sm.stageMode == .perDisplay {
                var assignScopeError: Response? = nil
                let sc = await resolveScope(request: request, daemon: daemon,
                                            errorOut: &assignScopeError)
                assignUUID = sc?.displayUUID ?? ""
                assignDesktopID = sc?.desktopID ?? 0
            } else {
                assignUUID = ""
                assignDesktopID = 0
            }
            EventBus.shared.publish(DesktopEvent.stageAssigned(
                wid: Int(wid), stageID: stageStr,
                displayUUID: assignUUID, desktopID: assignDesktopID))
            return .success(["created": AnyCodable(true), "stage_id": AnyCodable(stageStr), "wid": AnyCodable(Int(wid))])

        case "stage.create":
            guard let sm = daemon.stageManager else {
                return .error(.stageManagerDisabled, "stage manager disabled in config")
            }
            guard let stageStr = request.args?["stage_id"],
                  let displayName = request.args?["display_name"] else {
                return .error(.invalidArgument, "missing stage_id or display_name")
            }
            let stageID = StageID(stageStr)
            // SPEC-018 : en mode per_display, vérifier l'unicité dans le scope courant (ou overridé).
            let createUUID: String
            let createDesktopID: Int
            if sm.stageMode == .perDisplay {
                var scopeError: Response? = nil
                guard let baseScope = await resolveScope(request: request, daemon: daemon,
                                                         errorOut: &scopeError) else {
                    return scopeError ?? .error(.internalError, "scope resolution failed")
                }
                let scope = baseScope
                let fullScope = StageScope(displayUUID: scope.displayUUID,
                                           desktopID: scope.desktopID, stageID: stageID)
                if sm.stagesV2[fullScope] != nil {
                    return .error(.invalidArgument, "stage already exists in current scope")
                }
                _ = sm.createStage(id: stageID, displayName: displayName, scope: fullScope)
                createUUID = scope.displayUUID
                createDesktopID = scope.desktopID
            } else {
                if sm.stages[stageID] != nil {
                    return .error(.invalidArgument, "stage already exists")
                }
                _ = sm.createStage(id: stageID, displayName: displayName)
                createUUID = ""
                createDesktopID = 0
            }
            // SPEC-018 FR-017 : émettre stage_created enrichi (display_uuid + desktop_id).
            EventBus.shared.publish(DesktopEvent.stageCreated(
                stageID: stageID.value, displayName: displayName,
                displayUUID: createUUID, desktopID: createDesktopID))
            return .success(["created": AnyCodable(stageID.value)])

        case "stage.rename":
            // SPEC-014 T071 (US5) : renomme un stage et émet `stage_renamed`.
            guard let sm = daemon.stageManager else {
                return .error(.stageManagerDisabled, "stage manager disabled in config")
            }
            guard let stageStr = request.args?["stage_id"],
                  let newName = request.args?["new_name"] else {
                return .error(.invalidArgument, "missing stage_id or new_name")
            }
            let stageID = StageID(stageStr)
            // SPEC-018 : en mode per_display, vérifier l'existence dans le scope (ou overridé).
            let oldName: String
            let renameUUID: String
            let renameDesktopID: Int
            if sm.stageMode == .perDisplay {
                var scopeError: Response? = nil
                guard let baseScope = await resolveScope(request: request, daemon: daemon,
                                                         errorOut: &scopeError) else {
                    return scopeError ?? .error(.internalError, "scope resolution failed")
                }
                let scope = baseScope
                let fullScope = StageScope(displayUUID: scope.displayUUID,
                                           desktopID: scope.desktopID, stageID: stageID)
                guard let existing = sm.stagesV2[fullScope] else {
                    return .error(.unknownStage, "unknown stage \(stageStr) in current scope")
                }
                oldName = existing.displayName
                renameUUID = scope.displayUUID
                renameDesktopID = scope.desktopID
            } else {
                guard let oldStage = sm.stages[stageID] else {
                    return .error(.unknownStage, "unknown stage \(stageStr)")
                }
                oldName = oldStage.displayName
                renameUUID = ""
                renameDesktopID = 0
            }
            guard sm.renameStage(id: stageID, newName: newName) else {
                return .error(.invalidArgument, "rename failed (empty or > 32 chars)")
            }
            // SPEC-018 FR-017 : émettre stage_renamed enrichi (display_uuid + desktop_id).
            EventBus.shared.publish(DesktopEvent.stageRenamed(
                stageID: stageStr, oldName: oldName, newName: newName,
                displayUUID: renameUUID, desktopID: renameDesktopID))
            return .success([
                "stage_id": AnyCodable(stageStr),
                "new_name": AnyCodable(newName),
            ])

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
            // SPEC-018 : en mode per_display, supprimer dans le scope courant (ou overridé).
            let deleteUUID: String
            let deleteDesktopID: Int
            if sm.stageMode == .perDisplay {
                var scopeError: Response? = nil
                guard let baseScope = await resolveScope(request: request, daemon: daemon,
                                                         errorOut: &scopeError) else {
                    return scopeError ?? .error(.internalError, "scope resolution failed")
                }
                let scope = baseScope
                let fullScope = StageScope(displayUUID: scope.displayUUID,
                                           desktopID: scope.desktopID,
                                           stageID: StageID(stageStr))
                sm.deleteStage(scope: fullScope)
                deleteUUID = scope.displayUUID
                deleteDesktopID = scope.desktopID
            } else {
                sm.deleteStage(id: StageID(stageStr))
                deleteUUID = ""
                deleteDesktopID = 0
            }
            // SPEC-018 FR-017 : émettre stage_deleted enrichi (display_uuid + desktop_id).
            EventBus.shared.publish(DesktopEvent.stageDeleted(
                stageID: stageStr, displayUUID: deleteUUID, desktopID: deleteDesktopID))
            return .success()

        case "stage.hide_active":
            // SPEC-022+ "click bureau Apple" : hide TOUTES les fenêtres de la stage
            // active du scope (display, desktop) cible. Pas de toggle (no-op si déjà
            // hide). Pour ressortir, l'utilisateur clique une thumbnail dans le rail
            // → switchTo standard re-positionne via le tree.
            // Pas de mutation d'activeStageByDesktop : on laisse l'état logique tel
            // quel. Si un autre event invoque applyLayout entre-temps, les fenêtres
            // ressortiront naturellement (comportement Apple-like : reprise d'activité
            // = fin du hide).
            guard let sm = daemon.stageManager else {
                return .error(.stageManagerDisabled, "stage manager disabled in config")
            }
            var scopeError: Response? = nil
            guard let scope = await resolveScope(request: request, daemon: daemon,
                                                  errorOut: &scopeError) else {
                return scopeError ?? .error(.internalError, "scope resolution failed")
            }
            let key = DesktopKey(displayUUID: scope.displayUUID,
                                  desktopID: scope.desktopID)
            let activeStageID = sm.activeStageByDesktop[key] ?? StageID("1")
            let activeScope = StageScope(displayUUID: scope.displayUUID,
                                          desktopID: scope.desktopID,
                                          stageID: activeStageID)
            let widsToHide: [WindowID]
            if sm.stageMode == .perDisplay, let stage = sm.stagesV2[activeScope] {
                widsToHide = stage.memberWindows.map { $0.cgWindowID }
            } else if let stage = sm.stages[activeStageID] {
                widsToHide = stage.memberWindows.map { $0.cgWindowID }
            } else {
                widsToHide = []
            }
            var hiddenCount = 0
            for wid in widsToHide {
                guard let state = daemon.registry.get(wid) else { continue }
                if state.isTileable {
                    daemon.layoutEngine.setLeafVisible(wid, false)
                }
                HideStrategyImpl.hide(wid, registry: daemon.registry,
                                       strategy: daemon.config.stageManager.hideStrategy)
                hiddenCount += 1
            }
            logInfo("stage.hide_active", [
                "display_uuid": scope.displayUUID,
                "desktop_id": String(scope.desktopID),
                "stage_id": activeStageID.value,
                "hidden_count": String(hiddenCount),
            ])
            return .success([
                "hidden_count": AnyCodable(hiddenCount),
                "stage_id": AnyCodable(activeStageID.value),
            ])

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

        // MARK: - SPEC-014 rail commands

        case "window.thumbnail":
            return await handleWindowThumbnail(request: request, daemon: daemon)

        case "tiling.reserve":
            // SPEC-014 T080 (US6) : ajuste leftReserveByDisplay et re-applique le layout.
            // Args : edge ("left" V1), size (px, 0 pour annuler), display_id (CGDirectDisplayID).
            let edge = request.args?["edge"] ?? "left"
            guard let sizeStr = request.args?["size"], let size = Int(sizeStr) else {
                return .error(.invalidArgument, "missing or invalid size")
            }
            // V1 : seul edge "left" supporté.
            guard edge == "left" else {
                return .error(.invalidArgument, "only edge=left supported in V1")
            }
            // display_id : si manquant, applique au primary.
            let did: CGDirectDisplayID
            if let didStr = request.args?["display_id"], let parsed = UInt32(didStr) {
                did = parsed
            } else {
                did = CGMainDisplayID()
            }
            if size <= 0 {
                daemon.layoutEngine.leftReserveByDisplay.removeValue(forKey: did)
            } else {
                daemon.layoutEngine.leftReserveByDisplay[did] = CGFloat(size)
            }
            daemon.applyLayout()
            return .success([
                "edge": AnyCodable(edge),
                "size": AnyCodable(size),
                "display_id": AnyCodable(Int(did)),
            ])

        case "rail.status":
            return handleRailStatus(daemon: daemon)

        case "rail.toggle":
            return handleRailToggle(daemon: daemon)

        default:
            return .error(.invalidArgument, "unknown command: \(request.command)")
        }
    }

    // MARK: - SPEC-018 US4 : scope override helper

    /// Résout le StageScope en tenant compte des overrides CLI `display` et `desktop`.
    /// Si aucun override, délègue à `daemon.currentStageScope()` (curseur→frontmost→primary).
    /// Retourne nil si le selector display est invalide (`unknown_display`) ou si desktop
    /// est hors range (`desktop_out_of_range`), en remplissant `errorOut` dans ce cas.
    private static func resolveScope(
        request: Request,
        daemon: Daemon,
        errorOut: inout Response?
    ) async -> StageScope? {
        let displaySelector = request.args?["display"]
        let desktopArg = request.args?["desktop"]

        // Pas d'override → scope implicite (curseur/frontmost/primary).
        guard displaySelector != nil || desktopArg != nil else {
            return await daemon.currentStageScope()
        }

        // Résolution du display override.
        var resolvedUUID: String
        var resolvedDisplayID: CGDirectDisplayID?

        if let selector = displaySelector {
            guard let dReg = daemon.displayRegistry else {
                errorOut = .error(.unknownDisplay, "display registry not initialized")
                return nil
            }
            let count = await dReg.count
            if let index = Int(selector) {
                guard let display = await dReg.display(at: index) else {
                    errorOut = .error(.unknownDisplay,
                        "no display matching selector \"\(selector)\" or UUID")
                    return nil
                }
                resolvedUUID = display.uuid
                resolvedDisplayID = display.id
            } else {
                // Tentative de match UUID.
                guard let display = await dReg.display(forUUID: selector) else {
                    errorOut = .error(.unknownDisplay,
                        "no display matching selector \"\(selector)\" or UUID")
                    return nil
                }
                _ = count
                resolvedUUID = display.uuid
                resolvedDisplayID = display.id
            }
        } else {
            // Pas de display override : résoudre via scope implicite et garder son UUID.
            let implicit = await daemon.currentStageScope()
            resolvedUUID = implicit.displayUUID
            // Tenter de résoudre le displayID pour le desktop lookup.
            if let dReg = daemon.displayRegistry {
                resolvedDisplayID = await dReg.display(forUUID: resolvedUUID)?.id
            }
        }

        // Résolution du desktop override.
        let desktopCount = daemon.config.desktops.count
        var resolvedDesktopID: Int

        if let deskStr = desktopArg {
            guard let deskInt = Int(deskStr) else {
                errorOut = .error(.desktopOutOfRange,
                    "desktop \"\(deskStr)\" is not a valid integer")
                return nil
            }
            guard deskInt >= 1 && deskInt <= desktopCount else {
                errorOut = .error(.desktopOutOfRange,
                    "desktop \(deskInt) not in range 1..\(desktopCount)")
                return nil
            }
            resolvedDesktopID = deskInt
        } else {
            // Pas de desktop override : prendre le current desktop du display résolu.
            if let did = resolvedDisplayID {
                resolvedDesktopID = await daemon.desktopRegistry?.currentID(for: did) ?? 1
            } else {
                resolvedDesktopID = 1
            }
        }

        let result = StageScope(displayUUID: resolvedUUID, desktopID: resolvedDesktopID,
                               stageID: StageID(""))
        // Log uniquement pour le path explicit_cli (le path implicite est loggué dans currentStageScope).
        if displaySelector != nil || desktopArg != nil {
            logInfo("scope_inferred_from", [
                "source": "explicit_cli",
                "display_uuid": resolvedUUID,
                "desktop_id": String(resolvedDesktopID),
            ])
        }
        return result
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
            logWarn("desktop_focus_unresolved", [
                "selector": selector,
                "previous_id": String(previousID),
                "flow": "global",
                "reason": "selector_returned_nil",
            ])
            return .error(.unknownDesktop, "unknown desktop selector \"\(selector)\"")
        }
        let wasNoop = targetID == previousID && !daemon.config.desktops.backAndForth
        if wasNoop {
            logInfo("desktop_focus_noop", [
                "selector": selector,
                "current_id": String(previousID),
                "flow": "global",
                "back_and_forth": "false",
                "reason": "same_target_no_backforth",
            ])
        }
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
            logWarn("desktop_focus_unresolved", [
                "selector": selector,
                "previous_id": String(previousID),
                "target_display": String(targetDisplayID),
                "reason": "selector_returned_nil",
            ])
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
                // No-op silencieux côté UI mais on trace pour observabilité.
                logInfo("desktop_focus_noop", [
                    "selector": selector,
                    "current_id": String(previousID),
                    "target_display": String(targetDisplayID),
                    "back_and_forth": String(daemon.config.desktops.backAndForth),
                    "reason": daemon.config.desktops.backAndForth
                        ? "no_recent_desktop"
                        : "same_target_no_backforth",
                ])
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

        // SPEC-019 INV-3 — matérialiser stage 1 sur le (display, desktop) d'arrivée
        // si jamais visité. Sans ce passage, `handleDesktopFocusPerDisplay` ne passe
        // PAS par DesktopSwitcher.performSwitch (qui appelle onDesktopChanged →
        // ensureDefaultStage), donc desktop neuf reste sans stage 1 sur disque.
        if let sm = daemon.stageManager, sm.stageMode == .perDisplay,
           let displays = await daemon.displayRegistry?.displays,
           let dst = displays.first(where: { $0.id == targetDisplayID }),
           !dst.uuid.isEmpty {
            let arrivalScope = StageScope(displayUUID: dst.uuid,
                                           desktopID: resolvedTarget,
                                           stageID: StageID("1"))
            sm.ensureDefaultStage(scope: arrivalScope)
            sm.setCurrentDesktopKey(DesktopKey(displayUUID: dst.uuid,
                                                desktopID: resolvedTarget))
        }

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
        // SPEC-018 audit-cohérence : intersecter aussi avec le stage actif du desktop
        // cible. Sans ça, entrer un desktop affiche TOUTES ses wids (peu importe le
        // stage), contredisant le concept même de stage. Si le mode est global ou si
        // le desktop cible n'a jamais eu de stage actif mémorisé, fallback : show all.
        let activeStageOnTarget: StageID? = await {
            guard let sm = daemon.stageManager, sm.stageMode == .perDisplay else { return nil }
            guard let displays = await daemon.displayRegistry?.displays,
                  let target = displays.first(where: { $0.id == targetDisplayID }),
                  !target.uuid.isEmpty else { return nil }
            let key = DesktopKey(displayUUID: target.uuid, desktopID: resolvedTarget)
            return sm.activeStage(for: key)
        }()
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
            // BUGFIX : skip les fenêtres non-tilées (dialogs, popovers, modaux
            // système). Les hide/show les rendrait invisibles alors qu'elles
            // sont gérées par macOS natif (ex: dialog "Organiser…" Monitors).
            guard state.isTileable else { continue }
            let stageMatches: Bool = {
                guard let active = activeStageOnTarget else { return true }
                return state.stageID == active
            }()
            let shouldShow = state.desktopID == resolvedTarget && stageMatches
            logInfo("desktop.focus per_display window", [
                "wid": String(state.cgWindowID),
                "desktop": String(state.desktopID),
                "stage": state.stageID?.value ?? "nil",
                "active_stage": activeStageOnTarget?.value ?? "any",
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
            // SPEC-022 — re-étiqueter aussi widToScope (StageManager). Sinon la
            // fenêtre est physiquement sur dst mais le rail panel src continue de
            // l'afficher (étiquette logique inchangée). C'est l'action explicite
            // de l'user (raccourci `window display N`) → re-étiquetage légitime.
            if let sm = daemon.stageManager, sm.stageMode == .perDisplay {
                let activeStage = sm.activeStageByDesktop[
                    DesktopKey(displayUUID: dstDisplay.uuid, desktopID: targetDeskID)] ?? StageID("1")
                let targetScope = StageScope(displayUUID: dstDisplay.uuid,
                                              desktopID: targetDeskID, stageID: activeStage)
                if sm.stagesV2[targetScope] == nil {
                    _ = sm.createStage(id: activeStage, displayName: activeStage.value,
                                        scope: targetScope)
                }
                sm.assign(wid: wid, to: targetScope)
                EventBus.shared.publish(DesktopEvent(
                    name: "window_assigned",
                    payload: ["wid": String(wid),
                              "stage_id": activeStage.value,
                              "display_uuid": dstDisplay.uuid,
                              "desktop_id": String(targetDeskID)]))
            }
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

    // MARK: - SPEC-014 private handlers

    /// Retourne une vignette PNG pour `wid` via capture lazy on-demand
    /// (`CGWindowListCreateImage` à la demande, pattern AltTab).
    ///
    /// **Ordre de priorité** (capture systématique, cache en filet de secours) :
    /// 1. Capture immédiate (`captureNow`) — ~5-15 ms. Si succès → cache + retour.
    /// 2. Échec capture (DRM strict, fenêtre off-screen) → tenter le cache pour
    ///    réutiliser la dernière capture valide (vignette figée mais présente).
    /// 3. Cache vide → fallback icône d'app.
    ///
    /// Pourquoi capturer à chaque demande au lieu de respecter le cache d'abord ?
    /// Le rail ping ce handler toutes les ~2 s (refresh timer). Sans recapture
    /// systématique, une vignette mise en cache une fois (ex: écran noir Netflix
    /// au premier appel) reste figée éternellement même quand le contenu de la
    /// fenêtre change (autre onglet Firefox, etc.). CGWindowListCreateImage est
    /// ponctuel → pas d'activation DRM continue (vs SCStream).
    private static func handleWindowThumbnail(request: Request, daemon: Daemon) async -> Response {
        guard let widStr = request.args?["wid"], let widU = UInt32(widStr) else {
            return .error(.invalidArgument, "missing or invalid wid")
        }
        let wid = CGWindowID(widU)
        guard daemon.registry.get(wid) != nil else {
            return .error(.windowNotFound, "wid not found")
        }
        if let sck = daemon.sckCaptureService,
           let entry = sck.captureNow(wid: wid) {
            daemon.thumbnailCache?.put(entry)
            return thumbnailResponse(entry)
        }
        // Capture échouée (DRM strict / off-screen) : recycler la dernière
        // capture valide en cache pour ne pas afficher juste l'icône d'app.
        if let entry = daemon.thumbnailCache?.get(wid: wid) {
            return thumbnailResponse(entry)
        }
        return fallbackIconResponse(wid: wid, registry: daemon.registry)
    }

    private static func thumbnailResponse(_ entry: ThumbnailEntry) -> Response {
        let iso = iso8601String(entry.capturedAt)
        return .success([
            "png_base64": AnyCodable(entry.pngData.base64EncodedString()),
            "wid": AnyCodable(Int(entry.wid)),
            "size": AnyCodable([Int(entry.size.width), Int(entry.size.height)]),
            "degraded": AnyCodable(entry.degraded),
            "captured_at": AnyCodable(iso),
        ])
    }

    private static func fallbackIconResponse(wid: CGWindowID, registry: WindowRegistry) -> Response {
        let now = iso8601String(Date())
        guard let state = registry.get(wid),
              let bundleURL = NSWorkspace.shared.urlForApplication(
                  withBundleIdentifier: state.bundleID) else {
            return .error(.windowNotFound, "window not in registry or app not found")
        }
        let icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
        let target = NSSize(width: 128, height: 128)
        let resized = resizeImage(icon, to: target)
        let pngData = pngEncode(resized)
        return .success([
            "png_base64": AnyCodable(pngData.base64EncodedString()),
            "wid": AnyCodable(Int(wid)),
            "size": AnyCodable([128, 128]),
            "degraded": AnyCodable(true),
            "captured_at": AnyCodable(now),
        ])
    }

    /// Le rail vit dans le même process que le daemon (SPEC-024). `running`
    /// reflète directement la présence d'un RailController instancié sur Daemon.
    private static func handleRailStatus(daemon: Daemon) -> Response {
        let isRunning = daemon.railController != nil
        return .success([
            "running": AnyCodable(isRunning),
            "inprocess": AnyCodable(true),
            "pid": AnyCodable(Int(ProcessInfo.processInfo.processIdentifier)),
        ])
    }

    /// Toggle rail in-process. Pas d'état persistant à toggler — le rail est
    /// toujours instancié au boot du daemon (cf. RailIntegration.start()).
    /// Conservé pour compat CLI ascendante : retourne le statut courant sans
    /// muter (l'utilisateur ne peut pas désactiver le rail à la volée en V2,
    /// il faut éditer `[fx.rail].enabled = false` dans roadies.toml).
    private static func handleRailToggle(daemon: Daemon) -> Response {
        return .success([
            "action": AnyCodable("noop_inprocess"),
            "running": AnyCodable(daemon.railController != nil),
            "hint": AnyCodable("Le rail est intégré au daemon depuis SPEC-024. Désactivation via [fx.rail].enabled = false dans roadies.toml."),
        ])
    }

    // MARK: - SPEC-014 utilities

    private static func iso8601String(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    private static func fileCreationISO(_ path: String) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let date = attrs?[.creationDate] as? Date ?? Date()
        return iso8601String(date)
    }

    /// SPEC-019 — lecture de la clé `[fx.rail].renderer` depuis le TOML utilisateur.
    /// Retourne nil si absente, vide ou TOML illisible.
    private static func readCurrentRendererID() -> String? {
        let path = (NSString(string: "~/.config/roadies/roadies.toml")
            .expandingTildeInPath as String)
        guard let data = FileManager.default.contents(atPath: path),
              let toml = String(data: data, encoding: .utf8),
              let root = try? TOMLTable(string: toml),
              let fx = root["fx"]?.table,
              let rail = fx["rail"]?.table,
              let v = rail["renderer"]?.string,
              !v.isEmpty
        else { return nil }
        return v
    }

    /// SPEC-019 — écriture idempotente de `[fx.rail].renderer = "<id>"`. Préserve
    /// le reste de la section et du fichier. Crée le fichier + section si absent.
    private static func writeRendererID(_ id: String) throws {
        let path = (NSString(string: "~/.config/roadies/roadies.toml")
            .expandingTildeInPath as String)
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir,
                                                  withIntermediateDirectories: true)
        var lines: [String]
        if let data = FileManager.default.contents(atPath: path),
           let content = String(data: data, encoding: .utf8) {
            lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        } else {
            lines = []
        }
        // Trouver la section [fx.rail], y mettre/remplacer la clé renderer.
        var inFxRail = false
        var rendererLineIdx: Int? = nil
        var fxRailHeaderIdx: Int? = nil
        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                inFxRail = (trimmed == "[fx.rail]")
                if inFxRail { fxRailHeaderIdx = idx }
                continue
            }
            if inFxRail, trimmed.hasPrefix("renderer") {
                rendererLineIdx = idx
                break
            }
        }
        let newLine = "renderer = \"\(id)\""
        if let i = rendererLineIdx {
            lines[i] = newLine
        } else if let h = fxRailHeaderIdx {
            lines.insert(newLine, at: h + 1)
        } else {
            if !lines.isEmpty && !(lines.last?.isEmpty ?? true) { lines.append("") }
            lines.append("[fx.rail]")
            lines.append(newLine)
        }
        try lines.joined(separator: "\n").write(toFile: path,
                                                atomically: true, encoding: .utf8)
    }

    private static func resizeImage(_ image: NSImage, to size: NSSize) -> NSImage {
        let result = NSImage(size: size)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        result.unlockFocus()
        return result
    }

    private static func pngEncode(_ image: NSImage) -> Data {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return Data()
        }
        return png
    }

}
