import Foundation
import Testing
import RoadieDaemon

@Suite
struct SlashCommandCatalogTests {
    // MARK: - Une ligne par commande et par forme du contrat (SC-004)

    static let parseCases: [(String, SlashInvocation)] = [
        ("move gauche", .router(argv: ["move", "left"])),
        ("move right", .router(argv: ["move", "right"])),
        ("swap haut", .router(argv: ["window", "swap", "up"])),
        ("resize bas", .router(argv: ["resize", "down"])),
        ("full", .router(argv: ["toggle", "native-fullscreen"])),
        ("max", .router(argv: ["toggle", "maximize"])),
        ("stage 3", .router(argv: ["stage", "switch", "3"])),
        ("s 2", .router(argv: ["stage", "switch", "2"])),
        ("stage travail", .stageSwitchByName("travail")),
        ("stage Mon projet", .stageSwitchByName("Mon projet")),
        ("stage new", .stageCreate(name: nil)),
        ("stage new  Courrier  ", .stageCreate(name: "Courrier")),
        ("stage rename Nouveau nom", .stageRename("Nouveau nom")),
        ("stage send 4", .router(argv: ["stage", "assign", "4"])),
        ("screen droite", .router(argv: ["display", "focus", "right"])),
        ("screen 2", .router(argv: ["display", "focus", "2"])),
        ("send 2", .router(argv: ["window", "display", "2"])),
        ("desktop 3", .router(argv: ["desktop", "focus", "3"])),
        ("d 3", .router(argv: ["desktop", "focus", "3"])),
        ("layout bsp", .router(argv: ["mode", "bsp"])),
        ("layout spatial", .router(argv: ["mode", "spatialBsp"])),
        ("layout master", .router(argv: ["mode", "masterStack"])),
        ("layout float", .router(argv: ["mode", "float"])),
        ("balance", .router(argv: ["balance"])),
        ("split h", .router(argv: ["layout", "split", "horizontal"])),
        ("split v", .router(argv: ["layout", "split", "vertical"])),
        ("bm travail", .router(argv: ["bookmark", "jump", "travail"])),
        ("b a", .router(argv: ["bookmark", "jump", "a"])),
        ("bm set travail", .router(argv: ["bookmark", "set", "travail"])),
        ("grid", .routerDeferred(argv: ["grid", "interactive", "--scope", "display"])),
        ("grid fenêtre", .routerDeferred(argv: ["grid", "interactive", "--scope", "focused_window"])),
        ("grid fenetre", .routerDeferred(argv: ["grid", "interactive", "--scope", "focused_window"])),
        ("grid window", .routerDeferred(argv: ["grid", "interactive", "--scope", "focused_window"])),
        ("letters", .routerDeferred(argv: ["targets", "interactive", "--source", "all", "--include-app-targets"])),
        ("doctor", .routerInfo(argv: ["doctor"])),
        ("heal", .router(argv: ["daemon", "heal"])),
        ("reload", .router(argv: ["config", "reload"])),
        ("restart", .routerDeferred(argv: ["daemon", "restart"])),
        ("settings", .openSettings(category: nil)),
        ("settings grille", .openSettings(category: .grille)),
        ("settings Règles", .openSettings(category: .regles)),
        ("settings regles", .openSettings(category: .regles)),
        ("settings Stages et bureaux", .openSettings(category: .stages)),
        ("set", .setting(.listCategories)),
        ("set target_grid.rows", .setting(.read("target_grid.rows"))),
        ("set target_grid.rows 4", .setting(.write("target_grid.rows", "4"))),
        ("set target_grid.rows défaut", .setting(.reset("target_grid.rows"))),
        ("set target_grid.rows default", .setting(.reset("target_grid.rows"))),
        ("set target_grid.hint_characters  azeq sdw ", .setting(.write("target_grid.hint_characters", "azeq sdw"))),
    ]

    @Test(arguments: parseCases)
    func parseGivesExactInvocation(input: String, expected: SlashInvocation) {
        #expect(SlashCommandCatalog.parse(input) == .success(expected))
    }

    @Test func casingAndExtraSpacesAreIgnored() {
        #expect(SlashCommandCatalog.parse("  MOVE   Gauche ") == .success(.router(argv: ["move", "left"])))
        #expect(SlashCommandCatalog.parse("Stage  2") == .success(.router(argv: ["stage", "switch", "2"])))
    }

