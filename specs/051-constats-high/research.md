# Recherche - 051

Statut des constats relu le 18 octobre sur le code actuel (agent d'exploration, lecture seule) :
C-04 résolu par la session 040 ; A-01, A-05, C-02, C-03, C-06 partiels ; A-02, A-03, A-04,
B-01, C-05, D-02, D-03 ouverts. A-01, C-01, C-02, C-03 traités par la 048.

## Décisions

- A-02 : la réutilisation n'a lieu que si l'index couvre toutes les fenêtres CG demandées pour
  l'application. Une fenêtre nouvelle force l'énumération ; une fenêtre fermée quitte la liste CG.
  L'écrivain invalide déjà l'index sur création, destruction ou élément invalide.
- B-01 : la réconciliation peut émettre un événement (`focus.hidden_cross_display_after_missing_suppressed`).
  La transaction réutilise donc le résultat déjà calculé si l'état lu n'a pas changé, pour ne pas
  réconcilier deux fois.
- C-05 : bande de 44 points, comme `DropPreviewController.dragSourceWindow`, marge de 4 points.
  Les cadres viennent du dernier cycle du rail (au plus 1 s, mis à jour à chaque rendu).
- D-03 : seules les commandes en arbre (move, warp, resize). Le placement et l'affectation gardent
  leurs relevés : les réutiliser demande une réconciliation sans relevé, risque moyen.

## D-02 : recommandation, non appliquée

Les commandes routées s'exécutent entièrement sur le fil principal (`CommandSocketServer`,
`DispatchQueue.main.sync`). L'ADR 013 écarte explicitement leur déplacement. Le déplacer change
l'architecture (contrat synchrone des commandes, ordre des écritures AX). Décision utilisateur
requise. Étape intermédiaire possible sans changer d'architecture : servir `query` et
`state dump` par l'acquisition asynchrone des lecteurs (ADR 013).
