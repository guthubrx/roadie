import Foundation
import Testing
@testable import RoadieDaemon

struct Spec093NumericSafetyTests {
    private final class EventCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }

    @Test func plistNumbersOutsideIntegerRangeAreRejected() throws {
        #expect(PlistValue.double(2.9).int == 2)
        #expect(PlistValue.double(-2.9).int == -2)
        #expect(PlistValue.double(.greatestFiniteMagnitude).int == nil)
        #expect(PlistValue.double(-.greatestFiniteMagnitude).int == nil)
        #expect(PlistValue.double(.infinity).int == nil)
        #expect(PlistValue.double(.nan).int == nil)

        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-093-plist-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: sandbox) }
        var fixture = WorkflowFixture()
        fixture.add("SF", "input.scriptfilter", ["keyword": "exemple", "argumenttype": 1e100])
        let workflow = try fixture.write(in: sandbox)
        let entry = try #require(AlfredWorkflowIndex.entries([workflow]).first)
        #expect(entry.argument == .required)
    }

    @Test func calculatorLimitsRecursiveDepthButKeepsOrdinaryExpressions() {
        func nested(_ count: Int) -> String {
            "=" + String(repeating: "(", count: count) + "1" + String(repeating: ")", count: count)
        }
        #expect(LauncherCalculator.evaluate(nested(32))?.value == 1)
        #expect(LauncherCalculator.evaluate(nested(50_000)) == nil)
        #expect(LauncherCalculator.evaluate("=" + String(repeating: "-", count: 200) + "1") == nil)
        #expect(LauncherCalculator.evaluate("=" + Array(repeating: "1", count: 200).joined(separator: "^")) == nil)
        #expect(LauncherCalculator.evaluate(Array(repeating: "1", count: 300).joined(separator: "+"))?.value == 300)
    }

    @Test func invalidWorkflowKeyCodeDoesNotCrashOrEmitAKey() async {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-093-log-\(UUID().uuidString)")
        let counter = EventCounter()
        let effects = AlfredLiveEffects(events: EventLog(path: path.path), webSearchURL: "", reopen: { _ in },
                                        postKeyEvent: { _ in counter.increment() })
        // Le compteur remplace l'émission réelle et vérifie les deux chemins.
        await effects.keyCombo(keyCode: 65_536, character: "", modifiers: 0, count: 1)
        await effects.keyCombo(keyCode: .max, character: "", modifiers: 0, count: 1)
        #expect(counter.value == 0)
        await effects.keyCombo(keyCode: 0, character: "", modifiers: 0, count: 1)
        #expect(counter.value == 2)
    }

    @Test func rankingCountersDoNotOverflowOnDamagedButValidData() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var ranking = LauncherRanking(entries: ["a": .init(anchor: now.timeIntervalSince1970,
                                                             abbreviations: ["x": .max, "xx": 1], contexts: nil)])
        #expect(ranking.prefixUses("a", query: "x") == .max)
        ranking.recordVisit("a", query: "x", at: now)
        #expect(ranking.exactUses("a", query: "x") == .max)
        #expect(ranking.prefixUses("a", query: "x") == .max)
    }

    @Test func extremeRankingAnchorsRemainEncodable() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var ranking = LauncherRanking(entries: ["a": .init(anchor: 1e308, abbreviations: [:],
                                                             contexts: ["stage": .init(anchor: 1e308, abbreviations: [:])])])
        #expect(ranking.frecency("a", at: now).isFinite)
        #expect(ranking.frecency("a", at: now, context: "stage").isFinite)
        ranking.recordVisit("a", query: "x", at: now, context: "stage")
        #expect(ranking.entries["a"]?.anchor.isFinite == true)
        #expect(ranking.entries["a"]?.contexts?["stage"]?.anchor.isFinite == true)
        #expect(ranking.frecency("a", at: now).isFinite)
        #expect(ranking.frecency("a", at: now, context: "stage").isFinite)
        _ = try JSONEncoder().encode(ranking)
    }
}
