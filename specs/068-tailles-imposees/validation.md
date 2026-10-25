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
