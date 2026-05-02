import Foundation
import AppKit
import CoreGraphics
import RoadieCore
import RoadieFXCore
import TOMLKit

/// SPEC-008 RoadieBorders — bordure colorée focused/inactive autour fenêtres tracked.
/// Plafond LOC strict : 280 (cible 200). Gradient animé DROPPÉ après revue scope.
///
/// Le `BorderOverlay` utilise `NSWindowLevel.floating` natif. Pour forcer
/// l'overlay au-dessus de toutes les fenêtres (y compris elles-mêmes en
/// `.floating`), il faut que l'osax envoie un `setLevel` plus haut — reporté
/// à SPEC-004.1 (osax bundle Objective-C++).

public final class BordersModule: @unchecked Sendable {
    public static let shared = BordersModule()
    public var config = BordersConfig()
    private var focusedWID: CGWindowID?
    private var currentStageID: String?
    private var overlays: [CGWindowID: BorderOverlay] = [:]
    private let lock = NSLock()

    public func subscribe(to bus: FXEventBus) {
        loadConfigFromDisk()
        bus.subscribe(to: [.windowFocused, .windowCreated, .windowDestroyed,
                          .windowMoved, .windowResized,
                          .stageChanged, .desktopChanged,
                          .configReloaded]) { [weak self] event in
            self?.handle(event: event)
        }
    }

    /// Lit `[fx.borders]` dans `~/.config/roadies/roadies.toml` et applique
    /// la config résultante. Appelé au boot et sur event `.configReloaded`.
    /// Tolérant : fichier absent ou section absente → garde les défauts.
    func loadConfigFromDisk() {
        let path = ConfigLoader.defaultConfigPath()
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
            return
        }
        guard let root = try? TOMLTable(string: raw) else { return }
        guard let fx = root["fx"]?.table, let borders = fx["borders"]?.table else {
            return
        }
        var cfg = BordersConfig()
        if let v = borders["enabled"]?.bool { cfg.enabled = v }
        if let v = borders["thickness"]?.int { cfg.thickness = Int(v) }
        if let v = borders["corner_radius"]?.int { cfg.cornerRadius = Int(v) }
        if let v = borders["active_color"]?.string { cfg.activeColor = v }
        if let v = borders["inactive_color"]?.string { cfg.inactiveColor = v }
        if let v = borders["pulse_on_focus"]?.bool { cfg.pulseOnFocus = v }
        if let v = borders["focused_only"]?.bool { cfg.focusedOnly = v }
        if let arr = borders["stage_overrides"]?.array {
            cfg.stageOverrides = arr.compactMap { item -> StageOverride? in
                guard let t = item.table, let sid = t["stage_id"]?.string else { return nil }
                return StageOverride(stageID: sid, activeColor: t["active_color"]?.string)
            }
        }
        setConfig(cfg)
    }

    public func shutdown() {
        let toClose = lock.withLock { () -> [BorderOverlay] in
            let snap = Array(overlays.values)
            overlays.removeAll()
            focusedWID = nil
            currentStageID = nil
            return snap
        }
        Task { @MainActor in
            for overlay in toClose { overlay.close() }
        }
    }

    public func setConfig(_ cfg: BordersConfig) {
        lock.lock(); config = cfg; lock.unlock()
    }

    private func handle(event: FXEvent) {
        if event.kind == .configReloaded {
            loadConfigFromDisk()
            refreshAllColors()
            return
        }
        guard config.enabled else { return }
        switch event.kind {
        case .windowCreated:
            // Le daemon filtre déjà les non-tileables avant de publier sur
            // le bus FX (cf main.swift). Ici on accepte tout ce qui arrive.
            if let wid = event.wid, let frame = event.frame {
                spawnOverlay(wid: wid, frame: frame)
            }
        case .windowDestroyed:
            if let wid = event.wid { closeOverlay(wid: wid) }
        case .windowFocused:
            lock.lock(); focusedWID = event.wid; lock.unlock()
            refreshAllColors()
            // SPEC-008 pulse_on_focus : anime borderWidth de l'overlay focused.
            if config.pulseOnFocus, let wid = event.wid {
                let thickness = config.clampedThickness
                Task { @MainActor in
                    self.lock.lock()
                    let overlay = self.overlays[wid]
                    self.lock.unlock()
                    overlay?.pulse(from: thickness, to: thickness * 2)
                }
            }
        case .windowMoved, .windowResized:
            if let wid = event.wid, let frame = event.frame {
                Task { @MainActor in
                    self.lock.lock()
                    let overlay = self.overlays[wid]
                    self.lock.unlock()
                    overlay?.updateFrame(frame)
                }
            }
        case .stageChanged:
            lock.lock(); currentStageID = event.stageID; lock.unlock()
            refreshAllColors()
        default:
            break
        }
    }

    private func spawnOverlay(wid: CGWindowID, frame: CGRect) {
        let isFocused = (lock.withLock { focusedWID == wid })
        let colorHex = isFocused
            ? activeColor(forStage: lock.withLock { currentStageID }, config: config)
            : config.inactiveColor
        let nsColor = nsColor(fromHex: colorHex) ?? .systemBlue
        let thickness = config.clampedThickness
        let radius = config.clampedCornerRadius
        Task { @MainActor in
            let overlay = BorderOverlay(wid: wid, frame: frame,
                                        thickness: thickness, color: nsColor,
                                        cornerRadius: radius)
            self.lock.withLock { _ = self.overlays[wid].map { $0.close() }
                                 self.overlays[wid] = overlay }
            // SPEC-008 force level via osax : niveau 1000 met l'overlay au-dessus
            // de toutes les NSWindowLevel.floating natives (24).
            let overlayWID = overlay.overlayWindowID
            if overlayWID > 0 {
                _ = await BordersBridge.shared.send(.setLevel(wid: overlayWID, level: 1000))
            }
        }
    }

    private func closeOverlay(wid: CGWindowID) {
        let overlay = lock.withLock { overlays.removeValue(forKey: wid) }
        Task { @MainActor in overlay?.close() }
    }

    /// Recalcule la couleur de tous les overlays (focused → activeColor,
    /// autres → inactiveColor) ET la visibilité selon `focused_only`.
    /// Appelé sur focus_changed, stage_changed, configReloaded.
    private func refreshAllColors() {
        let (focused, stageID, inactive, focusedOnly, snapshot) = lock.withLock {
            (focusedWID, currentStageID, config.inactiveColor,
             config.focusedOnly, Array(overlays))
        }
        let activeHex = activeColor(forStage: stageID, config: config)
        Task { @MainActor in
            for (wid, overlay) in snapshot {
                let isFocused = (wid == focused)
                let hex = isFocused ? activeHex : inactive
                if let c = nsColor(fromHex: hex) {
                    overlay.updateColor(c)
                }
                overlay.setHidden(focusedOnly && !isFocused)
            }
        }
    }

    /// Calcule la couleur que l'overlay doit afficher pour une wid donnée.
    public func colorFor(wid: CGWindowID) -> String {
        lock.lock(); defer { lock.unlock() }
        if wid == focusedWID {
            return activeColor(forStage: currentStageID, config: config)
        }
        return config.inactiveColor
    }
}

