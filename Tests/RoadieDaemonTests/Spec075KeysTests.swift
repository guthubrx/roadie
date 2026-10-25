import AppKit
import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

struct Spec075VariantTests {
    private let display = DisplayID(rawValue: "A")
    private var home: (DisplayID, DesktopID) { (display, DesktopID(rawValue: 2)) }
    private var active: StageScope { StageScope(displayID: display, desktopID: DesktopID(rawValue: 2), stageID: StageID(rawValue: "1")) }
    private let firefox = LauncherSubject.app(LauncherApp(bundleID: "org.mozilla.firefox", path: "/Applications/Firefox.app", name: "Firefox", alternateNames: []))

    private func window(stage: String) -> LauncherSubject {
        .target(RoadieTarget(id: "window:7", kind: .window, title: "Firefox", source: .roadie,
                             scope: TargetScopeSnapshot(displayId: "A", desktopId: 2, stageId: stage, windowId: 7), actions: [.focus]))
    }

    private func variant(_ subject: LauncherSubject, _ modifier: LauncherModifier, query: String = "fire") -> LauncherVariant? {
        LauncherVariant.of(subject, modifier: modifier, query: query, newStageHome: home, activeStage: active)
    }

    @Test func commandOpensOrSendsToANewStageOfTheShownDesktop() throws {
        let app = try #require(variant(firefox, .command))
        #expect(app.title == "⌘ ↩ Ouvrir dans une nouvelle stage")
        guard case .action(let open) = app.effect else { Issue.record("action attendue"); return }
        #expect(open.verb == .openIn && open.destination?.kind == .newStage(name: nil, display, DesktopID(rawValue: 2)) && !open.follow)
        guard case .action(let send)? = variant(window(stage: "3"), .command)?.effect else { Issue.record("action attendue"); return }
        #expect(send.verb == .sendTo && send.follow)
    }

    @Test func optionBringsHereUnlessAlreadyThere() throws {
        guard case .action(let app)? = variant(firefox, .option)?.effect else { Issue.record("action attendue"); return }
        #expect(app.verb == .bringHere && app.destination?.kind == .stage(active))
        #expect(variant(window(stage: "3"), .option) != nil)
        #expect(variant(window(stage: "1"), .option) == nil)
        #expect(LauncherVariant.of(firefox, modifier: .option, query: "", newStageHome: home, activeStage: nil) == nil)
    }

    @Test func controlSearchesTheTypedTextAndScreenTargetsKeepTheirClicks() {
        #expect(variant(firefox, .control, query: " chat noir ")?.effect == .webSearch("chat noir"))
        #expect(variant(firefox, .control, query: "  ") == nil)
        let button = LauncherSubject.target(RoadieTarget(id: "ax:1", kind: .appElement, title: "Filtrer", source: .app, actions: [.click]))
        #expect(variant(button, .command) == nil)
        #expect(variant(button, .option) == nil)
        #expect(variant(button, .control) != nil)
        let stage = LauncherSubject.target(RoadieTarget(id: "stage:2", kind: .stage, title: "Com", source: .roadie, actions: [.switch]))
        #expect(variant(stage, .command) == nil && variant(stage, .option) == nil)
    }

    @Test func webSearchEncodesTheQuery() {
        let url = LauncherWeb.searchURL("https://www.google.com/search?q={query}", query: "chat noir & co")
        #expect(url?.absoluteString == "https://www.google.com/search?q=chat%20noir%20%26%20co")
        #expect(LauncherWeb.searchURL("https://example.com", query: "x") == nil)
    }
}

struct Spec075TilingVerbTests {
    private let window = LauncherSubject.target(RoadieTarget(id: "window:7", kind: .window, title: "Firefox", source: .roadie,
                                                             scope: TargetScopeSnapshot(displayId: "A", desktopId: 1, stageId: "1", windowId: 7), actions: [.focus]))

    private func tiling(_ state: LauncherTilingState) -> [LauncherVerb] {
        LauncherVerb.verbs(for: window, tiling: state).filter { [.float, .tileWindow, .floatAlways, .tileAlways, .clearTilingRule].contains($0) }
    }

