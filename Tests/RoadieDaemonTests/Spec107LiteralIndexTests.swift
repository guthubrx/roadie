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
}
