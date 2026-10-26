import Foundation
import Testing
@testable import RoadieDaemon

struct Spec087PathTests {
    private let commands = LauncherPathRules.commandNames
    private let root = ["Applications", "Library", "System", "Users", "Volumes", "bin", "dev", "opt", "sbin", "tmp", "usr"]

    @Test func slashIsACommandUnlessItNamesAFolder() {
        #expect(LauncherPathRules.isPath("/Us", commands: commands, rootEntries: root))
        #expect(LauncherPathRules.isPath("/App", commands: commands, rootEntries: root))
        #expect(LauncherPathRules.isPath("/tmp", commands: commands, rootEntries: root))
        #expect(LauncherPathRules.isPath("/Users/", commands: commands, rootEntries: root))
        #expect(LauncherPathRules.isPath("/s/x", commands: commands, rootEntries: root))
        // Commandes : le début d'une commande ou d'un alias garde la priorité.
        for command in ["/", "/s", "/set", "/settings", "/d", "/desktop", "/b", "/bm", "/l", "/letters", "/zz"] {
            #expect(!LauncherPathRules.isPath(command, commands: commands, rootEntries: root), "\(command)")
        }
        #expect(LauncherPathRules.isPath("~", commands: commands, rootEntries: root))
        #expect(LauncherPathRules.isPath("~/Doc", commands: commands, rootEntries: root))
        #expect(!LauncherPathRules.isPath("~moi", commands: commands, rootEntries: root))
        #expect(!LauncherPathRules.isPath("fire", commands: commands, rootEntries: root))
    }

    @Test func partsAndCompletion() {
        let home = "/Users/x"
        let doc = LauncherPathRules.parts("~/Doc", home: home)
        #expect(doc == LauncherPathQuery(directory: "/Users/x", prefix: "Doc", typedBase: "~/"))
        #expect(LauncherPathRules.parts("~", home: home) == LauncherPathQuery(directory: "/Users/x", prefix: "", typedBase: "~/"))
        #expect(LauncherPathRules.parts("/Us", home: home) == LauncherPathQuery(directory: "/", prefix: "Us", typedBase: "/"))
        #expect(LauncherPathRules.parts("/Users/x/", home: home) == LauncherPathQuery(directory: "/Users/x", prefix: "", typedBase: "/Users/x/"))
        let folder = LauncherFile(path: "/Users/x/Documents", name: "Documents", isFolder: true, lastUsed: nil)
        #expect(LauncherPathRules.completion(folder, in: doc) == "~/Documents/")
        let file = LauncherFile(path: "/Users/x/Doc.txt", name: "Doc.txt", isFolder: false, lastUsed: nil)
        #expect(LauncherPathRules.completion(file, in: doc) == "~/Doc.txt")
    }

    @Test func listingFiltersSortsAndHides() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-087-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Docker"), withIntermediateDirectories: true)
        for name in ["doc.txt", ".docrc", "zz.txt"] { try Data().write(to: dir.appendingPathComponent(name)) }
        defer { try? FileManager.default.removeItem(at: dir) }
        let names = LauncherPathListing.read(dir.path)
        let query = LauncherPathRules.parts(dir.path + "/doc", home: "/none")
        let found = LauncherPathRules.filter(names, query: query).map(\.name)
        // Nom exact d'abord (doc.txt n'est pas exact : « doc » ≠ « doc.txt »), puis dossiers avant fichiers.
        #expect(found.contains("Documents") && found.contains("Docker") && found.contains("doc.txt"))
        #expect(!found.contains(".docrc") && !found.contains("zz.txt"))
        #expect(found.firstIndex(of: "Docker")! < found.firstIndex(of: "doc.txt")!)
        let hidden = LauncherPathRules.filter(names, query: LauncherPathRules.parts(dir.path + "/.d", home: "/none")).map(\.name)
        #expect(hidden == [".docrc"])
        let all = LauncherPathRules.filter(names, query: LauncherPathRules.parts(dir.path + "/", home: "/none")).map(\.name)
        #expect(all == ["Docker", "Documents", "doc.txt", "zz.txt"])
        let exact = LauncherPathRules.filter(names, query: LauncherPathRules.parts(dir.path + "/zz.txt", home: "/none")).map(\.name)
        #expect(exact.first == "zz.txt")
    }

    @Test func pathListAndCalculationRow() throws {
        let file = LauncherFile(path: "/Users/x/Documents", name: "Documents", isFolder: true, lastUsed: nil)
        let list = LauncherList.path([file])
        #expect(list.rows == [.header("Chemin"), .file(file)])
        #expect(list.best == file.rankingKey)
        #expect(LauncherList.path([]).rows.isEmpty)
        var search = LauncherList.idle([.header("Fenêtres")])
        let calc = try #require(LauncherCalculator.evaluate("2+2", locale: Locale(identifier: "fr_FR")))
        search.prepend(.calc(calc), header: "Calcul")
        #expect(search.best == "calc")
        #expect(search.rows.prefix(2) == [.header("Calcul"), .calc(calc)])
    }
}
