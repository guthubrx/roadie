import AppKit
import Foundation

/// Commandes système de la barre (session 105), comme la section Système d'Alfred : verrouiller,
/// suspendre les écrans, tout quitter… Les commandes lourdes demandent un second Retour.
struct LauncherSystemCommand: Equatable, Hashable, Sendable {
    let id: String
    let title: String
    /// Autres mots qui la trouvent, en français et en anglais.
    let keywords: [String]
    let symbol: String
    /// Second Retour exigé.
    let confirms: Bool
    /// Détail de la ligne ; nil : « Système » (session 115 : « Réglages Système », « Paramètres de Roadie »).
    var detail: String? = nil

    /// `confirmQuitAll` : réglage `confirm_quit_all`.
    static func all(confirmQuitAll: Bool = true) -> [LauncherSystemCommand] {
        [
            .init(id: "lock", title: "Verrouiller l'écran", keywords: ["verrouiller", "lock"], symbol: "lock", confirms: false),
            .init(id: "sleep-displays", title: "Suspendre les écrans", keywords: ["écrans", "displays", "sleep displays"],
                  symbol: "display", confirms: false),
            .init(id: "sleep", title: "Suspendre l'activité", keywords: ["veille", "suspendre", "sleep"], symbol: "moon", confirms: false),
            .init(id: "screensaver", title: "Économiseur d'écran", keywords: ["économiseur", "screensaver"], symbol: "sparkles.tv", confirms: false),
            .init(id: "quit-all", title: "Tout quitter", keywords: ["quitter tout", "quit all"], symbol: "xmark.circle", confirms: confirmQuitAll),
            .init(id: "show-trash", title: "Afficher la corbeille", keywords: ["corbeille", "trash"], symbol: "trash", confirms: false),
            .init(id: "empty-trash", title: "Vider la corbeille", keywords: ["corbeille", "empty trash"], symbol: "trash.slash", confirms: true),
            .init(id: "eject-all", title: "Tout éjecter", keywords: ["éjecter", "eject"], symbol: "eject", confirms: false),
            .init(id: "volume-up", title: "Monter le son", keywords: ["volume", "son +"], symbol: "speaker.wave.3", confirms: false),
            .init(id: "volume-down", title: "Baisser le son", keywords: ["volume", "son -"], symbol: "speaker.wave.1", confirms: false),
            .init(id: "mute", title: "Couper ou remettre le son", keywords: ["muet", "mute", "volume"], symbol: "speaker.slash", confirms: false),
            .init(id: "logout", title: "Fermer la session", keywords: ["déconnexion", "log out"], symbol: "rectangle.portrait.and.arrow.right", confirms: true),
            .init(id: "restart", title: "Redémarrer", keywords: ["restart", "reboot"], symbol: "restart", confirms: true),
            .init(id: "shutdown", title: "Éteindre", keywords: ["shut down", "arrêter"], symbol: "power", confirms: true),
        ]
    }

    /// Titre, puis début d'un mot-clé (3 lettres au moins). O(k × t).
    func score(_ query: String) -> Int? {
        if let score = LauncherMatch.score(query, in: title) { return score }
        let needle = LauncherMatch.fold(query)
        guard needle.count >= 3, keywords.contains(where: { LauncherMatch.fold($0).hasPrefix(needle) }) else { return nil }
        return 2
    }

    /// Commandes qui correspondent, `limit` au plus (trois), dès deux lettres ; à score égal, le titre le plus
    /// court. O(c × q × t + c log c).
    static func matches(_ query: String, in commands: [LauncherSystemCommand], limit: Int = 3) -> [LauncherSystemCommand] {
        guard LauncherMatch.fold(query).count >= 2 else { return [] }
        return commands.compactMap { command in command.score(query).map { (command, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.title.count < $1.0.title.count }.prefix(limit).map(\.0)
    }

    /// Applications quittées par « Tout quitter » : applications ordinaires, sauf le Finder et Roadie.
    static func quitAllTargets(_ apps: [(bundleID: String?, regular: Bool, pid: pid_t)], ownPID: pid_t) -> [pid_t] {
        apps.filter { $0.regular && $0.bundleID != "com.apple.finder" && $0.pid != ownPID }.map(\.pid)
    }

    /// Exécute la commande. Les scripts passent par `osascript` dans leur propre processus.
    @MainActor func run() {
        switch id {
        case "lock":
            // ⌃⌘Q, raccourci de macOS pour verrouiller ; Roadie a le droit d'accessibilité.
            let source = CGEventSource(stateID: .hidSystemState)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 12, keyDown: down)
                event?.flags = [.maskCommand, .maskControl]
                event?.post(tap: .cghidEventTap)
            }
        case "sleep-displays": Self.process("/usr/bin/pmset", ["displaysleepnow"])
        case "sleep": Self.process("/usr/bin/pmset", ["sleepnow"])
        case "screensaver": Self.process("/usr/bin/open", ["-a", "ScreenSaverEngine"])
        case "quit-all":
            let own = ProcessInfo.processInfo.processIdentifier
            let apps = NSWorkspace.shared.runningApplications
            let pids = Set(Self.quitAllTargets(apps.map { ($0.bundleIdentifier, $0.activationPolicy == .regular, $0.processIdentifier) }, ownPID: own))
            apps.filter { pids.contains($0.processIdentifier) }.forEach { $0.terminate() }
        case "show-trash": NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash"))
        case "empty-trash": Self.script("tell application \"Finder\" to empty trash")
        case "eject-all": Self.script("tell application \"Finder\" to eject (every disk whose ejectable is true)")
        case "volume-up": Self.script("set volume output volume ((output volume of (get volume settings)) + 10)")
        case "volume-down": Self.script("set volume output volume ((output volume of (get volume settings)) - 10)")
        case "mute": Self.script("set volume output muted (not (output muted of (get volume settings)))")
        case "logout": Self.script("tell application \"System Events\" to log out")
        case "restart": Self.script("tell application \"System Events\" to restart")
        case "shutdown": Self.script("tell application \"System Events\" to shut down")
        default:
            // Réglages trouvés (session 115) : panneau des Réglages Système, page ou réglage de Roadie.
            if id.hasPrefix(LauncherSettingTargets.panePrefix),
               let url = LauncherSettingTargets.paneURL(String(id.dropFirst(LauncherSettingTargets.panePrefix.count))) {
                NSWorkspace.shared.open(url)
            } else if id.hasPrefix(LauncherSettingTargets.roadieCategoryPrefix) {
                SettingsWindowController.shared.show(category: SettingCategory(rawValue: String(id.dropFirst(LauncherSettingTargets.roadieCategoryPrefix.count))))
            } else if id.hasPrefix(LauncherSettingTargets.roadieSettingPrefix),
                      let descriptor = SettingsCatalog.find(id: String(id.dropFirst(LauncherSettingTargets.roadieSettingPrefix.count))) {
                SettingsWindowController.shared.show(category: descriptor.category, query: descriptor.label)
            }
        }
    }

    private static func script(_ source: String) {
        Task { _ = await LauncherBrowsers.run(source, timeout: 10) }
    }

    private static func process(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try? process.run()
    }
}
