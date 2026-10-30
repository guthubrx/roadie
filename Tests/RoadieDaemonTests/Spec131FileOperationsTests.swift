import Foundation
import Testing
@testable import RoadieDaemon

/// Session 131 : verbes de fichier d'Alfred (copier, déplacer, remplacer, corbeille, alias, informations,
/// étiquettes), sur des dossiers temporaires et une corbeille simulée.
struct Spec131FileOperationsTests {
    private final class FakeTrash: @unchecked Sendable {
        let folder: URL
        private(set) var items: [String] = []
        init(_ folder: URL) { self.folder = folder }
        func trash(_ url: URL) throws {
            items.append(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: folder.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent))
        }
    }

    private func sandbox() throws -> (root: URL, source: URL, target: URL, trash: FakeTrash) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("spec131-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let target = root.appendingPathComponent("target", isDirectory: true)
        let trash = root.appendingPathComponent("trash", isDirectory: true)
        for folder in [source, target, trash] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        return (root, source, target, FakeTrash(trash))
    }

    private func write(_ text: String, _ url: URL) throws { try text.write(to: url, atomically: true, encoding: .utf8) }
    private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    @Test func copyAndMoveRefuseExistingNamesUnlessReplacing() throws {
        let box = try sandbox()
        defer { try? FileManager.default.removeItem(at: box.root) }
        let a = box.source.appendingPathComponent("a.txt"), b = box.source.appendingPathComponent("b.txt")
        try write("A", a)
        try write("B", b)
        try write("ancien", box.target.appendingPathComponent("a.txt"))
        let trash: LauncherFileOperations.Trasher = { try box.trash.trash($0) }

        let copy = LauncherFileOperations.transfer([a.path, b.path], to: box.target.path, move: false, replace: false, trash: trash)
        #expect(copy.done == [box.target.appendingPathComponent("b.txt").path])
        #expect(copy.failures[a.path] != nil)
        #expect(read(box.target.appendingPathComponent("a.txt")) == "ancien")
        #expect(box.trash.items.isEmpty)

        let replace = LauncherFileOperations.transfer([a.path], to: box.target.path, move: true, replace: true, trash: trash)
        #expect(replace.succeeded)
        #expect(read(box.target.appendingPathComponent("a.txt")) == "A")
        #expect(!FileManager.default.fileExists(atPath: a.path))
        #expect(box.trash.items == ["a.txt"])
        #expect(FileManager.default.fileExists(atPath: b.path))
    }

    @Test func transferRefusesMissingFolderSameFolderAndFolderIntoItself() throws {
        let box = try sandbox()
        defer { try? FileManager.default.removeItem(at: box.root) }
        let a = box.source.appendingPathComponent("a.txt")
        try write("A", a)
        #expect(LauncherFileOperations.transfer([a.path], to: box.root.appendingPathComponent("absent").path, move: true, replace: false).failures.count == 1)
        #expect(LauncherFileOperations.transfer([a.path], to: box.source.path, move: true, replace: true).failures.count == 1)
        #expect(LauncherFileOperations.transfer([box.source.path], to: box.source.path, move: true, replace: true).failures.count == 1)
        #expect(FileManager.default.fileExists(atPath: a.path))
    }

    @Test func trashAliasAndInfo() throws {
        let box = try sandbox()
        defer { try? FileManager.default.removeItem(at: box.root) }
        let a = box.source.appendingPathComponent("a.txt"), b = box.source.appendingPathComponent("b.txt")
        try write("abc", a)
        try write("B", b)
        let report = LauncherFileOperations.trashItems([a.path, b.path], trash: { try box.trash.trash($0) })
        #expect(report.done.count == 2 && box.trash.items.sorted() == ["a.txt", "b.txt"])

        let c = box.source.appendingPathComponent("c.txt")
        try write("abc", c)
        let alias = try LauncherFileOperations.makeAlias(c.path)
        let second = try LauncherFileOperations.makeAlias(c.path)
        #expect(FileManager.default.fileExists(atPath: alias) && alias != second)
        #expect((try? URL(resolvingAliasFileAt: URL(fileURLWithPath: alias)))?.standardizedFileURL.path == c.standardizedFileURL.path)

        // Informations : la fenêtre ⌘I du Finder, une par élément ; guillemets et barres obliques inverses échappés.
        let script = LauncherFileOperations.finderInfoScript(["/tmp/a \"b\".txt", "/tmp/c\\d"])
        #expect(script.hasPrefix("tell application \"Finder\"\nactivate\n") && script.hasSuffix("\nend tell"))
        #expect(script.contains(#"open information window of (POSIX file "/tmp/a \"b\".txt" as alias)"#))
        #expect(script.contains(#"(POSIX file "/tmp/c\\d" as alias)"#))
    }

    @Test func tagsToggleLikeACheckbox() throws {
        let box = try sandbox()
        defer { try? FileManager.default.removeItem(at: box.root) }
        let a = box.source.appendingPathComponent("a.txt"), b = box.source.appendingPathComponent("b.txt")
        try write("A", a)
        try write("B", b)
        #expect(LauncherFileOperations.toggleTag("Spec131", on: [a.path]).succeeded)
        #expect(LauncherFileOperations.tags(a.path) == ["Spec131"])
        // Un seul des deux l'a : on l'ajoute aux deux ; ensuite tous l'ont : on la retire.
        #expect(LauncherFileOperations.toggleTag("Spec131", on: [a.path, b.path]).succeeded)
        #expect(LauncherFileOperations.tags(b.path) == ["Spec131"])
        _ = LauncherFileOperations.toggleTag("Spec131", on: [a.path, b.path])
        #expect(LauncherFileOperations.tags(a.path).isEmpty && LauncherFileOperations.tags(b.path).isEmpty)
        #expect(LauncherFileOperations.tagChoices(for: [a.path], finderLabels: ["None", "Rouge", "Rouge"]) == ["Rouge"])
    }

    @Test func folderDestinationsFollowTypedPathThenUsualFolders() throws {
        let box = try sandbox()
        defer { try? FileManager.default.removeItem(at: box.root) }
        let home = box.root.path
        for name in ["Desktop", "Documents", "Downloads"] {
            try FileManager.default.createDirectory(at: box.root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let destinations = LauncherFileOperations.folderDestinations(typed: box.target.path, recent: [box.source.path, box.target.path],
                                                                       excluding: [box.source.appendingPathComponent("a.txt").path], home: home)
        #expect(destinations.first?.kind == .folder(box.target.path))
        #expect(destinations.map(\.kind).contains(.folder(box.root.appendingPathComponent("Documents").path)))
        // Pas de doublon, pas le dossier de la source à déplacer.
        #expect(destinations.filter { $0.kind == .folder(box.target.path) }.count == 1)
        #expect(!destinations.map(\.kind).contains(.folder(box.source.path)))
    }

    @Test func fileVerbsAndBatch() {
        let file = LauncherFile(path: "/tmp/a.txt", name: "a.txt", isFolder: false, lastUsed: nil)
        let folder = LauncherFile(path: "/tmp", name: "tmp", isFolder: true, lastUsed: nil)
        let verbs = LauncherVerb.verbs(for: .file(file))
        for verb in [LauncherVerb.copyFile, .copyTo, .moveFileTo, .copyReplace, .moveReplace, .openWith, .email, .trash, .makeAlias, .info, .addTag] {
            #expect(verbs.contains(verb))
        }
        #expect(!verbs.contains(.browse))
        #expect(LauncherVerb.verbs(for: .file(folder)).contains(.browse) && LauncherVerb.verbs(for: .file(folder)).contains(.terminalHere))
        #expect(LauncherVerb.copyTo.needsDestination && LauncherVerb.openWith.needsDestination && LauncherVerb.addTag.needsDestination)
        #expect(!LauncherVerb.trash.needsDestination)
        var selection = LauncherSelection()
        selection.add(.file(file))
        selection.add(.file(LauncherFile(path: "/tmp/b.txt", name: "b.txt", isFolder: false, lastUsed: nil)))
        #expect(selection.applicable(.moveFileTo).count == 2 && selection.filePaths == ["/tmp/a.txt", "/tmp/b.txt"])
        #expect(LauncherActionList.batchDestinationVerb(selection, chosen: .copyTo) == .copyTo)
        let destination = LauncherDestination(kind: .folder("/tmp/x"), title: "x", detail: "")
        #expect(selection.actions(.copyTo, destination: destination).allSatisfy { $0.destination == destination })
    }
}
