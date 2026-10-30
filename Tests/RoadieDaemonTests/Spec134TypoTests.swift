import Foundation
import RoadieCore
import Testing
import TOMLKit
@testable import RoadieDaemon

/// Session 134 : fautes de frappe rattrapées, toujours après les correspondances exactes.
struct Spec134TypoTests {
    private func target(_ id: String, _ title: String) -> RoadieTarget {
        RoadieTarget(id: "app:\(id)", label: id, kind: .appElement, title: title, source: .app,
                     frame: Rect(x: 0, y: 0, width: 20, height: 20), actions: [.click])
    }

    private func app(_ name: String) -> LauncherApp {
        LauncherApp(bundleID: "test.\(name.lowercased())", path: "/Applications/\(name).app", name: name, alternateNames: [])
    }

    @Test func errorsAreCountedPerPassage() {
        #expect(TypoMatch.allowedErrors(forLength: 3, max: 2) == 0)
        #expect(TypoMatch.allowedErrors(forLength: 4, max: 2) == 1 && TypoMatch.allowedErrors(forLength: 7, max: 2) == 1)
        #expect(TypoMatch.allowedErrors(forLength: 8, max: 2) == 2 && TypoMatch.allowedErrors(forLength: 8, max: 1) == 1)
        #expect(TypoMatch.allowedErrors(forLength: 12, max: 0) == 0)
        // Inversion, oubli, lettre en trop, lettre remplacée : une faute chacune, n'importe où dans le texte.
        #expect(TypoMatch.distance("fierfox", in: "Firefox", setting: 2) == 1)
        #expect(TypoMatch.distance("sfari", in: "Safari", setting: 2) == 1)
        #expect(TypoMatch.distance("enregsitrer", in: "Fichier › Enregistrer sous…", setting: 2) == 1)
        #expect(TypoMatch.distance("mesagges", in: "Messages", setting: 2) == 2)
        // Trop court, trop fautif, ou réglage coupé : rien.
        #expect(TypoMatch.distance("fix", in: "Firefox", setting: 2) == nil)
        #expect(TypoMatch.distance("zzzz", in: "Firefox", setting: 2) == nil)
        #expect(TypoMatch.distance("fierfox", in: "Firefox", setting: 0) == nil)
    }

    @Test func screenSearchFallsBackOnlyWithoutExactMatch() {
        let targets = [target("A", "Enregistrer"), target("S", "Envoyer"), target("D", "Annuler")]
        var strict = TargetSearchModel(targets: targets)
        strict.type("enregsitrer")
        #expect(strict.matches.isEmpty && !strict.corrected)

        var model = TargetSearchModel(targets: targets)
        model.typoMaxErrors = 2
        model.type("enregsitrer")
        #expect(model.matches.map(\.title) == ["Enregistrer"] && model.corrected)
        #expect(model.highlighted?.title == "Enregistrer")
        // Une correspondance exacte, même partielle, garde la main : rien n'est rattrapé.
        model.replaceQuery("envo")
        #expect(model.matches.map(\.title) == ["Envoyer"] && !model.corrected)
    }

    @Test func launcherAddsDidYouMeanLastAndOnlyWhenExactIsShort() {
        let apps = [app("Firefox"), app("Safari"), app("Messages")]
        func list(_ query: String, apps: [LauncherApp], typos: Int = 2) -> LauncherList {
            LauncherList(query: query, apps: apps, details: [:], targets: [], ranking: LauncherRanking(), now: Date(), typoMaxErrors: typos)
        }
        func headers(_ list: LauncherList) -> [String] { list.rows.compactMap { if case .header(let title) = $0 { title } else { nil } } }
        func names(_ list: LauncherList) -> [String] { list.rows.compactMap { if case .app(let app, _) = $0 { app.name } else { nil } } }
        let typo = list("fierfox", apps: apps)
        #expect(headers(typo) == ["Vouliez-vous dire"] && names(typo) == ["Firefox"])
        #expect(typo.best == app("Firefox").rankingKey)
        // Exact : aucune section de fautes.
        #expect(!headers(list("fire", apps: apps)).contains("Vouliez-vous dire"))
        // Trois correspondances exactes ou plus : la section n'apparaît pas.
        let many = (1...3).map { app("Fierfox \($0)") } + apps
        #expect(!headers(list("fierfox", apps: many)).contains("Vouliez-vous dire"))
        // Moins de trois : elle vient en dernier, et la meilleure ligne reste exacte.
        let mixed = list("fierfox", apps: [app("Fierfox Nightly")] + apps)
        #expect(headers(mixed) == ["Applications", "Vouliez-vous dire"] && names(mixed) == ["Fierfox Nightly", "Firefox"])
        #expect(mixed.best == app("Fierfox Nightly").rankingKey)
        // Réglage coupé : rien n'est rattrapé.
        #expect(list("fierfox", apps: apps, typos: 0).rows.isEmpty)
    }

    @Test func settingIsClampedAndListed() throws {
        #expect(TargetModeConfig().typoMaxErrors == 2)
        let config = try TOMLDecoder().decode(RoadieConfig.self, from: "[experimental.target_mode]\ntypo_max_errors = 7\n")
        #expect(config.experimental.targetMode.typoMaxErrors == 2)
        #expect(SettingsCatalog.find(id: "target_mode.typo_max_errors")?.category == .recherche)
    }
}
