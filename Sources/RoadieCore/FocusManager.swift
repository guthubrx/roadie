import Foundation
import ApplicationServices
import Cocoa

/// Synchronise l'état focus interne avec macOS.
/// Différenciateur du projet : utilise `kAXApplicationActivatedNotification` pour rattraper
/// les clics souris qui ne déclenchent pas correctement `kAXFocusedWindowChangedNotification`
/// sur les apps Electron / JetBrains.
@MainActor
public final class FocusManager {
    private let registry: WindowRegistry

    /// SPEC-026 US5 — config mouse_follows_focus. Settable depuis main.swift.
    public var mouseFollowsFocus: Bool = false

    /// SPEC-026 US5 — anti-feedback warp → focus_follows_mouse. Posé par les
    /// warps curseur, lu par FocusFollowsMouseWatcher pour skip son setFocus.
    public private(set) var inhibitFollowMouseUntil: Date?

    /// SPEC-026 US5 — anti-double-warp. Posé par focus_follows_mouse avant son
    /// setFocus (pour signaler au hook onFocusChanged "déjà sur la fenêtre, pas
    /// de warp"). Lu par warpCursorToFocusedIfEnabled. Distinct de
    /// `inhibitFollowMouseUntil` pour éviter qu'un mouvement souris bloque
    /// un warp légitime déclenché par Cmd+Tab arrivant juste après.
    public private(set) var inhibitWarpUntil: Date?

    /// SPEC-028 — anti-loop stage_follows_focus ↔ focus_follows_mouse. Quand
    /// le focus est causé par un hover souris, on ne veut pas que le stage
    /// switche automatiquement (sinon : hover → focus → stage switch →
    /// applyAll repositionne → wid sous curseur change → cycle).
    /// Posé par FocusFollowsMouseWatcher avant son setFocus, lu par le hook
    /// onFocusChanged → followFocusToStageAndDesktop.
    public private(set) var inhibitStageFollowsFocusUntil: Date?

    public init(registry: WindowRegistry) {
        self.registry = registry
    }

    /// Re-synchronise le focus à partir du système.
    /// Appelé à chaque kAXApplicationActivatedNotification + kAXFocusedWindowChangedNotification.
    public func refreshFromSystem() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            registry.setFocus(nil)
            return
        }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        guard let focused = AXReader.focusedWindow(of: appElement),
              let wid = axWindowID(of: focused)
        else {
            return
        }
        registry.setFocus(wid)
    }

    public func setFocus(to wid: WindowID) {
        guard let element = registry.axElement(for: wid) else {
            logWarn("setFocus: window AX element missing", ["wid": String(wid)])
            return
        }
        // SPEC-025 — ORDRE critique pour les apps multi-window (iTerm, Firefox) :
        //   1. SetMain + SetFocused sur la wid cible AVANT toute activation app.
        //      Ces 2 attributs définissent la "key window" de l'app cible AVANT
        //      qu'iTerm/Firefox ne choisisse leur propre key window au moment
        //      de l'activation.
        //   2. Raise (kAXRaiseAction) pour z-order intra-app.
        //   3. activate() UNIQUEMENT si l'app n'est pas déjà frontmost. Sinon
        //      iTerm reçoit un signal d'activation, "se réveille" et choisit
        //      SA propre key window (last-active interne, pas notre setMain) →
        //      le focus saute sur une autre fenêtre iTerm.
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXReader.raise(element)
        if let state = registry.get(wid),
           let app = NSRunningApplication(processIdentifier: state.pid),
           !app.isActive {
            app.activate()
        }
        registry.setFocus(wid)
        logInfo("focusManager_setFocus", ["wid": String(wid)])
    }

    /// SPEC-026 US5 — focus issu d'un raccourci (HJKL/warp/move/stage_switch).
    /// Comportement = setFocus(to:) + warp curseur si mouseFollowsFocus activé.
    /// Pose un flag anti-feedback de 200ms pour éviter le re-trigger du
    /// FocusFollowsMouseWatcher au mouseMoved suivant.
    public func setFocusFromShortcut(to wid: WindowID) {
        setFocus(to: wid)
        guard mouseFollowsFocus else { return }
        guard let state = registry.get(wid) else { return }
        let center = CGPoint(x: state.frame.midX, y: state.frame.midY)
        CGWarpMouseCursorPosition(center)
        inhibitFollowMouseUntil = Date().addingTimeInterval(0.6)
        logInfo("mouse_follows_focus_warped", [
            "wid": String(wid),
            "x": String(Int(center.x)),
            "y": String(Int(center.y))
        ])
    }

    /// Vrai si le focus_follows_mouse doit être inhibé (post-warp window).
    public func isFollowMouseInhibited() -> Bool {
        guard let until = inhibitFollowMouseUntil else { return false }
        return Date() < until
    }

    /// Vrai si le warp doit être inhibé (focus_follows_mouse vient de set focus).
    public func isWarpInhibited() -> Bool {
        guard let until = inhibitWarpUntil else { return false }
        return Date() < until
    }

    /// Posé par FocusFollowsMouseWatcher avant son setFocus. Empêche le hook
    /// onFocusChanged de re-warper inutilement.
    public func setInhibitWarp(durationSeconds: TimeInterval) {
        inhibitWarpUntil = Date().addingTimeInterval(durationSeconds)
    }

    /// SPEC-028 — anti-loop. Posé par FocusFollowsMouseWatcher avant son setFocus.
    /// Empêche le hook stage_follows_focus de switcher la stage en réponse à un
    /// focus issu d'un simple hover.
    public func setInhibitStageFollowsFocus(durationSeconds: TimeInterval) {
        inhibitStageFollowsFocusUntil = Date().addingTimeInterval(durationSeconds)
    }

    /// Vrai si stage_follows_focus doit être inhibé (focus issu d'un hover souris).
    public func isStageFollowsFocusInhibited() -> Bool {
        guard let until = inhibitStageFollowsFocusUntil else { return false }
        return Date() < until
    }

    /// SPEC-026 US5 — warp uniquement (pas de re-set AX). Utile après un
    /// stage_switch / desktop_switch / Cmd+Tab où le focus AX a changé sans
    /// passer par setFocusFromShortcut.
    /// Skip si le warp est inhibé (focus_follows_mouse vient de set focus :
    /// la souris est déjà sur la fenêtre).
    public func warpCursorToFocusedIfEnabled() {
        guard mouseFollowsFocus else { return }
        if isWarpInhibited() { return }
        guard let wid = registry.focusedWindowID else { return }
        guard let state = registry.get(wid) else { return }
        let center = CGPoint(x: state.frame.midX, y: state.frame.midY)
        CGWarpMouseCursorPosition(center)
        inhibitFollowMouseUntil = Date().addingTimeInterval(0.6)
        logInfo("mouse_follows_focus_warped", [
            "via": "post-switch",
            "wid": String(wid),
            "x": String(Int(center.x)),
            "y": String(Int(center.y))
        ])
    }
}
