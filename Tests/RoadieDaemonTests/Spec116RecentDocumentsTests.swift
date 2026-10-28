import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

/// Documents récents d'une application (session 116).
struct Spec116RecentDocumentsTests {
    private let word = LauncherSubject.app(LauncherApp(bundleID: "com.microsoft.Word", path: "/Applications/Microsoft Word.app",
                                                       name: "Microsoft Word", alternateNames: []))

    private func tempFile(_ name: String, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        return url
    }

    @Test func macOSListGivesPathsFromBookmarksInOrder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("spec116-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try tempFile("devis.txt", in: folder), second = try tempFile("notes.txt", in: folder)
        let items = try [first, second].map { ["Bookmark": try $0.bookmarkData(), "uuid": UUID().uuidString] as NSDictionary }
        let data = try NSKeyedArchiver.archivedData(withRootObject: ["items": items, "properties": [:]] as NSDictionary,
                                                    requiringSecureCoding: false)
        let documents = LauncherRecentDocuments.sharedList(data)
        #expect(documents.map(\.name) == ["devis.txt", "notes.txt"])
        #expect(LauncherRecentDocuments.sharedList(Data("pas une archive".utf8)).isEmpty)
    }

    @Test func officeListIsSortedByLastUse() {
        let plist: [String: Any] = [
            "file:///Users/x/ancien.docx": ["kLastUsedDateKey": Date(timeIntervalSince1970: 100)],
            "file:///Users/x/Rapport%20final.docx": ["kLastUsedDateKey": Date(timeIntervalSince1970: 900)],
            "https://example.com/x.docx": ["kLastUsedDateKey": Date()],
        ]
        #expect(LauncherRecentDocuments.officeList(plist).map(\.name) == ["Rapport final.docx", "ancien.docx"])
        #expect(LauncherRecentDocuments.office(bundleID: "com.apple.Preview", home: "/nonexistent").isEmpty)
    }

    @Test func documentsKeepExistingFilesOnceAndAtMostTwenty() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("spec116-home-\(UUID().uuidString)")
        let preferences = home.appendingPathComponent("Library/Containers/com.microsoft.Word/Data/Library/Preferences")
        try FileManager.default.createDirectory(at: preferences, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        var plist: [String: Any] = [:]
        for index in 0..<30 { plist["file:///docs/\(index).docx"] = ["kLastUsedDateKey": Date(timeIntervalSince1970: Double(index))] }
        plist["file:///docs/disparu.docx"] = ["kLastUsedDateKey": Date()]
        (plist as NSDictionary).write(to: preferences.appendingPathComponent("com.microsoft.Word.securebookmarks.plist"), atomically: true)
        let documents = LauncherRecentDocuments.documents(bundleID: "com.microsoft.Word", home: home.path) { !$0.contains("disparu") }
        #expect(documents.count == 20 && documents.first?.name == "29.docx")
    }

    @Test func verbListsDocumentsAsTheThirdStep() {
        #expect(LauncherVerb.verbs(for: word).contains(.recentDocuments) && LauncherVerb.recentDocuments.needsDestination)
        #expect(LauncherVerb.primaryDestinationVerb(for: word) == .openIn)
        let documents = LauncherRecentDocuments.destinations([.init(path: "/Users/x/devis.docx", lastUsed: nil),
                                                              .init(path: "/Users/x/notes.docx", lastUsed: nil)])
        let home = (DisplayID(rawValue: "A"), DesktopID(rawValue: 1))
        let all = LauncherActionList.destinations(for: word, verb: .recentDocuments, query: "", destinations: documents, newStageHome: home)
        #expect(all.rows.first == .header("Microsoft Word › Documents récents"))
        #expect(all.rows.count == 3)
        let typed = LauncherActionList.destinations(for: word, verb: .recentDocuments, query: "dev", destinations: documents, newStageHome: home)
        #expect(typed.rows.dropFirst().map(\.id) == ["destination:recentDocuments:document:/Users/x/devis.docx"])
        // Un document n'est jamais une destination d'« Envoyer vers ».
        let send = LauncherActionList.destinations(for: word, verb: .sendTo, query: "", destinations: documents, newStageHome: home)
        #expect(!send.rows.contains { if case .destination(_, let d) = $0, case .document = d.kind { true } else { false } })
    }
}
