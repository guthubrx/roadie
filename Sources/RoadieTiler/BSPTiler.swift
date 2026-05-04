import Foundation
import RoadieCore

/// Stratégie BSP (Binary Space Partitioning) avec arbre N-aire sous-jacent.
/// Insertion : nouvelle fenêtre splitte le voisin focalisé en 2 (orientation alternée).
/// Layout : récursif avec adaptiveWeight pour les ratios.
public final class BSPTiler: Tiler {
    public static let strategyID: TilerStrategy = .bsp

    /// SPEC-025 amend — politique de split, configurable via [tiling].split_policy.
    public enum SplitPolicy: String, Sendable {
        /// Split sur le côté le plus long de la cible (default).
        /// Comportement actuel : suit l'aspect-ratio physique.
        case largestDim = "largest_dim"
        /// Split orthogonal au parent (alterne H/V à chaque profondeur).
        /// Layouts plus équilibrés, comportement i3/sway classique.
        case dwindle = "dwindle"
    }

    /// Politique active. Set au boot du daemon depuis la config TOML
    /// (`[tiling].split_policy`). Default = .largestDim pour compat backward.
    /// Thread-safe : accédée @MainActor (insertions BSP toujours main thread).
    @MainActor public static var splitPolicy: SplitPolicy = .largestDim

    public init() {}

    /// Auto-enregistrement dans le TilerRegistry. À appeler au bootstrap du daemon.
    public static func register() {
        TilerRegistry.register(.bsp) { BSPTiler() }
    }

    // MARK: - layout

    public func layout(rect: CGRect, root: TilingContainer) -> [WindowID: CGRect] {
        var result: [WindowID: CGRect] = [:]
        layoutRecursive(node: root, rect: rect, into: &result)
        return result
    }

    private func layoutRecursive(node: TreeNode, rect: CGRect, into result: inout [WindowID: CGRect]) {
        node.lastFrame = rect   // mémoïsation pour orientation-auto à l'insert
        if let leaf = node as? WindowLeaf {
            // Skip les leaves invisibles (minimisées) — leur position est préservée
            // dans l'arbre mais elles ne consomment pas d'espace au layout.
            if leaf.isVisible { result[leaf.windowID] = rect }
            return
        }
        guard let container = node as? TilingContainer, !container.children.isEmpty else { return }
        // Ne distribuer l'espace qu'entre les enfants visibles (au moins une leaf descendante visible).
        let visibleChildren = container.children.filter { isLayoutVisible($0) }
        guard !visibleChildren.isEmpty else { return }
        let totalWeight = visibleChildren.reduce(CGFloat(0)) { $0 + $1.adaptiveWeight }
        guard totalWeight > 0 else { return }

        if container.orientation == .horizontal {
            var x = rect.origin.x
            for child in visibleChildren {
                let w = rect.width * (child.adaptiveWeight / totalWeight)
                let childRect = CGRect(x: x, y: rect.origin.y, width: w, height: rect.height)
                layoutRecursive(node: child, rect: childRect, into: &result)
                x += w
            }
        } else {
            var y = rect.origin.y
            for child in visibleChildren {
                let h = rect.height * (child.adaptiveWeight / totalWeight)
                let childRect = CGRect(x: rect.origin.x, y: y, width: rect.width, height: h)
                layoutRecursive(node: child, rect: childRect, into: &result)
                y += h
            }
        }
    }

    // MARK: - insert / remove

    public func insert(leaf: WindowLeaf, near target: WindowLeaf?, in root: TilingContainer) {
        // Idempotence : si déjà présent, ne rien faire.
        if TreeNode.find(windowID: leaf.windowID, in: root) != nil { return }

        guard let target = target else {
            root.append(leaf)
            return
        }
        guard let parent = target.parent else {
            root.append(leaf)
            return
        }
        guard let idx = parent.index(of: target) else {
            root.append(leaf)
            return
        }

        // Auto-orientation selon la politique de split active.
        //   .largestDim : orientation choisie par l'aspect ratio du target
        //     (target large → split horizontal, target haute → split vertical)
        //   .dwindle    : orientation = opposée du parent (alterne H/V à
        //     chaque profondeur d'arbre, layout plus équilibré)
        // Fallback (.largestDim) : opposite du parent si target.lastFrame nil.
        let orientation: Orientation
        let reason: String
        var fallbackUsed = false
        let policy = MainActor.assumeIsolated { BSPTiler.splitPolicy }
        switch policy {
        case .largestDim:
            if let frame = target.lastFrame {
                orientation = frame.width >= frame.height ? .horizontal : .vertical
                reason = "policy=largest_dim aspect-ratio w=\(Int(frame.width)) h=\(Int(frame.height))"
            } else {
                orientation = parent.orientation.opposite
                reason = "policy=largest_dim fallback parent.opposite (target.lastFrame=nil)"
                fallbackUsed = true
            }
        case .dwindle:
            orientation = parent.orientation.opposite
            reason = "policy=dwindle parent_orientation=\(parent.orientation.rawValue).opposite"
        }
        // SPEC-025 amend — log structuré info pour traçabilité et observabilité.
        // Permet le replay post-mortem d'une insertion BSP qui aurait dérapé du
        // pattern attendu (= split sur côté le plus long).
        let tw = target.lastFrame.map { Int($0.width) } ?? -1
        let th = target.lastFrame.map { Int($0.height) } ?? -1
        logInfo("tiler_insert", [
            "strategy": "bsp",
            "new_wid": String(leaf.windowID),
            "target_wid": String(target.windowID),
            "orientation": orientation.rawValue,
            "parent_orientation": parent.orientation.rawValue,
            "target_w": String(tw),
            "target_h": String(th),
            "reason": reason,
        ])
        // Invariant : si la décision dépend du fallback (lastFrame nil), c'est
        // qu'on n'a pas pu calculer l'orientation idéale et on a peut-être
        // produit une division non-conforme à BSP "split-côté-le-plus-long".
        // Warn pour pouvoir mesurer la fréquence en prod.
        if fallbackUsed {
            logWarn("tiler_invariant_violation", [
                "strategy": "bsp",
                "invariant": "split_axis_from_aspect_ratio",
                "actual": "fallback_parent_opposite",
                "expected": "axis_orthogonal_to_target_longest_side",
                "wid": String(leaf.windowID),
                "target_wid": String(target.windowID),
            ])
        }

        let subContainer = TilingContainer(orientation: orientation,
                                           adaptiveWeight: target.adaptiveWeight)
        parent.children[idx] = subContainer
        subContainer.parent = parent
        target.adaptiveWeight = 1.0
        leaf.adaptiveWeight = 1.0
        target.parent = nil   // sera réattaché juste après
        subContainer.append(target)
        subContainer.append(leaf)
    }

