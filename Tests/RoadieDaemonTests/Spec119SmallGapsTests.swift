import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

/// Petites reprises d'Alfred (session 119).
struct Spec119SmallGapsTests {
    @Test func openAndFindKeywordsShowOnlyFiles() {
        #expect(LauncherFileQuery.parse("open devis") == LauncherFileQuery(mode: .name, needle: "devis", filesOnly: true))
        #expect(LauncherFileQuery.parse("find devis") == LauncherFileQuery(mode: .name, needle: "devis", filesOnly: true, reveals: true))
        #expect(LauncherFileQuery.parse("opener").filesOnly == false)
        #expect(!LauncherFileQuery.parse("find devis", keywords: LauncherFileKeywords(find: "")).reveals)
    }

    @Test func addedTypesAndExcludedFolders() {
        let predicate = LauncherFileRules.predicate(LauncherFileQuery.parse(" devis"), extraTypes: ["public.archive"]).predicateFormat
        #expect(predicate.contains("public.archive") && predicate.contains("public.folder"))
        let home = "/Users/x"
        #expect(!LauncherFileRules.isShown("/Users/x/Downloads/Archives/a.zip", home: home, excluded: ["~/Downloads/Archives", "/Users/x/Vieux/"]))
        #expect(!LauncherFileRules.isShown("/Users/x/Vieux/b.txt", home: home, excluded: ["/Users/x/Vieux/"]))
        #expect(LauncherFileRules.isShown("/Users/x/Downloads/ArchivesBis/a.zip", home: home, excluded: ["/Users/x/Downloads/Archives"]))
    }

    @Test func calculatorSeparatorAndGrouping() throws {
        let point = try #require(LauncherCalculator.evaluate("1234*2,5", locale: LauncherCalculator.locale("point")))
        #expect(point.text == "3085")
        let decimal = try #require(LauncherCalculator.evaluate("10/4", locale: LauncherCalculator.locale("point")))
        #expect(decimal.text == "2.5")
        let comma = try #require(LauncherCalculator.evaluate("10/4", locale: LauncherCalculator.locale("comma")))
        #expect(comma.text == "2,5")
        let grouped = try #require(LauncherCalculator.evaluate("1000*1234", locale: LauncherCalculator.locale("point"), grouping: true))
        #expect(grouped.text == "1,234,000")
        #expect(TargetModeConfig(calcDecimal: "autre").calcDecimal == "system")
    }

    @Test func scrollThumbFollowsTheVisibleRows() throws {
        let panel = CGRect(x: 0, y: 0, width: 600, height: 216)
        #expect(SearchBarRenderer.scrollThumb(panel: panel, shown: 0..<10, count: 10) == nil)
        let top = try #require(SearchBarRenderer.scrollThumb(panel: panel, shown: 0..<10, count: 40))
        let bottom = try #require(SearchBarRenderer.scrollThumb(panel: panel, shown: 30..<40, count: 40))
        #expect(abs(top.height - 50) < 1 && top.maxY == 208 && abs(bottom.minY - 8) < 0.5)
    }

    @Test func reloadAndSpotlightCommandsExist() throws {
        let commands = LauncherSystemCommand.all()
        #expect(commands.first { $0.id == "reload-apps" }?.confirms == false)
        #expect(commands.first { $0.id == "rebuild-spotlight" }?.confirms == true)
        #expect(LauncherSystemCommand.matches("reload", in: commands).first?.id == "reload-apps")
    }

    @Test func moreBuiltInWebSearchesWithUniqueKeywords() {
        let keywords = WebSearch.defaults.map(\.keyword)
        #expect(keywords.count == 17 && Set(keywords).count == keywords.count)
        #expect(LauncherWeb.keywordSearch("tr bonjour", in: WebSearch.defaults)?.search.title == "Google Traduction")
    }
}
