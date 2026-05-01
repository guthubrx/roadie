import Foundation
import RoadieCore

/// Stratégie Master-Stack : 1 fenêtre dominante (master) à gauche, les autres en pile à droite.
/// Architecture arbre :
///     root (horizontal)
///         ├── master leaf (weight = ratio)
///         └── stack (vertical, weight = 1-ratio)
///                ├── leaf 2
///                ├── leaf 3
///                └── ...
public final class MasterStackTiler: Tiler {
    public static let strategyID: TilerStrategy = .masterStack

    public var masterRatio: CGFloat = 0.6

    public init(masterRatio: CGFloat = 0.6) {
        self.masterRatio = masterRatio
    }

    /// Auto-enregistrement dans le TilerRegistry. À appeler au bootstrap du daemon.
    public static func register() {
        TilerRegistry.register(.masterStack) { MasterStackTiler() }
    }

    // MARK: - layout (réutilise l'algorithme général de partage par adaptiveWeight)

    public func layout(rect: CGRect, root: TilingContainer) -> [WindowID: CGRect] {
        var result: [WindowID: CGRect] = [:]
        layoutRecursive(node: root, rect: rect, into: &result)
        return result
    }

    private func layoutRecursive(node: TreeNode, rect: CGRect, into result: inout [WindowID: CGRect]) {
        node.lastFrame = rect
        if let leaf = node as? WindowLeaf {
            if leaf.isVisible { result[leaf.windowID] = rect }
            return
        }
        guard let container = node as? TilingContainer, !container.children.isEmpty else { return }
        let visibleChildren = container.children.filter { isLayoutVisible($0) }
        guard !visibleChildren.isEmpty else { return }
        let totalWeight = visibleChildren.reduce(CGFloat(0)) { $0 + $1.adaptiveWeight }
        guard totalWeight > 0 else { return }
        if container.orientation == .horizontal {
            var x = rect.origin.x
            for child in visibleChildren {
                let w = rect.width * (child.adaptiveWeight / totalWeight)
                let r = CGRect(x: x, y: rect.origin.y, width: w, height: rect.height)
                layoutRecursive(node: child, rect: r, into: &result)
                x += w
            }
        } else {
            var y = rect.origin.y
            for child in visibleChildren {
                let h = rect.height * (child.adaptiveWeight / totalWeight)
                let r = CGRect(x: rect.origin.x, y: y, width: rect.width, height: h)
                layoutRecursive(node: child, rect: r, into: &result)
                y += h
            }
        }
    }

    // MARK: - insert

    public func insert(leaf: WindowLeaf, near target: WindowLeaf?, in root: TilingContainer) {
        if TreeNode.find(windowID: leaf.windowID, in: root) != nil { return }

        // Cas 1 : root vide → leaf devient master.
        if root.children.isEmpty {
            root.orientation = .horizontal
            leaf.adaptiveWeight = 1.0
            root.append(leaf)
            return
        }

        // Cas 2 : root contient un seul leaf (master sans stack) → on crée la stack.
        if root.children.count == 1, let master = root.children[0] as? WindowLeaf {
            master.adaptiveWeight = masterRatio
            let stack = TilingContainer(orientation: .vertical,
                                        adaptiveWeight: 1.0 - masterRatio)
            stack.append(leaf)
            root.append(stack)
            return
        }

        // Cas 3 : root déjà avec master + stack → ajout dans la stack.
        if root.children.count >= 2, let stack = root.children[1] as? TilingContainer {
            stack.append(leaf)
            return
        }

        // Fallback : append à la racine.
        root.append(leaf)
    }

    // MARK: - remove

    public func remove(leaf: WindowLeaf, from root: TilingContainer) {
        guard let parent = leaf.parent else { return }
        parent.remove(leaf)

        // Si la stack devient vide, la retirer.
        if let parent = parent as? TilingContainer, parent.children.isEmpty, parent !== root {
            root.remove(parent)
        }

        // Si on a retiré le master mais qu'il reste une stack avec ≥1 leaf,
        // promouvoir la 1ère leaf de la stack en master.
        if root.children.count == 1, let onlyChild = root.children.first as? TilingContainer,
           let firstStackLeaf = onlyChild.children.first as? WindowLeaf {
            onlyChild.remove(firstStackLeaf)
            firstStackLeaf.adaptiveWeight = masterRatio
            root.children.insert(firstStackLeaf, at: 0)
            firstStackLeaf.parent = root
            if onlyChild.children.isEmpty { root.remove(onlyChild) }
        }

        // Si root contient juste un seul leaf, ce leaf prend tout l'espace.
        if root.children.count == 1, let only = root.children.first {
            only.adaptiveWeight = 1.0
        }
    }

