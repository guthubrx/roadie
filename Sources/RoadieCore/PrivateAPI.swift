import ApplicationServices
import CoreGraphics
import CoreFoundation

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

// MARK: - SkyLight Spaces (SPEC-003)
// Lecture seule, sans SIP désactivé. Pattern yabai depuis 10 ans.
// Réf : research.md décision 1 et 2.

public typealias CGSConnectionID = Int32
public typealias CGSSpaceID = UInt64

@_silgen_name("CGSMainConnectionID")
public func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetActiveSpace")
public func CGSGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID

@_silgen_name("CGSCopyManagedDisplaySpaces")
public func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray?
