import XCTest
import CoreGraphics
@testable import RoadieCore

/// SPEC-013 — Tests sur la logique pure de recovery au boot.
/// Couvre F1 (single setBounds + retry conditionnel), F2 (pas de dé-minimisation
/// agressive), F3 (balance conditionnel) — voir audit grade.
final class BootRecoveryTests: XCTestCase {

    private let primaryAX = CGRect(x: 0, y: 50, width: 1920, height: 1030)   // typical built-in
    private let secondaryAX = CGRect(x: 1920, y: 0, width: 2560, height: 1440)

    private var allScreens: [CGRect] { [primaryAX, secondaryAX] }

    // MARK: - isOnScreen

    func testIsOnScreenCenterInPrimary() {
        let f = CGRect(x: 100, y: 100, width: 800, height: 600)
        XCTAssertTrue(BootRecovery.isOnScreen(f, screenFramesAX: allScreens))
    }

    func testIsOnScreenCenterInSecondary() {
        let f = CGRect(x: 2500, y: 500, width: 800, height: 600)
        XCTAssertTrue(BootRecovery.isOnScreen(f, screenFramesAX: allScreens))
    }

    func testIsOnScreenOffscreen() {
        let f = CGRect(x: 0, y: -10000, width: 800, height: 600)
        XCTAssertFalse(BootRecovery.isOnScreen(f, screenFramesAX: allScreens))
    }

    // MARK: - isDegenerate

    func testIsDegenerateCollapsedHeight() {
        XCTAssertTrue(BootRecovery.isDegenerate(
            CGRect(x: 0, y: 0, width: 800, height: 19)))
    }

    func testIsDegenerateExtremelyOffscreen() {
        XCTAssertTrue(BootRecovery.isDegenerate(
            CGRect(x: 0, y: -10000, width: 800, height: 600)))
    }

    func testIsDegenerateAbsurdlyTall() {
        XCTAssertTrue(BootRecovery.isDegenerate(
            CGRect(x: 0, y: 0, width: 800, height: 200_000)))
    }

    func testIsDegenerateHealthyFrame() {
        XCTAssertFalse(BootRecovery.isDegenerate(
            CGRect(x: 100, y: 100, width: 800, height: 600)))
    }

    // MARK: - decide(_:)

    func testDecideHealthyFrameIsKept() {
        let obs = BootRecovery.WindowObservation(
            cgwid: 1, axFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
            expectedFrame: .zero, cgBounds: nil)
        let d = BootRecovery.decide(observation: obs,
                                    screenFramesAX: allScreens,
                                    primaryVisibleFrameAX: primaryAX)
        XCTAssertEqual(d, .keep)
    }

    /// F1+F2 résolus : si CG bounds dit que la fenêtre est saine, on adopte
    /// sans wake AX (pas de double setBounds, pas de setMinimized agressif).
    func testDecideAdoptsCGWhenAvailable() {
        let cg = CGRect(x: 100, y: 100, width: 1024, height: 768)
        let obs = BootRecovery.WindowObservation(
            cgwid: 1,
            axFrame: CGRect(x: 0, y: -2000, width: 1846, height: 20),  // AX dégénéré
            expectedFrame: .zero,
            cgBounds: cg)
        let d = BootRecovery.decide(observation: obs,
                                    screenFramesAX: allScreens,
                                    primaryVisibleFrameAX: primaryAX)
        XCTAssertEqual(d, .adoptCGBounds(cg))
    }

    /// F2 résolu : pas d'expectedFrame valide + frame dégénérée → on retire
    /// du BSP plutôt que de wake/restore agressivement (la fenêtre est peut-être
    /// minimisée par l'utilisateur).
    func testDecideRemovesFromBSPWhenNoTrace() {
        let obs = BootRecovery.WindowObservation(
            cgwid: 1,
            axFrame: CGRect(x: 0, y: -10000, width: 800, height: 1),
            expectedFrame: .zero,
            cgBounds: nil)
        let d = BootRecovery.decide(observation: obs,
                                    screenFramesAX: allScreens,
                                    primaryVisibleFrameAX: primaryAX)
        XCTAssertEqual(d, .removeFromBSP)
    }

