import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

struct Spec073LauncherMatchTests {
    @Test func substringsInitialsAndWordStartsMatch() {
        #expect(LauncherMatch.score("code", in: "Xcode") != nil)
        #expect(LauncherMatch.score("vsc", in: "Visual Studio Code") != nil)
        #expect(LauncherMatch.score("ps", in: "Adobe Photoshop 2026") != nil)
        #expect(LauncherMatch.score("stack", in: "OrbStack") != nil)
        #expect(LauncherMatch.score("calc", in: "Calculatrice") != nil)
        #expect(LauncherMatch.score("tele", in: "Télégramme") != nil)
        #expect(LauncherMatch.score("firefox", in: "Firefox") == Int.max)
        #expect(LauncherMatch.score("xyz", in: "Firefox") == nil)
        #expect(LauncherMatch.score("feox", in: "Firefox") == nil)
        #expect(LauncherMatch.score("s", in: "Safari") != nil)
        #expect(LauncherMatch.score("a", in: "Safari") == nil)
    }

    @Test func aWordStartScoresAboveAMidWordHit() throws {
        let start = try #require(LauncherMatch.score("st", in: "Stickies"))
        let inside = try #require(LauncherMatch.score("st", in: "Podcasts"))
        #expect(start > inside)
    }
}

struct Spec073LauncherRankingTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func visitsAreRememberedPerAbbreviationAndDecay() {
        var ranking = LauncherRanking()
        ranking.recordVisit("app:a", query: "Fi", at: now)
        ranking.recordVisit("app:a", query: "fi", at: now)
        #expect(ranking.exactUses("app:a", query: "FI") == 2)
        #expect(ranking.prefixUses("app:a", query: "f") == 2)
        #expect(ranking.frecency("app:a", at: now) > 150)
        let later = now.addingTimeInterval(LauncherRanking.halfLife)
        #expect(abs(ranking.frecency("app:a", at: later) - ranking.frecency("app:a", at: now) / 2) < 1)
        ranking.prune(at: now.addingTimeInterval(LauncherRanking.halfLife * 20))
        #expect(ranking.entries.isEmpty)
    }

    @Test func storeKeepsTheRankingOnDisk() {
        let store = LauncherRankingStore(path: tempPath("spec073-ranking"))
        store.recordVisit("app:a", query: "saf", at: now)
        #expect(store.load(at: now).exactUses("app:a", query: "saf") == 1)
    }
}

struct Spec073LauncherListTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let firefox = LauncherApp(bundleID: "org.mozilla.firefox", path: "/Applications/Firefox.app", name: "Firefox", alternateNames: [])
    private let finder = LauncherApp(bundleID: "com.apple.finder", path: "/System/Library/CoreServices/Finder.app", name: "Finder", alternateNames: [])
    private let calc = LauncherApp(bundleID: "com.apple.calculator", path: "/System/Applications/Calculator.app", name: "Calculatrice", alternateNames: ["Calculator"])

    private func target(_ id: String, _ kind: TargetKind, _ title: String) -> RoadieTarget {
        RoadieTarget(id: id, kind: kind, title: title, source: kind == .appElement ? .app : .roadie, actions: [.focus])
    }

    @Test func rowsAreGroupedBySectionWithHeaders() {
        let list = LauncherList(query: "fi", apps: [firefox, finder, calc], details: ["org.mozilla.firefox": "Ouverte · Perso"],
                                targets: [target("window:1", .window, "Firefox"), target("stage:2", .stage, "Fichiers"),
                                          target("ax:1", .appElement, "Filtrer")],
                                ranking: LauncherRanking(), now: now)
        let headers = list.rows.compactMap { if case .header(let title) = $0 { return title } else { return nil } }
        #expect(headers == ["Applications", "Fenêtres", "Stages et bureaux", "À l'écran · 1"])
        #expect(list.rows.contains(.app(firefox, detail: "Ouverte · Perso")))
        #expect(!list.rows.contains { $0.id == calc.rankingKey })
        #expect(LauncherList(query: " ", apps: [firefox], details: [:], targets: [], ranking: LauncherRanking(), now: now).rows.isEmpty)
    }

    @Test func alternateNamesAndLearnedChoicesDecide() {
        #expect(LauncherList(query: "calcul", apps: [calc], details: [:], targets: [], ranking: LauncherRanking(), now: now).best == calc.rankingKey)
        var ranking = LauncherRanking()
        let window = target("window:1", .window, "Firefox")
        #expect(LauncherList(query: "fire", apps: [firefox], details: [:], targets: [window], ranking: ranking, now: now).best == firefox.rankingKey)
        ranking.recordVisit(LauncherList.rankingKey(window), query: "fire", at: now)
        let learned = LauncherList(query: "fire", apps: [firefox], details: [:], targets: [window], ranking: ranking, now: now)
        #expect(learned.best == "target:window:1")
        #expect(learned.neighbour(of: learned.best, step: 1) == firefox.rankingKey)
        #expect(learned.neighbour(of: firefox.rankingKey, step: 1) == "target:window:1")
    }
}

