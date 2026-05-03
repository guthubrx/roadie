# ADR-002 — Arbre N-aire avec adaptiveWeight (vs BSP binaire pur)

🇫🇷 **Français** · 🇬🇧 [English](ADR-002-tree-naire-vs-bsp-binary.md)

**Date** : 2026-05-01 | **Statut** : Accepté

## Contexte

L'arbre représente la disposition des fenêtres tilées. Deux approches :

1. **yabai-style** : arbre binaire BSP strict. Chaque nœud interne a exactement 2 enfants. Bien adapté à BSP, mais Master-Stack (1 master + N en pile) doit simuler un container N-aire en chaînant des splits binaires successifs (lourd, fragile).

2. **AeroSpace-style** : arbre N-aire. Chaque nœud interne (`TilingContainer`) a une orientation et N enfants avec `adaptiveWeight`. BSP s'exprime comme contenant 2 enfants, Master-Stack comme un container racine avec 1 enfant master + 1 sous-container stack.

## Décision

**Option 2 (N-aire avec adaptiveWeight)**.

Structure :
```swift
class TreeNode { weak var parent: TreeNode?; var adaptiveWeight: CGFloat }
class TilingContainer: TreeNode { var children: [TreeNode]; var orientation: Orientation }
class WindowLeaf: TreeNode { let windowID: CGWindowID }
```

Le calcul de frame est récursif : pour chaque container, partage `rect` proportionnellement aux `adaptiveWeight` des enfants selon l'orientation.

## Conséquences

### Positives

- **Master-Stack natif** : un container vertical contenant la pile, à côté du master, sans contorsion.
- **Stratégies futures faciles** : Spiral, Fibonacci, Tabbed peuvent être ajoutées comme nouveaux Tilers en réutilisant le TreeNode.
- **`adaptiveWeight`** permet des resize fluides (l'utilisateur peut ajuster les ratios sans recalcul global).

### Négatives

- Plus de logique de **normalisation** à écrire : containers à 1 enfant doivent être collapsés, containers vides supprimés. ~100 LOC de plus que BSP binaire.
- **Algorithme `move`** plus complexe : un déplacement peut traverser plusieurs niveaux de containers (cf. `move-node` AeroSpace ~150 LOC).

## Alternatives rejetées

- **BSP binaire pur** (yabai) : simple, mais Master-Stack devient une plomberie.
- **Liste plate** (sans hiérarchie) : ne supporte que des layouts triviaux (1 colonne, grille).

## Références

- AeroSpace : `Sources/AppBundle/tree/TreeNode.swift`, `TilingContainer.swift`
- yabai : `src/view.c` — `struct window_node`
- research.md §2 (modèle arbre)
