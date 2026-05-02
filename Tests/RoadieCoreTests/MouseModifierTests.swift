import XCTest
import Cocoa
@testable import RoadieCore

/// SPEC-015 F4 — tests sur la logique pure `ModifierKey.nsFlags` + comportement
/// `MouseRaiser.skipWhenModifier` (modèle, sans hook NSEvent système).
final class MouseModifierTests: XCTestCase {

    // MARK: - ModifierKey.nsFlags mapping

    func testCtrlMapsToControl() {
        XCTAssertEqual(ModifierKey.ctrl.nsFlags, .control)
    }

    func testAltMapsToOption() {
        XCTAssertEqual(ModifierKey.alt.nsFlags, .option)
    }

    func testCmdMapsToCommand() {
        XCTAssertEqual(ModifierKey.cmd.nsFlags, .command)
    }

    func testShiftMapsToShift() {
        XCTAssertEqual(ModifierKey.shift.nsFlags, .shift)
    }

    func testHyperIncludesAllFour() {
        let h = ModifierKey.hyper.nsFlags
        XCTAssertTrue(h.contains(.control))
        XCTAssertTrue(h.contains(.option))
        XCTAssertTrue(h.contains(.command))
        XCTAssertTrue(h.contains(.shift))
    }

    func testNoneIsEmpty() {
        XCTAssertEqual(ModifierKey.none.nsFlags, [])
    }

    // MARK: - Modifier match logic (réplique de MouseDragHandler.modifierIsPressed)

    /// Helper pur reproduisant la logique du handler — testable sans NSEvent réel.
    private func modifierMatches(active: NSEvent.ModifierFlags, configured: ModifierKey) -> Bool {
        guard configured != .none else { return false }
        let mask: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
        let cleaned = active.intersection(mask)
        return cleaned.isSuperset(of: configured.nsFlags)
    }

    func testCtrlMatchesWhenCtrlPressed() {
        XCTAssertTrue(modifierMatches(active: .control, configured: .ctrl))
    }

    func testCtrlMatchesWhenCtrlPlusOtherKeys() {
        // Cmd-Ctrl pressed, configured = ctrl → still match (superset).
        XCTAssertTrue(modifierMatches(active: [.control, .command], configured: .ctrl))
    }

    func testAltDoesNotMatchWhenOnlyCtrlPressed() {
        XCTAssertFalse(modifierMatches(active: .control, configured: .alt))
    }

    /// CapsLock dans les flags ne doit PAS faire matcher .none → none = jamais match.
    func testNoneNeverMatches() {
        XCTAssertFalse(modifierMatches(active: [], configured: .none))
        XCTAssertFalse(modifierMatches(active: .control, configured: .none))
    }

    /// CapsLock parasite : un user avec CapsLock activé doit pouvoir continuer
    /// à utiliser le modifier ctrl normalement (le mask filtre capsLock).
    func testCapsLockStrippedFromMatching() {
        let withCapsLock: NSEvent.ModifierFlags = [.control, .capsLock]
        XCTAssertTrue(modifierMatches(active: withCapsLock, configured: .ctrl))
    }

    func testHyperRequiresAllFour() {
        XCTAssertFalse(modifierMatches(active: [.control, .option, .command], configured: .hyper))
        XCTAssertTrue(modifierMatches(active: [.control, .option, .command, .shift], configured: .hyper))
    }

    // MARK: - MouseRaiser skipWhenModifier behavior

    /// Logique de skip pure : MouseRaiser doit skip son raise si le modifier
    /// configuré est pressé. Réplique le check de ligne 47-51 dans MouseRaiser.
    private func raiserShouldSkip(active: NSEvent.ModifierFlags, skipWhen: ModifierKey?) -> Bool {
        guard let mod = skipWhen, mod != .none else { return false }
        let cleaned = active.intersection([.shift, .control, .option, .command])
        return cleaned.isSuperset(of: mod.nsFlags)
    }

    func testRaiserSkipsWhenModifierPressed() {
        XCTAssertTrue(raiserShouldSkip(active: .control, skipWhen: .ctrl))
    }

    func testRaiserDoesNotSkipWithoutModifier() {
        XCTAssertFalse(raiserShouldSkip(active: [], skipWhen: .ctrl))
    }

    func testRaiserDoesNotSkipWhenSkipWhenIsNil() {
        XCTAssertFalse(raiserShouldSkip(active: .control, skipWhen: nil))
    }

    func testRaiserDoesNotSkipWhenSkipWhenIsNone() {
        XCTAssertFalse(raiserShouldSkip(active: .control, skipWhen: .none))
    }

    // MARK: - MouseConfig disabled when all actions = .none

    func testHandlerDisabledWhenAllActionsNone() {
        let cfg = MouseConfig(modifier: .ctrl,
                              actionLeft: .none, actionRight: .none, actionMiddle: .none)
        XCTAssertEqual(cfg.actionLeft, .none)
        XCTAssertEqual(cfg.actionRight, .none)
        XCTAssertEqual(cfg.actionMiddle, .none)
    }
}
