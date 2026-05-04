import AppKit
import Foundation
import RoadieCore
import TOMLKit

// SPEC-014 T032 + T032b — Orchestrateur global : 1 panel par écran, IPC, events.

// MARK: - TOML helpers

/// Lecture d'une clé numérique (Double ou Int) avec clamping, retour `nil` si absente.
private func parsePreviewKey(_ table: TOMLTable, _ key: String, min lo: Double, max hi: Double) -> Double? {
    if let v = table[key]?.double { return max(lo, min(hi, v)) }
    if let v = table[key]?.int    { return max(lo, min(hi, Double(v))) }
    return nil
}

/// Mapping clé TOML → rendererID enregistré. Convention : la clé TOML est le préfixe
/// court, le rendererID complet contient parfois un suffixe (ex: stacked → stacked-previews).
private func resolveRendererID(fromTOMLKey key: String) -> String {
    switch key {
    case "stacked":  return "stacked-previews"
    case "parallax": return "parallax-45"
    default:         return key  // mosaic, hero-preview, icons-only : déjà identiques
    }
}

// MARK: - Per-renderer overrides

/// SPEC-019 — overrides optionnels d'un renderer sur les paramètres preview
/// globaux. nil = inherit du global ([fx.rail.preview]).
struct RendererPreviewOverrides {
    var width:           Double?
    var height:          Double?
    var leadingPadding:  Double?
    var trailingPadding: Double?
    var verticalPadding: Double?
    var borderColor:         String?
    var borderColorInactive: String?
    var borderWidth:         Double?
    var borderStyle:         String?
    var stageBorderOverrides: [String: String]?
}

/// Tuple résolu de la preview effective pour un renderer donné.
struct EffectivePreview {
    let width:           Double
    let height:          Double
    let leadingPadding:  Double
    let trailingPadding: Double
    let verticalPadding: Double
    let borderColor:         String
    let borderColorInactive: String
    let borderWidth:         Double
    let borderStyle:         String
    let stageBorderOverrides: [String: String]
}

// MARK: - Config

