import CoreGraphics
import RoadieCore

/// Séparation visible. Le chemin désigne l'arbre complet : true = first, false = second.
/// Les rectangles sont en coordonnées AX ; hitRect ne couvre aucune feuille placée.
public struct BSPDivider: Equatable, Sendable {
    public let path: [Bool]
    public let orientation: BSPOrientation
    public let ratio: Double
    public let container: CGRect
    public let hitRect: CGRect
    public let position: CGPoint
}

extension BSPTree {
    /// O(n·d), y compris les chemins rendus (d = profondeur). Aucun appariement de fenêtres.
    public func dividers(
        in container: CGRect,
        innerGap: CGFloat = 0,
        excluding absent: Set<WindowID> = []
    ) -> [BSPDivider] {
        guard container.width > 0, container.height > 0,
              container.minX.isFinite, container.minY.isFinite,
              container.width.isFinite, container.height.isFinite, innerGap.isFinite else { return [] }
        let visible = BSPDividerNode(self, excluding: absent, path: [])
        var result: [BSPDivider] = []
        visible.appendDividers(in: container, innerGap: max(0, innerGap), to: &result)
        return result
    }

    /// Déplace le centre de la séparation. nil si le chemin n'est plus visible.
    /// O(n·d + 16n) : recherche géométrique et recherche bornée des minimums connus.
    /// Les autres ratios et toutes les feuilles (même absentes) restent inchangés.
    public func movingDivider(
        at path: [Bool],
        to point: CGPoint,
        in container: CGRect,
        innerGap: CGFloat = 0,
        excluding absent: Set<WindowID> = [],
        knownMinimums: [WindowID: CGSize] = [:]
    ) -> BSPTree? {
        guard point.x.isFinite, point.y.isFinite,
              let divider = dividers(in: container, innerGap: innerGap, excluding: absent)
                .first(where: { $0.path == path }) else { return nil }
        let gap = max(0, innerGap)
        let usable = Self.usableExtent(of: divider.container, orientation: divider.orientation, innerGap: gap)
        guard usable > 0 else { return nil }
        let seam = Self.gap(for: divider.orientation, in: divider.container, innerGap: gap)
        let offset = divider.orientation == .vertical
            ? point.x - divider.container.minX : point.y - divider.container.minY
        let firstExtent = offset - seam / 2
        let rawRatio = Double(firstExtent / usable)
        // Au milieu du point entier produit par floor() : une relecture ne perd pas un pixel
        // par arrondi flottant. Les limites 0,05/0,95 restent celles du moteur.
        let ratio: Double
        if rawRatio <= Self.ratioBounds.lowerBound { ratio = Self.ratioBounds.lowerBound }
        else if rawRatio >= Self.ratioBounds.upperBound { ratio = Self.ratioBounds.upperBound }
        else {
            ratio = min(max(Double((floor(firstExtent) + 0.5) / usable), Self.ratioBounds.lowerBound), Self.ratioBounds.upperBound)
        }
        let requested = replacingDividerRatio(at: path[...], with: ratio)
        guard !knownMinimums.isEmpty else { return requested }
        let before = projected(excluding: absent).place(in: container, innerGap: gap)
        func fits(_ candidate: BSPTree) -> Bool {
            let after = candidate.projected(excluding: absent).place(in: container, innerGap: gap)
            return knownMinimums.allSatisfy { id, minimum in
                guard let original = before[id], let actual = after[id] else { return true }
                // Même règle que adjustingFence : ne pas aggraver un minimum déjà impossible.
                return actual.width >= min(minimum.width, original.width)
                    && actual.height >= min(minimum.height, original.height)
            }
        }
        if fits(requested) { return requested }
        var low = 0.0, high = 1.0
        var accepted = self
        for _ in 0..<16 {
            let fraction = (low + high) / 2
            let candidate = replacingDividerRatio(at: path[...], with: divider.ratio + (ratio - divider.ratio) * fraction)
            if fits(candidate) { low = fraction; accepted = candidate }
            else { high = fraction }
        }
        return accepted
    }

    // O(d) ; la géométrie a déjà vérifié le chemin dans l'arbre complet.
    private func replacingDividerRatio(at path: ArraySlice<Bool>, with ratio: Double) -> BSPTree {
        guard case .split(let orientation, let previous, let first, let second) = self else { return self }
        guard let side = path.first else {
            return .split(orientation: orientation, ratio: ratio, first: first, second: second)
        }
        return side
            ? .split(orientation: orientation, ratio: previous,
                     first: first.replacingDividerRatio(at: path.dropFirst(), with: ratio), second: second)
            : .split(orientation: orientation, ratio: previous,
                     first: first, second: second.replacingDividerRatio(at: path.dropFirst(), with: ratio))
    }
}

/// Projection qui conserve les chemins d'origine, même après repli d'un ancêtre absent.
private indirect enum BSPDividerNode {
    case empty
    case leaf
    case split([Bool], BSPOrientation, Double, BSPDividerNode, BSPDividerNode)

    init(_ tree: BSPTree, excluding absent: Set<WindowID>, path: [Bool]) {
        switch tree {
        case .empty: self = .empty
        case .leaf(let id): self = absent.contains(id) ? .empty : .leaf
        case .split(let orientation, let ratio, let first, let second):
            let a = BSPDividerNode(first, excluding: absent, path: path + [true])
            let b = BSPDividerNode(second, excluding: absent, path: path + [false])
            if case .empty = a { self = b }
            else if case .empty = b { self = a }
            else { self = .split(path, orientation, ratio, a, b) }
        }
    }

    func appendDividers(in rect: CGRect, innerGap: CGFloat, to result: inout [BSPDivider]) {
        guard case .split(let path, let orientation, let ratio, let first, let second) = self else { return }
        let children = BSPTree.childRects(of: rect, orientation: orientation, ratio: ratio, innerGap: innerGap)
        // place() applique .integral aux feuilles : arrondir vers l'intérieur de l'espace libre.
        let free: CGRect
        if orientation == .vertical {
            free = CGRect(x: ceil(children.first.maxX), y: ceil(rect.minY),
                          width: max(0, floor(children.second.minX) - ceil(children.first.maxX)),
                          height: max(0, floor(rect.maxY) - ceil(rect.minY)))
        } else {
            free = CGRect(x: ceil(rect.minX), y: ceil(children.first.maxY),
                          width: max(0, floor(rect.maxX) - ceil(rect.minX)),
                          height: max(0, floor(children.second.minY) - ceil(children.first.maxY)))
        }
        // La bande entière reste disponible, mais la prise n'excède pas huit points d'épaisseur.
        let hit = orientation == .vertical
            ? free.insetBy(dx: max(0, (free.width - 8) / 2), dy: 0)
            : free.insetBy(dx: 0, dy: max(0, (free.height - 8) / 2))
        result.append(BSPDivider(path: path, orientation: orientation,
                                 ratio: min(max(ratio, BSPTree.ratioBounds.lowerBound), BSPTree.ratioBounds.upperBound),
                                 container: rect, hitRect: hit,
                                 position: orientation == .vertical
                                    ? CGPoint(x: (children.first.maxX + children.second.minX) / 2, y: rect.midY)
                                    : CGPoint(x: rect.midX, y: (children.first.maxY + children.second.minY) / 2)))
        first.appendDividers(in: children.first, innerGap: innerGap, to: &result)
        second.appendDividers(in: children.second, innerGap: innerGap, to: &result)
    }
}