    public func remove(leaf: WindowLeaf, from root: TilingContainer) {
        guard let parent = leaf.parent else { return }
        parent.remove(leaf)
        parent.normalize()
        // Après normalize, parent peut être détaché si vide. Si root devient vide, c'est OK.
    }

    // MARK: - move

    public func move(leaf: WindowLeaf, direction: Direction, in root: TilingContainer) -> Bool {
        // Algorithme : remonter jusqu'à trouver un container dont l'orientation
        // matche la direction. Là on cherche le voisin (frère ou cousin) à swap.
        var current: TreeNode = leaf
        while let parent = current.parent {
            if parent.orientation == direction.orientation {
                guard let idx = parent.index(of: current) else { return false }
                let targetIdx = direction.sign > 0 ? idx + 1 : idx - 1
                if targetIdx < 0 || targetIdx >= parent.children.count {
                    // bord atteint dans ce parent, on remonte d'un niveau
                    current = parent
                    continue
                }
                // swap
                parent.children.swapAt(idx, targetIdx)
                return true
            }
            current = parent
        }
        return false
    }

    // MARK: - resize

    public func resize(leaf: WindowLeaf, direction: Direction, delta: CGFloat, in root: TilingContainer) {
        // Trouve le container parent dont l'orientation correspond à la direction.
        var current: TreeNode = leaf
        while let parent = current.parent {
            if parent.orientation == direction.orientation {
                guard let idx = parent.index(of: current) else { return }
                let targetIdx = direction.sign > 0 ? idx + 1 : idx - 1
                if targetIdx < 0 || targetIdx >= parent.children.count { return }
                // Transfert de poids de delta (en pixels) vers/depuis le voisin.
                // Approximation : 1 px = 0.001 unité de weight. Calibrage empirique.
                let unit: CGFloat = 0.001
                let transfer = delta * unit
                current.adaptiveWeight = max(0.1, current.adaptiveWeight + transfer)
                parent.children[targetIdx].adaptiveWeight = max(0.1,
                    parent.children[targetIdx].adaptiveWeight - transfer)
                return
            }
            current = parent
        }
    }

    // MARK: - focusNeighbor

    public func focusNeighbor(of leaf: WindowLeaf, direction: Direction, in root: TilingContainer) -> WindowLeaf? {
        // Remonte jusqu'à trouver un container avec une orientation qui matche
        // et un voisin dans la bonne direction.
        var current: TreeNode = leaf
        while let parent = current.parent {
            if parent.orientation == direction.orientation {
                guard let idx = parent.index(of: current) else { return nil }
                let targetIdx = direction.sign > 0 ? idx + 1 : idx - 1
                if targetIdx >= 0 && targetIdx < parent.children.count {
                    // Trouvé un voisin. Descendre dans son arbre pour récupérer une leaf.
                    return descendToLeaf(parent.children[targetIdx], preferring: direction)
                }
            }
            current = parent
        }
        return nil
    }

    /// Descend dans l'arbre vers une feuille, en préférant le côté correspondant à la direction.
    private func descendToLeaf(_ node: TreeNode, preferring direction: Direction) -> WindowLeaf? {
        if let leaf = node as? WindowLeaf { return leaf }
        guard let container = node as? TilingContainer, !container.children.isEmpty else { return nil }
        // Si le container est dans la direction du mouvement, prendre le coin proche.
        // Sinon, prendre le 1er enfant.
        let pickIndex: Int
        if container.orientation == direction.orientation {
            pickIndex = direction.sign > 0 ? 0 : container.children.count - 1
        } else {
            pickIndex = 0
        }
        return descendToLeaf(container.children[pickIndex], preferring: direction)
    }
}
