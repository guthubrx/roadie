import ApplicationServices
import Testing
@testable import RoadieAX

/// Session 022, round 2, lot G : R1-13 (REL-010, décision de réussite du focus).
/// L'appel AX réel est une frontière système : seule la décision pure est testée.
@Suite
struct Audit022R2LotGTests {
    private func decide(
        frontmost: AXError = .success,
        appIsActive: Bool = false,
        focusedWindow: AXError = .success,
        confirmed: Bool = false,
        raise: AXError = .success
    ) -> Bool {
        AXFocusDecision.succeeded(
            frontmost: frontmost,
            appIsActive: appIsActive,
            focusedWindow: focusedWindow,
            focusedWindowConfirmed: confirmed,
            raise: raise
        )
    }

    @Test
    func allWritesSucceedingIsASuccess() {
        #expect(decide())
    }

    @Test
    func raiseFailureIsAFailure() {
        #expect(!decide(raise: .failure))
        #expect(!decide(confirmed: true, raise: .actionUnsupported))
    }

    /// Écriture de la fenêtre focalisée en échec : succès seulement si la relecture la confirme.
    @Test
    func focusedWindowFailureNeedsReadBackConfirmation() {
        #expect(!decide(focusedWindow: .failure))
        #expect(!decide(focusedWindow: .attributeUnsupported))
        #expect(decide(focusedWindow: .failure, confirmed: true))
    }

    /// Application non mise devant : succès seulement si elle est active malgré tout.
    @Test
    func frontmostFailureNeedsActiveApplication() {
        #expect(!decide(frontmost: .failure))
        #expect(decide(frontmost: .failure, appIsActive: true))
    }
}
