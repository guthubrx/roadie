import Foundation
import CoreGraphics
import RoadieCore
import RoadieFXCore

/// SPEC-008 RoadieBorders — bordure colorée focused/inactive autour fenêtres tracked.
/// Plafond LOC strict : 280 (cible 200). Gradient animé DROPPÉ après revue scope.
///
/// L'implémentation NSWindow overlay (BorderOverlay.swift) est reportée à
/// l'étape post-merge framework SPEC-004. Ici on livre la logique pure :
/// parsing config, color resolver, contract event handler.

public final class BordersModule: @unchecked Sendable {
    public static let shared = BordersModule()
    public var config = BordersConfig()
    private var focusedWID: CGWindowID?
    private var currentStageID: String?
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
        // Pas d'overlay à fermer pour l'instant (BorderOverlay non implémenté en V1).
        lock.lock()
        focusedWID = nil
        currentStageID = nil
        lock.unlock()
    }

    public func setConfig(_ cfg: BordersConfig) {
        lock.lock(); config = cfg; lock.unlock()
    }

    private func handle(event: FXEvent) {
        guard config.enabled else { return }
        switch event.kind {
        case .windowFocused:
            lock.lock(); focusedWID = event.wid; lock.unlock()
            // BorderOverlay.update(focused: event.wid, color: activeColor(...))
        case .stageChanged:
            lock.lock(); currentStageID = event.stageID; lock.unlock()
            // Recompute la couleur active selon override stage et redessine.
        default:
            break
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
