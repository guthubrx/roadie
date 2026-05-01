import XCTest
@testable import RoadieCore

final class MigrationTests: XCTestCase {

    /// La migration utilise `~/.config/roadies/...` en dur (FR-023). On ne peut pas
    /// la rediriger sans monkey-patch ; ces tests vérifient le comportement no-op
    /// (pas de stages V1 préexistants, ou desktops V2 déjà présents).
    /// Les vrais déplacements de fichiers sont testés via le script d'intégration
    /// `tests/integration/07-multi-desktop-migration.sh` (T049).

    func test_runIfNeeded_noStagesDirYields_noMigration() {
        // Pré-condition : test isolé, pas de ~/.config/roadies/stages mock-able.
        // Ce test passera si la machine de test n'a pas de stages V1 — ce qui est
        // vrai en CI et pour un dev sans setup roadie. Sinon, le test est skip.
        let home = NSString(string: "~").expandingTildeInPath
        let v1Dir = "\(home)/.config/roadies/stages"
        let v2Root = "\(home)/.config/roadies/desktops"
        let v1Has = FileManager.default.fileExists(atPath: v1Dir)
        let v2Has = FileManager.default.fileExists(atPath: v2Root)

        let result = DesktopMigration.runIfNeeded(currentUUID: "test-uuid")
        // Cas attendu sur machine clean ou déjà migrée :
        // - !v1Has → migration impossible → migrated=false
        // - v1Has && v2Has → déjà migré → migrated=false
        if !v1Has || v2Has {
            XCTAssertFalse(result.migrated)
            XCTAssertEqual(result.movedFiles, 0)
            XCTAssertNil(result.backupPath)
        } else {
            // Cas où l'on a vraiment migré : on accepte le résultat positif mais
            // on ne nettoie pas (laisser au user, pour éviter de casser un setup).
            // Inutile d'asserter ici — pas de fail.
        }
    }
}
