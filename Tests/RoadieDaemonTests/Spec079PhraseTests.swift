import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

struct Spec079PhraseTests {
    private let display = DisplayID(rawValue: "A")
    private var home: (DisplayID, DesktopID) { (display, DesktopID(rawValue: 1)) }
    private var perso: StageScope { StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1")) }
    private var com2: StageScope { StageScope(displayID: display, desktopID: DesktopID(rawValue: 2), stageID: StageID(rawValue: "4")) }
    private var destinations: [LauncherDestination] {
        [LauncherDestination(kind: .stage(perso), title: "Perso", detail: ""),
         LauncherDestination(kind: .stage(com2), title: "Com 2", detail: ""),
         LauncherDestination(kind: .desktop(display, DesktopID(rawValue: 2)), title: "Bureau 2", detail: ""),
         LauncherDestination(kind: .display(display), title: "Écran A", detail: "écran")]
    }
    private let firefox = LauncherSubject.app(LauncherApp(bundleID: "org.mozilla.firefox", path: "/Applications/Firefox.app", name: "Firefox", alternateNames: []))

    private func parse(_ text: String) -> LauncherPhrase? { LauncherPhrase.parse(text, destinations: destinations, newStageHome: home) }

    @Test func frenchAndEnglishWordsGiveTheSamePhrase() throws {
        let fr = try #require(parse("fire perso gauche"))
        let en = try #require(parse("fire perso left"))
        #expect(fr == en)
        #expect(fr.objectQuery == "fire" && fr.position == .left)
        let action = try #require(fr.action(for: firefox, activeStage: perso))
        #expect(action.verb == .openIn && action.destination?.kind == .stage(perso))
        #expect(LauncherPhrase.title(action) == "Ouvrir Firefox dans Perso, à gauche")
    }

    @Test func noPhraseWithoutARecognisedEnding() {
        #expect(parse("fire") == nil)
        #expect(parse("visual studio") == nil)
        #expect(parse("perso") == nil)
        #expect(parse("gauche droite") == nil || parse("gauche droite")?.objectQuery == "gauche")
    }

    @Test func otherPlacesAreRecognised() throws {
        #expect(try #require(parse("fire ici")).place == .here)
        #expect(try #require(parse("fire nouvelle stage")).place
                == .destination(LauncherDestination(kind: .newStage(name: nil, display, DesktopID(rawValue: 1)), title: "Nouvelle stage", detail: "bureau 1")))
        #expect(try #require(parse("term desktop 2")).place == .destination(destinations[2]))
        #expect(try #require(parse("term écran 1 plein")).position == .full)
        // Nom de deux mots, et début unique d'au moins 3 lettres.
        #expect(try #require(parse("fire com 2")).place == .destination(destinations[1]))
        #expect(try #require(parse("fire pers")).place == .destination(destinations[0]))
        #expect(parse("fire pe") == nil)
    }

    @Test func eachObjectGetsItsVerb() throws {
        let window = LauncherSubject.target(RoadieTarget(id: "window:7", kind: .window, title: "Terminal", source: .roadie,
                                                         scope: TargetScopeSnapshot(displayId: "A", desktopId: 1, stageId: "1", windowId: 7), actions: [.focus]))
        #expect(try #require(parse("term com 2")).action(for: window, activeStage: perso)?.verb == .sendTo)
        #expect(try #require(parse("term perso")).action(for: window, activeStage: perso) == nil)
        #expect(try #require(parse("term gauche")).action(for: window, activeStage: perso)?.verb == .focus)
        let stage = LauncherSubject.target(RoadieTarget(id: "stage:4", kind: .stage, title: "Com 2", source: .roadie, actions: [.switch]))
        #expect(try #require(parse("com bureau 2")).action(for: stage, activeStage: perso)?.verb == .moveTo)
        // Une application ne va pas « vers un bureau » : pas d'action, la liste normale reste.
        #expect(try #require(parse("fire bureau 2")).action(for: firefox, activeStage: perso) == nil)
    }
}

struct Spec079AliasTests {
    private let display = DisplayID(rawValue: "A")
    private var perso: StageScope { StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1")) }
    private let app = LauncherApp(bundleID: "org.mozilla.firefox", path: "/Applications/Fire fox's.app", name: "Firefox", alternateNames: [])

    @Test func onlyDurableActionsAreKeptWithTheirCommand() throws {
        var action = LauncherAction(subject: .app(app), verb: .openIn, destination: LauncherDestination(kind: .stage(perso), title: "Perso", detail: ""))
        action.position = .left
        let alias = try LauncherAlias.from(action) { _ in "Perso" }.get()
        #expect(alias.command == #"roadie launch '/Applications/Fire fox'\''s.app' --stage 'Perso' --position left"#)
        #expect(LauncherAlias.from(action) { _ in nil } == .failure(.anonymousStage))
        let window = RoadieTarget(id: "window:1", kind: .window, title: "x", source: .roadie, actions: [.focus])
        #expect(LauncherAlias.from(LauncherAction(subject: .target(window), verb: .focus, destination: nil)) { _ in nil } == .failure(.notDurable))
        #expect(LauncherAlias.from(LauncherAction(subject: .app(app), verb: .quit, destination: nil)) { _ in nil } == .failure(.unsupportedVerb))
        let here = try LauncherAlias.from(LauncherAction(subject: .app(app), verb: .bringHere, destination: nil)) { _ in nil }.get()
        #expect(here.command.hasSuffix("--here"))
    }

    @Test func anAliasFindsItsStageByNameAtUseTime() throws {
        let alias = LauncherAlias(path: app.path, isApp: true, bundleID: app.bundleID, name: "Firefox", stage: "Perso",
                                  here: false, newStage: false, position: .full)
        let moved = StageScope(displayID: display, desktopID: DesktopID(rawValue: 3), stageID: StageID(rawValue: "9"))
        let state = PersistentStageState(scopes: [PersistentStageScope(displayID: display, desktopID: DesktopID(rawValue: 3),
                                                                       stages: [PersistentStage(id: StageID(rawValue: "9"), name: "Perso")])])
        let action = try #require(alias.action(state: state, activeStage: nil, home: (display, DesktopID(rawValue: 1))))
        #expect(action.destination?.kind == .stage(moved) && action.position == .full && action.verb == .openIn)
        #expect(alias.action(state: PersistentStageState(), activeStage: nil, home: (display, DesktopID(rawValue: 1))) == nil)
    }

    @Test func namesAndStorage() throws {
        #expect(LauncherAlias.isValidName("fp") && LauncherAlias.isValidName("douzecaracte") && !LauncherAlias.isValidName("treizecaracte"))
        #expect(!LauncherAlias.isValidName("f p") && !LauncherAlias.isValidName(" "))
        let store = LauncherAliasStore(path: tempPath("spec079-aliases") + ".json")
        let alias = LauncherAlias(path: app.path, isApp: true, bundleID: nil, name: "Firefox", stage: nil, here: true, newStage: false, position: nil)
        #expect(try store.save(alias, as: "FP") == nil)
        #expect(store.load().alias(for: "fp")?.1 == alias)
        #expect(try store.save(alias, as: "fp") == alias)
    }
}
