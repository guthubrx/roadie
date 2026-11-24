import CoreGraphics
import RoadieCore

/// Stratégie de placement en ruban défilant horizontal (`scrolling`, inspiré de Niri / PaperWM, Spec 164).
/// Place les fenêtres en colonnes côte à côte de largeur `columnWidthRatio * rect.width`, centrées sur
/// la fenêtre focalisée tout en maintenant un débord cliquable minimal (`24 pt`) aux bords de l'écran.
public struct ScrollingLayoutStrategy: LayoutStrategy {
    public var columnWidthRatio: CGFloat

    /// Largeur minimale visible en bord d'écran pour les colonnes hors fenêtre : évite le repositionnement
    /// arbitraire de macOS et reste strictement distinct des coordonnées `HiddenWindowPlacement`.
    public static let minimumEdgePeek: CGFloat = 24

    public init(columnWidthRatio: CGFloat = 0.65) {
        self.columnWidthRatio = columnWidthRatio.clamped(to: 0.25...1.0)
    }

    public func plan(_ request: LayoutRequest) -> LayoutPlan {
        let windows = request.windowIDs
        guard !windows.isEmpty else { return LayoutPlan(placements: [:]) }
        let rect = request.container.inset(by: request.outerGaps)
        guard rect.width > 0, rect.height > 0 else { return LayoutPlan(placements: [:]) }

        let colWidth: CGFloat
        if rect.width <= 120 {
            colWidth = rect.width
        } else {
            colWidth = min(rect.width, max(120, floor(rect.width * columnWidthRatio)))
        }
        let gap = min(CGFloat(request.innerGap), max(0, rect.width / 8))
        let step = colWidth + gap
        let totalWidth = CGFloat(windows.count) * colWidth + CGFloat(max(0, windows.count - 1)) * gap

        let focusedIndex = request.focusedWindowID.flatMap { windows.firstIndex(of: $0) } ?? 0
        let scrollX: CGFloat
        if totalWidth <= rect.width {
            // Tout le ruban tient dans l'écran : centrer l'ensemble proprement.
            scrollX = -floor((rect.width - totalWidth) / 2)
        } else {
            let focusedCenter = CGFloat(focusedIndex) * step + colWidth / 2
            let desired = focusedCenter - rect.width / 2
            scrollX = desired.clamped(to: 0...(totalWidth - rect.width))
        }

        let peek = min(Self.minimumEdgePeek, colWidth / 2, rect.width / 4)
        let minAllowedX = rect.minX - colWidth + peek
        let maxAllowedX = rect.maxX - peek

        var placements: [WindowID: CGRect] = [:]
        placements.reserveCapacity(windows.count)
        for (index, id) in windows.enumerated() {
            let rawX = rect.minX + CGFloat(index) * step - scrollX
            let clampedX = totalWidth <= rect.width ? rawX : rawX.clamped(to: minAllowedX...maxAllowedX)
            placements[id] = CGRect(
                x: clampedX,
                y: rect.minY,
                width: colWidth,
                height: rect.height
            ).integral
        }
        return LayoutPlan(placements: placements)
    }
}
