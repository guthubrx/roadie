# Contract — `StageRendererRegistry` Swift API

**Module**: `RoadieRail.Renderers`
**File**: `Sources/RoadieRail/Renderers/StageRendererRegistry.swift`
**LOC budget**: ≤ 50

## Définition

```swift
/// Registre central des renderers de cellule de stage.
///
/// Pattern reproduit textuellement de `RoadieTiler.TilerRegistry`. Chaque
/// implémentation `StageRenderer` s'enregistre via `register(id:factory:)`,
/// typiquement au boot via `registerBuiltinRenderers()`.
public enum StageRendererRegistry {
    public static let defaultID: String = "stacked-previews"
    private static var factories: [String: () -> any StageRenderer] = [:]

    /// Enregistre une factory pour un identifiant. Idempotent : appel ultérieur
    /// avec le même id remplace silencieusement la factory précédente.
    public static func register(id: String, factory: @escaping () -> any StageRenderer) {
        factories[id] = factory
    }

    /// Crée une instance pour `id`. Retourne nil si non enregistrée.
    public static func make(id: String) -> (any StageRenderer)? {
        factories[id]?()
    }

    /// Helper : `make(id) ?? make(defaultID)!` avec log warning si fallback.
    public static func makeOrFallback(id: String?) -> any StageRenderer {
        if let id = id, let renderer = make(id: id) { return renderer }
        if let id = id {
            logWarn("renderer_unknown", ["want": id, "fallback": defaultID])
        }
        guard let fallback = make(id: defaultID) else {
            // Fail loud : le default DOIT être enregistré.
            preconditionFailure("StageRendererRegistry: defaultID '\(defaultID)' missing")
        }
        return fallback
    }

    /// Identifiants enregistrés, triés lex.
    public static var availableRenderers: [String] {
        factories.keys.sorted()
    }

    /// Tests-only : vide le registre.
    public static func reset() {
        factories.removeAll()
    }
}
```

## Invariants

- **I1** : `defaultID = "stacked-previews"` est constant et publique.
- **I2** : `register/make/availableRenderers` sont thread-safe par construction (Swift `Dictionary` en accès @MainActor sur le rail UI).
- **I3** : `makeOrFallback(nil)` retourne le renderer par défaut sans warning.
- **I4** : `makeOrFallback("non-existing")` retourne le renderer par défaut + log warning.
- **I5** : si `make(defaultID)` est nil (= default jamais enregistré), `makeOrFallback` crash fail-loud — c'est un bug de bootstrap, pas un état runtime acceptable.

## Bootstrap canonique

```swift
// Sources/RoadieRail/Renderers/Bootstrap.swift (ou inline dans RailController.init)
public func registerBuiltinRenderers() {
    StageRendererRegistry.register(id: StackedPreviewsRenderer.rendererID,
                                   factory: { StackedPreviewsRenderer() })
    // US2+ ajouts :
    // StageRendererRegistry.register(id: IconsOnlyRenderer.rendererID,
    //                                factory: { IconsOnlyRenderer() })
    // ...
}
```

## Tests unit

```swift
final class StageRendererRegistryTests: XCTestCase {
    override func setUp() { StageRendererRegistry.reset(); registerBuiltinRenderers() }

    func testDefaultRegistered() {
        XCTAssertTrue(StageRendererRegistry.availableRenderers.contains(StageRendererRegistry.defaultID))
    }

    func testMakeKnown() {
        XCTAssertNotNil(StageRendererRegistry.make(id: "stacked-previews"))
    }

    func testMakeUnknownReturnsNil() {
        XCTAssertNil(StageRendererRegistry.make(id: "nonexistent-xyz"))
    }

    func testMakeOrFallbackUnknownReturnsDefault() {
        let r = StageRendererRegistry.makeOrFallback(id: "nonexistent-xyz")
        XCTAssertEqual(type(of: r).rendererID, StageRendererRegistry.defaultID)
    }

    func testMakeOrFallbackNilReturnsDefault() {
        let r = StageRendererRegistry.makeOrFallback(id: nil)
        XCTAssertEqual(type(of: r).rendererID, StageRendererRegistry.defaultID)
    }

    func testRegisterIsIdempotent() {
        let countBefore = StageRendererRegistry.availableRenderers.count
        StageRendererRegistry.register(id: "stacked-previews", factory: { StackedPreviewsRenderer() })
        XCTAssertEqual(StageRendererRegistry.availableRenderers.count, countBefore)
    }
}
```
