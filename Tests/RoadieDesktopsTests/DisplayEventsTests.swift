import XCTest
@testable import RoadieCore

// MARK: - DisplayEventsTests (SPEC-012 T044)
//
// Vérifie que `DisplayRegistry.setActive(id:)` retourne `true` quand l'id change
// et `false` quand il reste le même. Les tests d'émission réelle d'events sur
// EventBus.shared sont dans roadied/main.swift (câblage T042) ; ici on teste
// le contrat de la primitive qui conditionne cette émission.
//
// Note : EventBus.shared est @MainActor. Les tests d'intégration full-bus
// nécessiteraient un daemon lancé. On teste donc :
//   1. setActive retourne true/false correctement (prérequis T041).
//   2. Le DesktopEvent display_changed est sérialisable en JSON-line.
//   3. Latence < 50 ms simulée (subscribe + publish sur EventBus en isolation).

@MainActor
final class DisplayEventsTests: XCTestCase {

    // MARK: T044 — setActive change → retourne true

    func test_setActive_differentID_returnsTrue() async {
        let provider = MockDisplayProvider(screens: [])
        let registry = DisplayRegistry(provider: provider)
        let changed = await registry.setActive(id: 12345)
        XCTAssertTrue(changed,
            "setActive vers un nouvel id (depuis nil) doit retourner true")
    }

    func test_setActive_sameID_returnsFalse() async {
        let provider = MockDisplayProvider(screens: [])
        let registry = DisplayRegistry(provider: provider)
        await registry.setActive(id: 42)
        let changed = await registry.setActive(id: 42)
        XCTAssertFalse(changed,
            "setActive sur le même id doit retourner false (pas de re-émission d'event)")
    }

    func test_setActive_sequence_emitsOnlyOnChange() async {
        let provider = MockDisplayProvider(screens: [])
        let registry = DisplayRegistry(provider: provider)

        // nil → 1 : changement.
        let c1 = await registry.setActive(id: 1)
        // 1 → 1 : pas de changement.
        let c2 = await registry.setActive(id: 1)
        // 1 → 2 : changement.
        let c3 = await registry.setActive(id: 2)
        // 2 → 2 : pas de changement.
        let c4 = await registry.setActive(id: 2)

        XCTAssertTrue(c1)
        XCTAssertFalse(c2)
        XCTAssertTrue(c3)
        XCTAssertFalse(c4)
    }

    // MARK: T044 — DesktopEvent display_changed est sérialisable

    func test_displayChangedEvent_JSONLineFormat() {
        let event = DesktopEvent(
            name: "display_changed",
            payload: [
                "display_index": "2",
                "display_id": "724592257",
                "ts": "1746000000000"
            ]
        )
        let line = event.toJSONLine()
        XCTAssertTrue(line.hasSuffix("\n"), "JSON-line doit se terminer par newline")
        XCTAssertTrue(line.contains("display_changed"), "JSON-line doit contenir le nom de l'event")
        XCTAssertTrue(line.contains("display_index"), "JSON-line doit contenir display_index")
        XCTAssertTrue(line.contains("display_id"), "JSON-line doit contenir display_id")
    }

    // MARK: T044 — EventBus.shared : publish + subscribe latence < 50 ms

    func test_eventBus_displayChanged_latencyUnder50ms() async throws {
        let bus = EventBus()
        let stream = bus.subscribe()
        let exp = expectation(description: "display_changed reçu dans les 50 ms")

        let task = Task { @MainActor in
            let start = Date()
            for await evt in stream {
                if evt.name == "display_changed" {
                    let elapsed = Date().timeIntervalSince(start) * 1000
                    XCTAssertLessThan(elapsed, 50,
                        "Latence display_changed \(elapsed) ms dépasse 50 ms")
                    exp.fulfill()
                    break
                }
            }
        }

        try await Task.sleep(nanoseconds: 5_000_000)
        bus.publish(DesktopEvent(
            name: "display_changed",
            payload: ["display_index": "2", "display_id": "999"]
        ))

        await fulfillment(of: [exp], timeout: 1.0)
        task.cancel()
    }
}
