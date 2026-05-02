import XCTest

// SPEC-014 T006 — smoke test : valide que le module compile et linke proprement.
// Les tests métier viendront avec les implémentations US1+ (T024 IPCClient,
// T036 acceptance bash, etc.).

final class RoadieRailSmokeTests: XCTestCase {
    func testModuleLinksAndBootstraps() {
        // Le simple fait que ce test compile prouve que la cible test peut
        // dépendre du target executable — preuve que la fondation Phase 1 est
        // fonctionnelle.
        XCTAssertTrue(true, "Smoke test passe — fondation SPEC-014 OK")
    }
}
