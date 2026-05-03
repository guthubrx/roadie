# Contract — `StageRenderer` Swift Protocol

**Module**: `RoadieRail.Renderers`
**File**: `Sources/RoadieRail/Renderers/StageRendererProtocol.swift`
**LOC budget**: ≤ 60

## Définition

```swift
import SwiftUI
import AppKit

/// Contexte transmis à un renderer pour produire la View d'une cellule de stage.
public struct StageRenderContext {
    public let stage: StageVM
    public let windows: [CGWindowID: WindowVM]
    public let thumbnails: [CGWindowID: ThumbnailVM]
    public let haloColorHex: String
    public let haloIntensity: Double
    public let haloRadius: Double

    public init(stage: StageVM,
                windows: [CGWindowID: WindowVM],
                thumbnails: [CGWindowID: ThumbnailVM],
                haloColorHex: String = "#34C759",
                haloIntensity: Double = 0.75,
                haloRadius: Double = 18) {
        self.stage = stage
        self.windows = windows
        self.thumbnails = thumbnails
        self.haloColorHex = haloColorHex
        self.haloIntensity = haloIntensity
        self.haloRadius = haloRadius
    }
}

/// Callbacks orchestration UI passés au renderer.
public struct StageRendererCallbacks {
    public let onTap: () -> Void
    public let onDropAssign: (CGWindowID, String) -> Void
    public let onRename: (String, String) -> Void
    public let onAddFocused: (String) -> Void
    public let onDelete: (String) -> Void

    public init(onTap: @escaping () -> Void = {},
                onDropAssign: @escaping (CGWindowID, String) -> Void = { _, _ in },
                onRename: @escaping (String, String) -> Void = { _, _ in },
                onAddFocused: @escaping (String) -> Void = { _ in },
                onDelete: @escaping (String) -> Void = { _ in }) {
        self.onTap = onTap
        self.onDropAssign = onDropAssign
        self.onRename = onRename
        self.onAddFocused = onAddFocused
        self.onDelete = onDelete
    }
}

/// Protocole d'un rendu de cellule de stage. Stateless, fonction pure du contexte.
public protocol StageRenderer: AnyObject {
    static var rendererID: String { get }
    static var displayName: String { get }

    @MainActor
    func render(context: StageRenderContext,
                callbacks: StageRendererCallbacks) -> AnyView
}
```

## Invariants

- `rendererID` : lowercase-kebab-case, charset `[a-z0-9-]`, longueur ≤ 32.
- `displayName` : human-readable, max 40 chars.
- `render(...)` est **pure** : pas d'état mutable interne, pas de side-effect IO/IPC.
- `render(...)` peut lire `context.*` mais ne doit jamais le muter (struct value de toute façon).
- `render(...)` doit gérer le cas `context.stage.windowIDs.isEmpty` sans crash (placeholder).

## Conformance test (unit)

```swift
final class StageRendererProtocolTests: XCTestCase {
    func testEmptyStageDoesNotCrash() {
        let renderer = StackedPreviewsRenderer()
        let stage = StageVM(id: "1", displayName: "1", isActive: true, windowIDs: [])
        let ctx = StageRenderContext(stage: stage, windows: [:], thumbnails: [:])
        // Doit produire un AnyView sans crasher
        _ = renderer.render(context: ctx, callbacks: StageRendererCallbacks())
    }

    func testRendererIDFormat() {
        XCTAssertTrue(StackedPreviewsRenderer.rendererID.range(of: "^[a-z0-9-]+$",
                                                              options: .regularExpression) != nil)
        XCTAssertLessThanOrEqual(StackedPreviewsRenderer.rendererID.count, 32)
    }
}
```
