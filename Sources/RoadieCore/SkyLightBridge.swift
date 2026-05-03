import Foundation
import CoreGraphics

/// SPEC-021 — Bridge vers SLSCopySpacesForWindows (lecture seule, sans SIP off).
/// Pattern yabai éprouvé en prod 5+ ans. Permet de récupérer le space_id macOS
/// courant d'une fenêtre tierce : source de vérité OS, pas un cache local.
///
/// CGSCopyManagedDisplaySpaces : retourne un CFArray<CFDict> avec clés :
///   "Display Identifier" (String) — UUID de l'écran
///   "Spaces"             (CFArray<CFDict>) — chaque dict a "ManagedSpaceID" (Int)
/// Utilisé pour construire le mapping spaceID → (displayUUID, desktopID).

@_silgen_name("SLSCopySpacesForWindows")
private func SLSCopySpacesForWindows(_ cid: Int, _ mask: UInt32, _ wids: CFArray) -> CFArray?

@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> Int

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: Int) -> CFArray?

public enum SkyLightBridge {

    /// Retourne le space_id du desktop visible courant pour une wid donnée.
    /// nil si la wid n'a pas de space attribué (helper, off-screen, fullscreen non-managed).
    /// Latence typique ≤ 1 ms.
    @MainActor
    public static func currentSpaceID(for wid: CGWindowID) -> UInt64? {
        let cid = _CGSDefaultConnection()
        let widsArray = [wid] as CFArray
        guard let spaces = SLSCopySpacesForWindows(cid, 0x7, widsArray) as? [UInt64],
              let first = spaces.first else { return nil }
        return first
    }

    /// Retourne le mapping [{displayUUID, [spaceID]}] depuis SkyLight.
    /// Utilisé par DesktopRegistry pour rebuild son cache spaceID → scope.
    /// nil si l'appel SkyLight échoue (ex : headless CI).
    @MainActor
    public static func managedDisplaySpaces() -> [(displayUUID: String, spaceIDs: [UInt64])]? {
        let cid = _CGSDefaultConnection()
        guard let raw = CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]] else { return nil }
        var result: [(displayUUID: String, spaceIDs: [UInt64])] = []
        for displayDict in raw {
            guard let uuid = displayDict["Display Identifier"] as? String,
                  let spacesRaw = displayDict["Spaces"] as? [[String: Any]] else { continue }
            let spaceIDs = spacesRaw.compactMap { dict -> UInt64? in
                guard let sid = dict["ManagedSpaceID"] as? Int else { return nil }
                return UInt64(sid)
            }
            result.append((displayUUID: uuid, spaceIDs: spaceIDs))
        }
        return result
    }
}
