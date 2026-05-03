import AppKit
import Foundation
import TOMLKit

// SPEC-014 T032 + T032b — Orchestrateur global : 1 panel par écran, IPC, events.

// MARK: - Config

/// Configuration lue depuis [fx.rail] + [desktops] dans roadies.toml.
/// Fallback aux défauts (FR-031).
struct RailConfig {
    var enabled: Bool = true
    var reclaimHorizontalSpace: Bool = false
    var wallpaperClickToStage: Bool = true
    var panelWidth: CGFloat = 320
    var edgeWidth: CGFloat = 8
    var fadeDurationMs: Int = 200
    // SPEC-014 T090 (US7) : mode display ("per_display" ou "global").
    var displayMode: String = "per_display"
    // SPEC-018 polish — halo de la stage active. Default vert système Apple #34C759.
    var haloColor: String = "#34C759"
    var haloIntensity: Double = 0.75
    var haloRadius: Double = 18
    // SPEC-019 — id du renderer actif. nil → fallback "stacked-previews" via le registry.
    var rendererID: String? = nil

    var fadeDuration: TimeInterval { TimeInterval(fadeDurationMs) / 1000 }

    /// Lit les sections [fx.rail] et [desktops] depuis le TOML. Defaults (FR-031) si absentes.
    static func load() -> RailConfig {
        let path = (NSString(string: "~/.config/roadies/roadies.toml").expandingTildeInPath as String)
        guard let data = FileManager.default.contents(atPath: path),
              let toml = String(data: data, encoding: .utf8),
              let root = try? TOMLTable(string: toml)
        else { return RailConfig() }

        var cfg = RailConfig()
        if let fx = root["fx"]?.table, let rail = fx["rail"]?.table {
            if let v = rail["enabled"]?.bool { cfg.enabled = v }
            if let v = rail["reclaim_horizontal_space"]?.bool { cfg.reclaimHorizontalSpace = v }
            if let v = rail["wallpaper_click_to_stage"]?.bool { cfg.wallpaperClickToStage = v }
            if let v = rail["panel_width"]?.int { cfg.panelWidth = CGFloat(v) }
            if let v = rail["edge_width"]?.int { cfg.edgeWidth = CGFloat(v) }
            if let v = rail["fade_duration_ms"]?.int { cfg.fadeDurationMs = v }
            if let v = rail["halo_color"]?.string { cfg.haloColor = v }
            if let v = rail["halo_intensity"]?.double { cfg.haloIntensity = max(0.0, min(1.0, v)) }
            else if let v = rail["halo_intensity"]?.int { cfg.haloIntensity = max(0.0, min(1.0, Double(v))) }
            if let v = rail["halo_radius"]?.double { cfg.haloRadius = max(0.0, min(80.0, v)) }
            else if let v = rail["halo_radius"]?.int { cfg.haloRadius = max(0.0, min(80.0, Double(v))) }
            // SPEC-019 — clé optionnelle [fx.rail].renderer = "<id>" pour switch de rendu.
            if let v = rail["renderer"]?.string, !v.isEmpty { cfg.rendererID = v }
        }
        // SPEC-014 T090 : [desktops] mode informe si rails per_display ou global.
        if let desktops = root["desktops"]?.table,
           let mode = desktops["mode"]?.string {
            cfg.displayMode = mode
        }
        return cfg
    }
}

// MARK: - Controller

/// Orchestrateur principal du rail. Gère panels, IPC, event stream et edge monitor.
@MainActor
final class RailController {
    let state: RailState
    let ipc: RailIPCClient
    let eventStream: EventStream
    let edgeMonitor: EdgeMonitor
    let fade: FadeAnimator
    let fetcher: ThumbnailFetcher

    private var panels: [CGDirectDisplayID: StageRailPanel] = [:]
    private var config: RailConfig = .init()

    init() {
        state = RailState()
        ipc = RailIPCClient()
        eventStream = EventStream()
        edgeMonitor = EdgeMonitor()
        fade = FadeAnimator()
        fetcher = ThumbnailFetcher(ipc: ipc)
        // SPEC-019 — enregistrer les renderers livrés AVANT que les panels ne soient créés.
        // Le default `stacked-previews` DOIT être présent dans le registre, sinon
        // `StageRendererRegistry.makeOrFallback` trap fail-loud (cf. registry contract).
        registerBuiltinRenderers()
    }

    private var thumbnailRefreshTimer: Timer?