struct Spec073LauncherCatalogTests {
    @Test func scanFindsAppsOneFolderDeepWithoutDuplicates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("spec073-apps-\(UUID().uuidString)")
        func makeApp(_ relative: String, id: String, background: Bool = false) throws {
            let contents = root.appendingPathComponent(relative).appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            var info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": "Nom \(id)"]
            if background { info["LSBackgroundOnly"] = true }
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
        }
        defer { try? FileManager.default.removeItem(at: root) }
        try makeApp("Alpha.app", id: "test.alpha")
        try makeApp("Vendor/Beta.app", id: "test.beta")
        try makeApp("Vendor/Deep/Gamma.app", id: "test.gamma")
        try makeApp("Copy/Alpha.app", id: "test.alpha")
        try makeApp("Agent.app", id: "test.agent", background: true)
        let apps = LauncherAppCatalog.scan(roots: [root.path])
        #expect(Set(apps.map(\.bundleID)) == ["test.alpha", "test.beta"])
        #expect(apps.first { $0.bundleID == "test.alpha" }?.alternateNames.contains("Nom test.alpha") == true)
    }
}

struct Spec073LauncherPlacementTests {
    private let display = DisplayID(rawValue: "A")
    private func entry(_ id: UInt32, stage: String, desktop: Int = 1) -> WindowSwitcherEntry {
        WindowSwitcherEntry(window: WindowSnapshot(id: WindowID(rawValue: id), pid: 1, appName: "Firefox", bundleID: "org.mozilla.firefox",
                                                   title: "w\(id)", frame: Rect(x: 0, y: 0, width: 10, height: 10), isOnScreen: true, isTileCandidate: true),
                            scope: StageScope(displayID: display, desktopID: DesktopID(rawValue: desktop), stageID: StageID(rawValue: stage)))
    }
    private func state(active: String, focused: [String: UInt32]) -> PersistentStageState {
        PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, desktopID: DesktopID(rawValue: 1), activeStageID: StageID(rawValue: active), stages: ["1", "2"].map { id in
                PersistentStage(id: StageID(rawValue: id), name: id == "1" ? "Perso" : "Com", focusedWindowID: focused[id].map(WindowID.init(rawValue:)),
                                members: [PersistentStageMember(windowID: WindowID(rawValue: id == "1" ? 11 : 21), bundleID: "org.mozilla.firefox",
                                                                title: "w", frame: Rect(x: 0, y: 0, width: 10, height: 10))])
            }),
        ], desktopSelections: [PersistentDesktopSelection(displayID: display, currentDesktopID: DesktopID(rawValue: 1))])
    }

    @Test func theWindowShownAndFocusedWins() {
        let windows = [entry(21, stage: "2"), entry(11, stage: "1"), entry(12, stage: "1")]
        #expect(LauncherPlacement.preferredWindow(windows, state: state(active: "1", focused: ["1": 12]))?.id.rawValue == 12)
        #expect(LauncherPlacement.preferredWindow(windows, state: state(active: "1", focused: [:]))?.id.rawValue == 11)
        #expect(LauncherPlacement.preferredWindow(windows, state: state(active: "9", focused: ["2": 21]))?.id.rawValue == 21)
        #expect(LauncherPlacement.preferredWindow([], state: state(active: "1", focused: [:])) == nil)
    }

    @Test func detailsNameTheShownStageFirst() {
        let names = [StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1")): "Perso",
                     StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "2")): "Com"]
        let details = LauncherPlacement.details(runningBundleIDs: ["org.mozilla.firefox", "com.apple.mail"], state: state(active: "2", focused: [:]), stageNames: names)
        #expect(details["org.mozilla.firefox"] == "Ouverte · Com · bureau 1")
        #expect(details["com.apple.mail"] == "Ouverte")
        #expect(details["com.apple.finder"] == nil)
    }
}

struct Spec073RichLayoutTests {
    @Test func theListSlidesJustEnoughToKeepTheSelectionVisible() throws {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 400)
        let heights: [CGFloat] = [24] + Array(repeating: 46, count: 12)
        let top = SearchBarLayout.makeRich(bounds: bounds, heights: heights, selected: 1)
        #expect(top.firstVisible == 0)
        let shown = top.suggestionRows.count
        #expect(shown > 1 && shown < heights.count)
        let bottom = SearchBarLayout.makeRich(bounds: bounds, heights: heights, selected: 12)
        let first = try #require(bottom.firstVisible)
        #expect(first > 0 && first + bottom.suggestionRows.count == 13)
        // Le clic sur la dernière ligne montrée vise la ligne sélectionnée.
        let last = try #require(bottom.suggestionRows.last)
        #expect(bottom.suggestionIndex(at: CGPoint(x: last.midX, y: last.midY), count: 13, selected: 12) == 12)
        #expect((top.panel?.maxY ?? 0) <= bounds.maxY)
    }
}
