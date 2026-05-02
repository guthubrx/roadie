import XCTest
import CoreGraphics
@testable import RoadieCore

/// SPEC-013 F9 : tests sur le contract du cache (lookup, miss, init).
/// Le snapshot live est testé indirectement par les tests d'intégration —
/// ici on valide la couche logique pure.
final class CGWindowBoundsCacheTests: XCTestCase {

    func testEmptyCacheReturnsNil() {
        let c = CGWindowBoundsCache(bounds: [:])
        XCTAssertNil(c.cgBounds(for: 1234))
    }

    func testLookupHit() {
        let r = CGRect(x: 10, y: 20, width: 800, height: 600)
        let c = CGWindowBoundsCache(bounds: [42: r])
        XCTAssertEqual(c.cgBounds(for: 42), r)
    }

    func testLookupMiss() {
        let c = CGWindowBoundsCache(bounds: [42: .zero])
        XCTAssertNil(c.cgBounds(for: 99))
    }

    /// Smoke test : `snapshot()` doit retourner sans crash et fournir un dict
    /// (potentiellement vide si run hors session graphique). Ne fait pas
    /// d'assertion sur le contenu exact (dépend de l'environnement de test).
    func testSnapshotDoesNotCrash() {
        let c = CGWindowBoundsCache.snapshot()
        // dict peut être vide ; on vérifie juste qu'on a un objet utilisable.
        XCTAssertNotNil(c.bounds)
    }
}
