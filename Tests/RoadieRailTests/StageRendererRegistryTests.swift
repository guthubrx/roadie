import XCTest
@testable import RoadieRail

// SPEC-019 T012 — Tests unitaires du registre de renderers.
// Contrat de référence : specs/019-rail-renderers/contracts/registry-api.md

@MainActor
final class StageRendererRegistryTests: XCTestCase {

    override func setUp() async throws {
        await MainActor.run {
            StageRendererRegistry.reset()
            registerBuiltinRenderers()
        }
    }

    func testDefaultRegistered() {
        XCTAssertTrue(
            StageRendererRegistry.availableRenderers.contains(StageRendererRegistry.defaultID),
            "Le renderer par défaut doit être enregistré après registerBuiltinRenderers()"
        )
    }

    func testMakeKnown() {
        let renderer = StageRendererRegistry.make(id: "stacked-previews")
        XCTAssertNotNil(renderer, "make(id:) doit retourner une instance pour un id enregistré")
    }

    func testMakeUnknownReturnsNil() {
        let renderer = StageRendererRegistry.make(id: "nonexistent-xyz")
        XCTAssertNil(renderer, "make(id:) doit retourner nil pour un id inconnu")
    }

    func testMakeOrFallbackUnknownReturnsDefault() {
        let renderer = StageRendererRegistry.makeOrFallback(id: "nonexistent-xyz")
        XCTAssertEqual(
            type(of: renderer).rendererID,
            StageRendererRegistry.defaultID,
            "makeOrFallback doit retourner le renderer default pour un id inconnu"
        )
    }

    func testMakeOrFallbackNilReturnsDefault() {
        let renderer = StageRendererRegistry.makeOrFallback(id: nil)
        XCTAssertEqual(
            type(of: renderer).rendererID,
            StageRendererRegistry.defaultID,
            "makeOrFallback(nil) doit retourner le renderer default sans warning"
        )
    }

    func testRegisterIsIdempotent() {
        let countBefore = StageRendererRegistry.availableRenderers.count
        StageRendererRegistry.register(
            id: "stacked-previews",
            factory: { StackedPreviewsRenderer() }
        )
        XCTAssertEqual(
            StageRendererRegistry.availableRenderers.count,
            countBefore,
            "Un register sur un id existant ne doit pas ajouter d'entrée supplémentaire"
        )
    }
}
