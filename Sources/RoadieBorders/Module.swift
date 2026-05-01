import Foundation
import AppKit
import CoreGraphics
import RoadieCore
import RoadieFXCore

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
        bus.subscribe(to: [.windowFocused, .windowCreated, .windowDestroyed,
                          .windowMoved, .windowResized,
                          .stageChanged, .desktopChanged,
                          .configReloaded]) { [weak self] event in
            self?.handle(event: event)
        }
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
        guard config.enabled else { return }
        switch event.kind {
        case .windowCreated:
            if let wid = event.wid, let frame = event.frame {
                spawnOverlay(wid: wid, frame: frame)
            }
        case .windowDestroyed:
            if let wid = event.wid { closeOverlay(wid: wid) }
        case .windowFocused:
            lock.lock(); focusedWID = event.wid; lock.unlock()
            refreshAllColors()
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
        Task { @MainActor in
            let overlay = BorderOverlay(wid: wid, frame: frame,
                                        thickness: thickness, color: nsColor)
            self.lock.withLock { _ = self.overlays[wid].map { $0.close() }
                                 self.overlays[wid] = overlay }
        }
    }

    private func closeOverlay(wid: CGWindowID) {
        let overlay = lock.withLock { overlays.removeValue(forKey: wid) }
        Task { @MainActor in overlay?.close() }
    }

    /// Recalcule la couleur de tous les overlays (focused → activeColor,
    /// autres → inactiveColor). Appelé sur focus_changed et stage_changed.
    private func refreshAllColors() {
        let (focused, stageID, inactive, snapshot) = lock.withLock {
            (focusedWID, currentStageID, config.inactiveColor,
             Array(overlays))
        }
        let activeHex = activeColor(forStage: stageID, config: config)
        Task { @MainActor in
            for (wid, overlay) in snapshot {
                let hex = (wid == focused) ? activeHex : inactive
                if let c = nsColor(fromHex: hex) {
                    overlay.updateColor(c)
                }
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

/// Convertit un RGBA (config) en NSColor. Retourne nil si le hex est invalide.
public func nsColor(fromHex hex: String) -> NSColor? {
    guard let rgba = parseHexColor(hex) else { return nil }
    return NSColor(deviceRed: CGFloat(rgba.r) / 255.0,
                   green: CGFloat(rgba.g) / 255.0,
                   blue: CGFloat(rgba.b) / 255.0,
                   alpha: CGFloat(rgba.a) / 255.0)
}

@_cdecl("module_init")
public func module_init() -> UnsafeMutableRawPointer {
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
