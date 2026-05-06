import AppKit
import RoadieCore

/// SPEC-028 — Détection drop hors-rail sans overlay panel.
///
/// Pourquoi pas un overlay panel ? Sur Tahoe, un NSPanel `level=.floating`
/// au-dessus des apps absorbe les events scroll-wheel, même avec
/// `hitTest → nil` côté NSView. La molette est cassée → inacceptable.
///
/// Approche alternative : NSEvent monitor global sur `leftMouseUp`. Au
/// début d'un drag de vignette (`.draggable` preview onAppear), on enregistre
/// la wid + le panel rail courant (déduit de la position curseur vs les
/// frames panels enregistrés). Au mouseUp, on lit la position curseur :
/// - dans la frame d'un panel rail → laisse `dropDestination` SwiftUI gérer
///   (assignWindow sur cellule). On ne fait rien.
/// - hors de toute frame panel rail → déclenche `summonWindow(wid, displayUUID)`
///   qui re-assigne la fenêtre à la stage active du display d'origine.
///
/// Pas d'overlay = pas de problème de scroll/click passthrough.
@MainActor
public final class DragSummonTracker {
    public static let shared = DragSummonTracker()

    /// Frame en coordonnées screen + UUID display, par panel rail.
    /// RailController appelle `registerPanel(...)` à chaque buildPanels.
    private var panels: [(frame: NSRect, displayUUID: String)] = []

    /// Callback déclenché au drop hors-rail. Param : (wid, displayUUID du panel
    /// d'origine du drag). Set par RailController au boot.
    public var onSummon: ((CGWindowID, String) -> Void)?

    /// Drag en cours. nil quand pas de drag actif.
    private var activeDrag: (wid: CGWindowID, displayUUID: String)?
    private var mouseUpMonitor: Any?

    private init() {}

    /// À appeler par RailController dans buildPanels pour chaque panel rail.
    /// Reset via `clearPanels()` avant.
    public func registerPanel(frame: NSRect, displayUUID: String) {
        panels.append((frame: frame, displayUUID: displayUUID))
    }

    public func clearPanels() {
        panels.removeAll()
    }

    /// À appeler depuis `.draggable(payload, preview: { Color.clear.onAppear { ... } })`
    /// quand le drag d'une vignette démarre. Le `displayUUID` est déduit de la
    /// position courante du curseur (= le panel rail sous le curseur).
    public func startDrag(wid: CGWindowID) {
        let mouseLoc = NSEvent.mouseLocation
        let panel = panels.first { $0.frame.contains(mouseLoc) }
        let displayUUID = panel?.displayUUID ?? ""
        activeDrag = (wid: wid, displayUUID: displayUUID)
        logInfo("rail_summon_drag_started", [
            "wid": String(wid),
            "src_display": displayUUID,
            "loc_x": String(format: "%.1f", mouseLoc.x),
            "loc_y": String(format: "%.1f", mouseLoc.y),
        ])
        installMonitorIfNeeded()
    }

    /// Installe le monitor global mouseUp. NSEvent.addGlobalMonitor reçoit les
    /// events des autres apps ; pour les events DANS notre process (= drop sur
    /// notre rail), on a aussi besoin du local monitor.
    private func installMonitorIfNeeded() {
        guard mouseUpMonitor == nil else { return }
        // Local monitor : capture des events qui auraient atteint notre app.
        // Global monitor : pour les drops dans une autre app (la majorité du
        // temps quand on lâche sur le bureau / par-dessus une fenêtre tierce).
        // On combine les deux via un même handler.
        let handler: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor in self?.handleMouseUp() }
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { event in
            handler(event)
        }
        mouseUpMonitor = global
    }

    private func handleMouseUp() {
        guard let drag = activeDrag else { return }
        defer { cleanup() }
        let mouseLoc = NSEvent.mouseLocation
        let inRail = panels.contains { $0.frame.contains(mouseLoc) }
        if inRail {
            logInfo("rail_summon_skipped_in_rail", [
                "wid": String(drag.wid),
                "loc_x": String(format: "%.1f", mouseLoc.x),
                "loc_y": String(format: "%.1f", mouseLoc.y),
            ])
            return
        }
        logInfo("rail_summon_invoke", [
            "wid": String(drag.wid),
            "display_uuid": drag.displayUUID,
            "drop_x": String(format: "%.1f", mouseLoc.x),
            "drop_y": String(format: "%.1f", mouseLoc.y),
        ])
        onSummon?(drag.wid, drag.displayUUID)
    }

    private func cleanup() {
        activeDrag = nil
        if let m = mouseUpMonitor {
            NSEvent.removeMonitor(m)
            mouseUpMonitor = nil
        }
    }
}
