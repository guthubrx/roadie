import Foundation
import CoreFoundation
import CoreGraphics
#if canImport(AppKit)
import AppKit
#endif

/// Implémentation prod de `DesktopProvider` qui lit l'API privée SkyLight.
/// Lecture seule : ne nécessite pas SIP désactivé. Pattern yabai/AeroSpace.
@MainActor
public final class SkyLightDesktopProvider: DesktopProvider {

    private let cid: CGSConnectionID

    public init() {
        self.cid = CGSMainConnectionID()
    }

    public func currentDesktopUUID() -> String? {
        let activeID = CGSGetActiveSpace(cid)
        return uuid(forSpaceID: activeID)
    }

    public func listDesktops() -> [DesktopInfo] {
        guard let displays = CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]] else {
            return []
        }
        var result: [DesktopInfo] = []
        var globalIndex = 1
        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            for entry in spaces {
                guard let uuid = entry["uuid"] as? String else { continue }
                // type==0 = user space (Mission Control). Filtre fullscreen apps (type=4).
                let type = (entry["type"] as? Int) ?? 0
                guard type == 0 else { continue }
                result.append(DesktopInfo(uuid: uuid, index: globalIndex, label: nil))
                globalIndex += 1
            }
        }
        return result
    }

    public func requestFocus(uuid: String) {
        // Stratégie : envoyer Ctrl+<N> via NSAppleScript (= "Switch to Desktop N").
        // Indépendant du desktop courant (pas de delta-calcul fragile quand
        // CGSGetActiveSpace retourne un space hors de la liste filtrée type=0,
        // ex: fullscreen apps ou stage manager macOS).
        //
        // Pré-requis macOS : hotkeys « Switch to Desktop N » activés dans
        // Réglages > Clavier > Raccourcis > Mission Control. Pour activer
        // par script (sans reboot, mais nécessite logout pour effet runtime) :
        //   /usr/libexec/PlistBuddy ~/Library/Preferences/com.apple.symbolichotkeys.plist
        let desktops = listDesktops()
        guard let target = desktops.first(where: { $0.uuid == uuid }) else { return }
        // Mapping AZERTY/QWERTY physique : keycodes des chiffres 1..0 (non séquentiels).
        let digitKeycodes = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
        guard target.index >= 1, target.index <= digitKeycodes.count else { return }
        let keycode = digitKeycodes[target.index - 1]
        logInfo("requestFocus", ["to_index": String(target.index), "keycode": String(keycode)])

        let scriptText = "tell application \"System Events\" to key code \(keycode) using control down"
        #if canImport(AppKit)
        if let script = NSAppleScript(source: scriptText) {
            var err: NSDictionary?
            _ = script.executeAndReturnError(&err)
            if let err = err {
                logWarn("NSAppleScript error", ["err": "\(err)"])
            }
        }
        #endif
    }

    // MARK: - Helpers

    private func uuid(forSpaceID id: CGSSpaceID) -> String? {
        guard let displays = CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]] else {
            return nil
        }
        var triedKeys: [String] = []
        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            for entry in spaces {
                if triedKeys.isEmpty { triedKeys = Array(entry.keys) }
                // Tente plusieurs clés selon les versions macOS :
                // - "ManagedSpaceID" (Sonoma 14+), "id64", "id"
                for key in ["ManagedSpaceID", "id64", "id"] {
                    guard let v = entry[key] else { continue }
                    let entryID: CGSSpaceID?
                    if let u = v as? UInt64 { entryID = u }
                    else if let i = v as? Int { entryID = CGSSpaceID(i) }
                    else if let i = v as? Int64 { entryID = CGSSpaceID(i) }
                    else { entryID = nil }
                    if entryID == id, let uuid = entry["uuid"] as? String {
                        return uuid
                    }
                }
            }
        }
        if !triedKeys.isEmpty {
            logWarn("CGS spaces lookup failed",
                    ["space_id": String(id),
                     "available_keys": triedKeys.joined(separator: ",")])
        }
        return nil
    }
}
