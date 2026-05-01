import Foundation
import CoreGraphics

/// Commandes envoyées au scripting addition `roadied.osax` pour appel CGS privés
/// sur fenêtres tierces. Sérialisées en JSON-lines via OSAXBridge.
public enum OSAXCommand: Sendable, Equatable {
    case noop
    case setAlpha(wid: CGWindowID, alpha: Double)
    case setShadow(wid: CGWindowID, density: Double)
    case setBlur(wid: CGWindowID, radius: Int)
    case setTransform(wid: CGWindowID, scale: Double, tx: Double, ty: Double)
    case setLevel(wid: CGWindowID, level: Int)
    /// SPEC-007 : déplace l'origine de la fenêtre via SLSMoveWindow côté osax.
    /// Resize via SkyLight trop fragile → daemon utilise AX pour le size.
    /// `w` et `h` sont conservés dans le payload pour usages futurs.
    case setFrame(wid: CGWindowID, x: Double, y: Double, w: Double, h: Double)
    case moveWindowToSpace(wid: CGWindowID, spaceUUID: String)
    case setSticky(wid: CGWindowID, sticky: Bool)

    /// Sérialise en JSON-line (terminée par `\n`).
    public func toJSONLine() -> String {
        let json = toJSONObject()
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: []),
              let str = String(data: data, encoding: .utf8) else {
            return "{\"cmd\":\"noop\"}\n"
        }
        return str + "\n"
    }

    private func toJSONObject() -> [String: Any] {
        switch self {
        case .noop:
            return ["cmd": "noop"]
        case .setAlpha(let wid, let alpha):
            return ["cmd": "set_alpha", "wid": Int(wid), "alpha": alpha]
        case .setShadow(let wid, let density):
            return ["cmd": "set_shadow", "wid": Int(wid), "density": density]
        case .setBlur(let wid, let radius):
            return ["cmd": "set_blur", "wid": Int(wid), "radius": radius]
        case .setTransform(let wid, let scale, let tx, let ty):
            return ["cmd": "set_transform", "wid": Int(wid),
                    "scale": scale, "tx": tx, "ty": ty]
        case .setLevel(let wid, let level):
            return ["cmd": "set_level", "wid": Int(wid), "level": level]
        case .setFrame(let wid, let x, let y, let w, let h):
            return ["cmd": "set_frame", "wid": Int(wid),
                    "x": x, "y": y, "w": w, "h": h]
        case .moveWindowToSpace(let wid, let spaceUUID):
            return ["cmd": "move_window_to_space", "wid": Int(wid), "space_uuid": spaceUUID]
        case .setSticky(let wid, let sticky):
            return ["cmd": "set_sticky", "wid": Int(wid), "sticky": sticky]
        }
    }
}

/// Réponse de l'osax côté daemon.
public enum OSAXResult: Sendable, Equatable {
    case ok
    case error(code: String, message: String?)

    public init?(jsonLine: String) {
        guard let data = jsonLine.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let status = dict["status"] as? String else {
            return nil
        }
        if status == "ok" {
            self = .ok
        } else {
            let code = dict["code"] as? String ?? "unknown"
            let msg = dict["message"] as? String
            self = .error(code: code, message: msg)
        }
    }

    public var isOK: Bool {
        if case .ok = self { return true } else { return false }
    }
}
