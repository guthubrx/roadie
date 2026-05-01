import Foundation
import RoadieCore

/// Protocole que toute stratégie de tiling doit implémenter.
/// Voir contracts/tiler-protocol.md pour les invariants.
public protocol Tiler: AnyObject {
    static var strategyID: TilerStrategy { get }

    /// Calcule les frames pour toutes les feuilles de l'arbre. Pure function.
    func layout(rect: CGRect, root: TilingContainer) -> [WindowID: CGRect]

    /// Insère une feuille dans l'arbre, près d'une cible (typiquement la focalisée).
    func insert(leaf: WindowLeaf, near target: WindowLeaf?, in root: TilingContainer)

    /// Retire une feuille. Normalise les containers parent.
    func remove(leaf: WindowLeaf, from root: TilingContainer)

    /// Déplace une feuille dans une direction. Retourne true si déplacement effectif.
    @discardableResult
    func move(leaf: WindowLeaf, direction: Direction, in root: TilingContainer) -> Bool

    /// Ajuste les ratios pour redimensionner.
    func resize(leaf: WindowLeaf, direction: Direction, delta: CGFloat, in root: TilingContainer)

    /// Trouve la feuille voisine dans une direction. Nil si bord atteint.
    func focusNeighbor(of leaf: WindowLeaf, direction: Direction, in root: TilingContainer) -> WindowLeaf?
}
