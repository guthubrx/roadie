import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

struct Spec111VerbOrderTests {
    private let app = LauncherSubject.app(LauncherApp(bundleID: "org.mozilla.firefox", path: "/Applications/Firefox.app",
                                                      name: "Firefox", alternateNames: []))
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func withoutHistoryTheDefaultOrderStays() {
        let defaults = LauncherVerb.verbs(for: app)
        #expect(LauncherVerb.learnedOrder(defaults, for: app, ranking: LauncherRanking(), at: now) == defaults)
    }

    @Test func theMostChosenVerbComesFirstForThatKindOnly() {
        var ranking = LauncherRanking()
        ranking.recordVisit(LauncherVerb.quit.rankingKey(for: app), query: "", at: now)
        ranking.recordVisit(LauncherVerb.quit.rankingKey(for: app), query: "", at: now)
        ranking.recordVisit(LauncherVerb.hide.rankingKey(for: app), query: "", at: now)
        let ordered = LauncherVerb.learnedOrder(LauncherVerb.verbs(for: app), for: app, ranking: ranking, at: now)
        #expect(Array(ordered.prefix(3)) == [.quit, .hide, .open])
        // Un fichier garde son ordre : l'apprentissage est par type d'objet.
        let file = LauncherSubject.file(LauncherFile(path: "/tmp/a.txt", name: "a.txt", isFolder: false, lastUsed: nil))
        #expect(LauncherVerb.learnedOrder(LauncherVerb.verbs(for: file), for: file, ranking: ranking, at: now) == LauncherVerb.verbs(for: file))
    }

    @Test func keysNameTheKindAndTheVerb() {
        #expect(LauncherVerb.quit.rankingKey(for: app) == "verb:app:quit")
    }

    @Test func settingIsOnByDefaultInSearch() throws {
        #expect(TargetModeConfig().learnVerbOrder)
        let entry = try #require(SettingsCatalog.all.first { $0.tablePath == "experimental.target_mode" && $0.key == "learn_verb_order" })
        #expect(entry.category == .recherche && entry.defaultValue == .bool(true))
    }
}
