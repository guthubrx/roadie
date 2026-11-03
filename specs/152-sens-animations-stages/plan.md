# Plan152

Cause : FrameTransitionRuntime impose dx−40 à la sortie et dx+40 à une entrée hors écran. Si le pixel de parking est encore onScreen, il interpole directement du parking droit jusqu'à la cible. Les logs réels du3novembre08:58UTC montrent des trajets x5351→1662 pour stage.switch.

Réutiliser le pipeline CommandPlacement → SnapshotService.apply → FrameTransitionRuntime, sans nouvel écrivain ni nouveau minuteur. Ajouter un contexte directionnel optionnel limité à cette commande. Déduire la direction dans StageCommandService, dans la transaction de bascule, depuis l'ordre persistant des stages. Passer explicitement next/prev pour garder le sens au bouclage. Une valeur Direction représente le déplacement des fenêtres : up pour prev, down pour next.

Dans le runtime : sortie courte dans la direction ; entrée depuis la cible décalée dans le sens inverse. Reconnaître le parking même si isOnScreen=true. Hors navigation, garder le comportement de déplacement ordinaire et une arrivée courte à droite quand aucune direction n'est connue. Ne jamais afficher une fenêtre déjà parkée pour une sortie. Les nouvelles fenêtres à placement direct restent directes. Effets désactivés : même écriture finale qu'avant.

Pas d'AX supplémentaire, ni de lecture par frame ajoutée. Complexité inchangée O(k) pour k fenêtres et O(s) pour les positions de stages, une fois par commande. Réutiliser Direction, les permis et l'ordonnanceur existants. Pas de dépendance. Revue indépendante sur le commit publié, puis tests Swift séquentiels et essai sur le Mac signé.

Complément de revue : transmettre les écrans du relevé de commande au runtime pour rendre la reconnaissance du parking indépendante du cache de geste. Aucun état persistant ajouté. Les appels sans relevé explicite peuvent lire NSScreen via le fournisseur existant, sans inventaire AX.
