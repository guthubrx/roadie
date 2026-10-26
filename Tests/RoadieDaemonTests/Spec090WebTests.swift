import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

struct Spec090WebTests {
    @Test func typedAddresses() {
        #expect(LauncherWeb.address("github.com/guthubrx")?.absoluteString == "https://github.com/guthubrx")
        #expect(LauncherWeb.address("example.com")?.absoluteString == "https://example.com")
        #expect(LauncherWeb.address("www.lemonde.fr")?.absoluteString == "https://www.lemonde.fr")
        #expect(LauncherWeb.address("http://intra.local:8080/x")?.absoluteString == "http://intra.local:8080/x")
        #expect(LauncherWeb.address("localhost:3000")?.absoluteString == "http://localhost:3000")
        #expect(LauncherWeb.address("192.168.1.1")?.absoluteString == "http://192.168.1.1")
        #expect(LauncherWeb.address("readme.md/")?.absoluteString == "https://readme.md/")
        for text in ["fichier.txt", "a.b", "readme.md", "Safari.app", "run.sh", "fire perso", "localhost", "1.2", "12*4,5", "~/Doc", "https://"] {
            #expect(LauncherWeb.address(text) == nil, "\(text)")
        }
    }

    @Test func keywordSearchesAndFallbacks() throws {
        let searches = WebSearch.defaults
        let youtube = try #require(LauncherWeb.keywordSearch("yt chat noir", in: searches))
        #expect(youtube.search.title == "YouTube" && youtube.text == "chat noir")
        #expect(LauncherWeb.keywordSearch("yt ", in: searches)?.text == "")
        #expect(LauncherWeb.keywordSearch("yt", in: searches) == nil)
        #expect(LauncherWeb.keywordSearch("zz chat", in: searches) == nil)
        let rows = LauncherWeb.fallbackRows("zzqx", template: TargetModeConfig.defaultWebSearchURL, searches: searches, fallbacks: ["wp", "g", "absent"])
        #expect(rows.map(\.title) == ["Rechercher « zzqx » sur Google", "Rechercher « zzqx » sur Wikipédia"])
        #expect(LauncherWeb.fallbackRows("  ", template: TargetModeConfig.defaultWebSearchURL, searches: searches, fallbacks: []).isEmpty)
        #expect(LauncherWeb.engineName("https://www.qwant.com/?q={query}", searches: []) == "Qwant")
        // Le repli ne prend pas la sélection d'une liste qui a déjà des lignes.
        var list = LauncherList.idle([.header("Applications"), .history("x")])
        list.appendSection("Web", rows.map(LauncherList.Row.web))
        #expect(list.best == "history:x")
        var empty = LauncherList.empty
        empty.appendSection("Web", rows.map(LauncherList.Row.web))
        #expect(empty.best == rows[0].id)
    }

    @Test func configReadsSearchesFromToml() throws {
        let path = tempPath("spec090") + ".toml"
        try """
        [experimental.target_mode]
        fallback_searches = ["yt"]

        [[experimental.target_mode.web_searches]]
        keyword = "gh"
        title = "GitHub"
        url = "https://github.com/search?q={query}"
        """.write(toFile: path, atomically: true, encoding: .utf8)
        let config = try RoadieConfigLoader.load(from: path).experimental.targetMode
        #expect(config.webSearches == [WebSearch(keyword: "gh", title: "GitHub", url: "https://github.com/search?q={query}")])
        #expect(config.fallbackSearches == ["yt"])
        #expect(TargetModeConfig().webSearches == nil)
    }

    @Test func urlSubjectVerbsAndVariants() {
        let url = URL(string: "https://github.com/x")!
        #expect(LauncherVerb.verbs(for: .url(url)) == [.open, .openIn, .bringHere, .copyPath])
        let variant = LauncherVariant.of(.url(url), modifier: .command, query: "github.com/x",
                                         newStageHome: (DisplayID(rawValue: "A"), DesktopID(rawValue: 1)), activeStage: nil)
        #expect(variant?.title == "⌘ ↩ Ouvrir dans une nouvelle stage")
        #expect(LauncherSubject.url(url).rankingKey == "url:github.com")
    }
}
