# Journal d'Implémentation — SPEC-014 Manipulation interactive de l'arbre BSP

## Métadonnées
- **Spec** : `014-bsp-tree-manipulation`
- **Branche** : `main`
- **Démarré / Terminé** : 2026-05-22
- **Statut** : Implemented (tests automatiques) — smoke runtime visuel à valider par l'utilisateur

## Résultat

Rend `spatial_bsp` pleinement manipulable comme yabai : déplacer/échanger/redimensionner les fenêtres modifie désormais l'**arbre** (et non plus seulement les frames), donc les changements persistent.

### Opérations d'arbre (RoadieTiler/BSPTree.swift)
- `swapping(_:_:)` : échange deux feuilles, structure préservée (yabai `--swap`).
- `warping(_:nextTo:side:containerIsWide:)` : retire la fenêtre (le frère récupère l'espace) et la réinsère à côté de la voisine (yabai `--warp`).
- `resizing(window:orientation:delta:)` : ajuste le ratio du split ancêtre le plus profond de l'orientation donnée contenant la fenêtre, signe selon first/second, ratio clampé.

### Câblage (RoadieDaemon/WindowCommands.swift)
- Helper `applyBSPTreeMutation(scope:mutate:)` : lit l'arbre, applique la mutation, persiste (flock + writer SPEC-011), retire l'intent pour forcer le re-tile depuis l'arbre.
- `move` → `swapping` (échange avec la voisine directionnelle).
- `warp` → `warping` (déplace à côté de la voisine ; side selon direction).
- `resize` → `resizing` (orientation vertical pour gauche/droite, horizontal pour haut/bas ; delta ±0.05 selon direction).
- Les modes non-`spatial_bsp` gardent strictement leur comportement (branchement `if isSpatialBSP(...)`).

## Tests
- `swift build` (roadied + roadie) : OK (PATH Xcode)
- `swift test` : **465/465 OK** (455 + 10 nouveaux `BSPTreeMutationTests`)
  - swap (permutation, profondeur, no-op), warp (réinsertion, frère récupère), resize (ratio, sens, clamp, orientation profonde, no-op mauvaise orientation)
- Modes existants inchangés.

## Couverture EF / SC
| Critère | Vérifié par |
|---|---|
| EF-001 (swap persiste) | `swapPermutes...`, câblage move + applyBSPTreeMutation persist |
| EF-002 (warp) | `warpMovesWindowNextToNeighbor`, `warpSiblingRecoversSpace...` |
| EF-003 (resize persiste) | `resizeAdjusts...`, câblage resize + persist |
| EF-004 (opérations pures testables) | BSPTreeMutationTests (10) |
| EF-005 (coexistence) | branchement isSpatialBSP, 465 tests dont modes existants |
| EF-006 (persist gated writer) | applyBSPTreeMutation via stageStore (flock + persistStateChanges hérité) |
| SC-003 (455 verts + nouveaux) | 465/465 |

## Limite honnête — smoke runtime visuel
L'implémentation est validée par 465 tests. Le smoke visuel (activer `spatial_bsp`, déplacer/échanger/redimensionner et observer la persistance) **n'a pas été exécuté** (nécessite la config perso + observation). À valider par l'utilisateur.

## Reste pour itérations futures
- Rotation / miroir de l'arbre (yabai `--rotate`, `--mirror`).
- Insertion points manuels avancés.
