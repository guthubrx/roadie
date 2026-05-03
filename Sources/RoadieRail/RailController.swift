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
    // SPEC-018 polish — halo de la stage active. Default vert système Apple #34C759 à 0.65.
    var haloColor: String = "#34C759"
    var haloIntensity: Double = 0.65

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
        guard let panel = panel(for: screen) else { return }
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
            if config.displayMode == "per_display" {
                let evtUUID = payload["display_uuid"] as? String ?? ""
                if !evtUUID.isEmpty && !panelBelongsToUUID(evtUUID) { return }
                // Filtre desktop_id : si l'event cible un desktop précis, ne recharger
                // que si c'est le desktop courant du rail (state.currentDesktopID).
                if let evtDesktop = payload["desktop_id"] as? Int, evtDesktop != 0 {
                    guard evtDesktop == state.currentDesktopID else { return }
                }
            }
            loadInitialStages()
            loadWindows()
        case "desktop_changed":
            if let id = payload["desktop_id"] as? Int { state.currentDesktopID = id }
            // Après changement de desktop, resync les stages du nouveau desktop.
            loadInitialStages()
        case "thumbnail_updated":
            if let widRaw = payload["wid"] as? Int {
                fetcher.invalidate(wid: CGWindowID(widRaw))
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
        // SPEC-014 T041 : injecte switchToStage via closure capturée faiblement.
        let onTap: (String) -> Void = { [weak self] id in
            Task { @MainActor [weak self] in self?.switchToStage(id) }
        }
        // SPEC-014 T053 (US3) : drop chip → assign window à la stage cible.
        let onDrop: (CGWindowID, String) -> Void = { [weak self] wid, target in
            Task { @MainActor [weak self] in self?.assignWindow(wid, to: target) }
        }
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
            let view = StageStackView(
                state: state,
                haloColorHex: config.haloColor,
                haloIntensity: config.haloIntensity,
                onTapStage: onTap,
                onDropAssign: onDrop,
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
        Task {
            do {
                let payload = try await ipc.send(command: "stage.list")
                let stages = parseStages(from: payload)
                state.stages = stages
                state.connectionState = .connected
            } catch RailIPCError.daemonNotRunning {
                state.connectionState = .offline(reason: "daemon not running")
            } catch {
                state.connectionState = .offline(reason: "\(error)")
            }
        }
    }

    private func parseStages(from payload: [String: Any]) -> [StageVM] {
        guard let list = payload["stages"] as? [[String: Any]] else { return [] }
        let current = payload["current"] as? String ?? ""
        return list.compactMap { dict in
            guard let id = dict["id"] as? String else { return nil }
            let name = (dict["display_name"] as? String) ?? (dict["name"] as? String) ?? "Stage \(id)"
            // is_active vient du daemon (SPEC-014 T041) ; fallback : compare avec current.
            let active = (dict["is_active"] as? Bool) ?? (id == current)
            let wids = (dict["window_ids"] as? [Int])?.map { CGWindowID($0) } ?? []
            let desktop = dict["desktop_id"] as? Int ?? 1
            return StageVM(id: id, displayName: name, isActive: active,
                           windowIDs: wids, desktopID: desktop)
        }
    }

    // MARK: - SPEC-014 US3 (T053) : drag-drop chip → assign window à un stage.

    /// Envoie `stage.assign` au daemon avec wid + cible. Update optimiste local.
    /// Le daemon émet ensuite `window_assigned` qui re-sync via loadInitialStages.
    func assignWindow(_ wid: CGWindowID, to stageID: String) {
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
                _ = try await ipc.send(command: "stage.assign",
                                       args: ["stage_id": stageID, "wid": String(wid)])
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
    func switchToStage(_ id: String) {
        // Pas de re-trigger si déjà active (FR-018).
        if state.stages.first(where: { $0.id == id })?.isActive == true { return }
        // Update optimiste : marque la cible active immédiatement.
        state.stages = state.stages.map { stage in
            StageVM(id: stage.id, displayName: stage.displayName,
                    isActive: stage.id == id,
                    windowIDs: stage.windowIDs, desktopID: stage.desktopID)
        }
        state.activeStageID = id
        Task {
            do {
                _ = try await ipc.send(command: "stage.switch", args: ["stage_id": id])
            } catch {
                logErr("rail: stage.switch \(id) failed: \(error)")
                // Re-sync depuis le daemon en cas d'échec.
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