    @Test(arguments: [
        ("gauche", "left"), ("droite", "right"), ("haut", "up"), ("bas", "down"),
        ("left", "left"), ("right", "right"), ("up", "up"), ("down", "down"), ("Gauche", "left"),
    ])
    func directionsInFrenchAndEnglishAreEquivalent(word: String, expected: String) {
        #expect(SlashCommandCatalog.normalizeDirection(word) == expected)
        #expect(SlashCommandCatalog.parse("move \(word)") == .success(.router(argv: ["move", expected])))
    }

    @Test func unknownDirectionIsRejected() {
        #expect(SlashCommandCatalog.normalizeDirection("diagonale") == nil)
    }

    // MARK: - Catalogue

    @Test func catalogHasTheNineteenCommandsPlusSettingsAndSet() {
        let names = SlashCommandCatalog.commands.map(\.name)
        #expect(names.count == 21)
        #expect(Set(names).count == 21)
        #expect(names.suffix(2) == ["settings", "set"])
        #expect(!names.contains("float"))
        #expect(!names.contains("close"))
        #expect(SlashCommandCatalog.commands.allSatisfy { !$0.summary.isEmpty && $0.usage.hasPrefix("/\($0.name)") })
        let aliases = Dictionary(uniqueKeysWithValues: SlashCommandCatalog.commands.map { ($0.name, $0.aliases) })
        #expect(aliases["stage"] == ["s"])
        #expect(aliases["desktop"] == ["d"])
        #expect(aliases["bm"] == ["b"])
    }

    // MARK: - Erreurs

    @Test(arguments: [
        "stage", "stage 0", "stage 2 3", "stage rename", "stage send", "stage send x",
        "move", "move diagonale", "move gauche haut", "swap", "resize x",
        "screen", "screen 0", "screen x", "send", "send x", "desktop", "desktop 0",
        "layout", "layout xyz", "split", "split x", "bm", "bm set",
        "grid dessus", "full x", "max x", "balance x", "letters x", "doctor x", "heal x", "reload x", "restart x",
    ])
    func wrongArgumentsGiveUsage(input: String) throws {
        let name = try #require(input.split(separator: " ").first.map(String.init))
        let command = try #require(SlashCommandCatalog.commands.first { $0.name == name })
        guard case .failure(let error) = SlashCommandCatalog.parse(input) else {
            Issue.record("« \(input) » aurait dû échouer")
            return
        }
        #expect(error.usage == command.usage)
        #expect(!error.message.isEmpty)
    }

    @Test func unknownCommandSuggestsTheClosestName() {
        guard case .failure(let error) = SlashCommandCatalog.parse("stge 2") else {
            Issue.record("commande inconnue attendue")
            return
        }
        #expect(error.suggestion == "stage")
        #expect(error.message.contains("stge"))
        #expect(error.usage == nil)
    }

    @Test(arguments: ["zzz", "float", "close", ""])
    func farOrUnimplementedCommandsHaveNoSuggestion(input: String) {
        guard case .failure(let error) = SlashCommandCatalog.parse(input) else {
            Issue.record("« \(input) » aurait dû échouer")
            return
        }
        #expect(error.suggestion == nil)
    }

