import AppKit
import RoadieCore

/// Qualification hors fil principal, bornée et stricte sur l'identité. Aucun clic rejoué.
public enum WindowTitleDragAccess {
    public static let titleBarHeight: CGFloat = 44

    static func isInTitleBand(_ point: CGPoint, frame: CGRect) -> Bool {
        point.x >= frame.minX + 80 && point.x <= frame.maxX - 8
            && point.y >= frame.minY + 8 && point.y <= frame.minY + min(titleBarHeight, frame.height)
    }

    public static func accepts(window: WindowSnapshot, at point: CGPoint) -> Bool {
        let frame = window.frame.cgRect
        guard isInTitleBand(point, frame: frame),
              !AXUnresponsiveApps.shared.isQuarantined(window.pid) else { return false }
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return false }
        func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
            AXUIElementSetMessagingTimeout(element, 0.05)
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, key as CFString, &raw) == .success else { return nil }
            return raw
        }
        let role = value(hit, kAXRoleAttribute) as? String
        let owner: AXUIElement
        if role == kAXWindowRole { owner = hit }
        else {
            // Un bouton, onglet ou champ ne devient jamais un titre par sa seule géométrie.
            guard role == kAXStaticTextRole || role == kAXGroupRole,
                  let raw = value(hit, kAXWindowAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return false }
            owner = unsafeBitCast(raw, to: AXUIElement.self)
            if role == kAXStaticTextRole {
                guard let titleElement = value(owner, kAXTitleUIElementAttribute),
                      CFGetTypeID(titleElement) == AXUIElementGetTypeID(), CFEqual(titleElement, hit) else { return false }
            } else {
                var actions: CFArray?
                guard AXUIElementCopyActionNames(hit, &actions) == .success,
                      let actions = actions as? [String],
                      let hitFrame = AXWindowFrameWriter().frame(of: hit, pid: window.pid),
                      acceptsWindowContainer(role: role ?? "", actions: actions, frame: hitFrame, windowFrame: frame)
                else { return false }
                if abs(hitFrame.height - frame.height) > 1 || abs(hitFrame.width - frame.width) > 1 {
                    // Chrome expose ses zones de titre vides comme des groupes horizontaux.
                    // Un groupe de barre ne doit contenir aucun contrôle ni onglet.
                    var children: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(hit, kAXChildrenAttribute as CFString, &children) == .success,
                          let children = children as? [AXUIElement], children.isEmpty else { return false }
                }
            }
        }
        var id: CGWindowID = 0
        var pid: pid_t = 0
        guard AXUIElementGetPid(owner, &pid) == .success, pid == window.pid,
              AXUIElementGetWindowID(owner, &id) == .success, id == window.id.rawValue else { return false }
        return true
    }

    /// Electron peut exposer sa surface vide de titre comme le groupe racine de la fenêtre.
    /// Un petit groupe, un groupe avec action ou tout autre contrôle reste exclu.
    static func acceptsWindowContainer(role: String, actions: [String], frame: CGRect, windowFrame: CGRect) -> Bool {
        guard role == kAXGroupRole, actions.isEmpty else { return false }
        let pairs = [(frame.minX, windowFrame.minX), (frame.minY, windowFrame.minY),
                     (frame.width, windowFrame.width), (frame.height, windowFrame.height)]
        guard pairs.allSatisfy({ $0.0.isFinite && $0.1.isFinite }) else { return false }
        if pairs.allSatisfy({ abs($0.0 - $0.1) <= 1 }) { return true }
        return frame.width >= 160 && frame.height >= 8 && frame.height <= titleBarHeight
            && abs(frame.minY - windowFrame.minY) <= 1
            && frame.minX >= windowFrame.minX && frame.maxX <= windowFrame.maxX + 1
    }
}
