import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

struct Spec074VerbsTests {
    private let display = DisplayID(rawValue: "A")
    private let firefox = LauncherSubject.app(LauncherApp(bundleID: "org.mozilla.firefox", path: "/Applications/Firefox.app", name: "Firefox", alternateNames: []))
    private var home: (DisplayID, DesktopID) { (display, DesktopID(rawValue: 1)) }

    private func stage(_ id: String, _ name: String, desktop: Int = 1) -> LauncherDestination {
        LauncherDestination(kind: .stage(StageScope(displayID: display, desktopID: DesktopID(rawValue: desktop), stageID: StageID(rawValue: id))),
                            title: name, detail: "bureau \(desktop)")
    }
    private var destinations: [LauncherDestination] {
        [stage("1", "Perso"), stage("2", "Com"), stage("3", "Work", desktop: 2),
         LauncherDestination(kind: .desktop(display, DesktopID(rawValue: 2)), title: "Bureau 2", detail: "A"),
         LauncherDestination(kind: .display(display), title: "Écran A", detail: "écran")]
    }
    private func titles(_ list: LauncherActionList) -> [String] {
        list.rows.map { row in
            switch row {
            case .header(let title): "# \(title)"
            case .verb(let verb): verb.rawValue
            case .destination(let verb, let destination): "\(verb.rawValue) → \(destination.title)"
            case .workflow(let entry): "workflow \(entry.title)"
            }
        }
    }

    @Test func eachSubjectGetsItsVerbsDefaultFirst() {
        #expect(titles(.verbs(for: firefox, query: "", destinations: destinations, newStageHome: home))
                == ["# Firefox ›", "open", "openIn", "bringHere", "newWindow", "gatherIn", "hide", "quit"])
        let window = RoadieTarget(id: "window:7", kind: .window, title: "Firefox", subtitle: "Accueil", source: .roadie,
                                  scope: TargetScopeSnapshot(displayId: "A", desktopId: 1, stageId: "1", windowId: 7), actions: [.focus])
        #expect(LauncherVerb.verbs(for: .target(window)).first == .focus)
        let button = RoadieTarget(id: "ax:1", kind: .appElement, title: "Filtrer", source: .app, actions: [.click])
        #expect(LauncherVerb.verbs(for: .target(button)) == [.click, .doubleClick, .rightClick, .commandClick])
    }

    @Test func typingANameOffersTheDestinationDirectly() {
        let list = LauncherActionList.verbs(for: firefox, query: "perso", destinations: destinations, newStageHome: home)
        #expect(titles(list) == ["# Firefox ›", "# Destinations", "openIn → Perso", "openIn → Nouvelle stage"])
        #expect(list.best == "destination:openIn:stage:A/1/1")
        // Un nom inconnu propose de créer la stage sous ce nom.
        let fresh = LauncherActionList.verbs(for: firefox, query: "Lecture", destinations: destinations, newStageHome: home)
        #expect(titles(fresh).last == "openIn → Nouvelle stage « Lecture »")
        // Un nom de verbe garde le verbe en tête.
        #expect(LauncherActionList.verbs(for: firefox, query: "quit", destinations: destinations, newStageHome: home).best == "verb:quit")
    }

    @Test func destinationsFollowTheVerbAndSkipTheOwnStage() {
        let window = RoadieTarget(id: "window:7", kind: .window, title: "Firefox", source: .roadie,
                                  scope: TargetScopeSnapshot(displayId: "A", desktopId: 1, stageId: "1", windowId: 7), actions: [.focus])
        let send = titles(.destinations(for: .target(window), verb: .sendTo, query: "", destinations: destinations, newStageHome: home))
        #expect(send == ["# Firefox › Envoyer vers", "sendTo → Com", "sendTo → Work", "sendTo → Bureau 2", "sendTo → Écran A", "sendTo → Nouvelle stage"])
        let desktop = RoadieTarget(id: "desktop:2", kind: .desktop, title: "Bureau 2", source: .roadie,
                                   scope: TargetScopeSnapshot(displayId: "A", desktopId: 2), actions: [.switch])
        #expect(titles(.destinations(for: .target(desktop), verb: .moveTo, query: "", destinations: destinations, newStageHome: home))
                == ["# Bureau 2 › Déplacer vers", "moveTo → Écran A"])
    }

    @Test func destinationsListShownStagesDesktopsAndDisplays() {
        let screen = DisplaySnapshot(id: display, index: 0, name: "Écran A", frame: Rect(x: 0, y: 0, width: 100, height: 100),
                                     visibleFrame: Rect(x: 0, y: 0, width: 100, height: 100), isMain: true)
        let member = PersistentStageMember(windowID: WindowID(rawValue: 1), bundleID: "b", title: "t", frame: Rect(x: 0, y: 0, width: 1, height: 1))
        let state = PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stages: [PersistentStage(id: StageID(rawValue: "1"), name: "Perso")]),
            PersistentStageScope(displayID: display, desktopID: DesktopID(rawValue: 3), stages: [PersistentStage(id: StageID(rawValue: "2"), members: [member])]),
            PersistentStageScope(displayID: display, desktopID: DesktopID(rawValue: 4), stages: [PersistentStage(id: StageID(rawValue: "1"))]),
        ], desktopSelections: [PersistentDesktopSelection(displayID: display, currentDesktopID: DesktopID(rawValue: 1))])
        let names = [StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1")): "Perso",
                     StageScope(displayID: display, desktopID: DesktopID(rawValue: 3), stageID: StageID(rawValue: "2")): "Stage 1"]
        let found = LauncherPlacement.destinations(state: state, displays: [screen], stageNames: names).map(\.title)
        #expect(found == ["Perso", "Stage 1", "Bureau 1", "Bureau 3", "Écran A"])
    }

    @Test func aNewStageIsCreatedWithAUniqueName() {
        let store = StageStore(path: tempPath("spec074-create"))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stages: [PersistentStage(id: StageID(rawValue: "1"), name: "Perso")]),
        ]))
        let provider = PowerUserProvider(windows: [])
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), config: RoadieConfig(), stageStore: store)
        let commands = StageCommandService(service: service, store: store, events: EventLog(path: tempPath("spec074-events")))
        let (created, scope) = commands.createStage(named: "Lecture", displayID: display, desktopID: DesktopID(rawValue: 2))
        #expect(created.changed)
        #expect(scope?.desktopID == DesktopID(rawValue: 2))
        #expect(store.state().scopes.first { $0.desktopID == DesktopID(rawValue: 2) }?.stages.contains { $0.name == "Lecture" } == true)
        #expect(commands.createStage(named: "perso", displayID: display, desktopID: DesktopID(rawValue: 2)).1 == nil)
        #expect(commands.createStage(named: nil, displayID: display, desktopID: DesktopID(rawValue: 1)).1?.stageID == StageID(rawValue: "2"))
    }
}
