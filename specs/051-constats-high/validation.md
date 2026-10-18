# Validation - 051 Constats HIGH restants

Date : 18 octobre 2026. Branche : session-051-constats-high, au-dessus de la 048.

## Tests

- Rouge : compilation des tests en échec avant code (module RoadieAX : `reusableIndex` absent).
- Mutation B-01 (transaction toujours prise) et D-03 (sans `using:`) : 2 échecs ; code restauré.
- Suite complète : 1 731 tests / 205 suites, verts.

## Revue

Claude Haiku 5.5 via Bridget (Codex non routable). APPROVE_WITH_CHANGES.

| Objection | Vérifiée comment | Retenue | Suite |
|---|---|---|---|
| `mesures/apres.json` vide | Mesure en attente d'inactivité | Oui | Exclu du commit ; mesure finale après intégration |
| C-06 : vignettes lentes au dépliage | Budget du minuteur : 1 capture/s | Oui | `RailPanel.onRevealed` → rafraîchissement « reveal » (8 captures), test |
| D-03 : seul `move` testé | Lecture | Oui | Test `resize` ajouté |
| A-04 : test décoratif | Lecture | Oui | Assertion remplacée ; gain attesté par l'échantillon du 15/10 (35 éch./10 s) |
| C-05 : cadres d'un cycle ancien | Cadres mis à jour à chaque rendu du rail (≤ 1 s) | Limite | Aperçu de dépôt Roadie possible manqué si la fenêtre a bougé < 1 s avant ; déplacement natif inchangé |
| A-02 : index sans validation des éléments | Observateur AX actif en mode `run` ; repli `lastKnown` | Limite | Processus lecteurs autonomes : index possiblement ancien |
| A-05 : 1 s avant la première réaction après activation à chaud | Par construction | Limite | Documenté |
| Preuves visuelles | Aucun changement d'affichage voulu | - | Non produites ; bureau non capturé |

## Audit V15

Session : `audits/2026-10-18/session-2026-10-18-051-v15-constats-high-01/` (readonly, worktree
figé sur 38f69a6a). Décision calculée : **inconclusive**, `release_blocked = true`. Cause unique :
l'exécuteur refuse des arguments pour l'analyse de l'historique ; l'analyse ciblée v0.4.0..38f69a6a
(option A, décision utilisateur du 18 octobre) a tourné comme contrôle personnalisé, sans fuite,
mais le moteur compte `gitleaks-history` comme non exécuté. 14 contrôles vérifiés.
Constats : MEDIUM R5 (session de geste A-11 hors périmètre, R5 réécrite) ; LOW menu clic droit
(C-09, hors périmètre) ; LOW mesure non publiée (faite après intégration).

## D-02

Laissé en l'état par décision de l'utilisateur du 18 octobre. Recommandation dans `research.md`.

## Mesure

`mesures/apres.json` : 2,36 % d'un cœur au repos (2,34 % après la 048), contaminée par une
compilation d'audit concomitante. La mesure propre sur la version intégrée n'a pas pu être prise :
la machine n'est pas restée inactive. L'utilisateur a accepté ce manque le 18 octobre. Aucun gain
au repos n'est revendiqué pour la 051 ; ses gains vérifiés sont par test : un relevé par commande
en arbre au lieu de deux, aucun verrou d'état sans changement.

## Installation

Version intégrée installée : UUID 7FAEFA94-B08E-3C14-B9B4-852B532C97E3, puis relance à la demande
de l'utilisateur (PID 5718). Cinq contrôles santé OK. Écran externe débranché : rail sur l'écran
intégré seul (13 stages). Capture d'écran refusée par macOS : affichage non vérifié visuellement.
