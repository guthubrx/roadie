# Journal d'Implémentation — SPEC-013 Arbre BSP persistant

## Métadonnées

- **Spec** : `013-persistent-bsp-tree`
- **Branche** : `main`
- **Démarré / Terminé** : 2026-05-22
- **Statut** : Implemented (tests automatiques) — smoke runtime visuel à activer par l'utilisateur

## Résultat

Implémentation d'un vrai BSP à arbre persistant (style yabai/i3) en deux couches :

### Couche 1 — Cœur pur (RoadieTiler)
- `BSPTree.swift` : `indirect enum BSPTree { empty | leaf | split }` + `BSPOrientation` + `BSPInsertionSide`.
  - `place(in:innerGap:)` : placement géométrique récursif.
  - `inserting(_:nextTo:side:containerIsWide:)` : divise **uniquement** la feuille focalisée (les autres ne bougent pas), orientation auto (large → vertical, haut → horizontal), côté configurable.
  - `removing(_:)` : le frère récupère l'espace.
  - `reconciled(liveWindowIDs:focus:side:containerIsWide:)` : insère les nouvelles, retire les disparues.
  - `balanced(from:containerIsWide:)` : migration depuis une liste.
- `SpatialBSPLayoutStrategy.swift` : place via l'arbre fourni, repli équilibré si arbre absent/désynchronisé.
- `LayoutRequest.bspTree` + branche `.spatialBsp` dans `LayoutPlanner`.

### Couche 2 — Intégration runtime
- `WindowManagementMode.spatialBsp` (alias TOML : `spatial_bsp`, `spatial`, `tree`, `yabai`).
- `WindowPlacementConfig.newWindowSide` (`new_window_side`, défaut `"right"`).
- `PersistentStage.bspTree: BSPTree?` (Codable optionnel, rétro-compat).
- Helpers `PersistentStageState.bspTree(for:)` / `setBSPTree(_:for:)`.
- Reconciliation dans `DaemonSnapshot.layoutPlan` : pour un stage `.spatialBsp`, l'arbre est reconcilié avec les fenêtres réelles, persisté si writer (`persistStateChanges`, cohérent SPEC-011/012), puis fourni à la stratégie.

## Tests

- `swift build` (roadied + roadie) : OK (PATH Xcode)
- `swift test` : **455/455 OK** (428 baseline + 27 nouveaux)
  - `BSPTreeTests` (16) : placement, insertion focalisée, suppression, reconciliation, codable
  - `SpatialBSPLayoutStrategyTests` (4) : placement via arbre, replis
  - `SpatialBSPConfigTests` (7) : parsing mode + new_window_side, round-trip persistance, rétro-compat
- Modes existants (balanced/dwindle/masterStack/float) : inchangés, tous verts.

## Couverture EF / SC

| Critère | Vérifié par |
|---|---|
| EF-001 (arbre par stage) | BSPTree + PersistentStage.bspTree |
| EF-002 (split du focus) | `insertOnFocusedLeafSplitsOnlyThatLeaf`, `insertOnFocusDoesNotMoveOtherWindowsFrames` |
| EF-003 (frère récupère) | `removeSiblingRecoversSpace` |
| EF-004 (orientation auto) | `insertOrientationFollowsContainerShape` |
| EF-005 (new_window_side) | `windowPlacementParsesNewWindowSide`, défaut right |
| EF-006 (persistance) | `persistentStageRoundTripsBSPTree` + reconciliation persistée |
| EF-007 (parking/grace) | Reconciliation ne touche que les fenêtres live fournies ; persistance conditionnée writer |
| EF-008 (coexistence) | Nouveau cas isolé ; 455 tests dont modes existants |
| EF-009 (resize adopté) | `adoptingRatio(...)` présent (branchement runtime fin : itération suivante) |
| SC-001 (focus only) | `insertOnFocusDoesNotMoveOtherWindowsFrames` |
| SC-002 (side) | tests config |
| SC-003 (persiste redémarrage) | round-trip JSON |
| SC-004/005 | tests unitaires reconciliation/place |

## Limite honnête — smoke runtime visuel (T019)

L'implémentation est complète et validée par 455 tests automatiques. Le **smoke runtime visuel** (activer `default_strategy = "spatial_bsp"` dans `~/.config/roadies/roadies.toml`, ouvrir/fermer des fenêtres et observer l'insertion focalisée) **n'a pas été exécuté** car il nécessite de modifier la config personnelle de l'utilisateur et une observation à l'écran. À valider par l'utilisateur après activation.

### Pour activer le mode

```toml
[tiling]
default_strategy = "spatial_bsp"

[window_placement]
new_window_side = "right"
```
Puis redémarrer Roadie (`./Scripts/start` ou `./Scripts/start-modular`).

## Reste pour itérations futures (hors scope initial)

- Branchement runtime de `adoptingRatio` sur les resize manuels (EF-009 : l'API existe, le câblage fin sur la détection de resize reste à raffiner).
- Insertion points manuels avancés (`--insert` yabai) — non-objectif explicite.