    // MARK: - move (master ↔ stack)

    @discardableResult
    public func move(leaf: WindowLeaf, direction: Direction, in root: TilingContainer) -> Bool {
        // Master-Stack supporte un move basique gauche/droite : master ↔ première leaf stack.
        guard let parent = leaf.parent else { return false }
        if parent === root, let stack = root.children.last as? TilingContainer,
           let firstStackLeaf = stack.children.first as? WindowLeaf {
            // leaf est master, on swap avec la 1ère leaf stack
            if direction == .right {
                root.children[0] = firstStackLeaf
                firstStackLeaf.parent = root
                firstStackLeaf.adaptiveWeight = masterRatio
                stack.children[0] = leaf
                leaf.parent = stack
                leaf.adaptiveWeight = 1.0
                return true
            }
        }
        if let stack = parent as? TilingContainer, stack.parent === root,
           let master = root.children.first as? WindowLeaf, leaf !== master {
            // leaf dans la stack
            if direction == .left, let idx = stack.children.firstIndex(where: { $0 === leaf }), idx == 0 {
                root.children[0] = leaf
                leaf.parent = root
                leaf.adaptiveWeight = masterRatio
                stack.children[0] = master
                master.parent = stack
                master.adaptiveWeight = 1.0
                return true
            }
        }
        return false
    }

    // MARK: - resize

    public func resize(leaf: WindowLeaf, direction: Direction, delta: CGFloat, in root: TilingContainer) {
        // Pour Master-Stack, le seul resize qui a vraiment du sens est gauche/droite (ratio master).
        if direction == .left || direction == .right {
            guard root.children.count >= 2,
                  let master = root.children[0] as? WindowLeaf,
                  let stack = root.children[1] as? TilingContainer else { return }
            let unit: CGFloat = 0.001
            let transfer = delta * unit
            master.adaptiveWeight = max(0.1, min(0.9, master.adaptiveWeight + transfer))
            stack.adaptiveWeight = 1.0 - master.adaptiveWeight
            masterRatio = master.adaptiveWeight
        } else {
            // Resize vertical dans la stack : ajuste les frères de la leaf.
            guard let stack = leaf.parent as? TilingContainer, stack !== root else { return }
            guard let idx = stack.index(of: leaf) else { return }
            let targetIdx = direction == .up ? idx - 1 : idx + 1
            if targetIdx < 0 || targetIdx >= stack.children.count { return }
            let unit: CGFloat = 0.001
            let transfer = delta * unit
            leaf.adaptiveWeight = max(0.1, leaf.adaptiveWeight + transfer)
            stack.children[targetIdx].adaptiveWeight = max(0.1, stack.children[targetIdx].adaptiveWeight - transfer)
        }
    }

    // MARK: - focusNeighbor

    public func focusNeighbor(of leaf: WindowLeaf, direction: Direction, in root: TilingContainer) -> WindowLeaf? {
        guard let parent = leaf.parent else { return nil }
        if parent === root {
            // leaf est master
            if direction == .right, let stack = root.children.last as? TilingContainer,
               let first = stack.children.first as? WindowLeaf { return first }
            return nil
        }
        // leaf est dans la stack
        if let stack = parent as? TilingContainer {
            switch direction {
            case .left:
                return root.children.first as? WindowLeaf
            case .up:
                guard let idx = stack.index(of: leaf), idx > 0 else { return nil }
                return stack.children[idx - 1] as? WindowLeaf
            case .down:
                guard let idx = stack.index(of: leaf), idx < stack.children.count - 1 else { return nil }
                return stack.children[idx + 1] as? WindowLeaf
            case .right:
                return nil
            }
        }
        return nil
    }
}
