import CoreGraphics
import RoadieCore

/// Géométrie préparée d'un resize natif. Les nœuds contrôlés sont repérés une fois ;
/// chaque observation parcourt ensuite l'arbre une fois, sans recherche de fenêtre.
public struct BSPNativeResize: Sendable {
    public struct Layout: Sendable {
        public let tree: BSPTree
        public let frames: [WindowID: CGRect]
    }

    private indirect enum Node: Sendable {
        case empty(BSPTree)
        case leaf(WindowID, CGSize)
        case split(Int, BSPOrientation, Double, Node, Node)

        var visible: Bool {
            if case .empty = self { return false }
            return true
        }
    }

    private let root: Node
    private let startFrame: CGRect
    private let container: CGRect
    private let gap: CGFloat
    private let controls: [Int: BSPEdge]

    /// O(n + d), n feuilles, d profondeur. Les feuilles absentes restent dans l'arbre rendu.
    public init?(tree: BSPTree, windowID: WindowID, in container: CGRect,
                 innerGap: CGFloat = 0, excluding absent: Set<WindowID> = [],
                 knownMinimums: [WindowID: CGSize] = [:], startFrame: CGRect? = nil) {
        let frames = tree.projected(excluding: absent).place(in: container, innerGap: innerGap)
        guard let placed = frames[windowID], Self.valid(container), Self.valid(startFrame ?? placed) else { return nil }
        self.startFrame = startFrame ?? placed
        self.container = container
        gap = max(0, innerGap)
        var nextID = 0
        var nearest: [BSPEdge: Int] = [:]

        func prepare(_ tree: BSPTree) -> (Node, Bool) {
            switch tree {
            case .empty: return (.empty(tree), false)
            case let .leaf(id):
                guard let frame = frames[id] else { return (.empty(tree), false) }
                let minimum = knownMinimums[id] ?? .zero
                return (.leaf(id, CGSize(width: min(max(0, minimum.width), frame.width),
                                        height: min(max(0, minimum.height), frame.height))), id == windowID)
            case let .split(orientation, ratio, first, second):
                let id = nextID
                nextID += 1
                let (a, hasA) = prepare(first)
                let (b, hasB) = prepare(second)
                if !a.visible && !b.visible { return (.empty(tree), false) }
                if a.visible && b.visible && (hasA || hasB) {
                    let edge: BSPEdge = orientation == .vertical
                        ? (hasA ? .right : .left) : (hasA ? .down : .up)
                    // Postordre : le premier nœud retenu est l'ancêtre visible le plus proche.
                    if nearest[edge] == nil { nearest[edge] = id }
                }
                return (.split(id, orientation, ratio, a, b), hasA || hasB)
            }
        }
        let (root, found) = prepare(tree)
        guard found, !nearest.isEmpty else { return nil }
        self.root = root
        controls = Dictionary(uniqueKeysWithValues: nearest.map { ($0.value, $0.key) })
    }

    /// O(n), y compris calcul des minima et des cadres. Aucun accès système ni persistance.
    public func layout(observedFrame frame: CGRect) -> Layout? {
        guard Self.valid(frame) else { return nil }
        let horizontal = abs(frame.width - startFrame.width) > 0.5
        let vertical = abs(frame.height - startFrame.height) > 0.5
        guard horizontal || vertical || frame == startFrame else { return nil }
        var edges: Set<BSPEdge> = []
        if horizontal {
            if abs(frame.minX - startFrame.minX) > 0.5 { edges.insert(.left) }
            if abs(frame.maxX - startFrame.maxX) > 0.5 { edges.insert(.right) }
        }
        if vertical {
            if abs(frame.minY - startFrame.minY) > 0.5 { edges.insert(.up) }
            if abs(frame.maxY - startFrame.maxY) > 0.5 { edges.insert(.down) }
        }
        // Minima en postordre une fois ; pas de calcul de sous-arbre répété dans la descente.
        var minimums: [Int: CGSize] = [:]
        func minimum(_ node: Node) -> CGSize {
            switch node {
            case .empty: return .zero
            case let .leaf(_, size): return size
            case let .split(id, orientation, _, a, b):
                let x = minimum(a), y = minimum(b)
                let size: CGSize
                if !a.visible { size = y }
                else if !b.visible { size = x }
                else if orientation == .vertical {
                    size = CGSize(width: x.width + gap + y.width, height: max(x.height, y.height))
                } else {
                    size = CGSize(width: max(x.width, y.width), height: x.height + gap + y.height)
                }
                minimums[id] = size
                return size
            }
        }
        _ = minimum(root)
        func cachedMinimum(_ node: Node) -> CGSize {
            switch node {
            case .empty: .zero
            case let .leaf(_, size): size
            case let .split(id, _, _, _, _): minimums[id] ?? .zero
            }
        }
        var frames: [WindowID: CGRect] = [:]
        func render(_ node: Node, in rect: CGRect) -> BSPTree {
            switch node {
            case let .empty(tree): return tree
            case let .leaf(id, _): frames[id] = rect.integral; return .leaf(id)
            case let .split(id, orientation, original, a, b):
                if !a.visible {
                    return .split(orientation: orientation, ratio: original,
                                  first: render(a, in: rect), second: render(b, in: rect))
                }
                if !b.visible {
                    return .split(orientation: orientation, ratio: original,
                                  first: render(a, in: rect), second: render(b, in: rect))
                }
                var ratio = original
                let usable = BSPTree.usableExtent(of: rect, orientation: orientation, innerGap: gap)
                if let edge = controls[id], edges.contains(edge), usable > 0 {
                    let seam = BSPTree.gap(for: orientation, in: rect, innerGap: gap)
                    let extent: CGFloat = switch edge {
                    case .right: frame.maxX - rect.minX
                    case .left: frame.minX - seam - rect.minX
                    case .down: frame.maxY - rect.minY
                    case .up: frame.minY - seam - rect.minY
                    }
                    let first = cachedMinimum(a), second = cachedMinimum(b)
                    let firstMin = orientation == .vertical ? first.width : first.height
                    let secondMin = orientation == .vertical ? second.width : second.height
                    let lower = max(BSPTree.ratioBounds.lowerBound, Double(firstMin / usable))
                    let upper = min(BSPTree.ratioBounds.upperBound, Double(1 - secondMin / usable))
                    if lower <= upper {
                        ratio = min(max(Double((floor(extent) + 0.5) / usable), lower), upper)
                    }
                }
                let children = BSPTree.childRects(of: rect, orientation: orientation, ratio: ratio, innerGap: gap)
                return .split(orientation: orientation, ratio: ratio,
                              first: render(a, in: children.first), second: render(b, in: children.second))
            }
        }
        let tree = render(root, in: container)
        return Layout(tree: tree, frames: frames)
    }

    private static func valid(_ frame: CGRect) -> Bool {
        frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite && frame.height.isFinite
            && frame.width > 0 && frame.height > 0
    }
}
