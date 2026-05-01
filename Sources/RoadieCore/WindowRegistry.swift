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
        update(wid) { $0.frame = frame }
    }

    public func setFocus(_ wid: WindowID?) {
        // Push l'ancien focus en MRU si différent. Si l'ancien était nil
        // (premier focus connu), on ne crée pas de prev artificielle —
        // l'init du focus au boot du daemon assure qu'on a un focus réel
        // dès le départ via refreshFromSystem().
        if focusedWindowID != wid, let old = focusedWindowID {
            previousFocusedWindowID = old
        }
        focusedWindowID = wid
        if let wid = wid {
            logInfo("focus changed", ["wid": String(wid),
                                      "prev": previousFocusedWindowID.map(String.init) ?? "nil"])
        }
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
}
