import CoreGraphics
import RoadieCore

public struct BSPLayoutStrategy: LayoutStrategy {
    public init() {}

    /// O(n) sans fenêtre prioritaire (ratio constant et arbre de bornes pré-calculé en O(n)).
    /// Avec priorité, `splitRatio` parcourt chaque sous-liste : O(n²) en dwindle, O(n log n) en balanced.
    public func plan(_ request: LayoutRequest) -> LayoutPlan {
        let windows = request.windowIDs
        guard !windows.isEmpty else { return LayoutPlan(placements: [:]) }

        let innerGap = CGFloat(request.innerGap)
        let planNode = request.minimumSizes.isEmpty ? nil : PlanNode.build(
            for: windows[...],
            splitPolicy: request.splitPolicy,
            hGap: BSPTree.gap(for: .vertical, innerGap: innerGap),
            vGap: BSPTree.gap(for: .horizontal, innerGap: innerGap),
            minimumSizes: request.minimumSizes
        )
        var placements: [WindowID: CGRect] = [:]
        split(
            windows: windows[...],
            node: planNode,
            rect: request.container.inset(by: request.outerGaps),
            innerGap: innerGap,
            currentFrames: request.currentFrames,
            priorityWindowIDs: request.priorityWindowIDs,
            newWindowIDs: request.newWindowIDs,
            splitPolicy: request.splitPolicy,
            placements: &placements
        )
        return LayoutPlan(placements: placements)
    }

    private func split(
        windows: ArraySlice<WindowID>,
        node: PlanNode?,
        rect: CGRect,
        innerGap: CGFloat,
        currentFrames: [WindowID: CGRect],
        priorityWindowIDs: Set<WindowID>,
        newWindowIDs: Set<WindowID>,
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
        let (leftNode, rightNode): (PlanNode?, PlanNode?) = if case .branch(let l, let r, _, _, _, _, _) = node { (l, r) } else { (nil, nil) }
        let horizontal = rect.width >= rect.height

        if horizontal {
            splitHorizontally(
                leftWindows: leftWindows,
                rightWindows: rightWindows,
                leftNode: leftNode,
                rightNode: rightNode,
                rect: rect,
                innerGap: innerGap,
                currentFrames: currentFrames,
                priorityWindowIDs: priorityWindowIDs,
                newWindowIDs: newWindowIDs,
                splitPolicy: splitPolicy,
                placements: &placements
            )
        } else {
            splitVertically(
                topWindows: leftWindows,
                bottomWindows: rightWindows,
                topNode: leftNode,
                bottomNode: rightNode,
                rect: rect,
                innerGap: innerGap,
                currentFrames: currentFrames,
                priorityWindowIDs: priorityWindowIDs,
                newWindowIDs: newWindowIDs,
                splitPolicy: splitPolicy,
                placements: &placements
            )
        }
    }

    private func splitHorizontally(
        leftWindows: ArraySlice<WindowID>,
        rightWindows: ArraySlice<WindowID>,
        leftNode: PlanNode?,
        rightNode: PlanNode?,
        rect: CGRect,
        innerGap: CGFloat,
        currentFrames: [WindowID: CGRect],
        priorityWindowIDs: Set<WindowID>,
        newWindowIDs: Set<WindowID>,
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
            cross: rect.height,
            first: leftNode,
            second: rightNode,
            horizontal: true
        )
        let rightWidth = usableWidth - leftWidth
        let leftRect = CGRect(x: rect.minX, y: rect.minY, width: leftWidth, height: rect.height)
        let rightRect = CGRect(x: rect.minX + leftWidth + effectiveGap, y: rect.minY, width: rightWidth, height: rect.height)