/// Configuration lue depuis [fx.rail] + [desktops] dans roadies.toml.
/// Fallback aux défauts (FR-031).
struct RailConfig {
    var enabled: Bool = true
    var reclaimHorizontalSpace: Bool = false
    var wallpaperClickToStage: Bool = true
    var panelWidth: CGFloat = 320
    var edgeWidth: CGFloat = 8
    /// Click sur zone vide du rail (hors thumbnails + ceinture de sécurité) =
    /// hide toutes les fenêtres de la stage active du display courant. Pattern
    /// Stage Manager natif Apple. Pas de toggle (no-op si déjà hide) — pour
    /// ressortir, l'utilisateur clique une thumbnail.
    // SPEC-025 T001 — default false (était true V1). Cause de BUG-001 quand
    // déclenché par accident. Power-users peuvent ré-activer via TOML :
    //   [fx.rail] empty_click_hide_active = true
    var emptyClickHideActive: Bool = false
    /// Marge invisible (en px) autour de chaque thumbnail. Un click qui tombe
    /// dans cette ceinture est ignoré (ni "switch stage" ni "hide active") —
    /// évite les hide accidentels quand l'utilisateur vise une thumbnail mais
    /// rate de quelques pixels.
    var emptyClickSafetyMargin: Double = 12
    var fadeDurationMs: Int = 200
    /// Durée pendant laquelle le panel reste visible après que le curseur quitte
    /// la zone d'edge (`[fx.rail].persistence_ms`).
    /// - `-1` (défaut, sentinel "non configuré") : comportement legacy = fade-out immédiat à l'exit.
    /// - `0` : always-visible. Le panel apparaît au démarrage et n'est jamais caché.
    /// - `N > 0` : reste affiché N ms après l'exit puis fade-out (cancellable si re-enter).
    var persistenceMs: Int = -1
    // SPEC-014 T090 (US7) : mode display ("per_display" ou "global").
    var displayMode: String = "per_display"
    // SPEC-018 polish — halo de la stage active. Default vert système Apple #34C759.
    var haloEnabled: Bool = true   // SPEC-019 : on/off global du halo
    var haloColor: String = "#34C759"
    var haloIntensity: Double = 0.75
    var haloRadius: Double = 18
    // SPEC-019 — id du renderer actif. nil → fallback "stacked-previews" via le registry.
    var rendererID: String? = nil
    // SPEC-019 — paramètres scatter du renderer "stacked-previews".
    // Defaults marqués (effet « polaroïds éparpillés »). Tous configurables
    // via [fx.rail.stacked] dans le TOML utilisateur.
    var stackedOffsetX:   Double = 60   // ±px horizontal max par couche idx>=1
    var stackedOffsetY:   Double = 80   // ±px vertical max
    var stackedRotation:  Double = 12   // ±deg max
    var stackedScale:     Double = 0.06 // réduction par couche
    var stackedOpacity:   Double = 0.10 // transparence additionnelle par couche
    var stackedScatterMode: String = "compass" // "compass" | "random"
    // SPEC-019 — paramètres renderer "parallax-45". Configurables via
    // [fx.rail.parallax] TOML.
    var parallaxRotation: Double  = 35  // ° rotation 3D axe Y
    var parallaxOffsetX:  Double  = 18  // px décalage horizontal par couche
    var parallaxOffsetY:  Double  = 8   // px décalage vertical par couche
    var parallaxScale:    Double  = 0.05 // réduction par couche
    var parallaxOpacity:  Double  = 0.10 // transparence additionnelle par couche
    // SPEC-019 — taille des vignettes (WindowPreview) et distance depuis le bord
    // gauche du panel. Configurables via [fx.rail.preview] TOML.
    var previewWidth:    Double = 200   // px largeur thumbnail
    var previewHeight:   Double = 130   // px hauteur thumbnail
    var leadingPadding:  Double = 8     // px distance bord gauche
    var trailingPadding: Double = 16    // px distance bord droit
    var verticalPadding: Double = 20    // px padding vertical
    // SPEC-019 — bordure des vignettes. Hex (RGB ou RGBA), épaisseur, style trait.
    var borderColor:         String = "#FFFFFF26" // bordure du stage ACTIF (défaut)
    var borderColorInactive: String = "#80808033" // bordure des stages INACTIFS (gris ~20%)
    var borderWidth:     Double = 0.5         // px
    var borderStyle:     String = "solid"     // "solid" | "dashed" | "dotted"
    /// SPEC-019 — couleurs de bordure par stage actif. Mappe stage_id → hex.
    /// Quand un stage est actif et a un override ici, sa bordure prend cette
    /// couleur au lieu du défaut `borderColor`. Mirror du pattern fx.borders.
    var stageBorderOverrides: [String: String] = [:]
    // SPEC-019 — assombrissement progressif par couche pour le renderer parallax-45.
    // 0 = aucun effet. 0.10 = chaque couche idx perd ~10% de luminosité.
    var parallaxDarkenPerLayer: Double = 0.0
    // SPEC-019 — overrides par renderer. Chaque [fx.rail.<id>] peut redéfinir
    // n'importe lequel des 5 paramètres preview ci-dessus. Fallback sur le global
    // si non spécifié.
    var rendererOverrides: [String: RendererPreviewOverrides] = [:]

    var fadeDuration: TimeInterval { TimeInterval(fadeDurationMs) / 1000 }

