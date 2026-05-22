# Audit SPEC-014 — Manipulation interactive de l'arbre BSP

**Date** : 2026-05-22 | **Mode** : fix | **Grade** : **A**

## Synthèse
`spatial_bsp` devient pleinement mutable : `move` (swap), `warp` et `resize` modifient l'arbre persistant et tiennent dans le temps. Opérations d'arbre pures testées (10 tests), câblage isolé par `isSpatialBSP` (modes existants intacts).

## Findings
| ID | Sévérité | Statut |
|----|----------|--------|
| INFO1 | info | compliant (O(n), n borné, hors hot path) |
| INFO2 | info | resolved (branchement isolé, helper centralisé) |

Aucun critical/high/medium/low.

## Article XVIII
swapping/warping/resizing O(n) feuilles, n borné. Conforme.

## Tests
465/465 OK (455 + 10). Modes existants inchangés.

## Limite
Smoke runtime visuel à valider par l'utilisateur après activation `spatial_bsp`.

## Verdict
Conforme et testé. spatial_bsp est maintenant un BSP mutable façon yabai (insertion + déplacement + échange + resize). Restent rotation/miroir pour une itération future.