    @Test func unknownCategoryListsTheValidOnes() {
        guard case .failure(let error) = SlashCommandCatalog.parse("settings zzz") else {
            Issue.record("catégorie inconnue attendue")
            return
        }
        #expect(error.usage == "/settings [catégorie]")
        for category in SettingCategory.allCases { #expect(error.message.contains(category.rawValue)) }
    }

    // MARK: - Catégories

    @Test(arguments: [
        ("grille", SettingCategory.grille), ("Règles", .regles), ("regles", .regles), ("REGLES", .regles),
        ("Général", .general), ("general", .general), ("Stages et bureaux", .stages), ("stages", .stages),
        ("Avancé", .avance), ("avance", .avance),
    ])
    func resolveCategoryAcceptsIdentifierOrLabel(text: String, expected: SettingCategory) {
        #expect(SlashCommandCatalog.resolveCategory(text) == expected)
    }

    @Test func resolveCategoryRejectsUnknownText() {
        #expect(SlashCommandCatalog.resolveCategory("zzz") == nil)
        #expect(SlashCommandCatalog.resolveCategory("") == nil)
    }

    // MARK: - Suggestions

    private let context = SlashContext(stageNames: ["Travail", "Courrier"], bookmarkNames: ["a", "docs"])

    private func texts(_ input: String) -> [String] {
        SlashCommandCatalog.suggestions(for: input, context: context).map(\.text)
    }

    @Test func emptyInputListsEveryCommand() {
        let suggestions = SlashCommandCatalog.suggestions(for: "", context: context)
        #expect(suggestions.count == 21)
        #expect(suggestions.allSatisfy { $0.kind == .command && $0.text.hasSuffix(" ") })
    }

    @Test func commandPrefixComesBeforeContains() {
        let suggestions = SlashCommandCatalog.suggestions(for: "st", context: context)
        #expect(suggestions.first == SlashSuggestion(
            text: "stage ",
            detail: SlashCommandCatalog.commands.first { $0.name == "stage" }?.summary ?? "",
            kind: .command))
        let names = suggestions.map(\.text)
        #expect(names.firstIndex(of: "stage ")! < names.firstIndex(of: "restart ")!)
        #expect(names.contains("restart "))
        #expect(!names.contains("move "))
    }

    @Test func aliasMatchesItsCommandOnce() {
        let names = texts("b")
        #expect(names.contains("bm "))
        #expect(names.filter { $0 == "bm " }.count == 1)
    }

    @Test func stageArgumentsAreNamesThenActions() {
        let names = texts("stage ")
        #expect(Set(names) == ["Travail", "Courrier", "new", "rename", "send"])
        #expect(texts("stage tra") == ["Travail"])
        #expect(texts("s n").first == "new")
    }

    @Test func bookmarkArgumentsAreNamesAndSet() {
        #expect(Set(texts("bm ")) == ["a", "docs", "set"])
        #expect(texts("bm do") == ["docs"])
    }

    @Test func settingNamesFollowTheCatalog() {
        let suggestions = SlashCommandCatalog.suggestions(for: "set target_g", context: context)
        #expect(!suggestions.isEmpty)
        #expect(suggestions.allSatisfy { $0.kind == .setting && $0.text.hasPrefix("target_grid.") })
        #expect(suggestions.contains { $0.text == "target_grid.rows" })
        let rows = suggestions.first { $0.text == "target_grid.rows" }
        #expect(rows?.detail == SettingsCatalog.find(id: "target_grid.rows")?.label)
    }

    @Test func settingSearchFallsBackToContains() {
        let names = texts("set hint_char")
        #expect(names.contains("target_grid.hint_characters"))
        #expect(names.contains("app_targets.hint_characters"))
    }

    @Test func readOnlySettingsAreNotSuggested() {
        let readOnly = SettingsCatalog.all.filter { $0.readOnlyReason != nil }.map(\.id)
        let suggested = Set(texts("set "))
        #expect(!suggested.isEmpty)
        #expect(suggested.isDisjoint(with: readOnly))
    }

    @Test func settingsArgumentsAreCategories() {
        #expect(texts("settings ").count == SettingCategory.allCases.count)
        #expect(texts("settings gr") == ["grille"])
        #expect(texts("settings reg") == ["regles"])
    }

    @Test func allowedValuesFollowTheCommand() {
        #expect(texts("layout ") == ["bsp", "spatial", "master", "float"])
        #expect(texts("layout sp").first == "spatial")
        #expect(texts("split ") == ["h", "v"])
        #expect(texts("move ").prefix(4) == ["gauche", "droite", "haut", "bas"])
        #expect(texts("move g").first == "gauche")
        #expect(texts("screen ").prefix(4) == ["gauche", "droite", "haut", "bas"])
        #expect(texts("swap ").count == 8)
        #expect(texts("resize ").count == 8)
    }

    @Test func nothingIsSuggestedAfterTheFirstArgumentOrForUnknownCommands() {
        #expect(texts("layout bsp ").isEmpty)
        #expect(texts("zzz ").isEmpty)
        #expect(texts("full ").isEmpty)
        #expect(texts("set target_grid.rows ").isEmpty)
    }
}