        split(windows: leftWindows, node: leftNode, rect: leftRect, innerGap: innerGap, currentFrames: currentFrames, priorityWindowIDs: priorityWindowIDs, newWindowIDs: newWindowIDs, splitPolicy: splitPolicy, placements: &placements)
        split(windows: rightWindows, node: rightNode, rect: rightRect, innerGap: innerGap, currentFrames: currentFrames, priorityWindowIDs: priorityWindowIDs, newWindowIDs: newWindowIDs, splitPolicy: splitPolicy, placements: &placements)
    }

    private func splitVertically(
        topWindows: ArraySlice<WindowID>,
        bottomWindows: ArraySlice<WindowID>,
        topNode: PlanNode?,
        bottomNode: PlanNode?,
        rect: CGRect,
        innerGap: CGFloat,
        currentFrames: [WindowID: CGRect],
        priorityWindowIDs: Set<WindowID>,
        newWindowIDs: Set<WindowID>,
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
            cross: rect.width,
            first: topNode,
            second: bottomNode,
            horizontal: false
        )
        let bottomHeight = usableHeight - topHeight
        let topRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: topHeight)
        let bottomRect = CGRect(x: rect.minX, y: rect.minY + topHeight + effectiveGap, width: rect.width, height: bottomHeight)

        split(windows: topWindows, node: topNode, rect: topRect, innerGap: innerGap, currentFrames: currentFrames, priorityWindowIDs: priorityWindowIDs, newWindowIDs: newWindowIDs, splitPolicy: splitPolicy, placements: &placements)
        split(windows: bottomWindows, node: bottomNode, rect: bottomRect, innerGap: innerGap, currentFrames: currentFrames, priorityWindowIDs: priorityWindowIDs, newWindowIDs: newWindowIDs, splitPolicy: splitPolicy, placements: &placements)
    }

    /// Arbre des bornes minimales pré-calculé en O(n) avant le parcours descendant. Chaque nœud
    /// mémorise ses minimums selon qu'il coupe horizontalement (`width >= height`) ou verticalement.
    private indirect enum PlanNode {
        case leaf(minSize: CGSize)
        case branch(
            left: PlanNode,
            right: PlanNode,
            whenHorizontal: CGSize,
            whenVertical: CGSize,
            minWidth: CGFloat,
            minHeight: CGFloat,
            hasMinimum: Bool
        )

        var minWidth: CGFloat {
            switch self {
            case .leaf(let size): size.width
            case .branch(_, _, _, _, let width, _, _): width
            }
        }

        var minHeight: CGFloat {
            switch self {
            case .leaf(let size): size.height
            case .branch(_, _, _, _, _, let height, _): height
            }
        }

        var hasMinimum: Bool {
            switch self {
            case .leaf(let size): size.width > 0 || size.height > 0
            case .branch(_, _, _, _, _, _, let has): has
            }
        }

        static func build(
            for windows: ArraySlice<WindowID>,
            splitPolicy: String,
            hGap: CGFloat,
            vGap: CGFloat,
            minimumSizes: [WindowID: CGSize]
        ) -> PlanNode {
            guard let first = windows.first else { return .leaf(minSize: .zero) }
            guard windows.count > 1 else {
                let raw = minimumSizes[first] ?? .zero
                return .leaf(minSize: CGSize(width: max(0, raw.width), height: max(0, raw.height)))
            }
            let leftCount = splitPolicy == "dwindle" ? 1 : windows.count / 2
            let left = build(for: windows.prefix(leftCount), splitPolicy: splitPolicy, hGap: hGap, vGap: vGap, minimumSizes: minimumSizes)
            let right = build(for: windows.dropFirst(leftCount), splitPolicy: splitPolicy, hGap: hGap, vGap: vGap, minimumSizes: minimumSizes)
            let hasWidth = left.minWidth > 0 || right.minWidth > 0
            let hasHeight = left.minHeight > 0 || right.minHeight > 0
            let whenHorizontal = CGSize(
                width: hasWidth ? max(left.minWidth, BSPTree.minimumChildExtent) + max(right.minWidth, BSPTree.minimumChildExtent) + hGap : 0,
                height: max(left.minHeight, right.minHeight)
            )
            let whenVertical = CGSize(
                width: max(left.minWidth, right.minWidth),
                height: hasHeight ? max(left.minHeight, BSPTree.minimumChildExtent) + max(right.minHeight, BSPTree.minimumChildExtent) + vGap : 0
            )
            return .branch(
                left: left,
                right: right,
                whenHorizontal: whenHorizontal,
                whenVertical: whenVertical,
                minWidth: min(whenHorizontal.width, whenVertical.width),
                minHeight: min(whenHorizontal.height, whenVertical.height),
                hasMinimum: left.hasMinimum || right.hasMinimum
            )
        }
    }

    /// Choisit en O(1) l'étendue entière du premier côté la plus proche de `proposed` qui satisfait
    /// les bornes minimales des deux sous-arbres, y compris lorsqu'un ajustement inverse l'orientation
    /// (`width >= height`) d'un enfant.
    private func clampedFirstExtent(
        proposed: CGFloat,
        usable: CGFloat,
        cross: CGFloat,
        first: PlanNode?,
        second: PlanNode?,
        horizontal: Bool
    ) -> CGFloat {
        guard let first, let second, (first.hasMinimum || second.hasMinimum), usable > 0 else { return proposed }
        let firstIntervals = feasibleExtents(for: first, cross: cross, usable: usable, horizontal: horizontal)
        let secondIntervals = feasibleExtents(for: second, cross: cross, usable: usable, horizontal: horizontal)
        var best: CGFloat?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (aLo, aHi) in firstIntervals {
            for (bLo, bHi) in secondIntervals {
                let lo = max(aLo, usable - bHi)
                let hi = min(aHi, usable - bLo)
                guard lo <= hi else { continue }
                let candidate = min(max(proposed, lo), hi)
                let distance = abs(candidate - proposed)
                if distance < bestDistance {
                    bestDistance = distance
                    best = candidate
                }
            }
        }
        return best ?? proposed
    }

    /// Intervalles `[min, max]` d'étendue entière admissibles pour `node` sur l'axe courant (O(1)).
    private func feasibleExtents(
        for node: PlanNode,
        cross: CGFloat,
        usable: CGFloat,
        horizontal: Bool
    ) -> [(CGFloat, CGFloat)] {
        guard node.hasMinimum else { return [(0, usable)] }
        switch node {
        case .leaf(let size):
            let req = ceil(horizontal ? size.width : size.height)
            return req <= usable ? [(req, usable)] : []
        case .branch(_, _, let whenH, let whenV, _, _, _):
            func build(enforceCross: Bool) -> [(CGFloat, CGFloat)] {
                var result: [(CGFloat, CGFloat)] = []
                if horizontal {
                    // Enfant en coupe horizontale : extent >= cross.
                    if !enforceCross || cross >= ceil(whenH.height) {
                        let lo = max(ceil(cross), ceil(whenH.width))
                        if lo <= usable { result.append((lo, usable)) }
                    }
                    // Enfant en coupe verticale : extent < cross.
                    if !enforceCross || cross >= ceil(whenV.height) {
                        let strictUpper = cross > floor(cross) ? floor(cross) : cross - 1
                        let lo = ceil(whenV.width)
                        let hi = min(usable, strictUpper)
                        if lo <= hi { result.append((lo, hi)) }
                    }
                } else {
                    // Enfant en coupe horizontale : cross >= extent (i.e. extent <= floor(cross)).
                    if !enforceCross || cross >= ceil(whenH.width) {
                        let lo = ceil(whenH.height)
                        let hi = min(usable, floor(cross))
                        if lo <= hi { result.append((lo, hi)) }
                    }
                    // Enfant en coupe verticale : cross < extent (i.e. extent >= floor(cross) + 1).
                    if !enforceCross || cross >= ceil(whenV.width) {
                        let lo = max(floor(cross) + 1, ceil(whenV.height))
                        if lo <= usable { result.append((lo, usable)) }
                    }
                }
                return result
            }
            let strict = build(enforceCross: true)
            return strict.isEmpty ? build(enforceCross: false) : strict
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
