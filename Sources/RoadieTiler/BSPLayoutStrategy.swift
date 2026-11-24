import CoreGraphics
import RoadieCore

public struct BSPLayoutStrategy: LayoutStrategy {
    public init() {}

    /// O(n) sans fenêtre prioritaire (ratio constant). Avec priorité, `splitRatio` parcourt
    /// chaque sous-liste : O(n²) en dwindle, O(n log n) en balanced (redimensionnement manuel).
    public func plan(_ request: LayoutRequest) -> LayoutPlan {
        let windows = request.windowIDs
        guard !windows.isEmpty else { return LayoutPlan(placements: [:]) }

        var placements: [WindowID: CGRect] = [:]
        split(
            windows: windows[...],
            rect: request.container.inset(by: request.outerGaps),
            innerGap: CGFloat(request.innerGap),
            currentFrames: request.currentFrames,
            priorityWindowIDs: request.priorityWindowIDs,
            newWindowIDs: request.newWindowIDs,
            minimumSizes: request.minimumSizes,
            splitPolicy: request.splitPolicy,
            placements: &placements
        )
        return LayoutPlan(placements: placements)
    }

    private func split(
        windows: ArraySlice<WindowID>,
        rect: CGRect,
        innerGap: CGFloat,
        currentFrames: [WindowID: CGRect],
        priorityWindowIDs: Set<WindowID>,
        newWindowIDs: Set<WindowID>,
        minimumSizes: [WindowID: CGSize],
        splitPolicy: String,
        placements: inout [WindowID: CGRect]
    ) {
        guard let first = windows.first else { return }
        guard windows.count > 1 else {
            placements[first] = rect.integral
            return
        }

        let leftCount = splitPolicy == "dwindle" ? 1 : windows.count / 2
        let leftWindows = windows.prefix(leftCount)
        let rightWindows = windows.dropFirst(leftCount)
        let horizontal = rect.width >= rect.height

        if horizontal {
            splitHorizontally(
                leftWindows: leftWindows,
                rightWindows: rightWindows,
                rect: rect,
                innerGap: innerGap,
                currentFrames: currentFrames,
                priorityWindowIDs: priorityWindowIDs,
                newWindowIDs: newWindowIDs,
                minimumSizes: minimumSizes,
                splitPolicy: splitPolicy,
                placements: &placements
            )
        } else {
            splitVertically(
                topWindows: leftWindows,
                bottomWindows: rightWindows,
                rect: rect,
                innerGap: innerGap,
                currentFrames: currentFrames,
                priorityWindowIDs: priorityWindowIDs,
                newWindowIDs: newWindowIDs,
                minimumSizes: minimumSizes,
                splitPolicy: splitPolicy,
                placements: &placements
            )
        }
    }

