import CoreGraphics
import Foundation
import Testing
@testable import RoadieDaemon

/// Session 131 : menus de l'application active, commandes ajoutées à la barre, tâches téléchargées à la demande.
struct Spec131BarCommandsTests {
    @Test func menuQueryAndMatching() {
        #expect(LauncherMenuSearch.query("menu export") == "export")
        #expect(LauncherMenuSearch.query("Menus") == "")
        #expect(LauncherMenuSearch.query("menuiserie") == nil)
        let entries = [LauncherMenuSearch.Entry(path: ["Fichier", "Exporter…"], shortcut: "⇧⌘E", enabled: true),
                       LauncherMenuSearch.Entry(path: ["Fichier", "Exporter en PDF…"], shortcut: "", enabled: false),
                       LauncherMenuSearch.Entry(path: ["Format", "Police", "Gras"], shortcut: "⌘B", enabled: true),
                       LauncherMenuSearch.Entry(path: ["Fichier", "Imprimer…"], shortcut: "⌘P", enabled: true)]
        #expect(LauncherMenuSearch.matches("expo", in: entries).map(\.entry.title) == ["Exporter…"])
        // Le chemin compte aussi : « police » trouve Gras dans Format › Police.
        #expect(LauncherMenuSearch.matches("police", in: entries).map(\.index) == [2])
        #expect(LauncherMenuSearch.matches("", in: entries).count == 3)
        #expect(LauncherMenuSearch.menuShortcut(key: "E", modifiers: 1) == "⇧⌘E")
        #expect(LauncherMenuSearch.menuShortcut(key: "F", modifiers: 2 | 4) == "⌃⌥⌘F")
        #expect(LauncherMenuSearch.menuShortcut(key: "X", modifiers: 8) == "X")
    }

    @Test func newSystemCommands() {
        let ids = Set(LauncherSystemCommand.all().map(\.id))
        for id in ["dark-mode", "screenshot-screen", "screenshot-area", "screenshot-window"] { #expect(ids.contains(id), "\(id)") }
        #expect(LauncherSystemCommand.matches("capture", in: LauncherSystemCommand.all(), limit: 5).count == 3)
        #expect(LauncherSystemCommand.matches("dark", in: LauncherSystemCommand.all()).first?.id == "dark-mode")
        #expect(LauncherSystemCommand.screenshotArguments("screenshot-area") == ["-i"])
        #expect(LauncherSystemCommand.screenshotArguments("screenshot-window") == ["-iW"])
        #expect(LauncherSystemCommand.screenshotArguments("screenshot-screen") == ["-m"])
        let date = Date(timeIntervalSince1970: 1_793_000_000)
        let path = LauncherSystemCommand.screenshotPath(now: date, location: "~/Captures", home: "/Users/x")
        #expect(path.hasPrefix(NSString(string: "~/Captures").expandingTildeInPath + "/Capture d'écran ") && path.hasSuffix(".png"))
        #expect(LauncherSystemCommand.screenshotPath(now: date, location: nil, home: "/Users/x").hasPrefix("/Users/x/Desktop/"))
        #expect(LauncherAppleShortcuts.parse("Météo\n  Minuteur  \n\nMétéo\n") == ["Météo", "Minuteur"])
    }

    @Test func missingTaskIsDownloadedOnceThenRuns() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("spec131-tasks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        var fixture = WorkflowFixture()
        fixture.add("K", "input.keyword", ["keyword": "k"])
        fixture.add("T", "automation.task", ["taskuid": "test.core/nouvelle"])
        fixture.add("CB", "output.clipboard", ["clipboardtext": "{query}"])
        fixture.link("K", "T")
        fixture.link("T", "CB")
        let workflow = try fixture.write()
        let effects = RecordedEffects()
        var engine = AlfredWorkflowEngine(effects: effects)
        engine.tasksRoot = root
        let calls = Counter()
        engine.updateTasks = { root in
            calls.increment()
            let folder = root.appendingPathComponent("Tasks/test.core/nouvelle")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let task: [String: Any] = ["taskName": "Nouvelle", "scriptType": 0, "script": "printf telechargee"]
            try JSONSerialization.data(withJSONObject: task).write(to: folder.appendingPathComponent("alfredtask.json"))
            return 1
        }
        let outcome = await engine.run(workflow, from: "K", arg: [""])
        #expect(calls.value == 1 && effects.calls.contains("copy:telechargee") && outcome.missing.isEmpty)
        // Une seconde absence dans le même dossier ne relance pas de téléchargement.
        try FileManager.default.removeItem(at: root)
        _ = await engine.run(workflow, from: "K", arg: [""])
        #expect(calls.value == 1)
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }
}

/// Essai du 29 octobre 2026 : le trackpad fait défiler la liste et la grille de la barre.
struct Spec131ScrollTests {
    @Test func scrollDeltasBecomeSelectionSteps() {
        #expect(LauncherScroll.steps(accumulated: 0, delta: 10) == (0, 10))
        #expect(LauncherScroll.steps(accumulated: 10, delta: 15).steps == 1)
        #expect(LauncherScroll.steps(accumulated: 0, delta: -50).steps == -2)
        let (steps, rest) = LauncherScroll.steps(accumulated: 0, delta: -50)
        #expect(abs(rest - (-50 + 2 * LauncherScroll.step)) < 0.001 && steps == -2)
        #expect(TargetSearchDismissal.eventMask(search: true) & CGEventMask(1 << CGEventType.scrollWheel.rawValue) != 0)
        #expect(TargetSearchDismissal.eventMask(search: false) & CGEventMask(1 << CGEventType.scrollWheel.rawValue) == 0)
    }
}
