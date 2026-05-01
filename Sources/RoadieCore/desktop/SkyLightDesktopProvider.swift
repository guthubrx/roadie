import Foundation
import CoreFoundation

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
        // Sans SIP off, pas d'API publique stable pour scripter Mission Control.
        // Best-effort via osascript : envoie Ctrl+<N> (1..9) si l'utilisateur a activé
        // « Switch to Desktop N » dans Réglages Système > Clavier > Raccourcis > Mission Control.
        // Sinon : aucun effet (pas de crash). L'utilisateur reste maître via gestures/clavier natif.
        let desktops = listDesktops()
        guard let target = desktops.first(where: { $0.uuid == uuid }) else { return }
        // Mapping macOS QWERTY US : keycodes des chiffres 1..9 (non séquentiels !).
        // 1=18, 2=19, 3=20, 4=21, 5=23, 6=22, 7=26, 8=28, 9=25.
        let digitKeycodes = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        guard target.index >= 1, target.index <= digitKeycodes.count else { return }
        let keycode = digitKeycodes[target.index - 1]
        let script = """
        tell application "System Events"
            key code \(keycode) using control down
        end tell
        """
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        try? task.run()
    }

    // MARK: - Helpers

    private func uuid(forSpaceID id: CGSSpaceID) -> String? {
        guard let displays = CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]] else {
            return nil
        }
        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            for entry in spaces {
                if let id64 = entry["id64"] as? UInt64, id64 == id,
                   let uuid = entry["uuid"] as? String {
                    return uuid
                }
                if let id32 = entry["id"] as? Int, UInt64(id32) == id,
                   let uuid = entry["uuid"] as? String {
                    return uuid
                }
            }
        }
        return nil
    }
}
