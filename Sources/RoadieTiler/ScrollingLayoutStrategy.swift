import CoreGraphics
import RoadieCore

/// Stratégie de placement en ruban défilant horizontal (`scrolling`, inspiré de Niri / PaperWM, Spec 164).
/// Place les fenêtres en colonnes côte à côte de largeur `columnWidthRatio * rect.width`, centrées sur
/// la fenêtre focalisée tout en maintenant un débord cliquable échelonné aux bords de l'écran, strictement
/// distinct des coordonnées `HiddenWindowPlacement`.
public struct ScrollingLayoutStrategy: LayoutStrategy {
    public var columnWidthRatio: CGFloat
    /// Si `true`, un autre moniteur jouxte le bord gauche : aucune fenêtre ne descend sous `rect.minX`.
    public var clipsLeft: Bool
    /// Si `true`, un autre moniteur jouxte le bord droit : aucune fenêtre ne dépasse `rect.maxX`.
    public var clipsRight: Bool

    /// Largeur minimale visible en bord d'écran pour une colonne unique hors fenêtre.
    public static let minimumEdgePeek: CGFloat = 24

    /// Garde absolue vis-à-vis de `HiddenWindowPlacement.isPreferred` (tolérance 8 pt autour de `maxX - 1`).
    public static let safeHiddenClearance: CGFloat = 16

    /// Largeur minimale utile pour activer le ruban défilant ; en deçà, repli explicite plein cadre.
    public static let minimumRibbonWidth: CGFloat = 120

    /// Pas idéal entre colonnes lointaines échelonnées en éventail au bord de l'écran.
    private static let overflowCascadeStep: CGFloat = 16

    public init(
        columnWidthRatio: CGFloat = 0.65,
        clipsLeft: Bool = false,
        clipsRight: Bool = false
    ) {
        let finiteRatio = columnWidthRatio.isFinite ? columnWidthRatio : 0.65
        self.columnWidthRatio = finiteRatio.clamped(to: 0.25...1.0)
        self.clipsLeft = clipsLeft
        self.clipsRight = clipsRight
    }

    private static func isFinite(_ rect: CGRect) -> Bool {
        let limit: CGFloat = 1_000_000
        return rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.size.width.isFinite && rect.size.height.isFinite
            && abs(rect.origin.x) < limit && abs(rect.origin.y) < limit
            && rect.size.width < limit && rect.size.height < limit
    }

    private static func isFinite(_ insets: Insets) -> Bool {
        insets.top.isFinite && insets.right.isFinite && insets.bottom.isFinite && insets.left.isFinite
    }

    /// Répartition entière exacte sur `[start, end]` sans dérive flottante IEEE-754 :
    /// garantit un pas >= 1 pt entre positions consécutives dès que `end - start >= count - 1`.
    private static func distributeIntegral(from start: CGFloat, to end: CGFloat, count: Int) -> [CGFloat] {
        guard count > 1 else { return count == 1 ? [start] : [] }
        let startInt = Int(start.rounded())
        let endInt = Int(end.rounded())
        let spanInt = max(0, endInt - startInt)
        let divisor = count - 1
        return (0..<count).map { offset in
            CGFloat(startInt + (spanInt * offset) / divisor)
        }
    }

