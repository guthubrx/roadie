# Analyse par axe - diff 051 (commit 38f69a6a, readonly)

## Sécurité
Aucun point d'entrée réseau, aucune autorisation, aucun secret modifiés. Les changements portent sur
des caches internes et des minuteries. Semgrep : 1 règle Swift seulement.

## Logique et données
Invariants 1-7 de `contexte.md`. B-01 conserve l'écriture unique et les événements de réconciliation.
D-03 applique bien l'arbre muté. Constats F1 (R5), F3 (mesure).

## Concurrence
B-01 : lecture sans verrou sur écriture atomique par `rename` ; transaction sous `flock` avec
comparaison de l'état ; un seul écrivain en pratique. A-04 : cache sous `OSAllocatedUnfairLock`.
A-02 : `AXWindowIndexCache` sous `NSLock`, remplacement gardé par génération. A-05 : reprogrammation
sur MainActor depuis le tick.

## Complexité et performance
| Fonction | Complexité | Borne |
|---|---|---|
| `covers`, `reusableIndex` | O(k) | k fenêtres demandées d'une application |
| bundle par PID | O(1) par fenêtre | - |
| `generatedRulesPath` | O(1) | dictionnaire borné par les chemins de config |
| `timerInterval` | O(1) | - |
| B-01 | une réconciliation + comparaison O(taille de l'état) | état de `stages.json` |
| `clickMayStartWindowDrag` | O(w) | fenêtres gérées des écrans actifs |
Aucune boucle imbriquée, aucun N+1. Reste par clic : F1. Aucune mesure publiée (F3).

## Tests
Tests utiles pour B-01 (vrai `flock`) et D-03 (comptage des relevés). Fonctions pures pour A-02,
A-05, C-05 ; A-04 ne prouve que l'égalité ; A-03 et l'exclusion des captures C-06 non testées ;
D-03 ne vérifie pas les cadres appliqués ; `warp` non testé. Mutations B-01 et D-03 rapportées
(validation.md), non rejouées. Pas de linter.

## Architecture
Aucune dépendance de module ajoutée. `ConfigReloadService` importe `os` (déjà utilisé ailleurs).
Accesseurs ajoutés à `RailPanel` (`isRailCollapsed`, `onRevealed`). Pas de cycle.

## Minimalisme et frugalité
Checklist : `handleMouseDownOutsideTitleBands` répète deux lignes de `handleMouseDown`
(~2 lignes, gardées pour la lisibilité) ; `isRailCollapsed` est un accesseur d'un état privé
(nécessaire) ; aucun état dérivé redondant ; aucune abstraction prématurée ; aucune dépendance ;
aucun changement hors périmètre. Potentiel minimalisme : ~2 lignes (méthode : relecture du diff source).

## Vertus LLM et responsabilité future
Changements petits, commentés par identifiant de constat, réversibles un par un. Revue externe
documentée (Claude Haiku, APPROVE_WITH_CHANGES) ; limites écrites. Points faibles : R5 annoncée
comme atteinte alors que la session de geste relève encore (F1) ; mesure absente (F3) ; test A-04 qui
ne prouve pas la mémoire. Cet audit n'est pas indépendant.

## Observabilité
Aucun journal ajouté. Journal existant `window_gesture_target` écrit à chaque clic (F1). Pas de
compteur des réutilisations d'index AX ni des relevés évités.
