import Foundation
import CoreGraphics
import RoadieCore
import RoadieFXCore
import RoadieStagePlugin

/// SPEC-026 (fix bug Firefox slide animation) — implémentation du protocol
/// `StageHideOverride` qui remplace `HideStrategy.corner` (setBounds offscreen,
/// animé par macOS) par un setAlpha=0 via OSAX (= invisible sans déplacement,
/// donc sans animation).
///
/// Activé via `[fx.opacity.stage_hide].enabled = true` dans le TOML, lu par le
/// daemon au boot. Si SIP fully on (osax non chargé), les commandes setAlpha
/// échouent silencieusement et la fenêtre ne disparaît pas — l'user doit alors
/// désactiver le flag pour retomber sur HideStrategy.corner.
@MainActor
public final class OpacityStageHider: StageHideOverride {
    private let bridge: OSAXBridge

    public init(bridge: OSAXBridge) {
        self.bridge = bridge
    }

    public func hide(wid: WindowID, isTileable: Bool) {
        let cgwid = CGWindowID(wid)
        Task { [bridge] in
            _ = await bridge.send(.setAlpha(wid: cgwid, alpha: 0.0))
        }
    }

    public func show(wid: WindowID, isTileable: Bool) {
        let cgwid = CGWindowID(wid)
        Task { [bridge] in
            _ = await bridge.send(.setAlpha(wid: cgwid, alpha: 1.0))
        }
    }
}
