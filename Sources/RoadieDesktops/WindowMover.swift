import Foundation
import Cocoa
import ApplicationServices
import CoreGraphics
import RoadieCore

// MARK: - Protocole

/// Protocole de déplacement de fenêtre. Abstraite pour permettre le mock en tests (T016).
public protocol WindowMover: Sendable {
    func move(_ cgwid: CGWindowID, to point: CGPoint) async
}

// MARK: - AXWindowMover

/// Implémentation production via AX (kAXPositionAttribute).
/// Utilise `_AXUIElementGetWindow` (déjà dans RoadieCore/PrivateAPI.swift) pour mapper
/// CGWindowID → AXUIElement, puis `AXUIElementSetAttributeValue` pour repositionner.
/// Cache simple [CGWindowID: AXUIElement] pour éviter la résolution répétée (R-001).
public actor AXWindowMover: WindowMover {
    /// Cache CGWindowID → AXUIElement. Entrée expirée si le WID n'est plus valide.
    private var cache: [CGWindowID: AXUIElement] = [:]

    public init() {}

    public func move(_ cgwid: CGWindowID, to point: CGPoint) async {
        let element = resolveElement(cgwid)
        guard let element = element else { return }
        setPosition(element, point: point)
    }

    // MARK: - Résolution AXUIElement

    private func resolveElement(_ cgwid: CGWindowID) -> AXUIElement? {
        if let cached = cache[cgwid] {
            return cached
        }
        // Parcourir les apps courantes pour trouver l'AXUIElement correspondant
        for app in runningAccessibleApps() {
            let appElement = AXUIElementCreateApplication(app)
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &raw) == .success,
                  let windows = raw as? [AXUIElement] else { continue }
            for win in windows {
                var wid: CGWindowID = 0
                if _AXUIElementGetWindow(win, &wid) == .success, wid == cgwid {
                    cache[cgwid] = win
                    return win
                }
            }
        }
        return nil
    }

    /// Retire une entrée du cache AXUIElement pour le wid donné.
    /// Contrat : à appeler dès qu'un événement window-destroyed est reçu pour ce wid.
    /// Sans invalidation, le cache conserve une référence vers un AXUIElement mort
    /// qui sera silencieusement ignoré par AX mais représente un leak mémoire.
    /// Pas de TTL automatique — c'est à l'appelant d'invalider au bon moment.
    public func invalidate(_ cgwid: CGWindowID) {
        cache.removeValue(forKey: cgwid)
    }

    // MARK: - Position AX

    private func setPosition(_ element: AXUIElement, point: CGPoint) {
        var pos = point
        if let value = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
        }
    }
}

// MARK: - Helpers

private func runningAccessibleApps() -> [pid_t] {
    NSWorkspace.shared.runningApplications
        .filter { $0.activationPolicy == .regular || $0.activationPolicy == .accessory }
        .map { $0.processIdentifier }
}

// MARK: - MockWindowMover (tests)

/// Implémentation de test qui enregistre les mouvements sans appels système.
/// Utilisé par DesktopSwitcherTests, PerfTests, GhostTests (T016, T023, T027, T028).
public actor MockWindowMover: WindowMover {
    public struct MoveRecord: Sendable, Equatable {
        public let cgwid: CGWindowID
        public let point: CGPoint
    }

    public private(set) var moves: [MoveRecord] = []

    public init() {}

    public func move(_ cgwid: CGWindowID, to point: CGPoint) async {
        moves.append(MoveRecord(cgwid: cgwid, point: point))
    }

    public func reset() {
        moves = []
    }

    /// Retourne la dernière position enregistrée pour un wid, ou nil.
    public func lastPosition(for cgwid: CGWindowID) -> CGPoint? {
        moves.last(where: { $0.cgwid == cgwid })?.point
    }

    /// Retourne vrai si le wid a une position hors-écran (x ou y très négatif).
    public func isOffscreen(_ cgwid: CGWindowID, threshold: CGFloat = -10000) -> Bool {
        guard let pos = lastPosition(for: cgwid) else { return false }
        return pos.x < threshold || pos.y < threshold
    }

    /// Retourne vrai si le wid est à la position attendue.
    public func isAt(_ cgwid: CGWindowID, point: CGPoint) -> Bool {
        lastPosition(for: cgwid) == point
    }
}