    func start() {
        config = RailConfig.load()
        guard config.enabled else {
            logErr("roadie-rail: disabled via config (fx.rail.enabled = false)")
            return
        }
        edgeMonitor.edgeWidth = config.edgeWidth
        edgeMonitor.activeZoneWidth = config.panelWidth
        buildPanels()
        startEdgeMonitor()
        startEventStream()
        loadInitialStages()
        loadWindows()
        startThumbnailRefresh()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.rebuildPanels() }
        }
    }

    /// SPEC-014 : refresh des vignettes ScreenCaptureKit toutes les 2 s.
    /// Le daemon coupe l'observation après 30 s sans requête, donc tant que le
    /// rail tourne il maintient le flux. Pas de polling si le panel n'est pas visible.
    private func startThumbnailRefresh() {
        thumbnailRefreshTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshThumbnails() }
        }
        RunLoop.main.add(timer, forMode: .common)
        thumbnailRefreshTimer = timer
        // Premier fetch immédiat pour ne pas attendre 2 s.
        Task { @MainActor in self.refreshThumbnails() }
    }

    private func refreshThumbnails() {
        // Collecte des wid affichées dans des stages non vides.
        let visibleWids = Set(state.stages.flatMap { $0.windowIDs })
        debugLog("refreshThumbnails: \(visibleWids.count) visible wids")
        for wid in visibleWids {
            fetcher.invalidate(wid: wid)
            Task {
                if let vm = await fetcher.fetch(wid: wid) {
                    state.thumbnails[wid] = vm
                    debugLog("thumbnail set for wid=\(wid) degraded=\(vm.degraded) bytes=\(vm.pngData.count)")
                } else {
                    debugLog("thumbnail FETCH FAILED for wid=\(wid)")
                }
            }
        }
    }

    // MARK: - Event handling

    func handleEnterEdge(_ screen: NSScreen) {
        debugLog("handleEnterEdge: screen=\(displayID(for: screen)) panels.count=\(panels.count)")
        guard let panel = panel(for: screen) else {
            debugLog("handleEnterEdge: no panel for this screen — buildPanels skipped this display ?")
            return
        }
        // SPEC-014 T081 (US6) : reclaim horizontal space si activé en config.
        if config.reclaimHorizontalSpace {
            sendTilingReserve(size: Int(config.panelWidth), display: screen)
        }
        fade.fadeIn(panel, duration: config.fadeDuration)
    }

    func handleExitEdge(_ screen: NSScreen) {
        guard let panel = panel(for: screen) else { return }
        // SPEC-014 T082 (US6) : restaure le workArea au début du fade-out.
        if config.reclaimHorizontalSpace {
            sendTilingReserve(size: 0, display: screen)
        }
        fade.fadeOut(panel, duration: config.fadeDuration) { panel.orderOut(nil) }
    }

    private func sendTilingReserve(size: Int, display screen: NSScreen) {
        let did = displayID(for: screen)
        Task {
            do {
                _ = try await ipc.send(command: "tiling.reserve",
                                       args: ["edge": "left", "size": String(size),
                                              "display_id": String(did)])
            } catch {
                logErr("rail: tiling.reserve size=\(size) failed: \(error)")
            }
        }
    }

    func handleEvent(_ name: String, _ payload: [String: Any]) {
        switch name {
        case "stage_changed", "window_assigned", "window_unassigned",
             "window_created", "window_destroyed", "stage_renamed",
             "stage_created", "stage_deleted", "stage_assigned":
            // SPEC-018 T062 : filtre côté client en mode per_display.
            // Si l'event porte un display_uuid non vide, vérifier qu'il correspond
            // à l'un des panels de ce rail. Sinon l'event vient d'un autre display → ignorer.
            // Si display_uuid est vide (mode global ou events sans scope), on passe toujours.
            //
            // SPEC-018 fix : avant 2026-05-03, le filtre était trop strict. Si le scope
            // inferré côté daemon (cursor/frontmost/primary) divergeait du panel courant,
            // les events stage_* étaient ignorés → rail désynchronisé silencieusement.
            // Maintenant : sur mismatch display, on déclenche quand même un poll léger
            // (loadInitialStages SEUL, pas loadWindows) pour resync au cas où l'état
            // global aurait changé. Compromis : un appel IPC supplémentaire occasionnel,
            // mais zero update manqué.
            if config.displayMode == "per_display" {
                let evtUUID = payload["display_uuid"] as? String ?? ""
                let evtDesktop = decodeInt(payload["desktop_id"]) ?? 0
                let displayMatch = evtUUID.isEmpty || panelBelongsToUUID(evtUUID)
                let desktopMatch = evtDesktop == 0 || evtDesktop == state.currentDesktopID
                if !displayMatch || !desktopMatch {
                    // Mismatch léger : poll stage list pour rester resynchro mais sans
                    // recharger la full liste windows (économie de bande IPC).
                    loadInitialStages()
                    return
                }
            }
            loadInitialStages()
            loadWindows()
        case "desktop_changed":
            if let id = payload["desktop_id"] as? Int { state.currentDesktopID = id }
            // Après changement de desktop, full resync : stages ET windows du nouveau
            // scope. Sans loadWindows, state.windows reste celui de l'ancien desktop
            // → WindowStack filtre les wids du nouveau desktop comme "orphelines".
            // Aussi : invalider les thumbnails locales pour refetch les nouvelles wids.
            loadInitialStages()
            loadWindows()
            state.thumbnails.removeAll()
        case "thumbnail_updated":
            if let widRaw = payload["wid"] as? Int {
                fetcher.invalidate(wid: CGWindowID(widRaw))
            }
        case "config_reloaded":
            // SPEC-019 — relire la config TOML (notamment [fx.rail].renderer)
            // et reconstruire les panels pour que le rail bascule sur le nouveau
            // renderer en moins d'une seconde, sans perdre l'état des stages.
            let oldRenderer = config.rendererID ?? StageRendererRegistry.defaultID
            config = RailConfig.load()
            let newRenderer = config.rendererID ?? StageRendererRegistry.defaultID
            if oldRenderer != newRenderer {
                debugLog("renderer_changed from=\(oldRenderer) to=\(newRenderer)")
                rebuildPanels()
            }
        default:
            break
        }
    }


    /// Retourne true si l'UUID correspond à l'un des panels de ce rail.
    /// Utilisé pour le filtre display_uuid des events stage_* (SPEC-018 T062).
    private func panelBelongsToUUID(_ uuid: String) -> Bool {
        state.screens.contains { $0.displayUUID == uuid }
    }

    /// SPEC-014 : charge le dictionnaire windows (pid, bundle, app_name) pour
    /// permettre au WindowChip de résoudre l'icône via NSRunningApplication.
    private func loadWindows() {
        Task {
            do {
                let payload = try await ipc.send(command: "windows.list")
                debugLog("loadWindows: payload keys = \(payload.keys.sorted())")
                guard let list = payload["windows"] as? [[String: Any]] else {
                    debugLog("loadWindows: payload[\"windows\"] cast FAILED. raw = \(String(describing: payload["windows"]))")
                    return
                }
                var dict: [CGWindowID: WindowVM] = [:]
                for w in list {
                    guard let idInt = w["id"] as? Int else { continue }
                    let pid = (w["pid"] as? Int).map { Int32($0) } ?? 0
                    let vm = WindowVM(
                        id: CGWindowID(idInt),
                        pid: pid,
                        bundleID: w["bundle"] as? String ?? "",
                        title: w["title"] as? String ?? "",
                        appName: w["app_name"] as? String ?? "",
                        isFloating: w["is_floating"] as? Bool ?? false
                    )
                    dict[vm.id] = vm
                }
                state.windows = dict
                debugLog("loadWindows: loaded \(dict.count) windows. sample wid+pid+name: " +
                         dict.prefix(3).map { "\($0.key)→pid=\($0.value.pid),app=\($0.value.appName)" }.joined(separator: "; "))
            } catch {
                debugLog("loadWindows: FAILED \(error)")
                logErr("rail: windows.list failed: \(error)")
            }
        }
    }

    // MARK: - Private

    private func buildPanels() {
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
        // SPEC-014 T090 (US7) : si mode "global" → 1 seul panel sur primary.
        let targetScreens: [NSScreen]
        if config.displayMode == "global" {
            let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
                ?? NSScreen.main
            targetScreens = primary.map { [$0] } ?? []
        } else {
            targetScreens = NSScreen.screens
        }
        debugLog("buildPanels: targetScreens=\(targetScreens.count) displayMode=\(config.displayMode)")
        // SPEC-019 — capturer le displayUUID de chaque panel pour les callbacks scopés.
        // Le switch IPC envoie alors `--display <uuid>` au daemon, qui résout dans
        // le bon scope au lieu de retomber sur l'inférence curseur (qui peut différer
        // si la souris a bougé entre la liste et le clic).
        // SPEC-014 T070-T073 (US5) : menu contextuel.
        let onRename: (String, String) -> Void = { [weak self] sid, name in
            Task { @MainActor [weak self] in self?.renameStage(sid, to: name) }
        }
        let onAddFocused: (String) -> Void = { [weak self] sid in
            Task { @MainActor [weak self] in self?.addFocusedToStage(sid) }
        }
        let onDelete: (String) -> Void = { [weak self] sid in
            Task { @MainActor [weak self] in self?.deleteStage(sid) }
        }
        for screen in targetScreens {
            let id = displayID(for: screen)
            let panelUUID = displayUUID(for: screen)
            // SPEC-019 — callbacks scopés par panel. Le tap/drop IPC porte le display
            // explicite : le daemon résout dans CE scope, plus dans l'inférence curseur.
            let onTapScoped: (String) -> Void = { [weak self] sid in
                Task { @MainActor [weak self] in self?.switchToStage(sid, displayUUID: panelUUID) }
            }
            let onDropScoped: (CGWindowID, String) -> Void = { [weak self] wid, target in
                Task { @MainActor [weak self] in
                    self?.assignWindow(wid, to: target, displayUUID: panelUUID)
                }
            }
            let view = StageStackView(
                state: state,
                displayUUID: panelUUID,
                haloColorHex: config.haloColor,
                haloIntensity: config.haloIntensity,
                haloRadius: config.haloRadius,
                rendererID: config.rendererID,
                onTapStage: onTapScoped,
                onDropAssign: onDropScoped,
                onRename: onRename,
                onAddFocused: onAddFocused,
                onDelete: onDelete
            )
            let panel = StageRailPanel(rootView: view)
            panel.position(on: screen, width: config.panelWidth, edgeWidth: config.edgeWidth)
            panels[id] = panel
        }
        state.screens = NSScreen.screens.map { screenInfo(from: $0) }
        state.displayMode = config.displayMode == "global" ? .global : .perDisplay
    }

    private func rebuildPanels() {
        buildPanels()
    }

    private func startEdgeMonitor() {
        edgeMonitor.onEnterEdge = { [weak self] screen in
            Task { @MainActor [weak self] in self?.handleEnterEdge(screen) }
        }
        edgeMonitor.onExitEdge = { [weak self] screen in
            Task { @MainActor [weak self] in self?.handleExitEdge(screen) }
        }
        edgeMonitor.start()
    }

    private func startEventStream() {
        eventStream.onEvent = { [weak self] name, payload in
            self?.handleEvent(name, payload)
        }
        eventStream.start()
    }

    private func loadInitialStages() {
        // SPEC-019 — charger les stages PAR DISPLAY pour que chaque panel affiche
        // strictement les stages de son écran (et pas le scope inferré curseur,
        // qui mixait les 2 displays dans `state.stages`).
        let uuids = panels.keys.compactMap { id -> String? in
            guard let cf = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue()
            else { return nil }
            return CFUUIDCreateString(nil, cf) as String?
        }
        Task {
            // Compat fallback : si aucun panel encore créé OU UUIDs vides, retomber
            // sur `stage.list` sans override (= scope curseur).
            if uuids.isEmpty {
                do {
                    let payload = try await ipc.send(command: "stage.list")
                    state.stages = parseStages(from: payload)
                    state.connectionState = .connected
                } catch RailIPCError.daemonNotRunning {
                    state.connectionState = .offline(reason: "daemon not running")
                } catch {
                    state.connectionState = .offline(reason: "\(error)")
                }
                return
            }
            // Une requête par display, en parallèle.
            for uuid in uuids {
                do {
                    let payload = try await ipc.send(command: "stage.list",
                                                     args: ["display": uuid])
                    let stages = parseStages(from: payload)
                    state.stagesByDisplay[uuid] = stages
                    debugLog("loadInitialStages: uuid=\(uuid.prefix(8)) stages=\(stages.count)")
                    state.connectionState = .connected
                } catch RailIPCError.daemonNotRunning {
                    state.connectionState = .offline(reason: "daemon not running")
                } catch {
                    // Une erreur sur un display ne tue pas les autres.
                    logErr("rail: stage.list display=\(uuid) failed: \(error)")
                }
            }
            // Conserver `state.stages` à plat pour les call-sites legacy : union de tous
            // les scopes (déduplication par id n'est pas nécessaire — les stage IDs
            // sont uniques par scope mais peuvent coexister entre displays avec valeurs
            // équivalentes ; la flat list garde tout, dernier écrit gagne par id).
            var flat: [String: StageVM] = [:]
            for (_, list) in state.stagesByDisplay {
                for s in list { flat[s.id] = s }
            }
            state.stages = Array(flat.values)
        }
    }

    private func parseStages(from payload: [String: Any]) -> [StageVM] {
        guard let list = payload["stages"] as? [[String: Any]] else { return [] }
        let current = decodeString(payload["current"]) ?? ""
        return list.compactMap { dict in
            guard let id = decodeString(dict["id"]) else { return nil }
            let name = decodeString(dict["display_name"]) ?? decodeString(dict["name"]) ?? "Stage \(id)"
            // SPEC-018 fix : is_active passe par decodeBool tolérant (le daemon peut
            // sérialiser en Bool, Int 0/1 ou NSNumber selon le bridging AnyCodable —
            // l'échec silencieux du cast `as? Bool` provoquait des halos verts sur 2
            // stages au lieu d'1). Fallback final : compare avec `current`.
            let active = decodeBool(dict["is_active"]) ?? (id == current)
            let wids = (dict["window_ids"] as? [Int])?.map { CGWindowID($0) } ?? []
            let desktop = decodeInt(dict["desktop_id"]) ?? 1
            return StageVM(id: id, displayName: name, isActive: active,
                           windowIDs: wids, desktopID: desktop)
        }
    }

    // MARK: - SPEC-014 US3 (T053) : drag-drop chip → assign window à un stage.

    /// Envoie `stage.assign` au daemon avec wid + cible. Update optimiste local.
    /// Le daemon émet ensuite `window_assigned` qui re-sync via loadInitialStages.
    func assignWindow(_ wid: CGWindowID, to stageID: String, displayUUID: String = "") {
        // Update optimiste : retire wid de tout stage, l'ajoute à la cible.
        state.stages = state.stages.map { stage in
            var ids = stage.windowIDs.filter { $0 != wid }
            if stage.id == stageID { ids.append(wid) }
            return StageVM(id: stage.id, displayName: stage.displayName,
                           isActive: stage.isActive, windowIDs: ids,
                           desktopID: stage.desktopID)
        }
        Task {
            do {
                // SPEC-019 — override `--display` explicite pour que le daemon
                // résolve le scope dans le bon écran (pas via inférence curseur).
                var args: [String: String] = ["stage_id": stageID, "wid": String(wid)]
                if !displayUUID.isEmpty { args["display"] = displayUUID }
                _ = try await ipc.send(command: "stage.assign", args: args)
            } catch {
                logErr("rail: stage.assign \(wid)→\(stageID) failed: \(error)")
                loadInitialStages()
            }
        }
    }

    // MARK: - SPEC-014 US5 (T071-T073) : menu contextuel daemon-side.

    func renameStage(_ id: String, to newName: String) {
        Task {
            do {
                _ = try await ipc.send(command: "stage.rename",
                                       args: ["stage_id": id, "new_name": newName])
            } catch {
                logErr("rail: stage.rename \(id)→\(newName) failed: \(error)")
            }
        }
    }

    func addFocusedToStage(_ id: String) {
        // Pas de wid → daemon utilise focusedWindowID (compat ascendante).
        Task {
            do {
                _ = try await ipc.send(command: "stage.assign", args: ["stage_id": id])
            } catch {
                logErr("rail: stage.assign focused→\(id) failed: \(error)")
            }
        }
    }

    func deleteStage(_ id: String) {
        // FR-019 : stage 1 immortel — déjà bloqué côté daemon, double-check ici.
        guard id != "1" else { return }
        Task {
            do {
                _ = try await ipc.send(command: "stage.delete", args: ["stage_id": id])
            } catch {
                logErr("rail: stage.delete \(id) failed: \(error)")
            }
        }
    }

    // MARK: - SPEC-014 US2 (T041) : switch stage via IPC sur tap.

    /// Envoie `stage.switch` au daemon. Optimiste : pré-update activeStageID
    /// localement pour réactivité visuelle, le `stage_changed` event confirme.
    func switchToStage(_ id: String, displayUUID: String = "") {
        // SPEC-019 — la stage cible peut être active dans le scope du panel d'origine
        // mais pas dans state.stages (= état partagé qui peut refléter un autre scope).
        // On lève le no-op : le daemon est seul juge, il fera no-op si déjà active.
        // Update optimiste : marque la cible active dans `stagesByDisplay[uuid]` ET
        // dans `state.stages` (pour les call-sites qui n'utilisent pas le scope).
        if !displayUUID.isEmpty, var scoped = state.stagesByDisplay[displayUUID] {
            scoped = scoped.map { stage in
                StageVM(id: stage.id, displayName: stage.displayName,
                        isActive: stage.id == id,
                        windowIDs: stage.windowIDs, desktopID: stage.desktopID)
            }
            state.stagesByDisplay[displayUUID] = scoped
        }
        state.stages = state.stages.map { stage in
            StageVM(id: stage.id, displayName: stage.displayName,
                    isActive: stage.id == id,
                    windowIDs: stage.windowIDs, desktopID: stage.desktopID)
        }
        state.activeStageID = id
        Task {
            do {
                var args: [String: String] = ["stage_id": id]
                if !displayUUID.isEmpty { args["display"] = displayUUID }
                _ = try await ipc.send(command: "stage.switch", args: args)
            } catch {
                logErr("rail: stage.switch \(id) failed: \(error)")
                loadInitialStages()
            }
        }
    }

    private func panel(for screen: NSScreen) -> StageRailPanel? {
        panels[displayID(for: screen)]
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) ?? 0
    }

    /// SPEC-019 — UUID stable du display pour ce screen (utilisé en override `--display`
    /// dans les requêtes IPC scopées). Vide si la résolution AX échoue.
    private func displayUUID(for screen: NSScreen) -> String {
        let id = displayID(for: screen)
        guard let cf = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "" }
        return CFUUIDCreateString(nil, cf) as String? ?? ""
    }

    private func screenInfo(from screen: NSScreen) -> ScreenInfo {
        let id = displayID(for: screen)
        let uuid = CGDisplayCreateUUIDFromDisplayID(id).map {
            CFUUIDCreateString(nil, $0.takeRetainedValue()) as String
        } ?? ""
        return ScreenInfo(id: id, frame: screen.frame, visibleFrame: screen.visibleFrame,
                          isMain: screen == NSScreen.main, displayUUID: uuid)
    }
}

