import AppKit
import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

/// Session 099 : présentation des résultats en liste, grille ou grandes tuiles.
struct Spec099ViewModeTests {
    @Test func modesCycleWithSymbolsAndColumns() {
        #expect(LauncherViewMode.list.next == .grid && LauncherViewMode.grid.next == .large && LauncherViewMode.large.next == .list)
        #expect(LauncherViewMode.allCases.map(\.symbol) == ["☰", "▦", "▣"])
        #expect(LauncherViewMode.list.columns == nil && LauncherViewMode.grid.columns == 7 && LauncherViewMode.large.columns == 4)
    }

    @Test func bookRemembersPerSourceAndStaysBounded() {
        var book = LauncherViewBook()
        let emoji = LauncherViewSource.workflow("wf:a:sf", itemsAreFiles: false)
        let pictures = LauncherViewSource.folder("/Users/x/Pictures")
        #expect(book.mode(for: emoji) == .list && book.mode(for: nil) == .list)
        book.set(.grid, for: emoji)
        book.set(.large, for: pictures)
        #expect(book.mode(for: emoji) == .grid && book.mode(for: pictures) == .large)
        #expect(book.mode(for: .folder("/Users/x/Documents")) == .list)
        // 500 sources au plus : la plus ancienne part.
        let start = Date(timeIntervalSince1970: 0)
        var bounded = LauncherViewBook()
        for index in 0...LauncherViewBook.maxSources {
            bounded.set(.grid, for: .folder("/d\(index)"), at: start.addingTimeInterval(Double(index)))
        }
        #expect(bounded.choices.count == LauncherViewBook.maxSources)
        #expect(bounded.mode(for: .folder("/d0")) == .list && bounded.mode(for: .folder("/d500")) == .grid)
    }

    @Test func storeRoundTrips() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-099-\(UUID().uuidString)/views.json")
        let store = LauncherViewStore(url: url)
        var book = store.load()
        #expect(book.choices.isEmpty)
        book.set(.large, for: .files)
        store.save(book)
        #expect(store.load().mode(for: .files) == .large)
    }

    @Test func gridRowsDropHeadersAndKeepFilesForTheSearch() {
        let file = LauncherFile(path: "/tmp/a.png", name: "a.png", isFolder: false, lastUsed: nil)
        let calc = LauncherList.Row.calc(LauncherCalculator.evaluate("1+1")!)
        let rows: [LauncherList.Row] = [.header("Calcul"), calc, .header("Fichiers"), .file(file)]
        #expect(LauncherViewSource.files.gridRows(rows) == [.file(file)])
        #expect(LauncherViewSource.folder("/tmp").gridRows(rows) == [calc, .file(file)])
        #expect(LauncherViewSource.workflow("x", itemsAreFiles: false).namesInFooter)
        #expect(!LauncherViewSource.folder("/tmp").namesInFooter)
    }

    @MainActor @Test func cycleKeyIsResolvedAndRecognised() throws {
        let layout: [UInt32: String] = [5: "g", 4: "h"]
        let cycle = try #require(SearchInputPanel.cycleKey("command+g", layout: layout))
        #expect(cycle.keyCode == 5 && cycle.flags == .command)
        #expect(SearchInputPanel.cycleKey("", layout: layout) == nil)
        #expect(SearchInputPanel.cycleKey("command+alt+h", layout: layout)?.flags == [.command, .option])
        func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                                          context: nil, characters: "g", charactersIgnoringModifiers: "g", isARepeat: false, keyCode: code))
        }
        #expect(SearchInputPanel.navigation(try key(5, .command), viewCycle: cycle)?.kind == .cycleView)
        // Sans ⌘, la lettre s'écrit ; sans touche réglée, ⌘G n'a pas de rôle.
        #expect(SearchInputPanel.navigation(try key(5, []), viewCycle: cycle) == nil)
        #expect(SearchInputPanel.navigation(try key(5, .command)) == nil)
    }

    @Test func settingDefaultsToCommandG() throws {
        #expect(TargetModeConfig().viewCycleHotkey == "command+g")
        #expect(TargetModeConfig(viewCycleHotkey: "").viewCycleHotkey == "")
        #expect(SettingsCatalog.all.contains { $0.key == "view_cycle_hotkey" && $0.tablePath == "experimental.target_mode" })
    }

    @Test func thumbnailsAreReduced() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-099-\(UUID().uuidString).png")
        let image = NSImage(size: NSSize(width: 2000, height: 1000))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 2000, height: 1000).fill()
        image.unlockFocus()
        let rep = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        let thumbnail = try #require(SearchBarRenderer.thumbnailImage(url.path))
        #expect(max(thumbnail.size.width, thumbnail.size.height) <= 512)
        #expect(AlfredGridView.isImage(url.path) && !AlfredGridView.isImage("/tmp/notes.txt"))
    }
}
