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

## D-02

Laissé en l'état par décision de l'utilisateur du 18 octobre. Recommandation dans `research.md`.