/// Singleton OSAXBridge partagé pour ce module (envois setLevel).
public final class BordersBridge: @unchecked Sendable {
    public static let shared: OSAXBridge = OSAXBridge()
}

/// Convertit un RGBA (config) en NSColor. Retourne nil si le hex est invalide.
public func nsColor(fromHex hex: String) -> NSColor? {
    guard let rgba = parseHexColor(hex) else { return nil }
    return NSColor(deviceRed: CGFloat(rgba.r) / 255.0,
                   green: CGFloat(rgba.g) / 255.0,
                   blue: CGFloat(rgba.b) / 255.0,
                   alpha: CGFloat(rgba.a) / 255.0)
}

@_cdecl("roadie_fx_init_borders")
public func roadie_fx_init_borders() -> UnsafeMutableRawPointer {
    let vtable = UnsafeMutablePointer<FXModuleVTable>.allocate(capacity: 1)
    let nameStr = strdup("borders")!
    let versionStr = strdup("0.1.0")!
    vtable.initialize(to: FXModuleVTable(
        name: UnsafePointer(nameStr),
        version: UnsafePointer(versionStr),
        subscribe: { busPtr in
            BordersModule.shared.subscribe(to: FXEventBus.from(opaquePtr: busPtr))
        },
        shutdown: { BordersModule.shared.shutdown() }
    ))
    return UnsafeMutableRawPointer(vtable)
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        self.lock(); defer { self.unlock() }; return body()
    }
}
