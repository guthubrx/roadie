import Foundation
import RoadieCore
import Testing
@testable import RoadieDaemon

/// Spec 168 — Saut direct dans les dialogues « Ouvrir / Enregistrer sous » (`file_dialog_jump`).
@Suite(.serialized)
struct Spec168FileDialogJumpTests {
    private func tempDir(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-spec168-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func configDefaultAndTomlToggleWork() throws {
        let defaults = RoadieConfig()
        #expect(defaults.experimental.targetMode.fileDialogJump)

        let dir = try tempDir("config")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("roadies.toml")
        try """
        [launcher]
        file_dialog_jump = false
        """.write(to: file, atomically: true, encoding: .utf8)

        let loaded = try RoadieConfigLoader.load(from: file.path)
        #expect(!loaded.experimental.targetMode.fileDialogJump)
        let validation = RoadieConfigLoader.validate(path: file.path)
        #expect(!validation.hasErrors)
    }

    @Test func classifiesOpenAndSaveDialogsAccurately() {
        #expect(FileDialogJumpService.classify(
            role: "AXSheet", subrole: nil, identifier: "save-panel", title: "Enregistrer",
            hasFileBrowser: true, hasSaveField: true
        ) == .save)

        #expect(FileDialogJumpService.classify(
            role: "AXSheet", subrole: nil, identifier: "open-panel", title: "Open",
            hasFileBrowser: true, hasSaveField: false
        ) == .open)

        #expect(FileDialogJumpService.classify(
            role: "AXWindow", subrole: "AXDialog", identifier: nil, title: "Enregistrer sous",
            hasFileBrowser: true, hasSaveField: false
        ) == .save)

        // Feuille Save As sandboxée (TextEdit XPC : pas de titre, boutons Save + Cancel)
        #expect(FileDialogJumpService.classify(
            role: "AXSheet", subrole: nil, identifier: nil, title: "",
            hasFileBrowser: false, hasSaveField: false, hasDialogButtons: true, hasSaveButton: true
        ) == .save)

        // Une fenêtre applicative normale n'est jamais classée comme dialogue fichier
        #expect(FileDialogJumpService.classify(
            role: "AXWindow", subrole: "AXStandardWindow", identifier: nil, title: "Open Issues - GitHub",
            hasFileBrowser: false, hasSaveField: false
        ) == nil)
    }

    @Test func standardFavoriteFoldersAndBilingualSearchMatchDesktop() throws {
        let fakeHome = try tempDir("fake-home")
        defer { try? FileManager.default.removeItem(at: fakeHome) }
        for name in ["Desktop", "Downloads", "Documents", "Nextcloud"] {
            try FileManager.default.createDirectory(at: fakeHome.appendingPathComponent(name), withIntermediateDirectories: true)
        }

        let favorites = FileDialogJumpService.standardFavoriteFolders(homeDirectory: fakeHome.path)
        let titles = favorites.map(\.title)
        #expect(titles.contains("Desktop"))
        #expect(titles.contains("Downloads"))
        #expect(titles.contains("Documents"))

        let entries = FileDialogJumpService.suggestedFolderEntries(
            stageFolders: [],
            recentFolders: [],
            favoriteFolders: favorites,
            limit: 10
        )
        #expect(entries.first?.title == "Desktop")

        let matchEN = FileDialogJumpService.matchingFolders(query: "desktop", in: entries)
        #expect(matchEN.first?.title == "Desktop")
        let matchFR = FileDialogJumpService.matchingFolders(query: "bureau", in: entries)
        #expect(matchFR.first?.title == "Desktop")
        let matchDL = FileDialogJumpService.matchingFolders(query: "telecharg", in: entries)
        #expect(matchDL.first?.title == "Downloads")
    }

    @Test func resolvesFolderAndFileParentAndDeduplicatesSuggestions() throws {
        let dir = try tempDir("paths")
        defer { try? FileManager.default.removeItem(at: dir) }
        let sub = dir.appendingPathComponent("Contrats", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let pdf = sub.appendingPathComponent("devis.pdf")
        try Data("pdf".utf8).write(to: pdf)

        #expect(FileDialogJumpService.resolveTargetFolder(for: sub.path) == sub.path)
        #expect(FileDialogJumpService.resolveTargetFolder(for: pdf.path) == sub.path)
        #expect(FileDialogJumpService.resolveTargetFolder(for: "/nonexistent/roadie/168/path") == nil)

        let suggestions = FileDialogJumpService.suggestedFolders(
            stageFolders: [sub.path, dir.path],
            recentFolders: [sub.path, "/nonexistent/roadie/168", dir.path],
            limit: 5
        )
        #expect(suggestions == [sub.path, dir.path])
    }

    @Test func fileVerbsPrioritizeUseInFileDialogOnlyWhenActive() {
        let folder = LauncherFile(path: "/tmp", name: "tmp", isFolder: true, lastUsed: nil)
        let inactiveVerbs = LauncherVerb.verbs(for: .file(folder), fileDialogActive: false)
        #expect(!inactiveVerbs.contains(.useInFileDialog))
        #expect(inactiveVerbs.first == .open)

        let activeVerbs = LauncherVerb.verbs(for: .file(folder), fileDialogActive: true)
        #expect(activeVerbs.first == .useInFileDialog)
        #expect(activeVerbs.contains(.open))
    }

    @Test func fileDialogDescriptorExistsInSettingsCatalog() throws {
        let desc = try #require(SettingsCatalog.find(id: "target_mode.file_dialog_jump"))
        #expect(desc.kind == .bool)
        #expect(desc.defaultValue == .bool(true))
    }
}
