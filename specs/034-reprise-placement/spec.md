# Session 034 — Reprise du placement à l’ouverture

Spec: 034-reprise-placement
Titre: Attendre une fenêtre déplaçable avant de réserver sa place sur un autre écran
Statut: Complete
Priorité: P1
Tâches: 4/4 (100%)
Tests: 1551/1551 (100%)

Correction demandée le 2026-10-15 après diagnostic de l'ouverture d'iTerm2 à 12 h 19.
Deux placements ont échoué, puis le budget a bloqué la reprise pendant trois minutes.
T3 avait déjà été réduit sur l'écran externe, tandis que le terminal restait sur l'interne.

## Acceptation

- Une fenêtre encore illisible par l'accessibilité ne doit pas faire réduire ses voisines
  sur l'écran cible. Le rattachement et l'arbre restent conservés.
- Dès que la fenêtre devient lisible, le maintien ordinaire applique le placement,
  sans changement d'application, de stage ni intervention de l'utilisateur.
- La limite de deux écritures AX par fenêtre et par génération reste effective.
  L'attente ne produit ni écritures répétées ni faux événements d'acceptation.
- Seul le groupe concerné attend. L'autre écran reste géré normalement.
- Fermeture, changement de groupe, geste manuel et plein écran conservent leurs protections.
- Tester, installer la version combinée, vérifier signature, redémarrage et santé.

## Preuves

Incident local : /private/tmp/roadie-terminal-20261015-1224
Deux `layout_failed` à 12:19:24 et 12:19:25, puis 98 acceptations
`write_budget_exhausted` jusqu'à 12:22:40. Placement réel à 12:22:42 après activation.
La cause AX initiale précise n'est pas tracée. L'absence d'entrée au registre est
cohérente avec un échec avant l'écriture AX ; ce cas doit être reproduit en test.
