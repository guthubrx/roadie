import Foundation
import Cocoa

/// Observe les events globaux NSWorkspace et notifie le delegate.
/// Permet de capter les apps qui se lancent / se terminent et les changements de frontmost.
@MainActor
public protocol GlobalObserverDelegate: AnyObject {
    func didLaunchApp(_ app: NSRunningApplication)
    func didTerminateApp(pid: pid_t)
    func didActivateApp(_ app: NSRunningApplication)
}

@MainActor
public final class GlobalObserver {
    private weak var delegate: GlobalObserverDelegate?
    private var notificationTokens: [NSObjectProtocol] = []

    public init(delegate: GlobalObserverDelegate) {
        self.delegate = delegate
    }

    public func start() {
        let center = NSWorkspace.shared.notificationCenter
        notificationTokens.append(
            center.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil, queue: .main
            ) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                Task { @MainActor in self?.delegate?.didLaunchApp(app) }
            }
        )
        notificationTokens.append(
            center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil, queue: .main
            ) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let pid = app.processIdentifier
                Task { @MainActor in self?.delegate?.didTerminateApp(pid: pid) }
            }
        )
        notificationTokens.append(
            center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil, queue: .main
            ) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                Task { @MainActor in self?.delegate?.didActivateApp(app) }
            }
        )
        logInfo("GlobalObserver started")
    }

    public func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for token in notificationTokens { center.removeObserver(token) }
        notificationTokens.removeAll()
        logInfo("GlobalObserver stopped")
    }

    /// Liste les apps déjà en cours d'exécution au démarrage du daemon.
    public func currentApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    }
}
