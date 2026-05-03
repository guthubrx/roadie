import Foundation
import ApplicationServices

/// Registre central des fenêtres connues du daemon.
/// Toutes les opérations doivent être appelées sur le MainActor.
@MainActor
public final class WindowRegistry {
    private var windows: [WindowID: WindowState] = [:]
    private var axElements: [WindowID: AXUIElement] = [:]
    public private(set) var focusedWindowID: WindowID?

    /// MRU stack des fenêtres précédemment focalisées (pour insertion intelligente).
    /// Quand une nouvelle fenêtre est créée et prend le focus avant qu'on ne soit notifié,
    /// la prev-focused permet de placer la nouvelle "à côté" de celle qui avait le focus juste avant.
    public private(set) var previousFocusedWindowID: WindowID?

    /// Callback invoqué quand `focusedWindowID` change effectivement (vrai diff).
    /// Le daemon l'utilise pour publier `windowFocused` sur le bus FX (modules opt-in).
    public var onFocusChanged: ((WindowID?) -> Void)?

    public init() {}

    public func register(_ state: WindowState, axElement: AXUIElement) {
        windows[state.cgWindowID] = state
        axElements[state.cgWindowID] = axElement
        logDebug("registered window", [
            "wid": String(state.cgWindowID),
            "bundle": state.bundleID,
            "subrole": state.subrole.rawValue,
        ])
    }

    public func unregister(_ wid: WindowID) {
        windows.removeValue(forKey: wid)
        axElements.removeValue(forKey: wid)
        if focusedWindowID == wid { focusedWindowID = nil }
        logDebug("unregistered window", ["wid": String(wid)])
    }

    public func update(_ wid: WindowID, _ mutate: (inout WindowState) -> Void) {
        guard var state = windows[wid] else { return }
        mutate(&state)
        windows[wid] = state
    }

    public func updateFrame(_ wid: WindowID, frame: CGRect) {
        // SPEC-022 — rejeter toute frame avec size degenerate (height < 100 ou
        // width < 100). HideStrategy déplace à des positions extrêmes mais GARDE
        // la size normale → un setBounds via HideStrategy a toujours size OK.
        // Une frame degenerate vient TOUJOURS d'un AX bug (drawer transient,
        // popup, init en cours). Mieux vaut garder l'ancienne valeur sane.
        let minDim = WindowState.minimumUsefulDimension
        if frame.size.width < minDim || frame.size.height < minDim {
            logWarn("updateFrame: rejected degenerate frame", [
                "wid": String(wid),
                "frame": "\(Int(frame.origin.x)),\(Int(frame.origin.y)) \(Int(frame.size.width))x\(Int(frame.size.height))",
            ])
            return
        }
        update(wid) { $0.frame = frame }
    }

    public func setFocus(_ wid: WindowID?) {
        // Push l'ancien focus en MRU si différent. Si l'ancien était nil
        // (premier focus connu), on ne crée pas de prev artificielle —
        // l'init du focus au boot du daemon assure qu'on a un focus réel
        // dès le départ via refreshFromSystem().
        let changed = focusedWindowID != wid
        if changed, let old = focusedWindowID {
            previousFocusedWindowID = old
        }
        focusedWindowID = wid
        if let wid = wid {
            logInfo("focus changed", ["wid": String(wid),
                                      "prev": previousFocusedWindowID.map(String.init) ?? "nil"])
        }
        if changed { onFocusChanged?(wid) }
    }

    /// Retourne le meilleur candidat "near" pour insertion :
    /// - Cas normal : le focus courant est sur la fenêtre que l'utilisateur regarde,
    ///   c'est elle qu'on doit splitter.
    /// - Cas focus race : si la nouvelle fenêtre a déjà capté le focus (focused == newWID),
    ///   on prend le focus précédent (la fenêtre que l'utilisateur regardait juste avant).
    public func insertionTarget(for newWID: WindowID) -> WindowID? {
        if let current = focusedWindowID, current != newWID, windows[current]?.isTileable == true {
            return current
        }
        if let prev = previousFocusedWindowID, prev != newWID, windows[prev]?.isTileable == true {
            return prev
        }
        return nil
    }

    public func get(_ wid: WindowID) -> WindowState? { windows[wid] }
    public func axElement(for wid: WindowID) -> AXUIElement? { axElements[wid] }
    public var allWindows: [WindowState] { Array(windows.values) }
    public var tileableWindows: [WindowState] { windows.values.filter { $0.isTileable } }
    public func windows(in stage: StageID) -> [WindowState] {
        windows.values.filter { $0.stageID == stage }
    }

    /// SPEC-011 : retourne les fenêtres assignées à un desktop virtuel donné.
    public func windows(of desktopID: Int) -> [WindowState] {
        windows.values.filter { $0.desktopID == desktopID }
    }

    /// SPEC-011 : met à jour la expectedFrame d'une fenêtre — appelé uniquement
    /// quand la fenêtre est on-screen (desktopID == currentDesktopID, cf. R-002).
    public func updateExpectedFrame(_ wid: WindowID, frame: CGRect) {
        update(wid) { $0.expectedFrame = frame }
    }

    /// SPEC-011 : assigne une fenêtre à un desktop virtuel.
    public func assignDesktop(_ wid: WindowID, desktopID: Int) {
        update(wid) { $0.desktopID = desktopID }
    }

    /// Legacy SPEC-003 — conservé pour compatibilité transitoire.
    public func applyDesktopUUID(_ uuid: String) {
        for wid in windows.keys {
            update(wid) { $0.desktopUUID = uuid }
        }
    }
}
