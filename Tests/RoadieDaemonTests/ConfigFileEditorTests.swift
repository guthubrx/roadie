import Testing
import RoadieDaemon

@Suite
struct ConfigFileEditorTests {
    /// Reprend les constructions du vrai `roadies.toml` : commentaire de fin de ligne, `#` dans une chaîne,
    /// chaîne entre apostrophes, tableau multi-lignes commenté, clé commentée, même clé dans deux tables, `[[rules]]`.
    private let sample = """
    # FR: Configuration Roadie.
    [tiling]
    default_strategy = "bsp"
    gaps_outer = 8 # marge extérieure
    # gaps_outer_top = 4
    gaps_inner = 4

    [fx.borders]
    enabled = false
    # FR: Couleur de la bordure de la fenêtre active.
    active_color = "#7AA2F7"
    inactive_color = '#414868'

    [exclusions]
    # FR: Liste des applications à laisser en flottant.
    floating_bundles = [
        # FR: Réglages macOS exclus du tiling.
        "com.apple.systempreferences", # [pas une table]
        "weird]name",
    ]

    # FR: Menu contextuel expérimental.
    [experimental.target_mode]
    enabled = true
    # rows = 3

    [experimental.target_grid]
    enabled = false
    rows = 3

    [[rules]]
    id = "bournr-float"
    match = { app = "Bournr" }
    action = { floating = true }

    """

    private func lines(_ text: String) -> [String] {
        text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
    }

    /// Lignes retirées et ajoutées entre deux textes (préfixe et suffixe communs ignorés), et indice du premier écart.
    private func diff(_ before: String, _ after: String) -> (index: Int, removed: [String], added: [String]) {
        let a = lines(before), b = lines(after)
        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < a.count - prefix, suffix < b.count - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        return (prefix, Array(a[prefix..<(a.count - suffix)]), Array(b[prefix..<(b.count - suffix)]))
    }

    private func success(_ result: Result<String, ConfigEditError>) throws -> String {
        switch result {
        case .success(let text): return text
        case .failure(let error):
            Issue.record("refus inattendu : \(error)")
            throw error
        }
    }

    private func edit(_ text: String, _ table: String, _ key: String, _ value: String?) throws -> String {
        try success(ConfigFileEditor.edit(text, table: table, key: key, value: value))
    }

    // MARK: - Remplacement

    @Test
    func replacementKeepsTrailingComment() throws {
        let result = diff(sample, try edit(sample, "tiling", "gaps_outer", "12"))
        #expect(result.removed == ["gaps_outer = 8 # marge extérieure"])
        #expect(result.added == ["gaps_outer = 12 # marge extérieure"])
    }

    @Test
    func replacementOfStringContainingHash() throws {
        let result = diff(sample, try edit(sample, "fx.borders", "active_color", "\"#FF9E64\""))
        #expect(result.removed == ["active_color = \"#7AA2F7\""])
        #expect(result.added == ["active_color = \"#FF9E64\""])
    }

    @Test
    func replacementOfLiteralString() throws {
        let result = diff(sample, try edit(sample, "fx.borders", "inactive_color", "\"#000000\""))
        #expect(result.removed == ["inactive_color = '#414868'"])
        #expect(result.added == ["inactive_color = \"#000000\""])
    }

    @Test
    func replacementKeepsIndentationSpacingAndCommentAfterEscapedQuotes() throws {
        let text = "[t]\n  title  =  \"dit \\\"oui\\\" # pas un commentaire\"   # vrai commentaire\n"
        let result = diff(text, try edit(text, "t", "title", "\"non\""))
        #expect(result.added == ["  title  =  \"non\"   # vrai commentaire"])
        #expect(result.removed.count == 1)
    }

    @Test
    func sameKeyInTwoTablesOnlyTargetChanges() throws {
        let result = diff(sample, try edit(sample, "experimental.target_grid", "enabled", "true"))
        #expect(result.removed == ["enabled = false"])
        #expect(result.added == ["enabled = true"])
        #expect(lines(sample)[result.index - 1] == "[experimental.target_grid]")
    }

