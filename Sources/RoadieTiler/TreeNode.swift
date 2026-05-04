import Foundation
import RoadieCore

/// Arbre N-aire (cf. ADR-002).
/// Inspiration AeroSpace, conçu pour supporter BSP, Master-Stack et autres stratégies.

public class TreeNode {
    public weak var parent: TilingContainer?
    public var adaptiveWeight: CGFloat
    /// Dernière frame calculée (mise à jour par layout()). Permet à insert() de choisir
    /// une orientation cohérente avec la forme du target — split horizontal sur target large,
    /// split vertical sur target haute. Évite les cascades BSP rétrécissantes.
    public var lastFrame: CGRect?

    public init(adaptiveWeight: CGFloat = 1.0) {
        self.adaptiveWeight = adaptiveWeight
    }
}

public final class TilingContainer: TreeNode {
    public var children: [TreeNode] = []
    public var orientation: Orientation

    public init(orientation: Orientation, adaptiveWeight: CGFloat = 1.0) {
        self.orientation = orientation
        super.init(adaptiveWeight: adaptiveWeight)
    }

    public func append(_ child: TreeNode) {
        children.append(child)
        child.parent = self
    }

    public func insert(_ child: TreeNode, at index: Int) {
        children.insert(child, at: index)
        child.parent = self
    }

    public func remove(_ child: TreeNode) {
        children.removeAll { $0 === child }
        child.parent = nil
    }

    public func index(of child: TreeNode) -> Int? {
        children.firstIndex { $0 === child }
    }

    public var allLeaves: [WindowLeaf] {
        children.flatMap { node -> [WindowLeaf] in
            if let leaf = node as? WindowLeaf { return [leaf] }
            if let container = node as? TilingContainer { return container.allLeaves }
            return []
        }
    }

    /// SPEC-025 amend — observabilité layout.
    /// Profondeur max de l'arbre depuis ce nœud (leaf=0, container=1+max(children)).
    /// Sert à détecter les arbres "aplatis" (tous les leaves au niveau 1) qui
    /// révèlent un bug dans la cascade d'insertion (= politique BSP non respectée).
    public var maxDepth: Int {
        guard !children.isEmpty else { return 0 }
        let childMax = children.map { node -> Int in
            if node is WindowLeaf { return 0 }
            if let c = node as? TilingContainer { return c.maxDepth }
            return 0
        }.max() ?? 0
        return 1 + childMax
    }

    /// Dump compact à 1 ligne pour log : `H[L12,V[L17848,L20208]]`.
    /// `H` = horizontal, `V` = vertical, `L<wid>` = leaf. Lecture facile pour
    /// replay post-mortem. Limité à 200 char dans le log pour rester compact.
    public var compactStructure: String {
        let kids = children.map { node -> String in
            if let leaf = node as? WindowLeaf { return "L\(leaf.windowID)" }
            if let c = node as? TilingContainer { return c.compactStructure }
            return "?"
        }.joined(separator: ",")
        let prefix = orientation == .horizontal ? "H" : "V"
        return "\(prefix)[\(kids)]"
    }
}

public final class WindowLeaf: TreeNode {
    public let windowID: WindowID
    /// false quand la fenêtre est minimisée. Le tiler skip cette leaf dans son calcul
    /// de frames mais la garde dans la structure de l'arbre, ce qui préserve sa position
    /// d'origine pour la dé-minimisation.
    public var isVisible: Bool = true

    public init(windowID: WindowID, adaptiveWeight: CGFloat = 1.0) {
        self.windowID = windowID
        super.init(adaptiveWeight: adaptiveWeight)
    }
}

/// Helper : détermine si un nœud doit être pris en compte dans le calcul du layout.
/// Une leaf est visible si `isVisible == true`. Un container est visible si au moins
/// un de ses descendants leaves est visible (sinon il occuperait une zone vide).
public func isLayoutVisible(_ node: TreeNode) -> Bool {
    if let leaf = node as? WindowLeaf { return leaf.isVisible }
    if let container = node as? TilingContainer {
        return container.children.contains(where: { isLayoutVisible($0) })
    }
    return true
}

/// Représentation textuelle de l'arbre pour debug/diagnostic.
public func dumpTree(_ node: TreeNode, indent: Int = 0) -> String {
    let prefix = String(repeating: "  ", count: indent)
    if let leaf = node as? WindowLeaf {
        let vis = leaf.isVisible ? "visible" : "hidden"
        return "\(prefix)leaf wid=\(leaf.windowID) weight=\(String(format: "%.2f", leaf.adaptiveWeight)) \(vis)"
    }
    if let container = node as? TilingContainer {
        var lines = ["\(prefix)container[\(container.orientation.rawValue)] weight=\(String(format: "%.2f", container.adaptiveWeight)) children=\(container.children.count)"]
        for child in container.children {
            lines.append(dumpTree(child, indent: indent + 1))
        }
        return lines.joined(separator: "\n")
    }
    return "\(prefix)<unknown>"
}

/// Réajuste tous les `adaptiveWeight` à 1.0 dans l'arbre (équivalent `yabai -m space --balance`).
/// Utile quand le layout est devenu déséquilibré suite à des resize ou des manipulations.
public func balanceWeights(_ node: TreeNode) {
    node.adaptiveWeight = 1.0
    if let container = node as? TilingContainer {
        for child in container.children {
            balanceWeights(child)
        }
    }
}

// MARK: - Helpers de manipulation

public extension TilingContainer {
    /// Retire ce container de son parent et y déplace ses enfants un niveau au-dessus.
    /// Utilisé par la normalisation : container vide ou single-child.
    func collapseInto(parent: TilingContainer) {
        guard let idx = parent.index(of: self) else { return }
        parent.children.remove(at: idx)
        for (offset, child) in children.enumerated() {
            parent.children.insert(child, at: idx + offset)
            child.parent = parent
        }
        children.removeAll()
        self.parent = nil
    }

    /// Supprime les containers vides ou single-child à partir de ce nœud, en remontant.
    func normalize() {
        // 1. Profondeur d'abord
        for child in children.compactMap({ $0 as? TilingContainer }) {
            child.normalize()
        }
        // 2. Single-child : on collapse dans le parent
        if children.count == 1, let parent = parent {
            collapseInto(parent: parent)
            parent.normalize()
            return
        }
        // 3. Empty container : on retire du parent
        if children.isEmpty, let parent = parent {
            parent.remove(self)
            parent.normalize()
        }
    }
}

public extension TreeNode {
    /// Trouve la feuille contenant le windowID donné, recursive.
    static func find(windowID: WindowID, in root: TilingContainer) -> WindowLeaf? {
        for child in root.children {
            if let leaf = child as? WindowLeaf, leaf.windowID == windowID { return leaf }
            if let container = child as? TilingContainer, let found = find(windowID: windowID, in: container) {
                return found
            }
        }
        return nil
    }
}
