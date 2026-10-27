import Foundation
import RoadieCore
import Testing
@testable import RoadieDaemon

/// Session 103 : commande tapée après `>`, lancée dans le terminal choisi.
struct Spec103TerminalTests {
    @Test func theChevronIntroducesACommand() {
        #expect(LauncherTerminal.command("> ls -la") == "ls -la")
        #expect(LauncherTerminal.command(">top") == "top")
        #expect(LauncherTerminal.command(">") == "")
        #expect(LauncherTerminal.command("~/Documents") == nil)
        #expect(LauncherTerminal.command("firefox > x") == nil)
    }

    @Test func terminalAndITermGetAnEscapedScript() {
        let command = #"echo "salut" \ fin"#
        guard case .appleScript(let script) = LauncherTerminal.plan("terminal", command: command) else {
            Issue.record("Terminal : AppleScript attendu"); return
        }
        #expect(script.contains(#"tell application "Terminal""#))
        #expect(script.contains(#"do script "echo \"salut\" \\ fin""#))
        guard case .appleScript(let iterm) = LauncherTerminal.plan("iterm", command: "htop") else {
            Issue.record("iTerm : AppleScript attendu"); return
        }
        #expect(iterm.contains("create window with default profile"))
        #expect(iterm.contains(#"write text "htop""#))
    }

    @Test func otherTerminalsGetArgumentsWithoutAnIntermediateShellString() {
        let shell = "/bin/zsh"
        let keep = [shell, "-lic", "git status; exec /bin/zsh -l"]
        #expect(LauncherTerminal.plan("ghostty", command: "git status", shell: shell) == .open(app: "Ghostty", arguments: ["-e"] + keep))
        #expect(LauncherTerminal.plan("kitty", command: "git status", shell: shell) == .open(app: "kitty", arguments: keep))
        #expect(LauncherTerminal.plan("wezterm", command: "git status", shell: shell) == .open(app: "WezTerm", arguments: ["start", "--"] + keep))
        #expect(LauncherTerminal.plan("alacritty", command: "git status", shell: shell) == .open(app: "Alacritty", arguments: ["-e"] + keep))
        #expect(LauncherTerminal.plan("warp", command: "git status", shell: shell) == .copyAndOpen(app: "Warp"))
    }

    @Test func theSettingIsValidatedAndNamed() {
        #expect(TargetModeConfig(terminalApp: "iterm").terminalApp == "iterm")
        #expect(TargetModeConfig(terminalApp: "cmd.exe").terminalApp == "terminal")
        #expect(LauncherTerminal.appName("wezterm") == "WezTerm")
        #expect(LauncherTerminal.appName("autre") == "Terminal")
        #expect(LauncherList.Row.terminal("ls").id == "terminal")
    }
}
