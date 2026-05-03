# ADR-002 — N-ary tree with adaptiveWeight (vs pure binary BSP)

🇬🇧 **English** · 🇫🇷 [Français](ADR-002-tree-naire-vs-bsp-binary.fr.md)

**Date**: 2026-05-01 | **Status**: Accepted

## Context

The tree represents the layout of tiled windows. Two approaches:

1. **yabai-style**: strict binary BSP tree. Each internal node has exactly 2 children. Well-suited to BSP, but Master-Stack (1 master + N stacked) must simulate an N-ary container by chaining successive binary splits (cumbersome, fragile).

2. **AeroSpace-style**: N-ary tree. Each internal node (`TilingContainer`) has an orientation and N children with `adaptiveWeight`. BSP is expressed as a container with 2 children; Master-Stack is expressed as a root container with 1 master child + 1 stack sub-container.

## Decision

**Option 2 (N-ary with adaptiveWeight)**.

Structure:
```swift
class TreeNode { weak var parent: TreeNode?; var adaptiveWeight: CGFloat }
class TilingContainer: TreeNode { var children: [TreeNode]; var orientation: Orientation }
class WindowLeaf: TreeNode { let windowID: CGWindowID }
```

Frame computation is recursive: for each container, the `rect` is split proportionally to the children's `adaptiveWeight` along the orientation axis.

## Consequences

### Positive

- **Native Master-Stack**: a vertical container holding the stack, alongside the master, with no contortion.
- **Future strategies are easy to add**: Spiral, Fibonacci, Tabbed can be implemented as new Tilers reusing `TreeNode`.
- **`adaptiveWeight`** enables smooth resizing (the user can adjust ratios without a global recalculation).

### Negative

- More **normalization logic** to write: single-child containers must be collapsed, empty containers removed. ~100 LOC more than pure binary BSP.
- **`move` algorithm** is more complex: a move may traverse several levels of containers (cf. `move-node` in AeroSpace ~150 LOC).

## Rejected alternatives

- **Pure binary BSP** (yabai): simple, but Master-Stack becomes boilerplate plumbing.
- **Flat list** (no hierarchy): only supports trivial layouts (single column, grid).

## References

- AeroSpace: `Sources/AppBundle/tree/TreeNode.swift`, `TilingContainer.swift`
- yabai: `src/view.c` — `struct window_node`
- research.md §2 (tree model)
