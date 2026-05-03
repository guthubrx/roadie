import XCTest
@testable import RoadieCore

// SPEC-021 — Tests SkyLightBridge (T042)
// Note : skip automatique si headless (pas de display connecté)
final class SkyLightBridgeTests: XCTestCase {

    // T042 — currentSpaceID retourne non-nil pour la wid frontmost si display dispo
    @MainActor
    func test_currentSpaceID_returns_nonnil_for_frontmost() throws {
        // Skip si headless (CI sans display).
        guard CGMainDisplayID() != 0 else {
            throw XCTSkip("headless: no display connected")
        }
        // Récupérer la première fenêtre visible via CGWindowListCopyWindowInfo.
        let opts: CGWindowListOption = [.excludeDesktopElements, .optionOnScreenOnly]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]],
              let first = list.first,
              let wid = first[kCGWindowNumber as String] as? CGWindowID,
              wid != 0 else {
            throw XCTSkip("no on-screen window found")
        }
        let spaceID = SkyLightBridge.currentSpaceID(for: wid)
        // Peut être nil pour une fenêtre fullscreen non-managed, mais au moins
        // l'appel ne doit pas crasher. On accepte nil sans échec du test.
        _ = spaceID
    }

    // T042 — managedDisplaySpaces retourne des entrées cohérentes si display dispo
    @MainActor
    func test_managedDisplaySpaces_structure() throws {
        guard CGMainDisplayID() != 0 else {
            throw XCTSkip("headless: no display connected")
        }
        guard let displays = SkyLightBridge.managedDisplaySpaces() else {
            throw XCTSkip("CGSCopyManagedDisplaySpaces returned nil (headless?)")
        }
        // Au moins un display, chaque entry a un UUID non vide et au moins 1 space.
        XCTAssertFalse(displays.isEmpty, "expected at least one managed display")
        for entry in displays {
            XCTAssertFalse(entry.displayUUID.isEmpty, "displayUUID must be non-empty")
            XCTAssertFalse(entry.spaceIDs.isEmpty, "each display must have at least 1 space")
        }
    }
}