    public func plan(_ request: LayoutRequest) -> LayoutPlan {
        let windows = request.windowIDs
        guard !windows.isEmpty,
              Self.isFinite(request.container),
              Self.isFinite(request.outerGaps),
              request.innerGap.isFinite,
              columnWidthRatio.isFinite
        else { return LayoutPlan(placements: [:]) }

        let rect = request.container.inset(by: request.outerGaps)
        guard Self.isFinite(rect), rect.width > 0, rect.height > 0 else { return LayoutPlan(placements: [:]) }

        // Conteneur trop étroit pour un ruban défilant : repli explicite plein cadre sans débordement,
        // garantissant l'absence de faux positif `HiddenWindowPlacement` même sur des conteneurs minuscules.
        if rect.width < Self.minimumRibbonWidth {
            let full = rect.integral
            var placements: [WindowID: CGRect] = [:]
            placements.reserveCapacity(windows.count)
            for id in windows {
                placements[id] = full
            }
            return LayoutPlan(placements: placements)
        }

        let colWidth = min(rect.width, max(Self.minimumRibbonWidth, floor(rect.width * columnWidthRatio)))
        let gap = max(0, min(CGFloat(request.innerGap), rect.width / 8))
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

        let rawXs = windows.indices.map { index in
            floor(rect.minX + CGFloat(index) * step - scrollX)
        }

        var resolvedXs = rawXs
        let minClippedX = ceil(rect.minX)
        let maxClippedX = max(minClippedX, floor(rect.maxX - colWidth))
        if totalWidth > rect.width {
            let singlePeek = floor(min(Self.minimumEdgePeek, max(Self.safeHiddenClearance, rect.width / 4)))
            let minAllowedX = clipsLeft ? minClippedX : (ceil(rect.minX - colWidth) + singlePeek)
            let maxAllowedX = clipsRight ? maxClippedX : (floor(rect.maxX) - singlePeek)

            let leftOverflow = windows.indices.filter { rawXs[$0] < minAllowedX }
            let inRange = windows.indices.filter { rawXs[$0] >= minAllowedX && rawXs[$0] <= maxAllowedX }
            let rightOverflow = windows.indices.filter { rawXs[$0] > maxAllowedX }

            // Colonnes hors-écran à gauche : échelonnées de façon strictement croissante d'au moins 1 pt
            // tant que la bande disponible le permet ; si `clipsLeft`, strictement bornées >= `rect.minX`
            // (derrière la fenêtre focalisée) pour ne jamais déborder sur le moniteur voisin de gauche.
            if leftOverflow.count == 1, let idx = leftOverflow.first {
                resolvedXs[idx] = minAllowedX
            } else if leftOverflow.count > 1 {
                let bandStart = clipsLeft ? minClippedX : (ceil(rect.minX - colWidth) + Self.safeHiddenClearance)
                let nextVisibleX = inRange.first.map { rawXs[$0] } ?? maxClippedX
                let maxUpperBound = clipsRight ? maxClippedX : nextVisibleX - 1
                let maxStrictEnd = max(bandStart, min(maxUpperBound, nextVisibleX - 1))
                let requiredMinSpan = CGFloat(leftOverflow.count - 1)
                let preferredEnd = nextVisibleX - Self.safeHiddenClearance
                let comfortableEnd = min(maxStrictEnd, max(preferredEnd, bandStart + requiredMinSpan))
                let preferredSpan = min(
                    requiredMinSpan * Self.overflowCascadeStep,
                    max(requiredMinSpan, floor(rect.width / 3))
                )
                let bandEnd = min(comfortableEnd, bandStart + preferredSpan)
                let positions = Self.distributeIntegral(from: bandStart, to: bandEnd, count: leftOverflow.count)
                for (offset, idx) in leftOverflow.enumerated() {
                    resolvedXs[idx] = positions[offset]
                }
            }

            // Colonnes hors-écran à droite : échelonnées de façon strictement croissante d'au moins 1 pt
            // tant que la bande disponible le permet ; si `clipsRight`, strictement bornées <= `rect.maxX - colWidth`
            // (derrière la fenêtre focalisée) pour ne jamais déborder sur le moniteur voisin de droite.
            if rightOverflow.count == 1, let idx = rightOverflow.first {
                resolvedXs[idx] = maxAllowedX
            } else if rightOverflow.count > 1 {
                let bandEnd = clipsRight ? maxClippedX : (floor(rect.maxX) - Self.safeHiddenClearance)
                let prevVisibleX = inRange.last.map { rawXs[$0] } ?? minClippedX
                let minLowerBound = clipsLeft ? minClippedX : prevVisibleX + 1
                let minStrictStart = min(bandEnd, max(minLowerBound, prevVisibleX + 1))
                let requiredMinSpan = CGFloat(rightOverflow.count - 1)
                let preferredStart = prevVisibleX + Self.safeHiddenClearance
                let comfortableStart = max(minStrictStart, min(preferredStart, bandEnd - requiredMinSpan))
                let preferredSpan = min(
                    requiredMinSpan * Self.overflowCascadeStep,
                    max(requiredMinSpan, floor(rect.width / 3))
                )
                let bandStart = max(comfortableStart, bandEnd - preferredSpan)
                let positions = Self.distributeIntegral(from: bandStart, to: bandEnd, count: rightOverflow.count)
                for (offset, idx) in rightOverflow.enumerated() {
                    resolvedXs[idx] = positions[offset]
                }
            }
        }

        var placements: [WindowID: CGRect] = [:]
        placements.reserveCapacity(windows.count)
        let minSafeX: CGFloat = clipsLeft ? minClippedX : -.infinity
        let maxSafeX: CGFloat = clipsRight ? maxClippedX : (floor(rect.maxX) - Self.safeHiddenClearance)
        for (index, id) in windows.enumerated() {
            var finalX = resolvedXs[index]
            if totalWidth > rect.width || clipsLeft || clipsRight {
                finalX = min(max(finalX, minSafeX), maxSafeX)
            }
            placements[id] = CGRect(
                x: finalX,
                y: rect.minY,
                width: colWidth,
                height: rect.height
            ).integral
        }
        return LayoutPlan(placements: placements)
    }
}
