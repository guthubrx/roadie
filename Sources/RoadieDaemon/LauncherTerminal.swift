import AppKit
import Foundation

/// Commande tapée après `>` (session 103), comme le préfixe Terminal d'Alfred : elle s'exécute dans une
/// nouvelle fenêtre du terminal choisi par `terminal_app`, depuis le dossier personnel. Règles pures,
/// lancement à part.
enum LauncherTerminal {
    /// Façon de lancer la commande : script AppleScript, ou application ouverte avec des arguments
    /// (`open -na`, sans interpréteur intermédiaire), ou application ouverte et commande copiée.
    enum Plan: Equatable {
        case appleScript(String)
        case open(app: String, arguments: [String])
        case copyAndOpen(app: String)
    }

    /// Commande tapée : texte après `>`, sans espaces autour ; nil si la saisie ne commence pas par `>`.
    static func command(_ query: String) -> String? {
        guard query.hasPrefix(">") else { return nil }
        return String(query.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    /// Nom affiché et nom d'application de `terminal_app`.
    static func appName(_ setting: String) -> String {
        switch setting {
        case "iterm": "iTerm"
        case "ghostty": "Ghostty"
        case "warp": "Warp"
        case "kitty": "kitty"
        case "wezterm": "WezTerm"
        case "alacritty": "Alacritty"
        default: "Terminal"
        }
    }

    /// La fenêtre reste ouverte après la commande : le shell de connexion reprend la main.
    static func shellArguments(_ command: String, shell: String) -> [String] {
        [shell, "-lic", "\(command); exec \(shell) -l"]
    }

    /// O(n). `shell` : shell de connexion de l'utilisateur (`$SHELL`).
    static func plan(_ setting: String, command: String, shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh") -> Plan {
        let escaped = command.applescriptEscaped
        switch setting {
        case "iterm":
            return .appleScript("""
            tell application "iTerm"
            activate
            set newWindow to (create window with default profile)
            tell current session of newWindow to write text "\(escaped)"
            end tell
            """)
        case "ghostty": return .open(app: "Ghostty", arguments: ["-e"] + shellArguments(command, shell: shell))
        case "kitty": return .open(app: "kitty", arguments: shellArguments(command, shell: shell))
        case "wezterm": return .open(app: "WezTerm", arguments: ["start", "--"] + shellArguments(command, shell: shell))
        case "alacritty": return .open(app: "Alacritty", arguments: ["-e"] + shellArguments(command, shell: shell))
        // Warp n'accepte pas de commande au lancement : il s'ouvre, la commande est dans le presse-papiers.
        case "warp": return .copyAndOpen(app: "Warp")
        default:
            return .appleScript("""
            tell application "Terminal"
            activate
            do script "\(escaped)"
            end tell
            """)
        }
    }

    /// Le terminal est-il installé ? O(1) par appel à Launch Services.
    @MainActor static func isInstalled(_ setting: String) -> Bool {
        let ids = ["terminal": "com.apple.Terminal", "iterm": "com.googlecode.iterm2", "ghostty": "com.mitchellh.ghostty",
                   "warp": "dev.warp.Warp-Stable", "kitty": "net.kovidgoyal.kitty", "wezterm": "com.github.wez.wezterm",
                   "alacritty": "org.alacritty"]
        if let id = ids[setting], NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil { return true }
        return NSWorkspace.shared.fullPath(forApplication: appName(setting)) != nil
    }

    /// Lance la commande ; faux si le lancement a échoué tout de suite.
    @MainActor static func run(_ setting: String, command: String) -> Bool {
        switch plan(setting, command: command) {
        case .appleScript(let script):
            Task { _ = await LauncherBrowsers.run(script, timeout: 5) }
            return true
        case .open(let app, let arguments):
            return open(["-na", app, "--args"] + arguments)
        case .copyAndOpen(let app):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            return open(["-a", app])
        }
    }

    private static func open(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        do { try process.run() } catch { return false }
        return true
    }
}
