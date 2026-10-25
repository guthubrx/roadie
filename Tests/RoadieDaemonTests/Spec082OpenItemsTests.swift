import CoreGraphics
import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

struct Spec082BrowserTests {
    @Test func appleScriptOutputIsReadLineByLine() {
        let output = "1\t0\t25\t1200\t800\t1\tfalse\tAccueil\thttps://a.org/\n"
            + "1\t0\t25\t1200\t800\t2\ttrue\tFacture\tEDF\thttps://edf.fr/facture\n"
            + "ligne cassée\n"
        let tabs = LauncherBrowsers.parse(output)
        #expect(tabs.count == 2)
        #expect(tabs[1] == LauncherBrowsers.Tab(window: 1, bounds: CGRect(x: 0, y: 25, width: 1200, height: 775), index: 2,
                                                 isActive: true, title: "Facture\tEDF", url: "https://edf.fr/facture"))
    }

    @Test func aTabFindsItsWindowByFrame() {
        let windows = [(WindowID(rawValue: 4), CGRect(x: 0, y: 25, width: 1200, height: 775)),
                       (WindowID(rawValue: 5), CGRect(x: 1300, y: 0, width: 600, height: 400))]
        #expect(LauncherBrowsers.window(matching: CGRect(x: 1, y: 26, width: 1199, height: 774), among: windows) == WindowID(rawValue: 4))
        #expect(LauncherBrowsers.window(matching: CGRect(x: 900, y: 0, width: 600, height: 400), among: windows) == nil)
    }

    @Test func onlyScriptableBrowsersGetAScript() throws {
        #expect(LauncherBrowsers.listScript(bundleID: "org.mozilla.firefox") == nil)
        let chrome = try #require(LauncherBrowsers.listScript(bundleID: "com.google.Chrome"))
        #expect(chrome.contains("active tab index of w") && chrome.contains("title of t"))
        let safari = try #require(LauncherBrowsers.listScript(bundleID: LauncherBrowsers.safari))
        #expect(safari.contains("index of current tab of w") && safari.contains("name of t"))
        #expect(LauncherBrowsers.activateScript(bundleID: "com.google.Chrome", window: 2, tab: 5).contains("set active tab index of window 2 to 5"))
    }
}

struct Spec082ListTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func item(_ kind: LauncherOpenItem.Kind, _ title: String, url: String? = nil) -> LauncherOpenItem {
        LauncherOpenItem(kind: kind, windowID: WindowID(rawValue: 9), bundleID: "b", appName: "Aperçu", title: title,
                         detail: "Aperçu · ~/Documents · Perso", url: url, browserWindow: kind == .tab ? 1 : nil, tabIndex: kind == .tab ? 3 : nil)
    }

    @Test func documentsAndTabsAreFoundByNameTitleOrAddress() {
        let items = [item(.document, "facture-2026-10.pdf"), item(.tab, "Mon espace client", url: "https://edf.fr/facture"),
                     item(.tab, "Météo", url: "https://meteo.fr")]
        let list = LauncherList(query: "facture", apps: [], details: [:], targets: [], ranking: LauncherRanking(), now: now, openItems: items)
        #expect(list.rows.first == .header("Documents et onglets"))
        let titles = list.rows.compactMap { if case .openItem(let item) = $0 { return item.title } else { return nil } }
        #expect(Set(titles) == ["facture-2026-10.pdf", "Mon espace client"])
        #expect(item(.tab, "x", url: "https://edf.fr").score("ed") == nil)
    }
}
