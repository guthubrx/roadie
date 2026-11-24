import CoreGraphics
import RoadieCore

/// Stratégie de placement en onglets (`tabbed`, Spec 164).
/// - 1 fenêtre : occupe tout le conteneur (sans barre d'onglets).
/// - 2+ fenêtres : réserve `barHeight` en haut pour la barre d'onglets cliquable et empile toutes les
///   fenêtres dans le rectangle de contenu dessous, évitant tout redimensionnement à la bascule d'onglet.
public struct TabbedLayoutStrategy: LayoutStrategy {
    public var barHeight: CGFloat

    public init(barHeight: CGFloat = 28) {
        let finiteHeight = barHeight.isFinite ? barHeight : 28
        self.barHeight = finiteHeight.clamped(to: 20...44)
    }

    private static func isFinite(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.size.width.isFinite && rect.size.height.isFinite
    }

    private static func isFinite(_ insets: Insets) -> Bool {
        insets.top.isFinite && insets.right.isFinite && insets.bottom.isFinite && insets.left.isFinite
    }

    /// Rectangle de la barre d'onglets en coordonnées AX (source unique partagée avec `StageTabBarController`).
    /// Retourne `nil` lorsqu'il y a moins de 2 fenêtres ou un conteneur trop petit ou non fini.
    public static func tabBarFrame(
        in container: CGRect,
        outerGaps: Insets,
        barHeight: Double,
        windowCount: Int
    ) -> CGRect? {
        guard windowCount >= 2, Self.isFinite(container), Self.isFinite(outerGaps) else { return nil }
        let inset = container.inset(by: outerGaps)
        guard Self.isFinite(inset), inset.width >= 80, inset.height >= 80 else { return nil }
        let clampedHeight = CGFloat(barHeight.isFinite ? barHeight : 28).clamped(to: 20...44)
        let effectiveHeight = min(clampedHeight, max(20, inset.height - 60))
        return CGRect(
            x: inset.minX,
            y: inset.minY,
            width: inset.width,
            height: effectiveHeight
        ).integral
    }

    public func plan(_ request: LayoutRequest) -> LayoutPlan {
        let windows = request.windowIDs
        guard !windows.isEmpty,
              Self.isFinite(request.container),
              Self.isFinite(request.outerGaps),
              request.innerGap.isFinite
        else { return LayoutPlan(placements: [:]) }
        let inset = request.container.inset(by: request.outerGaps)
        guard Self.isFinite(inset), inset.width > 0, inset.height > 0 else { return LayoutPlan(placements: [:]) }

        let contentRect: CGRect
        if let bar = Self.tabBarFrame(
            in: request.container,
            outerGaps: request.outerGaps,
            barHeight: Double(barHeight),
            windowCount: windows.count
        ) {
            let separator = max(0, min(CGFloat(request.innerGap), 6))
            let reserved = min(bar.height + separator, max(0, inset.height - 40))
            contentRect = CGRect(
                x: inset.minX,
                y: inset.minY + reserved,
                width: inset.width,
                height: max(40, inset.height - reserved)
            ).integral
        } else {
            contentRect = inset.integral
        }

        var placements: [WindowID: CGRect] = [:]
        placements.reserveCapacity(windows.count)
        for id in windows {
            placements[id] = contentRect
        }
        return LayoutPlan(placements: placements)
    }
}
