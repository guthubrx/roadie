import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

/// Session 107 : l'index des littéraux donne les mêmes valeurs que `readLiteral`, refus compris.
@Suite
struct Spec107LiteralIndexTests {
    private let tricky = """
    top = 1
    [a]
    x = 2 # commentaire
    y = "texte # pas un commentaire"
    multi = [
      1, 2,
    ]
    after = 3
    inline = { p = 1 }
    dup = 1
    dup = 2
    sub.k = 4
    empty =
    [a.sub]
    k = 5
    [b]
    s = \"\"\"
    plusieurs
    lignes
    \"\"\"
    t = 6
    [c]
    v = 7
    [c]
    w = 8
    [[rules]]
    id = "r"
    [d]
    q = 'simple'
    """

    @Test func indexMatchesReadLiteralOnTrickyFiles() {
        let index = ConfigFileEditor.literalIndex(tricky)
        let probes: [(String, String)] = [("", "top"), ("a", "x"), ("a", "y"), ("a", "multi"), ("a", "after"), ("a", "inline"),
            ("a", "dup"), ("a", "sub"), ("a", "empty"), ("a.sub", "k"), ("b", "s"), ("b", "t"), ("c", "v"), ("c", "w"),
            ("rules", "id"), ("d", "q"), ("a.inline", "p"), ("absente", "k")]
        for (table, key) in probes {
            #expect(ConfigFileEditor.literal(in: index, table: table, key: key) == ConfigFileEditor.readLiteral(tricky, table: table, key: key),
                    "\(table).\(key)")
        }
    }

    /// Audit du 29 octobre 2026 : une clé à valeur vide, puis redéfinie, reste un doublon refusé.
    @Test func emptyValueThenRedefinitionIsRefused() {
        for text in ["y =\ny = 8", "y = # vide\ny = 8", "[b]\ny =\ny = \"t\""] {
            let table = text.hasPrefix("[b]") ? "b" : ""
            #expect(ConfigFileEditor.readLiteral(text, table: table, key: "y") == nil)
            #expect(ConfigFileEditor.literal(in: ConfigFileEditor.literalIndex(text), table: table, key: "y") == nil, "\(text)")
        }
    }

    /// Test différentiel à graine fixe : fichiers générés à partir de lignes délicates, l'index rend
    /// exactement `readLiteral` pour chaque sonde (audit du 29 octobre 2026).
    @Test func indexMatchesReadLiteralOnGeneratedFiles() {
        let lines = ["[a]", "[b]", "[a.sub]", "[[arr]]", "[ a ]", "[a] # c", "x = 1", "y = \"t # n\"", "dup = 2", "dup = 3",
                     "sub.k = 4", "k = 'q'", "x = [", "  1,", "]", "x = { p = 1 }", "y = \"\"\"", "z", "\"\"\"", "# rien", "",
                     "x = 5 # fin", "\"x\" = 6", "y =", "k = \"ouvert", "x=7", "  y = 8  ", "a.x = 9", "k = \"\\\"\"", "y = # vide"]
        let tables = ["", "a", "b", "a.sub", "arr"], keys = ["x", "y", "dup", "sub", "k"]
        var state: UInt64 = 129
        func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        var mismatches: [String] = []
        for _ in 0..<3_000 {
            let text = (0..<Int(next() % 14 + 1)).map { _ in lines[Int(next() % UInt64(lines.count))] }.joined(separator: "\n")
            let index = ConfigFileEditor.literalIndex(text)
            for table in tables {
                for key in keys where ConfigFileEditor.literal(in: index, table: table, key: key)
                    != ConfigFileEditor.readLiteral(text, table: table, key: key) && mismatches.count < 5 {
                    mismatches.append("[\(table)].\(key) dans <<<\(text)>>>")
                }
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches)")
    }
}
