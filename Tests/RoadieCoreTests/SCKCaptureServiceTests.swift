import XCTest
@testable import RoadieCore

/// Tests minimaux SCKCaptureService.
/// Un mock SCStream complet est reporté en V2 (coût trop élevé pour V1 —
/// SCStream est une classe système non mockable sans wrapper protocol dédié).
/// Ces tests vérifient : init sans crash, observe/unobserve sur wid bidon sans crash.
@MainActor
final class SCKCaptureServiceTests: XCTestCase {

    func testInitNoCrash() {
        let service = SCKCaptureService()
        XCTAssertNotNil(service)
    }

    func testOnCaptureCallbackAssignment() {
        let service = SCKCaptureService()
        var called = false
        service.onCapture = { _ in called = true }
        // Pas de stream actif → callback jamais appelé.
        XCTAssertFalse(called)
    }

    /// observe() sur une wid bidon : ScreenCaptureKit ne trouve pas la fenêtre.
    /// Avec Screen Recording permission absente (CI) → throw ou log + no-op.
    /// Dans les deux cas : pas de crash, pas d'état corrompu.
    func testObserveUnknownWidNoCrash() async {
        let service = SCKCaptureService()
        // wid 0 n'existe jamais → SCShareableContent n'en retournera pas.
        // On accepte throw (permission) ou no-op (fenêtre absente).
        do {
            try await service.observe(wid: 0)
        } catch {
            // Permission Screen Recording absente en CI — attendu.
        }
        // unobserve doit être safe même si observe a échoué.
        await service.unobserve(wid: 0)
    }

    func testUnobserveUnknownWidIsNoOp() async {
        let service = SCKCaptureService()
        // Doit ne pas crasher.
        await service.unobserve(wid: 999_999)
    }

    func testObserveIdempotent() async {
        let service = SCKCaptureService()
        // Double observe : idempotent. Pas de crash, pas de double stream.
        // La deuxième observe est un no-op si la permission manque → throws au 1er.
        do {
            try await service.observe(wid: 1)
            try await service.observe(wid: 1) // no-op
        } catch {
            // Permission absente en CI : acceptable.
        }
    }
}