    private func splitHorizontally(
        leftWindows: ArraySlice<WindowID>,
        rightWindows: ArraySlice<WindowID>,
        rect: CGRect,
        innerGap: CGFloat,
        currentFrames: [WindowID: CGRect],
        priorityWindowIDs: Set<WindowID>,
        newWindowIDs: Set<WindowID>,
        minimumSizes: [WindowID: CGSize],
        splitPolicy: String,
        placements: inout [WindowID: CGRect]
    ) {
        // Espacement borné au conteneur (REL-033), comme `BSPTree` : l'espacement demandé
        // reste transmis aux splits descendants.
        let effectiveGap = BSPTree.gap(for: .vertical, in: rect, innerGap: innerGap)
        let usableWidth = max(0, rect.width - effectiveGap)
        let ratio = splitRatio(
            left: leftWindows,
            right: rightWindows,
            rect: rect,
            horizontal: true,
            innerGap: effectiveGap,
            currentFrames: currentFrames,
            priorityWindowIDs: priorityWindowIDs,
            newWindowIDs: newWindowIDs
        )
        let leftWidth = clampedFirstExtent(
            proposed: floor(usableWidth * ratio),
            usable: usableWidth,
            rect: rect,
            innerGap: innerGap,
            splitPolicy: splitPolicy,
            first: leftWindows,
            second: rightWindows,
            horizontal: true,
            minimumSizes: minimumSizes
        )
        let rightWidth = usableWidth - leftWidth
        let leftRect = CGRect(x: rect.minX, y: rect.minY, width: leftWidth, height: rect.height)
        let rightRect = CGRect(x: rect.minX + leftWidth + effectiveGap, y: rect.minY, width: rightWidth, height: rect.height)

        split(windows: leftWindows, rect: leftRect, innerGap: innerGap, currentFrames: currentFrames, priorityWindowIDs: priorityWindowIDs, newWindowIDs: newWindowIDs, minimumSizes: minimumSizes, splitPolicy: splitPolicy, placements: &placements)
        split(windows: rightWindows, rect: rightRect, innerGap: innerGap, currentFrames: currentFrames, priorityWindowIDs: priorityWindowIDs, newWindowIDs: newWindowIDs, minimumSizes: minimumSizes, splitPolicy: splitPolicy, placements: &placements)
    }

    private func splitVertically(
        topWindows: ArraySlice<WindowID>,
        bottomWindows: ArraySlice<WindowID>,
        rect: CGRect,
        innerGap: CGFloat,
        currentFrames: [WindowID: CGRect],
        priorityWindowIDs: Set<WindowID>,
        newWindowIDs: Set<WindowID>,
        minimumSizes: [WindowID: CGSize],
        splitPolicy: String,
        placements: inout [WindowID: CGRect]
    ) {
        // Couture de barre de titre et borne au conteneur (REL-033) : voir `BSPTree.gap`.
        let effectiveGap = BSPTree.gap(for: .horizontal, in: rect, innerGap: innerGap)
        let usableHeight = max(0, rect.height - effectiveGap)
        let ratio = splitRatio(
            left: topWindows,
            right: bottomWindows,
            rect: rect,
            horizontal: false,
            innerGap: effectiveGap,
            currentFrames: currentFrames,
            priorityWindowIDs: priorityWindowIDs,
            newWindowIDs: newWindowIDs
        )
        let topHeight = clampedFirstExtent(
            proposed: floor(usableHeight * ratio),
            usable: usableHeight,
            rect: rect,
            innerGap: innerGap,
            splitPolicy: splitPolicy,
            first: topWindows,
            second: bottomWindows,
            horizontal: false,
            minimumSizes: minimumSizes
        )
        let bottomHeight = usableHeight - topHeight
        let topRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: topHeight)
        let bottomRect = CGRect(x: rect.minX, y: rect.minY + topHeight + effectiveGap, width: rect.width, height: bottomHeight)

