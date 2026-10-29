import AppKit
import Foundation
import RoadieCore

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

    /// Titre dans la langue de l'interface ; les deux noms restent des mots-clés (session 126).
    init(id: String, fr: String, en: String, keywords: [String], symbol: String, confirms: Bool) {
        self.init(id: id, title: tr(fr, en), keywords: keywords + [fr, en], symbol: symbol, confirms: confirms)
    }

    init(id: String, title: String, keywords: [String], symbol: String, confirms: Bool, detail: String? = nil) {
        self.id = id
        self.title = title
        self.keywords = keywords
        self.symbol = symbol
        self.confirms = confirms
        self.detail = detail
    }

    /// `confirmQuitAll` : réglage `confirm_quit_all`.
    static func all(confirmQuitAll: Bool = true) -> [LauncherSystemCommand] {
        [
            .init(id: "lock", fr: "Verrouiller l'écran", en: "Lock screen", keywords: ["verrouiller", "lock"], symbol: "lock", confirms: false),
            .init(id: "sleep-displays", fr: "Suspendre les écrans", en: "Sleep displays", keywords: ["écrans", "displays", "sleep displays"],
                  symbol: "display", confirms: false),
            .init(id: "sleep", fr: "Suspendre l'activité", en: "Sleep", keywords: ["veille", "suspendre", "sleep"], symbol: "moon", confirms: false),
            .init(id: "screensaver", fr: "Économiseur d'écran", en: "Screen saver", keywords: ["économiseur", "screensaver"], symbol: "sparkles.tv", confirms: false),
            .init(id: "quit-all", fr: "Tout quitter", en: "Quit all", keywords: ["quitter tout", "quit all"], symbol: "xmark.circle", confirms: confirmQuitAll),
            .init(id: "show-trash", fr: "Afficher la corbeille", en: "Show trash", keywords: ["corbeille", "trash"], symbol: "trash", confirms: false),
            .init(id: "empty-trash", fr: "Vider la corbeille", en: "Empty trash", keywords: ["corbeille", "empty trash"], symbol: "trash.slash", confirms: true),
            .init(id: "eject-all", fr: "Tout éjecter", en: "Eject all", keywords: ["éjecter", "eject"], symbol: "eject", confirms: false),
            .init(id: "volume-up", fr: "Monter le son", en: "Volume up", keywords: ["volume", "son +"], symbol: "speaker.wave.3", confirms: false),
            .init(id: "volume-down", fr: "Baisser le son", en: "Volume down", keywords: ["volume", "son -"], symbol: "speaker.wave.1", confirms: false),
            .init(id: "mute", fr: "Couper ou remettre le son", en: "Mute or unmute", keywords: ["muet", "mute", "volume"], symbol: "speaker.slash", confirms: false),
            .init(id: "logout", fr: "Fermer la session", en: "Log out", keywords: ["déconnexion", "log out"], symbol: "rectangle.portrait.and.arrow.right", confirms: true),
            .init(id: "restart", fr: "Redémarrer", en: "Restart", keywords: ["restart", "reboot"], symbol: "restart", confirms: true),
            .init(id: "shutdown", fr: "Éteindre", en: "Shut down", keywords: ["shut down", "arrêter"], symbol: "power", confirms: true),
            // Session 119 : « reload » et la reconstruction de l'index de macOS, dans l'Avancé d'Alfred.
            .init(id: "reload-apps", fr: "Recharger les applications", en: "Reload apps", keywords: ["reload", "recharger"], symbol: "arrow.clockwise",
                  confirms: false),
            .init(id: "rebuild-spotlight", fr: "Reconstruire l'index Spotlight", en: "Rebuild Spotlight index", keywords: ["spotlight", "mdutil", "index"],
                  symbol: "magnifyingglass.circle", confirms: true),
            // Session 131 : tâches d'Alfred « Apparence » et « Captures d'écran », depuis la barre seule.
            .init(id: "dark-mode", fr: "Basculer le mode sombre", en: "Toggle dark mode", keywords: ["mode sombre", "dark mode", "apparence", "appearance"],
                  symbol: "circle.lefthalf.filled", confirms: false),
            .init(id: "screenshot-screen", fr: "Capture de l'écran", en: "Screenshot of the screen", keywords: ["capture", "screenshot", "écran", "screen"],
                  symbol: "camera.viewfinder", confirms: false),
            .init(id: "screenshot-area", fr: "Capture d'une zone", en: "Screenshot of an area", keywords: ["capture", "screenshot", "zone", "area"],
                  symbol: "rectangle.dashed", confirms: false),
            .init(id: "screenshot-window", fr: "Capture d'une fenêtre", en: "Screenshot of a window", keywords: ["capture", "screenshot", "fenêtre", "window"],
                  symbol: "macwindow", confirms: false),
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
        case "sleep-displays": process("/usr/bin/pmset", ["displaysleepnow"])
        case "sleep": process("/usr/bin/pmset", ["sleepnow"])
        case "screensaver": process("/usr/bin/open", ["-a", "ScreenSaverEngine"])
        case "quit-all":
            let own = ProcessInfo.processInfo.processIdentifier
            let apps = NSWorkspace.shared.runningApplications
            let pids = Set(Self.quitAllTargets(apps.map { ($0.bundleIdentifier, $0.activationPolicy == .regular, $0.processIdentifier) }, ownPID: own))
            apps.filter { pids.contains($0.processIdentifier) }.forEach { $0.terminate() }
        case "show-trash": NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash"))
        case "empty-trash": script("tell application \"Finder\" to empty trash")
        case "eject-all": script("tell application \"Finder\" to eject (every disk whose ejectable is true)")
        case "volume-up": script("set volume output volume ((output volume of (get volume settings)) + 10)")
        case "volume-down": script("set volume output volume ((output volume of (get volume settings)) - 10)")
        case "mute": script("set volume output muted (not (output muted of (get volume settings)))")
        case "logout": script("tell application \"System Events\" to log out")
        case "restart": script("tell application \"System Events\" to restart")
        case "shutdown": script("tell application \"System Events\" to shut down")
        case "reload-apps": LauncherAppCatalog.shared.refresh()
        // macOS demande le mot de passe d'un administrateur ; l'index se reconstruit ensuite en arrière-plan (plus d'une heure).
        case "rebuild-spotlight": script("do shell script \"/usr/bin/mdutil -E /\" with administrator privileges")
        case "dark-mode": script("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
        case "screenshot-screen", "screenshot-area", "screenshot-window":
            // La barre se ferme d'abord, pour ne pas être sur l'image.
            let arguments = Self.screenshotArguments(id) + [Self.screenshotPath()]
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                process("/usr/sbin/screencapture", arguments)
            }
        default:
            // Raccourci de l'app Raccourcis (session 131).
            if id.hasPrefix(LauncherAppleShortcuts.prefix) {
                process("/usr/bin/shortcuts", ["run", String(id.dropFirst(LauncherAppleShortcuts.prefix.count))])
                return
            }
            // Élément d'un menu de l'application active (session 131).
            if id.hasPrefix("menu:") {
                if let index = Int(id.dropFirst("menu:".count)) { LauncherMenuSearch.shared.press(index) }
                return
            }
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

    /// Options de `screencapture` : écran principal, zone choisie (Espace passe à une fenêtre), fenêtre choisie. O(1).
    static func screenshotArguments(_ id: String) -> [String] {
        switch id {
        case "screenshot-area": ["-i"]
        case "screenshot-window": ["-iW"]
        default: ["-m"]
        }
    }

    /// Fichier d'une capture : dossier réglé dans macOS (`com.apple.screencapture location`), sinon le Bureau ; nom
    /// daté comme ceux de macOS. O(1).
    static func screenshotPath(now: Date = Date(), location: String? = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
                               home: String = NSHomeDirectory()) -> String {
        let folder = location.map { ($0 as NSString).expandingTildeInPath }.flatMap { $0.isEmpty ? nil : $0 }
            ?? (home as NSString).appendingPathComponent("Desktop")
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd' \(tr("à", "at")) 'HH.mm.ss"
        return (folder as NSString).appendingPathComponent(tr("Capture d'écran", "Screenshot") + " " + format.string(from: now) + ".png")
    }

    /// Délai d'un script : une boîte de mot de passe ou de confirmation (session, redémarrage) attend
    /// l'utilisateur ; l'arrêter plus tôt annulerait la commande sans le dire (audit du 29 octobre 2026).
    static let scriptTimeout: TimeInterval = 600

    /// Script dans un `try` : il rend « ok », ou le numéro de son erreur. O(n).
    static func guarded(_ source: String) -> String {
        "try\n\(source)\nreturn \"ok\"\non error number errorNumber\nreturn errorNumber as text\nend try"
    }

    /// Message d'échec d'après la réponse du script gardé ; nil pour une réussite ou une annulation par
    /// l'utilisateur (-128). Sans réponse (osascript arrêté ou absent) : échec sans numéro. O(1).
    static func failureMessage(_ title: String, answer: String?) -> String? {
        let answer = answer?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard answer != "ok", answer != "-128" else { return nil }
        return tr("\(title) : échec", "\(title): failed") + (answer.map { " (\($0))" } ?? "")
    }

    /// Lance un script de la commande et signale son échec par une notification (session 129).
    private func script(_ source: String) {
        let title = title
        Task {
            let answer = await LauncherBrowsers.run(Self.guarded(source), timeout: Self.scriptTimeout)
            if let message = Self.failureMessage(title, answer: answer) { await Self.notify(message) }
        }
    }

    private func process(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do { try process.run() } catch {
            let message = tr("\(title) : échec", "\(title): failed")
            Task { await Self.notify(message) }
        }
    }

    private static func notify(_ text: String) async {
        _ = await LauncherBrowsers.run("display notification \"\(text.applescriptEscaped)\" with title \"Roadie\"", timeout: 3)
    }
}

/// Raccourcis de l'app Raccourcis dans la barre (session 131), comme la famille « Raccourcis » des tâches d'Alfred :
/// lus par `shortcuts list` en fond, gardés 10 minutes, montrés comme des commandes « Système ».
final class LauncherAppleShortcuts: @unchecked Sendable {
    static let shared = LauncherAppleShortcuts()
    static let prefix = "shortcut:"

    private let lock = NSLock()
    private var names: [String] = []
    private var readAt: Date?
    private var reading = false

    /// Noms de la sortie de `shortcuts list` : une ligne par raccourci, espaces retirés, sans doublon. O(n).
    static func parse(_ output: String) -> [String] {
        var seen = Set<String>()
        return output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Commandes de la barre pour les raccourcis connus. O(n).
    var commands: [LauncherSystemCommand] {
        lock.withLock { names }.map {
            LauncherSystemCommand(id: Self.prefix + $0, title: $0, keywords: ["raccourci", "shortcut", "raccourcis", "shortcuts"],
                                  symbol: "square.2.layers.3d", confirms: false, detail: tr("Raccourci", "Shortcut"))
        }
    }

    /// Relit la liste en fond si elle a plus de 10 minutes. O(1) sur l'appelant.
    func refresh(now: Date = Date()) {
        let start = lock.withLock { () -> Bool in
            if reading { return false }
            if let readAt, now.timeIntervalSince(readAt) < 600 { return false }
            reading = true
            return true
        }
        guard start, !TestEnvironment.isRunningTests else { lock.withLock { reading = false }; return }
        Task {
            let output = await LauncherBrowsers.runProcess("/usr/bin/shortcuts", ["list"], timeout: 5)
            lock.withLock {
                if let output { names = Self.parse(output) }
                readAt = Date()
                reading = false
            }
        }
    }
}
