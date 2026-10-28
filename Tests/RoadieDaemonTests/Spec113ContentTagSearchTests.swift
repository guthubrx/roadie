import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

/// Recherche dans le contenu et par étiquette Finder (`in`, `tags`, session 113).
struct Spec113ContentTagSearchTests {
    @Test func keywordsNeedASpaceAndOnlyShowFiles() {
        let content = LauncherFileQuery.parse("in facture mars")
        #expect(content == LauncherFileQuery(mode: .content, needle: "facture mars", filesOnly: true))
        #expect(LauncherFileQuery.parse("Tags Rouge") == LauncherFileQuery(mode: .tag, needle: "Rouge", filesOnly: true))
        // `inbox`, `tagsy` : des noms ordinaires.
        #expect(LauncherFileQuery.parse("inbox") == LauncherFileQuery(mode: .name, needle: "inbox", filesOnly: false))
        #expect(LauncherFileQuery.parse("tagsy").mode == .name)
        #expect(LauncherFileQuery.parse(" rap") == LauncherFileQuery(mode: .name, needle: "rap", filesOnly: true))
    }

    @Test func keywordsFollowTheSettingsAndCanBeTurnedOff() {
        let french = LauncherFileKeywords(content: "dans", tag: "")
        #expect(LauncherFileQuery.parse("dans devis", keywords: french).mode == .content)
        #expect(LauncherFileQuery.parse("in devis", keywords: french).mode == .name)
        #expect(LauncherFileQuery.parse("tags rouge", keywords: french).mode == .name)
        #expect(LauncherFileRules.shouldSearch("in de") && !LauncherFileRules.shouldSearch("in d"))
    }

    @Test func contentMatchesEachWordAsTheStartOfAWord() {
        let predicate = LauncherFileRules.predicate(LauncherFileQuery.parse("in fac\"ture *mars")).predicateFormat
        // Spotlight relit la requête en « commence par » ; guillemet et étoile tapés restent du texte.
        #expect(predicate.contains(#"kMDItemTextContent BEGINSWITH[cdlw] "fac\"ture""#))
        #expect(predicate.contains(#"kMDItemTextContent BEGINSWITH[cdlw] "*mars""#))
    }

    @Test func frenchColoursAlsoLookForTheirEnglishName() {
        let predicate = LauncherFileRules.predicate(LauncherFileQuery.parse("tags rouge")).predicateFormat
        #expect(predicate.contains(#"BEGINSWITH[cdl] "rouge""#) && predicate.contains(#"BEGINSWITH[cdl] "Red""#))
        #expect(!LauncherFileRules.predicate(LauncherFileQuery.parse("tags projet")).predicateFormat.contains("Red"))
    }

    @Test func onlineStorageFoldersAreSearchedButNotTheRestOfLibrary() {
        let home = "/Users/x"
        #expect(LauncherFileRules.isShown("/Users/x/Library/CloudStorage/OneDrive-Perso/devis.pdf", home: home))
        #expect(LauncherFileRules.isShown("/Users/x/Library/Mobile Documents/com~apple~CloudDocs/a.txt", home: home))
        #expect(!LauncherFileRules.isShown("/Users/x/Library/Caches/a.txt", home: home))
    }

    @Test func listShowsOnlyFilesForAContentSearch() {
        let app = LauncherApp(bundleID: "com.apple.Notes", path: "/System/Applications/Notes.app", name: "Notes", alternateNames: [])
        let file = LauncherFile(path: "/Users/x/devis.pdf", name: "devis.pdf", isFolder: false, lastUsed: nil)
        let list = LauncherList(query: "in notes", apps: [app], details: [:], targets: [], ranking: LauncherRanking(), now: Date(),
                                files: [file])
        #expect(list.rows.contains { if case .file = $0 { true } else { false } })
        #expect(!list.rows.contains { if case .app = $0 { true } else { false } })
    }

    @Test func settingsSitInSearch() {
        let keys = SettingsCatalog.all.filter { $0.tablePath == "experimental.target_mode" && $0.key.hasSuffix("_search_keyword") }
        #expect(keys.map(\.key) == ["content_search_keyword", "tag_search_keyword"])
        #expect(TargetModeConfig().contentSearchKeyword == "in" && TargetModeConfig().tagSearchKeyword == "tags")
    }
}
