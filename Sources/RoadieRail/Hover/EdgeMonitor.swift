import AppKit

// SPEC-014 T025 — Détecte l'entrée/sortie de la souris sur l'edge gauche des écrans.
// Polling à 80ms (FR-012). Debounce 100ms à la sortie (FR-013).

/// Surveille la position de la souris et notifie quand elle entre ou sort
/// de l'edge gauche d'un écran (zone de 8px de large × hauteur écran).
final class EdgeMonitor {
    var onEnterEdge: ((NSScreen) -> Void)?
    var onExitEdge: ((NSScreen) -> Void)?

    /// Largeur de la zone d'activation en pixels (déclenche le show).
    var edgeWidth: CGFloat = 8
    /// Largeur de la zone "active étendue" : tant que la souris est dans cette zone,
    /// le panel reste visible. Permet à l'utilisateur d'aller cliquer les vignettes
    /// sans que le panel disparaisse. Doit matcher la largeur réelle du panel.
    var activeZoneWidth: CGFloat = 320

    private var timer: Timer?
    // Écrans actuellement en état "actif" (souris dans l'edge ou le panel visible).
    private var activeScreenIDs: Set<CGDirectDisplayID> = []
    // Debounce exit : date de première sortie détectée par écran.
    private var exitTimes: [CGDirectDisplayID: Date] = [:]

    private static let pollInterval: TimeInterval = 0.08
    /// Délai avant de déclencher le hide après que la souris a quitté la zone active.
    /// 0.7 s donne le temps d'aller cliquer une vignette ou faire un drag-drop.
    private static let exitDebounce: TimeInterval = 0.7

    func start() {
        timer = Timer.scheduledTimer(
            withTimeInterval: Self.pollInterval,
            repeats: true
        ) { [weak self] _ in
            self?.tick()
        }
        // Le timer doit tourner même quand SwiftUI consomme des événements.
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        activeScreenIDs.removeAll()
        exitTimes.removeAll()
    }

    // MARK: - Private

    private func tick() {
        // NSEvent.mouseLocation : coordonnées NS (origine en bas-gauche).
        let mouse = NSEvent.mouseLocation

        for screen in NSScreen.screens {
            let displayID = displayID(for: screen)
            let inEdge = isInEdge(mouse: mouse, screen: screen)

            if inEdge {
                exitTimes.removeValue(forKey: displayID)
                if !activeScreenIDs.contains(displayID) {
                    activeScreenIDs.insert(displayID)
                    onEnterEdge?(screen)
                }
            } else {
                if activeScreenIDs.contains(displayID) {
                    // Debounce : on attend 100ms avant de déclencher la sortie.
                    if let first = exitTimes[displayID] {
                        if Date().timeIntervalSince(first) >= Self.exitDebounce {
                            exitTimes.removeValue(forKey: displayID)
                            activeScreenIDs.remove(displayID)
                            onExitEdge?(screen)
                        }
                    } else {
                        exitTimes[displayID] = Date()
                    }
                }
            }
        }
    }

    private func isInEdge(mouse: CGPoint, screen: NSScreen) -> Bool {
        let f = screen.frame
        // Zone active : `edgeWidth` au repos (déclenche show), `activeZoneWidth` une
        // fois le panel visible (= largeur réelle du panel) pour permettre à la
        // souris d'aller sur les vignettes sans déclencher le hide.
        let displayID = self.displayID(for: screen)
        let width: CGFloat = activeScreenIDs.contains(displayID)
            ? max(activeZoneWidth, edgeWidth)
            : edgeWidth
        let zone = CGRect(x: f.minX, y: f.minY, width: width, height: f.height)
        return zone.contains(mouse)
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        // deviceDescription["NSScreenNumber"] contient le CGDirectDisplayID.
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) ?? 0
    }
}
