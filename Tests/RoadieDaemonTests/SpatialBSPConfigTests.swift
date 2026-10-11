import Foundation
import Testing
import RoadieCore
import RoadieDaemon
import RoadieTiler

@Suite
struct SpatialBSPConfigTests {
    @Test
    func windowManagementModeParsesSpatialAliases() {
        #expect(WindowManagementMode(roadieValue: "spatial_bsp") == .spatialBsp)
        #expect(WindowManagementMode(roadieValue: "spatial") == .spatialBsp)
        #expect(WindowManagementMode(roadieValue: "tree") == .spatialBsp)
        #expect(WindowManagementMode.spatialBsp.usesTreeEngine)
        #expect(WindowManagementMode.mutableBsp.usesTreeEngine)
        #expect(!WindowManagementMode.bsp.usesTreeEngine)
        #expect(!WindowManagementMode.masterStack.usesTreeEngine)
        #expect(!WindowManagementMode.float.usesTreeEngine)
    }

    private func loadConfig(_ toml: String) throws -> RoadieConfig {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roadie-spec013-\(UUID().uuidString).toml")
        try toml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return try RoadieConfigLoader.load(from: url.path)
    }

    @Test
    func windowPlacementParsesNewWindowSide() throws {
        let config = try loadConfig("""
        [window_placement]
        new_apps_target = "mouse"
        new_window_side = "left"
        """)
        #expect(config.windowPlacement.newAppsTarget == "mouse")
        #expect(config.windowPlacement.newWindowSide == "left")
    }

    @Test
    func newWindowSideDefaultsToRight() throws {
        let config = try loadConfig("""
        [window_placement]
        new_apps_target = "macos"
        """)
        #expect(config.windowPlacement.newWindowSide == "right")
    }

    @Test
    func invalidNewWindowSideFallsBackToRight() throws {
        let config = try loadConfig("""
        [window_placement]
        new_window_side = "diagonal"
        """)
        #expect(config.windowPlacement.newWindowSide == "right")
    }

    @Test
    func tilingModeParsesSpatialBsp() throws {
        let config = try loadConfig("""
        [tiling]
        default_strategy = "spatial_bsp"
        """)
        #expect(config.tiling.defaultStrategy == .spatialBsp)
    }

    /// SPEC-017 A8 : la config n'a pas d'état, ses alias `mutableBsp` désignent l'arbre.
    @Test(arguments: ["yabai", "mutableBsp", "mutable_bsp", "mutable-bsp"])
    func tilingModeParsesMutableBspAliasesAsSpatialBsp(_ value: String) throws {
        let config = try loadConfig("""
        [tiling]
        default_strategy = "\(value)"
        """)
        #expect(config.tiling.defaultStrategy == .spatialBsp)
    }

    /// Le décodage de `stages.json` est inchangé : `mutableBsp` y reste lu tel quel jusqu'à la migration.
    @Test
    func persistedMutableBspStageStillDecodes() throws {
        let stage = PersistentStage(id: StageID(rawValue: "1"), mode: .mutableBsp)
        let decoded = try JSONDecoder().decode(PersistentStage.self, from: JSONEncoder().encode(stage))
        #expect(decoded.mode == .mutableBsp)
    }

    @Test
    func persistentStageRoundTripsBSPTree() throws {
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.5, first: .leaf(WindowID(rawValue: 1)), second: .leaf(WindowID(rawValue: 2)))
        let stage = PersistentStage(id: StageID(rawValue: "1"), mode: .spatialBsp, bspTree: tree)
        let data = try JSONEncoder().encode(stage)
        let decoded = try JSONDecoder().decode(PersistentStage.self, from: data)
        #expect(decoded.mode == .spatialBsp)
        #expect(decoded.bspTree == tree)
    }

    @Test
    func persistentStageWithoutBSPTreeDecodesNil() throws {
        // Rétro-compat : un stage sérialisé avant SPEC-013 n'a pas de bspTree.
        let json = #"{"id":"1","name":"Stage 1","mode":"bsp","members":[],"groups":[],"parkingState":"native"}"#
        let decoded = try JSONDecoder().decode(PersistentStage.self, from: Data(json.utf8))
        #expect(decoded.bspTree == nil)
    }
}
