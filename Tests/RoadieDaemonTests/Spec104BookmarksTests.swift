import Compression
import Foundation
import RoadieCore
import SQLite3
import Testing
@testable import RoadieDaemon

/// Session 104 : signets de Firefox, Safari et Chrome, onglets ouverts de Firefox.
@Suite(.serialized)
struct Spec104BookmarksTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-104-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func execute(_ database: URL, _ sql: String) throws {
        var handle: OpaquePointer?
        try #require(sqlite3_open(database.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        try #require(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
    }

    @Test func firefoxBookmarksKeepTheirFoldersTagsAndKeywords() throws {
        let profile = try folder()
        defer { try? FileManager.default.removeItem(at: profile) }
        try execute(profile.appendingPathComponent("places.sqlite"), """
        CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT);
        CREATE TABLE moz_bookmarks (id INTEGER PRIMARY KEY, type INTEGER, fk INTEGER, parent INTEGER, title TEXT, guid TEXT);
        CREATE TABLE moz_keywords (id INTEGER PRIMARY KEY, keyword TEXT, place_id INTEGER);
        INSERT INTO moz_places VALUES (1, 'https://github.com/'), (2, 'https://fr.wikipedia.org/w/index.php?search=%s'), (3, 'place:sort=8');
        INSERT INTO moz_bookmarks VALUES (1, 2, NULL, 0, '', 'root________'), (3, 2, NULL, 1, 'toolbar', 'toolbar_____'),
          (4, 2, NULL, 1, 'tags', 'tags________'), (10, 2, NULL, 3, 'Outils', 'f1'), (11, 1, 1, 10, 'GitHub', 'b1'),
          (12, 1, 2, 3, 'Wikipédia', 'b2'), (13, 1, 3, 3, 'Récents', 'b3'), (20, 2, NULL, 4, 'code', 't1'), (21, 1, 1, 20, NULL, 't2');
        INSERT INTO moz_keywords VALUES (1, 'w', 2);
        """)
        let bookmarks = FirefoxBookmarks.read(FirefoxProfiles.Profile(path: profile, name: "Moi"), profileLabel: "Moi")
        #expect(bookmarks.count == 2)
        let github = try #require(bookmarks.first { $0.title == "GitHub" })
        #expect(github.folder == "Barre personnelle › Outils")
        #expect(github.tags == ["code"])
        #expect(github.detail == "Firefox · Moi · Barre personnelle › Outils")
        #expect(github.score("code") != nil)
        let wiki = try #require(bookmarks.first { $0.keyword == "w" })
        let searches = LauncherBookmark.keywordSearches(bookmarks, taken: ["g"])
        #expect(searches == [WebSearch(keyword: "w", title: "Wikipédia", url: "https://fr.wikipedia.org/w/index.php?search={query}")])
        #expect(LauncherBookmark.keywordSearches([wiki], taken: ["w"]).isEmpty)
    }

    @Test func firefoxProfilesComeFromTheIniAndTheProfileGroups() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["Profiles/a.default", "Profiles/b.Profile 1", "Profiles/c.vide"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        FileManager.default.createFile(atPath: root.appendingPathComponent("Profiles/a.default/places.sqlite").path, contents: Data())
        FileManager.default.createFile(atPath: root.appendingPathComponent("Profiles/b.Profile 1/places.sqlite").path, contents: Data())
        try "[General]\nVersion=2\n\n[Profile0]\nName=default\nIsRelative=1\nPath=Profiles/a.default\n\n[Profile1]\nName=vide\nPath=Profiles/c.vide\n"
            .write(to: root.appendingPathComponent("profiles.ini"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Profile Groups"), withIntermediateDirectories: true)
        try execute(root.appendingPathComponent("Profile Groups/x.sqlite"),
                    "CREATE TABLE Profiles (id INTEGER, path TEXT, name TEXT); INSERT INTO Profiles VALUES (1, 'Profiles/b.Profile 1', 'Moi');")
        let profiles = FirefoxProfiles.all(root: root)
        #expect(profiles.map(\.name) == ["Moi", "default"])
        #expect(FirefoxProfiles.iniProfiles("[Profile3]\nPath=/abs/p\nName=x\n[Install1]\nDefault=y").map(\.path) == ["/abs/p"])
    }

    @Test func chromiumAndSafariBookmarksAreRead() throws {
        let chrome = """
        {"roots":{"bookmark_bar":{"type":"folder","name":"Bar","children":[{"type":"url","name":"Roadie","url":"https://example.org/roadie"},
        {"type":"folder","name":"Dev","children":[{"type":"url","name":"","url":"https://swift.org"}]}]},
        "other":{"type":"folder","children":[]},"synced":{"type":"folder","children":[]}}}
        """
        let found = ChromiumBookmarks.read(Data(chrome.utf8), browser: "chrome", profile: "")
        #expect(found.map(\.title) == ["Roadie", "https://swift.org"])
        #expect(found.last?.folder == "Barre de favoris › Dev")
        let safari: [String: Any] = ["Title": "", "WebBookmarkType": "WebBookmarkTypeList", "Children": [
            ["Title": "History", "WebBookmarkType": "WebBookmarkTypeProxy"],
            ["Title": "BookmarksBar", "WebBookmarkType": "WebBookmarkTypeList", "Children": [
                ["WebBookmarkType": "WebBookmarkTypeLeaf", "URLString": "https://apple.com", "URIDictionary": ["title": "Apple"]]]],
        ]]
        let data = try PropertyListSerialization.data(fromPropertyList: safari, format: .binary, options: 0)
        let read = SafariBookmarks.read(data)
        #expect(read.map(\.title) == ["Apple"])
        #expect(read.first?.folder == "Barre des favoris")
    }

    @Test func matchingPrefersTitlesAndDropsDuplicates() {
        let one = LauncherBookmark(title: "GitHub", url: "https://github.com/", folder: "", browser: "firefox", profile: "Moi")
        let two = LauncherBookmark(title: "GitHub", url: "https://github.com", folder: "", browser: "chrome", profile: "")
        let three = LauncherBookmark(title: "Forge", url: "https://git.example.org", folder: "", browser: "safari", profile: "")
        #expect(LauncherBookmark.matches("git", in: [three, one, two]).map(\.title) == ["GitHub", "Forge"])
        #expect(LauncherBookmark.matches("g", in: [one]).isEmpty)
        let row = LauncherWebRow(kind: .bookmark(one), title: one.title)
        #expect(row.url == URL(string: "https://github.com/"))
        #expect(row.id == "bookmark:firefox:https://github.com/")
    }

    @Test func firefoxSessionTabsAreDecoded() throws {
        let session = """
        {"windows":[{"selected":2,"screenX":10,"screenY":20,"width":800,"height":600,"tabs":[
          {"index":1,"entries":[{"url":"https://a.example","title":"A"}]},
          {"index":2,"entries":[{"url":"https://old.example","title":"Old"},{"url":"https://b.example","title":"B"}]},
          {"index":1,"hidden":true,"entries":[{"url":"https://c.example","title":"C"}]}]}]}
        """
        let json = Data(session.utf8)
        var compressed = Data(count: json.count + 64)
        let size = compressed.withUnsafeMutableBytes { destination in
            json.withUnsafeBytes { source in
                compression_encode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, json.count + 64,
                                          source.bindMemory(to: UInt8.self).baseAddress!, json.count, nil, COMPRESSION_LZ4_RAW)
            }
        }
        var file = Data("mozLz40\0".utf8)
        withUnsafeBytes(of: UInt32(json.count).littleEndian) { file.append(contentsOf: $0) }
        file.append(compressed.prefix(size))
        let decoded = try #require(FirefoxSession.decompress(file))
        #expect(decoded == json)
        let tabs = FirefoxSession.tabs(decoded, profile: "")
        #expect(tabs.map(\.title) == ["A", "B"])
        #expect(tabs.last?.isActive == true)
        #expect(tabs.last?.bounds == CGRect(x: 10, y: 20, width: 800, height: 600))
        #expect(FirefoxSession.decompress(Data("pas un fichier".utf8)) == nil)
    }

    @Test func svgIconsAreIgnoredAndUnknownBrowsersDropped() {
        #expect(LauncherBookmarkStore.isSVG(Data("<svg xmlns='x'/>".utf8)))
        #expect(!LauncherBookmarkStore.isSVG(Data([0x89, 0x50, 0x4E, 0x47])))
        #expect(TargetModeConfig(bookmarkBrowsers: ["firefox", "netscape"]).bookmarkBrowsers == ["firefox"])
    }
}
