# Audit SPEC-012 — Unification du cycle de vie

**Date** : 2026-05-22 | **Mode** : fix | **Grade** : **A**

## Synthèse

Refactor pur : extraction de 7 fonctions de démarrage uniques dans `Sources/roadied/main.swift`, supprimant la duplication entre le mode monolithique (`run`) et les sous-commandes modulaires. Aucune nouvelle fonctionnalité, aucun changement de comportement observable (sauf D2 documenté : `--no-tiler` n'installe plus l'observer d'écran).

## Findings

| ID | Sévérité | Statut |
|----|----------|--------|
| INFO1 | info | resolved (refactor réducteur de dette) |

Aucun finding critical/high/medium/low.

## Conformité Article XVIII

Refactor de déplacement de code, aucune boucle ni hot path introduit. Conforme.

## Tests

428/428 OK. Smoke modulaire : 7 composants, `live_tick` fonctionnel (parité réactivité préservée).

## Verdict

Implémentation conforme. Base de lifecycle unifiée prête pour SPEC-013 (arbre BSP persistant).