        split(windows: topWindows, rect: topRect, innerGap: innerGap, currentFrames: currentFrames, priorityWindowIDs: priorityWindowIDs, newWindowIDs: newWindowIDs, minimumSizes: minimumSizes, splitPolicy: splitPolicy, placements: &placements)
        split(windows: bottomWindows, rect: bottomRect, innerGap: innerGap, currentFrames: currentFrames, priorityWindowIDs: priorityWindowIDs, newWindowIDs: newWindowIDs, minimumSizes: minimumSizes, splitPolicy: splitPolicy, placements: &placements)
    }

    private func clampedFirstExtent(
        proposed: CGFloat,
        usable: CGFloat,
        rect: CGRect,
        innerGap: CGFloat,
        splitPolicy: String,
        first: ArraySlice<WindowID>,
        second: ArraySlice<WindowID>,
        horizontal: Bool,
        minimumSizes: [WindowID: CGSize]
    ) -> CGFloat {
        guard !minimumSizes.isEmpty, usable > 0 else { return proposed }
        let firstProposed = max(1, proposed)
        let secondProposed = max(1, usable - proposed)
        let firstRect = horizontal
            ? CGRect(x: 0, y: 0, width: firstProposed, height: rect.height)
            : CGRect(x: 0, y: 0, width: rect.width, height: firstProposed)
        let secondRect = horizontal
            ? CGRect(x: 0, y: 0, width: secondProposed, height: rect.height)
            : CGRect(x: 0, y: 0, width: rect.width, height: secondProposed)
        let firstMin = requiredMinimum(for: first, in: firstRect, innerGap: innerGap, splitPolicy: splitPolicy, minimumSizes: minimumSizes)
        let secondMin = requiredMinimum(for: second, in: secondRect, innerGap: innerGap, splitPolicy: splitPolicy, minimumSizes: minimumSizes)
        let minFirst = horizontal ? firstMin.width : firstMin.height
        let minSecond = horizontal ? secondMin.width : secondMin.height
        guard minFirst > 0 || minSecond > 0 else { return proposed }
        let lower = ceil(max(0, minFirst))
        let upper = floor(usable - ceil(max(0, minSecond)))
        guard lower <= upper else { return proposed }
        return min(max(proposed, lower), upper)
    }

    /// Besoin minimal composé d'une sous-liste selon les orientations de coupe descendantes.
    private func requiredMinimum(
        for windows: ArraySlice<WindowID>,
        in rect: CGRect,
        innerGap: CGFloat,
        splitPolicy: String,
        minimumSizes: [WindowID: CGSize]
    ) -> CGSize {
        guard let firstID = windows.first else { return .zero }
        guard windows.count > 1 else {
            let raw = minimumSizes[firstID] ?? .zero
            return CGSize(width: max(0, raw.width), height: max(0, raw.height))
        }
        let leftCount = splitPolicy == "dwindle" ? 1 : windows.count / 2
        let left = windows.prefix(leftCount)
        let right = windows.dropFirst(leftCount)
        let horizontal = rect.width >= rect.height
        let orientation: BSPOrientation = horizontal ? .vertical : .horizontal
        let gap = BSPTree.gap(for: orientation, innerGap: innerGap)
        let childRect = horizontal
            ? CGRect(x: 0, y: 0, width: max(1, (rect.width - gap) / 2), height: rect.height)
            : CGRect(x: 0, y: 0, width: rect.width, height: max(1, (rect.height - gap) / 2))
        let a = requiredMinimum(for: left, in: childRect, innerGap: innerGap, splitPolicy: splitPolicy, minimumSizes: minimumSizes)
        let b = requiredMinimum(for: right, in: childRect, innerGap: innerGap, splitPolicy: splitPolicy, minimumSizes: minimumSizes)
        if horizontal {
            let width = (a.width > 0 || b.width > 0)
                ? max(a.width, BSPTree.minimumChildExtent) + max(b.width, BSPTree.minimumChildExtent) + gap
                : 0
            return CGSize(width: width, height: max(a.height, b.height))
        } else {
            let height = (a.height > 0 || b.height > 0)
                ? max(a.height, BSPTree.minimumChildExtent) + max(b.height, BSPTree.minimumChildExtent) + gap
                : 0
            return CGSize(width: max(a.width, b.width), height: height)
        }
    }

    private func splitRatio(
        left: ArraySlice<WindowID>,
        right: ArraySlice<WindowID>,
        rect: CGRect,
        horizontal: Bool,
        innerGap: CGFloat,
        currentFrames: [WindowID: CGRect],
        priorityWindowIDs: Set<WindowID>,
        newWindowIDs: Set<WindowID>
    ) -> CGFloat {
        // Sans fenêtre prioritaire, tous les chemins ci-dessous rendent 0,5 : O(1) au lieu
        // de parcourir les sous-listes (PERF-008). Avec priorité : O(taille du split).
        guard !priorityWindowIDs.isEmpty else { return 0.5 }
        // Nouvelle fenetre : split 50/50 plutot qu'heriter de la frame macOS arbitraire.
        // Exception : si un resize explicite (priority)
        // est en cours dans ce split, on laisse le calcul priority habituel.
        let anyPriority = left.contains { priorityWindowIDs.contains($0) }
            || right.contains { priorityWindowIDs.contains($0) }
        if !anyPriority {
            let leftHasNew = left.contains { newWindowIDs.contains($0) }
            let rightHasNew = right.contains { newWindowIDs.contains($0) }
            if leftHasNew || rightHasNew {
                return 0.5
            }
        }

        guard let leftFrame = unionFrame(for: left, in: currentFrames),
              let rightFrame = unionFrame(for: right, in: currentFrames)
        else { return 0.5 }

        let usableExtent = horizontal ? rect.width - innerGap : rect.height - innerGap
        guard usableExtent > 0 else { return 0.5 }

        let priorityLeftFrame = unionPriorityFrame(for: left, in: currentFrames, priorityWindowIDs: priorityWindowIDs)
        let priorityRightFrame = unionPriorityFrame(for: right, in: currentFrames, priorityWindowIDs: priorityWindowIDs)

        guard isManagedSplit(leftFrame: leftFrame, rightFrame: rightFrame, rect: rect, horizontal: horizontal) else {
            if let priorityLeftFrame {
                let extent = horizontal ? priorityLeftFrame.width : priorityLeftFrame.height
                return (extent / usableExtent).clamped(to: 0.1...0.9)
            }
            if let priorityRightFrame {
                let extent = horizontal ? priorityRightFrame.width : priorityRightFrame.height
                return ((usableExtent - extent) / usableExtent).clamped(to: 0.1...0.9)
            }
            return 0.5
        }

        let leftEdge = horizontal ? leftFrame.maxX - rect.minX : leftFrame.maxY - rect.minY
        let rightEdge = horizontal ? rightFrame.minX - innerGap - rect.minX : rightFrame.minY - innerGap - rect.minY

        if let priorityLeftFrame {
            let priorityExtent = horizontal ? priorityLeftFrame.width : priorityLeftFrame.height
            let ratio = containsOnlyPriority(left, priorityWindowIDs) ? leftEdge / usableExtent : priorityExtent / usableExtent
            return ratio.clamped(to: 0.1...0.9)
        }
        if let priorityRightFrame {
            let priorityExtent = horizontal ? priorityRightFrame.width : priorityRightFrame.height
            let ratio = containsOnlyPriority(right, priorityWindowIDs) ? rightEdge / usableExtent : (usableExtent - priorityExtent) / usableExtent
            return ratio.clamped(to: 0.1...0.9)
        }
        return 0.5
    }

    private func unionPriorityFrame(
        for windows: ArraySlice<WindowID>,
        in currentFrames: [WindowID: CGRect],
        priorityWindowIDs: Set<WindowID>
    ) -> CGRect? {
        let filtered = windows.filter { priorityWindowIDs.contains($0) }
        return unionFrame(for: filtered[...], in: currentFrames)
    }

    private func containsOnlyPriority(_ windows: ArraySlice<WindowID>, _ priorityWindowIDs: Set<WindowID>) -> Bool {
        windows.allSatisfy { priorityWindowIDs.contains($0) }
    }

    private func isManagedSplit(leftFrame: CGRect, rightFrame: CGRect, rect: CGRect, horizontal: Bool) -> Bool {
        let tolerance = CGFloat(12)
        if horizontal {
            return leftFrame.minX.isClose(to: rect.minX, tolerance: tolerance)
                && rightFrame.maxX.isClose(to: rect.maxX, tolerance: tolerance)
        }
        return leftFrame.minY.isClose(to: rect.minY, tolerance: tolerance)
            && rightFrame.maxY.isClose(to: rect.maxY, tolerance: tolerance)
    }
}
