import ApplicationServices
import CoreGraphics

/// API privée stable depuis macOS 10.7.
/// Utilisée par yabai (10+ ans), AeroSpace (2 ans), Hammerspoon, Rectangle, Amethyst.
/// Réutilise l'expérience SPEC-001 (stage.swift).
@_silgen_name("_AXUIElementGetWindow")
public func _AXUIElementGetWindow(_ element: AXUIElement,
                                  _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Wrapper safe : retourne le CGWindowID d'un AXUIElement, ou nil si erreur.
public func axWindowID(of element: AXUIElement) -> WindowID? {
    var wid: CGWindowID = 0
    let err = _AXUIElementGetWindow(element, &wid)
    return (err == .success && wid != 0) ? wid : nil
}
