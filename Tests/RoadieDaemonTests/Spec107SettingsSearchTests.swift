import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

/// Session 107 : la recherche des paramètres filtre la colonne de gauche.
@Suite
@MainActor
struct Spec107SettingsSearchTests {
    private func makeModel() throws -> SettingsViewModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-107-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = directory.appendingPathComponent("roadies.toml")
        try "[fx.borders]\nenabled = false\n".write(to: config, atomically: true, encoding: .utf8)
        let service = SettingsService(configPath: config.path, eventLog: EventLog(path: directory.appendingPathComponent("e.jsonl").path), afterWrite: {})
        return SettingsViewModel(service: service)
    }

    @Test func searchFindsCategoryAndGroupNames() {
        // « Vue d'ensemble » n'apparaît ni dans les libellés ni dans les aides de tous ses réglages.
        let overview = SettingsCatalog.descriptors(in: .overview).map(\.id)
        #expect(Set(SettingsCatalog.search("vue d’ensemble").map(\.id)).isSuperset(of: overview))
        // Nom d'un groupe : « Perspective » du rail.
        #expect(SettingsCatalog.search("perspective").contains { $0.id.contains("parallax.") })
    }

    @Test func sidebarListsOnlyMatchingCategoriesAndFocusRestrictsTheDetail() throws {
        let model = try makeModel()
        model.query = "police"
        let categories = model.searchResults.map(\.category)
        #expect(categories.count > 1)
        #expect(categories.count < SettingCategory.allCases.count)
        #expect(model.sections.map(\.category) == categories)

        let chosen = try #require(categories.last)
        model.searchFocus = chosen
        #expect(model.sections.map(\.category) == [chosen])
        #expect(model.searchResults.map(\.category) == categories)

        // Nouvelle saisie : tous les résultats reviennent.
        model.query = "polices"
        #expect(model.searchFocus == nil)
        model.query = ""
        #expect(model.searchResults.isEmpty)
    }

    @Test func aBroadSearchListsEveryResultAsLazyItems() throws {
        let model = try makeModel()
        model.query = "p"
        let total = model.searchResults.reduce(0) { $0 + $1.descriptors.count }
        #expect(total > 100)
        let items = SettingsDetailItem.items(model.sections)
        #expect(items.filter { if case .row = $0.kind { return true }; return false }.count == total)
        #expect(Set(items.map(\.id)).count == items.count)
        // Chaque carte commence et finit par une ligne arrondie.
        let rows = items.compactMap { item -> (Bool, Bool)? in if case .row(_, let first, let last) = item.kind { return (first, last) }; return nil }
        #expect(rows.filter(\.0).count == rows.filter(\.1).count)
    }
}
