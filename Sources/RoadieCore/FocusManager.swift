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

    /// SPEC-026 US5 — flag anti-feedback loop. Quand mouse_follows_focus warp
    /// le curseur, ce timestamp est posé à now+0.2s ; le FocusFollowsMouseWatcher
    /// vérifie ce flag avant de déclencher un setFocus pour éviter une cascade.
    public private(set) var inhibitFollowMouseUntil: Date?

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
        inhibitFollowMouseUntil = Date().addingTimeInterval(0.2)
        logInfo("mouse_follows_focus_warped", [
            "wid": String(wid),
            "x": String(Int(center.x)),
            "y": String(Int(center.y)),
        ])
    }

    /// Vrai si le focus_follows_mouse doit être inhibé (post-warp window).
    public func isFollowMouseInhibited() -> Bool {
        guard let until = inhibitFollowMouseUntil else { return false }
        return Date() < until
    }

    /// SPEC-026 US5 — pose un inhibit transitoire. Utilisé par
    /// FocusFollowsMouseWatcher pour signaler "ce setFocus vient de moi, ne
    /// re-warpe pas via le hook onFocusChanged". Évite warp redondant sur hover.
    public func setInhibitFollowMouse(durationSeconds: TimeInterval) {
        inhibitFollowMouseUntil = Date().addingTimeInterval(durationSeconds)
    }

    /// SPEC-026 US5 — warp uniquement (pas de re-set AX). Utile après un
    /// stage_switch ou desktop_switch où la wid focalisée a changé sans
    /// passer par setFocusFromShortcut (le show des fenêtres a déclenché
    /// macOS qui a focalisé une wid de la nouvelle stage).
    public func warpCursorToFocusedIfEnabled() {
        guard mouseFollowsFocus else { return }
        guard let wid = registry.focusedWindowID else { return }
        guard let state = registry.get(wid) else { return }
        let center = CGPoint(x: state.frame.midX, y: state.frame.midY)
        CGWarpMouseCursorPosition(center)
        inhibitFollowMouseUntil = Date().addingTimeInterval(0.2)
        logInfo("mouse_follows_focus_warped", [
            "via": "post-switch",
            "wid": String(wid),
            "x": String(Int(center.x)),
            "y": String(Int(center.y)),
        ])
    }
}
