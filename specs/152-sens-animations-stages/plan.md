# Plan152

Cause : FrameTransitionRuntime impose dx−40 à la sortie et dx+40 à une entrée hors écran. Si le pixel de parking est encore onScreen, il interpole directement du parking droit jusqu'à la cible. Les logs réels du3novembre08:58UTC montrent des trajets x5351→1662 pour stage.switch.

Réutiliser le pipeline CommandPlacement → SnapshotService.apply → FrameTransitionRuntime, sans nouvel écrivain ni nouveau minuteur. Ajouter un contexte directionnel optionnel limité à cette commande. Déduire la direction dans StageCommandService, dans la transaction de bascule, depuis l'ordre persistant des stages. Passer explicitement next/prev pour garder le sens au bouclage. Une valeur Direction représente le déplacement des fenêtres : up pour prev, down pour next.

Dans le runtime : sortie courte dans la direction ; entrée depuis la cible décalée dans le sens inverse. Reconnaître le parking même si isOnScreen=true. Hors navigation, garder le comportement de déplacement ordinaire et une arrivée courte à droite quand aucune direction n'est connue. Ne jamais afficher une fenêtre déjà parkée pour une sortie. Les nouvelles fenêtres à placement direct restent directes. Effets désactivés : même écriture finale qu'avant.

Pas d'AX supplémentaire, ni de lecture par frame ajoutée. Complexité inchangée O(k) pour k fenêtres et O(s) pour les positions de stages, une fois par commande. Réutiliser Direction, les permis et l'ordonnanceur existants. Pas de dépendance. Revue indépendante sur le commit publié, puis tests Swift séquentiels et essai sur le Mac signé.

Complément de revue : transmettre les écrans du relevé de commande au runtime pour rendre la reconnaissance du parking indépendante du cache de geste. Aucun état persistant ajouté. Les appels sans relevé explicite peuvent lire NSScreen via le fournisseur existant, sans inventaire AX.

## Capture transitoire autorisée le 3 novembre
Les essais natifs montrent que macOS bloque les fenêtres au bord supérieur. L'utilisateur accepte une image pendant la courte animation, si le délai et la charge restent faibles. Capturer la scène du scope avant le placement, appliquer une seule fois le plan final avec le dispatcher existant, puis capturer la scène cible. Animer les deux images dans des couches GPU avec la politique Motion existante. Les vraies fenêtres restent déjà à leur place finale. Le panneau ne prend ni focus ni clic. Les fenêtres stationnaires ont des trous dans le masque.

Préparation source bornée à 40 ms, attente du placement et de la cible bornée à 200 ms. Dépassement, absence de permission ou métadonnées froides : bascule directe, jamais de file de captures. Deux images de 2 millions de pixels maximum, libérées à la fermeture. Aucun disque ni capture par image. Une génération périmée ne peut afficher ni appliquer une ancienne scène. Mesurer les captures, la durée totale et les enchaînements natifs avant conclusion.