    /// SPEC-019 — résout la preview effective pour un renderer donné en appliquant
    /// les overrides `[fx.rail.<id>]` sur les défauts globaux `[fx.rail.preview]`.
    func effectivePreview(for rendererID: String) -> EffectivePreview {
        let o = rendererOverrides[rendererID]
        return EffectivePreview(
            width:           o?.width           ?? previewWidth,
            height:          o?.height          ?? previewHeight,
            leadingPadding:  o?.leadingPadding  ?? leadingPadding,
            trailingPadding: o?.trailingPadding ?? trailingPadding,
            verticalPadding: o?.verticalPadding ?? verticalPadding,
            borderColor:          o?.borderColor          ?? borderColor,
            borderColorInactive:  o?.borderColorInactive  ?? borderColorInactive,
            borderWidth:          o?.borderWidth          ?? borderWidth,
            borderStyle:          o?.borderStyle          ?? borderStyle,
            stageBorderOverrides: o?.stageBorderOverrides ?? stageBorderOverrides
        )
    }

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
            if let v = rail["empty_click_hide_active"]?.bool { cfg.emptyClickHideActive = v }
            if let v = rail["empty_click_safety_margin"]?.double {
                cfg.emptyClickSafetyMargin = max(0, min(60, v))
            } else if let v = rail["empty_click_safety_margin"]?.int {
                cfg.emptyClickSafetyMargin = max(0, min(60, Double(v)))
            }
            if let v = rail["panel_width"]?.int { cfg.panelWidth = CGFloat(v) }
            if let v = rail["edge_width"]?.int { cfg.edgeWidth = CGFloat(v) }
            if let v = rail["fade_duration_ms"]?.int { cfg.fadeDurationMs = v }
            if let v = rail["persistence_ms"]?.int { cfg.persistenceMs = max(0, v) }
            if let v = rail["halo_enabled"]?.bool { cfg.haloEnabled = v }
            if let v = rail["halo_color"]?.string { cfg.haloColor = v }
            if let v = rail["halo_intensity"]?.double { cfg.haloIntensity = max(0.0, min(1.0, v)) }
            else if let v = rail["halo_intensity"]?.int { cfg.haloIntensity = max(0.0, min(1.0, Double(v))) }
            if let v = rail["halo_radius"]?.double { cfg.haloRadius = max(0.0, min(80.0, v)) }
            else if let v = rail["halo_radius"]?.int { cfg.haloRadius = max(0.0, min(80.0, Double(v))) }
            // SPEC-019 — clé optionnelle [fx.rail].renderer = "<id>" pour switch de rendu.
            if let v = rail["renderer"]?.string, !v.isEmpty { cfg.rendererID = v }
            // SPEC-019 — sous-section [fx.rail.stacked] pour les paramètres scatter.
            if let stacked = rail["stacked"]?.table {
                if let v = stacked["offset_x"]?.double { cfg.stackedOffsetX = max(0, min(200, v)) }
                else if let v = stacked["offset_x"]?.int { cfg.stackedOffsetX = max(0, min(200, Double(v))) }
                if let v = stacked["offset_y"]?.double { cfg.stackedOffsetY = max(0, min(200, v)) }
                else if let v = stacked["offset_y"]?.int { cfg.stackedOffsetY = max(0, min(200, Double(v))) }
                if let v = stacked["rotation"]?.double { cfg.stackedRotation = max(0, min(45, v)) }
                else if let v = stacked["rotation"]?.int { cfg.stackedRotation = max(0, min(45, Double(v))) }
                if let v = stacked["scale_per_layer"]?.double { cfg.stackedScale = max(0, min(0.3, v)) }
                if let v = stacked["opacity_per_layer"]?.double { cfg.stackedOpacity = max(0, min(0.5, v)) }
                if let v = stacked["scatter_mode"]?.string, v == "compass" || v == "random" {
                    cfg.stackedScatterMode = v
                }
            }
            // SPEC-019 — sous-section [fx.rail.parallax] pour parallax-45.
            if let parallax = rail["parallax"]?.table {
                if let v = parallax["rotation"]?.double { cfg.parallaxRotation = max(0, min(75, v)) }
                else if let v = parallax["rotation"]?.int { cfg.parallaxRotation = max(0, min(75, Double(v))) }
                if let v = parallax["offset_x"]?.double { cfg.parallaxOffsetX = max(0, min(80, v)) }
                else if let v = parallax["offset_x"]?.int { cfg.parallaxOffsetX = max(0, min(80, Double(v))) }
                if let v = parallax["offset_y"]?.double { cfg.parallaxOffsetY = max(0, min(80, v)) }
                else if let v = parallax["offset_y"]?.int { cfg.parallaxOffsetY = max(0, min(80, Double(v))) }
                if let v = parallax["scale_per_layer"]?.double { cfg.parallaxScale = max(0, min(0.3, v)) }
                if let v = parallax["opacity_per_layer"]?.double { cfg.parallaxOpacity = max(0, min(0.5, v)) }
                if let v = parallax["darken_per_layer"]?.double { cfg.parallaxDarkenPerLayer = max(0, min(1.0, v)) }
            }
            // SPEC-019 — sous-section [fx.rail.preview] : défauts globaux pour TOUS
            // les renderers. Chaque clé peut être surchargée individuellement par
            // une sous-section [fx.rail.<id>] (ex: [fx.rail.parallax].leading_padding = 4).
            if let preview = rail["preview"]?.table {
                if let v = parsePreviewKey(preview, "width", min: 60, max: 600)            { cfg.previewWidth = v }
                if let v = parsePreviewKey(preview, "height", min: 40, max: 400)           { cfg.previewHeight = v }
                if let v = parsePreviewKey(preview, "leading_padding", min: 0, max: 200)   { cfg.leadingPadding = v }
                if let v = parsePreviewKey(preview, "trailing_padding", min: 0, max: 200)  { cfg.trailingPadding = v }
                if let v = parsePreviewKey(preview, "vertical_padding", min: 0, max: 200)  { cfg.verticalPadding = v }
                if let v = preview["border_color"]?.string { cfg.borderColor = v }
                if let v = preview["border_color_inactive"]?.string { cfg.borderColorInactive = v }
                if let v = parsePreviewKey(preview, "border_width", min: 0, max: 20)       { cfg.borderWidth = v }
                if let v = preview["border_style"]?.string,
                   ["solid", "dashed", "dotted"].contains(v) { cfg.borderStyle = v }
                // SPEC-019 — stage_overrides : tableau de tables { stage_id, active_color }
                if let arr = preview["stage_overrides"]?.array {
                    for item in arr {
                        guard let row = item.table,
                              let sid = row["stage_id"]?.string,
                              let color = row["active_color"]?.string else { continue }
                        cfg.stageBorderOverrides[sid] = color
                    }
                }
            }
            // SPEC-019 — overrides preview par renderer. On scanne TOUTES les sous-tables
            // de [fx.rail] et on extrait les 5 clés preview pour chacune. Les autres
            // clés (rotation, scatter_mode, etc.) restent traitées en-dessous par renderer.
            for (key, node) in rail where node.table != nil {
                guard let table = node.table, key != "preview" else { continue }
                var ov = RendererPreviewOverrides()
                ov.width           = parsePreviewKey(table, "width", min: 60, max: 600)
                ov.height          = parsePreviewKey(table, "height", min: 40, max: 400)
                ov.leadingPadding  = parsePreviewKey(table, "leading_padding", min: 0, max: 200)
                ov.trailingPadding = parsePreviewKey(table, "trailing_padding", min: 0, max: 200)
                ov.verticalPadding = parsePreviewKey(table, "vertical_padding", min: 0, max: 200)
                ov.borderColor         = table["border_color"]?.string
                ov.borderColorInactive = table["border_color_inactive"]?.string
                ov.borderWidth         = parsePreviewKey(table, "border_width", min: 0, max: 20)
                if let s = table["border_style"]?.string, ["solid", "dashed", "dotted"].contains(s) {
                    ov.borderStyle = s
                }
                if let arr = table["stage_overrides"]?.array {
                    var ovr: [String: String] = [:]
                    for item in arr {
                        guard let row = item.table,
                              let sid = row["stage_id"]?.string,
                              let color = row["active_color"]?.string else { continue }
                        ovr[sid] = color
                    }
                    if !ovr.isEmpty { ov.stageBorderOverrides = ovr }
                }
                if ov.width != nil || ov.height != nil
                    || ov.leadingPadding != nil || ov.trailingPadding != nil
                    || ov.verticalPadding != nil
                    || ov.borderColor != nil || ov.borderColorInactive != nil
                    || ov.borderWidth != nil || ov.borderStyle != nil
                    || ov.stageBorderOverrides != nil {
                    // Conversion sous-section TOML → renderer ID. [fx.rail.stacked]
                    // → "stacked-previews", [fx.rail.parallax] → "parallax-45", etc.
                    let id = resolveRendererID(fromTOMLKey: key)
                    cfg.rendererOverrides[id] = ov
                }
            }
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
public final class RailController {
    let state: RailState
    let ipc: RailDaemonProxy
    let eventStream: EventStreamInProcess
    let edgeMonitor: EdgeMonitor
    let fade: FadeAnimator
    let fetcher: ThumbnailFetcher

