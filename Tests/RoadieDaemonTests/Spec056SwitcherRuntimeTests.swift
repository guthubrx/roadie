import Testing
import RoadieCore
import Carbon
@testable import RoadieDaemon

struct Spec056SwitcherRuntimeTests {
    @Test @MainActor func searchHandlerDoesNotConsumeSwitcherHotkeys() {
        var presses = 0
        let search = TargetSearchHotkey { presses += 1 }
        #expect(search.handle(EventHotKeyID(signature: 0x52445357, id: 1)) == eventNotHandledErr)
        #expect(search.handle(EventHotKeyID(signature: 0x52445352, id: 2)) == eventNotHandledErr)
        #expect(presses == 0)
        #expect(search.handle(EventHotKeyID(signature: 0x52445352, id: 1)) == noErr)
        #expect(presses == 1)
    }
    @Test func externalCycleKeepsModifiersDirectionAndProfile() {
        let command = WindowSwitcherRuntimeBridge.command(["cycle", "--hold", "cmd", "--backwards", "--profile", "work"])
        #expect(command?.name == "switcher.cycle")
        #expect(command?.string("hold") == "cmd")
        #expect(command?.string("backwards") == "true")
        #expect(command?.string("profile") == "work")
        #expect(WindowSwitcherRuntimeBridge.command(["cycle", "--hold", "cmd++alt"]) == nil)
        #expect(WindowSwitcherRuntimeBridge.command(["cycle", "--hold", "tab"]) == nil)
        #expect(WindowSwitcherRuntimeBridge.command(["show", "--hold", "cmd"]) == nil)
        #expect(WindowSwitcherRuntimeBridge.command(["cycle", "--backwards", "--backwards"]) == nil)
    }

    @Test func cliKeepsProfileAndNavigationDistinct() {
        let command = WindowSwitcherRuntimeBridge.command(["show", "--profile", "work", "--json"])
        #expect(command?.name == "switcher.show")
        #expect(command?.string("profile") == "work")
        #expect(WindowSwitcherRuntimeBridge.command(["previous"])?.name == "switcher.previous")
    }

    @Test(arguments: [["show", "--profile"], ["next", "--profile", "work"], ["show", "unknown"], ["delete"], ["show", "--profile", "--json"]])
    func invalidArgumentsDoNotDispatch(arguments: [String]) {
        #expect(WindowSwitcherRuntimeBridge.command(arguments) == nil)
    }

    @Test @MainActor func cliAdvertisesAndRejectsBeforeDispatch() {
        let router = CLICommandRouter(makeService: { _ in
            let provider = PowerUserProvider(windows: [])
            return SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider),
                config: RoadieConfig(), intentStore: LayoutIntentStore(path: tempPath("switcher-cli-intents")),
                stageStore: StageStore(path: tempPath("switcher-cli-stages")),
                events: EventLog(path: tempPath("switcher-cli-events")), persistStateChanges: false)
        })
        #expect(router.run(["switcher", "--help"]).stdout.contains("--profile"))
        #expect(router.run(["switcher", "next", "--profile", "all"]).exitCode == 64)
        // Le client envoie une notification au composant graphique, sans acquisition AX locale.
        #expect(!CLICommandRouter.isDaemonRouted(["switcher", "show"]))
    }
}
