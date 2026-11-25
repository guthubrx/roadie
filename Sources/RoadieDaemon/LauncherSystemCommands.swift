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
    /// Titre et mots-clés pré-pliés une seule fois à la construction (Lot K : supprime les milliers d'appels
    /// `String.folding` par touche sur les réglages et commandes système).
    let preparedTitle: LauncherMatch.Prepared
    let foldedKeywords: [String]

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
        self.preparedTitle = LauncherMatch.Prepared(title)
        self.foldedKeywords = keywords.map(LauncherMatch.fold)
    }

    static func == (lhs: LauncherSystemCommand, rhs: LauncherSystemCommand) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.keywords == rhs.keywords
            && lhs.symbol == rhs.symbol && lhs.confirms == rhs.confirms && lhs.detail == rhs.detail
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(keywords)
        hasher.combine(symbol)
        hasher.combine(confirms)
        hasher.combine(detail)
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
            // Navigateur SF Symbols d'Alfred 6.
            .init(id: "sf-symbols:", fr: "Navigateur SF Symbols", en: "SF Symbols browser", keywords: ["symbols", "symboles", "icônes", "icons", "sf"],
                  symbol: "square.grid.3x3", confirms: false),
            // Session 173 (SPEC-157) : commandes Roadie d'ergonomie directe depuis le lanceur.
            .init(id: "roadie-balance", fr: "Égaliser les proportions", en: "Equalize proportions",
                  keywords: ["egaliser", "equalize", "equilibrer", "balance", "proportions", "fenetres", "windows", "tuiles"],
                  symbol: "rectangle.split.2x1", confirms: false),
            .init(id: "roadie-display-swap", fr: "Échanger les écrans", en: "Swap displays",
                  keywords: ["echanger", "swap", "ecrans", "displays", "inverser", "switch displays"],
                  symbol: "rectangle.2.swap", confirms: false),
            .init(id: "roadie-prune-empty", fr: "Nettoyer les stages vides", en: "Clean up empty stages",
                  keywords: ["nettoyer", "prune", "vides", "empty", "stages", "bureaux", "clean"],
                  symbol: "sparkles", confirms: false),
            // Session 178 (SPEC-160) : Quick Wins WM.
            .init(id: "roadie-window-close", fr: "Fermer la fenêtre active", en: "Close active window",
                  keywords: ["fermer", "close", "fenetre", "window", "quitter"],
                  symbol: "xmark.square", confirms: false),
            .init(id: "roadie-window-gather-app", fr: "Rassembler les fenêtres de l'app", en: "Gather app windows",
                  keywords: ["rassembler", "gather", "app", "application", "fenetres", "windows", "regrouper"],
                  symbol: "square.stack.3d.up", confirms: false),
            .init(id: "roadie-layout-rotate", fr: "Pivoter la disposition (90°)", en: "Rotate layout (90°)",
                  keywords: ["pivoter", "rotate", "rotation", "tourner", "layout", "disposition", "bsp"],
                  symbol: "rotate.right", confirms: false),
            .init(id: "roadie-layout-mirror-x", fr: "Miroir horizontal de la disposition", en: "Mirror layout horizontally",
                  keywords: ["miroir", "mirror", "flip", "inverser", "horizontal", "layout", "disposition"],
                  symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", confirms: false),
            .init(id: "roadie-layout-mirror-y", fr: "Miroir vertical de la disposition", en: "Mirror layout vertically",
                  keywords: ["miroir", "mirror", "flip", "inverser", "vertical", "layout", "disposition"],
                  symbol: "arrow.up.and.down.righttriangle.up.righttriangle.down", confirms: false),
            // Session 179 (SPEC-161) : pipette de couleur native (NSColorSampler).
            .init(id: "color-picker", fr: "Pipette de couleur", en: "Color picker",
                  keywords: ["color", "couleur", "pipette", "eyedropper", "hex", "rgb", "hsl", "picker"],
                  symbol: "eyedropper", confirms: false),
            // Session 180 (SPEC-162) : bascule rapide du scratchpad flottant.
            .init(id: "roadie-scratchpad-toggle", fr: "Scratchpad (afficher/masquer)", en: "Toggle scratchpad",
                  keywords: ["scratchpad", "tiroir", "flottant", "floating", "drawer", "toggle"],
                  symbol: "macwindow.on.rectangle", confirms: false),
            // Session 182 (SPEC-164) : modes de disposition avancés (Onglets & Ruban défilant).
            .init(id: "roadie-mode-tabbed", fr: "Disposition : Onglets (tabbed)", en: "Layout: Tabbed",
                  keywords: ["tabbed", "tabs", "onglets", "mode", "disposition", "layout"],
                  symbol: "rectangle.topthird.inset.filled", confirms: false),
            .init(id: "roadie-mode-scrolling", fr: "Disposition : Ruban défilant (scrolling)", en: "Layout: Scrolling ribbon",
                  keywords: ["scrolling", "scroll", "ribbon", "ruban", "niri", "mode", "disposition", "layout"],
                  symbol: "rectangle.split.3x1", confirms: false),
            // Session 186 (SPEC-165) : tuiles à onglets intégrées dans spatialBsp.
            .init(id: "roadie-tab-next", fr: "Onglet suivant", en: "Next tab",
                  keywords: ["tab", "onglet", "suivant", "next", "tuile", "bsp"],
                  symbol: "arrow.right.square", confirms: false),
            .init(id: "roadie-tab-prev", fr: "Onglet précédent", en: "Previous tab",
                  keywords: ["tab", "onglet", "precedent", "previous", "prev", "tuile", "bsp"],
                  symbol: "arrow.left.square", confirms: false),
            .init(id: "roadie-tab-stack-left", fr: "Empiler en onglet (gauche)", en: "Stack as tab (left)",
                  keywords: ["tab", "stack", "empiler", "onglet", "gauche", "left", "tuile"],
                  symbol: "square.stack.3d.up", confirms: false),
            .init(id: "roadie-tab-stack-right", fr: "Empiler en onglet (droite)", en: "Stack as tab (right)",
                  keywords: ["tab", "stack", "empiler", "onglet", "droite", "right", "tuile"],
                  symbol: "square.stack.3d.up", confirms: false),
            .init(id: "roadie-tab-stack-up", fr: "Empiler en onglet (haut)", en: "Stack as tab (up)",
                  keywords: ["tab", "stack", "empiler", "onglet", "haut", "up", "tuile"],
                  symbol: "square.stack.3d.up", confirms: false),
            .init(id: "roadie-tab-stack-down", fr: "Empiler en onglet (bas)", en: "Stack as tab (down)",
                  keywords: ["tab", "stack", "empiler", "onglet", "bas", "down", "tuile"],
                  symbol: "square.stack.3d.up", confirms: false),
            .init(id: "roadie-tab-unstack", fr: "Détacher l'onglet en tuile", en: "Detach tab to tile",
                  keywords: ["tab", "unstack", "detach", "detacher", "onglet", "tuile", "separer"],
                  symbol: "rectangle.split.2x1", confirms: false),
        ]
    }

    /// Titre, puis début d'un mot-clé (3 lettres au moins). O(k × t).
    func score(_ query: String) -> Int? {
        score(LauncherMatch.Query(query), needle: LauncherMatch.fold(query))
    }

    /// Variante sur requête déjà pliée une seule fois par frappe (Lot K). O(t + k).
    func score(_ query: LauncherMatch.Query?, needle: String) -> Int? {
        if let query, let score = LauncherMatch.score(query, in: preparedTitle) { return score }
        guard needle.count >= 3, foldedKeywords.contains(where: { $0.hasPrefix(needle) }) else { return nil }
        return 2
    }

    /// Commandes qui correspondent, `limit` au plus (trois), dès deux lettres ; à score égal, le titre le plus
    /// court. O(c × t + k log k) grâce au pré-pliage unique de la saisie et des commandes (Lot K).
    static func matches(_ query: String, in commands: [LauncherSystemCommand], limit: Int = 3) -> [LauncherSystemCommand] {
        let needle = LauncherMatch.fold(query)
        guard needle.count >= 2 else { return [] }
        let prepared = LauncherMatch.Query(query)
        return commands.compactMap { command in command.score(prepared, needle: needle).map { (command, $0) } }
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
        case "roadie-balance":
            Task.detached(priority: .userInitiated) { _ = LayoutCommandService().balance() }
        case "roadie-display-swap":
            Task.detached(priority: .userInitiated) { _ = DisplayCommandService().swapDefault() }
        case "roadie-prune-empty":
            Task.detached(priority: .userInitiated) { _ = StageCommandService().pruneEmpty() }
        case "roadie-window-close":
            Task.detached(priority: .userInitiated) { _ = WindowCommandService().close() }
        case "roadie-window-gather-app":
            Task.detached(priority: .userInitiated) { _ = WindowCommandService().gatherApp() }
        case "roadie-layout-rotate":
            Task.detached(priority: .userInitiated) { _ = LayoutCommandService().rotate(90) }
        case "roadie-layout-mirror-x":
            Task.detached(priority: .userInitiated) { _ = LayoutCommandService().mirror("x") }
        case "roadie-layout-mirror-y":
            Task.detached(priority: .userInitiated) { _ = LayoutCommandService().mirror("y") }
        case "color-picker":
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                LauncherColorFormat.pickColor()
            }
        case "roadie-scratchpad-toggle":
            Task.detached(priority: .userInitiated) { _ = ScratchpadCommandService().toggle() }
        case "roadie-mode-tabbed":
            Task.detached(priority: .userInitiated) { _ = StageCommandService().setMode(.tabbed) }
        case "roadie-mode-scrolling":
            Task.detached(priority: .userInitiated) { _ = StageCommandService().setMode(.scrolling) }
        case "roadie-tab-next":
            Task.detached(priority: .userInitiated) { _ = WindowCommandService().tabCycle(delta: 1) }
        case "roadie-tab-prev":
            Task.detached(priority: .userInitiated) { _ = WindowCommandService().tabCycle(delta: -1) }
        case "roadie-tab-stack-left":
            Task.detached(priority: .userInitiated) { _ = WindowCommandService().tabStack(.left) }
        case "roadie-tab-stack-right":
            Task.detached(priority: .userInitiated) { _ = WindowCommandService().tabStack(.right) }
        case "roadie-tab-stack-up":
            Task.detached(priority: .userInitiated) { _ = WindowCommandService().tabStack(.up) }
        case "roadie-tab-stack-down":
            Task.detached(priority: .userInitiated) { _ = WindowCommandService().tabStack(.down) }
        case "roadie-tab-unstack":
            Task.detached(priority: .userInitiated) { _ = WindowCommandService().tabUnstack(nil) }
        case "roadie-timer-cancel-all":
            let count = LauncherTimerService.shared.cancelAll()
            LauncherTimerService.postLocalNotification(
                title: tr("Minuteurs annulés", "Timers cancelled"),
                body: tr("\(count) minuteur(s) arrêté(s)", "\(count) timer(s) stopped")
            )
        default:
            if id.hasPrefix("emoji-copy:") {
                let glyph = String(id.dropFirst("emoji-copy:".count))
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(glyph, forType: .string)
                return
            }
            if id.hasPrefix("roadie-timer-start:") {
                let payload = String(id.dropFirst("roadie-timer-start:".count))
                let parts = payload.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                if let secStr = parts.first, let seconds = Int(secStr), seconds > 0 {
                    let label = parts.count > 1 ? String(parts[1]) : tr("Minuteur", "Timer")
                    let timer = LauncherTimerService.shared.start(seconds: seconds, label: label)
                    LauncherTimerService.postLocalNotification(
                        title: tr("Minuteur démarré : \(timer.label)", "Timer started: \(timer.label)"),
                        body: LauncherTimerService.formatDuration(timer.totalSeconds)
                    )
                }
                return
            }
            if id.hasPrefix("roadie-timer-cancel:") {
                if let timerID = Int(id.dropFirst("roadie-timer-cancel:".count)) {
                    _ = LauncherTimerService.shared.cancel(id: timerID)
                }
                return
            }
            if id.hasPrefix("clipboard-copy:") {
                let entryID = String(id.dropFirst("clipboard-copy:".count))
                if let entry = ClipboardHistoryStore().load().entry(matching: entryID) {
                    _ = ClipboardMonitor.copyToPasteboard(entry.text)
                }
                return
            }
            if id.hasPrefix("snippet-copy:") {
                let keyword = String(id.dropFirst("snippet-copy:".count))
                let config = ConfigReloadService.shared.currentConfig()
                if config.snippets.enabled, let item = SnippetsService.find(keyword: keyword, in: config.snippets.items) {
                    let expanded = SnippetsService.expand(item.body, clipboardText: ClipboardMonitor.readPlainTextIfSafe())
                    _ = ClipboardMonitor.copyToPasteboard(expanded.text)
                }
                return
            }
            // Navigateur SF Symbols (session 131), avec la recherche tapée après `symbols`.
            if id.hasPrefix("sf-symbols:") {
                LauncherSymbolsPanel.show(query: String(id.dropFirst("sf-symbols:".count)))
                return
            }
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
