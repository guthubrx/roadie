import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

struct Spec081MemoryTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let display = DisplayID(rawValue: "A")
    private var com: StageScope { StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "2")) }
    private var perso: StageScope { StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1")) }

    private func move(_ id: UInt32, _ bundle: String, from: StageScope?, to: StageScope, minutesAgo: Double) -> WindowMove {
        WindowMove(windowID: WindowID(rawValue: id), bundleID: bundle, appName: bundle == "slack" ? "Slack" : "Notes",
                   from: from, to: to, at: now.addingTimeInterval(-minutesAgo * 60))
    }
    private func identity(_ scope: StageScope) -> (key: String, title: String)? {
        scope == com ? ("stage:com", "Com") : scope == perso ? ("stage:perso", "Perso") : nil
    }

    @Test func aRepeatedMoveBecomesASuggestionUntilDeclined() throws {
        var book = LauncherMemoryBook()
        for index in 0..<3 { book.record(move(UInt32(10 + index), "slack", from: perso, to: com, minutesAgo: Double(100 - index))) }
        book.record(move(20, "notes", from: com, to: perso, minutesAgo: 5))
        let found = book.suggestions(at: now, identity: identity, hasRule: { _, _ in false })
        let first = try #require(found.first)
        #expect(found.count == 1 && first.appName == "Slack" && first.stage == com && first.count == 3)
        // Une règle déjà écrite l'empêche ; « Plus tard » la cache un jour ; « Jamais » pour toujours.
        #expect(book.suggestions(at: now, identity: identity, hasRule: { app, scope in app == "Slack" && scope == com }).isEmpty)
        book.decline(first, .later, at: now)
        #expect(book.suggestions(at: now.addingTimeInterval(3600), identity: identity, hasRule: { _, _ in false }).isEmpty)
        #expect(!book.suggestions(at: now.addingTimeInterval(25 * 3600), identity: identity, hasRule: { _, _ in false }).isEmpty)
        book.decline(first, .never, at: now)
        #expect(book.suggestions(at: now.addingTimeInterval(30 * 24 * 3600), identity: identity, hasRule: { _, _ in false }).isEmpty)
    }

    @Test func scatteredMovesAreNotAHabit() {
        var book = LauncherMemoryBook()
        for index in 0..<3 { book.record(move(UInt32(index + 1), "slack", from: perso, to: com, minutesAgo: 10)) }
        for index in 0..<2 { book.record(move(UInt32(index + 9), "slack", from: com, to: perso, minutesAgo: 9)) }
        #expect(book.suggestions(at: now, identity: identity, hasRule: { _, _ in false }).isEmpty)
    }

    @Test func onlyTheLastRecentMoveCanBeUndone() {
        var book = LauncherMemoryBook()
        book.record(move(7, "notes", from: perso, to: com, minutesAgo: 3))
        #expect(book.undoable(at: now, currentScope: { _ in self.com })?.windowID == WindowID(rawValue: 7))
        // Fenêtre déplacée depuis, ou déplacement trop ancien : plus d'annulation.
        #expect(book.undoable(at: now, currentScope: { _ in self.perso }) == nil)
        #expect(book.undoable(at: now.addingTimeInterval(8 * 60), currentScope: { _ in self.com }) == nil)
    }

    @Test func movesAreBounded() {
        var book = LauncherMemoryBook()
        for index in 0..<(LauncherMemoryBook.maxMoves + 5) { book.record(move(UInt32(index + 1), "notes", from: perso, to: com, minutesAgo: 1)) }
        #expect(book.moves.count == LauncherMemoryBook.maxMoves && book.moves.first?.windowID == WindowID(rawValue: 6))
    }

    @Test func recentlyClosedWindowsNewestFirstWithinTwelveHours() {
        func member(_ id: UInt32, _ title: String, closedMinutesAgo: Double?) -> PersistentStageMember {
            var member = PersistentStageMember(windowID: WindowID(rawValue: id), bundleID: "mail", title: title, frame: Rect(x: 0, y: 0, width: 1, height: 1))
            member.confirmedClosedAt = closedMinutesAgo.map { now.addingTimeInterval(-$0 * 60) }
            return member
        }
        let state = PersistentStageState(scopes: [PersistentStageScope(displayID: display, stages: [
            PersistentStage(id: StageID(rawValue: "2"), name: "Com", members: [
                member(1, "Boîte", closedMinutesAgo: 30), member(2, "Brouillon", closedMinutesAgo: 3),
                member(3, "Ancien", closedMinutesAgo: 13 * 60), member(4, "Ouverte", closedMinutesAgo: nil),
                member(5, "Boîte", closedMinutesAgo: 60),
            ]),
        ])])
        let closed = ClosedWindow.recent(in: state, at: now)
        #expect(closed.map(\.title) == ["Brouillon", "Boîte"])
        #expect(ClosedWindow.ago(now.addingTimeInterval(-180), now: now) == "il y a 3 min")
        #expect(ClosedWindow.ago(now.addingTimeInterval(-7300), now: now) == "il y a 2 h")
    }

    @Test func storeRecordsOnlyRealMoves() {
        let store = LauncherMemoryStore(path: tempPath("spec081-moves") + ".json")
        let window = WindowSnapshot(id: WindowID(rawValue: 3), pid: 1, appName: "Notes", bundleID: "notes", title: "",
                                    frame: Rect(x: 0, y: 0, width: 1, height: 1), isOnScreen: true, isTileCandidate: true)
        store.record(window: window, from: com, to: com, at: now)
        store.record(window: window, from: perso, to: com, at: now)
        #expect(store.load().moves.count == 1)
    }
}

struct Spec081IdleListTests {
    @Test func theIdleListKeepsItsRowsAndSelectsTheFirst() {
        let suggestion = RuleSuggestion(bundleID: "slack", appName: "Slack",
                                        stage: StageScope(displayID: DisplayID(rawValue: "A"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "2")),
                                        stageTitle: "Com", count: 3, declineKey: "slack|stage:com")
        let list = LauncherList.idle([.header("Règle proposée"), .rule(suggestion, .create), .rule(suggestion, .later)])
        #expect(list.best == "rule:slack|stage:com:create")
        #expect(list.neighbour(of: list.best, step: 1) == "rule:slack|stage:com:later")
        var bar = TargetSearchBar(query: "fi", matchCount: 4, properties: nil, isLoading: false)
        bar.chip = "💡 1"
        #expect(bar.counterText == "💡 1   4")
    }
}
