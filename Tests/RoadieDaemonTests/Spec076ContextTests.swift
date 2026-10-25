import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

struct Spec076ContextTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let outlook = LauncherApp(bundleID: "com.microsoft.Outlook", path: "/Applications/Microsoft Outlook.app", name: "Outlook", alternateNames: [])
    private let orb = LauncherApp(bundleID: "dev.orbstack", path: "/Applications/OrbStack.app", name: "OrbStack", alternateNames: [])

    private func best(_ ranking: LauncherRanking, query: String, context: String?) -> String? {
        LauncherList(query: query, apps: [outlook, orb], details: [:], targets: [], ranking: ranking, now: now, context: context).best
    }

    @Test func eachStageKeepsItsOwnChoices() {
        var ranking = LauncherRanking()
        for _ in 0..<3 {
            ranking.recordVisit(outlook.rankingKey, query: "o", at: now, context: "stage:com")
            ranking.recordVisit(orb.rankingKey, query: "o", at: now, context: "stage:dev")
        }
        #expect(best(ranking, query: "o", context: "stage:com") == outlook.rankingKey)
        #expect(best(ranking, query: "o", context: "stage:dev") == orb.rankingKey)
        // Une stage sans historique garde l'ordre global (ici à égalité : l'ordre alphabétique).
        #expect(best(ranking, query: "o", context: "stage:perso") == best(ranking, query: "o", context: nil))
    }

    @Test func aStageHabitBreaksTiesWithoutBeatingABetterMatch() {
        var ranking = LauncherRanking()
        ranking.recordVisit(orb.rankingKey, query: "orbstack", at: now, context: "stage:com")
        // « o » : les deux commencent par o ; l'habitude de la stage départage.
        #expect(best(ranking, query: "o", context: "stage:com") == orb.rankingKey)
        // « out » : seul Outlook correspond.
        #expect(best(ranking, query: "out", context: "stage:com") == outlook.rankingKey)
    }

    @Test func onlyTheMostRecentStagesAreKept() {
        var ranking = LauncherRanking()
        for index in 0..<8 {
            ranking.recordVisit(outlook.rankingKey, query: "o", at: now.addingTimeInterval(Double(index)), context: "stage:s\(index)")
        }
        let contexts = ranking.entries[outlook.rankingKey]?.contexts ?? [:]
        #expect(contexts.count == LauncherRanking.maxContexts)
        #expect(contexts["stage:s0"] == nil && contexts["stage:s7"] != nil)
    }

    @Test func the073FileFormatReadsBothWays() throws {
        let old = #"{"entries":{"app:x":{"anchor":2000000500,"abbreviations":{"o":2}}}}"#
        let read = try JSONDecoder().decode(LauncherRanking.self, from: Data(old.utf8))
        #expect(read.exactUses("app:x", query: "o") == 2 && read.entries["app:x"]?.contexts == nil)
        var ranking = read
        ranking.recordVisit("app:x", query: "o", at: now, context: "stage:com")
        // Le décodeur 073 ne connaît que l'ancre et les abréviations : il lit le nouveau fichier.
        struct Entry073: Decodable { var anchor: Double; var abbreviations: [String: Int] }
        struct Ranking073: Decodable { var entries: [String: Entry073] }
        let legacy = try JSONDecoder().decode(Ranking073.self, from: JSONEncoder().encode(ranking))
        #expect(legacy.entries["app:x"]?.abbreviations["o"] == 3)
    }

    @Test func namedStagesAreKnownByNameAndOthersByPlace() {
        let scope = StageScope(displayID: DisplayID(rawValue: "A"), desktopID: DesktopID(rawValue: 2), stageID: StageID(rawValue: "3"))
        #expect(LauncherSearchContext.rankingContext(scope, name: "Com") == "stage:com")
        #expect(LauncherSearchContext.rankingContext(scope, name: "") == "scope:\(scope.description)")
        #expect(LauncherSearchContext.rankingContext(scope, name: nil) == "scope:\(scope.description)")
    }
}
