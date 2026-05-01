import Foundation
import Cocoa

/// Filet de sécurité périodique pour rattraper les fenêtres dont la création
/// n'a pas été notifiée par les AXObservers.
///
/// **Pourquoi ce module existe** : certaines apps (notamment celles basées sur
/// Electron — Cursor, VSCode, Discord, Slack) ne déclenchent **aucun** event AX
/// après la création de leur fenêtre principale. Ni `kAXWindowCreatedNotification`,
/// ni `kAXMainWindowChangedNotification`, ni `kAXFocusedWindowChangedNotification`.
/// L'AXObserver attaché à l'app reste silencieux.
///
/// On reposera donc sur un re-scan toutes les `interval` secondes de toutes les
/// apps connues, pour comparer les fenêtres système à notre registry et combler
/// les manques. Coût : 1 appel `AXReader.windows()` par app/sec, négligeable.
@MainActor
public final class PeriodicScanner {
    private let interval: TimeInterval
    private var timer: Timer?
    private let scanAction: @MainActor () -> Void

    public init(interval: TimeInterval = 1.0, scanAction: @escaping @MainActor () -> Void) {
        self.interval = interval
        self.scanAction = scanAction
    }

    public func start() {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in self.scanAction() }
        }
        logInfo("PeriodicScanner started", ["interval_s": String(interval)])
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }
}