    @Test func verbsFollowTheWindowAndItsApplicationRule() {
        #expect(tiling(LauncherTilingState(pinned: false, tiled: true, rule: nil)) == [.float, .floatAlways])
        #expect(tiling(LauncherTilingState(pinned: true, tiled: false, rule: nil)) == [.tileWindow, .floatAlways])
        #expect(tiling(LauncherTilingState(pinned: false, tiled: false, rule: .float)) == [.tileAlways, .clearTilingRule])
        #expect(tiling(LauncherTilingState(pinned: false, tiled: true, rule: .tile)) == [.float, .floatAlways, .clearTilingRule])
        // Fenêtre que macOS fait flotter par nature (dialogue) : seule la règle de l'application change cela.
        #expect(tiling(LauncherTilingState(pinned: false, tiled: false, rule: nil)) == [.floatAlways, .tileAlways])
        #expect(LauncherVerb.floatAlways.title(app: "Firefox") == "Toujours faire flotter Firefox")
        #expect(LauncherVerb.verbs(for: window).contains(.float))
    }
}

struct Spec075TilingRuleTests {
    private let firefox = WindowSnapshot(id: WindowID(rawValue: 7), pid: 1, appName: "Firefox", bundleID: "org.mozilla.firefox",
                                         title: "Accueil", frame: Rect(x: 0, y: 0, width: 100, height: 100), isOnScreen: true, isTileCandidate: true)
    private let scope = StageScope(displayID: DisplayID(rawValue: "A"), desktopID: DesktopID(rawValue: 2), stageID: StageID(rawValue: "3"))
    private let display = DisplaySnapshot(id: DisplayID(rawValue: "A"), index: 0, name: "Écran A", frame: Rect(x: 0, y: 0, width: 100, height: 100),
                                          visibleFrame: Rect(x: 0, y: 0, width: 100, height: 100), isMain: true)

    @Test func oneRulePerApplicationKeepsBothChoices() throws {
        let path = tempPath("spec075-rules") + ".toml"
        let service = WindowRuleAffinityService(path: path, eventLog: EventLog(path: tempPath("spec075-events")))
        #expect(service.saveTiling(.float, window: firefox).changed)
        #expect(service.tilingChoice(for: firefox) == .float)
        // L'affinité d'ouverture rejoint la même règle sans effacer le flottement.
        #expect(service.saveAffinity(kind: .app, window: firefox, scope: scope, display: display).changed)
        var rules = try RoadieConfigLoader.loadRulesFile(from: path)
        #expect(rules.count == 1 && rules[0].action.floating == true && rules[0].action.assignStage == "3")
        // Retirer l'affinité garde le flottement ; retirer le flottement efface la règle devenue vide.
        #expect(service.removeAppAffinity(window: firefox, scope: scope).changed)
        rules = try RoadieConfigLoader.loadRulesFile(from: path)
        #expect(rules.count == 1 && rules[0].action.floating == true && rules[0].action.assignStage == nil)
        #expect(service.saveTiling(.tile, window: firefox).changed)
        #expect(service.tilingChoice(for: firefox) == .tile)
        #expect(service.saveTiling(nil, window: firefox).changed)
        #expect(try RoadieConfigLoader.loadRulesFile(from: path).isEmpty)
        #expect(service.tilingChoice(for: firefox) == nil)
    }
}

@MainActor
struct Spec075KeyboardTests {
    private func key(_ code: UInt16, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                                      context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
    }

    @Test func rightArrowAtTheEndOpensTheVerbsAndElsewhereMovesTheCaret() throws {
        _ = NSApplication.shared
        let panel = SearchInputPanel()
        panel.update(text: "fire", frame: CGRect(x: 300, y: 100, width: 560, height: 28), font: .systemFont(ofSize: 15))
        panel.beginEditing()
        defer { panel.endEditing() }
        var received: [SearchKeyInput.Kind] = []
        panel.onKey = { received.append($0.kind) }
        let arrow = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                  windowNumber: panel.windowNumber, context: nil, characters: "\u{F703}",
                                                  charactersIgnoringModifiers: "\u{F703}", isARepeat: false, keyCode: 124))
        panel.sendEvent(arrow)
        #expect(received == [.actions])
        let editor = try #require(panel.field.currentEditor() as? NSTextView)
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        panel.sendEvent(arrow)
        #expect(received == [.actions])
    }

    @Test func commandDigitsPickARankAndReturnCarriesItsModifiers() throws {
        #expect(SearchInputPanel.navigation(try key(18, flags: .command))?.kind == .pick(1))
        #expect(SearchInputPanel.navigation(try key(25, flags: .command))?.kind == .pick(9))
        #expect(SearchInputPanel.navigation(try key(92, flags: .command))?.kind == .pick(9))
        #expect(SearchInputPanel.navigation(try key(18)) == nil)
        #expect(SearchInputPanel.navigation(try key(36, flags: .option))?.kind == .confirm(shift: false, command: false, option: true, control: false, isRepeat: false))
        #expect(SearchInputPanel.navigation(try key(36, flags: .control))?.kind == .confirm(shift: false, command: false, option: false, control: true, isRepeat: false))
    }
}
