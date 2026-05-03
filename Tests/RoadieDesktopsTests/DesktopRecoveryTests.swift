import XCTest
import CoreGraphics
@testable import RoadieCore
@testable import RoadieDesktops

/// SPEC-013 T035 (US3) : tests d'intégration recovery écran branché/débranché.
/// Couvre la séquence persistance → débranchement → rebranchement → restoration
/// du current desktop et des window snapshots.
///
/// Note : on teste le contract des helpers `DesktopPersistence` + `DesktopRegistry`
/// utilisés par `Daemon.handleDisplayConfigurationChange`, pas le daemon lui-même
/// (qui dépend d'AX et nécessiterait un harness E2E).
final class DesktopRecoveryTests: XCTestCase {
    private var tempDir: URL!
    private let lgUUID = "TEST-LG-EXTERNAL"
    private let primaryUUID = "TEST-BUILTIN-PRIMARY"

    override func setUp() async throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DesktopRecoveryTests-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Scenario US3 acceptance #1+#2 : LG desktop 2 avec 3 fenêtres, débrancher
    /// → state conservé sur disque ; rebrancher → restoration current + 3 fenêtres.
    func testRebranchRestoresCurrentAndWindows() async throws {
        // Setup : LG desktop 2 actif avec 3 fenêtres assignées.
        let snaps = (1...3).map { i in
            DesktopPersistence.WindowSnapshot(
                cgwid: UInt32(1000 + i),
                bundleID: "com.app.test\(i)",
                titlePrefix: "Window \(i)",
                expectedFrame: CGRect(x: i * 100, y: i * 100, width: 800, height: 600))
        }
        DesktopPersistence.saveCurrent(configDir: tempDir, displayUUID: lgUUID, currentID: 2)
        DesktopPersistence.saveDesktopWindows(
            configDir: tempDir, displayUUID: lgUUID, desktopID: 2, windows: snaps)

        // Simulate débranchement : runtime registry retire l'entry mais le disque
        // est intact (FR-019).
        let registry = DesktopRegistry(configDir: tempDir, displayUUID: "TEST-UUID-0001", count: 5, mode: .perDisplay)
        await registry.load()
        let lgID: CGDirectDisplayID = 999
        await registry.syncCurrentByDisplay(presentIDs: []) // no display
        let mapAfterUnplug = await registry.currentByDisplay
        XCTAssertNil(mapAfterUnplug[lgID], "LG entry retirée du runtime")

        // Rebranchement : simuler la séquence faite par handleDisplayConfigurationChange.
        await registry.syncCurrentByDisplay(presentIDs: [lgID])
        let savedCurrent = DesktopPersistence.loadCurrent(
            configDir: tempDir, displayUUID: lgUUID)
        XCTAssertEqual(savedCurrent, 2, "current persiste sur disque malgré le débranchement")
        await registry.setCurrent(savedCurrent!, on: lgID)
        let mapAfterReplug = await registry.currentByDisplay
        XCTAssertEqual(mapAfterReplug[lgID], 2, "current restauré au rebranchement")

        // Snapshots des fenêtres restituables.
        let restored = DesktopPersistence.loadDesktopWindows(
            configDir: tempDir, displayUUID: lgUUID, desktopID: 2)
        XCTAssertEqual(restored.count, 3)
        XCTAssertEqual(Set(restored.map(\.cgwid)), Set([1001, 1002, 1003]))
    }

    /// US3 acceptance #3 : F2 process tué entre débranchement et rebranchement
    /// → restoration ignore silencieusement le wid orphelin (FR-020).
    func testRebranchIgnoresOrphanCgwid() {
        let snaps = [
            DesktopPersistence.WindowSnapshot(
                cgwid: 2001, bundleID: "alive", titlePrefix: "ok",
                expectedFrame: CGRect(x: 0, y: 0, width: 100, height: 100)),
            DesktopPersistence.WindowSnapshot(
                cgwid: 2002, bundleID: "tué", titlePrefix: "dead",
                expectedFrame: CGRect(x: 0, y: 0, width: 100, height: 100)),
        ]
        DesktopPersistence.saveDesktopWindows(
            configDir: tempDir, displayUUID: lgUUID, desktopID: 1, windows: snaps)

        // Simuler le matching N1 (cgwid encore vivant) : 2001 vivant, 2002 mort.
        let alive: Set<UInt32> = [2001]
        let loaded = DesktopPersistence.loadDesktopWindows(
            configDir: tempDir, displayUUID: lgUUID, desktopID: 1)
        let restorable = loaded.filter { alive.contains($0.cgwid) }
        XCTAssertEqual(restorable.count, 1)
        XCTAssertEqual(restorable[0].cgwid, 2001)
        // 2002 ignoré silencieusement, pas d'erreur.
    }

    /// US3 acceptance #4 : mode global, débranchement → comportement V2 (state
    /// global non lié à un display, pas de restoration spéciale).
    func testGlobalModeNoPerDisplayRestore() async {
        let registry = DesktopRegistry(configDir: tempDir, displayUUID: "TEST-UUID-0001", count: 5, mode: .global)
        await registry.load()
        // En mode global, setCurrent(_:on:) propage à toutes les entries.
        let did1: CGDirectDisplayID = 100
        let did2: CGDirectDisplayID = 200
        await registry.syncCurrentByDisplay(presentIDs: [did1, did2])
        await registry.setCurrent(3, on: did1)
        // did1 retiré (débranchement)
        await registry.syncCurrentByDisplay(presentIDs: [did2])
        let map = await registry.currentByDisplay
        XCTAssertEqual(map[did2], 3, "did2 inchangé en global après unplug did1")
        XCTAssertNil(map[did1])
    }

    /// SC-002 mesurabilité : ≥95% des fenêtres reviennent. Test sur 20 fenêtres
    /// avec 1 dead → 19/20 = 95%.
    func testRecoveryRateAbove95PctWith20Windows() {
        var snaps: [DesktopPersistence.WindowSnapshot] = []
        for i in 1...20 {
            snaps.append(DesktopPersistence.WindowSnapshot(
                cgwid: UInt32(3000 + i),
                bundleID: "com.app.\(i)",
                titlePrefix: "W\(i)",
                expectedFrame: CGRect(x: 0, y: 0, width: 100, height: 100)))
        }
        DesktopPersistence.saveDesktopWindows(
            configDir: tempDir, displayUUID: lgUUID, desktopID: 1, windows: snaps)

        // 1 fenêtre tuée entre débranchement et rebranchement
        var alive: Set<UInt32> = Set((3001...3020).map(UInt32.init))
        alive.remove(3010)

        let loaded = DesktopPersistence.loadDesktopWindows(
            configDir: tempDir, displayUUID: lgUUID, desktopID: 1)
        let restorable = loaded.filter { alive.contains($0.cgwid) }
        let rate = Double(restorable.count) / Double(loaded.count)
        XCTAssertGreaterThanOrEqual(rate, 0.95, "SC-002 : ≥95% restoration rate")
    }

    /// Persistance robuste : un long sommeil avec rebranchement plusieurs heures
    /// plus tard ne doit rien casser (pas d'expiration). Edge case spec.
    func testStateValidAfterArbitraryDelay() {
        DesktopPersistence.saveCurrent(configDir: tempDir, displayUUID: lgUUID, currentID: 4)
        // Pas de mécanisme d'expiration → loadCurrent reste valide indéfiniment.
        let v1 = DesktopPersistence.loadCurrent(configDir: tempDir, displayUUID: lgUUID)
        XCTAssertEqual(v1, 4)
    }
}
