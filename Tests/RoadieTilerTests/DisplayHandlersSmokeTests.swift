import XCTest
import RoadieCore
@testable import RoadieTiler

// MARK: - DisplayHandlersSmokeTests (SPEC-012 T036, T046, T047)
//
// Tests unitaires sur la logique de résolution de selectors display
// et le comportement mono-écran. Pas de socket round-trip : on teste
// directement les primitives utilisées par les handlers.
//
// Contrainte : NSScreen ne peut pas être instancié directement. Tous les tests
// utilisent `NSScreen.screens` préfixé au count demandé. Si la machine n'a pas
// assez d'écrans, certains tests sont skippés proprement.

final class DisplayHandlersSmokeTests: XCTestCase {

    // MARK: Helpers

    /// Retourne un registry avec min(count, NSScreen.screens.count) écrans.
    private func makeRegistry(count: Int) async -> (DisplayRegistry, actual: Int) {
        let screens = Array(NSScreen.screens.prefix(count))
        let provider = MockDisplayProvider(screens: screens)
        let registry = DisplayRegistry(provider: provider)
        await registry.refresh()
        return (registry, screens.count)
    }

    // MARK: T036 / T046 — display.list mono-écran retourne 1 display

    func test_displayList_monoScreen_returns1() async {
        let (reg, actual) = await makeRegistry(count: 1)
        guard actual >= 1 else { return }
        let displays = await reg.displays
        XCTAssertEqual(displays.count, 1, "mono-écran doit retourner exactement 1 display")
        XCTAssertEqual(displays[0].index, 1)
    }

    // MARK: T036 — display.list 2 écrans retourne 2 displays avec bons index

    func test_displayList_twoScreens_returns2() async {
        let (reg, actual) = await makeRegistry(count: 2)
        guard actual >= 2 else {
            // Skip si la machine n'a qu'un écran.
            return
        }
        let displays = await reg.displays
        XCTAssertEqual(displays.count, 2)
        let indices = displays.map(\.index).sorted()
        XCTAssertEqual(indices, [1, 2])
    }

    // MARK: T036 — registry.count == provider.count (quelle que soit la machine)

    func test_displayList_registryCountMatchesProvider() async {
        let real = NSScreen.screens
        let provider = MockDisplayProvider(screens: real)
        let registry = DisplayRegistry(provider: provider)
        await registry.refresh()
        let count = await registry.count
        XCTAssertEqual(count, real.count,
            "registry.count doit refléter le nombre d'écrans du provider")
    }

    // MARK: T036 — display(at:) résolution index

    func test_displayAt_validIndex1_returnsDisplay() async {
        let (reg, actual) = await makeRegistry(count: 1)
        guard actual >= 1 else { return }
        let d1 = await reg.display(at: 1)
        XCTAssertNotNil(d1)
        XCTAssertEqual(d1?.index, 1)
    }

    func test_displayAt_validIndex2_returnsDisplay() async {
        let (reg, actual) = await makeRegistry(count: 2)
        guard actual >= 2 else { return }
        let d2 = await reg.display(at: 2)
        XCTAssertNotNil(d2)
        XCTAssertEqual(d2?.index, 2)
    }

    // MARK: T047 — selector hors range sur mono-écran retourne nil

    func test_displayAt_outOfRange_returnsNil() async {
        let (reg, actual) = await makeRegistry(count: 1)
        guard actual >= 1 else { return }
        // Si le provider n'a qu'un écran, display(at:2) doit retourner nil.
        let registryCount = await reg.count
        guard registryCount == 1 else { return }
        let d = await reg.display(at: 2)
        XCTAssertNil(d, "selector display 2 sur mono-écran doit retourner nil (unknown_display)")
    }

    // MARK: T047 — logique range check du handler

    func test_monoScreen_selectorOutOfRange_failsRangeCheck() async {
        let (reg, actual) = await makeRegistry(count: 1)
        guard actual >= 1 else { return }
        let count = await reg.count
        guard count == 1 else { return }
        // Reproduit le range check du handler display.focus / window.display.
        let selectorN = 2
        let inRange = (1...count).contains(selectorN)
        XCTAssertFalse(inRange,
            "display selector 2 sur mono-écran doit être hors range → error unknown_display")
    }

    // MARK: T036 — setActive / activeID tracking

    func test_setActive_changesActiveID() async {
        let (reg, actual) = await makeRegistry(count: 1)
        guard actual >= 1 else { return }
        let displays = await reg.displays
        let id = displays[0].id
        let changed = await reg.setActive(id: id)
        let activeID = await reg.activeID
        XCTAssertTrue(changed, "setActive doit retourner true quand l'id change depuis nil")
        XCTAssertEqual(activeID, id)
    }

    func test_setActive_sameID_returnsFalse() async {
        let (reg, _) = await makeRegistry(count: 1)
        let displays = await reg.displays
        guard !displays.isEmpty else { return }
        let id = displays[0].id
        await reg.setActive(id: id)
        // Deuxième appel sur le même id : doit retourner false.
        let changed = await reg.setActive(id: id)
        XCTAssertFalse(changed, "setActive sur le même id doit retourner false")
    }

    // MARK: T036 — displayContaining(point:) retourne un display pour le centre de l'écran

    func test_displayContaining_pointInMainScreen_returnsDisplay() async {
        let screens = NSScreen.screens
        guard let main = screens.first else { return }
        let provider = MockDisplayProvider(screens: [main])
        let registry = DisplayRegistry(provider: provider)
        await registry.refresh()
        // Centre de l'écran principal en coords NS (bottom-left).
        let center = CGPoint(x: main.frame.midX, y: main.frame.midY)
        let hit = await registry.displayContaining(point: center)
        XCTAssertNotNil(hit,
            "displayContaining pour le centre de l'écran principal doit retourner un display")
        XCTAssertEqual(hit?.index, 1)
    }
}
