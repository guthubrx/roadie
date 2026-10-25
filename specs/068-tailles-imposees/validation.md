# Validation 068

- Diagnostic sur les événements réels : `layout_app_response_accepted` répété pour la
  fenêtre 20684 (requested 150,30 1650x1087, actual 150,30 471x1086) à chaque
  `command:stage.switch` et changement de fenêtre active, de 08:50:37 à 08:51:59.
- `Spec068LastingRefusalTests` : refus durable après deux générations, relance sur autre
  cible ou autre cadre, effacement après écriture acceptée, recomptage sur autre réponse.
- Suite complète : 1 950 tests / 246 suites réussis.
- Installé : PID 59101, santé 5/5, signature roadied-cert conservée.
- Après un redémarrage, la mémoire est vide : la fenêtre peut encore changer de taille
  au plus deux fois avant que le refus soit retenu.

## Complément après publication (25 octobre 2026, 10:30)
L'oscillation continuait, toutes les 2 à 3 s, sans action de l'utilisateur. Cause :
l'émulateur accepte d'abord la taille écrite (relue 1362 × 942), puis revient de
lui-même à 407 × 942 environ une seconde plus tard ; son redimensionnement relance une
passe. `record` effaçait le refus durable dès une relecture conforme, il ne s'accumulait
donc jamais. Correction : seule une réponse qui garde la cible (`accept`) l'efface.
Tests Spec068 : 4 réussis. Installé (PID 28771) : deux sauts après le redémarrage
(10:33:49, 10:33:51), puis aucun ; fenêtre stable à 407 × 942, santé 5/5.
