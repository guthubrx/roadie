# Session 043 — Redimensionnement fiable

Statut : validée par l’utilisateur le 2026-10-18 (« fais les 3 P1 à l’aide de sous agents T3 »).
Branche : session-043-redimensionnement-fiable. Tests : à déterminer.

## Objectif
Livrer les trois P1 du comparatif : poignées de séparation explicites, historique court des cadres attendus, refus de taille et gestes concurrents fiables. Préserver les gestes natifs, les budgets de placement, le plein écran natif, les groupes et le multi-écran.

## Exigences
- FR-001 Afficher des poignées discrètes sur les séparations réellement actives de spatialBsp, sur chaque écran. Les surfaces ne capturent que la séparation ; pas les applications voisines. Aucun contrôle pour une seule fenêtre, un écran absent ou une disposition non compatible.
- FR-002 Un glisser désigne une séparation stable. Modifier seulement son ratio avec les contraintes minimales existantes ; appliquer et persister le résultat. La fin du geste, sa perte, un changement de stage/topologie ou l’arrêt libèrent toujours la session. Conserver le redimensionnement natif.
- FR-003 Prévoir un interrupteur immédiat dans Tuilage pour les poignées. Pas de nouveau framework, pas de dépendance.
- FR-004 Garder un historique borné par fenêtre des cadres récemment demandés/observés/acceptés. Durée initiale 1,5 s, au plus 32 cadres. Reconnaître un retour ancien de A après B sans transformer ce retour en nouveau geste. Purger à oubli/destruction ; ne pas étendre une génération ou ses budgets.
- FR-005 Un geste utilisateur réel reste prioritaire. Ne pas absorber aveuglément un événement de géométrie pendant un appui souris. Le nouvel historique ne confirme pas un refus d’une autre génération.
- FR-006 Les refus confirmés ajustent les contraintes sans boucle de corrections. Un refus ancien ne remplace pas une intention de souris plus récente. Conserver la confirmation par seconde observation, le budget par génération et les minimums existants ; corriger uniquement les causes démontrées par les tests.
- FR-007 Tester deux puis quatre fenêtres, retour AX retardé/désordonné, limites de taille, geste concurrent, fin/annulation de glisser et multi-écran. Ne pas effectuer de benchmark sur la machine chargée.

## Exclusions
Pas de caméra, onglets, nouvel ordonnanceur AX, captures animées ni aperçu fantôme général (P2/P3). Les mécanismes sont réimplémentés à partir des besoins Roadie et de son modèle ; pas de code Trellis incorporé.

## Acceptation
La séparation reste à la position choisie après relâchement/relecture. Une application imposant un minimum ne provoque pas de va-et-vient permanent. Un ancien écho ne rétablit pas une taille passée. Les autres modes fonctionnent comme avant. Les paramètres enregistrent leur vraie clé et s’appliquent immédiatement.

