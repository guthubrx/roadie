import Foundation
import Testing
@testable import RoadieDaemon

/// Reproductions de l'audit V15 du 29 octobre 2026 (copie de laboratoire, jamais commitée).
struct Audit129ReproTests {
    /// F-RUNSCRIPT : une action Run Script qui dure plus de 10 s est arrêtée, sa suite ne s'exécute pas.
    @Test func runScriptLongerThanTenSecondsIsStopped() async throws {
        var fixture = WorkflowFixture()
        fixture.add("K", "input.keyword", ["keyword": "k"])
        fixture.add("LONG", "action.script", ["type": 0, "scriptargtype": 1, "script": "sleep 11; printf fini"])
        fixture.add("CB", "output.clipboard", ["clipboardtext": "{query}"])
        fixture.link("K", "LONG")
        fixture.link("LONG", "CB")
        let workflow = try fixture.write()
        let effects = RecordedEffects()
        let started = Date()
        let outcome = await AlfredWorkflowEngine(effects: effects).run(workflow, from: "K", arg: ["x"])
        let elapsed = Date().timeIntervalSince(started)
        print("AUDIT129 runscript elapsed=\(elapsed) calls=\(effects.calls) errors=\(outcome.errors)")
        #expect(!effects.calls.contains("copy:fini"))
        #expect(outcome.errors.contains("timeout"))
    }

    /// Témoin : la même chaîne avec un script court aboutit.
    @Test func shortRunScriptCompletes() async throws {
        var fixture = WorkflowFixture()
        fixture.add("K", "input.keyword", ["keyword": "k"])
        fixture.add("SHORT", "action.script", ["type": 0, "scriptargtype": 1, "script": "sleep 1; printf fini"])
        fixture.add("CB", "output.clipboard", ["clipboardtext": "{query}"])
        fixture.link("K", "SHORT")
        fixture.link("SHORT", "CB")
        let workflow = try fixture.write()
        let effects = RecordedEffects()
        _ = await AlfredWorkflowEngine(effects: effects).run(workflow, from: "K", arg: ["x"])
        print("AUDIT129 short calls=\(effects.calls)")
        #expect(effects.calls.contains("copy:fini"))
    }

    /// F-SPOTLIGHT : le lanceur d'AppleScript de la barre arrête le script au délai donné, même si le
    /// script aurait abouti ensuite (ici 12 s pour un délai de 10 s, valeur de `LauncherSystemCommand.script`).
    @Test func appleScriptRunnerStopsAtTimeout() async {
        let started = Date()
        let output = await LauncherBrowsers.run("delay 12\nreturn \"fini\"", timeout: 10)
        let elapsed = Date().timeIntervalSince(started)
        print("AUDIT129 osascript elapsed=\(elapsed) output=\(output ?? "nil")")
        #expect(output == nil)
        #expect(elapsed < 11.5)
    }
}

/// Test différentiel de l'audit : `literalIndex` + `literal(in:)` doit rendre exactement `readLiteral`
/// sur des fichiers TOML générés (graine fixe, 3 000 fichiers, 25 sondes chacun).
struct Audit129LiteralIndexDifferentialTests {
    private struct Rng { var state: UInt64; mutating func next() -> UInt64 { state &+= 0x9E37_79B9_7F4A_7C15; var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9; z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB; return z ^ (z >> 31) }
        mutating func pick<T>(_ items: [T]) -> T { items[Int(next() % UInt64(items.count))] } }

    @Test func indexMatchesReadLiteralOnGeneratedFiles() {
        let lines = ["[a]", "[b]", "[a.sub]", "[[arr]]", "[ a ]", "[a] # c", "x = 1", "y = \"t # n\"", "dup = 2", "dup = 3",
                     "sub.k = 4", "k = 'q'", "x = [", "  1,", "]", "x = { p = 1 }", "y = \"\"\"", "z", "\"\"\"", "# rien", "",
                     "x = 5 # fin", "\"x\" = 6", "y =", "k = \"ouvert", "x=7", "  y = 8  ", "a.x = 9", "k = \"\\\"\""]
        let tables = ["", "a", "b", "a.sub", "arr"], keys = ["x", "y", "dup", "sub", "k"]
        var rng = Rng(state: 129)
        var mismatches: [String] = []
        for _ in 0..<3_000 {
            let text = (0..<Int(rng.next() % 14 + 1)).map { _ in rng.pick(lines) }.joined(separator: "\n")
            let index = ConfigFileEditor.literalIndex(text)
            for table in tables { for key in keys {
                let fast = ConfigFileEditor.literal(in: index, table: table, key: key)
                let slow = ConfigFileEditor.readLiteral(text, table: table, key: key)
                if fast != slow, mismatches.count < 8 {
                    mismatches.append("[\(table)].\(key) index=\(fast ?? "nil") read=\(slow ?? "nil") <<<\(text.replacingOccurrences(of: "\n", with: "⏎"))>>>")
                }
            } }
        }
        print("AUDIT129 literal mismatches=\(mismatches.count)")
        mismatches.forEach { print("AUDIT129 " + $0) }
        #expect(mismatches.isEmpty)
    }
}

/// Même générateur sans la ligne de valeur vide `y =` : aucun autre écart attendu si la cause est unique.
struct Audit129LiteralIndexWithoutEmptyValueTests {
    @Test func noOtherMismatch() {
        let lines = ["[a]", "[b]", "[a.sub]", "[[arr]]", "[ a ]", "[a] # c", "x = 1", "y = \"t # n\"", "dup = 2", "dup = 3",
                     "sub.k = 4", "k = 'q'", "x = [", "  1,", "]", "x = { p = 1 }", "y = \"\"\"", "z", "\"\"\"", "# rien", "",
                     "x = 5 # fin", "\"x\" = 6", "k = \"ouvert", "x=7", "  y = 8  ", "a.x = 9", "k = \"\\\"\"", "y = # vide"]
        let tables = ["", "a", "b", "a.sub", "arr"], keys = ["x", "y", "dup", "sub", "k"]
        var state: UInt64 = 129
        func next() -> UInt64 { state &+= 0x9E37_79B9_7F4A_7C15; var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9; z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB; return z ^ (z >> 31) }
        var total = 0, withComment = 0, other: [String] = []
        for _ in 0..<5_000 {
            let text = (0..<Int(next() % 14 + 1)).map { _ in lines[Int(next() % UInt64(lines.count))] }.joined(separator: "\n")
            let index = ConfigFileEditor.literalIndex(text)
            for table in tables { for key in keys where ConfigFileEditor.literal(in: index, table: table, key: key)
                    != ConfigFileEditor.readLiteral(text, table: table, key: key) {
                total += 1
                if text.contains("y = # vide") { withComment += 1 } else if other.count < 5 { other.append("[\(table)].\(key) <<<\(text.replacingOccurrences(of: "\n", with: "⏎"))>>>") }
            } }
        }
        print("AUDIT129 noempty total=\(total) withCommentOnlyValue=\(withComment) other=\(other.count)")
        other.forEach { print("AUDIT129 other " + $0) }
        #expect(other.isEmpty)
    }
}
