import Foundation
import Testing
@testable import RoadieDaemon

/// Session 131 : grille Apps (Launchpad d'Alfred 6).
struct Spec131AppsGridTests {
    private func app(_ id: String, _ name: String, _ category: String) -> LauncherApp {
        var app = LauncherApp(bundleID: id, path: "/Applications/\(name).app", name: name, alternateNames: [])
        app.category = category
        return app
    }

    @Test func queryAndCategories() {
        #expect(LauncherAppsGrid.query("apps") == "" && LauncherAppsGrid.query("Apps mus") == "mus")
        #expect(LauncherAppsGrid.query("launchpad x") == "x" && LauncherAppsGrid.query("appstore") == nil)
        #expect(LauncherAppsGrid.categoryName("public.app-category.productivity") == "Productivité")
        #expect(LauncherAppsGrid.categoryName("public.app-category.puzzle-games") == "Jeux")
        #expect(LauncherAppsGrid.categoryName("") == "Autres")
    }

    @Test func sectionsPutPinsFirstThenCategoriesAndOthersLast() {
        let apps = [app("a.notes", "Notes", "public.app-category.productivity"), app("a.music", "Musique", "public.app-category.music"),
                    app("a.tool", "Outil", ""), app("a.pages", "Pages", "public.app-category.productivity")]
        let sections = LauncherAppsGrid.sections(apps: apps, query: "", pins: ["a.pages", "absent"])
        #expect(sections.map(\.title) == ["Épinglées", "Musique", "Productivité", "Autres"])
        #expect(sections[0].apps.map(\.name) == ["Pages"] && sections[2].apps.map(\.name) == ["Notes"])
        #expect(LauncherAppsGrid.sections(apps: apps, query: "mus", pins: []).map(\.title) == ["Musique"])
    }

    @Test func pinsToggleAndAppsOpenInGrid() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("spec131-pins-\(UUID().uuidString).json").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let pins = LauncherAppsPins(path: path)
        #expect(pins.toggle("a") && pins.toggle("b") && !pins.toggle("a"))
        #expect(pins.load() == ["b"])
        #expect(LauncherViewBook().mode(for: .apps) == .grid && LauncherViewBook().mode(for: .files) == .list)
        var book = LauncherViewBook()
        book.set(.list, for: .apps)
        #expect(book.mode(for: .apps) == .list)
    }
}
