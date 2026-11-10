import Foundation
import Testing
@testable import RoadieDaemon

@MainActor @Suite struct Spec155ShellCompletionTests {
    private func lines() -> [String] {
        ShellCompletion.zsh(specs: CLICommandRouter.commandTable).components(separatedBy: "\n")
    }

    @Test func scriptListsTheImplementedCommands() throws {
        let all = lines()
        #expect(all.first == "#compdef roadie")
        let commands = try #require(all.first { $0.hasPrefix("  commands=(") })
        let names = commands.dropFirst("  commands=(".count).dropLast().split(separator: " ").map(String.init)
        #expect(names.contains("display"))
        #expect(names.contains("completion"))
        #expect(names.contains("update"))
        #expect(!names.contains("--version"))
        #expect(Set(names).count == names.count)
    }

    @Test func subcommandsComeFromTheSecondWord() {
        let all = lines()
        #expect(all.contains("      display) compadd list current focus ;;"))
        #expect(all.contains("      completion) compadd zsh ;;"))
        #expect(all.contains("      update) compadd check ;;"))
    }

    @Test func commandsNotImplementedAreLeftOut() throws {
        let script = ShellCompletion.zsh(specs: [
            CLICommandSpec(usage: "window close", implemented: false),
            CLICommandSpec(usage: "window reset"),
            CLICommandSpec(usage: "ghost run", implemented: false),
        ])
        #expect(script.contains("  commands=(window)"))
        #expect(script.contains("      window) compadd reset ;;"))
        #expect(!script.contains("close"))
        #expect(!script.contains("ghost"))
    }

    @Test func routerPrintsTheScriptAndRejectsOtherShells() {
        let router = CLICommandRouter()
        let response = router.run(["completion", "zsh"])
        #expect(response.exitCode == 0)
        #expect(response.stdout == ShellCompletion.zsh(specs: CLICommandRouter.commandTable) + "\n")
        #expect(router.run(["completion", "bash"]).exitCode == 64)
        #expect(router.run(["completion"]).exitCode == 64)
    }
}
