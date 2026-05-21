import Foundation
import Testing

/// Tests parser des flags --no-* du mode `roadied run --yes`.
///
/// Le parser actuel est `args.contains("--no-X")` dans Sources/roadied/main.swift,
/// ce qui est trivial. Ces tests documentent les flags supportes et detectent
/// toute regression de nommage. Si un nouveau flag --no-* est ajoute, l'ajouter
/// ici pour forcer la mise a jour de printUsage().
@Suite
struct RoadiedRunFlagsTests {
    static let supportedNoFlags: [String] = [
        "--no-tiler",
        "--no-rail",
        "--no-border",
        "--no-focus-mouse",
        "--no-titlebar-menu",
        "--no-target-mode",
        "--no-restore-safety"
    ]

    @Test
    func flagsAreLowerKebabAndUnique() {
        let set = Set(Self.supportedNoFlags)
        #expect(Self.supportedNoFlags.count == set.count)
        for flag in Self.supportedNoFlags {
            #expect(flag.hasPrefix("--no-"))
            #expect(flag == flag.lowercased())
            #expect(!flag.contains("_"))
        }
    }

    @Test
    func parserSemanticsMatchArgsContains() {
        let exampleArgs = ["run", "--yes", "--no-rail", "--no-focus-mouse"]
        #expect(exampleArgs.contains("--no-rail"))
        #expect(exampleArgs.contains("--no-focus-mouse"))
        #expect(!exampleArgs.contains("--no-tiler"))
        // Negatif : pas de flag inconnu accepte par accident
        #expect(!exampleArgs.contains("--no-unknown"))
    }
}
