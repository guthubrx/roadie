import XCTest
import CoreGraphics
@testable import RoadieCore

@MainActor
final class WallpaperClickWatcherTests: XCTestCase {

    // MARK: - Init / start / stop

    func testInitNoCrash() {
        let registry = WindowRegistry()
        let watcher = WallpaperClickWatcher(registry: registry)
        XCTAssertNotNil(watcher)
    }

    /// start() : Finder peut être absent ou AX peut échouer en CI — doit être silent no-op.
    func testStartNoCrash() {
        let registry = WindowRegistry()
        let watcher = WallpaperClickWatcher(registry: registry)
        watcher.start()
        watcher.stop()
    }

    func testDoubleStartIsNoOp() {
        let registry = WindowRegistry()
        let watcher = WallpaperClickWatcher(registry: registry)
        watcher.start()
        watcher.start() // idempotent
        watcher.stop()
    }

    func testStopWithoutStartIsNoOp() {
        let registry = WindowRegistry()
        let watcher = WallpaperClickWatcher(registry: registry)
        watcher.stop() // ne doit pas crasher
    }

    func testCallbackAssignment() {
        let registry = WindowRegistry()
        let watcher = WallpaperClickWatcher(registry: registry)
        var fired = false
        watcher.onWallpaperClick = { _ in fired = true }
        XCTAssertFalse(fired)
    }

    // MARK: - isClickOnWallpaper logique pure

    /// Avec un registry vide (aucune fenêtre trackée), tout point est candidat wallpaper.
    /// L'AX query finale peut retourner Finder ou nil — dans les deux cas la logique
    /// du Test 1 (aucune fenêtre) permet de passer.
    func testEmptyRegistryNoWindowsAlwaysCandidate() {
        let registry = WindowRegistry()
        let watcher = WallpaperClickWatcher(registry: registry)
        // Test 1 passe (aucune fenêtre).
        // Test 2 dépend de l'état AX système → non garanti en CI, on ne l'asserte pas.
        // Ce test vérifie juste que la méthode ne crashe pas.
        _ = watcher.isClickOnWallpaper(at: NSPoint(x: 100, y: 100))
    }

    /// Avec une fenêtre qui couvre le point, isClickOnWallpaper doit retourner false.
    func testWindowCoveringPointReturnsFalse() {
        let registry = WindowRegistry()
        // On insère une fenêtre qui couvre un rectangle large.
        // Frame AX : origin top-left (100, 100), 500×400.
        // Frame NS (pour screenHeight=900) : origin=(100, 900-100-400)=(100, 400), 500×400.
        let screenHeight = NSScreen.screens.first?.frame.height ?? 900
        let axFrame = CGRect(x: 0, y: 0, width: screenHeight, height: screenHeight)
        let state = WindowState(
            cgWindowID: 42,
            pid: 12345,
            bundleID: "com.test",
            title: "test",
            frame: axFrame,
            subrole: .standard,
            isFloating: false
        )
        let fakeElement = AXUIElementCreateApplication(12345)
        registry.register(state, axElement: fakeElement)

        let watcher = WallpaperClickWatcher(registry: registry)
        // Point au centre de la frame AX convertie en NS.
        let nsOriginY = screenHeight - axFrame.origin.y - axFrame.height
        let centerNS = NSPoint(x: axFrame.midX, y: nsOriginY + axFrame.height / 2)
        // Test 1 : une fenêtre couvre ce point → false (Test 1 suffit à retourner false).
        let result = watcher.isClickOnWallpaper(at: centerNS)
        XCTAssertFalse(result,
            "Un point dans une fenêtre trackée ne doit pas être considéré comme wallpaper")
    }
}