    /// F1 raffiné : restoration AVEC expectedFrame valide → wake + retry car
    /// AX-collapsed nécessite double setBounds. Encodé explicitement, pas de
    /// magie.
    func testDecideRestoresWithWakeAndRetryWhenDegenerate() {
        let exp = CGRect(x: 100, y: 100, width: 1024, height: 768)
        let obs = BootRecovery.WindowObservation(
            cgwid: 1,
            axFrame: CGRect(x: 0, y: -10000, width: 1024, height: 1),
            expectedFrame: exp,
            cgBounds: nil)
        let d = BootRecovery.decide(observation: obs,
                                    screenFramesAX: allScreens,
                                    primaryVisibleFrameAX: primaryAX)
        XCTAssertEqual(d, .restore(target: exp, requiresWake: true, retrySetBounds: true))
    }

    /// F1 raffiné : fenêtre simplement offscreen (pas dégénérée) → restore
    /// SANS wake, SANS retry. Le code ne fait QUE setBounds, sans toucher
    /// minimized/fullscreen.
    func testDecideRestoresSingleSetBoundsWhenJustOffscreen() {
        let exp = CGRect(x: 200, y: 200, width: 800, height: 600)
        let obs = BootRecovery.WindowObservation(
            cgwid: 1,
            axFrame: CGRect(x: 100_000, y: 200, width: 800, height: 600), // healthy size, offscreen X
            expectedFrame: exp,
            cgBounds: nil)
        let d = BootRecovery.decide(observation: obs,
                                    screenFramesAX: allScreens,
                                    primaryVisibleFrameAX: primaryAX)
        XCTAssertEqual(d, .restore(target: exp, requiresWake: false, retrySetBounds: false))
    }

    /// Restoration vers fallback centré quand pas d'expectedFrame ET frame
    /// hors écran mais pas dégénérée (cas : user a déplacé la fenêtre sur un
    /// écran qui a depuis été débranché).
    func testDecideCentersOnPrimaryWhenNoExpected() {
        let obs = BootRecovery.WindowObservation(
            cgwid: 1,
            axFrame: CGRect(x: 100_000, y: 200, width: 800, height: 600),
            expectedFrame: .zero,
            cgBounds: nil)
        let d = BootRecovery.decide(observation: obs,
                                    screenFramesAX: allScreens,
                                    primaryVisibleFrameAX: primaryAX)
        if case .restore(let target, let wake, let retry) = d {
            XCTAssertEqual(wake, false)
            XCTAssertEqual(retry, false)
            // Centré sur primary visibleFrame
            XCTAssertEqual(target.size, CGSize(width: 800, height: 600))
            XCTAssertTrue(allScreens.contains { $0.contains(CGPoint(x: target.midX, y: target.midY)) })
        } else {
            XCTFail("expected .restore, got \(d)")
        }
    }

    // MARK: - shouldBalance (F3)

    /// F3 résolu : balance UNIQUEMENT si un weight est dégénéré. Évite la
    /// remise à 1.0 inconditionnelle qui efface un layout custom valide.
    func testShouldBalanceTrueOnDegenerateWeight() {
        XCTAssertTrue(BootRecovery.shouldBalance(weights: [0.5, 0.5, 0.001]))
        XCTAssertTrue(BootRecovery.shouldBalance(weights: [0.04, 0.96]))
    }

    func testShouldBalanceFalseOnHealthyWeights() {
        XCTAssertFalse(BootRecovery.shouldBalance(weights: [0.5, 0.5]))
        XCTAssertFalse(BootRecovery.shouldBalance(weights: [0.3, 0.3, 0.4]))
        XCTAssertFalse(BootRecovery.shouldBalance(weights: [1.0]))
    }

    func testShouldBalanceEmptyTreeIsFalse() {
        XCTAssertFalse(BootRecovery.shouldBalance(weights: []))
    }
}
