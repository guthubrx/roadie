# Fluidité par les bords natifs — proposition

31 octobre 2026. Roadie étudié : b223718ff9bedc101035cfd5fb0edc0d8704763f.

Le geste visé reste le redimensionnement normal par un bord ou un coin. Aucun geste supplémentaire ni poignée Roadie n’est requis.

## Diagnostic vérifié

- Le scheduler est bloqué pendant l’appui. Son câblage de production utilise `UserInputActivity.blocksLayout`.
- Le maintainer retourne aussi sans plan dès qu’un bouton est enfoncé.
- `UserInputActivity.mouseDragged` marque seulement le premier mouvement. Il ne fournit pas actuellement un flux de géométrie pour un redimensionnement interactif.
- Au relâchement, `LayoutMaintainer.applyGesture` compare la taille initiale et la taille observée. Il sait ajuster les frontières BSP et enregistrer les nouvelles proportions.
- L’observateur AX lit le cadre dans son callback sur le fil principal. Le coût de cette lecture pendant un geste reste à mesurer.
- La limitation des poignées à 20 passes/s, identifiée dans l’autre note, ne décrit pas ce chemin natif : celui-ci attend actuellement la fin du geste.

Sources locales :

- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/roadied/main.swift:423
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/TickScheduler.swift:149
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/LayoutMaintainer.swift:423
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/LayoutMaintainer.swift:1573
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/FocusFollowsMouseController.swift:201
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieAX/AXWindowEventObserver.swift:148

## Architecture proposée

1. Au clic, mémoriser identité, stage, arbre, cadre initial et position. Confirmer le resize par une variation de taille, pas par le seul mouvement du pointeur. Conserver les axes/bords cohérents avec les cadres observés. Distinguer déplacement de fenêtre, clic de contenu et redimensionnement.
2. Pendant le geste natif, macOS et l’application restent propriétaires du cadre de la fenêtre saisie. Le chemin interactif ne lui écrit pas. La disposition ordinaire ne remet pas son ancien cadre.
3. Observer le cadre réel de la cible avec des lectures regroupées et bornées, hors fil principal. Les notifications servent de signal, sans supposer qu’elles sont exhaustives ou à chaque image. Une lecture de secours ciblée peut être évaluée pendant la session ; aucun inventaire complet par mouvement. Ne pas calculer uniquement depuis le curseur : une application peut imposer une taille différente.
4. Calculer un arbre provisoire depuis une base stable, avec les séparations contrôlées et leurs chemins mémorisés. Éviter une recherche répétée dans tout l’arbre. `adjustingFence` donne une base fonctionnelle mais sa complexité peut être quadratique dans le pire cas : ne pas simplement l’appeler à chaque pixel sans étude. Le calcul des cadres peut rester linéaire dans le nombre de fenêtres concernées.
5. Envoyer seulement les cadres modifiés des voisines. Réutiliser le point d’écriture commun avec une session et des générations. Aucun second écrivain indépendant. Une cible en attente par fenêtre, remplacée par la plus récente. Un travail AX par application évite qu’une application lente retienne les autres. Ne pas lancer de nouvel appel tant que la ressource correspondante est occupée. Un appel déjà engagé n’est pas supposé annulable.
6. Coordonner la publication avec le rythme utile de l’écran via CADisplayLink. Le callback d’affichage ne doit pas contenir d’appel AX bloquant. 60 ou 120 Hz est une cadence d’ordonnancement éventuelle, pas une garantie d’acceptation des tailles par les applications. Arrêter cette activité hors geste.
7. Au relâchement, attendre une observation finale bornée, réconcilier les cadres acceptés et les contraintes, puis enregistrer l’arbre. Une notification finale peut arriver après le mouseUp. Écarter les résultats anciens. Sur interruption, préserver les tailles réellement observées et reprendre une disposition cohérente. Un changement de stage/écran, une fermeture ou une configuration nouvelle invalide la session.

Le BSP est le premier périmètre conseillé. Les modes de colonnes et master/stack doivent utiliser leur propre règle d’adaptation des largeurs, via une interface interactive commune. Ce choix est une proposition, pas une réduction silencieuse d’un futur périmètre validé.

Ne pas retirer globalement la garde des boutons dans le scheduler : les glissers de contenu et les déplacements doivent conserver leur protection. Le changement consiste à autoriser une voie limitée aux voisines d’un resize natif confirmé.

## Mesures et critères proposés

- Délai entre un nouveau cadre observé de la cible et le cadre visible des voisines, avec p50/p95.
- Délai pointeur→fenêtre saisie, pour distinguer le coût de l’application du coût de Roadie.
- Durées d’attente et d’exécution AX par application, âge des cibles appliquées, nombre de cibles remplacées.
- Temps du fil principal, coût du calcul, consommation pendant le geste et au repos.
- Cible provisoire : voisines à moins de deux rafraîchissements sur applications réactives. À 60 Hz cela représente environ 33 ms ; à 120 Hz environ 17 ms. Rien de mesuré à ce stade.
- Validation native aux bords et coins, dans les deux sens, avec minima, fenêtres à taille imposée, applications lentes, plusieurs écrans et changements de contexte. Aucun bras de fer, oscillation, accumulation ou retour à une ancienne taille.

Si la fenêtre manipulée saccade elle-même, il faut mesurer la charge qu’elle subit et ses réponses AX. Le suivi des voisines ne peut pas garantir de rendre rapide une application dont le propre rendu est lent.

Documentation Apple vérifiée :
- https://developer.apple.com/documentation/appkit/nsscreen/displaylink(target:selector:) — callback synchronisé sur l’écran.
- https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:) — observation asynchrone des événements ; le moniteur ne les modifie pas.

## État

Proposition et démonstrateur pédagogique uniquement. Aucun changement des sources de production, aucun test natif ni benchmark exécuté. L’implémentation devra passer par la session SpecKit validée.