    @Test
    func neighbourArrayOfTablesStaysIntact() throws {
        let replaced = diff(sample, try edit(sample, "experimental.target_grid", "rows", "5"))
        #expect(replaced.removed == ["rows = 3"])
        #expect(replaced.added == ["rows = 5"])
        let inserted = diff(sample, try edit(sample, "experimental.target_grid", "label_font_size", "20"))
        #expect(inserted.removed.isEmpty)
        #expect(inserted.added == ["label_font_size = 20"])
        #expect(lines(sample)[inserted.index - 1] == "rows = 3")
    }

    // MARK: - Insertion

    @Test
    func insertionAfterMultilineArrayLeavesArrayUntouched() throws {
        let result = diff(sample, try edit(sample, "exclusions", "extra", "1"))
        #expect(result.removed.isEmpty)
        #expect(result.added == ["extra = 1"])
        #expect(lines(sample)[result.index - 1] == "]")
    }

    @Test
    func commentedKeyIsIgnoredAndInsertionGoesAfterLastUsefulLine() throws {
        let result = diff(sample, try edit(sample, "experimental.target_mode", "rows", "4"))
        #expect(result.removed.isEmpty)
        #expect(result.added == ["rows = 4"])
        #expect(lines(sample)[result.index - 1] == "enabled = true")
        #expect(lines(sample)[result.index] == "# rows = 3")
    }

    @Test
    func insertionDirectlyAfterHeaderBeforeSubArrayOfTables() throws {
        let text = "[t]\n[[t.x]]\nid = 1\n"
        #expect(try edit(text, "t", "a", "1") == "[t]\na = 1\n[[t.x]]\nid = 1\n")
    }

    @Test
    func missingTableIsAppendedAfterBlankLine() throws {
        #expect(try edit(sample, "experimental.target_record", "enabled", "true") == sample + "\n[experimental.target_record]\nenabled = true\n")
        #expect(try edit("[a]\nx = 1\n\n", "b", "y", "2") == "[a]\nx = 1\n\n[b]\ny = 2\n")
    }

    @Test
    func tableNameDoesNotMatchSubTableOrArrayOfTables() throws {
        #expect(try edit("[a.b.c]\nx = 1\n", "a.b", "x", "2") == "[a.b.c]\nx = 1\n\n[a.b]\nx = 2\n")
        #expect(try edit("[[a.b]]\nx = 1\n", "a.b", "x", "2") == "[[a.b]]\nx = 1\n\n[a.b]\nx = 2\n")
    }

    @Test
    func emptyFileGetsTableAndKey() throws {
        #expect(try edit("", "experimental.target_grid", "label_font_size", "20") == "[experimental.target_grid]\nlabel_font_size = 20\n")
    }

    @Test
    func fileWithoutFinalNewline() throws {
        let text = "[t]\na = 1"
        #expect(try edit(text, "t", "a", "5") == "[t]\na = 5")
        #expect(try edit(text, "t", "b", "2") == "[t]\na = 1\nb = 2")
        #expect(try edit(text, "u", "b", "2") == "[t]\na = 1\n\n[u]\nb = 2\n")
        #expect(try edit("[t]\na = 1\nb = 2", "t", "b", nil) == "[t]\na = 1")
    }

    @Test
    func crlfLineEndingsArePreserved() throws {
        let text = "[t]\r\na = 1 # c\r\n"
        #expect(try edit(text, "t", "a", "2") == "[t]\r\na = 2 # c\r\n")
        #expect(try edit(text, "t", "b", "2") == "[t]\r\na = 1 # c\r\nb = 2\r\n")
        #expect(try edit(text, "u", "b", "2") == "[t]\r\na = 1 # c\r\n\r\n[u]\r\nb = 2\r\n")
        #expect(try edit(text, "t", "a", nil) == "[t]\r\n")
    }

    // MARK: - Retrait