    private var panels: [CGDirectDisplayID: StageRailPanel] = [:]
    private var config: RailConfig = .init()
    /// Tasks de fade-out différé par display, indexées par `displayID`. Permet
    /// d'annuler le hide programmé si le curseur revient sur l'edge avant
    /// l'expiration de `persistenceMs`.
    private var pendingHideTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]

    /// SPEC-024 — accès in-process au daemon. Le `handler` est le `Daemon` lui-même
    /// (qui implémente `CommandHandler` dans RoadieCore.Server). Plus de socket Unix
    /// pour les appels rail→daemon : appel direct via le proxy.
    public init(handler: CommandHandler) {
        state = RailState()
        ipc = RailDaemonProxy(handler: handler)
        eventStream = EventStreamInProcess()
        edgeMonitor = EdgeMonitor()
        fade = FadeAnimator()
        fetcher = ThumbnailFetcher(ipc: ipc)
        // SPEC-019 — enregistrer les renderers livrés AVANT que les panels ne soient créés.
        // Le default `stacked-previews` DOIT être présent dans le registre, sinon
        // `StageRendererRegistry.makeOrFallback` trap fail-loud (cf. registry contract).
        registerBuiltinRenderers()
    }

    private var thumbnailRefreshTimer: Timer?

    public func start() {
        config = RailConfig.load()
        guard config.enabled else {
            logErr("rail: disabled via config (fx.rail.enabled = false)")
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
        // SPEC-022 — collecter wids depuis stagesByDisplay (per-scope), pas state.stages
        // (flat keyed par stageID). En multi-display avec stage "1" sur 2 écrans, le flat
        // collapse perd les wids d'un display → fetch incomplet → vignettes manquantes
        // côté display "perdant".
        var visibleWids = Set<CGWindowID>()
        for (_, list) in state.stagesByDisplay {
            for stage in list {
                visibleWids.formUnion(stage.windowIDs)
            }
        }
        // Fallback compat : si stagesByDisplay vide (mode global), retomber sur state.stages.
        if visibleWids.isEmpty {
            visibleWids = Set(state.stages.flatMap { $0.windowIDs })
        }
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
        // Annuler tout fade-out en attente sur ce display (cas re-enter pendant
        // la fenêtre de persistance).
        let did = displayID(for: screen)
        pendingHideTasks[did]?.cancel()
        pendingHideTasks.removeValue(forKey: did)
        // SPEC-014 T081 (US6) : reclaim horizontal space si activé en config.
        if config.reclaimHorizontalSpace {
            sendTilingReserve(size: Int(config.panelWidth), display: screen)
        }
        fade.fadeIn(panel, duration: config.fadeDuration)
    }

    func handleExitEdge(_ screen: NSScreen) {
        guard let panel = panel(for: screen) else { return }
        // Mode always-visible : ignorer l'exit, le panel reste affiché.
        if config.persistenceMs == 0 { return }
        // SPEC-014 T082 (US6) : restaure le workArea au début du fade-out.
        if config.reclaimHorizontalSpace {
            sendTilingReserve(size: 0, display: screen)
        }
        let doFadeOut: @MainActor () -> Void = { [weak self] in
            guard let self = self else { return }
            self.fade.fadeOut(panel, duration: self.config.fadeDuration) { panel.orderOut(nil) }
        }
        if config.persistenceMs > 0 {
            // Délai cancellable : si le curseur revient sur l'edge avant l'expiration,
            // handleEnterEdge annule cette task et le panel reste affiché.
            let did = displayID(for: screen)
            pendingHideTasks[did]?.cancel()
            let delayNs = UInt64(config.persistenceMs) * 1_000_000
            pendingHideTasks[did] = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled, let self = self else { return }
                self.pendingHideTasks.removeValue(forKey: did)
                doFadeOut()
            }
        } else {
            // Comportement legacy (persistenceMs == -1, sentinel "non configuré") :
            // fade-out immédiat à l'exit.
            doFadeOut()
        }
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
        case "window_focused":
            // SPEC-019 — promouvoir la vignette focused au rang « hero » (idx=0)
            // dans le renderer stacked-previews. Coût : un appel windows.list (pas
            // de thumbnails refetched, juste les VM avec is_focused mis à jour).
            loadWindows()
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
                logInfo("renderer_changed", ["from": oldRenderer, "to": newRenderer])
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
                        isFloating: w["is_floating"] as? Bool ?? false,
                        isFocused: w["is_focused"] as? Bool ?? false
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
            let onEmptyClickScoped: () -> Void = { [weak self] in
                Task { @MainActor [weak self] in self?.hideActiveStage(displayUUID: panelUUID) }
            }
            // SPEC-019 — résoudre la preview effective pour le renderer actif.
            // Renderer changes (config_reloaded) déclenchent rebuildPanels → re-résolution.
            let activeRendererID = config.rendererID ?? StageRendererRegistry.defaultID
            let effective = config.effectivePreview(for: activeRendererID)
            let view = StageStackView(
                state: state,
                displayUUID: panelUUID,
                haloColorHex: config.haloColor,
                haloIntensity: config.haloIntensity,
                haloRadius: config.haloRadius,
                rendererID: config.rendererID,
                stackedOffsetX: config.stackedOffsetX,
                stackedOffsetY: config.stackedOffsetY,
                stackedRotation: config.stackedRotation,
                stackedScale: config.stackedScale,
                stackedOpacity: config.stackedOpacity,
                stackedScatterMode: config.stackedScatterMode,
                parallaxRotation: config.parallaxRotation,
                parallaxOffsetX: config.parallaxOffsetX,
                parallaxOffsetY: config.parallaxOffsetY,
                parallaxScale: config.parallaxScale,
                parallaxOpacity: config.parallaxOpacity,
                previewWidth: effective.width,
                previewHeight: effective.height,
                leadingPadding: effective.leadingPadding,
                trailingPadding: effective.trailingPadding,
                verticalPadding: effective.verticalPadding,
                borderColor: effective.borderColor,
                borderColorInactive: effective.borderColorInactive,
                borderWidth: effective.borderWidth,
                borderStyle: effective.borderStyle,
                stageBorderOverrides: effective.stageBorderOverrides,
                haloEnabled: config.haloEnabled,
                parallaxDarkenPerLayer: config.parallaxDarkenPerLayer,
                onTapStage: onTapScoped,
                onDropAssign: onDropScoped,
                onRename: onRename,
                onAddFocused: onAddFocused,
                onDelete: onDelete,
                emptyClickHideActive: config.emptyClickHideActive,
                emptyClickSafetyMargin: config.emptyClickSafetyMargin,
                onEmptyClick: onEmptyClickScoped
            )
            let panel = StageRailPanel(rootView: view)
            panel.position(on: screen, width: config.panelWidth, edgeWidth: config.edgeWidth)
            panels[id] = panel
        }
        state.screens = NSScreen.screens.map { screenInfo(from: $0) }
        state.displayMode = config.displayMode == "global" ? .global : .perDisplay
        // Mode always-visible : afficher tous les panels immédiatement, sans attendre
        // un edge-hover. Le fade-out est neutralisé dans handleExitEdge.
        if config.persistenceMs == 0 {
            for (id, panel) in panels {
                if config.reclaimHorizontalSpace,
                   let screen = NSScreen.screens.first(where: { displayID(for: $0) == id }) {
                    sendTilingReserve(size: Int(config.panelWidth), display: screen)
                }
                fade.fadeIn(panel, duration: config.fadeDuration)
            }
        }
    }

    private func rebuildPanels() {
        // Annuler les pending hides : les panels vont être recréés.
        for (_, task) in pendingHideTasks { task.cancel() }
        pendingHideTasks.removeAll()
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

    /// Click sur zone vide du rail (hors thumbnails + ceinture de sécurité).
    /// Hide toutes les fenêtres de la stage active du display ciblé. Pattern
    /// Apple Stage Manager natif. Pour ressortir, l'utilisateur clique une thumbnail.
    func hideActiveStage(displayUUID: String = "") {
        Task {
            do {
                var args: [String: String] = [:]
                if !displayUUID.isEmpty { args["display"] = displayUUID }
                _ = try await ipc.send(command: "stage.hide_active", args: args)
            } catch {
                logErr("rail: stage.hide_active failed: \(error)")
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
