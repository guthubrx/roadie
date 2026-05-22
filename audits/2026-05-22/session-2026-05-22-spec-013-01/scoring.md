# Audit SPEC-013 — Arbre BSP persistant

**Date** : 2026-05-22 | **Mode** : fix | **Grade** : **A**

## Synthèse

Vrai BSP à arbre persistant (yabai/i3) : nouvelle fenêtre divise uniquement le pane focalisé, structure mémorisée, direction configurable. Cœur pur testé à 100% (modèle d'arbre + stratégie), intégration runtime (mode, config, persistance, reconciliation). Modes existants intacts.

## Findings

| ID | Sévérité | Statut |
|----|----------|--------|
| P1 | info | compliant (complexité documentée, n borné) |
| R1 | low | noted (persistance bornée + flock, à surveiller) |
| INFO2 | info | resolved (repli défensif) |

Aucun finding critical/high/medium.

## Conformité Article XVIII

`BSPTree.inserting` O(n²) au pire, `reconciled` O(k·n) ; n = fenêtres d'un stage, borné par construction. Commentaire de complexité ajouté documentant le compromis. Conforme §4.

## Tests

455/455 OK (428 baseline + 27 SPEC-013). Modes balanced/dwindle/masterStack/float inchangés.

## Limite

Smoke runtime visuel (activation `spatial_bsp` + observation) à valider par l'utilisateur — non exécuté car nécessite modification de la config personnelle.

## Verdict

Implémentation conforme et testée. Prête à l'activation par l'utilisateur.
