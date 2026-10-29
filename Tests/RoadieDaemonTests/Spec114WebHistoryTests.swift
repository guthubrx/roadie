import Foundation
import SQLite3
import Testing
import RoadieCore
@testable import RoadieDaemon

/// Historique des navigateurs dans la barre (session 114).
struct Spec114WebHistoryTests {
    private func page(_ title: String, _ url: String, visits: Int) -> LauncherBookmark {
        LauncherWebHistory.page(title: title, url: url, browser: "firefox", profile: "", visits: visits)!
    }

    @Test func onlyWebPagesBecomeHistoryRows() {
        #expect(LauncherWebHistory.page(title: "a", url: "file:///tmp/a", browser: "firefox", profile: "", visits: 1) == nil)
        let github = page("", "https://github.com/", visits: 3)
        #expect(github.title == "https://github.com/" && github.folder == "Historique" && github.isHistory)
        // Une page et un signet de même adresse n'ont pas le même identifiant.
        #expect(github.id == "history:firefox:https://github.com/")
    }

    @Test func matchesSkipBookmarkedPagesAndPreferTheMostVisited() {
        let pages = [page("Guide Roadie", "https://example.com/guide", visits: 2),
                     page("Roadie releases", "https://github.com/guthubrx/roadie/releases", visits: 9),
                     page("Roadie", "https://roadie.example/", visits: 50)]
        let found = LauncherWebHistory.matches("roadie", in: LauncherBookmarkIndex(pages), excluding: ["https://roadie.example"])
        #expect(found.map(\.url) == ["https://github.com/guthubrx/roadie/releases", "https://example.com/guide"])
        #expect(LauncherWebHistory.matches("r", in: LauncherBookmarkIndex(pages), excluding: []).isEmpty)
    }

    @Test func firefoxPlacesAreReadWithinTheWindow() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("spec114-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var db: OpaquePointer?
        #expect(sqlite3_open(folder.appendingPathComponent("places.sqlite").path, &db) == SQLITE_OK)
        let now = Date()
        let recent = Int64(now.addingTimeInterval(-86_400).timeIntervalSince1970 * 1_000_000)
        let old = Int64(now.addingTimeInterval(-200 * 86_400).timeIntervalSince1970 * 1_000_000)
        let sql = """
        CREATE TABLE moz_places (url TEXT, title TEXT, visit_count INTEGER, last_visit_date INTEGER, hidden INTEGER, frecency INTEGER);
        INSERT INTO moz_places VALUES ('https://recent.example/', 'Récente', 4, \(recent), 0, 10);
        INSERT INTO moz_places VALUES ('https://old.example/', 'Ancienne', 9, \(old), 0, 20);
        INSERT INTO moz_places VALUES ('https://hidden.example/', 'Cachée', 1, \(recent), 1, 30);
        """
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        let pages = LauncherWebHistory.firefox(FirefoxProfiles.Profile(path: folder, name: "Moi"), label: "Moi",
                                               since: now.addingTimeInterval(-90 * 86_400))
        #expect(pages.map(\.title) == ["Récente"])
        #expect(pages.first?.visits == 4 && pages.first?.profile == "Moi")
    }

    @Test func settingKeepsNinetyDaysByDefault() throws {
        #expect(TargetModeConfig().webHistoryDays == 90)
        #expect(TargetModeConfig(webHistoryDays: 999).webHistoryDays == 365)
        let entry = try #require(SettingsCatalog.all.first { $0.tablePath == "experimental.target_mode" && $0.key == "web_history_days" })
        #expect(entry.category == .recherche && entry.defaultValue == .int(90))
    }
}
