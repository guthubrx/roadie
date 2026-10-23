import AppKit
import os
import RoadieCore

/// Commandes d'ouverture/navigation ; seul le composant graphique les exécute.
@MainActor
public final class WindowSwitcherRuntimeBridge {
    nonisolated public static let notificationName = Notification.Name("com.roadie.switcher.command")
    nonisolated private static let focusNotification = Notification.Name("com.roadie.switcher.focus")
    private struct FocusPublication: Sendable {
        var enabled = false
        var lastID: WindowID?
    }
    nonisolated private static let focusPublication = OSAllocatedUnfairLock(initialState: FocusPublication())
    private let controller: WindowSwitcherController
    private var observer: NSObjectProtocol?
    private var focusObserver: NSObjectProtocol?

    public init(controller: WindowSwitcherController) { self.controller = controller }

    public func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.notificationName, object: "roadie", queue: .main
        ) { [weak self] notification in
            let command = TargetModeRuntimeCommand(userInfo: notification.userInfo)
            Task { @MainActor in self?.handle(command) }
        }
        focusObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.focusNotification, object: "roadie", queue: .main
        ) { notification in
            guard let raw = notification.userInfo?["windowID"] as? String,
                  let id = UInt32(raw), id > 0 else { return }
            WindowSwitcherFocusHistory.shared.observe(WindowID(rawValue: id))
        }
    }

    public func stop() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        if let focusObserver { DistributedNotificationCenter.default().removeObserver(focusObserver) }
        focusObserver = nil
    }

    /// Seul le tiler publie : les lecteurs ne renvoient pas les notifications reçues.
    nonisolated public static func setFocusPublishing(_ enabled: Bool) {
        focusPublication.withLock { $0.enabled = enabled; $0.lastID = nil }
    }

    /// Un envoi par changement, sans disque ni timer, y compris en mode modulaire.
    nonisolated static func publishFocus(_ id: WindowID) {
        let changed = focusPublication.withLock { state in
            guard state.enabled, state.lastID != id else { return false }
            state.lastID = id
            return true
        }
        guard changed else { return }
        DistributedNotificationCenter.default().postNotificationName(
            focusNotification, object: "roadie", userInfo: ["windowID": String(id.rawValue)], deliverImmediately: true)
    }

    private func handle(_ command: TargetModeRuntimeCommand?) {
        switch command?.name {
        case "switcher.show": controller.show(profileID: command?.string("profile"))
        case "switcher.next": controller.next()
        case "switcher.previous": controller.next(backwards: true)
        case "switcher.accept": controller.accept()
        case "switcher.cancel": controller.cancel()
        default: break
        }
    }

    /// Validation stricte avant envoi : une faute de saisie ne choisit pas un autre profil. O(a).
    nonisolated static func command(_ arguments: [String]) -> TargetModeRuntimeCommand? {
        let args = arguments.filter { $0 != "--json" }
        guard let verb = args.first, ["show", "next", "previous", "accept", "cancel"].contains(verb) else { return nil }
        var payload: [String: String] = [:]
        if args.count > 1 {
            guard verb == "show", args.count == 3, args[1] == "--profile",
                  !args[2].isEmpty, !args[2].hasPrefix("--") else { return nil }
            payload["profile"] = args[2]
        }
        return TargetModeRuntimeCommand(name: "switcher.\(verb)", arguments: payload)
    }
}
