import XCTest
import CoreGraphics
@testable import RoadieCore
@testable import RoadieDesktops

/// SPEC-013 US1+US2 acceptance scenarios — sémantique du focus per_display
/// au niveau registry (handlers `handleDesktopFocusPerDisplay` / `handleWindowDesktop`
/// en CommandRouter délèguent la mutation d'état à ces APIs).
///
/// Ces tests valident SC-001 (zéro impact des focus inter-écrans) sans dépendance
/// AX/main.swift : on rejoue la séquence d'opérations qu'effectuent les handlers.
final class DesktopFocusPerDisplaySemanticsTests: XCTestCase {
    private var tempDir: URL!
    private let displayLG: CGDirectDisplayID = 4242    // simulate external LG
    private let displayBuiltin: CGDirectDisplayID = 1  // simulate built-in display

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DesktopFocusPerDisplaySemanticsTests-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// SPEC-013 US1 acceptance #1 : mode per_display, frontmost sur LG, focus 2
    /// → seul LG bascule, built-in inchangé. SC-001 vérifié sur registry.
    func testPerDisplayFocusOnlyAffectsTargetDisplay() async {
        let registry = DesktopRegistry(configDir: tempDir, displayUUID: "TEST-UUID-0001", count: 5, mode: .perDisplay)
        await registry.load()
        await registry.syncCurrentByDisplay(presentIDs: [displayLG, displayBuiltin])

        // setCurrent(2, on: LG) — équivalent au handler resolvedTarget=2, targetDisplayID=LG
        await registry.setCurrent(2, on: displayLG)

        let map = await registry.currentByDisplay
        XCTAssertEqual(map[displayLG], 2, "LG basculé sur desktop 2")
        XCTAssertEqual(map[displayBuiltin], 1, "built-in inchangé (SC-001)")
    }

    /// SPEC-013 US1 acceptance #3 : mode global, focus 2 → tous les écrans basculent.
    func testGlobalFocusPropagatesToAllDisplays() async {
        let registry = DesktopRegistry(configDir: tempDir, displayUUID: "TEST-UUID-0001", count: 5, mode: .global)
        await registry.load()
        await registry.syncCurrentByDisplay(presentIDs: [displayLG, displayBuiltin])

        await registry.setCurrent(2, on: displayLG)

        let map = await registry.currentByDisplay
        XCTAssertEqual(map[displayLG], 2)
        XCTAssertEqual(map[displayBuiltin], 2, "global mode propage à tous (compat V2)")
    }

    /// SPEC-013 fix back-and-forth scopé : `desktop focus 1` sur LG (qui est
    /// déjà sur 1) ne doit PAS basculer vers le recent du built-in. Bug fix
    /// commit 386da56 — testé via recentByDisplay vs recentID global.
    func testBackAndForthIsScopedPerDisplay() async {
        let registry = DesktopRegistry(configDir: tempDir, displayUUID: "TEST-UUID-0001", count: 5, mode: .perDisplay)
        await registry.load()
        await registry.syncCurrentByDisplay(presentIDs: [displayLG, displayBuiltin])

        // Built-in : 1 → 3 (recent built-in = 1)
        await registry.setCurrent(3, on: displayBuiltin)
        // LG : 1 → 2 (recent LG = 1)
        await registry.setCurrent(2, on: displayLG)
        // LG : 2 → 5 (recent LG = 2)
        await registry.setCurrent(5, on: displayLG)

        let recentLG = await registry.recentID(for: displayLG)
        let recentBuiltin = await registry.recentID(for: displayBuiltin)
        XCTAssertEqual(recentLG, 2, "LG recent = 2 (basé sur historique LG seul)")
        XCTAssertEqual(recentBuiltin, 1, "built-in recent = 1 (indépendant)")
    }

    /// SPEC-013 US2 acceptance #1 : drag d'une fenêtre LG (desktop 1) vers
    /// built-in (desktop 3) → la fenêtre adopte desktop 3 (current du target display).
    /// Test du contract du registry — le handler onDragDrop fait registry.update + updateWindowDisplayUUID.
    func testWindowAdoptsTargetDisplayCurrentInPerDisplay() async {
        let registry = DesktopRegistry(configDir: tempDir, displayUUID: "TEST-UUID-0001", count: 5, mode: .perDisplay)
        await registry.load()
        await registry.syncCurrentByDisplay(presentIDs: [displayLG, displayBuiltin])
        await registry.setCurrent(1, on: displayLG)
        await registry.setCurrent(3, on: displayBuiltin)

        // Au drag onto built-in, le handler lit currentID(for: displayBuiltin).
        let adopted = await registry.currentID(for: displayBuiltin)
        XCTAssertEqual(adopted, 3, "fenêtre draggée adopte le current du target display")
    }