    @Test
    func removalDeletesOnlyTheKeyLine() throws {
        let result = diff(sample, try edit(sample, "tiling", "gaps_inner", nil))
        #expect(result.removed == ["gaps_inner = 4"])
        #expect(result.added.isEmpty)
    }

    @Test
    func removalOfAbsentKeyOrTableKeepsText() throws {
        #expect(try edit(sample, "tiling", "master_ratio", nil) == sample)
        #expect(try edit(sample, "experimental.target_record", "enabled", nil) == sample)
        #expect(try edit(sample, "experimental.target_mode", "rows", nil) == sample)
    }

    // MARK: - Lecture d'un littéral

    @Test
    func readLiteralReturnsRawValueWithoutComment() {
        #expect(ConfigFileEditor.readLiteral(sample, table: "tiling", key: "gaps_outer") == "8")
        #expect(ConfigFileEditor.readLiteral(sample, table: "fx.borders", key: "active_color") == "\"#7AA2F7\"")
        #expect(ConfigFileEditor.readLiteral(sample, table: "fx.borders", key: "inactive_color") == "'#414868'")
        #expect(ConfigFileEditor.readLiteral(sample, table: "experimental.target_mode", key: "enabled") == "true")
        #expect(ConfigFileEditor.readLiteral(sample, table: "experimental.target_grid", key: "enabled") == "false")
    }

    @Test
    func readLiteralIsNilWhenAbsentCommentedOrAmbiguous() {
        #expect(ConfigFileEditor.readLiteral(sample, table: "tiling", key: "gaps_outer_top") == nil)
        #expect(ConfigFileEditor.readLiteral(sample, table: "experimental.target_mode", key: "rows") == nil)
        #expect(ConfigFileEditor.readLiteral(sample, table: "absent", key: "rows") == nil)
        #expect(ConfigFileEditor.readLiteral(sample, table: "exclusions", key: "floating_bundles") == nil)
        #expect(ConfigFileEditor.readLiteral("[t]\na = 1\na = 2\n", table: "t", key: "a") == nil)
        #expect(ConfigFileEditor.readLiteral("[t]\na =\n", table: "t", key: "a") == nil)
        #expect(ConfigFileEditor.readLiteral("", table: "t", key: "a") == nil)
    }

    // MARK: - Refus

    @Test(arguments: [
        ("[t]\nlist = [\n  1, # un\n]\n", "list", ConfigEditError.multilineValue(line: 2)),
        ("[t]\nlist = [1, 2]\n", "list", .multilineValue(line: 2)),
        ("[t]\ntext = \"\"\"\nabc\n\"\"\"\n", "text", .multilineValue(line: 2)),
        ("[t]\nrows.max = 3\n", "rows", .dottedKey(line: 2)),
        ("[t]\nmatch = { app = \"Bournr\" }\n", "match", .inlineTable(line: 2)),
        ("[t]\na = 1\nb = 2\na = 3\n", "a", .duplicateKey(line: 4)),
        ("[t]\na = 1\n[u]\nb = 2\n[t]\nc = 3\n", "a", .duplicateTable),
        ("[t]\ncolor = \"#7AA2F7\n", "color", .unterminatedString(line: 2)),
        ("[t]\nlist = [\n  1,\n", "other", .ambiguousInsertion),
    ])
    func refusals(text: String, key: String, expected: ConfigEditError) {
        #expect(ConfigFileEditor.edit(text, table: "t", key: key, value: "2") == .failure(expected))
    }

    @Test
    func dottedKeyFromParentTableIsRefused() {
        let text = "[experimental]\ntarget_grid.rows = 3\n"
        #expect(ConfigFileEditor.edit(text, table: "experimental.target_grid", key: "cols", value: "4") == .failure(.dottedKey(line: 2)))
    }

    @Test
    func refusalAlsoAppliesToRemoval() {
        #expect(ConfigFileEditor.edit("[t]\nlist = [1]\n", table: "t", key: "list", value: nil) == .failure(.multilineValue(line: 2)))
    }
}
