import Foundation
import Testing
@testable import RoadieDaemon

/// Ordres à Alfred traduits par Roadie (SPEC-093), sur les formes relevées dans le corpus (research R1).
struct Spec093BridgeTests {
    private let cli = "/u/bin/roadie"
    private var call: String { #"do shell script "'/u/bin/roadie' workflow alfred "# }

    // MARK: AppleScript

    @Test func appleScriptOneLinersBecomeRoadieCommands() {
        func translate(_ text: String) -> String? { AlfredBridge.translate(text, language: .appleScript, cli: cli, version: "5.5") }
        #expect(translate(#"tell application "Alfred" to search "hue " & action"#)
            == call + #"search " & quoted form of ("hue " & action)"#)
        #expect(translate(#"tell application "Alfred 2" to search "|f ""#) == call + #"search " & quoted form of ("|f ")"#)
        #expect(translate(#"tell application id "com.runningwithcrayons.Alfred" to run trigger "build" in workflow "com.alfredapp.vitor.aliashomebrewapps""#)
            == call + #"trigger " & quoted form of ("com.alfredapp.vitor.aliashomebrewapps") & " " & quoted form of ("build")"#)
        #expect(translate(#"tell application "Alfred 4" to run trigger "remind" in workflow "com.surrealroad.alfred-reminder" with argument "demain""#)
            == call + #"trigger " & quoted form of ("com.surrealroad.alfred-reminder") & " " & quoted form of ("remind") & " " & quoted form of ("demain")"#)
        #expect(translate(#"tell application id "com.runningwithcrayons.Alfred" to reload workflow (system attribute "alfred_workflow_bundleid")"#)
            == call + #"reload " & quoted form of ((system attribute "alfred_workflow_bundleid"))"#)
        #expect(translate(#"tell application id "com.runningwithcrayons.Alfred" to return version"#) == #"return "5.5""#)
        #expect(translate(#"tell application id "com.runningwithcrayons.Alfred" to set configuration "k" to value "v" in workflow "w" as exportable false"#)
            == call + #"set " & quoted form of ("w") & " " & quoted form of ("k") & " " & quoted form of ("v")"#)
        #expect(translate(#"tell application "Alfred" to remove configuration "k" in workflow "w""#)
            == call + #"remove " & quoted form of ("w") & " " & quoted form of ("k")"#)
    }

    @Test func appleScriptBlocksAndUntouchedText() {
        let block = "set x to 1\ntell application \"Alfred 5\"\n  activate\n  search \"emoji \"\nend tell\nreturn x"
        #expect(AlfredBridge.translate(block, language: .appleScript, cli: cli, version: "5.5")
            == "set x to 1\n-- Alfred (Roadie)\n  set __roadieAlfred to 0\n  " + call + #"search " & quoted form of ("emoji ")"# + "\n-- fin\nreturn x")
        // Sans Alfred : rien n'est traduit (nil), le texte reste identique.
        #expect(AlfredBridge.translate(#"tell application "Finder" to activate"#, language: .appleScript, cli: cli, version: "5.5") == nil)
    }

    // MARK: JavaScript

    @Test func javaScriptApplicationBecomesRoadieObject() throws {
        let source = #"const alfred = Application("com.runningwithcrayons.Alfred"); alfred.runTrigger(argv[1], { inWorkflow: argv[0] })"#
        let translated = try #require(AlfredBridge.translate(source, language: .javaScript, cli: cli, version: "5.5"))
        #expect(translated.hasPrefix("var __roadieAlfred = "))
        #expect(translated.hasSuffix(#"const alfred = __roadieAlfred; alfred.runTrigger(argv[1], { inWorkflow: argv[0] })"#))
        #expect(translated.contains(#"'/u/bin/roadie' workflow alfred "#))
        // Shebang gardé en tête.
        let file = "#!/usr/bin/osascript -l JavaScript\nApplication('Alfred').search('x')"
        let shebang = try #require(AlfredBridge.translate(file, language: .javaScript, cli: cli, version: "5.5"))
        #expect(shebang.hasPrefix("#!/usr/bin/osascript -l JavaScript\nvar __roadieAlfred"))
        #expect(shebang.hasSuffix("__roadieAlfred.search('x')"))
        #expect(AlfredBridge.translate(#"Application("Notes").notes[0]"#, language: .javaScript, cli: cli, version: "5.5") == nil)
    }

    /// L'objet JavaScript appelle vraiment la commande (osascript réel, commande remplacée par `echo`).
    @Test func javaScriptObjectRunsTheCommand() async throws {
        let source = #"function run() { return Application("com.runningwithcrayons.Alfred").runTrigger("go", { inWorkflow: "w", withArgument: "it's" }) }"#
        let translated = try #require(AlfredBridge.translate(source, language: .javaScript, cli: "/bin/echo", version: "5.5"))
        let workflow = try WorkflowFixture().write()
        let result = await AlfredScriptRunner.run(AlfredScript(language: 7, source: translated), query: "", arguments: [], workflow: workflow, variables: [:])
        #expect(result.text.trimmingCharacters(in: .whitespacesAndNewlines) == "workflow alfred trigger w go it's")
    }

    // MARK: Fiche

    @Test func ordersFoundForTheReport() {
        let text = """
        osascript -e 'tell application id "com.runningwithcrayons.Alfred" to run trigger "x" in workflow "y"'
        const a = Application("com.runningwithcrayons.Alfred"); a.setConfiguration("k", {}); a.removeConfiguration("k", {})
        Application('com.runningwithcrayons.Alfred').action(["/tmp"])
        cache="$HOME/Library/Caches/com.runningwithcrayons.Alfred/Workflow Data"
        """
        let orders = AlfredBridge.orders(in: text)
        #expect(orders.translated == ["remove configuration", "run trigger", "set configuration"])
        #expect(orders.untranslated == ["action"])
        // Une simple citation (dossier de cache) n'est pas un ordre.
        #expect(AlfredBridge.orders(in: "~/Library/Caches/com.runningwithcrayons.Alfred/x").translated.isEmpty)
    }

    @Test func reportListsOrdersNotCitations() throws {
        var fixture = WorkflowFixture()
        fixture.add("K", "input.keyword", ["keyword": "k"])
        fixture.add("A", "action.script", ["type": 7, "script": #"Application("com.runningwithcrayons.Alfred").search("x")"#])
        fixture.add("B", "action.script", ["type": 0, "script": #"rm -rf "$HOME/Library/Caches/com.runningwithcrayons.Alfred/Workflow Data/x""#])
        fixture.link("K", "A")
        fixture.link("A", "B")
        let report = AlfredCompatibility.report(try fixture.write())
        #expect(report.orders == ["search"] && report.untranslated.isEmpty && report.mentionsAlfred)
        var citation = WorkflowFixture()
        citation.add("K", "input.keyword", ["keyword": "k"])
        citation.add("B", "action.script", ["type": 0, "script": #"ls "$HOME/Library/Caches/com.runningwithcrayons.Alfred""#])
        citation.link("K", "B")
        #expect(!AlfredCompatibility.report(try citation.write()).mentionsAlfred)
    }

    // MARK: osascript

    @Test func osascriptArgumentsAreParsedAndRebuilt() {
        let call = AlfredBridge.OsascriptCall(["-l", "JavaScript", "-e", "a", "-e", "b", "-s", "h", "x", "y"])
        #expect(call.language == "JavaScript" && call.statements == ["a", "b"] && call.options == ["-s", "h"])
        #expect(call.file == nil && call.arguments == ["x", "y"])
        let file = AlfredBridge.OsascriptCall(["/tmp/s.applescript", "1"])
        #expect(file.file == "/tmp/s.applescript" && file.arguments == ["1"] && file.statements.isEmpty)
        #expect(call.rebuilt(source: "z") == ["-l", "JavaScript", "-s", "h", "-e", "z", "x", "y"])
    }

    @Test func shellTextUsesRoadieOsascript() {
        let source = #"/usr/bin/osascript -e 'tell application id "com.runningwithcrayons.Alfred" to return version'"# + "\n<string>/usr/bin/osascript</string>"
        #expect(AlfredBridge.redirectOsascript(source, shim: "/c/osascript")
            == #"/c/osascript -e 'tell application id "com.runningwithcrayons.Alfred" to return version'"# + "\n<string>/usr/bin/osascript</string>")
        // Ordre écrit avec des guillemets échappés dans un `-e "…"` de shell.
        let escaped = #"/usr/bin/osascript -e "tell application id \"com.runningwithcrayons.Alfred\" to run trigger \"b\" in workflow \"w\"""#
        #expect(AlfredBridge.redirectOsascript(escaped, shim: "/c/osascript").hasPrefix("/c/osascript -e"))
        #expect(AlfredBridge.orders(in: escaped).translated == ["run trigger"])
        // Sans ordre à Alfred, le texte ne change pas.
        #expect(AlfredBridge.redirectOsascript("/usr/bin/osascript -e 'beep'", shim: "/c/osascript") == "/usr/bin/osascript -e 'beep'")
    }

    // MARK: Lancement (FR-003)

    @Test func scriptsAreBridgedBeforeLaunch() {
        let apple = AlfredScript(language: 6, source: #"tell application "Alfred" to search "x""#)
        #expect(AlfredScriptRunner.bridged(apple, cli: cli, shim: "/c/osascript").source == call + #"search " & quoted form of ("x")"#)
        let shell = AlfredScript(language: 0, source: #"/usr/bin/osascript -e 'tell application "Alfred" to search "x"'"#)
        #expect(AlfredScriptRunner.bridged(shell, cli: cli, shim: "/c/osascript").source.hasPrefix("/c/osascript -e"))
        let plain = AlfredScript(language: 0, source: "echo ok")
        #expect(AlfredScriptRunner.bridged(plain, cli: cli, shim: "/c/osascript") == plain)
        let external = AlfredScript(language: 8, source: "", file: "run.sh")
        #expect(AlfredScriptRunner.bridged(external, cli: cli, shim: "/c/osascript") == external)
        let env = AlfredScriptRunner.environment(workflow: AlfredWorkflow(id: "w", bundleID: "", name: "", description: "", version: "",
                                                                            folder: URL(fileURLWithPath: "/tmp"), source: .roadie, disabled: false,
                                                                            objects: [:], connections: [:], variables: [:], userSettings: [], prefs: [:]),
                                                 variables: [:], keyword: nil, base: ["PATH": "/opt/bin"], bridge: "/c/osascript")
        #expect(env["PATH"]?.hasPrefix("/c:/opt/bin:") == true)
    }

    /// AppleScript traduit exécuté pour de vrai (osascript), commande remplacée par `echo`.
    @Test func appleScriptTranslationRuns() async throws {
        let source = #"tell application id "com.runningwithcrayons.Alfred" to run trigger "go" in workflow "w" with argument "it's""#
        let translated = try #require(AlfredBridge.translate(source, language: .appleScript, cli: "/bin/echo", version: "5.5"))
        let workflow = try WorkflowFixture().write()
        let result = await AlfredScriptRunner.run(AlfredScript(language: 6, source: translated), query: "", arguments: [], workflow: workflow, variables: [:])
        #expect(result.text.trimmingCharacters(in: .whitespacesAndNewlines) == "workflow alfred trigger w go it's")
    }

    // MARK: Audit V15 (F1 à F3)

    /// F1 : fichier `.js` sans `-l` ; F3 : `running()` ; exécutés pour de vrai par osascript.
    @Test func auditFixesKeepJavaScriptFilesAndRunning() async throws {
        #expect(AlfredBridge.OsascriptCall(["/tmp/a.js", "x"]).rebuilt(source: "z") == ["-l", "JavaScript", "-e", "z", "x"])
        #expect(AlfredBridge.OsascriptCall(["/tmp/a.applescript"]).rebuilt(source: "z") == ["-e", "z"])
        let source = #"Application("com.runningwithcrayons.Alfred").running() ? "oui" : "non""#
        let translated = try #require(AlfredBridge.translate(source, language: .javaScript, cli: "/bin/echo", version: "5.5"))
        let workflow = try WorkflowFixture().write()
        let result = await AlfredScriptRunner.run(AlfredScript(language: 7, source: translated), query: "", arguments: [], workflow: workflow, variables: [:])
        #expect(result.text.trimmingCharacters(in: .whitespacesAndNewlines) == "oui")
        #expect(AlfredBridge.orders(in: source).translated == ["running"])
    }

    /// F2 : sans workflow, aucun fichier `.json` sans nom n'est écrit.
    @Test func keptSettingsNeedAWorkflow() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-093-\(UUID().uuidString)")
        let store = AlfredKeptSettings(folder: folder)
        #expect(throws: AlfredKeptSettings.MissingWorkflow.self) { try store.set("k", to: "v", workflow: "") }
        #expect(throws: AlfredKeptSettings.MissingWorkflow.self) { try store.remove("k", workflow: "") }
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(".json").path))
    }

    // MARK: Réglages gardés

    @Test func keptSettingsOverridePrefs() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-093-\(UUID().uuidString)")
        let store = AlfredKeptSettings(folder: folder)
        try store.set("vault", to: "/v", workflow: "test.roadie.essai")
        try store.set("other", to: "1", workflow: "test.roadie.essai")
        try store.remove("other", workflow: "test.roadie.essai")
        #expect(store.values(for: "test.roadie.essai") == ["vault": "/v"])
        var fixture = WorkflowFixture()
        fixture.prefs = ["vault": "/ancien", "theme": "dark"]
        let workflow = try fixture.write()
        let merged = AlfredWorkflow.load(folder: workflow.folder, source: .roadie, kept: store)
        #expect(merged?.configuredVariables["vault"] == "/v" && merged?.configuredVariables["theme"] == "dark")
    }
}
