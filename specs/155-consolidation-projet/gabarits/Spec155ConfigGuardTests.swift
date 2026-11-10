import Foundation
import Testing
import TOMLKit
import RoadieCore

/// Garde-fous des réglages (spec 155, US3) : un réglage ajouté à moitié fait échouer un test.
@Suite struct Spec155ConfigGuardTests {
    // O(n), n = valeurs de la configuration encodée.
    private func walk(
        _ table: [String: Any], path: String, known: [String: Set<String>],
        unknown: inout [String], unchecked: inout [String]
    ) {
        for (key, value) in table {
            let childPath = path.isEmpty ? key : "\(path).\(key)"
            if let child = value as? [String: Any] {
                if known[childPath] == nil {
                    unchecked.append(childPath)
                } else {
                    walk(child, path: childPath, known: known, unknown: &unknown, unchecked: &unchecked)
                }
            } else if known[path]?.contains(key) != true {
                unknown.append(childPath)
            }
        }
    }

    @Test func everyDefaultSettingIsKnownByTheValidator() throws {
        let data = try JSONEncoder().encode(RoadieConfig())
        let tree = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var unknown: [String] = []
        var unchecked: [String] = []
        walk(tree, path: "", known: RoadieConfigLoader.knownKeys(), unknown: &unknown, unchecked: &unchecked)

        // `rules` et `shortcuts` sont des tableaux de tables à la racine : le validateur les traite à part.
        #expect(unknown.sorted() == ["rules", "shortcuts"], "réglages encodés mais absents de knownKeys : \(unknown.sorted())")
        #expect(unchecked.isEmpty, "tables encodées mais absentes de knownKeys : \(unchecked.sorted())")
    }

    @Test func anEmptyFileGivesTheDefaultConfiguration() throws {
        let decoded = try TOMLDecoder().decode(RoadieConfig.self, from: "")
        #expect(decoded == RoadieConfig())
    }
}