private func logErr(_ msg: String) {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
}

/// Debug temporaire : append une ligne dans /tmp/roadie-rail-debug.log
/// (le rail est spawné par le daemon, son stderr part dans le néant ; ce log
/// permet de tracer ce qui se passe côté rail). À supprimer une fois OK.
@MainActor
private func debugLog(_ msg: String) {
    let path = "/tmp/roadie-rail-debug.log"
    let line = "[\(Date())] \(msg)\n"
    if let data = line.data(using: .utf8) {
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(data)
            try? fh.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}

// MARK: - SPEC-018 fix : helpers de cast robustes pour payloads JSON-AnyCodable
//
// Problème observé : `payload["x"] as? Bool` échoue silencieusement quand le JSON
// renvoie un Int (0/1) ou un NSNumber au lieu d'un Bool natif (cas typique
// JSONSerialization → AnyCodable bridging). Le fallback (nil ou autre default)
// peut masquer un vrai bug. Les helpers ci-dessous tentent toutes les
// représentations communes avant d'abandonner.

/// Décodage tolérant : Bool natif, NSNumber bool, Int (0=false, autre=true),
/// String ("true"/"false"/"1"/"0", case-insensitive). Retourne nil sinon.
func decodeBool(_ any: Any?) -> Bool? {
    guard let any = any else { return nil }
    if let b = any as? Bool { return b }
    if let n = any as? NSNumber { return n.boolValue }
    if let i = any as? Int { return i != 0 }
    if let s = any as? String {
        switch s.lowercased() {
        case "true", "1", "yes", "on": return true
        case "false", "0", "no", "off": return false
        default: return nil
        }
    }
    return nil
}

/// Décodage tolérant : Int natif, NSNumber, String numérique. Retourne nil sinon.
func decodeInt(_ any: Any?) -> Int? {
    guard let any = any else { return nil }
    if let i = any as? Int { return i }
    if let n = any as? NSNumber { return n.intValue }
    if let s = any as? String, let i = Int(s) { return i }
    if let d = any as? Double { return Int(d) }
    return nil
}

/// Décodage tolérant : String natif, NSString, ou description de tout autre type.
func decodeString(_ any: Any?) -> String? {
    guard let any = any else { return nil }
    if let s = any as? String { return s }
    if let n = any as? NSNumber { return n.stringValue }
    return "\(any)"
}
