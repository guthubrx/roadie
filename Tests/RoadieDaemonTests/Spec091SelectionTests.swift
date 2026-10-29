import AppKit
import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

@MainActor
struct Spec091SelectionTests {
    private func window(_ id: Int, _ title: String) -> LauncherSubject {
        .target(RoadieTarget(id: "window:\(id)", kind: .window, title: title, source: .roadie,
                             scope: TargetScopeSnapshot(displayId: "A", desktopId: 1, stageId: "1", windowId: UInt32(id)), actions: [.focus]))
    }
    private let app = LauncherSubject.app(LauncherApp(bundleID: "org.mozilla.firefox", path: "/Applications/Firefox.app", name: "Firefox", alternateNames: []))
    private let file = LauncherSubject.file(LauncherFile(path: "/tmp/a.txt", name: "a.txt", isFolder: false, lastUsed: nil))

    @Test func toggleAddRemoveAndClear() {
        var selection = LauncherSelection()
        let added = selection.toggle(window(1, "Firefox"))
        #expect(added)
        selection.add(window(2, "iTerm2"))
        selection.add(window(2, "iTerm2"))
        selection.add(app)
        #expect(selection.count == 3)
        let removed = !selection.toggle(window(1, "Firefox"))
        #expect(removed && selection.count == 2)
        // Une stage ne se sélectionne pas.
        let stage = LauncherSubject.target(RoadieTarget(id: "stage:1", kind: .stage, title: "Dev", source: .roadie, actions: [.switch]))
        let stageAdded = selection.toggle(stage)
        #expect(!stageAdded && selection.count == 2)
        selection.removeLast()
        #expect(selection.subjects == [window(2, "iTerm2")])
        selection.clear()
        #expect(selection.isEmpty)
    }

    @Test func batchVerbsCountsAndActions() throws {
        var selection = LauncherSelection()
        for subject in [window(1, "Firefox"), window(2, "iTerm2"), app, file] { selection.add(subject) }
        #expect(selection.applicable(.sendTo).count == 4 && selection.applicable(.close).count == 2)
        #expect(selection.applicable(.quit).count == 1 && selection.applicable(.copyPath).count == 1)
        let list = LauncherActionList.batch(selection, query: "")
        #expect(list.rows.compactMap(\.id) == ["verb:sendTo", "verb:bringHere", "verb:close", "verb:minimize", "verb:quit", "verb:hide",
                                               "verb:copyPath", "verb:reveal", "verb:copyFile", "verb:copyTo", "verb:moveFileTo",
                                               "verb:copyReplace", "verb:moveReplace", "verb:openWith", "verb:email", "verb:trash",
                                               "verb:makeAlias", "verb:addTag"])
        #expect(LauncherActionList.batch(selection, query: "ferm").rows.compactMap(\.id) == ["verb:close"])
        #expect(LauncherSelection.title(.close, count: 2) == "Fermer les fenêtres (2)")
        let display = DisplayID(rawValue: "A")
        let fresh = LauncherDestination(kind: .newStage(name: "Dev", display, DesktopID(rawValue: 1)), title: "Nouvelle stage « Dev »", detail: "")
        let actions = selection.actions(.sendTo, destination: fresh)
        #expect(actions.map(\.verb) == [.sendTo, .sendTo, .openIn, .openIn])
        // Vers un bureau : les fenêtres seulement.
        let desktop = LauncherDestination(kind: .desktop(display, DesktopID(rawValue: 2)), title: "Bureau 2", detail: "")
        #expect(selection.actions(.sendTo, destination: desktop).count == 2)
        #expect(LauncherActionList.batchDestinationVerb(selection) == .sendTo)
        var appsOnly = LauncherSelection()
        appsOnly.add(app)
        #expect(LauncherActionList.batchDestinationVerb(appsOnly) == .openIn)
    }

    @Test func optionKeysDriveTheSelection() throws {
        func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = .option) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                                          context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
        }
        let active = SelectionKeys(hasSelection: true, rowSelectable: true)
        #expect(SearchInputPanel.navigation(try key(126), selection: active)?.kind == .selectToggle)
        #expect(SearchInputPanel.navigation(try key(125), selection: active)?.kind == .selectAddNext)
        #expect(SearchInputPanel.navigation(try key(123), selection: active)?.kind == .selectRemoveLast)
        #expect(SearchInputPanel.navigation(try key(124), selection: active)?.kind == .selectionVerbs)
        #expect(SearchInputPanel.navigation(try key(51), selection: active)?.kind == .selectClear)
        // Calcul ou chemin, sans sélection : ⌥ + flèches et ⌥⌫ restent au champ (mot par mot).
        for code: UInt16 in [126, 125, 123, 124, 51] {
            #expect(SearchInputPanel.navigation(try key(code), text: "=sqrt(2)+3") == nil)
        }
        // Ligne qui se choisit, sans sélection : ⌥↓ ajoute, ⌥← et ⌥→ déplacent le curseur.
        let row = SelectionKeys(hasSelection: false, rowSelectable: true)
        #expect(SearchInputPanel.navigation(try key(125), selection: row)?.kind == .selectAddNext)
        #expect(SearchInputPanel.navigation(try key(123), selection: row) == nil)
        #expect(SearchInputPanel.navigation(try key(124), selection: row) == nil)
        // Sans ⌥ : les flèches gardent leur rôle.
        #expect(SearchInputPanel.navigation(try key(125, []))?.kind == .next)
        #expect(SearchInputPanel.navigation(try key(123, [])) == nil)
    }

    @Test func aBatchUndoesTogether() {
        let a = StageScope(displayID: DisplayID(rawValue: "A"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let b = StageScope(displayID: DisplayID(rawValue: "A"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "2"))
        let now = Date()
        var book = LauncherMemoryBook()
        book.record(WindowMove(windowID: WindowID(rawValue: 9), bundleID: "x", appName: "X", from: b, to: a, at: now.addingTimeInterval(-60)))
        for id in [1, 2, 3] {
            book.record(WindowMove(windowID: WindowID(rawValue: UInt32(id)), bundleID: "b\(id)", appName: "A\(id)", from: a, to: b, at: now))
        }
        book.mark(batch: "lot", windows: [WindowID(rawValue: 1), WindowID(rawValue: 2), WindowID(rawValue: 3)], since: now)
        let scopes: [UInt32: StageScope] = [1: b, 2: b, 3: b, 9: a]
        let moves = book.undoableBatch(at: now, currentScope: { scopes[$0.rawValue] })
        #expect(moves.map(\.windowID.rawValue) == [1, 2, 3])
        // Une fenêtre déjà repartie ailleurs n'est plus remise.
        #expect(book.undoableBatch(at: now, currentScope: { $0.rawValue == 2 ? a : scopes[$0.rawValue] }).count == 2)
        // Sans lot : le dernier déplacement seul, comme avant (081).
        var single = LauncherMemoryBook()
        single.record(WindowMove(windowID: WindowID(rawValue: 9), bundleID: "x", appName: "X", from: b, to: a, at: now))
        #expect(single.undoableBatch(at: now, currentScope: { _ in a }).count == 1)
    }
}
