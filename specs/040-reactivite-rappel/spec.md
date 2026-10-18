# Session 040 — Réactivité du rail et rappel des fenêtres

Correction autorisée le 18 octobre 2026. Revue indépendante autorisée.

## Résultats attendus
- Les écritures sans rapport avec un enregistrement ne reconstruisent plus le rail.
- Le rappel d'un stage essaie une autre fenêtre quand la cible préférée est introuvable ; les fermetures confirmées restent exclues.
- Une fenêtre réduite peut être restaurée par le rappel ; le plein écran natif conserve son comportement.
- Les autres échecs de placement et délais sont classés par cause avant toute correction.

## Vérification
Tests reproductibles avant/après, suite complète isolée, installation signée et santé réelle. Parcours visuel si l'accès écran fonctionne ; sinon limite explicite. Aucun changement de configuration ou de stages utilisateur pour masquer un défaut.
