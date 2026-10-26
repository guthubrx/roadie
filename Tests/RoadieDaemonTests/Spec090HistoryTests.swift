import Foundation
import Testing
@testable import RoadieDaemon

struct Spec090HistoryTests {
    @Test func keepsTwentyDistinctQueriesAndResumesWithinFiveMinutes() {
        var book = LauncherHistoryBook()
        let start = Date(timeIntervalSince1970: 1_000_000)
        for index in 0..<25 { book.record("q\(index)", at: start.addingTimeInterval(Double(index))) }
        #expect(book.entries.count == 20 && book.entries.first?.query == "q5")
        book.record("q10", at: start.addingTimeInterval(100))
        #expect(book.entries.count == 20 && book.entries.last?.query == "q10")
        book.record("  ", at: start.addingTimeInterval(101))
        #expect(book.entries.last?.query == "q10")
        #expect(book.recent(3) == ["q10", "q24", "q23"])
        #expect(book.resumable(at: start.addingTimeInterval(100 + 120)) == "q10")
        #expect(book.resumable(at: start.addingTimeInterval(100 + 360)) == nil)
    }

    @Test func storeWritesAndClears() {
        let store = LauncherHistoryStore(path: tempPath("spec090-history") + ".json")
        store.record("yt chat")
        store.record("github.com")
        #expect(store.load().recent(2) == ["github.com", "yt chat"])
        store.clear()
        #expect(store.load().entries.isEmpty)
    }
}
