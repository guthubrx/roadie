# Tiler Protocol — Swift Interface

**Feature** : 002-tiler-stage | **Phase** : 1 | **Date** : 2026-05-01

Ce document est le contrat normatif que toute implémentation `Tiler` doit respecter.

---

## Définition

```swift
import CoreGraphics

public protocol Tiler {
    /// Identifiant unique pour serialization config et logs.
    static var strategyID: TilerStrategy { get }

    /// Calcule les frames pour les fenêtres données dans le rect cible.
    /// Doit être pure : appel répété avec les mêmes paramètres = même résultat.
    /// - Parameters:
    ///   - rect: rectangle cible (typiquement la zone utile de l'écran moins les gaps externes)
    ///   - root: racine de l'arbre courant pour ce workspace
    /// - Returns: dictionnaire `[CGWindowID: CGRect]` couvrant TOUTES les feuilles de l'arbre.
    func layout(rect: CGRect, root: TilingContainer) -> [CGWindowID: CGRect]

    /// Insère une nouvelle feuille dans l'arbre.
    /// La stratégie décide où exactement (split BSP / append pile Master-Stack / ...).
    /// - Parameters:
    ///   - leaf: nouvelle feuille (avec parent=nil au moment de l'appel)
    ///   - target: feuille de référence pour l'insertion (typiquement la focalisée)
    ///   - root: racine workspace (peut être mutée — l'insertion peut créer/supprimer des containers intermédiaires)
    func insert(leaf: WindowLeaf, near target: WindowLeaf?, in root: TilingContainer)

    /// Retire une feuille de l'arbre. Normalise les containers parent (collapse single-child).
    func remove(leaf: WindowLeaf, from root: TilingContainer)

    /// Déplace une feuille dans une direction. Peut traverser plusieurs containers.
    /// - Returns: true si déplacement effectué, false si pas de cible (bord d'écran atteint).
    func move(leaf: WindowLeaf, direction: Direction, in root: TilingContainer) -> Bool

    /// Redimensionne une feuille en ajustant les adaptiveWeight des frères.
    /// - Parameter delta: variation en pixels dans la direction donnée.
    func resize(leaf: WindowLeaf, direction: Direction, delta: CGFloat, in root: TilingContainer)

    /// Trouve la feuille voisine dans une direction (pour `focus`).
    /// - Returns: WindowLeaf voisine ou nil si bord atteint.
    func focusNeighbor(of leaf: WindowLeaf, direction: Direction, in root: TilingContainer) -> WindowLeaf?
}
```

---

## Invariants à respecter

### I1 — Pureté de `layout`

`layout(rect:root:)` est une **fonction pure** : aucun side-effect, aucune dépendance à un état externe au-delà de ses arguments. Le même `(rect, root)` doit produire le même résultat. Cela permet de cacher les calculs et de paralléliser si nécessaire.

### I2 — Couverture totale

Le résultat de `layout` doit couvrir **toutes les feuilles** de l'arbre. Aucune fenêtre ne doit avoir un frame manquant. Si une feuille existe dans l'arbre, elle a un rect dans le retour.

### I3 — Pas d'overlap

Les rects retournés par `layout` ne se superposent pas. La somme de leurs aires (moins les gaps inter-fenêtres) égale l'aire du rect cible.

### I4 — Idempotence d'`insert`

Insérer la même feuille deux fois est un **no-op silencieux** (pas d'erreur, pas de duplicata dans l'arbre).

### I5 — Symétrie `insert/remove`

Pour toute séquence `insert(L, near: T) ; remove(L)`, l'arbre revient à son état initial. La normalisation post-remove (collapse, merge) est idempotente.

### I6 — Tolérance `target == nil`

Si `target` est nil dans `insert`, la stratégie choisit une politique par défaut (BSP : append à la racine ; Master-Stack : ajout en pile).

### I7 — Stabilité `focusNeighbor`

Pour toute feuille L et direction D, `focusNeighbor(L, D)` retourne soit nil, soit une feuille différente de L (jamais L elle-même).

---

## Protocole étendu — `Configurable`

Pour les stratégies paramétrables (Master-Stack ratio, BSP split direction par défaut), un protocole secondaire :

```swift
public protocol ConfigurableTiler: Tiler {
    associatedtype Config: Codable
    var config: Config { get set }
}
```

Exemple Master-Stack :

```swift
struct MasterStackConfig: Codable {
    var masterRatio: CGFloat = 0.6           // [0.1, 0.9]
    var masterPosition: Edge = .left         // left | right | top | bottom
    var stackOrientation: Orientation = .vertical
}
```

---

## Implémentation BSP de référence