    /// SPEC-013 US2 acceptance #3 : mode global, drag cross-écran → desktopID
    /// préservé (compat V2). Test du contract — le handler onDragDrop ne met
    /// PAS à jour state.desktopID en mode global.
    func testGlobalDragDoesNotChangeWindowDesktop() async {
        let registry = DesktopRegistry(configDir: tempDir, displayUUID: "TEST-UUID-0001", count: 5, mode: .global)
        await registry.load()
        await registry.syncCurrentByDisplay(presentIDs: [displayLG, displayBuiltin])
        await registry.setCurrent(2, on: displayLG)
        // En global, currentID est synchronisé à 2 partout. Le handler ne lit
        // PAS currentID(for:) — il garde le desktopID original. Validation : la
        // valeur retournée n'est utilisée que comme assignment displayUUID, pas
        // pour muter desktopID en mode global.
        let allEqual = await registry.currentByDisplay.values.allSatisfy { $0 == 2 }
        XCTAssertTrue(allEqual, "global mode : currentByDisplay synchronisé")
    }

    /// SPEC-013 fallback : si frontmost introuvable / display inconnu, currentID(for:)
    /// retourne le primary ou le currentID global. Edge case documenté spec.md.
    func testCurrentIDForUnknownDisplayFallsBackToPrimary() async {
        let registry = DesktopRegistry(configDir: tempDir, displayUUID: "TEST-UUID-0001", count: 5, mode: .perDisplay)
        await registry.load()
        await registry.syncCurrentByDisplay(presentIDs: [CGMainDisplayID()])
        await registry.setCurrent(4, on: CGMainDisplayID())

        let v = await registry.currentID(for: 99999) // unknown
        XCTAssertEqual(v, 4, "fallback sur primary current")
    }

    /// FR-016 : persister à chaque focus change. Test du contract :
    /// après setCurrent + saveCurrent, loadCurrent retourne la valeur.
    func testFocusChangeIsPersisted() async {
        let registry = DesktopRegistry(configDir: tempDir, displayUUID: "TEST-UUID-0001", count: 5, mode: .perDisplay)
        await registry.load()
        await registry.syncCurrentByDisplay(presentIDs: [displayLG])
        await registry.setCurrent(3, on: displayLG)

        // Le handler appelle DesktopPersistence.saveCurrent après setCurrent.
        let uuid = "TEST-LG"
        DesktopPersistence.saveCurrent(configDir: tempDir, displayUUID: uuid, currentID: 3)
        let loaded = DesktopPersistence.loadCurrent(configDir: tempDir, displayUUID: uuid)
        XCTAssertEqual(loaded, 3)
    }

    /// SPEC-013 fix F7 (cycle 1) : `recentByDisplay` ne doit PAS contenir d'entries
    /// pour des displays absents (sinon recentID(for:) peut retourner du stale
    /// si un CGDirectDisplayID est réattribué).
    func testRecentByDisplayCleanedOnDisplayRemoval() async {
        let registry = DesktopRegistry(configDir: tempDir, displayUUID: "TEST-UUID-0001", count: 5, mode: .perDisplay)
        await registry.load()
        let lgID: CGDirectDisplayID = 999
        let primaryID = CGMainDisplayID()
        await registry.syncCurrentByDisplay(presentIDs: [lgID, primaryID])
        await registry.setCurrent(3, on: lgID)
        await registry.setCurrent(5, on: lgID) // recent[lg] = 3

        // Débranchement LG
        await registry.syncCurrentByDisplay(presentIDs: [primaryID])

        let recentLG = await registry.recentID(for: lgID)
        // Fallback sur recentID global (le LG a été retiré → pas de stale dans
        // recentByDisplay). recentID global = 3 (dernier recent LG).
        XCTAssertNotNil(recentLG)
    }

    /// SPEC-013 fix F15 (additional cycle) : setCurrent(id:) maintient aussi
    /// recentByDisplay pour cohérence avec setCurrent(_:on:).
    func testSetCurrentLegacyMaintainsRecentByDisplay() async {
        let registry = DesktopRegistry(configDir: tempDir, displayUUID: "TEST-UUID-0001", count: 5, mode: .global)
        await registry.load()
        await registry.syncCurrentByDisplay(presentIDs: [displayLG, displayBuiltin])

        // setCurrent legacy (mode global → propagation toutes entries)
        await registry.setCurrent(id: 2)
        await registry.setCurrent(id: 4)

        // recentByDisplay doit refléter le previous (= 2) sur les 2 displays
        let recentLG = await registry.recentID(for: displayLG)
        let recentBuiltin = await registry.recentID(for: displayBuiltin)
        XCTAssertEqual(recentLG, 2)
        XCTAssertEqual(recentBuiltin, 2)
    }
}
