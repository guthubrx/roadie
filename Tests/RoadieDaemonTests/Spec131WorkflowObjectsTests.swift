import Foundation
import Testing
@testable import RoadieDaemon

/// Session 131 : briques d'Alfred Commande système, Commande Musique, Dictionnaire, Applications ouvertes.
struct Spec131WorkflowObjectsTests {
    @Test func numberTablesFollowTheRecordedWorkflows() {
        // Numéros relevés dans des workflows publics (research R2, R3).
        #expect(AlfredSystemObjects.systemCommandID(1) == "screensaver")
        #expect(AlfredSystemObjects.systemCommandID(6) == "lock")
        #expect(AlfredSystemObjects.systemCommandID(7) == "restart")
        #expect(AlfredSystemObjects.systemCommandID(8) == "shutdown")
        #expect(AlfredSystemObjects.systemCommandID(9) == "quit-all")
        #expect(AlfredSystemObjects.systemCommandID(11) == "sleep-displays")
        #expect(AlfredSystemObjects.systemCommandID(99) == nil)
        // Chaque identifiant existe dans les commandes système de la barre.
        let known = Set(LauncherSystemCommand.all().map(\.id))
        for number in 1...14 { #expect(AlfredSystemObjects.systemCommandID(number).map(known.contains) == true, "\(number)") }
        #expect(AlfredSystemObjects.musicScript(1)?.contains("playpause") == true)
        #expect(AlfredSystemObjects.musicScript(13)?.contains("100") == true)
        #expect(AlfredSystemObjects.musicScript(5) == nil)
    }

    @Test func engineRunsSystemAndMusicCommands() async throws {
        var fixture = WorkflowFixture()
        fixture.add("K", "input.keyword", ["keyword": "k"])
        fixture.add("SYS", "action.systemcommand", ["command": 6, "confirm": false])
        fixture.add("ASK", "action.systemcommand", ["command": 8, "confirm": true])
        fixture.add("MUS", "action.itunescommand", ["command": 2])
        fixture.add("BAD", "action.itunescommand", ["command": 42])
        for uid in ["SYS", "ASK", "MUS", "BAD"] { fixture.link("K", uid) }
        let workflow = try fixture.write()
        let effects = RecordedEffects()
        let outcome = await AlfredWorkflowEngine(effects: effects).run(workflow, from: "K", arg: [""])
        #expect(effects.calls.contains("system:lock"))
        #expect(effects.calls.contains("system:shutdown") && effects.calls.contains { $0.hasPrefix("dialog:") })
        #expect(effects.calls.contains("music:next track"))
        #expect(outcome.errors.contains("musiccommand:42"))

        // Confirmation refusée : la commande n'est pas lancée.
        let refusing = RecordedEffects()
        refusing.dialogChoice = 2
        _ = await AlfredWorkflowEngine(effects: refusing).run(workflow, from: "K", arg: [""])
        #expect(!refusing.calls.contains("system:shutdown") && refusing.calls.contains("system:lock"))
    }

    @MainActor @Test func dictionaryAndRunningAppsRows() {
        let items = AlfredSystemObjects.dictionaryItems("chat", showAllWords: true,
                                                        definition: { $0 == "chat" ? "chat\nanimal domestique" : nil },
                                                        completions: { _ in ["chat", "chaton", "chatte"] })
        #expect(items.map(\.title) == ["chat", "chaton", "chatte"])
        #expect(items[0].subtitle == "chat" && items[0].arg == ["chat"] && items[1].subtitle == "Aucune définition")
        #expect(AlfredSystemObjects.dictionaryItems("  ", showAllWords: false).isEmpty)

        let apps = [AlfredSystemObjects.RunningApp(name: "Safari", path: "/Applications/Safari.app", bundleID: "com.apple.Safari"),
                    AlfredSystemObjects.RunningApp(name: "Mail", path: "/System/Applications/Mail.app", bundleID: "com.apple.mail")]
        let found = AlfredSystemObjects.runningAppItems("saf", apps: apps, outputType: 2, prefix: "id:")
        #expect(found.map(\.title) == ["Safari"] && found[0].arg == ["id:com.apple.Safari"])
        #expect(AlfredSystemObjects.runningAppItems("", apps: apps, outputType: 0, prefix: "").map(\.arg) == [["/System/Applications/Mail.app"], ["/Applications/Safari.app"]])
    }

    @Test func indexAndCompatibility() throws {
        var fixture = WorkflowFixture()
        fixture.add("D", "input.dictionaryfilter", ["keyword": "def", "showallwords": true])
        fixture.add("R", "input.runningappsfilter", ["keyword": "apps", "outputtype": 1, "outputprefix": ">"])
        fixture.add("S", "action.systemcommand", ["command": 6])
        fixture.add("M", "action.itunescommand", ["command": 1])
        fixture.link("D", "S")
        fixture.link("R", "M")
        let workflow = try fixture.write()
        let entries = AlfredWorkflowIndex.entries([workflow])
        #expect(entries.first { $0.keyword == "def" }?.kind == .dictionary && entries.first { $0.keyword == "def" }?.showAllWords == true)
        let apps = entries.first { $0.keyword == "apps" }
        #expect(apps?.kind == .runningApps && apps?.outputType == 1 && apps?.outputPrefix == ">")
        #expect(AlfredCompatibility.report(workflow).state == .complete)
    }
}