```swift
public class BSPTiler: Tiler {
    public static let strategyID: TilerStrategy = .bsp

    public func layout(rect: CGRect, root: TilingContainer) -> [CGWindowID: CGRect] {
        var result: [CGWindowID: CGRect] = [:]
        layoutRecursive(node: root, rect: rect, into: &result)
        return result
    }

    private func layoutRecursive(node: TreeNode, rect: CGRect, into result: inout [CGWindowID: CGRect]) {
        switch node {
        case let leaf as WindowLeaf:
            result[leaf.windowID] = rect
        case let container as TilingContainer:
            let totalWeight = container.children.reduce(CGFloat(0)) { $0 + $1.adaptiveWeight }
            var offset: CGFloat = 0
            for child in container.children {
                let ratio = child.adaptiveWeight / totalWeight
                let childRect = computeChildRect(parent: rect,
                                                 orientation: container.orientation,
                                                 offset: offset,
                                                 ratio: ratio)
                layoutRecursive(node: child, rect: childRect, into: &result)
                offset += container.orientation == .horizontal ? rect.width * ratio : rect.height * ratio
            }
        default:
            fatalError("Unknown TreeNode type")
        }
    }

    public func insert(leaf: WindowLeaf, near target: WindowLeaf?, in root: TilingContainer) {
        // Cas 1 : pas de cible → append à la racine
        guard let target = target else {
            root.children.append(leaf)
            leaf.parent = root
            return
        }
        // Cas 2 : la cible a un parent container, on insère dans le même container après la cible
        guard let parent = target.parent as? TilingContainer else { return }
        let idx = parent.children.firstIndex { $0 === target }!
        // BSP : on splitte en créant un sous-container avec orientation opposée si nécessaire
        // Simplification V1 : append au même niveau, alternance via enable-normalization-opposite
        parent.children.insert(leaf, at: idx + 1)
        leaf.parent = parent
    }

    public func remove(leaf: WindowLeaf, from root: TilingContainer) {
        guard let parent = leaf.parent as? TilingContainer else { return }
        parent.children.removeAll { $0 === leaf }
        leaf.parent = nil
        normalizeContainer(parent)
    }

    private func normalizeContainer(_ container: TilingContainer) {
        // Collapse : container avec 1 enfant → on remplace le container par son enfant
        if container.children.count == 1, let parent = container.parent as? TilingContainer {
            let child = container.children[0]
            let idx = parent.children.firstIndex { $0 === container }!
            parent.children[idx] = child
            child.parent = parent
        }
        // Suppression : container vide → on retire du parent
        if container.children.isEmpty, let parent = container.parent as? TilingContainer {
            parent.children.removeAll { $0 === container }
            container.parent = nil
            normalizeContainer(parent)
        }
    }

    public func move(leaf: WindowLeaf, direction: Direction, in root: TilingContainer) -> Bool {
        // Algorithme de move : remonte l'arbre jusqu'à trouver un container dont l'orientation
        // correspond à la direction, puis swap avec le voisin si possible.
        // Détails dans BSPTiler.swift implem.
        // ...
        return false  // stub
    }

    public func resize(leaf: WindowLeaf, direction: Direction, delta: CGFloat, in root: TilingContainer) {
        // Trouve le container parent, ajuste adaptiveWeight des frères.
        // ...
    }

    public func focusNeighbor(of leaf: WindowLeaf, direction: Direction, in root: TilingContainer) -> WindowLeaf? {
        // Recherche du voisin via traversée de l'arbre (similaire à move mais sans modification).
        // ...
        return nil  // stub
    }
}
```

---

## Comment ajouter une nouvelle stratégie

1. Créer un fichier `Sources/RoadieTiler/<Name>Tiler.swift`.
2. Conformer au protocole `Tiler` (et optionnellement `ConfigurableTiler`).
3. Ajouter le cas dans l'enum `TilerStrategy`.
4. Enregistrer dans le registre (V1 : switch dans `LayoutEngine.makeTiler(strategy:)`).
5. Écrire les tests unitaires `Tests/RoadieTilerTests/<Name>TilerTests.swift`.
6. Documenter dans `quickstart.md` la nouvelle option de config.

V1 : enregistrement statique via switch case. V2 : registre dynamique pour permettre les plugins externes.

---

## Tests requis pour toute implémentation

Pour qu'une implémentation soit considérée valide, elle DOIT passer les tests suivants :

1. `test_layout_empty_root` — root vide → `[:]`
2. `test_layout_single_window` — une feuille → couvre 100 % du rect
3. `test_layout_two_windows_equal_split` — 2 feuilles avec même weight → split 50/50
4. `test_layout_three_windows_different_weights` — vérifie ratios
5. `test_insert_into_empty` — insert sur arbre vide
6. `test_insert_after_target` — order préservé
7. `test_remove_normalizes_parent` — container 1-child collapsé
8. `test_focus_neighbor_horizontal` — left/right
9. `test_focus_neighbor_vertical` — up/down
10. `test_focus_neighbor_at_edge` — retour nil aux bords

Plus 5 tests par stratégie spécifique (BSP : alternation orientation ; Master-Stack : ratio configurable, etc.).
