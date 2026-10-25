# Validation 071

- `Spec071LivePreviewTests` : aperçu des bureaux (renumérotation, autre écran), des
  stages et fenêtres vers de nouveaux contenants, zone sous le dernier bureau, centrage.
- Tests 061, 066, 067 et 070 adaptés (géométrie de référence centrée, rappel `onDrop`).
- Rendus natifs vérifiés sur données fictives après animation : stage déplacée, fenêtre
  vers un nouveau bureau, bureaux réordonnés, fenêtre vers une nouvelle stage ; sonde
  retirée ensuite.
- Suite complète : 1 959 tests / 249 suites réussis.

## Correction après essai utilisateur
Les fenêtres glissées sur une autre stage créaient une nouvelle stage (événements
`stage_assign_window` vers les stages 8 et 9 à 10:48, 10:49 et 11:06). Cause : la place
visée se calculait sur la disposition d'avant le geste ; l'aperçu déplaçait la carte
visée et le pointeur tombait sur une zone vide de l'ancienne disposition. Correction :
viser la disposition affichée ; sur un fantôme, l'intention en cours est gardée ; le
relâchement applique l'intention de l'aperçu affiché. Test de régression
`droppingOnTheGhostKeepsTheTargetStage` (échoue avec l'ancien calcul : l'endroit n'est
sur aucune carte de la disposition initiale). Suite complète : 1 960 tests / 249 suites.
Installé : PID 8610, santé 5/5.
